extends SceneTree
## 场景修补工具（T009）：把 `l_movement_lab.tscn` 的**灰盒玩家**换成正式猫
## （`animal_body.tscn` 实例 + `cat.tres`），使 T002/T005/T007 的既有断言直接跑在正式控制器上。
##
## 为什么用工具而不是手写 .tscn（与 `tool_add_probe_asset.gd` 同规矩）：
##   1) 场景编辑**绝不把场景加入场景树**，否则 pack() 会把运行时状态（下落中的 transform）烧进文件；
##   2) 引用 packed scene 实例 + 导出的 resource 属性，交给引擎序列化比手写可靠；
##   3) 顺带核对"除 Player 外没有任何节点被动过"。
##
## 幂等：Player 已经是猫 `AnimalBody` 且配置为 `cat.tres` 时直接复用。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/tool_set_lab_player.gd'

const LAB := "res://scenes/maps/l_movement_lab.tscn"
const BODY := "res://scenes/characters/animal_body.tscn"
const CAT := "res://resources/species/cat.tres"

## 除了 Player 之外必须原样不动的节点
const MUST_NOT_MOVE := [
	"PlayerStart", "Ground", "Ruler100cm", "DirectionMarker", "ProbeAsset", "SunLight", "WorldEnvironment",
]

var _before: Dictionary = {}
var _before_paths: Array = []


func _initialize() -> void:
	print("TOOL|set_lab_player|start")
	var packed: PackedScene = load(LAB)
	if packed == null:
		print("TOOL|ERROR|lab load failed")
		quit(1)
		return

	var lab: Node3D = packed.instantiate() as Node3D   # 不入树
	_before_paths = _list_paths(lab)
	for nm in MUST_NOT_MOVE:
		var n := _find(lab, nm)
		if n is Node3D:
			_before[nm] = (n as Node3D).transform

	_replace_player(lab)
	_verify(lab)
	var unchanged := _verify_no_unintended_change(lab)

	var out := PackedScene.new()
	if out.pack(lab) != OK:
		print("TOOL|ERROR|pack failed")
		lab.free()
		quit(1)
		return
	var err := ResourceSaver.save(out, LAB)
	print("TOOL|save_result=%d (%s)|path=%s" % [err, "OK" if err == OK else "FAIL", LAB])
	lab.free()
	var ok: bool = err == OK and unchanged
	print("TOOL|set_lab_player|%s" % ("done" if ok else "FAILED"))
	quit(0 if ok else 1)


func _replace_player(lab: Node3D) -> void:
	var old := lab.get_node_or_null("Player") as Node3D
	if old == null:
		print("TOOL|ERROR|Player 节点不存在")
		return
	var body: AnimalBody = null
	if old is AnimalBody and (old as AnimalBody).species_config != null \
			and (old as AnimalBody).species_config.species_id == &"Cat":
		print("TOOL|Player=reused (已是 Cat AnimalBody)")
		body = old as AnimalBody
	else:
		var pos: Vector3 = old.position
		var rot: Vector3 = old.rotation
		var parent := old.get_parent()
		parent.remove_child(old)
		old.free()

		body = (load(BODY) as PackedScene).instantiate() as AnimalBody
		body.name = "Player"
		parent.add_child(body)
		body.owner = lab
		body.position = pos
		body.rotation = rot
		body.species_config = load(CAT) as SpeciesConfig
		print("TOOL|Player=created|pos=%s|rot=%s|config=%s" % [
			body.position, body.rotation,
			body.species_config.species_id if body.species_config != null else "<none>",
		])
	# 相机必须 current（lab 的旧灰盒相机是 current=true，T005/T006 视觉捕获依赖它）。
	# 注意不能用"改子节点 Camera3D.current"：实例子节点的属性覆盖不会被 pack() 序列化（实测），
	# 所以走 AnimalBody 自己的导出属性 `make_camera_current`，由 `_ready()` 生效。
	if not body.make_camera_current:
		body.make_camera_current = true
		print("TOOL|Player.make_camera_current=true (set)")


func _verify(lab: Node3D) -> void:
	var body := lab.get_node_or_null("Player") as AnimalBody
	_report("player_is_animal_body", body != null)
	if body == null:
		return
	_report("player_species_is_cat", body.species_config != null and body.species_config.species_id == &"Cat")
	var start := lab.get_node_or_null("PlayerStart") as Marker3D
	_report("player_at_player_start", start != null and body.position.distance_to(start.position) < 1e-6)
	var cam := body.get_node_or_null("Camera3D") as Camera3D
	_report("camera_exists", cam != null)
	_report("player_make_camera_current", body.make_camera_current)
	_report("player_collision_layer_is_animal", body.collision_layer == AnimalBody.LAYER_ANIMAL)
	_report("player_collision_mask_is_world_static", body.collision_mask == AnimalBody.LAYER_WORLD_STATIC)
	_report("player_has_collision_shape", body.get_node_or_null("CollisionShape3D") is CollisionShape3D)
	print("TOOL|VERIFY|player|pos=%s|layer=%d|mask=%d|make_camera_current=%s" % [
		body.position, body.collision_layer, body.collision_mask, body.make_camera_current
	])


func _verify_no_unintended_change(lab: Node3D) -> bool:
	print("TOOL|-- 无意外变更自检 --")
	var ok := true
	for nm in MUST_NOT_MOVE:
		var n := _find(lab, nm)
		if n == null:
			print("TOOL|unchanged|%s|MISSING!" % nm)
			ok = false
			continue
		if not (n is Node3D):
			# WorldEnvironment 这类节点继承自 Node（不是 Node3D），没有 transform 可比
			print("TOOL|unchanged|%s|OK (非 Node3D，仅核对存在)" % nm)
			continue
		var same: bool = (n as Node3D).transform.is_equal_approx(_before[nm])
		print("TOOL|unchanged|%s|%s" % [nm, "OK" if same else "CHANGED!"])
		ok = ok and same
	# 节点集合比对：**Player 子树本来就是要换掉的东西**，只统计子树之外的增删。
	# （踩到过：新玩家带 BodyMesh 灰盒网格，若不过滤子树，工具会自己报 CHANGED!/FAILED 的假警。）
	var after := _list_paths(lab)
	var player_prefix: String = "/%s/Player" % lab.name
	var added: Array = []
	var removed: Array = []
	for p in after:
		if not _before_paths.has(p) and not String(p).begins_with(player_prefix):
			added.append(p)
	for p in _before_paths:
		if not after.has(p) and not String(p).begins_with(player_prefix):
			removed.append(p)
	print("TOOL|unchanged|node_set|%s (added_outside_player=%s removed_outside_player=%s)" % [
		"OK" if added.is_empty() and removed.is_empty() else "CHANGED!", added, removed
	])
	if not added.is_empty() or not removed.is_empty():
		ok = false
	return ok


## 列出全部节点路径。**不要用 `Node.get_path()`**：不入树的节点会报
## "Cannot get path of node as it is not in a scene tree."（实测满屏 ERROR，且返回空串会让
## 节点集合比对变成"永远相等"的假通过）。这里自己拼路径。
func _list_paths(node: Node, prefix: String = "") -> Array:
	var here: String = prefix + "/" + String(node.name)
	var acc: Array = [here]
	for c in node.get_children():
		acc.append_array(_list_paths(c, here))
	return acc


func _find(root_node: Node, nm: String) -> Node:
	if root_node.name == nm:
		return root_node
	for c in root_node.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null


func _report(id: String, ok: bool) -> void:
	print("VERIFY|%s|%s" % [id, "OK" if ok else "FAIL"])
