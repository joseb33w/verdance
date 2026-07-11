extends Node3D
## RPG STREAMING TEMPLATE — orchestration. Fetches a FETCHABLE world.json + quests.json
## (loose files served next to index.html, NOT packed in the .pck) + the asset manifest,
## wires the streaming systems, and keeps the player / combat / HUD PERSISTENT across area
## transitions. Areas + their .glb stream from R2 at runtime.
##
## EDITS COME FROM THE CHAT, not in-game: a chat edit is validated by qgcheck server-side
## and the new world.json is written back to R2. This template POLLS world.json and
## hot-reloads the live area when it changes (no re-export), so an open preview updates live.
##
## CHUNK MODE: when world.mode=="chunk" the one-resident ZONE streamer (SceneManager) is replaced
## by ChunkManager (resident 3x3 ring around the player). All chunk wiring is ADDITIVE + guarded
## by chunk_mode, so a non-chunk world behaves exactly as before.

const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4

# Default drivable-car model when a world-level "vehicles" entry omits "model" (resolved via _norm).
const VEHICLE_MODEL := "props/kk_city/car_sedan.glb"

# Third-person orbit camera (SpringArm rig) — see _build_player/_process/_input.
const CAM_DIST := 8.5
const CAM_HEAD := 1.5
const CAM_PITCH_MIN := -1.30
const CAM_PITCH_MAX := 0.6     # Wave 2: was -0.18 — raised (~+34°) so the player can look ABOVE the
                               # horizon. The SpringArm still pulls the cam off the ground on the way up.
const LOOK_SENS := 0.006

# Wave 2 (FEEL): canonical vertical motion + swim. GRAVITY applies ONLY while airborne — a floor snap
# hugs descents so the player never hovers off a ledge; together they restore the full default 45°
# climbable slope (stairs ~35° and river banks ~41° become walkable). SWIM floats the body at the
# water surface (head/shoulders above, always visible) when the water is deeper than a wade.
const GRAVITY := 22.0
const STEP_MAX := 1.2             # step-up assist lifts onto a lip no higher than this (else = a wall)
const JUMP_SPEED := 8.5           # jump launch velocity — apex ~1.6m at GRAVITY 22 (v = sqrt(2*g*h))
const SWIM_SPEED := 3.5
const SWIM_SURFACE_OFF := 1.1     # feet ride this far below the surface so the body sits IN the water (chest-deep, head+shoulders above). 0.4 pinned the FEET just under the surface -> the whole 1.7m body floated ON TOP ("walks then floats")
const WADE_DEPTH := 0.6           # water this much above the ground -> swim. MUST stay below a typical water.level (~1.0): the old 1.1 needed the seabed below -0.1, so ~95% of a shallow noise-lake never triggered swim ("can't swim in water")
const CLIMB_SPEED := 3.0          # CONTRACT C: ladder ascent/descent speed along Y

# Wave 4 ranged fire: auto-aim cone APEX angle (i.e. ±15° of the character's facing) and the
# muzzle's forward offset from the GEquipSlot (approximates the weapon tip for flash + spawn).
const FIRE_CONE_DEG := 30.0
const MUZZLE_FWD := 0.4

# Wave 1.5 native hero_model: the placeholder capsule mesh is 1.6 tall centred at y=0.85, so its
# top sits ~1.65 m — a fetched hero avatar scales to that height before its feet are seated at y=0.
const HERO_HEIGHT := 1.65

var origin := "https://preview.myapping.com"
var world_url := "https://preview.myapping.com/world.json"   # overridden from window.location on web
var build_id := ""
var props_pool: Array = []

var world_data := {}
var quests_data := {}
var _world_raw := ""          # last raw world.json text (change-detect for the poll)
var _polling := false

var env: Environment
var sun: DirectionalLight3D
var player: CharacterBody3D
var _capsule_body: MeshInstance3D = null   # placeholder capsule mesh — hidden when a native hero_model attaches
var cam: Camera3D
var cam_rig: Node3D
var cam_spring: SpringArm3D
var cam_yaw := 0.0
var cam_pitch := -0.55
var look_idx := -1
var look_last := Vector2.ZERO
var swing_t := 0.0                 # melee swing window (visual + re-tap gate) — decays in _process
# Wave 4 equipped-weapon state. GEquip owns the attached visual; main tracks the "GEquipSlot"
# node it hangs on the player (the swing pivot AND the ranged muzzle origin) and keeps the
# visual in sync with rpg.equipped_weapon (_sync_equip_visual).
var weapon_slot: Node3D = null     # the GEquipSlot on the player (BoneAttachment3D or fixed offset)
var _equipped_visual_id := ""      # weapon id the attached visual represents (sync guard)
var _equip_busy := false           # _sync_equip_visual re-entrancy latch (its model fetch awaits)
var _fire_cd := 0.0                # ranged/thrown cooldown (1.0 / def rate) — decays in _process
var _weapon_stowed := false        # Wave 1.5: weapon visual hidden while DRIVING A VEHICLE (kept on mounts)
var _jump_queued := false           # a JUMP press (Space / HUD button) waiting to be consumed on the floor
var _weapon_btn: Button = null     # HUD draw/holster toggle (updates its own DRAW/SHEATHE label)
var _hero_ap: AnimationPlayer = null   # the hero avatar's AnimationPlayer (retargeted OR embedded clips)
var _hero_anim := ""                    # current semantic anim kind (idle/walk/run/attack)
var _hero_attack_t := 0.0               # remaining melee-attack-clip hold (s)
var _hero_avatar: Node3D = null         # the attached hero GLB — hidden when the camera collapses onto it

var rpg: RpgState
var director: VerdanceDirector
var builder: AreaBuilder
var interaction: InteractionSystem
var scene_manager: SceneManager
var quest: QuestSystem
var weather: Weather3D

# --- chunk-mode resident-ring streaming (behind world.mode=="chunk") ---
var chunk_manager: ChunkManager
var chunk_mode := false

# --- drivable vehicles (world-level "vehicles", vehicle.gd) — PERSISTENT, never cell-parented ---
var vehicle_root: Node3D = null   # persistent layer: chunk eviction / zone transitions never touch it
var vehicles: Array = []          # live Vehicle nodes
var active_vehicle: Vehicle = null   # the car being driven (input routed here; null = on foot)
var _vehicles_spec: Array = []    # snapshot of world "vehicles" for the hot-reload diff
var auto_roam := false          # ?soak=1 -> player auto-roams so peak memory can be measured headlessly
var _roam_t := 0.0
var _js_set_time_cb = null      # window.gogiSetTime callback (web) — held so JavaScriptBridge doesn't GC it
var _js_get_player_cb = null    # window.gogiGetPlayer callback (web, verify) — held so it isn't GC'd
var _js_solids_cb = null        # window.gogiSolids callback (web, verify) — held so it isn't GC'd

var move_idx := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO

# Wave 2 FEEL state.
var swimming := false          # true while the player floats in deep water (see _chunk_physics)
var climbing = null            # CONTRACT C ladder state Dictionary {pos, base_y, top_y, facing}; null = off-ladder

var hud_layer: CanvasLayer
var stats: Label
var hp_bar: ColorRect
var _hud_btns: Dictionary = {}   # name -> Button, repositioned by _relayout_ui on resize
var _dismount_btn: Button = null   # contextual GET-OFF button: hidden on foot, shown while driving/riding


func _ready() -> void:
	# RESPONSIVE FULL-SCREEN FILL: force expand at runtime (first-frame web canvas race) and
	# relayout the HUD against the LIVE viewport on every resize/rotation.
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.size_changed.connect(_relayout_ui)
	_fit_ui_scale()
	if OS.has_feature("web"):
		var o = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(o) == TYPE_STRING and String(o) != "":
			origin = String(o)
		var dir = JavaScriptBridge.eval("window.location.href.replace(/[^/]*$/, '')", true)
		if typeof(dir) == TYPE_STRING and String(dir) != "":
			world_url = String(dir) + "world.json"
		# Build id = the first path segment ONLY when it actually looks like one (cloud-*/news-cloud-*).
		# Serving from a bare root (localhost verify, custom domain) otherwise captured "index.html"
		# as the build id and the self-heal re-rooted every asset onto a bogus /index.html/… path.
		var bid = JavaScriptBridge.eval("(function(){var s=location.pathname.split('/').filter(Boolean)[0]||'';return /^(news-)?cloud-/.test(s)?s:'';})()", true)
		if typeof(bid) == TYPE_STRING and String(bid) != "":
			build_id = String(bid)
		var soak = JavaScriptBridge.eval("window.location.search.indexOf('soak=1')>=0", true)
		if typeof(soak) == TYPE_BOOL and soak:
			auto_roam = true

	_build_env()
	_build_player()
	# Prompt-driven sky + weather owns the env/sun from here; defaults to clear day
	# until world.json's "sky" block is read in _boot. (See _apply_weather.)
	weather = Weather3D.new()
	add_child(weather)
	weather.setup(env, sun, cam_rig)
	_setup_web_time_hooks()   # window.gogiSetTime / gogiGetTime (web only) — needs `weather` to exist
	_build_hud()
	AudioManager.show_tap_overlay()   # web: gesture-gate so audio unlocks (autoplay policy) + a loading veil

	rpg = RpgState.new()
	add_child(rpg)
	rpg.changed.connect(_update_stats)
	rpg.changed.connect(_on_rpg_changed)   # Wave 4: chest auto-equip -> swap the weapon visual

	builder = AreaBuilder.new()
	builder.origin = origin
	builder.world_url = world_url   # lets _region_base_dir() resolve region_*.json next to world.json
	builder.env = env
	add_child(builder)

	interaction = InteractionSystem.new()
	add_child(interaction)

	scene_manager = SceneManager.new()
	add_child(scene_manager)

	quest = QuestSystem.new()
	add_child(quest)
	quest.setup(rpg)
	quest.objective_changed.connect(_update_stats)

	interaction.setup(player, rpg, scene_manager, quest, hud_layer)
	interaction.main_ref = self   # Wave 3: _nearest reads active_vehicle so seats are gated while driving/riding
	scene_manager.setup(player, builder, interaction, self, hud_layer)
	scene_manager.area_entered.connect(quest.notify_area)   # reach_area objectives progress on arrival

	chunk_manager = ChunkManager.new()
	add_child(chunk_manager)
	chunk_manager.setup(player, builder, self, env, interaction, rpg)
	chunk_manager.area_entered.connect(quest.notify_area)   # chunk-mode reach_area parity (only the active streamer emits)

	# poll world.json so a chat edit (qgcheck-gated, written to R2) hot-reloads live
	var poll := Timer.new()
	poll.wait_time = 4.0
	poll.autostart = true
	poll.timeout.connect(_poll_world)
	add_child(poll)

	# Wave 4: attach the default melee weapon NOW (parametric — no fetch), replacing the old
	# hardcoded sword MeshInstance, so the player isn't bare-handed while world.json streams.
	# _boot re-syncs if "start_weapon" names something else.
	_sync_equip_visual()

	# VERDANCE director: title screen (mode select), regions/weather, beacons, taming/stable,
	# campaign chain, persistence. Owns input gating until a mode is chosen.
	director = VerdanceDirector.new()
	add_child(director)
	director.setup(self)

	_update_stats()
	await get_tree().process_frame
	await get_tree().process_frame
	_relayout_ui()   # the web canvas size is NOT final on the first frame
	_boot()


