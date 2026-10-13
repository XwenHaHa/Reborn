extends SceneTree
## 场景修补工具（合并版 v2）：加光源/环境、激活相机、加区分材质。
##
## ---------------------------------------------------------------------------
## 核心原则（第一版踩坑后的修正）：
##   **场景编辑工具绝不能把场景加进场景树。**
##
##   第一版工具做了 `root.add_child(lab)` + `await process_frame` 再 `pack()` 保存。
##   后果：入树会执行各节点的 _ready() 与物理，
##   `PackedScene.pack()` 捕获的是**运行时状态**，于是把
##       Player.transform = (0, 1.4210554, 0)   ← 已下落 7.9cm
##       Player.velocity = Vector3(0, -1.1433334, 0)
##   烧进了场景文件。测试 run_t002 因此稳定失败，才发现此问题。
##
##   修正：全程在**未入树的实例**上操作。方向光/环境/材质都不需要入树；
##   Camera3D.current 直接在实例上设标志位也会被序列化。
##   另加"无意外变更"自检：编辑前后比对关键节点 transform，变了就报错。
## ---------------------------------------------------------------------------
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/tool_edit_lab_scene.gd'

const LAB := "res://scenes/maps/l_movement_lab.tscn"

## 编辑前后必须保持不变的节点（防止运行时状态被烧进场景）
const MUST_NOT_MOVE := ["Player", "PlayerStart", "Ground", "Camera3D"]

var _before: Dictionary = {}


func _initialize() -> void:
	print("TOOL|edit_lab|start")

	var packed: PackedScene = load(LAB)
	if packed == null:
		print("TOOL|ERROR|load failed")
		quit(1)
		return

	# 实例化但**不入树**
	var lab: Node3D = packed.instantiate()
	_snapshot(lab)

	_ensure_light(lab)
	_ensure_environment(lab)
	_ensure_camera_current(lab)
	_ensure_materials(lab)

	_verify_no_unintended_change(lab)

	var out := PackedScene.new()
	if out.pack(lab) != OK:
		print("TOOL|ERROR|pack failed")
		lab.free()
		quit(1)
		return
	var err := ResourceSaver.save(out, LAB)
	print("TOOL|save_result=%d (%s)" % [err, "OK" if err == OK else "FAIL"])
	lab.free()
	print("TOOL|edit_lab|done")
	quit(0)


func _snapshot(lab: Node3D) -> void:
	for nm in MUST_NOT_MOVE:
		var n := _find(lab, nm)
		if n is Node3D:
			_before[nm] = (n as Node3D).transform
	# 额外记录 Player 的速度，作为"是否跑了物理"的哨兵
	var p := _find(lab, "Player") as CharacterBody3D
	if p:
		_before["Player.velocity"] = p.velocity


func _verify_no_unintended_change(lab: Node3D) -> void:
	print("TOOL|-- 无意外变更自检 --")
	for nm in MUST_NOT_MOVE:
		var n := _find(lab, nm)
		if not (n is Node3D):
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


## 深度优先按名查找（不限层级，避免写死路径）
func _find(root_node: Node, nm: String) -> Node:
	if root_node.name == nm:
		return root_node
	for c in root_node.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null


func _ensure_light(lab: Node3D) -> void:
	var light := lab.get_node_or_null("SunLight") as DirectionalLight3D
	if light == null:
		light = DirectionalLight3D.new()
		light.name = "SunLight"
		lab.add_child(light)
		light.owner = lab  # 不设 owner，pack() 会跳过该节点
		print("TOOL|SunLight=created")
	else:
		print("TOOL|SunLight=reused")
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true


func _ensure_environment(lab: Node3D) -> void:
	var we := lab.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		lab.add_child(we)
		we.owner = lab
		print("TOOL|WorldEnvironment=created")
	else:
		print("TOOL|WorldEnvironment=reused")
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	print("TOOL|env|bg=%d|ambient=%d" % [env.background_mode, env.ambient_light_source])


## 在未入树的实例上设置 current 标志位；引擎会把它序列化为 `current = true`。
func _ensure_camera_current(lab: Node3D) -> void:
	var cam := _find(lab, "Camera3D") as Camera3D
	if cam == null:
		print("TOOL|ERROR|Camera3D not found")
		return
	cam.current = true
	print("TOOL|Camera3D.current_set=true (detached)")


## 材质：区分颜色提高对比度。
## 注意：**不加自发光**。第一版给物体加了 emission=0.25，vision 复核报告
## "立方体各面颜色几乎一致、立体感很弱"——自发光把方向光的明暗差冲掉了。
func _ensure_materials(lab: Node3D) -> void:
	_set_mat(lab, "Ground/GroundMesh", Color(0.32, 0.34, 0.36), 0.9)
	_set_mat(lab, "Ruler100cm", Color(0.90, 0.72, 0.18), 0.6)
	_set_mat(lab, "DirectionMarker", Color(0.18, 0.62, 0.85), 0.6)


func _set_mat(lab: Node3D, path: String, color: Color, roughness: float) -> void:
	var mi := lab.get_node_or_null(path) as MeshInstance3D
	if mi == null:
		print("TOOL|MISS_or_not_mesh|%s" % path)
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mi.material_override = mat
	print("TOOL|material|%s|%s" % [path, color.to_html(false)])
