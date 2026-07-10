class_name VerdanceDirector extends Node
## VERDANCE game director — everything above the engine template:
##  - title screen (FREE ROAM / CAMPAIGN / CONTINUE) + input gating
##  - the four Reaches: region detection, per-region weather + ambient beds, discovery toasts
##  - a real day/night cycle layered over region weather (2-seg cross-fade trick)
##  - Beacons: relight interactables + FX, the Spire Core finale, victory sequence
##  - mount TAMING + the stable (summon panel)
##  - campaign quest chain + an objective compass
##  - Supabase persistence (SaveSystem) of the whole player state

const DAY_CYCLE: Array = [["day", 170.0], ["sunset", 50.0], ["night", 120.0], ["sunrise", 50.0]]
const AMBIENTS := {
	"forest": "res://audio/amb_forest.ogg",
	"lake": "res://audio/amb_lake.ogg",
	"city": "res://audio/amb_city.ogg",
	"frostpeak": "res://audio/amb_frost.ogg",
}

var main: Node3D
var rpg: RpgState
var quest: QuestSystem
var saver: SaveSystem
var title: TitleScreen

var mode := ""                       # "" until chosen -> input locked
var stable: Array = []               # tamed mount stable_ids
var discovered: Array = []           # region ids seen at least once
var campaign_idx := 0                # index into the quest chain
var _chain: Array = []               # quest ids in order

var _regions: Array = []             # {id,name,bbox,weather}
var _beacons: Array = []             # {id,name,pos,flag,shard,requires,fx,label}
var _cur_region := ""
var _wx_t := "day"                   # last-applied time/weather (fade-from state)
var _wx_w := "clear"
var _day_idx := 0
var _day_t := 0.0
var _victory := false
var _victory_shown := false
var _granted_toast := false
var _world_ready := false
var _saved_blob: Dictionary = {}
var _restore_pending := false

var _toast: Label
var _compass: Label
var _region_lbl: Label
var _stable_panel: PanelContainer = null
var _toast_q: Array = []
var _toast_busy := false
var _js_verdance_cb = null
var _js_tp_cb = null
var _js_use_cb = null
var _js_attack_cb = null
var _js_mode_cb = null
var _js_inject_cb = null


func setup(m: Node3D) -> void:
	main = m
	rpg = m.rpg
	quest = m.quest
	saver = SaveSystem.new()
	add_child(saver)
	title = TitleScreen.new()
	add_child(title)
	title.mode_chosen.connect(_on_mode)
	_build_overlay_ui()
	quest.objective_changed.connect(_on_objective_changed)
	var t := Timer.new()
	t.wait_time = 10.0
	t.autostart = true
	t.timeout.connect(_autosave)
	add_child(t)
	var rt := Timer.new()
	rt.wait_time = 0.8
	rt.autostart = true
	rt.timeout.connect(_region_tick)
	add_child(rt)
	_fetch_save()


func input_locked() -> bool:
	return mode == ""


func _fetch_save() -> void:
	var blob: Dictionary = await saver.load_save()
	if not blob.is_empty() and String(blob.get("mode", "")) != "":
		_saved_blob = blob
		if mode == "" and title != null and is_instance_valid(title):
			var lbl := "CAMPAIGN" if String(blob.get("mode", "")) == "campaign" else "FREE ROAM"
			title.enable_continue(lbl)


## Called by main._boot AFTER chunk_manager.start() — terrain + vehicles exist now.
func world_ready() -> void:
	_world_ready = true
	_parse_regions()
	_build_beacons()
	_wire_tame_hooks()
	_setup_js_hook()
	_apply_wx(true)
	if _restore_pending:
		_apply_world_restore()
	# a mode picked BEFORE the world finished streaming re-runs its grants now that
	# weapons/vehicles/quests exist (both paths are idempotent)
	if mode == "free":
		_grant_all()
	elif mode == "campaign" and _chain.is_empty():
		_start_campaign()
	# ?mode=free|campaign deep-link: jump straight into gameplay (verify/QA + shareable links)
	if mode == "" and OS.has_feature("web"):
		var m = JavaScriptBridge.eval("(new URLSearchParams(window.location.search)).get('mode') || ''", true)
		var ms := String(m) if typeof(m) == TYPE_STRING else ""
		if ms == "free" or ms == "campaign":
			_on_mode(ms)


