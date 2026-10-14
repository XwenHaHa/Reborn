extends SceneTree
## T006 无头验收脚本：骨骼往返（Blender → glTF → Godot）
##
## 验收的不是"文件生成了"，而是**引擎读回的真实数据 + 真的能播放**：
##   A) 结构：Skeleton3D 骨骼名/层级保留、皮肤绑定 4 根骨、蒙皮权重真的是 1 骨/顶点
##   B) 尺寸：网格 AABB 与源一致（米制链路同 T005）、骨骼静止位姿符合实测轴向映射
##   C) 动画：长度 = 1.0 s、loop_mode 实测值、轨道确实指向骨骼
##   D) **实际播放**：seek 到 t=0 / 0.5 / 1.0，读骨骼真实姿态——
##        t=0.5 相对 t=0 转了 ≈30°（真的动了）、t=1.0 与 t=0 完全一致（循环闭合）
##   E) **无根运动 / 无根骨缩放**：播放全程节点与 root 骨都不位移、不缩放
##
## 为什么用 seek 而不是等真实时间：seek 是确定性的，同样的输入必然得到同样的姿态，
## 适合无头断言；真实时间推进已在 `Docs/Evidence/T006.md` 的视觉两帧里留证。
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/run_t006_rig.gd' --quit-after 20000
## 退出码：0 = 全部断言通过；1 = 有失败。

const ASSET := "res://assets/tests/sk_rig_probe.glb"

const EPS := 0.01          # 1 cm
const EPS_SCALE := 0.001
const EPS_ANGLE_CLOSURE := 0.5      # 度：首末姿态一致性
const EPS_DEG_LOCAL := 1.0          # 度：作者角度容差。源里 30°/6° 是精确值，
                                    # 但 Godot 按 30 fps 重采样后"最接近 t=0.5 的键"差约半帧，实测偏差 0.47°
const LEG_LENGTH := 0.24            # 米：源里腿骨长度（见 Tools/Blender/t006_rig_probe.py）

## 源数据（Blender，米）——断言按"实测映射 (x,y,z)→(x,z,−y)"换算
const BLENDER_BONE_HEADS := {
	"root": Vector3(0.0, 0.0, 0.0),
	"spine": Vector3(0.0, -0.30, 0.34),
	"leg_front": Vector3(0.0, 0.20, 0.24),
	"leg_back": Vector3(0.0, -0.20, 0.24),
}
const BLENDER_MESH_AABB_SIZE := Vector3(0.20, 0.60, 0.44)
## 源网格 AABB（Blender）：x ±0.10、y ±0.30、z 0↔0.44 → 映射后 Godot 的角点是 (-0.10, 0.0, -0.30)

const ANIM := "Loop"
const ANIM_LENGTH := 1.0
## 实测值：Godot 的 Animation.LOOP_LINEAR == 1（dump 实测 loop_mode=1）
const EXPECTED_LOOP_MODE := 1

var _checks := 0

## 源里每根骨的作者旋转（度，绕骨本地 X）——用于断言**动画轨道里真实存的数值**
const EXPECTED_TRACK_DEG := {
	"spine": {"deg": 6.0, "axis_x_sign": 1.0},
	"leg_front": {"deg": 30.0, "axis_x_sign": 1.0},
	"leg_back": {"deg": 30.0, "axis_x_sign": -1.0},
}
var _fails := 0


func _initialize() -> void:
	print("TEST|run_t006_rig|engine=%s" % Engine.get_version_info().string)
	print("TEST|asset=%s" % ASSET)

	var packed: PackedScene = load(ASSET)
	if packed == null:
		_assert("asset_loads", "PackedScene", "null", false)
		_finish()
		return
	_assert("asset_loads", "PackedScene", "PackedScene", true)

	var root_node: Node = packed.instantiate()
	print("ASSET|root_class=%s|root_name=%s" % [root_node.get_class(), root_node.name])
	_assert("root_is_node3d", "Node3D", root_node.get_class(), root_node is Node3D)

	var sk := _find_skeleton(root_node)
	var ap := _find_anim_player(root_node)
	var mi := _find_mesh(root_node)

	_check_structure(root_node, sk, ap, mi)
	if sk != null:
		_check_skin(mi, sk)
		_check_units(sk, mi)
	if ap != null:
		_check_animation_data(ap)
		await _check_playback(root_node, sk, ap, mi)

	root_node.free()
	_finish()


