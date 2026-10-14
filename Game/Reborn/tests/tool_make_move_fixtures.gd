extends SceneTree
## 场景生成工具（T009）：生成猫移动试验世界 `res://scenes/maps/l_move_fixtures.tscn`
##
## 为什么用工具而不是手写 .tscn：
##   与 `tests/tool_add_probe_asset.gd` 同规矩——**场景编辑绝不把场景加入场景树**
##   （否则 pack() 会把运行时状态写进文件），并且子资源（BoxMesh/BoxShape3D/材质）
##   由引擎序列化比手写可靠。
##
## 内容（`Docs/Tasks/T009.md` §7）——四个互不干扰的试验区，全部坐在 16×16 m 地面上（顶面 y=0.10）：
##   1) Ramp        2.0×0.2×6.0，绕 X 转 +25°，从 z≈1.5 处出地面、向 −Z 升高   → 斜坡测试
##   2) LowCeiling  板底 0.10+0.42=0.52（猫蹲高 0.30 < 0.42 < 猫站高 0.48）+ 4 柱 → 低顶测试（M02）
##   3) WallCornerA/B 0.3 厚、3 高，交成阳角（内侧面 x=−5.85、z=−5.85）        → 相机穿墙测试（M02）
##   4) Platform50  2.0×0.5×2.0，顶面 0.10+0.50=0.60                            → 50 cm 高台（M01）
##
## 运行：
##   & '<godot_console.exe>' --headless --path 'E:\Reborn\Game\Reborn' \
##       --script 'res://tests/tool_make_move_fixtures.gd'
## 幂等：每次都按同一套常量重建并覆盖，随后**重新加载**并核对几何（打印 VERIFY|）。

const OUT := "res://scenes/maps/l_move_fixtures.tscn"
const GROUND_SIZE := Vector3(16.0, 0.2, 16.0)
const GROUND_TOP := 0.1

const RAMP_DEG := 25.0
const RAMP_SIZE := Vector3(2.0, 0.2, 6.0)
## 让坡面在 z=1.5 处正好穿过地面顶面：坡顶面中心 = 坡体中心 + (厚度/2)·(0,cosθ,sinθ)
const RAMP_SURFACE_AT_Z := 1.5

## 低顶：板底相对地面顶的净空（必须 ∈ (猫蹲高 0.30, 猫站高 0.48)）
const LOW_CEILING_CLEARANCE := 0.42
const LOW_CEILING_SIZE := Vector3(2.6, 0.2, 2.6)
## 试验区的**分道**安排（互不干扰，别再放到同一条线上——踩过一次）：
##   * 斜坡：x∈[−1,1]，z∈[−1.7,4.6]
##   * 低顶：x=−6（支柱 x=±1.2 → −7.2/−4.8），z∈[−1.3,1.3]
##   * 墙角：内侧面 x=−5.85（wall A 的 z∈[−6,−2]）与 z=−5.85（wall B 的 x∈[−6,−2]）
##   * 50 cm 高台：x=6.5，z∈[−6,−4]；**它的助跑车道 x=6.5 必须空着**（平台测试从 z=−1.5 直冲）
##     曾经把低顶放在 x=6，结果平台助跑直接撞进低顶里（猫被压在地面、测不下去）。
##   * 鼠洞（T010）：x=2.5（两侧墙 x∈[1.5,2.38] 与 [2.62,3.5]），z≈−2；鼠的车道沿 x=2.5 从 z=+2 走到 z=−4
##   * 鼠低顶（T010）：x=−3.5，z∈[1.0,3.0]（支柱 ±0.8）；鼠从 z=5.0 往 −z 进
##     —— 这两个新车道都避开了 T009 的坡道(x∈[−1,1])、猫低顶(x=−6)、墙角(x/z≈−6)、高台(x=6.5)
const LOW_CEILING_POS := Vector3(-6.0, 0.0, 0.0)
const PILLAR_SIZE := Vector3(0.2, 0.42, 0.2)
const PILLAR_OFFSET := 1.2