# ---------------- mode selection ----------------

func _on_mode(m: String) -> void:
	if mode != "":
		return
	if m == "continue":
		mode = String(_saved_blob.get("mode", "free"))
		_restore(_saved_blob)
	else:
		mode = m
		if m == "free":
			_grant_all()
		elif m == "campaign":
			_start_campaign()
	title.visible = false
	title.queue_free()
	main.hud_layer.visible = true
	AudioManager.play_music(load("res://audio/music_main.ogg"))
	if _cur_region != "" and AMBIENTS.has(_cur_region):
		AudioManager.play_ambient(load(String(AMBIENTS[_cur_region])))
	_save_now()


func _start_campaign() -> void:
	_chain = []
	for q in main.quests_data.get("quests", []):
		_chain.append(String(q.get("id", "")))
	campaign_idx = 0
	if _chain.size() > 0:
		quest.start(_chain[0])
		toast("The Fade spreads. Relight the four Beacons, Warden.")


func _grant_all() -> void:
	# every weapon in hand, every mount tamed, the whole world open (idempotent — re-run
	# once the world finishes loading if the mode was picked early)
	var best_id := ""
	var best_dmg := -1.0
	for id in rpg.weapons:
		if not rpg.has_item(String(id)):
			rpg.add_item(String(id))
		var d := float(rpg.weapon_def(String(id)).get("damage", 1.0))
		if d > best_dmg:
			best_dmg = d
			best_id = String(id)
	if best_id != "":
		rpg.equip(best_id, true)
	for spec in _mount_specs():
		var sid := String(spec.get("stable_id", ""))
		if sid != "" and not stable.has(sid):
			stable.append(sid)
	_rename_tamed()
	if not _granted_toast:
		_granted_toast = true
		toast("Free Roam: the Four Reaches are open. Every mount answers you.")


# ---------------- campaign chain ----------------

func _on_objective_changed() -> void:
	if mode != "campaign" or _chain.is_empty() or campaign_idx >= _chain.size():
		return
	var cur: String = _chain[campaign_idx]
	if quest.st.has(cur) and String(quest.st[cur].status) == "done":
		campaign_idx += 1
		AudioManager.play_sfx("pickup", 0.0, 1.3)
		if campaign_idx < _chain.size():
			var nid: String = _chain[campaign_idx]
			toast("Quest complete!  Next: " + String(quest.defs[nid].get("name", nid)))
			quest.start(nid)
		_save_now()


# ---------------- regions / weather / day-night ----------------

func _parse_regions() -> void:
	_regions = []
	for r in main.world_data.get("regions", []):
		if r is Dictionary:
			_regions.append(r)


func _region_tick() -> void:
	if not _world_ready or main.player == null:
		return
	var gx := floori(main.player.global_position.x / 16.0)
	var gz := floori(main.player.global_position.z / 16.0)
	var found := ""
	var fname := ""
	for r in _regions:
		var bb: Array = r.get("bbox", [])
		if bb.size() >= 4 and gx >= int(bb[0]) and gz >= int(bb[1]) and gx <= int(bb[2]) and gz <= int(bb[3]):
			found = String(r.get("id", ""))
			fname = String(r.get("name", found))
			break
	if found == "" or found == _cur_region:
		return
	_cur_region = found
	if _region_lbl != null:
		_region_lbl.text = fname.to_upper()
	if not discovered.has(found):
		discovered.append(found)
		toast(fname + "  --  discovered!")
		AudioManager.play_sfx("pickup", -2.0, 1.5)
		_save_now()
	else:
		toast("Entering " + fname)
	if mode != "" and AMBIENTS.has(found):
		AudioManager.play_ambient(load(String(AMBIENTS[found])))
	_apply_wx(false)