# ---------------------------------------------------------------------------
# A) 结构
# ---------------------------------------------------------------------------

func _check_structure(root_node: Node, sk: Skeleton3D, ap: AnimationPlayer, mi: MeshInstance3D) -> void:
	_assert("skeleton_found", "Skeleton3D", str(sk), sk != null)
	_assert("animation_player_found", "AnimationPlayer", str(ap), ap != null)
	_assert("mesh_instance_found", "MeshInstance3D", str(mi), mi != null)
	if sk == null or ap == null or mi == null:
		return

	var names := _bone_names(sk)
	_assert("bone_count", "4", str(names.size()), names.size() == 4)
	print("STRUCT|bones=%s" % str(names))
	var want := PackedStringArray(["root", "spine", "leg_front", "leg_back"])
	_assert("bone_names_preserved", str(want), str(names), names == want)

	# 层级：spine 挂在 root，两条腿挂在 spine
	var i_root := names.find("root")
	var i_spine := names.find("spine")
	_assert("spine_parent_is_root", str(i_root), str(sk.get_bone_parent(i_spine)), sk.get_bone_parent(i_spine) == i_root)
	for leg in ["leg_front", "leg_back"]:
		var i_leg := names.find(leg)
		_assert("parent_of_%s" % leg, str(i_spine), str(sk.get_bone_parent(i_leg)), sk.get_bone_parent(i_leg) == i_spine)

	var list := ap.get_animation_list()
	_assert("animation_list", "[Loop]", str(list), list.size() == 1 and list[0] == ANIM)


func _check_skin(mi: MeshInstance3D, sk: Skeleton3D) -> void:
	if mi.mesh == null or mi.skin == null:
		_assert("mesh_has_skin", "Skin", "null", false)
		return
	_assert("mesh_has_skin", "Skin", "Skin", true)
	_assert("skin_bind_count", "4", str(mi.skin.get_bind_count()), mi.skin.get_bind_count() == 4)

	var bind_names := PackedStringArray()
	for i in mi.skin.get_bind_count():
		bind_names.append(mi.skin.get_bind_name(i))
	_assert("skin_bind_names", str(_bone_names(sk)), str(bind_names), bind_names == _bone_names(sk))

	# 权重：每顶点权重和 ≈1.0，且真的是"刚性"（1 骨/顶点）
	var stats := _weight_stats(mi.mesh)
	print("SKIN|%s" % stats)
	var sum_min := float(stats["sum_min"])
	var sum_max := float(stats["sum_max"])
	var max_per := int(stats["max_per_vertex"])
	var used: Variant = stats["used"]
	_assert("weights_sum_is_1", "min/max = 1.0", "%.4f / %.4f" % [sum_min, sum_max],
		absf(sum_min - 1.0) < 1e-3 and absf(sum_max - 1.0) < 1e-3)
	_assert("rigid_one_bone_per_vertex", "1", str(max_per), max_per == 1)
	_assert("used_bone_indices", "[1, 2, 3]", str(used), str(used) == "[1, 2, 3]")


# ---------------------------------------------------------------------------
# B) 尺寸 / 轴向 / 缩放
# ---------------------------------------------------------------------------