## 墙角：两块墙交成阳角，内侧面在 x=−5.85 与 z=−5.85
const WALL_SIZE_A := Vector3(0.3, 3.0, 4.0)
const WALL_POS_A := Vector3(-6.0, 1.5, -4.0)
const WALL_SIZE_B := Vector3(4.0, 3.0, 0.3)
const WALL_POS_B := Vector3(-4.0, 1.5, -6.0)

## 50 cm 高台（M01）：顶面 = 地面顶 + 0.50
const PLATFORM_HEIGHT := 0.5
const PLATFORM_SIZE := Vector3(2.0, PLATFORM_HEIGHT, 2.0)
const PLATFORM_POS := Vector3(6.5, 0.0, -5.0)

## 鼠洞（T010，M01 的"内宽 24 / 高 30 cm 通道"）：三块盒子围出一个矩形开口，
## 不做 CSG（避免引入未验证的布尔几何）。开口中心 x = 2.5、z 厚度 0.2。
const TUNNEL_X_CENTER := 2.5
const TUNNEL_HALF_SPAN := 1.0          # 两侧墙从中心各延伸 1.0 m
const TUNNEL_THICK := 0.2              # 沿 z 的厚度
const TUNNEL_Z := -2.0                 # 洞所在 z
const TUNNEL_OPENING_W := 0.24         # 内宽（M01）
const TUNNEL_OPENING_H := 0.30         # 高（M01）
const TUNNEL_WALL_TOP := 1.10          # 两侧墙相对地面的顶高

## 鼠低顶（T010，M02 鼠部分）：净空必须夹在鼠蹲高 0.12 与鼠站高 0.18 之间。
## （猫蹲高 0.30 > 0.15 ⇒ 猫连蹲都进不去，顺带成为尺度对照。）
const MOUSE_LOW_CLEARANCE := 0.15
const MOUSE_LOW_SIZE := Vector3(2.0, 0.2, 2.0)
const MOUSE_LOW_POS := Vector3(-3.5, 0.0, 2.0)
const MOUSE_LOW_PILLAR := Vector3(0.2, MOUSE_LOW_CLEARANCE, 0.2)
const MOUSE_LOW_PILLAR_OFFSET := 0.8

var _fails := 0


func _initialize() -> void:
	print("TOOL|make_move_fixtures|start")

	var root_node := Node3D.new()
	root_node.name = "MoveFixtures"

	_add_ground(root_node)
	_add_ramp(root_node)
	_add_low_ceiling(root_node)
	_add_wall_corner(root_node)
	_add_platform(root_node)
	_add_mouse_tunnel(root_node)
	_add_mouse_low_ceiling(root_node)
	_add_spawn(root_node)
	_add_light_and_env(root_node)

	var out := PackedScene.new()
	if out.pack(root_node) != OK:
		print("TOOL|ERROR|pack failed")
		quit(1)
		return
	var err := ResourceSaver.save(out, OUT)
	print("TOOL|save_result=%d (%s)|path=%s" % [err, "OK" if err == OK else "FAIL", OUT])
	root_node.free()
	if err != OK:
		quit(1)
		return

	_verify()
	print("TOOL|make_move_fixtures|%s" % ("done" if _fails == 0 else "FAILED"))
	quit(0 if _fails == 0 else 1)


# ---------------------------------------------------------------------------
# 几何：与 `l_movement_lab.tscn` 保持同一口径（地面厚 0.2 居中于 y=0 → 顶面 0.10）
# ---------------------------------------------------------------------------

func _add_ground(parent: Node3D) -> void:
	_mk_box(parent, "Ground", GROUND_SIZE, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, Color(0.32, 0.34, 0.36))


