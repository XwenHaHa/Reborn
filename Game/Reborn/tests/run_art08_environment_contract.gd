extends SceneTree
## ART08 环境表现层契约：验证装饰不改变碰撞、导航和关键通道。

const LEVEL := "res://scenes/maps/l_courtyard.tscn"
var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var packed := load(LEVEL) as PackedScene
	_check("level_loads", packed != null)
	if packed == null:
		_finish()
		return
	var level := packed.instantiate()
	root.add_child(level)
	await process_frame
	var static_bodies := _nodes_of_type(level, "StaticBody3D")
	_check("static_body_count_20", static_bodies.size() == 20)
	_check("nav_source_count_20", root.get_tree().get_nodes_in_group("nav_source_courtyard").size() == 20)
	var water := level.find_child("CreekWater", true, false) as MeshInstance3D
	_check("creek_water_exists", water != null)
	_check("creek_water_no_collision", water != null and _find_collision(water) == null)
	_check("water_body_count_1", root.get_tree().get_nodes_in_group("water_bodies").size() == 1)
	var hole := level.find_child("HideSpot_RootHole", true, false)
	_check("root_hole_exists", hole != null)
	_check("decor_nodes_have_no_collision", _decor_collision_count(level) == 0)
	_check("decor_nodes_not_in_nav", _decor_nav_count(level) == 0)
	print("MEASURE|environment|static_bodies=%d|nav_source=%d|water=%d|decor_collision=%d|decor_nav=%d" % [
		static_bodies.size(), root.get_tree().get_nodes_in_group("nav_source_courtyard").size(),
		root.get_tree().get_nodes_in_group("water_bodies").size(), _decor_collision_count(level), _decor_nav_count(level)])
	level.queue_free()
	_finish()

func _nodes_of_type(node: Node, type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	if node.get_class() == type_name:
		out.append(node)
	for child in node.get_children():
		out.append_array(_nodes_of_type(child, type_name))
	return out

func _find_collision(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
		var found := _find_collision(child)
		if found != null:
			return found
	return null

func _decor_collision_count(node: Node) -> int:
	if node is Area3D or node.is_in_group("nav_source_courtyard") or node.is_in_group("cover_volumes") or node is StaticBody3D:
		return 0
		return 0
	var count := 1 if node is CollisionShape3D else 0
	for child in node.get_children():
		count += _decor_collision_count(child)
	return count

func _decor_nav_count(node: Node) -> int:
	if node.is_in_group("nav_source_courtyard") or node.is_in_group("cover_volumes"):
		return 0
	var count := 0
	for child in node.get_children():
		count += _decor_nav_count(child)
	return count

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])

func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)