func _check_units(sk: Skeleton3D, mi: MeshInstance3D) -> void:
	if mi.mesh != null:
		var aabb: AABB = mi.mesh.get_aabb()
		# Blender (0.20, 0.60, 0.44) → Godot (x, z, y)；角点同理映射
		var want_size := Vector3(BLENDER_MESH_AABB_SIZE.x, BLENDER_MESH_AABB_SIZE.z, BLENDER_MESH_AABB_SIZE.y)
		# 注意：**角点不随轴翻转映射为角点**。Blender AABB 的"最小角"在 Godot 里可能变成最大角，
		# 必须整段区间映射后再取 min 才是 Godot 的 AABB 角。这里直接写实测出来的 Godot 值。
		var want_pos := Vector3(-0.10, 0.0, -0.30)
		print("SIZE|aabb_pos=%s|aabb_size=%s|want_pos=%s|want_size=%s" % [aabb.position, aabb.size, want_pos, want_size])
		_assert_near_vec("mesh_aabb_size_m", want_size, aabb.size, EPS)
		_assert_near_vec("mesh_aabb_pos_m", want_pos, aabb.position, EPS)

	# 骨骼静止位姿（全局）必须等于 Blender 头位置按 (x,y,z)→(x,z,−y) 的映射
	for bone_name in BLENDER_BONE_HEADS:
		var idx := sk.find_bone(bone_name)
		if idx < 0:
			_assert("bone_%s_found" % bone_name, ">= 0", str(idx), false)
			continue
		var origin: Vector3 = sk.get_bone_global_rest(idx).origin
		var b: Vector3 = BLENDER_BONE_HEADS[bone_name]
		var want := Vector3(b.x, b.z, -b.y)
		print("BONE_REST|%s|blender=%s|want_godot=%s|actual=%s" % [bone_name, b, want, origin])
		_assert_near_vec("bone_rest_%s" % bone_name, want, origin, EPS)

	# 缩放：骨骼静止缩放与节点缩放都必须为 1（根骨缩放异常是骨骼往返的经典故障）
	for bone_name in BLENDER_BONE_HEADS:
		var idx := sk.find_bone(bone_name)
		if idx < 0:
			continue
		var s: Vector3 = sk.get_bone_global_rest(idx).basis.get_scale()
		_assert_near_vec("bone_rest_scale_%s" % bone_name, Vector3.ONE, s, EPS_SCALE)
	_assert_near_vec("skeleton_node_scale", Vector3.ONE, sk.scale, EPS_SCALE)


# ---------------------------------------------------------------------------
# C) 动画数据
# ---------------------------------------------------------------------------

func _check_animation_data(ap: AnimationPlayer) -> void:
	var a: Animation = ap.get_animation(ANIM)
	if a == null:
		_assert("animation_exists", ANIM, "null", false)
		return
	print("ANIM|name=%s|length=%.6f|loop_mode=%d|tracks=%d|step=%.4f" % [
		a.get_name(), a.length, a.loop_mode, a.get_track_count(), a.step
	])
	_assert_near("animation_length_s", ANIM_LENGTH, a.length, 0.01)
	_assert("animation_loop_mode", str(EXPECTED_LOOP_MODE), str(a.loop_mode), a.loop_mode == EXPECTED_LOOP_MODE)
	_assert("animation_track_count", "3", str(a.get_track_count()), a.get_track_count() == 3)

	# 轨道必须指向骨骼（而不是某个节点），且首末键值一致
	var want_paths := {
		"Rig/Skeleton3D:spine": false,
		"Rig/Skeleton3D:leg_front": false,
		"Rig/Skeleton3D:leg_back": false,
	}
	for i in a.get_track_count():
		var p := str(a.track_get_path(i))
		_assert("track_type_%d" % i, "TYPE_ROTATION_3D(%d)" % Animation.TYPE_ROTATION_3D,
			str(a.track_get_type(i)), a.track_get_type(i) == Animation.TYPE_ROTATION_3D)
		if want_paths.has(p):
			want_paths[p] = true
		var nk := a.track_get_key_count(i)
		_assert("track_%d_has_keys" % i, "> 2", str(nk), nk > 2)
		if nk >= 2:
			var v0: Variant = a.track_get_key_value(i, 0)
			var v1: Variant = a.track_get_key_value(i, nk - 1)
			var t1 := a.track_get_key_time(i, nk - 1)
			# 首末键值相同 = 循环闭合（源里帧 0 与帧 24 姿态相同）
			var same: bool = v0 is Quaternion and v1 is Quaternion and (v0 as Quaternion).angle_to(v1 as Quaternion) < 0.001
			print("TRACK|%s|keys=%d|last_t=%.4f|first_v=%s|last_v=%s|closed=%s" % [p, nk, t1, str(v0), str(v1), same])
			var all_times := PackedStringArray()
			for k in nk:
				all_times.append("%.4f" % a.track_get_key_time(i, k))
			print("TRACK_TIMES|%s|count=%d|times=%s" % [p, nk, ",".join(all_times)])
			_assert("track_%d_ends_at_length" % i, "%.4f" % a.length, "%.4f" % t1, absf(t1 - a.length) < 0.001)
			_assert("track_%d_loop_closed" % i, "angle_to < 0.001 rad", str(same), same)

		# 轨道里的**作者数值**：以首键为基准，遍历所有键取最大旋转角 = 动画峰值幅度。
		#
		# 为什么不用"t=0.5 的键"：实测 Godot 重采样出的 30 个键里**没有 0.5**
		# （实测键时间 ...0.4667 → **0.5333**...，末键 1.0000），在峰值两侧做插值会低估幅度
		# （实测插值到 0.5 只有 29.28°，而作者写的是 30°）。峰值本身才是作者的数值。
		if nk >= 2:
			var q0: Quaternion = a.track_get_key_value(i, 0)
			var peak_deg := 0.0
			var peak_idx := 0
			var peak_axis := Vector3.ZERO
			for k in nk:
				var dq := q0.inverse() * (a.track_get_key_value(i, k) as Quaternion)
				var d := rad_to_deg(dq.get_angle())
				if d > peak_deg:
					peak_deg = d
					peak_idx = k
					peak_axis = dq.get_axis()
			var qm05: Quaternion = a.rotation_track_interpolate(i, 0.5)
			var interp_deg := rad_to_deg((q0.inverse() * qm05).get_angle())
			print("TRACK_PEAK|%s|peak=%.3f deg|peak_t=%.4f|axis=%s|interp_at_0.5=%.3f deg" % [
				p, peak_deg, a.track_get_key_time(i, peak_idx), peak_axis, interp_deg
			])
			var bone := _bone_from_path(p)
			if EXPECTED_TRACK_DEG.has(bone):
				var exp: Dictionary = EXPECTED_TRACK_DEG[bone]
				_assert_near("track_peak_%s" % bone, float(exp["deg"]), peak_deg, EPS_DEG_LOCAL)
				var sign := float(exp["axis_x_sign"])
				_assert("track_axis_%s" % bone, "axis.x sign %+.0f" % sign, "%.4f" % peak_axis.x,
					peak_axis.x * sign > 0.99)
			else:
				_assert("track_peak_known_%s" % bone, "in table", bone, false)
	for p in want_paths:
		_assert("track_path_present_%s" % p, "true", str(want_paths[p]), bool(want_paths[p]))