func _add_ramp(parent: Node3D) -> void:
	var deg := deg_to_rad(RAMP_DEG)
	var normal := Vector3(0.0, cos(deg), sin(deg))          # 坡顶面法线（本地 +Y 映射）
	var center := Vector3(0.0, GROUND_TOP, RAMP_SURFACE_AT_Z) - normal * (RAMP_SIZE.y * 0.5)
	_mk_box(parent, "Ramp", RAMP_SIZE, center, Vector3(RAMP_DEG, 0.0, 0.0), Color(0.85, 0.55, 0.25))
	print("TOOL|Ramp|center=%s|deg=%.1f|slope_tan=%.4f" % [center, RAMP_DEG, tan(deg)])


func _add_low_ceiling(parent: Node3D) -> void:
	var slab_bottom := GROUND_TOP + LOW_CEILING_CLEARANCE
	var size := LOW_CEILING_SIZE
	var center := Vector3(LOW_CEILING_POS.x, slab_bottom + size.y * 0.5, LOW_CEILING_POS.z)
	_mk_box(parent, "LowCeiling", size, center, Vector3.ZERO, Color(0.55, 0.30, 0.75))
	print("TOOL|LowCeiling|slab_bottom=%.3f|clearance=%.3f" % [slab_bottom, LOW_CEILING_CLEARANCE])
	var pillar_y := GROUND_TOP + PILLAR_SIZE.y * 0.5
	var i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			i += 1
			_mk_box(
				parent,
				"LowCeilingPillar%d" % i,
				PILLAR_SIZE,
				Vector3(LOW_CEILING_POS.x + sx * PILLAR_OFFSET, pillar_y, LOW_CEILING_POS.z + sz * PILLAR_OFFSET),
				Vector3.ZERO,
				Color(0.45, 0.25, 0.60),
			)


func _add_wall_corner(parent: Node3D) -> void:
	_mk_box(parent, "WallCornerA", WALL_SIZE_A, WALL_POS_A, Vector3.ZERO, Color(0.60, 0.60, 0.64))
	_mk_box(parent, "WallCornerB", WALL_SIZE_B, WALL_POS_B, Vector3.ZERO, Color(0.60, 0.60, 0.64))
	print("TOOL|WallCorner|inner_x=%.3f|inner_z=%.3f" % [
		WALL_POS_A.x + WALL_SIZE_A.x * 0.5, WALL_POS_B.z + WALL_SIZE_B.z * 0.5
	])


func _add_platform(parent: Node3D) -> void:
	var center := Vector3(PLATFORM_POS.x, GROUND_TOP + PLATFORM_HEIGHT * 0.5, PLATFORM_POS.z)
	_mk_box(parent, "Platform50", PLATFORM_SIZE, center, Vector3.ZERO, Color(0.20, 0.65, 0.45))
	print("TOOL|Platform50|top=%.3f|height_above_ground=%.3f" % [
		center.y + PLATFORM_SIZE.y * 0.5, PLATFORM_HEIGHT
	])


## 鼠洞（T010）：三块盒子围出矩形开口（不做 CSG，避免引入未验证的布尔几何）
func _add_mouse_tunnel(parent: Node3D) -> void:
	var wall_top := TUNNEL_WALL_TOP                      # 绝对高度
	var wall_h: float = wall_top - GROUND_TOP
	var wall_cy: float = GROUND_TOP + wall_h * 0.5
	var half_w: float = TUNNEL_OPENING_W * 0.5
	var side_w: float = TUNNEL_HALF_SPAN - half_w
	var opening_top: float = GROUND_TOP + TUNNEL_OPENING_H
	var lintel_h: float = wall_top - opening_top
	var lintel_cy: float = opening_top + lintel_h * 0.5
	var wall_color := Color(0.50, 0.55, 0.62)

	_mk_box(parent, "MouseTunnelLeft", Vector3(side_w, wall_h, TUNNEL_THICK),
		Vector3(TUNNEL_X_CENTER - half_w - side_w * 0.5, wall_cy, TUNNEL_Z), Vector3.ZERO, wall_color)
	_mk_box(parent, "MouseTunnelRight", Vector3(side_w, wall_h, TUNNEL_THICK),
		Vector3(TUNNEL_X_CENTER + half_w + side_w * 0.5, wall_cy, TUNNEL_Z), Vector3.ZERO, wall_color)
	_mk_box(parent, "MouseTunnelLintel", Vector3(TUNNEL_OPENING_W, lintel_h, TUNNEL_THICK),
		Vector3(TUNNEL_X_CENTER, lintel_cy, TUNNEL_Z), Vector3.ZERO, wall_color)
	print("TOOL|MouseTunnel|opening=%.3f x %.3f|center_x=%.3f|z=%.3f|wall_top=%.3f" % [
		TUNNEL_OPENING_W, TUNNEL_OPENING_H, TUNNEL_X_CENTER, TUNNEL_Z, wall_top
	])


