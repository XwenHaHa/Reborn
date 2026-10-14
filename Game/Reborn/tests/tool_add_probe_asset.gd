extends SceneTree
## 场景修补工具：把 T005 的静态资产（sm_probe_cube.glb）接入 l_movement_lab。
##
## 为什么用工具而不是手写 .tscn：
##   1) 已有先例（tests/tool_edit_lab_scene.gd）：**场景编辑工具绝不能把场景加进场景树**，
##      否则 pack() 会把运行时状态（下落中的 transform / velocity）烧进场景文件。
##   2) 引用一个 glb 实例需要写对 ext_resource 的 uid 与 instance 语法；
##      由引擎自己序列化比手写更可靠（同类教训见 Visual-Verification §3.1）。
##
## 产物结构（确定性）：
##   ProbeAsset (StaticBody3D, layer=world_static, mask=0, 位置 = 标尺右端旁边)
##   ├── sm_probe_cube  (sm_probe_cube.glb 的实例，纯视觉)
##   └── ProbeShape     (CollisionShape3D + BoxShape3D 1×1×1 —— 简单碰撞，不用三角度复杂碰撞)
##
## 幂等：已存在则复用并核对参数，不重复添加（杜绝 .001 式重复）。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/tool_add_probe_asset.gd'

const LAB := "res://scenes/maps/l_movement_lab.tscn"
const ASSET := "res://assets/tests/sm_probe_cube.glb"

## 位置：地面顶面 0.10 + 立方体半边长 0.5 = 0.60 → 立方体正好坐在 10×10 m 地面上。
## x/z 选在标尺（x 0.7–1.7, z=-2.5）右端旁边，避开 T002/T007 的运动路径：
##   T007 的 move_right 只走到 x≈1.9 且 z≈0；本资产在 z∈[-3.0,-2.0]，不重叠。
const PROBE_POS := Vector3(2.4, 0.6, -2.5)
## 碰撞：与导入网格 AABB 一致（1 m 立方体），运行中由 run_t005_asset.gd 核对该一致性。
const PROBE_BOX := Vector3(1.0, 1.0, 1.0)

## 编辑前后必须保持不变的节点（防止运行时状态被烧进场景）
const MUST_NOT_MOVE := ["Player", "PlayerStart", "Ground", "Camera3D", "Ruler100cm", "DirectionMarker"]

var _before: Dictionary = {}


func _initialize() -> void:
	print("TOOL|add_probe|start")

	var packed: PackedScene = load(LAB)
	if packed == null:
		print("TOOL|ERROR|lab load failed")
		quit(1)
		return

	# 实例化但**不入树**
	var lab: Node3D = packed.instantiate()
	_before_nodes = _list_paths(lab)
	_snapshot(lab)

	_ensure_probe(lab)
	_verify_no_unintended_change(lab)
	_verify_expected_structure(lab)

	var out := PackedScene.new()
	if out.pack(lab) != OK:
		print("TOOL|ERROR|pack failed")
		lab.free()
		quit(1)
		return
	var err := ResourceSaver.save(out, LAB)
	print("TOOL|save_result=%d (%s)" % [err, "OK" if err == OK else "FAIL"])
	lab.free()
	print("TOOL|add_probe|%s" % ("done" if err == OK else "failed"))
	quit(0 if err == OK else 1)


func _list_paths(node: Node) -> Array:
	var acc: Array = [String(node.get_path())]
	for c in node.get_children():
		acc.append_array(_list_paths(c))
	return acc


var _before_nodes: Array = []