func _process(delta: float) -> void:
	if mode == "":
		return
	_day_t += delta
	var seg: Array = DAY_CYCLE[_day_idx]
	if _day_t >= float(seg[1]):
		_day_t = 0.0
		_day_idx = (_day_idx + 1) % DAY_CYCLE.size()
		_apply_wx(false)
	_update_compass()


func _region_weather() -> String:
	if _victory:
		return "clear"
	for r in _regions:
		if String(r.get("id", "")) == _cur_region:
			return String(r.get("weather", "clear"))
	return "clear"


func _apply_wx(snap: bool) -> void:
	if main.weather == null:
		return
	var t := String(DAY_CYCLE[_day_idx][0])
	if _victory:
		t = "day"
	var w := _region_weather()
	if snap:
		main.weather.apply({"time": t, "weather": w})
	else:
		# 2-segment cycle: hold the CURRENT state briefly, then cross-fade (~3.3s) into the new
		# one — a bare apply({time,weather}) snaps, which reads as a lighting glitch mid-play.
		main.weather.apply({"loop": false, "cycle": [
			{"time": _wx_t, "weather": _wx_w, "seconds": 2.0},
			{"time": t, "weather": w, "seconds": 600000.0},
		]})
	_wx_t = t
	_wx_w = w


# ---------------- beacons ----------------

func _build_beacons() -> void:
	var terrain = main.chunk_manager.terrain
	for b in main.world_data.get("beacons", []):
		if not (b is Dictionary):
			continue
		var pos: Array = b.get("pos", [])
		if pos.size() < 2:
			continue
		var x := float(pos[0])
		var z := float(pos[1])
		var y := 0.0
		if terrain != null:
			y = float(terrain.height(x, z))
		y += float(b.get("y_off", 0.0))   # e.g. the Spire Core stabilize point on the top floor
		var entry := {
			"id": String(b.get("id", "")),
			"name": String(b.get("name", "Beacon")),
			"flag": String(b.get("flag", "")),
			"shard": String(b.get("shard", "")),
			"requires": b.get("requires", []),
			"pos": Vector3(x, y, z),
		}
		var fx := _beacon_fx_node(entry)
		main.add_child(fx)
		fx.global_position = entry["pos"]
		entry["fx"] = fx
		_beacons.append(entry)
		var use_label := "Relight " + String(entry["name"])
		if entry["id"] == "core":
			use_label = "Stabilize the Spire Core"
		main.interaction.add_action(Vector3(x, y, z), use_label, _use_beacon.bind(entry))
		_set_beacon_lit(entry, rpg.has_flag(String(entry["flag"])), false)


func _beacon_fx_node(_entry: Dictionary) -> Node3D:
	var root := Node3D.new()
	# UNLIT: grey ash motes drifting down — the Fade clinging to the beacon
	var unlit := Node3D.new()
	unlit.name = "Unlit"
	var ash := CPUParticles3D.new()
	ash.amount = 24
	ash.lifetime = 3.0
	ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	ash.emission_sphere_radius = 2.2
	ash.direction = Vector3(0, -1, 0)
	ash.initial_velocity_min = 0.2
	ash.initial_velocity_max = 0.6
	ash.gravity = Vector3.ZERO
	ash.scale_amount_min = 0.12
	ash.scale_amount_max = 0.3
	ash.color = Color(0.45, 0.45, 0.5, 0.6)
	ash.position.y = 3.0
	unlit.add_child(ash)
	root.add_child(unlit)
	# LIT: a tall teal light-beam + rising sparks + a real light
	var lit := Node3D.new()
	lit.name = "Lit"
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.8
	cyl.height = 40.0
	beam.mesh = cyl
	beam.position.y = 20.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(0.15, 0.7, 0.62, 0.5)
	bm.emission_enabled = true
	bm.emission = Color(0.3, 1.0, 0.9)
	bm.emission_energy_multiplier = 2.0
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lit.add_child(beam)
	var sparks := CPUParticles3D.new()
	sparks.amount = 40
	sparks.lifetime = 2.2
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 1.4
	sparks.direction = Vector3(0, 1, 0)
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.gravity = Vector3(0, 1.5, 0)
	sparks.scale_amount_min = 0.08
	sparks.scale_amount_max = 0.22
	sparks.color = Color(0.5, 1.0, 0.9)
	sparks.position.y = 2.0
	lit.add_child(sparks)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.4, 1.0, 0.9)
	lamp.light_energy = 2.4
	lamp.omni_range = 16.0
	lamp.position.y = 4.0
	lit.add_child(lamp)
	root.add_child(lit)
	return root