func _boot() -> void:
	# manifest -> props pool (best effort)
	var man := HTTPRequest.new()
	add_child(man)
	man.request(origin + "/godot-assets/manifest.json")
	var mr = await man.request_completed
	man.queue_free()
	if mr[1] == 200:
		_parse_manifest(mr[3])
	builder.props_pool = props_pool

	# world.json (required) — a loose file served next to index.html
	var wq := HTTPRequest.new()
	add_child(wq)
	wq.request(world_url)
	var wr = await wq.request_completed
	wq.queue_free()
	if wr[1] != 200:
		stats.text = "world.json fetch failed (HTTP %s) @ %s" % [str(wr[1]), world_url]
		return
	var raw := (wr[3] as PackedByteArray).get_string_from_utf8()
	var world = JSON.parse_string(raw)
	if not (world is Dictionary):
		stats.text = "world.json parse error"
		return
	world_data = world
	_world_raw = raw
	_apply_weather(world)
	rpg.load_weapons(world.get("weapons", {}))   # Wave 4: world "weapons" merge over inline ITEMS

	# quests.json (fetched alongside world.json — the same data qgcheck validates)
	var qq := HTTPRequest.new()
	add_child(qq)
	qq.request(world_url.replace("world.json", "quests.json"))
	var qr = await qq.request_completed
	qq.queue_free()
	if qr[1] == 200:
		var qdata = JSON.parse_string((qr[3] as PackedByteArray).get_string_from_utf8())
		if qdata is Dictionary:
			quests_data = qdata
			quest.load_quests(qdata)
			# Quests do NOT auto-start: the VerdanceDirector starts the campaign chain when
			# (and only when) the player picks THE WARDEN'S CAMPAIGN on the title screen.

	# world-level drivable vehicles — spawned ONCE onto the persistent layer BEFORE the streamer
	# starts, so their builder._ensure can't interleave with a cell build's parallel downloads.
	await _spawn_vehicles(world)

	# Wave 4: "start_weapon" equips at spawn. Its model prefetch is SERIALIZED here (like the
	# vehicles above) so a library//BUILD_ID weapon GLB can't interleave with the streamer's
	# parallel downloads; "parametric:*" models need no fetch at all.
	var start_id := String(world.get("start_weapon", ""))
	if start_id != "":
		if not rpg.has_item(start_id):
			rpg.add_item(start_id)
		rpg.equip(start_id, true)   # force: the authored start weapon wins regardless of damage
	await _sync_equip_visual()

	# Wave 1.5: a world-level "hero_model" wears a real character over the placeholder capsule.
	# Serialized here (like the vehicles/start_weapon prefetch) so its GLB fetch can't interleave
	# with the streamer's parallel downloads.
	await _attach_hero_model()

	if String(world.get("mode", "")) == "chunk":
		chunk_mode = true
		scene_manager._fade.visible = false   # chunk mode never fades -> hide the opaque black overlay
		sun.shadow_enabled = true              # restored: the floor slab is cast_shadow=OFF (no self-acne),
		sun.shadow_normal_bias = 2.0           # so props/buildings cast real contact shadows + read as planted
		sun.directional_shadow_max_distance = 42.0   # ring is only ~24u -> tight cascade = sharper + cheaper (mobile)
		await chunk_manager.start(world)
		_wire_vehicle_terrain()   # GTerrain exists only after start() — hand it to the parked cars
		# Wave 3 spawn-clearance: vehicles spawn (line ~235) BEFORE any cell is built, so a vehicle
		# authored on top of a building can't be de-wedged at spawn time — do it now that the start
		# ring's structures exist. Pushes only a genuinely-wedged vehicle onto clear ground.
		for v in vehicles:
			if is_instance_valid(v):
				v.global_position = chunk_manager.nudge_out(v.global_position, 2.5)
		interaction.terrain = chunk_manager.terrain   # Wave 3: grounds the stand-up-from-a-seat spot
		if director != null:
			director.world_ready()   # beacons/regions/taming need terrain + vehicles
	else:
		scene_manager.start(world)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if director != null and director.input_locked():
		return   # title screen open — the world holds still behind it
	if active_vehicle != null:
		# DRIVING: feed the car the SAME input vector that walks the player (one input path, no
		# second binding). The vehicle integrates it in its own physics tick and parks the hidden
		# player on itself, so chunk streaming + reach_area quest notifications (both read
		# player.global_position) keep following the driven position.
		if not is_instance_valid(active_vehicle):
			active_vehicle = null   # freed under us (hot-reload edge) — fall through to on-foot
		else:
			# CONTRACT A: feed the vehicle a CAMERA-relative world-XZ desired heading (length =
			# throttle 0..1). The raw drive_input(Vector2) path stays intact on vehicle.gd for the
			# verify harness — we just route the on-screen drive through drive_input_world here.
			var v := _keyboard_vec() + move_vec
			if v.length() > 1.0:
				v = v.normalized()
			var d3 := Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y)
			# Untyped hop: this compiles green while vehicle.gd's drive_input_world half lands in
			# parallel (a typed Vehicle call would parse-fail until the method exists).
			var av = active_vehicle
			av.drive_input_world(Vector2(d3.x, d3.z))
			return
	# Wave 3 (sittable furniture): a SEATED player doesn't move — but movement input IS the intent
	# to leave, so it stands them up first (interaction restores the pose + places them beside the
	# seat, grounded); motion resumes next tick. This ONE gate covers BOTH the zone and chunk
	# physics paths below. The camera is untouched — the SpringArm rig follows the seated player.
	if interaction != null and interaction.player_seated:
		if (_keyboard_vec() + move_vec).length() > 0.1:
			interaction.stand_player()
		return
	if chunk_mode:
		_chunk_physics(delta)
		return
	if scene_manager == null:
		return
	if scene_manager.transitioning or scene_manager.current_root == null:
		return
	var v := _keyboard_vec() + move_vec
	if v.length() > 1.0:
		v = v.normalized()
	# Camera-relative: forward = away from the camera, rotated by the orbit yaw.
	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y)
	# Wave 2 canonical vertical motion: horizontal drive + airborne-only gravity + floor snap, so
	# descents hug the ground (no ledge hover) and the full 45° slope stays climbable (stairs/ramps).
	player.velocity.x = dir.x * 6.0
	player.velocity.z = dir.z * 6.0
	if player.is_on_floor():
		player.velocity.y = JUMP_SPEED if _jump_queued else 0.0   # launch a queued jump off the ground
	else:
		player.velocity.y -= GRAVITY * delta
	_jump_queued = false
	player.floor_snap_length = 0.0 if player.velocity.y > 0.1 else 0.8   # don't let floor-snap cancel a jump
	if dir.length() > 0.1:
		var look := player.global_position - dir
		player.look_at(Vector3(look.x, player.global_position.y, look.z), Vector3.UP)
	player.move_and_slide()
	_step_up_assist(dir)


