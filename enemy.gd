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

var hp := 45.0
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


func setup(p: Node3D, model: Node, w: Node, index := 0, total := 1, etype := "skeleton") -> void:
	player = p
	world = w
	kind = etype
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
		m.albedo_color = Color(0.8, 0.3, 0.3)
		mi.material_override = m
		add_child(mi)
		mesh_root = mi


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