func _set_beacon_lit(entry: Dictionary, lit: bool, fanfare: bool) -> void:
	var fx: Node3D = entry.get("fx")
	if fx == null or not is_instance_valid(fx):
		return
	(fx.get_node("Unlit") as Node3D).visible = not lit
	(fx.get_node("Lit") as Node3D).visible = lit
	if fanfare:
		var burst := CPUParticles3D.new()
		burst.one_shot = true
		burst.explosiveness = 1.0
		burst.amount = 80
		burst.lifetime = 1.6
		burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		burst.emission_sphere_radius = 0.8
		burst.initial_velocity_min = 6.0
		burst.initial_velocity_max = 12.0
		burst.gravity = Vector3(0, -4, 0)
		burst.scale_amount_min = 0.1
		burst.scale_amount_max = 0.35
		burst.color = Color(0.55, 1.0, 0.92)
		burst.position.y = 2.5
		fx.add_child(burst)
		burst.emitting = true
		var tw := burst.create_tween()
		tw.tween_interval(2.2)
		tw.tween_callback(burst.queue_free)
		_shake_cam(0.35)


func _use_beacon(entry: Dictionary) -> void:
	var flag := String(entry["flag"])
	if rpg.has_flag(flag):
		toast(String(entry["name"]) + " already burns bright.")
		return
	var reqs: Array = entry.get("requires", [])
	for r in reqs:
		if not rpg.has_flag(String(r)):
			toast("The Core is dormant -- all four Beacons must burn first.")
			return
	var shard := String(entry["shard"])
	if shard != "" and not rpg.has_item(shard):
		toast("The brazier is cold. It needs its Lightshard.")
		AudioManager.play_sfx("ui", -4.0, 0.8)
		return
	rpg.set_flag(flag)
	_set_beacon_lit(entry, true, true)
	AudioManager.play_sfx("door", 0.0, 1.4)
	AudioManager.play_sfx("pickup", 0.0, 0.7)
	if String(entry["id"]) == "core":
		_do_victory()
	else:
		toast(String(entry["name"]) + " relit!  The Fade recoils.")
	rpg.grant_xp(60)
	_save_now()


func _do_victory() -> void:
	_victory = true
	_apply_wx(false)   # daylight + clear weather flood back
	if _victory_shown:
		return
	_victory_shown = true
	AudioManager.play_music(load("res://audio/music_victory.ogg"))
	var lay := CanvasLayer.new()
	lay.layer = 40
	main.add_child(lay)
	var gold := ColorRect.new()
	gold.color = Color(1.0, 0.9, 0.55, 0.0)
	gold.set_anchors_preset(Control.PRESET_FULL_RECT)
	gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(gold)
	var gt := gold.create_tween()
	gt.tween_property(gold, "color:a", 0.75, 0.8)
	gt.tween_property(gold, "color:a", 0.0, 2.4)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	lay.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var big := Label.new()
	big.text = "VERDANCE RESTORED"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override("font_size", 60)
	big.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	box.add_child(big)
	var sub := Label.new()
	sub.text = "The four Beacons burn. Color and daylight return to the Reaches."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	box.add_child(sub)
	var btn := Button.new()
	btn.text = "KEEP EXPLORING"
	btn.custom_minimum_size = Vector2(340, 72)
	btn.add_theme_font_size_override("font_size", 26)
	box.add_child(btn)
	btn.pressed.connect(func() -> void: lay.queue_free())
	_shake_cam(0.5)