func _ensure_probe(lab: Node3D) -> void:
	var probe := lab.get_node_or_null("ProbeAsset") as StaticBody3D
	if probe != null:
		print("TOOL|ProbeAsset=reused")
	else:
		probe = StaticBody3D.new()
		probe.name = "ProbeAsset"
		lab.add_child(probe)
		probe.owner = lab  # 必须设 owner，否则 pack() 会跳过该节点
		print("TOOL|ProbeAsset=created")

	# 物理：静态世界层，不主动检测别人（与 Ground 一致）
	probe.collision_layer = 1
	probe.collision_mask = 0
	probe.position = PROBE_POS

	# 视觉：实例化 glb（实例节点由引擎按 scene_file_path 序列化为 instance=ExtResource）
	var has_visual := false
	for c in probe.get_children():
		if c.scene_file_path == ASSET:
			has_visual = true
	print("TOOL|visual_instance=%s" % ("reused" if has_visual else "created"))
	if not has_visual:
		var inst_scene: PackedScene = load(ASSET)
		if inst_scene == null:
			print("TOOL|ERROR|asset load failed: %s" % ASSET)
			return
		var inst: Node = inst_scene.instantiate()
		probe.add_child(inst)
		inst.owner = lab
		inst.position = Vector3.ZERO
		print("TOOL|visual_root_name=%s|scene_file_path=%s" % [inst.name, inst.scene_file_path])

	# 碰撞：简单 BoxShape3D，尺寸 = 资产网格 AABB（下面核对）
	var shape_node := probe.get_node_or_null("ProbeShape") as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "ProbeShape"
		probe.add_child(shape_node)
		shape_node.owner = lab
		print("TOOL|ProbeShape=created")
	else:
		print("TOOL|ProbeShape=reused")
	var box := BoxShape3D.new()
	box.size = PROBE_BOX
	shape_node.shape = box
	shape_node.position = Vector3.ZERO
	print("TOOL|ProbeShape|size=%s" % box.size)


## 核对结构与"碰撞尺寸 = 网格 AABB"这一条硬约束（这里先查，运行期由测试再查一次）
func _verify_expected_structure(lab: Node3D) -> void:
	var probe := lab.get_node_or_null("ProbeAsset") as StaticBody3D
	if probe == null:
		print("TOOL|VERIFY|ProbeAsset|MISSING")
		return
	print("TOOL|VERIFY|ProbeAsset|pos=%s|layer=%d|mask=%d" % [
		probe.position, probe.collision_layer, probe.collision_mask
	])
	# 注意：glb 实例的根是 Node3D，网格在它的子节点里，所以必须**递归**找（已实测踩到）
	var mi := _find_mesh(probe)
	if mi == null or mi.mesh == null:
		print("TOOL|VERIFY|mesh|MISSING")
		return
	var aabb: AABB = mi.mesh.get_aabb()
	var shape_node := probe.get_node_or_null("ProbeShape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node else null
	print("TOOL|VERIFY|mesh_aabb_size=%s|mesh_aabb_pos=%s" % [aabb.size, aabb.position])
	print("TOOL|VERIFY|shape_size=%s" % (box.size if box else "<none>"))
	if box:
		var ok: bool = box.size.distance_to(aabb.size) < 0.01
		print("TOOL|VERIFY|shape_matches_mesh_aabb|%s" % ("OK" if ok else "MISMATCH"))


func _snapshot(lab: Node3D) -> void:
	for nm in MUST_NOT_MOVE:
		var n := _find(lab, nm)
		if n is Node3D:
			_before[nm] = (n as Node3D).transform
	var p := _find(lab, "Player") as CharacterBody3D
	if p:
		_before["Player.velocity"] = p.velocity


func _verify_no_unintended_change(lab: Node3D) -> void:
	print("TOOL|-- 无意外变更自检 --")
	for nm in MUST_NOT_MOVE:
		var n := _find(lab, nm)
		if not (n is Node3D):
			print("TOOL|unchanged|%s|MISSING!" % nm)
			continue
		var t: Transform3D = (n as Node3D).transform
		var ok: bool = t.is_equal_approx(_before[nm])
		print("TOOL|unchanged|%s|%s" % [nm, "OK" if ok else "CHANGED!"])
	var p := _find(lab, "Player") as CharacterBody3D
	if p:
		var vok: bool = p.velocity.is_zero_approx()
		print("TOOL|unchanged|Player.velocity_is_zero|%s (actual %s)" % [
			"OK" if vok else "CHANGED!", p.velocity
		])
	# 除新增的 ProbeAsset 子树外，节点集合必须完全一致
	var after := _list_paths(lab)
	var added: Array = []
	for pth in after:
		if not _before_nodes.has(pth) and not pth.begins_with("/root/ProbeAsset"):
			added.append(pth)
	print("TOOL|unchanged|node_set|%s (added_outside_probe=%s)" % [
		"OK" if added.is_empty() else "CHANGED!", added
	])


func _find(root_node: Node, nm: String) -> Node:
	if root_node.name == nm:
		return root_node
	for c in root_node.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null


## 递归找第一个网格（glb 实例层级：Node3D → MeshInstance3D → ...）
func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null
