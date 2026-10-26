extends SceneTree
## 步态量测工具（第三阶段 §四）：对候选 GLB 的 **Walk / Run** 逐腿量测。
##
## 用法：
##   godot --headless --path E:\Reborn\Game\Reborn `
##     --script res://tests/tool_cat_gait_eval.gd -- --glb=res://assets/characters/cat/sm_cat_004.glb
##   可选：--clips=Walk,Run  --dt=0.0041667
##
## 与 tool_audit_cat_slip.gd（真实关卡）的分工：
##   本工具只读动画本身，把"身体以 v 前移"合成到脚掌轨迹上算**游戏内滑移**，
##   用来做参数网格筛选；最终候选必须再用 tool_audit_cat_slip.gd 在真实关卡复验。
##   合成方式：游戏里脚掌世界速度 = d(脚掌本地位置)/dt + 身体速度矢量(0,0,-v)。
##   支撑相该值 ≈ 0 即"锁地"。同时输出膝关节角、髋-趾根距离（判拉腿）、
##   脚掌最低点与抬升（判穿地/摆腿）、根骨竖直范围（判身体起伏与下沉）。
##
## 不写任何文件、不改任何资源。

const PAWS := ["Bone.018", "Bone.022", "Bone.014", "Bone.026"]
const LEGS := {
	"Bone.018": {"hip": "Bone.015", "ball": "Bone.018"},
	"Bone.022": {"hip": "Bone.019", "ball": "Bone.022"},
	"Bone.014": {"hip": "Bone.011", "ball": "Bone.014"},
	"Bone.026": {"hip": "Bone.023", "ball": "Bone.026"},
}
const BODY_SPEED := {"Walk": 1.8, "Run": 4.5}
const CONTACT_EPS := 0.002

var _skel: Skeleton3D = null


func _initialize() -> void:
	var glb := "res://assets/characters/cat/sm_cat_004.glb"
	var clips := ["Walk", "Run"]
	var dt := 1.0 / 240.0
	var dump_arg := ""
	var tracks_arg := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--glb="):
			glb = arg.substr(6)
		elif arg.begins_with("--clips="):
			clips = Array(arg.substr(8).split(","))
		elif arg.begins_with("--dt="):
			dt = float(arg.substr(5))
		elif arg.begins_with("--dump="):
			dump_arg = arg.substr(7)
		elif arg.begins_with("--tracks="):
			tracks_arg = arg.substr(9)
	print("GAITEVAL|start|glb=%s|dt=%.6f|dump=%s" % [glb, dt, dump_arg])
	var ps: PackedScene = load(glb)
	if ps == null:
		print("GAITEVAL|FAIL|load|%s" % glb)
		quit(1)
		return
	var root: Node = ps.instantiate()
	get_root().add_child(root)
	await process_frame
	_skel = _find(root, "Skeleton3D") as Skeleton3D
	var ap := _find(root, "AnimationPlayer") as AnimationPlayer
	if _skel == null or ap == null:
		print("GAITEVAL|FAIL|missing_node")
		quit(1)
		return
	for cn in clips:
		if not ap.has_animation(cn):
			print("GAITEVAL|FAIL|missing_clip|%s" % cn)
			continue
		await _eval(ap, cn, BODY_SPEED.get(cn, 0.0), dt)
	if dump_arg != "":
		var parts := Array(dump_arg.split(":"))
		if parts.size() == 2:
			await _dump(ap, parts[0], parts[1], dt)
	if tracks_arg != "":
		_tracks(ap, tracks_arg)
	root.free()
	print("GAITEVAL|end")
	quit(0)


func _eval(ap: AnimationPlayer, cn: String, v: float, dt: float) -> void:
	var a: Animation = ap.get_animation(cn)
	a.loop_mode = Animation.LOOP_LINEAR
	ap.play(cn)
	ap.speed_scale = 1.0
	ap.pause()
	var n := int(round(a.length / dt))
	var ts := []
	var paw := {}
	var hip := {}
	var ball := {}
	var root_y := []
	for bn in PAWS:
		paw[bn] = []
		hip[bn] = []
		ball[bn] = []
	var root_bi := _skel.find_bone("Bone")
	for i in n + 1:
		var t := float(i) * dt
		ap.seek(t, true)
		await process_frame
		ts.append(t)
		for bn in PAWS:
			paw[bn].append(_world(bn))
			hip[bn].append(_world(LEGS[bn]["hip"]))
			ball[bn].append(_world(LEGS[bn]["ball"]))
		root_y.append((_skel.global_transform * _skel.get_bone_global_pose(root_bi)).origin.y)
	print("GAITEVAL|clip|%s|length=%.5f|samples=%d|body_speed=%.2f" % [cn, a.length, ts.size(), v])
	print("GAITEVAL|body|%s|root_y=[%.4f..%.4f]|range=%.4f|knee_angle_min=%.1f|stretch_max=%.4f" % [
		cn, root_y.min(), root_y.max(), root_y.max() - root_y.min(),
		_knee_min(hip, ball, paw), _stretch_max(hip, ball)])
	var body_v := Vector3(0.0, 0.0, -v)
	for bn in PAWS:
		var arr: Array = paw[bn]
		var ymin: float = 1e9
		var ymax: float = -1e9
		var zmin: float = 1e9
		var zmax: float = -1e9
		for p in arr:
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
			zmin = minf(zmin, p.z)
			zmax = maxf(zmax, p.z)
		var contact := []
		var slip := []
		var first_c := -1
		var last_c := -1
		for i in range(1, arr.size()):
			if float(arr[i].y) <= ymin + CONTACT_EPS:
				if first_c < 0:
					first_c = i
				last_c = i
				var vel: Vector3 = (arr[i] - arr[i - 1]) / dt
				slip.append((vel + body_v).length())
				contact.append(i)
		var phase := (float(first_c) * dt / a.length) if first_c >= 0 else -1.0
		var duty := 0.0
		if first_c >= 0:
			duty = float(contact.size()) / float(arr.size())
		print("GAITEVAL|paw|%s|%s|stance_frames=%d/%d|duty=%.3f|first_contact_t=%.4f|phase=%.3f" % [
			cn, bn, contact.size(), arr.size() - 1, duty,
			(float(first_c) * dt) if first_c >= 0 else -1.0, phase])
		print("GAITEVAL|paw|%s|%s|slip_game m/s: mean=%.4f max=%.4f (0=锁地) |lift=%.4f|lift_pct=%.1f%%|y_min=%.4f" % [
			cn, bn, _mean(slip), slip.max() if not slip.is_empty() else -1.0,
			ymax - ymin, 100.0 * (ymax - ymin) / maxf(1e-6, ymax), ymin])
		print("GAITEVAL|paw|%s|%s|travel_z=%.4f|z_range=[%.4f..%.4f]|hip_ball_max=%.4f|stretch=%.4f" % [
			cn, bn, zmax - zmin, zmin, zmax, _max_dist(hip[bn], ball[bn]),
			_max_dist(hip[bn], ball[bn]) / maxf(1e-6, _rest_reach(bn))])