func _shake_cam(strength: float) -> void:
	var camn: Camera3D = main.cam
	if camn == null:
		return
	var tw := camn.create_tween()
	for i in 5:
		var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * strength * (1.0 - i / 5.0)
		tw.tween_property(camn, "position", off, 0.05)
	tw.tween_property(camn, "position", Vector3.ZERO, 0.06)


# ---------------- taming + stable ----------------

func _mount_specs() -> Array:
	var out: Array = []
	for v in main.vehicles:
		if is_instance_valid(v) and (v as Vehicle).is_mount() and v.has_meta("spec"):
			out.append(v.get_meta("spec"))
	return out


func _wire_tame_hooks() -> void:
	for v in main.vehicles:
		if is_instance_valid(v):
			(v as Vehicle).drive_state_changed.connect(_on_ride_state)
	_rename_tamed()


func _on_ride_state(v: Vehicle, is_driving: bool) -> void:
	if not is_driving or not v.is_mount() or not v.has_meta("spec"):
		return
	var spec: Dictionary = v.get_meta("spec")
	var sid := String(spec.get("stable_id", ""))
	if sid == "" or stable.has(sid):
		return
	stable.append(sid)
	v.display_name = String(spec.get("tamed_name", v.display_name.replace("Wild ", "")))
	rpg.set_flag("tamed_a_mount")
	rpg.grant_xp(25)
	AudioManager.play_sfx("pickup", 0.0, 1.2)
	toast("Tamed " + v.display_name + "!  Added to your stable.")
	var hearts := CPUParticles3D.new()
	hearts.one_shot = true
	hearts.explosiveness = 1.0
	hearts.amount = 24
	hearts.lifetime = 1.2
	hearts.initial_velocity_min = 2.0
	hearts.initial_velocity_max = 4.0
	hearts.direction = Vector3(0, 1, 0)
	hearts.gravity = Vector3(0, -2, 0)
	hearts.scale_amount_min = 0.1
	hearts.scale_amount_max = 0.25
	hearts.color = Color(0.55, 1.0, 0.8)
	v.add_child(hearts)
	hearts.position.y = 1.5
	hearts.emitting = true
	var tw := hearts.create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(hearts.queue_free)
	_save_now()


func _rename_tamed() -> void:
	for v in main.vehicles:
		if is_instance_valid(v) and v.has_meta("spec"):
			var spec: Dictionary = v.get_meta("spec")
			var sid := String(spec.get("stable_id", ""))
			if sid != "" and stable.has(sid):
				(v as Vehicle).display_name = String(spec.get("tamed_name", (v as Vehicle).display_name.replace("Wild ", "")))


