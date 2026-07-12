extends CharacterBody3D
## Enemy: CharacterBody3D + NavigationAgent3D chase with RVO avoidance so enemies ENCIRCLE
## the player (distinct slot angle per index) instead of clumping. Melee w/ cooldown,
## health, death. The streamed KayKit skeleton GLBs carry NO embedded clips, so the
## animations are RETARGETED from the packed kk_rig_medium_* libraries via AnimRig
## (anim_rig.gd) — see animation.md. Falls back to no-anim if those libs aren't packed.

var world: Node
var player: Node3D
var anim: AnimationPlayer
var agent: NavigationAgent3D
var mesh_root: Node3D

var hp := 120.0             # base pool. Raised from 90 for clearer multi-hit feel; combined with the
                            # per-hit cap in take_hit (a single blow can never exceed HIT_CAP_FRAC of
                            # hp_max) this GUARANTEES no weapon one-shots an enemy — always 2+ clean
                            # hits, regardless of weapon upgrades. Per-region/tier scaling: playbook #16.
var hp_max := 120.0         # spawn pool, captured in setup(); the never-one-shot cap is relative to it
const HIT_CAP_FRAC := 0.55  # a single hit removes at most this fraction of hp_max -> min 2 hits to kill
var speed := 3.3
var kind := "skeleton"      # reported on death -> kill_count quest match (honors cell.enemy_type)
var dead := false
var atk_cd := 0.0
var flash_t := 0.0
var slot_angle := 0.0       # distinct approach angle so enemies encircle, not clump
var surround_radius := 1.7
var attack_range := 2.0

var c_idle := ""
var c_walk := ""
var c_attack := ""
var c_die := ""
var c_hurt := ""
var hurt_t := 0.0           # brief flinch hold so locomotion doesn't override the hurt clip
var _cur := ""


const MAX_ENEMY_H := 3.0    # cap absurdly-large Meshy enemy models so a giant can't fill the frame ("monster popup" / full-screen mass); normal enemies are untouched. 4.0 still walled a portrait frame at melee range (gamefeel P1)
const CAM_FADE_NEAR := 1.6  # hide the enemy mesh when this close to the CAMERA so a body pressed against the lens can't wall the view
var body_h := 1.8           # model height after the MAX_ENEMY_H cap — the near-camera fade scales with it

func setup(p: Node3D, model: Node, w: Node, index := 0, total := 1, etype := "skeleton") -> void:
	player = p
	world = w
	kind = etype
	hp_max = hp   # capture spawn pool so the never-one-shot cap tracks any region/tier hp scaling
	collision_layer = 4   # enemy layer
	collision_mask = 1    # world only; RVO avoidance handles enemy separation
	floor_max_angle = deg_to_rad(55)   # match the player: climb steep terrain instead of stalling at 45°
	slot_angle = TAU * float(index) / float(max(1, total))
	speed = 3.0 + float(index % 4) * 0.3   # desync so they don't move as one blob

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.5
	cs.shape = cap
	cs.position.y = 0.75
	add_child(cs)

	agent = NavigationAgent3D.new()
	agent.radius = 0.55
	agent.height = 1.5
	agent.path_desired_distance = 0.6
	agent.target_desired_distance = 0.4
	agent.avoidance_enabled = true
	agent.neighbor_distance = 4.0
	agent.max_neighbors = 10
	agent.max_speed = speed
	add_child(agent)
	agent.velocity_computed.connect(_on_safe_velocity)

	if model:
		mesh_root = Node3D.new()
		add_child(mesh_root)
		mesh_root.add_child(model)
		# scale-normalize (#6): cap a giant Meshy enemy so it can't fill the screen when it attacks.
		# Only shrinks models taller than MAX_ENEMY_H, then re-grounds the feet — normal enemies untouched.
		if model is Node3D:
			var mab := _model_aabb(model as Node3D)
			if mab.size.y > MAX_ENEMY_H and mab.size.y > 0.01:
				var m3 := model as Node3D
				m3.scale *= MAX_ENEMY_H / mab.size.y
				mab = _model_aabb(m3)
				m3.position.y -= mab.position.y   # re-ground the shrunk model's base to the origin
			body_h = clampf(mab.size.y, 0.8, MAX_ENEMY_H)
		anim = _find_anim(model)
		if anim == null and model is Node3D:
			# Streamed KayKit skeletons ship with NO embedded clips — retarget from
			# the packed kk_rig_medium_* libraries (fetch them into res://models/).
			anim = AnimRig.attach(model as Node3D, {
				"idle": "Idle_A", "walk": "Walking_A",
				"attack": "Melee_1H_Attack_Chop", "death": "Death_A", "hurt": "Hit_A",
			}, ["idle", "walk"])
		_resolve_clips()
		_play(c_idle)
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.5
		mi.mesh = cm
		mi.position.y = 0.75
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.57, 0.6)   # neutral "loading" gray, not a jarring red — the model hot-swaps in when its fetch lands (#9)
		mi.material_override = m
		add_child(mi)
		mesh_root = mi
		print("GOGI_PLACEHOLDER enemy ", kind)   # verify.mjs asset-fail gate: a gray enemy box is visible