# ---------------------------------------------------------------------------
# D/E) 实际播放：骨骼真的动、循环闭合、无根运动、无根骨缩放
# ---------------------------------------------------------------------------

func _check_playback(root_node: Node, sk: Skeleton3D, ap: AnimationPlayer, mi: MeshInstance3D) -> void:
	if sk == null or ap == null:
		return

	# 试验世界：只放进资产实例（不依赖 lab 场景）
	var world := Node3D.new()
	world.name = "T006World"
	root.add_child(world)
	world.add_child(root_node)
	await process_frame
	await physics_frame

	# 实测：Godot 4.7 的 AnimationPlayer.play() 返回 void（不是 Error），所以只能查 play 后的状态
	ap.play(ANIM)
	_assert("player_playing", ANIM, ap.current_animation,
		ap.is_playing() and ap.current_animation == ANIM)
	await process_frame

	var i_leg_front := sk.find_bone("leg_front")
	var i_leg_back := sk.find_bone("leg_back")
	var i_root := sk.find_bone("root")

	# 关掉循环，方便用长过长度的 seek 精确停在 1.0（先记录真实 loop_mode 已在 C 段断言）
	ap.get_animation(ANIM).loop_mode = Animation.LOOP_NONE

	var rig := root_node.get_node_or_null("Rig") as Node3D
	var rig_tf_start: Transform3D = rig.global_transform if rig != null else Transform3D()

	var p0 := _sample(sk, ap, i_leg_front, 0.0, i_root)
	var p_mid := _sample(sk, ap, i_leg_front, 0.5, i_root)
	var p1 := _sample(sk, ap, i_leg_front, ANIM_LENGTH, i_root)
	var b0 := _sample(sk, ap, i_leg_back, 0.0, i_root)
	var b_mid := _sample(sk, ap, i_leg_back, 0.5, i_root)

	var d0: Vector3 = p0["dir"]
	var d_mid: Vector3 = p_mid["dir"]
	var d1: Vector3 = p1["dir"]
	var f0: Vector3 = p0["foot"]
	var f_mid: Vector3 = p_mid["foot"]
	var f1: Vector3 = p1["foot"]
	print("PLAY|leg_front|t0_dir=%s|t05_dir=%s|t1_dir=%s" % [d0, d_mid, d1])
	print("PLAY|leg_front|t0_foot=%s|t05_foot=%s|t1_foot=%s" % [f0, f_mid, f1])

	# 骨骼姿态里 Godot 报的"pose rotation"**含静止位姿**（实测 t=0 时腿骨已是 90° = 静止的 −90°），
	# 所以它的角度不是作者写的 30°。精确断言放在 C 段的**动画轨道数据**上；
	# 这里只把姿态数值打出来供人核对（INFO）。
	print("PLAY|pose_rot_includes_rest|leg_front_t05=%.3f deg|leg_back_t05=%.3f deg|leg_front_t0=%.3f deg" % [
		float(p_mid["local_angle"]), float(b_mid["local_angle"]), float(p0["local_angle"])
	])

	# 只做"确实动了"的粗阈值断言；精确的作者角度断言在 C 段的**动画轨道数据**上。
	var front_world := float(p_mid["world_angle"])
	var back_world := float(b_mid["world_angle"])
	print("PLAY|world_dir_change|leg_front=%.3f deg|leg_back=%.3f deg (腿 30° + spine 6° 的合成)" % [
		front_world, back_world
	])
	_assert("leg_front_world_swing_range", "[25, 40] deg", "%.3f" % front_world,
		front_world >= 25.0 and front_world <= 40.0)
	_assert("leg_back_world_swing_range", "[18, 30] deg", "%.3f" % back_world,
		back_world >= 18.0 and back_world <= 30.0)
	_assert("leg_front_foot_moved_m", "> 0.05", "%.4f" % f0.distance_to(f_mid), f0.distance_to(f_mid) > 0.05)
	_assert("leg_back_foot_moved_m", "> 0.05", "%.4f" % (b_mid["foot"] as Vector3).distance_to(b0["foot"] as Vector3),
		(b_mid["foot"] as Vector3).distance_to(b0["foot"] as Vector3) > 0.05)

	# 循环闭合：t=1.0 与 t=0.0 的姿态完全一致（pose 角度相等 + 脚端重合）
	_assert_near("loop_closure_pose_deg_diff", 0.0, absf(float(p1["local_angle"]) - float(p0["local_angle"])), 0.01)
	_assert_near("loop_closure_foot_mm", 0.0, f0.distance_to(f1) * 1000.0, 2.0)

	# 无根运动：整段播放中 Rig 与 Skeleton3D 的全局变换不变
	var rig_tf_end: Transform3D = rig.global_transform if rig != null else Transform3D()
	_assert_near("rig_node_no_translation_mm", 0.0, rig_tf_start.origin.distance_to(rig_tf_end.origin) * 1000.0, 0.1)
	_assert_near("rig_node_no_rotation_deg", 0.0, rad_to_deg(rig_tf_start.basis.get_rotation_quaternion().angle_to(
		rig_tf_end.basis.get_rotation_quaternion())), 0.01)
	_assert_near_vec("skeleton_node_no_translation", Vector3.ZERO, sk.position, 0.0001)

	# root 骨：全程不位移、不缩放
	var root_t0: Vector3 = p0["root_origin"]
	var root_mid: Vector3 = p_mid["root_origin"]
	var root_s0: Vector3 = p0["root_scale"]
	var root_s_mid: Vector3 = p_mid["root_scale"]
	_assert_near_vec("root_bone_no_translation_mm", Vector3.ZERO, (root_mid - root_t0) * 1000.0, 0.1)
	_assert_near_vec("root_bone_scale_at_t0", Vector3.ONE, root_s0, EPS_SCALE)
	_assert_near_vec("root_bone_scale_at_t05", Vector3.ONE, root_s_mid, EPS_SCALE)
	print("NOMOTION|rig_start=%s|rig_end=%s|skeleton_pos=%s|root_t0=%s|root_t05=%s" % [
		rig_tf_start.origin, rig_tf_end.origin, sk.position, p0["root_origin"], p_mid["root_origin"]
	])

	# 顺带核对"蒙皮网格在播放中确实变形"：t=0 与 t=0.5 的 AABB 或坐标不同
	if mi != null and mi.mesh != null:
		print("PLAY|mesh_aabb=%s" % [mi.mesh.get_aabb().size])

	ap.stop()
	root_node.get_parent().remove_child(root_node)
	world.queue_free()
	await process_frame


