extends SceneTree
## 资产锚点探针：打印每个 glb 的**合并 AABB**（世界/局部一致，因为缩放为 1）。
##
## 用途：摆装饰件时不要靠猜"原点在脚底还是在中心"——`min_y` 就是落地时该给的偏移量。
## 用法：`& $g --headless --path $proj --script 'res://tests/tool_probe_aabb.gd' --quit-after 60000`

const ASSETS := [
	"res://assets/environment/sm_boulder_001.glb",
	"res://assets/environment/sm_bush_002.glb",
	"res://assets/environment/sm_root_hole_001.glb",
	"res://assets/environment/sm_root_barrier_001.glb",
	"res://assets/environment/sm_wall_low_001.glb",
	"res://assets/environment/sm_fence_module_001.glb",
	"res://assets/environment/sm_shelter_post_001.glb",
	"res://assets/environment/sm_roof_001.glb",
	"res://assets/environment/sm_mound_001.glb",
]


func _initialize() -> void:
	for path in ASSETS:
		var ps := load(path) as PackedScene
		if ps == null:
			print("AABB|%s|MISSING" % path)
			continue
		var inst := ps.instantiate() as Node3D
		root.add_child(inst)
		var box := _aabb(inst)
		print("AABB|%s|min=(%.3f, %.3f, %.3f)|max=(%.3f, %.3f, %.3f)|size=(%.3f, %.3f, %.3f)|ground_offset=%.3f" % [
			path.get_file(), box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z, box.size.x, box.size.y, box.size.z,
			-box.position.y,
		])
		inst.queue_free()
	quit(0)


func _aabb(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for item in _meshes(node):
		var mi := item as MeshInstance3D
		if mi == null:
			continue
		var box_local: AABB = mi.get_aabb()
		var b: AABB = mi.global_transform * box_local
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for child in n.get_children():
		out.append_array(_meshes(child))
	return out