func _physics_process(delta: float) -> void:
	if dead or not is_instance_valid(player):
		return
	atk_cd = max(0.0, atk_cd - delta)
	flash_t = max(0.0, flash_t - delta)
	hurt_t = max(0.0, hurt_t - delta)

	var ppos: Vector3 = player.global_position
	var to: Vector3 = ppos - global_position
	to.y = 0.0
	var dist := to.length()
	var desired := Vector3.ZERO

	# attack when in range, INDEPENDENT of movement (so they don't stop and pile up)
	if dist <= attack_range and atk_cd <= 0.0:
		atk_cd = 1.3
		_play(c_attack, false)
		if player.has_method("take_damage"):
			player.call("take_damage", 9.0)
		elif is_instance_valid(world) and world.has_method("take_damage"):
			world.call("take_damage", 9.0)   # the code-built player body carries no script — main owns HP

	# ALWAYS seek a DISTINCT slot around the player -> enemies encircle, not bunch
	var slot := ppos + Vector3(cos(slot_angle), 0.0, sin(slot_angle)) * surround_radius
	agent.target_position = slot
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0.0
	if dir.length() < 0.05:   # fallback if navmesh path is degenerate
		dir = slot - global_position
		dir.y = 0.0
	_face(to)   # always look at the player while circling/attacking
	if dir.length() > 0.2:
		desired = dir.normalized() * speed
		if _cur != c_attack and hurt_t <= 0.0:   # keep moving, but let a hurt flinch play out
			_play(c_walk)
	elif _cur != c_attack and hurt_t <= 0.0:
		_play(c_idle)

	# feed desired velocity into RVO avoidance; actual move happens in the callback
	agent.set_velocity(desired)


func _on_safe_velocity(safe: Vector3) -> void:
	if dead:
		return
	velocity = Vector3(safe.x, 0.0, safe.z)
	move_and_slide()
	# FALL-CATCHER: enemies run without gravity, but a chunk-streaming collider gap can still leave one
	# sunk below the world. _ground_y reads the heightmap directly (no collider needed); snap up only
	# when clearly below it, so an enemy can never fall through — without yanking one off an elevated
	# structure (we never pull DOWN).
	if is_instance_valid(world):
		var cm = world.get("chunk_manager")
		if cm != null and is_instance_valid(cm):
			var gy: float = cm._ground_y(global_position.x, global_position.z)
			if global_position.y < gy - 0.5:
				global_position.y = gy


## THE one damage door (Wave-4 contract): melee (main._attack) AND projectiles
## (GProjectile's per-tick sphere-cast hit test) both land here — nothing else writes hp.
## The param stays FLOAT (not the draft int): rpg.weapon_damage() is float, and an int
## caller (a projectile passing the schema's damage) converts losslessly, so both fit.
func take_hit(d: float) -> void:
	if dead:
		return
	d = minf(d, hp_max * HIT_CAP_FRAC)   # never one-shot: cap a single blow so a kill always takes 2+ hits
	hp -= d
	flash_t = 0.12
	AudioManager.play_sfx("hit")
	if hp <= 0.0:
		_die()
	else:
		hurt_t = 0.3
		_play(c_hurt, false)   # brief flinch (rig-lab/library "hurt"/"Hit_A" clip; "" -> silent no-op)


func _die() -> void:
	dead = true
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(world) and world.has_method("on_enemy_killed"):
		world.on_enemy_killed(kind)   # -> XP + quest kill progress (authored enemy_type)
	_play(c_die, false)
	var t := create_tween()
	t.tween_interval(1.1)
	t.tween_callback(queue_free)


# ---------------- anim ----------------

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _resolve_clips() -> void:
	c_idle = _pick(["idle"])
	c_walk = _pick(["walk", "run", "move"])
	c_attack = _pick(["attack", "melee", "swing", "slash", "punch", "bite", "strike"])
	c_die = _pick(["death", "die", "dead"])
	c_hurt = _pick(["hurt", "hit", "flinch", "pain"])


func _pick(keys: Array) -> String:
	if anim == null:
		return ""
	for n in anim.get_animation_list():
		var l := n.to_lower()
		for k in keys:
			if k in l:
				return n
	return ""


func _play(clip: String, loop := true) -> void:
	if anim == null or clip == "" or _cur == clip:
		return
	_cur = clip
	if anim.has_animation(clip):
		var a := anim.get_animation(clip)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		anim.play(clip)


func _face(dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var look := global_position - Vector3(dir.x, 0.0, dir.z)
	look_at(Vector3(look.x, global_position.y, look.z), Vector3.UP)


# Hide the enemy mesh when the CAMERA is pressed against its BODY (fed by main._process): a body
# against the lens reads as a "popup". Distance is measured to the body CENTRE and the threshold
# scales with model height — measured to the feet origin, a 4m model legally walled the frame
# (gamefeel P1: the fade never fired because the camera rides ~1.5-2m above the ground). The
# SpringArm masks world-only, so it never pulls in on enemies (layer 4). (#6)
func set_camera_near(cam_dist: float) -> void:
	if mesh_root != null and is_instance_valid(mesh_root):
		mesh_root.visible = cam_dist > maxf(CAM_FADE_NEAR, 0.45 * body_h)


# Local-frame merged mesh bounds of a subtree (scale/ground decisions at setup, before the model
# animates). Accumulates transforms from IDENTITY so the result is relative to `root`.
func _model_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var n: Node = pair[0]
		var xf: Transform3D = pair[1]
		for c in n.get_children():
			var cx := xf
			if c is Node3D:
				cx = xf * (c as Node3D).transform
			stack.append([c, cx])
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var wa: AABB = xf * (n as MeshInstance3D).get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
	return merged