## 鼠低顶（T010）：板底净空必须夹在鼠蹲高与鼠站高之间
func _add_mouse_low_ceiling(parent: Node3D) -> void:
	var slab_bottom: float = GROUND_TOP + MOUSE_LOW_CLEARANCE
	var center := Vector3(MOUSE_LOW_POS.x, slab_bottom + MOUSE_LOW_SIZE.y * 0.5, MOUSE_LOW_POS.z)
	_mk_box(parent, "MouseLowCeiling", MOUSE_LOW_SIZE, center, Vector3.ZERO, Color(0.25, 0.60, 0.65))
	print("TOOL|MouseLowCeiling|slab_bottom=%.3f|clearance=%.3f" % [slab_bottom, MOUSE_LOW_CLEARANCE])
	var pillar_y: float = GROUND_TOP + MOUSE_LOW_PILLAR.y * 0.5
	var i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			i += 1
			_mk_box(
				parent,
				"MouseLowCeilingPillar%d" % i,
				MOUSE_LOW_PILLAR,
				Vector3(
					MOUSE_LOW_POS.x + sx * MOUSE_LOW_PILLAR_OFFSET,
					pillar_y,
					MOUSE_LOW_POS.z + sz * MOUSE_LOW_PILLAR_OFFSET,
				),
				Vector3.ZERO,
				Color(0.20, 0.48, 0.52),
			)


## 出生参考点（猫站在地面上时的身体中心高度 = 地面顶 + 半高）
func _add_spawn(parent: Node3D) -> void:
	var m := Marker3D.new()
	m.name = "CatSpawn"
	m.position = Vector3(0.0, GROUND_TOP + 0.24, 3.0)
	parent.add_child(m)
	m.owner = parent
	print("TOOL|CatSpawn|pos=%s" % m.position)


func _add_light_and_env(parent: Node3D) -> void:
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	parent.add_child(light)
	light.owner = parent

	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	parent.add_child(we)
	we.owner = parent


## 一个静态盒子：StaticBody3D（layer=world_static, mask=0）+ MeshInstance3D + CollisionShape3D
func _mk_box(
	parent: Node3D,
	nm: String,
	size: Vector3,
	pos: Vector3,
	rot_deg: Vector3,
	color: Color,
) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = nm
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees = rot_deg
	parent.add_child(sb)
	sb.owner = parent

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mi.material_override = mat
	sb.add_child(mi)
	mi.owner = parent

	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	cs.owner = parent
	return sb


# ---------------------------------------------------------------------------
# 自检：重新加载刚保存的文件，核对几何与设计意图常量（不是"文件存在"就算过）
# ---------------------------------------------------------------------------