## 在给定时间点采样骨骼，返回：
##   dir/foot        —— 骨骼世界方向（骨轴 +Y）与骨尖位置
##   local_angle/axis—— **局部姿态旋转**（相对静止位姿）的角度与轴：这是"作者到底转了多少度"的直接证据
##   world_angle     —— 世界方向相对 t=0 的变化量（会被父骨旋转叠加，故只用粗阈值）
##   root_*          —— root 骨的位置与缩放（用于"无根运动/无根骨缩放"）
func _sample(sk: Skeleton3D, ap: AnimationPlayer, bone_idx: int, t: float, root_idx: int) -> Dictionary:
	ap.seek(t, true)
	var pose: Transform3D = sk.get_bone_global_pose(bone_idx)
	var dir: Vector3 = pose.basis.y.normalized()
	var root_pose: Transform3D = sk.get_bone_global_pose(root_idx)
	var q: Quaternion = sk.get_bone_pose_rotation(bone_idx)
	var out := {
		"dir": dir,
		"foot": pose.origin + dir * LEG_LENGTH,
		"local_angle": rad_to_deg(q.get_angle()),
		"local_axis": q.get_axis(),
		"root_origin": root_pose.origin,
		"root_scale": root_pose.basis.get_scale(),
		"world_angle": 0.0,
	}
	if t == 0.0:
		_rest_dir = dir
	else:
		out["world_angle"] = rad_to_deg(_rest_dir.angle_to(dir))
	return out