func _chunk_physics(delta: float) -> void:
	# CONTRACT C: a ladder takes over vertical motion entirely (the ONE no-vertical-face exception).
	if climbing != null:
		_climb_physics(delta)
		return
	var v := _keyboard_vec() + move_vec
	if auto_roam and chunk_manager != null:
		_roam_t += delta
		# diagonal ping-pong across the whole grid -> the resident ring shifts + evicts repeatedly
		var rect := chunk_manager.grid_world_rect()
		var tt := fmod(_roam_t * 0.05, 2.0)
		var f := tt if tt <= 1.0 else (2.0 - tt)
		var target := Vector3(rect.position.x, 0.0, rect.position.y).lerp(
			Vector3(rect.end.x, 0.0, rect.end.y), f)
		var to := target - player.global_position
		v = Vector2(to.x, to.z)
	if v.length() > 1.0:
		v = v.normalized()
	# Camera-relative when the player drives; world-relative during the headless
	# soak roam (auto_roam computes a world-space target, cam_yaw must not rotate it).
	var dir := Vector3(v.x, 0.0, v.y) if auto_roam else Basis(Vector3.UP, cam_yaw) * Vector3(v.x, 0.0, v.y)

	# CONTRACT D: swim/wade is decided from chunk_manager's water fields (READ-only). `depth` is how
	# far the water level sits above the ground beneath the player's feet.
	var px := player.global_position.x
	var pz := player.global_position.z
	var wl := chunk_manager.water_level if (chunk_manager != null and chunk_manager.water_cfg != null) else -1e9
	var gy := chunk_manager._ground_y(px, pz) if chunk_manager != null else 0.0
	var depth := wl - gy                                 # water column above the seabed at this XZ
	var below := wl - player.global_position.y           # how far the body sits under the surface (feet-origin)
	# Engage swim when the player stands in a column deeper than a wade OR the body itself has dropped
	# below the surface by more than a wade. The player-Y branch is INDEPENDENT of the seabed reading,
	# so a too-high seabed, a steep unwadeable shore, or a dive-in can no longer suppress swim (the old
	# depth-only gate + a redundant `player.y < wl-0.2` AND-clause meant a shallow noise-lake never
	# triggered — the player just stood on a bottom ~0.3m under the surface, reading as lying ON the lake).
	# Exit only once the seabed has risen to the waterline AND the body is back near the surface (hysteresis).
	if not swimming and wl > -1e8 and (depth > WADE_DEPTH or below > WADE_DEPTH):
		_enter_swim()
	elif swimming and depth <= WADE_DEPTH and below <= 0.2:
		_exit_swim()   # ground rose to the waterline -> hand back to walk

	if swimming:
		# Float the body at the surface (head/shoulders above, always VISIBLE), move horizontally,
		# NO gravity — the water holds the player up.
		player.velocity.x = dir.x * SWIM_SPEED
		player.velocity.z = dir.z * SWIM_SPEED
		player.velocity.y = 0.0
		if dir.length() > 0.1:
			var slook := player.global_position - dir
			player.look_at(Vector3(slook.x, player.global_position.y, slook.z), Vector3.UP)
		player.move_and_slide()
		player.global_position.y = maxf(gy - 0.2, wl - SWIM_SURFACE_OFF)   # ride the surface offset, but never sink the feet through the seabed in marginal-depth water
		return

	# WALK: horizontal drive at 6 m/s + airborne-only gravity + floor snap (canonical vertical
	# motion — hugs descents, restores the full 45° climbable slope, no mid-air ledge hover).
	player.velocity.x = dir.x * 6.0
	player.velocity.z = dir.z * 6.0
	if player.is_on_floor():
		player.velocity.y = JUMP_SPEED if _jump_queued else 0.0   # launch a queued jump off the ground
	else:
		player.velocity.y -= GRAVITY * delta
	_jump_queued = false
	player.floor_snap_length = 0.0 if player.velocity.y > 0.1 else 0.8   # don't let floor-snap cancel a jump
	if dir.length() > 0.1:
		var look := player.global_position - dir
		player.look_at(Vector3(look.x, player.global_position.y, look.z), Vector3.UP)
	player.move_and_slide()
	_step_up_assist(dir)
	# FALL-CATCHER: chunk streaming can leave a one-frame collision gap while a cell's colliders
	# (re)build under the player — with gravity on, the player tunnels through and falls forever
	# ("the world vanished after walking"). _ground_y reads the heightmap DIRECTLY (no collider
	# needed), so if we've dropped well below it, snap back onto the surface. 2 m of slack leaves
	# legitimate drops/steps alone; the player is never meant to be below the ground floor.
	var floor_y := chunk_manager._ground_y(player.global_position.x, player.global_position.z) if chunk_manager != null else 0.0
	if player.global_position.y < floor_y - 2.0:
		player.global_position.y = floor_y + 0.05
		player.velocity.y = 0.0


# CONTRACT C (player half): joystick-Y climbs Y between base_y/top_y at CLIMB_SPEED, pinned to the
# ladder xz so the player can't drift off; at the top step FORWARD onto the surface and detach; below
# the base or a strong sideways push also detaches. velocity.y drives motion — the one place a
# vertical face is walkable. `climbing` is the Dictionary interaction.gd's ladder USE handed us.
func _climb_physics(_delta: float) -> void:
	var c: Dictionary = climbing
	var pos: Vector3 = c["pos"]
	var base_y := float(c["base_y"])
	var top_y := float(c["top_y"])
	var facing: Vector3 = c["facing"]
	var v := _keyboard_vec() + move_vec
	if absf(v.x) > 0.7:
		climbing = null                      # strong sideways input -> step off the ladder
		return
	player.velocity = Vector3(0.0, -v.y * CLIMB_SPEED, 0.0)   # screen-up (-y) ascends
	player.move_and_slide()
	player.global_position.x = pos.x         # pin to the ladder xz (no drift)
	player.global_position.z = pos.z
	if player.global_position.y >= top_y:
		player.global_position.y = top_y
		player.global_position += facing.normalized() * 0.6   # step forward onto the top surface
		climbing = null
		return
	if player.global_position.y <= base_y:
		player.global_position.y = base_y
		if v.y > 0.1:                        # still pushing down at the foot -> dismount at the base
			climbing = null


func _enter_swim() -> void:
	swimming = true
	GPose.swim(player)                       # self-guards: a capsule (unrigged) player is a no-op


func _exit_swim() -> void:
	swimming = false
	GPose.stand(player)


# Wave 2 UNIVERSAL STEP-UP ASSIST: when a grounded walk is blocked by a low lip (is_on_wall while
# pushing into it) but a walkable surface sits just ahead no higher than STEP_MAX, lift the feet onto
# it. This is the shoreline-exit + low-ledge fix. A DOWN-ray from just above STEP_MAX finds the
# surface; anything higher (a true wall) is left alone so the player is never launched up a face.
# Works in BOTH modes/tiers via the physics ray — no dependency on the terrain heightfield.
func _step_up_assist(dir: Vector3) -> void:
	if player == null or dir.length() < 0.1:
		return
	if not (player.is_on_wall() and player.is_on_floor()):
		return
	var into := dir.normalized()
	if into.dot(-player.get_wall_normal()) < 0.3:
		return                               # not actually moving into the wall we hit
	var feet := player.global_position.y
	# Probe PAST the capsule radius (0.4): at exactly the radius the down-ray lands tangent to a
	# sharp ledge face and hits the ground IN FRONT of it (step≈0) instead of the lip on top, so
	# low sharp ledges never lifted. 0.6 = radius + margin, landing the ray solidly on the lip.
	var ahead := player.global_position + into * 0.6
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(ahead.x, feet + STEP_MAX + 0.1, ahead.z),
		Vector3(ahead.x, feet - 0.5, ahead.z), L_WORLD)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var step := float(hit["position"].y) - feet
	if step > 0.05 and step <= STEP_MAX:
		player.global_position.y = float(hit["position"].y) + 0.02   # onto the lip