func toggle_stable_panel() -> void:
	if _stable_panel != null and is_instance_valid(_stable_panel):
		_stable_panel.queue_free()
		_stable_panel = null
		return
	_stable_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.11, 0.1, 0.94)
	sb.border_color = Color(0.3, 0.65, 0.58)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	_stable_panel.add_theme_stylebox_override("panel", sb)
	_stable_panel.set_anchors_preset(Control.PRESET_CENTER)
	main.hud_layer.add_child(_stable_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_stable_panel.add_child(box)
	var head := Label.new()
	head.text = "YOUR STABLE  --  tap to call"
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", Color(0.5, 0.95, 0.85))
	box.add_child(head)
	if stable.is_empty():
		var none := Label.new()
		none.text = "No mounts tamed yet.\nWalk up to a wild creature and RIDE it to tame it."
		none.add_theme_font_size_override("font_size", 18)
		box.add_child(none)
	for v in main.vehicles:
		if not is_instance_valid(v) or not v.has_meta("spec"):
			continue
		var spec: Dictionary = v.get_meta("spec")
		var sid := String(spec.get("stable_id", ""))
		if sid == "" or not stable.has(sid):
			continue
		var b := Button.new()
		b.text = "CALL  " + String(spec.get("tamed_name", sid.capitalize()))
		b.custom_minimum_size = Vector2(320, 56)
		b.add_theme_font_size_override("font_size", 22)
		box.add_child(b)
		b.pressed.connect(_summon.bind(v))
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(320, 48)
	close.add_theme_font_size_override("font_size", 20)
	box.add_child(close)
	close.pressed.connect(toggle_stable_panel)


func _summon(v: Vehicle) -> void:
	if not is_instance_valid(v):
		return
	if main.active_vehicle != null:
		toast("Dismount first.")
		return
	var fwd: Vector3 = Basis(Vector3.UP, main.cam_yaw) * Vector3(0, 0, -4.0)
	var p: Vector3 = main.player.global_position + fwd
	if main.chunk_manager != null:
		p = main.chunk_manager.nudge_out(p, 2.5)
		if main.chunk_manager.terrain != null:
			p.y = float(main.chunk_manager.terrain.height(p.x, p.z)) + 0.4
	v.global_position = p
	AudioManager.play_sfx("ui", 0.0, 1.4)
	toast(v.display_name + " answers your call.")
	toggle_stable_panel()


# ---------------- HUD extras (toast / compass / region) ----------------

func _build_overlay_ui() -> void:
	_region_lbl = Label.new()
	_region_lbl.text = ""
	_region_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_lbl.add_theme_font_size_override("font_size", 20)
	_region_lbl.add_theme_color_override("font_color", Color(0.55, 0.9, 0.82, 0.9))
	_region_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_region_lbl.offset_top = 118.0   # below the compact stats block + hp bar (no top-strip collisions)
	main.hud_layer.add_child(_region_lbl)
	_compass = Label.new()
	_compass.text = ""
	_compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass.add_theme_font_size_override("font_size", 19)
	_compass.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.offset_top = 144.0
	main.hud_layer.add_child(_compass)
	_toast = Label.new()
	_toast.text = ""
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Color(0.95, 1.0, 0.9))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 200.0
	_toast.modulate.a = 0.0
	main.hud_layer.add_child(_toast)
	main.hud_layer.visible = false   # hidden behind the title screen until a mode is chosen


func toast(t: String) -> void:
	_toast_q.append(t)
	if not _toast_busy:
		_next_toast()


func _next_toast() -> void:
	if _toast_q.is_empty():
		_toast_busy = false
		return
	_toast_busy = true
	_toast.text = String(_toast_q.pop_front())
	_toast.modulate.a = 0.0
	var tw := _toast.create_tween()
	tw.tween_property(_toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.45)
	tw.tween_callback(_next_toast)


func _update_compass() -> void:
	if _compass == null:
		return
	if mode != "campaign" or _chain.is_empty() or campaign_idx >= _chain.size():
		_compass.text = ""
		return
	var qid: String = _chain[campaign_idx]
	if not quest.defs.has(qid) or String(quest.st[qid].status) != "active":
		_compass.text = ""
		return
	var qdef: Dictionary = quest.defs[qid]
	for step in qdef.get("steps", []):
		if not (step is Dictionary):
			continue
		if quest._step_done(qid, step.get("objective", {})):
			continue
		var tgt: Array = step.get("target", [])
		var line := String(step.get("desc", ""))
		if tgt.size() >= 2 and main.player != null:
			var to: Vector3 = Vector3(float(tgt[0]), 0.0, float(tgt[1])) - (main.player as Node3D).global_position
			to.y = 0.0
			var dist := int(to.length())
			var comp := _compass_dir(to)
			line += "   [%s %dm]" % [comp, dist]
		_compass.text = "> " + line
		return
	_compass.text = ""


func _compass_dir(to: Vector3) -> String:
	var ang := rad_to_deg(atan2(to.x, -to.z))   # bearing: 0 = N (-Z), 90 = E (+X)
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx := int(round(fposmod(ang, 360.0) / 45.0)) % 8
	return dirs[idx]


# ---------------- persistence ----------------

func _autosave() -> void:
	if mode != "":
		_save_now()


