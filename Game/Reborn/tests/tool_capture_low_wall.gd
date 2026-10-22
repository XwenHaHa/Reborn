extends SceneTree
## ART03-⑮ 诊断用：单独把 `sm_wall_low_001.glb` 摆进空场景拍正/背两面，
## 把"模块本身有没有洞"和"生成器平铺有没有问题"分开。
##
## 用法：
##   & '<godot_console.exe>' --path 'E:\Reborn\Game\Reborn' `
##       --script 'res://tests/tool_capture_low_wall.gd' --quit-after 900 -- low-wall
##
## 产物：user://lowwall_front.png / lowwall_back.png

const RES := Vector2i(960, 480)
const SETTLE := 12
const ASSET := "res://assets/environment/sm_wall_low_001.glb"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.size = RES
	if args.has("low-wall"):
		await _run()
	else:
		print("CAP|lowwall|ERROR|need_arg|pass '-- low-wall'")
	print("CAP|lowwall|done")
	quit(0)


func _run() -> void:
	var packed: PackedScene = load(ASSET)
	if packed == null:
		print("CAP|lowwall|ERROR|load_failed")
		return
	var node: Node3D = packed.instantiate() as Node3D
	root.add_child(node)
	# 世界原点摆一块，背后放一块深色板当"衬板"背景，和前面对照
	var mi: MeshInstance3D = _find_mesh(node)
	if mi != null and mi.mesh != null:
		var aabb := mi.mesh.get_aabb()
		print("CAP|lowwall|aabb=%s|tris=%d" % [aabb.size, mi.mesh.get_faces().size() / 3])
	var cam := Camera3D.new()
	cam.name = "LowWallCam"
	cam.near = 0.02
	cam.far = 50.0
	cam.fov = 40.0
	root.add_child(cam)
	await process_frame
	for v in [{"tag": "lowwall_front", "pos": Vector3(0.0, 0.45, -3.4),
			"look": Vector3(0.0, 0.42, 0.0)},
			{"tag": "lowwall_back", "pos": Vector3(0.0, 0.45, 3.4),
			"look": Vector3(0.0, 0.42, 0.0)}]:
		cam.look_at_from_position(v["pos"], v["look"], Vector3.UP)
		cam.current = true
		print("CAP|lowwall|view=%s|pos=%s" % [v["tag"], v["pos"]])
		await _save(v["tag"])


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _save(tag: String) -> void:
	for i in SETTLE:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := root.get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		print("CAP|lowwall|%s|ERROR|no_image" % tag)
		return
	var path := "user://%s.png" % tag
	var err := img.save_png(path)
	print("CAP|lowwall|%s|save_result=%d (%s)|global=%s" % [
		tag, err, "OK" if err == OK else "FAIL", ProjectSettings.globalize_path(path)])