func _process(delta: float) -> void:
	if cam_rig and player:
		# Rig follows the player; yaw/pitch come from drag-look. The SpringArm
		# keeps the camera aimed at the head and pulls it in through walls.
		var head := CAM_HEAD
		# HIDDEN driver (closed-cabin modeled vehicle / tank swap-in): the player is parked at
		# the body origin, so the head pivot sits INSIDE the hull — lift it so the orbit reads
		# over the roof. Keyed on visibility, not body type: any hidden-driver ride has this.
		if active_vehicle != null and is_instance_valid(active_vehicle) and not player.visible:
			head += 0.6
		# CONTRACT B: while driving AND not drag-looking, ease the orbit behind the vehicle. Manual
		# drag-look (look_idx != -1) overrides so the player keeps camera control. Composes with the
		# Wave 1.5 hidden-driver head-lift above (both keyed on active_vehicle).
		if active_vehicle != null and is_instance_valid(active_vehicle) and look_idx == -1:
			cam_yaw = lerp_angle(cam_yaw, active_vehicle.rotation.y + PI, minf(1.0, 3.0 * delta))
		cam_rig.global_position = player.global_position + Vector3(0.0, head, 0.0)
		cam_rig.rotation.y = cam_yaw
		cam_spring.rotation.x = cam_pitch
		# SpringArm collapse guard: when a prop/wall squeezes the camera onto the player, the view
		# renders from INSIDE the hero mesh (a full-screen smear of cape/armor). Hide the avatar
		# while the camera is that close — standard near-camera treatment.
		if _hero_avatar != null and is_instance_valid(_hero_avatar):
			var cd := cam.global_position.distance_to(cam_rig.global_position)
			_hero_avatar.visible = cd > 1.35
	# Wave 4: attack timers + the melee swing visual moved HERE from the two physics paths
	# (which early-return while DRIVING) so a MOUNTED rider's swing still animates/decays and
	# the ranged cooldown keeps ticking — riders fire too. Same 0.22s window and the exact
	# hardcoded-sword formula, now routed at the GEquipSlot pivot. Non-melee weapons keep the
	# orientation GEquip gave them (no -10° idle stomp on a bow).
	swing_t = maxf(0.0, swing_t - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_update_hero_anim(delta)   # idle/walk/run/attack state machine (on foot; riders are GPose-posed)
	_fade_near_camera_enemies()   # #6: hide any enemy pressed against the camera lens so it can't "pop up"
	if weapon_slot != null and is_instance_valid(weapon_slot) \
			and String(_equipped_def().get("kind", "melee")) == "melee":
		weapon_slot.rotation_degrees.x = (-90.0 + (1.0 - swing_t / 0.22) * 120.0) if swing_t > 0.0 else -10.0
	if chunk_mode and chunk_manager != null:
		chunk_manager.tick(delta)
	if stats:
		_refresh_stats()


# ---------------- HUD ----------------

func _update_stats() -> void:
	_refresh_stats()
	if hp_bar and rpg:
		hp_bar.size.x = 220.0 * clamp(rpg.hp / rpg.max_hp, 0.0, 1.0)


func _refresh_stats() -> void:
	if rpg == null:
		return
	var inv := rpg.inventory_summary()
	if inv.length() > 46:
		inv = inv.substr(0, 43) + "..."
	stats.text = "Lv %d  HP %d/%d  XP %d/%d  Gold %d\nWpn: %s\nInv: %s" % [
		rpg.level, int(rpg.hp), int(rpg.max_hp), rpg.xp, rpg.xp_next, rpg.gold,
		rpg.item_name(rpg.equipped_weapon), inv]


# ---------------- combat / hooks ----------------

# The ONE attack entry (the HUD ATTACK button): routes by the equipped weapon's kind.
# melee -> the Wave-1 swing, byte-identical semantics (2.6u reach, forward half-cone,
# enemy.take_hit). ranged/thrown -> _fire_ranged (auto-aim + pooled GProjectile). The button
# stays LIVE while DRIVING/MOUNTED — only _physics_process's movement routing is gated on
# active_vehicle, Button.pressed never passes through it — so riders fire too.
## Hide any enemy that presses against the camera lens (#6) so a body up close can't fill the frame like
## a "popup". main runs the distance test because the SpringArm masks world-only and never collides with
## enemies (layer 4). Giant enemies are also scale-capped at spawn (enemy.gd MAX_ENEMY_H).
func _fade_near_camera_enemies() -> void:
	if cam == null or not is_instance_valid(cam):
		return
	var streamer = chunk_manager if chunk_mode else scene_manager
	if streamer == null:
		return
	var cp := cam.global_position
	for e in streamer.enemies:
		if is_instance_valid(e) and e.has_method("set_camera_near"):
			e.set_camera_near(cp.distance_to(e.global_position))


func _attack() -> void:
	if _weapon_stowed:
		_toggle_weapon()   # draw the weapon to strike — a sheathed weapon never blocks combat
	var streamer = chunk_manager if chunk_mode else scene_manager
	if streamer == null or streamer.transitioning:
		return
	var def := _equipped_def()
	var kind := String(def.get("kind", "melee"))
	if kind == "ranged" or kind == "thrown":
		_fire_ranged(def, streamer)
		return
	if swing_t > 0.0:
		return
	swing_t = 0.22
	_hero_attack_t = 0.45   # play the melee swing body animation
	_play_hero("attack")
	AudioManager.play_sfx("attack")
	var dmg := rpg.weapon_damage()
	var fwd := player.global_transform.basis.z   # forward=+Z (look_at(pos-dir) faces +Z); -basis.z hit BEHIND (inverted cone)
	# DIRECT HIT: strike only the SINGLE CLOSEST foe inside a real forward swing arc — not every body in
	# a ~150° hemisphere. The old `length < 2.6 and dot > 0.25` sprayed FULL damage across the whole
	# surrounding pack (one tap wiped a group) and let a near-miss "kill by proximity". Acquire the
	# nearest foe roughly ahead, turn to face it (the blow reads as aimed), then land ONE hit.
	var target = null
	var target_d := 2.4   # melee reach, metres
	for e in streamer.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var to: Vector3 = e.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d > 0.001 and d < target_d and fwd.dot(to / d) > 0.35:
			target = e
			target_d = d
	if target == null:
		# AIM ASSIST (mobile): nothing in the forward cone, but a foe is within REACH — acquire the
		# nearest one in ANY direction. A stationary ATTACK tap must never whiff while an enemy
		# gnaws at the player's back (enemies circle their surround slots, so "behind" is common).
		# Still ONE target, still full reach, and the look_at below turns the body so the blow
		# reads as aimed — not a proximity kill.
		target_d = 2.4
		for e in streamer.enemies:
			if not is_instance_valid(e) or e.dead:
				continue
			var to2: Vector3 = e.global_position - player.global_position
			to2.y = 0.0
			var d2 := to2.length()
			if d2 > 0.001 and d2 < target_d:
				target = e
				target_d = d2
	if target != null:
		var tp: Vector3 = target.global_position
		player.look_at(Vector3(tp.x, player.global_position.y, tp.z), Vector3.UP)   # face the struck foe
		target.take_hit(dmg)
		_hit_spark(tp + Vector3(0.0, 1.0, 0.0))


# JUICE FLOOR: a one-shot spark burst at the melee impact point (ranged already puffs via
# GProjectile) — a hit you can't SEE land reads as broken combat.
func _hit_spark(at: Vector3) -> void:
	var streamer = chunk_manager if chunk_mode else scene_manager
	var root: Node3D = streamer.current_root if streamer != null else null
	if root == null or not is_instance_valid(root):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 16
	p.lifetime = 0.45
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.16
	p.color = Color(1.0, 0.9, 0.5)
	root.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(0.8)
	tw.tween_callback(p.queue_free)


# The live equipped-weapon def: GEquip stamps "gequip_def" on the character at equip time;
# before the first equip lands (async boot) fall back to the catalog def for the equipped id.
func _equipped_def() -> Dictionary:
	if player != null and player.has_meta("gequip_def"):
		var d = player.get_meta("gequip_def")
		if d is Dictionary:
			return d
	return rpg.weapon_def(rpg.equipped_weapon) if rpg != null else {}


# Wave 4 ranged/thrown fire — mobile-first AUTO-AIM: the NEAREST live enemy inside the
# FIRE_CONE_DEG cone of the character's facing AND inside weapon range is aimed at its chest
# (+1.0m); none in the cone -> straight ahead. The per-weapon rate gates repeat taps.
# MOUNTED riders compose for free: the GEquipSlot rides the player, which vehicle.gd's
# _track_driver parks (and faces) on the boardable every tick — origin + facing follow, no
# special casing. Facing is +basis.z, the stack convention (characters FACE +Z — see
# vehicle.gd / GPose); melee's legacy -basis.z half-cone above is untouched by contract.
func _fire_ranged(def: Dictionary, streamer) -> void:
	if _fire_cd > 0.0:
		return
	var root: Node3D = streamer.current_root
	if root == null or not is_instance_valid(root):
		return
	_fire_cd = 1.0 / maxf(0.1, float(def.get("rate", 1.2)))
	var fwd: Vector3 = player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3.BACK
	var rng := maxf(1.0, float(def.get("range", 20.0)))
	var cone := cos(deg_to_rad(FIRE_CONE_DEG * 0.5))
	var best: Node3D = null
	var bd := rng   # nearest-wins inside the cone
	for e in streamer.enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var to: Vector3 = (e as Node3D).global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.01 or d > bd:
			continue
		if fwd.dot(to / d) < cone:
			continue
		bd = d
		best = e
	# muzzle = the GEquipSlot (weapon tip-ish) + a small forward offset; slot not attached
	# yet (async equip in flight) -> chest height on the player. in_tree guard: NEVER read a
	# global transform off a detached node (doctrine).
	var muzzle: Vector3 = player.global_position + Vector3(0.0, 1.2, 0.0)
	if weapon_slot != null and is_instance_valid(weapon_slot) and weapon_slot.is_inside_tree():
		muzzle = weapon_slot.global_position
	muzzle += fwd * MUZZLE_FWD
	var dir: Vector3 = fwd
	if best != null:
		dir = ((best.global_position + Vector3(0.0, 1.0, 0.0)) - muzzle).normalized()
	AudioManager.play_sfx("attack")
	GProjectile.flash(muzzle, root)
	GProjectile.fire(root, muzzle, dir, def, _live_enemies)


# enemies_provider handed to GProjectile.fire — always the ACTIVE streamer's live union
# (chunk resident ring / zone area), so a projectile in flight never holds a stale list.
func _live_enemies() -> Array:
	var streamer = chunk_manager if chunk_mode else scene_manager
	return streamer.enemies if streamer != null else []


# Keep the ATTACHED weapon visual in sync with rpg.equipped_weapon (boot start_weapon, chest
# auto-equip upgrades, hot-reload re-stats). "parametric:*" models attach with no fetch;
# library//BUILD_ID GLBs prefetch through the SHARED builder cache (the vehicles' path).
# Loops because equipped_weapon can change again during the await; GEquip.equip is
# idempotent, one weapon at a time.
func _sync_equip_visual() -> void:
	if _equip_busy or player == null or rpg == null:
		return
	_equip_busy = true
	while _equipped_visual_id != rpg.equipped_weapon:
		var id: String = rpg.equipped_weapon
		var def: Dictionary = rpg.weapon_def(id)
		var model: Node3D = null
		var mu := String(def.get("model", ""))
		if mu != "" and not mu.begins_with("parametric:"):
			var u := _norm(mu)
			if u != "":
				await builder._ensure([u])
				if builder.cache.has(u) and builder.cache[u] != null:
					model = (builder.cache[u] as Node).duplicate() as Node3D
		GEquip.equip(player, def, model)
		weapon_slot = player.find_child("GEquipSlot", true, false) as Node3D
		if weapon_slot != null:
			weapon_slot.visible = not _weapon_stowed   # a mid-ride re-equip must not un-stow (Wave 1.5)
		_equipped_visual_id = id
	_equip_busy = false


func _on_rpg_changed() -> void:
	if rpg != null and _equipped_visual_id != rpg.equipped_weapon:
		_sync_equip_visual()   # fire-and-forget — the latch + loop absorb re-entry


func take_damage(d: float) -> void:
	AudioManager.play_sfx("hurt")
	_flash_hurt(false)   # brief red flash so the hit READS — non-modal, never a banner/popup/dialog
	if director != null:
		director._shake_cam(0.15)   # small kick so a hit taken lands physically, not just as a tint
	if chunk_mode:
		if rpg.take_damage(d):
			rpg.hp = rpg.max_hp   # forgiving respawn in place (no area transition in chunk mode)
			_flash_hurt(true)     # stronger pulse marks the recovery instead of a modal "you died" banner
		return
	if scene_manager == null or scene_manager.transitioning:
		return
	if rpg.take_damage(d):
		rpg.hp = rpg.max_hp        # forgiving respawn: full heal in the current area
		_flash_hurt(true)
		scene_manager.goto_area(scene_manager.current_id, scene_manager.areas[scene_manager.current_id].spawns.keys()[0])


# Non-modal damage feedback: pulse the red overlay and fade it out. `strong` = a bigger pulse for the
# in-place recovery (hp hit 0). NEVER a popup/banner/dialog — a hit must never interrupt play.
func _flash_hurt(_strong: bool) -> void:
	# DISABLED by request: no on-hit screen overlay at all. The full-screen red flash read as an
	# intrusive "popup" when the player was attacked. Damage still registers (hp, audio, camera kick);
	# there is simply no visual interrupt. Kept as a no-op so every existing call site stays valid.
	return


func on_enemy_killed(type: String) -> void:   # called by enemy.gd on death
	AudioManager.play_sfx("death")
	if rpg:
		rpg.grant_xp(15)
	if quest:
		quest.notify_kill(type)


# ---------------- live hot-reload from chat edits ----------------

## Parse JSON to a Dictionary WITHOUT the engine printing "Parse JSON failed" on a bad body (a 503 error
## page, a truncated edge-cache response, or an in-flight write). The static JSON.parse_string() pushes a
## global ERROR on a malformed body even when the caller handles the null; JSON.new().parse() returns an
## error code silently. Returns {} on any failure. (#17 — boot/poll JSON hardening.)
func _json_dict(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	return j.data if j.data is Dictionary else {}


func _poll_world() -> void:
	# re-fetch world.json; if a chat edit changed it (qgcheck already gated it server-side),
	# hot-reload the current area live. Cache-buster bypasses the edge cache.
	if scene_manager == null or scene_manager.transitioning or world_data.is_empty() or _polling:
		return
	_polling = true
	var req := HTTPRequest.new()
	add_child(req)
	req.request(world_url + "?t=" + str(Time.get_ticks_msec()))
	var res = await req.request_completed
	req.queue_free()
	_polling = false
	if res[1] != 200:
		return
	var raw := (res[3] as PackedByteArray).get_string_from_utf8()
	if raw == _world_raw or raw.strip_edges() == "":
		return
	var w := _json_dict(raw)   # #17: silent parse — a truncated/error poll body degrades quietly, no console spam
	if w.is_empty():
		return
	# chunk worlds carry "cells"/"grid" (not "areas"); zone worlds carry "areas"
	if chunk_mode:
		if not w.has("cells"):
			return
	elif not w.has("areas"):
		return
	_world_raw = raw
	world_data = w
	_apply_weather(w)
	# Wave 4: a chat edit can re-stat "weapons" (damage/model/…). Reload the merged catalog and
	# re-attach the visual ONLY when the equipped def's content actually changed (deep ==).
	# Awaited so a weapon-model fetch is serialized BEFORE the streamer reload's downloads.
	var eq_before: Dictionary = rpg.weapon_def(rpg.equipped_weapon)
	rpg.load_weapons(w.get("weapons", {}))
	if rpg.weapon_def(rpg.equipped_weapon) != eq_before:
		_equipped_visual_id = ""
		await _sync_equip_visual()
	# vehicles-only rebuild when the world "vehicles" list changed (never touches the player or the
	# streamer). Awaited so its model fetch is serialized BEFORE the streamer reload's downloads.
	await _reload_vehicles(w)
	if chunk_mode:
		chunk_manager.reload(world_data)   # rebuild only CHANGED resident cells in place — no player move
	else:
		scene_manager.reload(world_data)   # no re-export — the live area rebuilds


# ---------------- drivable vehicles (world-level "vehicles", vehicle.gd) ----------------

# Spawn the world's "vehicles" ONCE onto a persistent layer (a direct child of main — chunk cell
# eviction and zone area frees can never reclaim it). Zone worlds get the same world-space
# placement. Models fetch through the SHARED builder cache (parallel, dedup'd); a world with no
# "vehicles" returns immediately — zero behavior change.
func _spawn_vehicles(world: Dictionary) -> void:
	var list = world.get("vehicles", [])
	if not (list is Array) or (list as Array).is_empty():
		_vehicles_spec = []
		return
	_vehicles_spec = (list as Array).duplicate(true)   # snapshot for the hot-reload diff
	if vehicle_root == null:
		vehicle_root = Node3D.new()
		add_child(vehicle_root)
	var urls: Array = []
	for spec in list:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var u := _vehicle_model_url(spec)
		if u != "" and not urls.has(u):
			urls.append(u)
	await builder._ensure(urls)
	for spec in list:
		if typeof(spec) != TYPE_DICTIONARY:
			continue
		var pos = spec.get("pos", [])
		if not (pos is Array) or (pos as Array).size() < 2:
			continue
		var mu := _vehicle_model_url(spec)
		var model: Node3D = null
		if mu != "" and builder.cache.has(mu) and builder.cache[mu] != null:
			model = (builder.cache[mu] as Node).duplicate() as Node3D
		var car := Vehicle.new()
		car.player_ref = player
		car.set_meta("spec", spec)   # director reads stable_id/tamed_name for taming + summon
		car.setup(spec, model)   # scale-normalize (4m car) + AABB-ground + box collider + prompt
		vehicle_root.add_child(car)
		car.global_position = Vector3(float(pos[0]), 0.0, float(pos[1]))
		car.drive_state_changed.connect(_on_vehicle_drive_state)
		interaction.add_vehicle(car)   # same touch/USE mechanism chests/NPCs use -> enter/exit
		vehicles.append(car)


# world.json vehicle "model" (or url/asset) -> absolute URL. Defaults are
# PER-PROFILE (Wave 3): mounts resolve their pinned library creature
# (farm_Horse / farm_Cow / monster_Dragon via Vehicle.default_model_path);
# parametric profiles (car/tank/boat/plane) return "" — the Vehicle builds
# its own body, so prefetching the sedan for them would be wasted.
func _vehicle_model_url(spec: Dictionary) -> String:
	var u := String(spec.get("model", spec.get("url", spec.get("asset", ""))))
	if u == "":
		u = Vehicle.default_model_path(String(spec.get("profile", "car")))
	if u == "":
		return ""   # parametric profile with no explicit model — nothing to fetch
	return _norm(u)


# Hot-reload: the polled world.json changed — if (and only if) its "vehicles" list differs from the
# spawned snapshot, rebuild the vehicles alone. The player is untouched UNLESS they are driving a
# rebuilt car, in which case they step out first (a hidden player must never be left attached to a
# freed node).
func _reload_vehicles(w: Dictionary) -> void:
	var list = w.get("vehicles", [])
	if not (list is Array):
		list = []
	if (list as Array) == _vehicles_spec:   # deep == on nested Arrays/Dictionaries
		return
	if active_vehicle != null and is_instance_valid(active_vehicle):
		active_vehicle.exit()   # clears active_vehicle via _on_vehicle_drive_state
	active_vehicle = null
	for v in vehicles:
		if is_instance_valid(v):
			(v as Node).queue_free()
	vehicles = []
	interaction.remove_vehicles()
	await _spawn_vehicles(w)
	_wire_vehicle_terrain()


# Vehicles spawn before ChunkManager builds GTerrain — hand them the heightfield afterwards so a
# parked car snaps onto the rendered surface (no-op for flat/zone worlds: terrain stays null -> y=0).
func _wire_vehicle_terrain() -> void:
	if not chunk_mode or chunk_manager == null:
		return
	for v: Vehicle in vehicles:
		if is_instance_valid(v):
			v.set_terrain(chunk_manager.terrain)
			# Wave 3: boats ride the water surface — hand them the level when
			# the world opted into water (else they keep the terrain degrade).
			if chunk_manager.water_cfg != null:
				v.set_water(chunk_manager.water_level)


# Enter/exit bookkeeping: route input to the active car and exclude its body from the camera
# SpringArm sweep (the car is on the world layer the arm collides with — without the exclusion the
# arm hits the car's own box and jams the camera against the roof).
func _on_vehicle_drive_state(v: Vehicle, is_driving: bool) -> void:
	if is_driving:
		active_vehicle = v
		cam_spring.add_excluded_object(v.get_rid())
		_set_weapon_stowed(not v.is_mount())   # Wave 1.5: stow the weapon in VEHICLES, keep it on mounts
	else:
		if active_vehicle == v:
			active_vehicle = null
		cam_spring.remove_excluded_object(v.get_rid())
		_set_weapon_stowed(false)   # back on foot — the weapon reappears
	if _dismount_btn != null and is_instance_valid(_dismount_btn):
		_dismount_btn.visible = active_vehicle != null   # show GET-OFF only while aboard


# Weapon-visual STOW (Wave 1.5). While DRIVING A VEHICLE the equipped weapon is hidden (a driver
# isn't brandishing a blade); MOUNTS keep it — firing from the saddle is a Wave-4 feature. Toggled
# ONLY on the board/exit transitions above, and re-asserted by _sync_equip_visual so a mid-ride
# chest auto-equip re-attaches HIDDEN. The HUD (Wpn: label, ATTACK button) is untouched — combat
# still fires; only the on-body visual disappears while stowed.
func _set_weapon_stowed(stow: bool) -> void:
	_weapon_stowed = stow
	if weapon_slot != null and is_instance_valid(weapon_slot):
		weapon_slot.visible = not stow


# ---------------- input ----------------

func _input(event: InputEvent) -> void:
	if scene_manager == null or scene_manager.transitioning:
		return
	if director != null and director.input_locked():
		return   # title screen owns the pointer until a mode is chosen
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_SPACE:
		_jump_queued = true   # consumed next physics frame if the player is on the floor
		return
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and move_idx == -1:
				move_idx = event.index
				move_origin = event.position
				move_vec = Vector2.ZERO
			elif event.position.x >= half and look_idx == -1:
				# right half of the screen = drag to orbit the camera
				look_idx = event.index
				look_last = event.position
		else:
			if event.index == move_idx:
				move_idx = -1
				move_vec = Vector2.ZERO
			elif event.index == look_idx:
				look_idx = -1
	elif event is InputEventScreenDrag:
		if event.index == move_idx:
			move_vec = ((event.position - move_origin) / 80.0).limit_length(1.0)
		elif event.index == look_idx:
			_apply_look(event.position - look_last)
			look_last = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and move_idx == -1 and look_idx == -1:
		# desktop drag-look (no active touches → ignores emulated-from-touch motion)
		_apply_look(event.relative)


func _apply_look(d: Vector2) -> void:
	cam_yaw -= d.x * LOOK_SENS
	cam_pitch = clampf(cam_pitch - d.y * LOOK_SENS, CAM_PITCH_MIN, CAM_PITCH_MAX)


func _keyboard_vec() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): v.y += 1.0
	return v


# ---------------- manifest ----------------

func _parse_manifest(body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		return
	# Scatter = ambient NATURE clutter ONLY (rocks/plants/trees/logs). The manifest tags every prop
	# with a `category`; pulling the WHOLE library scattered buildings/walls/swords/pipes into every
	# area (incongruous, odd-shaped "floating" junk). Named PALETTE props are a separate path, unaffected.
	for p in data.get("props", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if String(p.get("category", "")) != "nature":
			continue
		# within "nature", skip terrain/tiling pieces (cliffs, paths, beach/road edges) — those tile
		# the ground, they're not free-standing scatter clutter
		var fn := String(p.get("file", "")).get_file().to_lower()
		if "terrain" in fn or "path" in fn or "cliff" in fn or "beach" in fn or "railway" in fn or "road" in fn or "fence" in fn:
			continue
		var u := _norm(String(p.get("file", "")))   # relative → resolves against origin (portable)
		if u != "" and "/godot-assets/props/" in u:
			props_pool.append(u)


func _collect(v, out_arr: Array) -> void:
	match typeof(v):
		TYPE_STRING:
			if (v as String).to_lower().ends_with(".glb"):
				out_arr.append(v)
		TYPE_DICTIONARY:
			for k in v:
				_collect(v[k], out_arr)
		TYPE_ARRAY:
			for e in v:
				_collect(e, out_arr)


func _norm(s: String) -> String:
	if s.begins_with("http"):
		return s
	if s.begins_with("/"):
		# Self-heal build-coupled paths: a rebuilt world.json bakes the AUTHORING build's id into
		# absolute /cloud-<id>/… (and /news-cloud-<id>/…) asset URLs, so after a rebuild to a NEW id
		# every one 404s and renders as a gray placeholder. Re-root any such path onto the CURRENT
		# build_id so the build's own committed assets resolve regardless of which id authored them.
		if build_id != "" and (s.begins_with("/cloud-") or s.begins_with("/news-cloud-")):
			var slash := s.find("/", 1)   # the '/' after the leading /<buildid> segment
			if slash > 0:
				return origin + "/" + build_id + s.substr(slash)
		return origin + s
	if "/" in s:
		return origin + "/godot-assets/" + s
	return ""


# Prompt-driven sky/weather: the agent sets a top-level "sky" block in world.json
# (a fixed {time,weather} or a {cycle:[...],loop}). Re-applied on hot-reload.
func _apply_weather(world: Dictionary) -> void:
	if weather == null:
		return
	var sky = world.get("sky", null)
	if sky is Dictionary:
		weather.apply(sky)


# ---------------- web time-of-day hooks (window.gogiSetTime / gogiGetTime) ----------------

# Let page JS drive the sky for preview/QA harnesses. gogiSetTime(state) pins the time-of-day
# INSTANTLY (Weather3D.set_time snaps — no lerp) keeping the current weather; gogiGetTime() reads
# the last-applied state back. Accepts any Weather3D TIME key ("day"/"night"/"sunrise"/"sunset").
# No-op off the web. The callback is stored in a member — JavaScriptBridge callbacks are GC'd the
# instant nothing references them.
func _setup_web_time_hooks() -> void:
	if not OS.has_feature("web") or weather == null:
		return
	_js_set_time_cb = JavaScriptBridge.create_callback(_on_gogi_set_time)
	var win = JavaScriptBridge.get_interface("window")
	if win != null:
		win.gogiSetTime = _js_set_time_cb
	JavaScriptBridge.eval("window.__gogiTime='%s';window.gogiGetTime=function(){return window.__gogiTime;};" % weather.time_state, true)
	# Wave 5: publish window.gogiGetPlayer() + window.gogiSolids() so verify.mjs's live probes (drive /
	# swim / collision / spawn / ascent / streaming) activate. Each raw callback returns a JSON STRING
	# (the only reliably-marshalled return type); a thin JS wrapper JSON.parses it to the object/array
	# the probes expect (verify.mjs:1255-1258). Web + verify only; no cost off the web.
	_js_get_player_cb = JavaScriptBridge.create_callback(_on_gogi_get_player)
	_js_solids_cb = JavaScriptBridge.create_callback(_on_gogi_solids)
	if win != null:
		win.__gogiGetPlayerRaw = _js_get_player_cb
		win.__gogiSolidsRaw = _js_solids_cb
	JavaScriptBridge.eval(
		"window.gogiGetPlayer=function(){var s=window.__gogiGetPlayerRaw();return s?JSON.parse(s):(window.__gogiPlayer||null);};" +
		"window.gogiSolids=function(){var s=window.__gogiSolidsRaw();return s?JSON.parse(s):[];};", true)
	# JavaScriptBridge callback RETURN VALUES do not marshal back to JS in the web export (the raw
	# call yields null), so the wrapper above would always return null — the same reason the director
	# PUSHES __gogiVerdance on a timer. Mirror that: push the player state every 0.3s and let the
	# wrapper fall back to the pushed snapshot.
	var pt := Timer.new()
	pt.wait_time = 0.3
	pt.autostart = true
	pt.timeout.connect(func() -> void:
		JavaScriptBridge.eval("window.__gogiPlayer=" + _on_gogi_get_player([]) + ";", true))
	add_child(pt)


func _on_gogi_set_time(args: Array) -> void:
	if weather == null or args.is_empty():
		return
	var state := String(args[0])
	weather.set_time(state)   # immediate where the state resolves; a lerp only if a cycle chase is mid-flight
	JavaScriptBridge.eval("window.__gogiTime='%s';" % weather.time_state, true)
	print("GOGI_TIME ", weather.time_state)


# window.gogiGetPlayer() — live player state as a JSON string (the JS wrapper parses it). Fields match
# the verify.mjs probe contract (verify.mjs:1255-1258). Off-ladder `climbing` is null -> false.
func _on_gogi_get_player(_args: Array) -> String:
	if player == null or not is_instance_valid(player):
		return "null"
	var p := player.global_position
	var d := {
		"x": p.x, "y": p.y, "z": p.z,
		"in_vehicle": active_vehicle != null and is_instance_valid(active_vehicle),
		"cam_yaw": cam_yaw,
		"climbing": climbing != null,
		"swimming": swimming,
		"on_floor": player.is_on_floor(),   # verify.mjs floating-avatar gate: grounded unless swim/climb/vehicle
	}
	if active_vehicle != null and is_instance_valid(active_vehicle):
		d["vehicle_yaw"] = active_vehicle.rotation.y
		d["vehicle_airborne"] = active_vehicle._airborne   # verify flight-brake probe
		d["vehicle_profile"] = active_vehicle.profile      # verify boat/mount probes (car/boat/plane/horse/…)
	if _dismount_btn != null and is_instance_valid(_dismount_btn):
		# verify: the DISMOUNT affordance's visibility + UI rect (+ the UI viewport size, so the
		# harness can convert UI coords -> CSS px under canvas_items/expand content scaling)
		var vps := get_viewport().get_visible_rect().size
		d["dismount_visible"] = _dismount_btn.visible
		d["dismount_rect"] = [_dismount_btn.global_position.x, _dismount_btn.global_position.y,
			_dismount_btn.size.x, _dismount_btn.size.y, vps.x, vps.y]
	return JSON.stringify(d)


# window.gogiSolids() — world AABBs of the SOLID bodies (structures/props/roads) in the resident ring,
# as a JSON string of [{min:[x,y,z], max:[x,y,z]}]. Excludes the terrain floor (group "gogi_terrain")
# so a player standing ON the ground never reads as "inside a solid". On-demand only (verify probes).
func _on_gogi_solids(_args: Array) -> String:
	var out: Array = []
	if chunk_manager != null and is_instance_valid(chunk_manager):
		for k in chunk_manager.resident:
			var rec = chunk_manager.resident[k]
			var root = rec.get("root")
			if root != null and is_instance_valid(root):
				_collect_solids(root, out)
	return JSON.stringify(out)


func _collect_solids(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is StaticBody3D and not (c as Node).is_in_group("gogi_terrain"):
			var ab := _body_world_aabb(c as StaticBody3D)
			if ab.size.length() > 0.01:
				out.append({
					"min": [ab.position.x, ab.position.y, ab.position.z],
					"max": [ab.end.x, ab.end.y, ab.end.z]})
		_collect_solids(c, out)


# Merged world AABB of a static body's collision shapes. Shape3D.get_debug_mesh() yields a local AABB
# for ANY shape (box/sphere/trimesh), transformed by the shape node's world transform.
func _body_world_aabb(body: StaticBody3D) -> AABB:
	var merged := AABB()
	var first := true
	for cs in body.get_children():
		if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
			var dm := (cs as CollisionShape3D).shape.get_debug_mesh()
			if dm == null:
				continue
			var wa: AABB = (cs as CollisionShape3D).global_transform * dm.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged


# ---------------- world build (persistent player/env/hud) ----------------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.66)
	# Look upgrade (env is shared; the Weather3D system reuses it and only overrides sky/ambient, so
	# these survive). ACES tonemap = warm/filmic vs the flat linear default; a touch of contrast +
	# saturation so nothing reads washed-out. Both are Compatibility/WebGL2-safe (Environment GLOW is
	# NOT — neon is faked with emissive + an additive quad per art.md, never env.glow_enabled).
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# tonemap_white MUST be > 1.0: at the default (1.0) ACES clips ALL radiance >= 1.0 to pure
	# white, so any albedo >= ~0.72 under the noon sun+ambient renders as a detail-free blob
	# (stucco/plaster/limestone/marble all become the same white). 4.0 restores highlight
	# headroom and N.L shading separation on pale walls, day AND night.
	env.tonemap_white = 4.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -45.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true   # contact shadows GROUND props. In CHUNK mode _boot tightens the cascade +
	add_child(sun)              # the floor slab is cast_shadow=OFF, so props cast but the flat floor can't acne.


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.collision_layer = L_PLAYER
	player.collision_mask = L_WORLD | L_ENEMY
	player.floor_snap_length = 0.8   # Wave 2: feet stay stuck to descents/stairs (no mid-air hover)
	player.floor_max_angle = deg_to_rad(55)   # climb steep alien hills/ramps (Godot's 45° default read them as walls)
	add_child(player)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.85
	player.add_child(cs)
	# DEFAULT body = a placeholder capsule. To use a real character, load a .glb
	# (library OR Meshy — SAME path) and SEAT it so its feet rest on the floor
	# (character GLB origins sit at the hips, so feet sink under the floor without this):
	#     var avatar := load("res://models/hero.glb").instantiate() as Node3D
	#     player.add_child(avatar)
	#     _seat_avatar(avatar)            # feet at y=0; then remove the capsule body
	#     # size the CollisionShape capsule from the model's height if it differs.
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.6
	body.mesh = cm
	body.position.y = 0.85
	body.material_override = _mat(Color(0.3, 0.6, 0.95))
	player.add_child(body)
	_capsule_body = body   # kept so a native hero_model attach can hide the placeholder (see _attach_hero_model)
	# Wave 4: the old hardcoded sword MeshInstance is GONE — GEquip attaches the equipped
	# weapon's visual on a "GEquipSlot" node instead (_sync_equip_visual, called from _ready
	# once RpgState exists). The swing routine in _process rotates that slot, same formula.
	# Third-person SpringArm orbit rig: a yaw pivot that follows the player, a
	# collision-aware spring arm (pulls the cam in at walls), and the camera on
	# the tip — empirically the cam lands at +Z*length, auto-aimed at the pivot.
	# Pitch is clamped so it can never dive to the floor; movement is camera-relative.
	cam_rig = Node3D.new()
	add_child(cam_rig)
	cam_spring = SpringArm3D.new()
	cam_spring.spring_length = CAM_DIST
	cam_spring.collision_mask = L_WORLD
	cam_spring.margin = 0.3
	cam_spring.rotation.x = cam_pitch
	cam_rig.add_child(cam_spring)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.1   # up from the 0.05 default — better distant depth precision (far stays 4000)
	cam_spring.add_child(cam)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


# Seat a MODEL avatar so its feet rest on the floor (y=0 at the body origin).
# Library/Meshy character GLBs often have their origin at the hips/centre, so
# without this the feet sink under the floor — props get the same treatment in
# the AreaBuilder; this is the player-side equivalent. Call after add_child().
const AVATAR_FOOT_LIFT := 0.05   # lowest skeleton bone is the ankle/toe; nudge up a hair so soles sit ON the ground, not a toe-thickness into it

func _seat_avatar(node: Node3D) -> void:
	# Seat the avatar so its FEET rest at the body origin. Prefer the SKELETON's lowest bone over the
	# raw mesh AABB: a Meshy/library character's lowest MESH point is often a robe/cape/tail/weapon that
	# hangs BELOW the soles, so seating the mesh-bottom at y=0 lifted the whole body ~0.5-0.8m — it
	# "floated above its shadow" while walking (root-caused live). Bone poses ignore dangling cloth.
	# Falls back to the mesh AABB only when the model is unrigged (no Skeleton3D).
	var foot := _skeleton_min_y(node)
	if is_finite(foot):
		node.position.y -= (foot - AVATAR_FOOT_LIFT)
	else:
		node.position.y -= _subtree_aabb(node).position.y
	# verify.mjs floating-avatar gate: the SEATED mesh's lowest point in player-local space. A correct
	# seat leaves it near 0 (feet at the ground origin; a rigged cape may drag slightly below). Well
	# above 0 means the whole avatar was lifted off the ground — it "floats above its shadow".
	print("GOGI_HERO_SEAT %.3f" % _subtree_aabb(node).position.y)


func _skeleton_min_y(root: Node) -> float:
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return INF
	var skel := skels[0] as Skeleton3D
	# Seat by the true FOOT bones. A rigged cape/cloak/skirt/tail/coat hangs BELOW the soles, so
	# taking the raw lowest bone picks the cloth tip and over-lifts the whole body — it "floats above
	# its shadow" while walking even though the mesh-AABB fix was already in place (the caped Warden
	# defeated it because its cloth is RIGGED, not just mesh). Skip those bones by name; if a rig
	# leaves them all filtered (unnamed Meshy cloth), fall back to the unfiltered min so we never
	# return INF for a rigged model.
	var best := INF
	var best_any := INF
	for i in skel.get_bone_count():
		var wy: float = (skel.global_transform * skel.get_bone_global_pose(i).origin).y
		best_any = minf(best_any, wy)
		if _is_cloth_bone(skel.get_bone_name(i).to_lower()):
			continue
		best = minf(best, wy)
	return best if is_finite(best) else best_any


# Dangling cloth / appendage bones that can hang below the soles and must not be treated as the foot.
func _is_cloth_bone(bn: String) -> bool:
	for kw in ["cape", "cloak", "cloth", "skirt", "robe", "coat", "dress", "tail", "scarf", "sash", "tassel", "ribbon", "hair", "beard"]:
		if kw in bn:
			return true
	return false


func _subtree_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var wa: AABB = mi.global_transform * mi.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged


# ---------------- native hero_model (world.json "hero_model") ----------------

# A world-level "hero_model" wears a real character GLB in place of the placeholder capsule — the
# NATIVE form of the _build_player recipe. The GLB is fetched (same GLTFDocument.append_from_buffer
# idiom as area_builder), scaled to the capsule height, feet-seated, and idle-autoplayed. GUARDS:
#  (a) a builder that already wired an avatar the documented way (ANY Skeleton3D under the player)
#      wins — we skip; (b) a single fetch RETRY (saltwind QA P1) before degrading to the capsule.
# Relative paths resolve through _norm, exactly like vehicle/weapon model URLs.
func _attach_hero_model() -> void:
	if player == null:
		return
	var hero := String(world_data.get("hero_model", ""))
	if hero == "":
		return
	if not player.find_children("*", "Skeleton3D", true, false).is_empty():
		print("GOGI_HERO builder-wired avatar detected — native attach skipped")
		return
	var url := _norm(hero)
	if url == "":
		return
	# Retry the fetch with backoff — a transient GLB fetch failure must not strand the player as the
	# placeholder capsule (no skeleton -> the weapon can't attach to a hand and floats, and there are
	# no body anims). ~4 attempts before degrading.
	var node: Node3D = null
	for attempt in range(4):
		node = await _fetch_glb_scene(url)
		if node != null:
			break
		await get_tree().create_timer(0.4).timeout
	if node == null:
		return
	node.name = "GogiHeroAvatar"
	player.add_child(node)
	_hero_avatar = node
	# Meshy characters carry a 0.01-scale Armature over a cm-unit skeleton, so the MESH AABB is
	# unreliable (near-zero) — measure a rigged character by its skeleton REST bounds instead and
	# fall back to the mesh AABB only for unrigged models.
	var h := _char_height(node)
	if h > 0.05:
		node.scale *= HERO_HEIGHT / h
	else:
		var ab := _subtree_aabb(node)
		if ab.size.y > 0.001:
			node.scale *= HERO_HEIGHT / ab.size.y   # size to the capsule (~1.65 m tall)
	_seat_avatar(node)                           # skeleton-aware: feet (not dangling cloth) to y=0
	if _capsule_body != null and is_instance_valid(_capsule_body):
		_capsule_body.visible = false            # the placeholder body gives way to the avatar
	_play_hero_idle(node)
	print("GOGI_HERO native avatar attached (char_h=%.3f)" % h)


# Height of a RIGGED character = its skeleton's global-rest bone span scaled by the cumulative
# node scale up to `node` (Meshy: cm-unit bones under a 0.01 Armature -> ~1.74m). 0.0 = no rig.
func _char_height(node: Node3D) -> float:
	var sks := node.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return 0.0
	var s := sks[0] as Skeleton3D
	if s.get_bone_count() == 0:
		return 0.0
	var lo := 1e9
	var hi := -1e9
	for i in s.get_bone_count():
		var gy := s.get_bone_global_rest(i).origin.y
		lo = minf(lo, gy)
		hi = maxf(hi, gy)
	if hi <= lo:
		return 0.0
	var sc := 1.0
	var walker: Node = s
	while walker != null and walker != node and walker is Node3D:
		sc *= (walker as Node3D).scale.y
		walker = walker.get_parent()
	return (hi - lo) * sc


# Fetch a GLB by absolute URL -> instanced scene root (null on any failure). Mirrors the builder's
# parse path (append_from_buffer -> generate_scene); the caller owns the single retry.
func _fetch_glb_scene(url: String) -> Node3D:
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return null
	var res = await req.request_completed
	req.queue_free()
	if res[1] != 200:
		return null
	var buf := res[3] as PackedByteArray
	if buf.is_empty():
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_buffer(buf, "", st) != OK:
		return null
	return doc.generate_scene(st) as Node3D


# Autoplay the hero's idle so it isn't a frozen A-pose. A model that EMBEDS clips (Meshy/library
# creature) plays its own; a clipless KayKit Rig_Medium retargets from the packed kk_rig_medium_*
# libraries via AnimRig (the enemy.gd / crowd idiom). Silent no-op when neither yields a clip.
func _play_hero_idle(node: Node3D) -> void:
	var ap := AnimRig._find_ap(node)
	if ap == null or ap.get_animation_list().is_empty():
		# retarget a FULLER clip set so the hero idles / walks / runs / attacks instead of freezing
		# on a single idle pose. Aliases whose source clip is missing are simply skipped by AnimRig,
		# and _play_hero degrades run->walk->idle, so a thinner library still animates.
		ap = AnimRig.attach(node, {
			"idle": "Idle_A", "walk": "Walking_A", "run": "Running_A",
			"attack": "Melee_1H_Attack_Chop",
			"jump": "Jump_Full_Short", "fall": "Jump_Idle",
		}, ["idle", "walk", "run", "fall"])
	if ap == null or ap.get_animation_list().is_empty():
		return
	_hero_ap = ap
	_hero_anim = ""
	_hero_attack_t = 0.0
	_play_hero("idle")


# Resolve a semantic anim kind (idle/walk/run/attack) to a real clip on the hero's AnimationPlayer —
# works for BOTH the retargeted alias set (exact name) and a model that embeds its OWN clips
# (substring match), so library AND Meshy creature avatars animate. "" = no such clip.
func _resolve_hero_clip(kind: String) -> String:
	if _hero_ap == null or not is_instance_valid(_hero_ap):
		return ""
	if _hero_ap.has_animation(kind):
		return kind
	var keys: Array = {
		"idle": ["idle"], "walk": ["walk"],
		"run": ["run", "sprint", "jog"],
		"jump": ["jump", "leap"],
		"fall": ["fall", "jump_idle", "air"],
		"attack": ["attack", "melee", "chop", "slash", "punch", "strike"],
	}.get(kind, [kind])
	for c in _hero_ap.get_animation_list():
		var cl := String(c).to_lower()
		for k in keys:
			if k in cl:
				return String(c)
	return ""


# Switch the hero to a semantic anim with a short crossfade. Falls back run->walk->idle so a rig
# missing a clip animates instead of snapping to a frozen pose.
func _play_hero(kind: String) -> void:
	if _hero_ap == null or not is_instance_valid(_hero_ap) or kind == _hero_anim:
		return
	var clip := _resolve_hero_clip(kind)
	if clip == "" and kind == "run":
		clip = _resolve_hero_clip("walk")
	if clip == "" and kind != "idle":
		clip = _resolve_hero_clip("idle")
	if clip == "":
		return
	_hero_anim = kind
	_hero_ap.play(clip, 0.15)


# Per-frame hero animation state machine (on foot only — a seated/mounted rider is posed by GPose).
# The attack clip plays out its window uninterrupted; otherwise moving -> run (walk fallback),
# still -> idle.
func _update_hero_anim(delta: float) -> void:
	if _hero_ap == null or not is_instance_valid(_hero_ap):
		return
	if active_vehicle != null and is_instance_valid(active_vehicle):
		return
	_hero_attack_t = maxf(0.0, _hero_attack_t - delta)
	if _hero_attack_t > 0.0:
		return   # let the swing clip / a one-shot action finish before locomotion resumes
	if player != null and is_instance_valid(player) and not player.is_on_floor():
		_play_hero("jump" if player.velocity.y > 0.5 else "fall")   # rising = jump, descending/apex = fall
		return
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	if spd > 3.0:
		_play_hero("run")
	elif spd > 0.3:
		_play_hero("walk")
	else:
		_play_hero("idle")


# Play a one-shot ACTION / emote clip on the hero (dance, wave, cheer, sit, taunt, …) then auto-return
# to locomotion after `hold` seconds. `clip` is any clip NAME on the rig OR a semantic key
# _resolve_hero_clip understands. This is the hook that lets the game give the character ALL types of
# animations beyond the built-in idle/walk/run/jump/attack set — call it on any event.
func _play_hero_action(clip: String, hold := 1.2) -> void:
	if _hero_ap == null or not is_instance_valid(_hero_ap):
		return
	var resolved := _resolve_hero_clip(clip)
	if resolved == "" and _hero_ap.has_animation(clip):
		resolved = clip
	if resolved == "":
		return
	_hero_attack_t = hold   # reuse the "don't override locomotion" gate for the action's duration
	_hero_anim = "action"
	_hero_ap.play(resolved, 0.15)


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	stats = Label.new()
	stats.position = Vector2(12, 12)
	stats.add_theme_font_size_override("font_size", 22)
	stats.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	hud_layer.add_child(stats)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.5)
	bg.position = Vector2(12, 112)
	bg.size = Vector2(220, 14)
	hud_layer.add_child(bg)
	hp_bar = ColorRect.new()
	hp_bar.color = Color(0.85, 0.25, 0.25)
	hp_bar.position = Vector2(12, 112)
	hp_bar.size = Vector2(220, 14)
	hud_layer.add_child(hp_bar)
	# full-screen red flash for damage feedback (starts transparent; _flash_hurt pulses it). Ignores
	# mouse so it never eats a HUD button press, and it's non-modal — just juice, no popup.
	var vp := get_viewport().get_visible_rect().size
	_hud_btns["attack"] = _button("ATTACK", vp - Vector2(250, 180), Vector2(220, 130), _attack)
	_hud_btns["use"] = _button("USE", vp - Vector2(250, 330), Vector2(220, 120), func() -> void: interaction.try_use())
	_hud_btns["potion"] = _button("POTION", vp - Vector2(490, 180), Vector2(220, 130), func() -> void: rpg.use_potion())
	_weapon_btn = _button("SHEATHE", vp - Vector2(490, 330), Vector2(220, 120), _toggle_weapon)
	_hud_btns["weapon"] = _weapon_btn
	# JUMP in the RIGHT thumb column (720-wide portrait base: x=vp-250 keeps it on-screen and OUT of the
	# left-half movement joystick — the old x=vp-730 fell off the left edge on mobile).
	_hud_btns["jump"] = _button("JUMP", vp - Vector2(250, 480), Vector2(220, 130), func() -> void: _jump_queued = true)
	# GET-OFF: a dedicated, discoverable dismount control. Exit was bound to USE with NO on-screen
	# affordance, so riders had no way to know how to get off any vehicle/mount. This button is hidden
	# on foot and shown the moment you board (toggled in _on_vehicle_drive_state); it calls the same
	# guarded exit() every profile uses (flight requests a braked descent-then-dismount, so it's safe
	# mid-air too).
	_dismount_btn = _button("DISMOUNT", vp - Vector2(490, 480), Vector2(220, 130), func() -> void:
		if active_vehicle != null and is_instance_valid(active_vehicle):
			active_vehicle.exit())
	_dismount_btn.visible = false
	_hud_btns["dismount"] = _dismount_btn
	_hud_btns["stable"] = _button("STABLE", Vector2(vp.x - 250, 12), Vector2(220, 90),
		func() -> void:
			if director != null:
				director.toggle_stable_panel())
	_relayout_ui()


# The design base is PORTRAIT 720x1280 with aspect EXPAND, which scales the UI by the WIDTH
# ratio — a LANDSCAPE phone (e.g. 860x400) therefore renders the whole UI at ~0.31x design
# scale (7px stats text, 41px-tall buttons). Rescale from the SHORT side instead so text and
# buttons keep their designed physical size at any orientation.
func _fit_ui_scale() -> void:
	var win := get_window()
	var sz: Vector2 = Vector2(win.size)
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	# content_scale_factor MULTIPLIES the automatic expand scale (min of the per-axis ratios),
	# so apply the ratio between the wanted short-side scale and the automatic one.
	var auto_scale := minf(sz.x / 720.0, sz.y / 1280.0)
	if auto_scale <= 0.0:
		return
	win.content_scale_factor = (minf(sz.x, sz.y) / 720.0) / auto_scale


# Reposition the HUD against the LIVE (expanded) viewport — called on every window resize /
# rotation so portrait AND landscape phones get on-screen controls (never a stale base rect).
func _relayout_ui() -> void:
	_fit_ui_scale()
	if hud_layer == null or _hud_btns.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var bw := clampf(vp.x * 0.28, 150.0, 230.0)         # button width scales with the screen
	var bh := clampf(vp.y * 0.13, 84.0, 130.0)
	var m := 18.0
	for k in _hud_btns:
		var b: Button = _hud_btns[k]
		if b == null or not is_instance_valid(b):
			continue
		b.size = Vector2(bw, bh)
	(_hud_btns["attack"] as Button).position = Vector2(vp.x - bw - m, vp.y - bh - m - 40.0)
	(_hud_btns["use"] as Button).position = Vector2(vp.x - bw - m, vp.y - 2.0 * bh - 2.0 * m - 40.0)
	(_hud_btns["jump"] as Button).position = Vector2(vp.x - bw - m, vp.y - 3.0 * bh - 3.0 * m - 40.0)
	(_hud_btns["potion"] as Button).position = Vector2(vp.x - 2.0 * bw - 2.0 * m, vp.y - bh - m - 40.0)
	(_hud_btns["dismount"] as Button).position = Vector2(vp.x - 2.0 * bw - 2.0 * m, vp.y - 3.0 * bh - 3.0 * m - 40.0)
	(_hud_btns["weapon"] as Button).position = Vector2(vp.x - 2.0 * bw - 2.0 * m, vp.y - 2.0 * bh - 2.0 * m - 40.0)
	(_hud_btns["stable"] as Button).position = Vector2(vp.x - bw - m, 158.0)   # below the stats block
	(_hud_btns["stable"] as Button).size = Vector2(bw, clampf(bh * 0.6, 54.0, 78.0))


func _button(text: String, pos: Vector2, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 28)
	b.position = pos
	b.size = sz
	b.pressed.connect(cb)
	hud_layer.add_child(b)
	return b


# HUD draw/holster: flip the weapon between DRAWN (in hand) and SHEATHED (hidden). The button label
# tracks state; attacking auto-draws (see _attack), so a sheathed weapon never blocks combat.
func _toggle_weapon() -> void:
	_set_weapon_stowed(not _weapon_stowed)
	if _weapon_btn != null and is_instance_valid(_weapon_btn):
		_weapon_btn.text = "DRAW" if _weapon_stowed else "SHEATHE"