func _verify() -> void:
	var packed: PackedScene = load(OUT)
	_check("scene_loads", packed != null)
	if packed == null:
		return
	var scene: Node3D = packed.instantiate() as Node3D
	_check("root_is_node3d", scene != null)
	if scene == null:
		return

	# 地面
	var ground := _box(scene, "Ground")
	_check("ground_top_is_0.10", not ground.is_empty() and absf(float(ground["top"]) - GROUND_TOP) < 1e-6)

	# 斜坡：绕 X 转 +25°、坡面在 z=1.5 处等于地面顶
	var ramp := _box(scene, "Ramp")
	if _check("ramp_exists", not ramp.is_empty()):
		var ramp_body := ramp["body"] as Node3D
		var xf: Transform3D = ramp_body.transform
		_check("ramp_deg_25", absf(xf.basis.get_euler().x - deg_to_rad(RAMP_DEG)) < 1e-4)
		var surface := _ramp_surface_y(ramp_body, RAMP_SURFACE_AT_Z)
		_check("ramp_meets_ground_at_z1.5", absf(surface - GROUND_TOP) < 1e-3)
		print("VERIFY|Ramp|surface_y_at_z1.5=%.4f|top_y_at_z_minus2=%.4f" % [
			surface, _ramp_surface_y(ramp_body, -2.0)
		])

	# 低顶
	var slab := _box(scene, "LowCeiling")
	if _check("low_ceiling_exists", not slab.is_empty()):
		var clearance: float = float(slab["bottom"]) - GROUND_TOP
		_check("low_ceiling_clearance_0.42", absf(clearance - LOW_CEILING_CLEARANCE) < 1e-6)
		# 设计意图：蹲得下（0.30 < 净空）但站不起（净空 < 0.48），因此净空必须介于两者之间
		_check("low_ceiling_between_crouch_and_stand", clearance > 0.30 and clearance < 0.48)
		print("VERIFY|LowCeiling|clearance=%.3f|slab_bottom=%.3f" % [clearance, float(slab["bottom"])])
	for i in range(1, 5):
		_check("low_ceiling_pillar%d_exists" % i, not _box(scene, "LowCeilingPillar%d" % i).is_empty())

	# 墙角
	var wa := _box(scene, "WallCornerA")
	var wb := _box(scene, "WallCornerB")
	if _check("wall_corner_exists", not wa.is_empty() and not wb.is_empty()):
		print("VERIFY|WallCorner|A_inner_x=%.3f|B_inner_z=%.3f" % [
			WALL_POS_A.x + WALL_SIZE_A.x * 0.5, WALL_POS_B.z + WALL_SIZE_B.z * 0.5
		])

	# 50 cm 高台
	var pf := _box(scene, "Platform50")
	if _check("platform_exists", not pf.is_empty()):
		var height: float = float(pf["top"]) - GROUND_TOP
		_check("platform_height_0.50", absf(height - PLATFORM_HEIGHT) < 1e-6)
		print("VERIFY|Platform50|top=%.3f|height_above_ground=%.3f|footprint_x=%s|footprint_z=%s" % [
			float(pf["top"]), height, [pf["min_x"], pf["max_x"]], [pf["min_z"], pf["max_z"]]
		])

	# 鼠洞（T010）：开口尺寸 + "鼠能过、猫过不去"的尺度关系（设计意图常量写在这里，测试从配置算）
	var tl := _box(scene, "MouseTunnelLeft")
	var tr := _box(scene, "MouseTunnelRight")
	var li := _box(scene, "MouseTunnelLintel")
	if _check("mouse_tunnel_exists", not tl.is_empty() and not tr.is_empty() and not li.is_empty()):
		var w: float = float(tr["min_x"]) - float(tl["max_x"])
		var h: float = float(li["bottom"]) - GROUND_TOP
		_check("mouse_tunnel_opening_w_0.24", absf(w - TUNNEL_OPENING_W) < 1e-6)
		_check("mouse_tunnel_opening_h_0.30", absf(h - TUNNEL_OPENING_H) < 1e-6)
		_check("mouse_tunnel_walls_start_at_ground",
			absf(float(tl["bottom"]) - GROUND_TOP) < 1e-6 and absf(float(tr["bottom"]) - GROUND_TOP) < 1e-6)
		# 设计意图（鼠站立 0.12×0.18 / 蹲 0.12×0.12；猫站立 0.32×0.48 / 蹲 0.32×0.30）
		_check("mouse_stand_fits_tunnel", 0.12 <= w and 0.18 <= h)
		_check("mouse_crouch_fits_tunnel", 0.12 <= w and 0.12 <= h)
		_check("cat_stand_does_not_fit_tunnel", 0.32 > w or 0.48 > h)
		_check("cat_crouch_does_not_fit_tunnel", 0.32 > w)
		print("VERIFY|MouseTunnel|opening_w=%.3f|opening_h=%.3f|center_x=%.3f|z=[%.2f,%.2f]" % [
			w, h, float(tl["max_x"]) + w * 0.5, float(tl["min_z"]), float(tl["max_z"])
		])

	# 鼠低顶（T010）：净空 = 0.15，夹在鼠蹲高 0.12 与鼠站高 0.18 之间（猫蹲高 0.30 进不去）
	var mlow := _box(scene, "MouseLowCeiling")
	if _check("mouse_low_ceiling_exists", not mlow.is_empty()):
		var cl: float = float(mlow["bottom"]) - GROUND_TOP
		_check("mouse_low_clearance_0.15", absf(cl - MOUSE_LOW_CLEARANCE) < 1e-6)
		_check("mouse_low_between_crouch_and_stand", cl > 0.12 and cl < 0.18)
		_check("cat_crouch_cannot_enter_mouse_low", cl < 0.30)
		print("VERIFY|MouseLowCeiling|clearance=%.3f|slab_bottom=%.3f|z=[%.2f,%.2f]" % [
			cl, float(mlow["bottom"]), float(mlow["min_z"]), float(mlow["max_z"])
		])
	for i in range(1, 5):
		_check("mouse_low_pillar%d_exists" % i, not _box(scene, "MouseLowCeilingPillar%d" % i).is_empty())

	_check("spawn_exists", scene.get_node_or_null("CatSpawn") != null)
	_check("has_light", scene.get_node_or_null("SunLight") != null)
	_check("has_environment", scene.get_node_or_null("WorldEnvironment") != null)
	scene.free()

