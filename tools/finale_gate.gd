extends SceneTree
## Headless finale-interior gate: build the Spire Core spec from world.json and assert
## the stairwell + slabs actually reach the beacon height (the past unwinnable-finale bug).

func _init() -> void:
	var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world.json"))
	var spec: Dictionary = {}
	for c in w["cells"]:
		var cc: Array = c.get("cell", [])
		if cc.size() == 2 and int(cc[0]) == 19 and int(cc[1]) == 15:
			for s in c.get("structures", []):
				if typeof(s) == TYPE_DICTIONARY and s.has("interior"):
					spec = s
					break
	if spec.is_empty():
		print("FINALE_GATE FAIL no enterable structure in cell [19,15]")
		quit(1)
		return
	var node: Node3D = GBuild.structure(spec)
	root.add_child(node)
	var slab_tops: Array = []
	var stair_count := 0
	var has_door_opening := false
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		var nm := String(n.name)
		if nm.begins_with("Stairs") or nm.contains("Flight"):
			stair_count += 1
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var ab: AABB = xf * mi.get_aabb()
			# slab-like: thin + wide
			if ab.size.y <= 0.35 and ab.size.x > 3.0 and ab.size.z > 3.0:
				slab_tops.append(ab.position.y + ab.size.y)
		if nm.contains("Door") or nm.contains("door"):
			has_door_opening = true
		for ch in n.get_children():
			stack.append([ch, xf])
	slab_tops.sort()
	var top: float = slab_tops[-1] if not slab_tops.is_empty() else -1.0
	# the ROOF deck sits at ~65; the top WALKING storey slab must be ~58.5 for the y=59.5 beacon
	var walk_top := -1.0
	for t in slab_tops:
		var tf: float = t
		if tf > walk_top and tf < 60.0:
			walk_top = tf
	print("FINALE_GATE slabs=", slab_tops.size(), " stair_nodes=", stair_count, " top_slab=", top, " top_walk_slab=", walk_top, " door=", has_door_opening)
	var ok := stair_count >= 9 and walk_top >= 57.5 and walk_top <= 59.5
	print("FINALE_GATE ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
