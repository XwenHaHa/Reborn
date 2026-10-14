extends SceneTree
## 导入结构 dump 工具：打印一个 PackedScene 资源的真实节点树与网格/材质事实。
##
## 为什么需要：写完 .glb 导出后**不能凭记忆猜** Godot 会把它导成什么结构
## （根节点类型、名字、网格 AABB、材质槽、变换是否被烘焙）。
## 本工具只读、只打印，用来决定 .tscn 里该怎么引用，以及断言该怎么写。
## T006（骨骼往返）同样适用。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/tool_dump_scene_tree.gd' -- 'res://assets/tests/sm_probe_cube.glb'
##   （`--` 之后的第一个参数是资源路径；省略则用下面的默认值）
## 退出码：0 = 成功 dump；1 = 资源加载失败。

const DEFAULT_TARGET := "res://assets/tests/sm_probe_cube.glb"

var _lines: int = 0


func _initialize() -> void:
	var target := DEFAULT_TARGET
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		target = user_args[0]

	print("DUMP|target=%s" % target)
	print("DUMP|engine=%s" % Engine.get_version_info().string)

	var packed: PackedScene = load(target)
	if packed == null:
		print("DUMP|ERROR|load_failed")
		quit(1)
		return
	print("DUMP|loaded=PackedScene")

	var node: Node = packed.instantiate()
	_dump(node, 0)
	print("DUMP|line_count=%d" % _lines)
	print("DUMP|done")
	node.free()
	quit(0)


func _dump(node: Node, depth: int) -> void:
	_lines += 1

	var indent := "  ".repeat(depth)
	var line := "DUMP|node|path=%s|class=%s|name=%s|index=%d" % [
		String(node.get_path()), node.get_class(), node.name, node.get_index()
	]
	if node is Node3D:
		var n3 := node as Node3D
		line += "|pos=%s|rot_deg=%s|scale=%s" % [
			_v(n3.position), _v(n3.rotation_degrees), _v(n3.scale)
		]
	if node is CollisionObject3D:
		var co := node as CollisionObject3D
		line += "|layer=%d|mask=%d" % [co.collision_layer, co.collision_mask]
	print("%s%s" % [indent, line])

	if node is MeshInstance3D:
		_dump_mesh(node as MeshInstance3D, indent)
	elif node is CollisionShape3D:
		var cs := node as CollisionShape3D
		print("%sDUMP|shape|path=%s|class=%s|props=%s" % [
			indent, String(cs.get_path()), _class_of(cs.shape), _shape_facts(cs.shape)
		])
	if node is Skeleton3D:
		_dump_skeleton(node as Skeleton3D, indent)
	if node is AnimationPlayer:
		_dump_animation_player(node as AnimationPlayer, indent)

	for child in node.get_children():
		_dump(child, depth + 1)


func _dump_mesh(mi: MeshInstance3D, indent: String) -> void:
	var mesh: Mesh = mi.mesh
	if mesh == null:
		print("%sDUMP|mesh|path=%s|MISSING" % [indent, String(mi.get_path())])
		return
	var aabb: AABB = mesh.get_aabb()
	print("%sDUMP|mesh|path=%s|class=%s|surface_count=%d|aabb_pos=%s|aabb_size=%s|verts=%d|tris=%d" % [
		indent, String(mi.get_path()), _class_of(mesh), mesh.get_surface_count(),
		_v(aabb.position), _v(aabb.size), _vertex_count(mesh), _triangle_count(mesh)
	])
	if mi.material_override != null:
		print("%sDUMP|mat_override|path=%s|%s" % [
			indent, String(mi.get_path()), _mat_facts(mi.material_override)
		])
	for i in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(i)
		print("%sDUMP|surface|index=%d|material=%s" % [
			indent, i, _mat_facts(m) if m != null else "<none>"
		])
	if mi.skin != null:
		var bind_names := PackedStringArray()
		for i in mi.skin.get_bind_count():
			bind_names.append(mi.skin.get_bind_name(i))
		print("%sDUMP|skin|path=%s|binds=%d|joints=%s" % [
			indent, String(mi.get_path()), mi.skin.get_bind_count(), ",".join(bind_names)
		])
		print("%sDUMP|skin_weights|path=%s|%s" % [indent, String(mi.get_path()), _weight_stats(mesh)])
	else:
		print("%sDUMP|skin|path=%s|NONE" % [indent, String(mi.get_path())])