func _save_now() -> void:
	if mode == "" or saver == null:
		return
	var p := Vector3.ZERO
	if main.player != null:
		p = main.player.global_position
	saver.save({
		"v": 1, "mode": mode,
		"pos": [p.x, p.y, p.z],
		"hp": rpg.hp, "max_hp": rpg.max_hp,
		"level": rpg.level, "xp": rpg.xp, "xp_next": rpg.xp_next,
		"gold": rpg.gold,
		"inventory": rpg.inventory,
		"equipped": rpg.equipped_weapon,
		"flags": rpg.flags,
		"stable": stable,
		"discovered": discovered,
		"campaign_idx": campaign_idx,
		"day_idx": _day_idx,
	})


func _restore(blob: Dictionary) -> void:
	rpg.hp = float(blob.get("hp", 100.0))
	rpg.max_hp = float(blob.get("max_hp", 100.0))
	rpg.level = int(blob.get("level", 1))
	rpg.xp = int(blob.get("xp", 0))
	rpg.xp_next = int(blob.get("xp_next", 30))
	rpg.gold = int(blob.get("gold", 0))
	var inv: Array = blob.get("inventory", [])
	if not inv.is_empty():
		rpg.inventory = inv.duplicate()
	var flags: Dictionary = blob.get("flags", {})
	for f in flags:
		if bool(flags[f]):
			rpg.flags[f] = true
	var eq := String(blob.get("equipped", ""))
	if eq != "" and rpg.has_item(eq):
		rpg.equip(eq, true)
	stable = blob.get("stable", []).duplicate()
	discovered = blob.get("discovered", []).duplicate()
	campaign_idx = int(blob.get("campaign_idx", 0))
	_day_idx = clampi(int(blob.get("day_idx", 0)), 0, DAY_CYCLE.size() - 1)
	rpg.changed.emit()
	if mode == "campaign":
		_chain = []
		for q in main.quests_data.get("quests", []):
			_chain.append(String(q.get("id", "")))
		for i in range(mini(campaign_idx, _chain.size())):
			if quest.st.has(_chain[i]):
				quest.st[_chain[i]].status = "done"
		if campaign_idx < _chain.size():
			quest.start(_chain[campaign_idx])
	if _world_ready:
		_apply_world_restore()
	else:
		_restore_pending = true
	toast("Welcome back, Warden.")


func _apply_world_restore() -> void:
	_restore_pending = false
	if _saved_blob.is_empty():
		return
	var pos: Array = _saved_blob.get("pos", [])
	if pos.size() >= 3 and main.player != null:
		main.player.global_position = Vector3(float(pos[0]), float(pos[1]) + 0.3, float(pos[2]))
	_rename_tamed()
	for entry in _beacons:
		_set_beacon_lit(entry, rpg.has_flag(String(entry["flag"])), false)
	var all_lit := not _beacons.is_empty()
	for entry in _beacons:
		if String(entry["id"]) != "core" and not rpg.has_flag(String(entry["flag"])):
			all_lit = false
	if rpg.has_flag("world_restored"):
		_victory = true
		_victory_shown = true   # don't replay the fanfare on load
	_apply_wx(true)


# ---------------- verify/QA hook ----------------

func _setup_js_hook() -> void:
	if not OS.has_feature("web"):
		return
	# NOTE: create_callback ARG marshalling works, but RETURN values do not — so state is
	# PUSHED into window.__gogiVerdance on a short timer and gogiVerdance() just reads it.
	_js_tp_cb = JavaScriptBridge.create_callback(_on_js_teleport)
	_js_use_cb = JavaScriptBridge.create_callback(_on_js_use)
	_js_attack_cb = JavaScriptBridge.create_callback(_on_js_attack)
	_js_mode_cb = JavaScriptBridge.create_callback(_on_js_mode)
	var win = JavaScriptBridge.get_interface("window")
	if win != null:
		win.gogiTeleport = _js_tp_cb      # QA/verify knob: gogiTeleport(x, z)
		win.gogiUse = _js_use_cb          # QA/verify knob: press USE
		win.gogiAttack = _js_attack_cb    # QA/verify knob: press ATTACK
		win.gogiChooseMode = _js_mode_cb  # QA/verify knob: gogiChooseMode("free"|"campaign"|"continue")
		_js_inject_cb = JavaScriptBridge.create_callback(_on_js_inject_save)
		win.gogiInjectSave = _js_inject_cb  # QA: replay a save blob (sandbox can't reach Supabase)
	JavaScriptBridge.eval(
		"window.gogiVerdance=function(){return window.__gogiVerdance||null;};", true)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_push_js_state)
	add_child(t)
	_push_js_state()