## 取一个盒子 StaticBody3D 的尺寸/世界位置/上下/左右范围（本地坐标，场景根在原点）
func _box(scene: Node3D, nm: String) -> Dictionary:
	var sb := scene.get_node_or_null(nm) as StaticBody3D
	if sb == null:
		return {}
	var cs := sb.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D if cs != null else null
	if box == null:
		return {}
	var center: Vector3 = sb.position
	var half := box.size * 0.5
	return {
		"body": sb,
		"size": box.size,
		"center": center,
		"top": center.y + half.y,
		"bottom": center.y - half.y,
		"min_x": center.x - half.x,
		"max_x": center.x + half.x,
		"min_z": center.z - half.z,
		"max_z": center.z + half.z,
	}


## 坡面（顶面）在世界 z 处的高度：坡体绕 X 旋转，顶面为平面
func _ramp_surface_y(ramp: Node3D, world_z: float) -> float:
	var cs := ramp.get_node_or_null("Shape") as CollisionShape3D
	var box := cs.shape as BoxShape3D
	var half := box.size * 0.5
	var xf := ramp.transform
	var surface_center: Vector3 = xf * Vector3(0.0, half.y, 0.0)
	var normal: Vector3 = (xf.basis * Vector3.UP).normalized()
	if absf(normal.z) < 1e-9:
		return surface_center.y
	# 平面：normal·(p − surface_center) = 0，解 y（x 固定为坡面中心 x）
	return surface_center.y - normal.z * (world_z - surface_center.z) / normal.y


func _check(id: String, ok: bool) -> bool:
	if not ok:
		_fails += 1
	print("VERIFY|%s|%s" % [id, "OK" if ok else "FAIL"])
	return ok