func _mat_facts(m: Material) -> String:
	var s := "class=%s|res_name=%s" % [_class_of(m), m.resource_name]
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		s += "|albedo_color=%s|emission_enabled=%s|roughness=%.3f|metallic=%.3f" % [
			b.albedo_color, b.emission_enabled, b.roughness, b.metallic
		]
	return s


func _vertex_count(mesh: Mesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(i)
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _shape_facts(shape: Shape3D) -> String:
	if shape == null:
		return "<none>"
	if shape is BoxShape3D:
		return "size=%s" % _v((shape as BoxShape3D).size)
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return "radius=%.4f|height=%.4f" % [c.radius, c.height]
	return "unhandled"


func _class_of(obj: Object) -> String:
	return obj.get_class() if obj != null else "<null>"


func _v(v: Variant) -> String:
	if v is Vector3:
		var x := v as Vector3
		return "(%.6f, %.6f, %.6f)" % [x.x, x.y, x.z]
	if v is Color:
		var c := v as Color
		return "(%.4f, %.4f, %.4f, %.4f)" % [c.r, c.g, c.b, c.a]
	return str(v)


## --- 骨骼 / 动画 / 蒙皮 dump（T006 起） ---

func _dump_skeleton(sk: Skeleton3D, indent: String) -> void:
	print("%sDUMP|skeleton|path=%s|bones=%d|names=%s" % [
		indent, String(sk.get_path()), sk.get_bone_count(), ",".join(_bone_names(sk))
	])
	for i in sk.get_bone_count():
		var rest: Transform3D = sk.get_bone_rest(i)
		print("%sDUMP|bone|index=%d|name=%s|parent=%d|rest_pos=%s|rest_rot_deg=%s|rest_scale=%s" % [
			indent, i, sk.get_bone_name(i), sk.get_bone_parent(i),
			_v(rest.origin), _v(rest.basis.get_euler() * 180.0 / PI), _v(rest.basis.get_scale())
		])


func _bone_names(sk: Skeleton3D) -> PackedStringArray:
	var acc := PackedStringArray()
	for i in sk.get_bone_count():
		acc.append(sk.get_bone_name(i))
	return acc


func _dump_animation_player(ap: AnimationPlayer, indent: String) -> void:
	var names := ap.get_animation_list()
	print("%sDUMP|anim_player|path=%s|animations=%d|names=%s" % [
		indent, String(ap.get_path()), names.size(), ",".join(names)
	])
	for nm in names:
		var a: Animation = ap.get_animation(nm)
		print("%sDUMP|animation|name=%s|length=%.6f|loop_mode=%d|tracks=%d|step=%.4f" % [
			indent, nm, a.length, a.loop_mode, a.get_track_count(), a.step
		])
		for i in a.get_track_count():
			print("%sDUMP|track|index=%d|type=%d|path=%s|keys=%d" % [
				indent, i, a.track_get_type(i), a.track_get_path(i), a.track_get_key_count(i)
			])
			var nk := a.track_get_key_count(i)
			if nk > 0:
				print("%sDUMP|track_keys|index=%d|first_t=%.4f|first_v=%s|last_t=%.4f|last_v=%s" % [
					indent, i,
					a.track_get_key_time(i, 0), str(a.track_get_key_value(i, 0)),
					a.track_get_key_time(i, nk - 1), str(a.track_get_key_value(i, nk - 1))
				])


## 蒙皮统计：证明权重真的写出去了（而不是"看起来有 skin"）
func _weight_stats(mesh: Mesh) -> String:
	var used := {}
	var max_per_vertex := 0
	var sum_lo := 1e9
	var sum_hi := -1e9
	var verts := 0
	for si in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(si)
		if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var b: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var vc: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if vc == 0 or w.size() % vc != 0 or b.size() % vc != 0:
			return "shape_mismatch|verts=%d|weights=%d|bones=%d" % [vc, w.size(), b.size()]
		var stride: int = w.size() / vc
		verts += vc
		for v in vc:
			var count := 0
			var total := 0.0
			for k in stride:
				var wv := w[v * stride + k]
				if wv > 0.0:
					count += 1
					total += wv
					used[b[v * stride + k]] = true
			max_per_vertex = maxi(max_per_vertex, count)
			sum_lo = minf(sum_lo, total)
			sum_hi = maxf(sum_hi, total)
	var keys := used.keys()
	keys.sort()
	return "verts=%d|weight_sum_min=%.4f|weight_sum_max=%.4f|max_bones_per_vertex=%d|used_bone_indices=%s" % [
		verts, sum_lo, sum_hi, max_per_vertex, str(keys)
	]