## 膝关节角（度）：髋→膝 与 膝→趾根 的夹角；180 = 完全伸直（=拉腿）
func _knee_min(hip: Dictionary, ball: Dictionary, paw: Dictionary) -> float:
	var worst := 180.0
	for bn in PAWS:
		for i in hip[bn].size():
			var h: Vector3 = hip[bn][i]
			var k: Vector3 = _world(_knee_of(bn))
			var b: Vector3 = ball[bn][i]
			var d1 := (k - h).normalized()
			var d2 := (b - k).normalized()
			if d1.length() < 0.5 or d2.length() < 0.5:
				continue
			worst = minf(worst, rad_to_deg(acos(clampf(d1.dot(d2), -1.0, 1.0))))
	return worst


func _knee_of(paw: String) -> String:
	match paw:
		"Bone.018": return "Bone.016"
		"Bone.022": return "Bone.020"
		"Bone.014": return "Bone.012"
		"Bone.026": return "Bone.024"
	return ""


func _stretch_max(hip: Dictionary, ball: Dictionary) -> float:
	var m := 0.0
	for bn in PAWS:
		m = maxf(m, _max_dist(hip[bn], ball[bn]) / maxf(1e-6, _rest_reach(bn)))
	return m


func _max_dist(a: Array, b: Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, (a[i] - b[i]).length())
	return m


## 可达长度 = |髋-膝| + |膝-趾根|（与生成端的两节 IK 一致），用它把 hip_ball 归一化。
## 结果 ≤1 表示没超过可达范围；>1 说明 IK 被夹紧（脚没落到目标）。
func _rest_reach(bn: String) -> float:
	var hi := _skel.find_bone(LEGS[bn]["hip"])
	var ki := _skel.find_bone(_knee_of(bn))
	var bi := _skel.find_bone(LEGS[bn]["ball"])
	if hi < 0 or ki < 0 or bi < 0:
		return 1.0
	var gt := _skel.global_transform
	var h: Vector3 = (gt * _skel.get_bone_global_rest(hi)).origin
	var k: Vector3 = (gt * _skel.get_bone_global_rest(ki)).origin
	var b: Vector3 = (gt * _skel.get_bone_global_rest(bi)).origin
	return (k - h).length() + (b - k).length()

func _world(bn: String) -> Vector3:
	var bi := _skel.find_bone(bn)
	if bi < 0:
		return Vector3.ZERO
	return (_skel.global_transform * _skel.get_bone_global_pose(bi)).origin


func _mean(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


## 诊断：把某条腿逐帧的高度/水平位置打出来（判定"支撑相脚掌是否真的定在地面"）
func _dump(ap: AnimationPlayer, cn: String, bn: String, dt: float) -> void:
	var a: Animation = ap.get_animation(cn)
	ap.play(cn)
	ap.pause()
	var n := int(round(a.length / dt))
	for i in n + 1:
		var t := float(i) * dt
		ap.seek(t, true)
		await process_frame
		var p := _world(bn)
		print("GAITEVAL|dump|%s|%s|t=%.5f|y=%.5f|z=%.5f|x=%.5f" % [cn, bn, t, p.y, p.z, p.x])


## 诊断：打印导入后动画的全部轨道（路径 / 关键帧数 / 时间点），
## 用来判断"Godot 导入是否丢失或改写了关键帧"。
func _tracks(ap: AnimationPlayer, cn: String) -> void:
	var a: Animation = ap.get_animation(cn)
	print("GAITEVAL|tracks|%s|count=%d|length=%.5f" % [cn, a.get_track_count(), a.length])
	for t in a.get_track_count():
		var kc := a.track_get_key_count(t)
		var times := []
		for k in mini(kc, 20):
			times.append("%.5f" % a.track_get_key_time(t, k))
		print("GAITEVAL|track|%s|%d|%s|keys=%d|times=[%s]" % [
			cn, t, a.track_get_path(t), kc, ", ".join(times)])