func _push_js_state() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.__gogiVerdance=" + _state_json() + ";", true)


func _on_js_teleport(args: Array) -> void:
	if args.size() < 2 or main.player == null:
		return
	var x := float(args[0])
	var z := float(args[1])
	var y := 2.0
	if main.chunk_manager != null and main.chunk_manager.terrain != null:
		y = float(main.chunk_manager.terrain.height(x, z)) + 0.4
	if args.size() >= 3:
		y = float(args[2])   # explicit height (QA: interior floors, rooftops)
	(main.player as Node3D).global_position = Vector3(x, y, z)
	print("GOGI_TP ", x, " ", z, " ", y)


func _on_js_use(_args: Array) -> void:
	if main.interaction != null:
		main.interaction.try_use()


func _on_js_attack(_args: Array) -> void:
	main._attack()


func _on_js_mode(args: Array) -> void:
	if args.size() >= 1:
		_on_mode(String(args[0]))


func _on_js_inject_save(args: Array) -> void:
	if args.size() < 1:
		return
	var parsed: Variant = JSON.parse_string(String(args[0]))
	if parsed is Dictionary:
		_saved_blob = parsed
		print("GOGI_SAVE_INJECTED")


func _state_json() -> String:
	var lit: Array = []
	for entry in _beacons:
		if rpg.has_flag(String(entry["flag"])):
			lit.append(String(entry["id"]))
	var alive := 0
	var near_hp := -1.0
	var near_d := 1e9
	if main.chunk_manager != null and main.player != null:
		for e in main.chunk_manager.enemies:
			if is_instance_valid(e) and not e.dead:
				alive += 1
				var d: float = (e as Node3D).global_position.distance_to((main.player as Node3D).global_position)
				if d < near_d:
					near_d = d
					near_hp = float(e.hp)
	var px := 0.0
	var py := 0.0
	var pz := 0.0
	var in_veh := false
	var veh_prof := ""
	if main.player != null:
		var pp: Vector3 = (main.player as Node3D).global_position
		px = pp.x
		py = pp.y
		pz = pp.z
	if main.active_vehicle != null and is_instance_valid(main.active_vehicle):
		in_veh = true
		veh_prof = String(main.active_vehicle.profile)
	var use_label := ""
	if main.interaction != null:
		var nit = main.interaction._nearest(2.9)
		if nit != null:
			use_label = String(nit.label)
	return JSON.stringify({
		"mode": mode, "title_open": input_locked(), "region": _cur_region,
		"dialog_open": main.interaction != null and bool(main.interaction.active),
		"talks": int(main.interaction.talks) if main.interaction != null else 0,
		"max_hp": rpg.max_hp,
		"use_label": use_label,
		"lit": lit, "stable": stable, "discovered": discovered,
		"campaign_idx": campaign_idx, "victory": _victory,
		"hp": rpg.hp, "gold": rpg.gold, "equipped": rpg.equipped_weapon,
		"inventory": rpg.inventory, "flags": rpg.flags.keys(),
		"enemies_alive": alive, "nearest_enemy_hp": near_hp, "nearest_enemy_d": near_d,
		"x": px, "y": py, "z": pz,
		"in_vehicle": in_veh, "vehicle_profile": veh_prof,
		"swimming": bool(main.swimming),
	})


## Called by main so a chosen mode routes through the director (choose_mode wrapper for tests)
func choose_mode(m: String) -> void:
	_on_mode(m)