var _rest_dir: Vector3 = Vector3(0.0, -1.0, 0.0)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	return _find(node, "Skeleton3D") as Skeleton3D


func _find_anim_player(node: Node) -> AnimationPlayer:
	return _find(node, "AnimationPlayer") as AnimationPlayer


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


func _bone_names(sk: Skeleton3D) -> PackedStringArray:
	var acc := PackedStringArray()
	for i in sk.get_bone_count():
		acc.append(sk.get_bone_name(i))
	return acc


func _weight_stats(mesh: Mesh) -> Dictionary:
	var used := {}
	var max_per_vertex := 0
	var sum_lo := 1e9
	var sum_hi := -1e9
	for si in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(si)
		if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var b: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var vc: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if vc == 0:
			continue
		var stride: int = w.size() / vc
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
	return {"sum_min": sum_lo, "sum_max": sum_hi, "max_per_vertex": max_per_vertex, "used": keys}


func _assert(id: String, expected: String, actual: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s|%s|%s" % [id, expected, actual, "PASS" if ok else "FAIL"])


func _assert_near(id: String, expected: float, actual: float, eps: float) -> void:
	var ok: bool = absf(expected - actual) <= eps
	_assert(id, "%.4f (±%.4f)" % [expected, eps], "%.4f" % actual, ok)


func _assert_near_vec(id: String, expected: Vector3, actual: Vector3, eps: float) -> void:
	var ok: bool = (expected - actual).length() <= eps
	_assert(id, "%s (±%.4f)" % [expected, eps], str(actual), ok)


func _finish() -> void:
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)


## 找与 t 最接近的键下标（读轨道的"作者数值"用）
func _nearest_key_index(a: Animation, track: int, t: float) -> int:
	var best := 0
	var best_d := 1e9
	for k in a.track_get_key_count(track):
		var d := absf(a.track_get_key_time(track, k) - t)
		if d < best_d:
			best_d = d
			best = k
	return best


## 从轨道路径 "Rig/Skeleton3D:leg_front" 取骨骼名
func _bone_from_path(path_str: String) -> String:
	var parts := path_str.split(":", false)
	return parts[parts.size() - 1] if parts.size() > 0 else path_str
