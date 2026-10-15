class_name DebugEntry
extends Node3D
## T013 调试入口（**只用于开发/验证**）
##
## 边界（`Docs/Tasks/T013.md` §4 D1）：正式场景 `l_courtyard.tscn` / `main.tscn` **不得**含本节点；
## 调试 HUD / 路径可视化只存在于 `scenes/debug/debug_entry.tscn`。正式 HUD 属 T018。
##
## 提供四件事：
##   1) 一键切换猫 / 鼠两种玩家（重建 `AnimalBody`：碰撞胶囊、相机、导航层、HUD 全部同步）
##   2) 碰撞形状显示：用引擎开关 `SceneTree.debug_collisions_hint`（实测没有 `Viewport` 侧碰撞项；
##      运行时是否真的可见由像素差判据给出，见 `Docs/Evidence/T013.md`），**不自己画碰撞线**
##   3) 导航路径显示：`ImmediateMesh` 自己画线（T012 实测：引擎的导航调试视图**运行时画不出来**，
##      所以这里是"我们自己画的路径线"，不是引擎调试视图 —— 不谎称是引擎视图）
##   4) 只属于调试的 HUD + 移动参数记录（进关卡打印一次 `PARAMS|`，周期打印 `MOV|`）
##
## 不写物种名判断：
##   * 物种差异全部来自 `resources/species/*.tres`（这里只做**引用**与转述，不做数值判断）
##   * 导航层不写死数字，从关卡 `NavigationRegion3D` 的 `metadata/species_id` 反查
##   * 路径颜色按"配置在 `_config_pool()` 里的下标"取，不按物种名分支
##
## 遗留项 ②（T012 §9：「猫跨 0.50 树根屏障在导航层不可达」）在这里**只做可视化与记录**：
##   `probe_target` 是 T012 实测用过的车道端点（洞南侧），HUD 同时给出"本物种层"与"另一层"
##   到该点的路径长度与是否穿过洞口；是否加 `NavigationLink3D` 由负责人定，本任务不擅自加。

## 物种切换完成（测试与外部观察用）
signal species_switched(species_id: StringName)

const LEVEL_SCENE := preload("res://scenes/maps/l_courtyard.tscn")
const BODY_SCENE := preload("res://scenes/characters/animal_body.tscn")
const CAT_CONFIG := preload("res://resources/species/cat.tres")
const MOUSE_CONFIG := preload("res://resources/species/mouse.tres")

## 调试动作名（键码在 `project.godot`；测试用引擎常量 `KEY_F1..KEY_F5` 对照）
const ACTION_SWITCH_CAT := "debug_switch_cat"
const ACTION_SWITCH_MOUSE := "debug_switch_mouse"
const ACTION_TOGGLE_COLLISION := "debug_toggle_collision"
const ACTION_TOGGLE_PATH := "debug_toggle_path"
const ACTION_TOGGLE_HUD := "debug_toggle_hud"
const DEBUG_ACTIONS: Array[StringName] = [
	&"debug_switch_cat", &"debug_switch_mouse", &"debug_toggle_collision",
	&"debug_toggle_path", &"debug_toggle_hud",
]

## 路径颜色：按配置在池里的下标（0 = 第一个配置，1 = 第二个），不按物种名分支
const SPECIES_COLORS: Array[Color] = [Color(1.0, 0.35, 0.30), Color(0.25, 0.90, 1.00)]
## 探针路径颜色（遗留项 ②）
const PROBE_COLOR := Color(1.0, 0.85, 0.20)
## 自绘碰撞线框颜色（**不是**引擎调试视图的颜色约定，见文件末尾说明）
const COLLISION_WIRE_COLOR := Color(0.25, 1.0, 0.45)
## 胶囊/球线框的圆周段数
const CAPSULE_SEGMENTS := 12

## 导航代理的半径/高度余量（与 T012 烘焙口径一致：`agent_radius = 胶囊半径 + 0.01`）
const AGENT_RADIUS_MARGIN := 0.01
const AGENT_HEIGHT_MARGIN := 0.02
## 路径线抬高量（米）：导航面高度 = 地面 + 2×cell(T012 实测 = 0.14)，抬一点避免与面重叠
const PATH_LIFT := 0.04

## HUD / 路径刷新节流（物理帧）
const HUD_REFRESH_FRAMES := 5
const PATH_REFRESH_FRAMES := 6

## 遗留项 ② 的探针车道（**来自 T012 实测**：鼠洞口 x=26.5、屏障 z∈[18.5,19.5]）
const LEGACY_PROBE_FROM := Vector3(26.5, 0.10, 21.5)
const LEGACY_PROBE_TARGET := Vector3(26.5, 0.10, 16.5)
const HOLE_X := 26.5
const HOLE_HALF_W := 0.25
const BARRIER_Z_MIN := 18.5
const BARRIER_Z_MAX := 19.5

## 关卡场景（默认生态灰盒；测试可换）
@export var level_scene: PackedScene = LEVEL_SCENE
## 动物身体场景
@export var body_scene: PackedScene = BODY_SCENE
## 两个物种的配置（下标 0/1 决定路径颜色；不写物种名判断）
@export var cat_config: SpeciesConfig = CAT_CONFIG
@export var mouse_config: SpeciesConfig = MOUSE_CONFIG
## 起始物种（默认取第一个配置的 `species_id`）
@export var start_species: StringName = &""
## `MOV|` 记录的周期（秒）
@export var record_period_sec: float = 0.5
## 遗留项 ② 的探针目标点
@export var probe_target: Vector3 = LEGACY_PROBE_TARGET

## 关卡实例（其子节点里放玩家）
var level: Node3D = null
## 当前玩家（`AnimalBody`）
var player: AnimalBody = null
## 当前物种 ID（空 = 尚未成型）
var current_species: StringName = &""
## 调试 HUD（`CanvasLayer`，**只在调试入口里**）
var hud: CanvasLayer = null
var hud_label: Label = null
## 路径线（`ImmediateMesh`）
var path_mesh: MeshInstance3D = null
## 遗留项 ② 探针代理的定位锚点（`NavigationAgent3D` 不是 `Node3D`，位置靠父节点）
var _probe_anchor: Node3D = null
var main_agent: NavigationAgent3D = null
## 遗留项 ② 探针代理（固定车道端点，T012 口径）
var probe_agent: NavigationAgent3D = null

## 开关状态（对外只读方法：`collision_debug_enabled()` / `path_display_enabled()` / `hud_enabled()`）
var collision_debug_on := false
var path_display_on := false
var hud_on := true
## 是否已经打印过 `PARAMS|`（进关卡一次）
var params_logged := false
var params_log_lines := 0
## 已打印的 `MOV|` 行数
var mov_lines := 0
## 最近一次路径点数 / 长度（HUD 与测试读取）
var last_path_points := 0
var last_path_length := 0.0
## 最近一次自绘的碰撞形状数量（F3 关闭时为 0）
var collision_shapes_drawn := 0

var _main_mat: StandardMaterial3D = null
var _probe_mat: StandardMaterial3D = null
var _collision_mesh: MeshInstance3D = null
var _collision_mat: StandardMaterial3D = null
var _record_accum := 0.0
var _frame := 0
var _probe_cache: Dictionary = {}
var _probe_cache_frame := -1
## 遗留项 ② 探针结果缓存（导航查询不便宜；HUD 刷新频率高于查询需要）
const PROBE_CACHE_FRAMES := 30


func _ready() -> void:
	_build_level()
	_build_path_mesh()
	_build_collision_mesh()
	_build_hud()
	_apply_collision_debug()
	var first: StringName = start_species
	if first == &"":
		var pool := _config_pool()
		first = pool[0].species_id if not pool.is_empty() else &""
	if first != &"":
		switch_species(first)
	_refresh_hud()
	print("DBG|debug_entry_ready|level=%s|species=%s" % [
		level.name if level != null else "<none>", current_species
	])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_SWITCH_CAT):
		switch_species(_config_pool()[0].species_id)
	elif event.is_action_pressed(ACTION_SWITCH_MOUSE):
		var pool := _config_pool()
		if pool.size() > 1:
			switch_species(pool[1].species_id)
	elif event.is_action_pressed(ACTION_TOGGLE_COLLISION):
		toggle_collision_debug()
	elif event.is_action_pressed(ACTION_TOGGLE_PATH):
		toggle_path_display()
	elif event.is_action_pressed(ACTION_TOGGLE_HUD):
		toggle_hud()


func _physics_process(delta: float) -> void:
	_frame += 1
	_record_accum += delta
	if _record_accum >= record_period_sec:
		_record_accum = 0.0
		record_movement_line()
	if _frame % HUD_REFRESH_FRAMES == 0:
		_refresh_hud()
	if path_display_on and _frame % PATH_REFRESH_FRAMES == 0:
		_rebuild_path_mesh()


# ---------------------------------------------------------------------------
# 场景搭建
# ---------------------------------------------------------------------------

func _build_level() -> void:
	if level_scene == null:
		push_error("DebugEntry: level_scene 为空")
		return
	level = level_scene.instantiate() as Node3D
	if level == null:
		push_error("DebugEntry: level_scene 的根不是 Node3D")
		return
	level.name = "Level"
	add_child(level)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "DebugHUD"
	add_child(hud)
	hud_label = Label.new()
	hud_label.name = "DebugLabel"
	hud_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud_label.position = Vector2(12.0, 10.0)
	hud_label.add_theme_font_size_override("font_size", 14)
	hud_label.add_theme_color_override("font_color", Color(0.88, 1.0, 0.62))
	hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	hud_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(hud_label)
	hud.visible = hud_on


func _build_path_mesh() -> void:
	path_mesh = MeshInstance3D.new()
	path_mesh.name = "DebugPathMesh"
	path_mesh.mesh = ImmediateMesh.new()
	path_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mesh.visible = false
	add_child(path_mesh)
	_main_mat = _line_material(SPECIES_COLORS[0])
	_probe_mat = _line_material(PROBE_COLOR)


func _line_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.disable_receive_shadows = true
	return m


# ---------------------------------------------------------------------------
# 玩家：切换物种
# ---------------------------------------------------------------------------

## 切换玩家物种。**不 await**：旧身体 `queue_free()` 后立刻建新身体，
## 两者不互相碰撞（`collision_mask` 只有 world_static），所以不会互相干扰。
func switch_species(species_id: StringName) -> void:
	var cfg := _config_for(species_id)
	if cfg == null:
		push_error("DebugEntry: 没有物种 %s 的配置" % species_id)
		return
	_release_player()
	if level == null or body_scene == null:
		push_error("DebugEntry: 关卡或身体场景缺失")
		return

	player = body_scene.instantiate() as AnimalBody
	if player == null:
		push_error("DebugEntry: body_scene 的根不是 AnimalBody")
		return
	player.name = "Player"
	player.species_config = cfg        # 入树前赋值：_ready 里会 apply_config()
	player.player_controlled = true
	player.make_camera_current = true
	level.add_child(player)
	player.global_position = _spawn_position(cfg)
	player.velocity = Vector3.ZERO
	if player.climb != null:
		player.climb.reset_base()

	var layer := nav_layer_for(cfg.species_id)
	main_agent = _make_agent(player, cfg, layer)
	var target := _supply_target(cfg.species_id)
	if target != null:
		main_agent.target_position = target.global_position
	if probe_agent != null:
		probe_agent.navigation_layers = maxi(1, layer)
		probe_agent.set_navigation_map(_nav_map())
		probe_agent.target_position = probe_target

	current_species = cfg.species_id
	_probe_cache_frame = -1
	if _main_mat != null:
		_main_mat.albedo_color = SPECIES_COLORS[maxi(0, _config_index(cfg))]
	_rebuild_path_mesh()
	_rebuild_collision_mesh()
	_refresh_hud()

	if not params_logged:
		params_logged = true
		params_log_lines += 1
		print(params_line())
	species_switched.emit(current_species)
	print("DBG|switch_species|%s|spawn=%s|capsule_h=%.3f|nav_layer=%d|target=%s" % [
		current_species, player.global_position, cfg.capsule_height(), layer,
		str(main_agent.target_position) if main_agent != null else "<none>"
	])


func _release_player() -> void:
	if main_agent != null and is_instance_valid(main_agent):
		main_agent.queue_free()
	main_agent = null
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null


## 建立（或重建）遗留项 ② 的探针代理与固定起点。
##
## **踩坑（实测）**：`NavigationAgent3D` 继承 `Node`、**不是 `Node3D`**，它自己没有变换，
## 位置取自父节点。直接给它 `global_position` 赋值会报
## "Invalid assignment of property or key 'global_position' on NavigationAgent3D"。
## 所以先挂一个放在车道起点的 `Node3D` 锚点，代理挂在锚点下。
func _ensure_probe_agent() -> void:
	if probe_agent != null and is_instance_valid(probe_agent):
		return
	_probe_anchor = Node3D.new()
	_probe_anchor.name = "LegacyProbeAnchor"
	add_child(_probe_anchor)
	_probe_anchor.global_position = LEGACY_PROBE_FROM
	probe_agent = NavigationAgent3D.new()
	probe_agent.name = "LegacyProbeAgent"
	_probe_anchor.add_child(probe_agent)
	probe_agent.path_desired_distance = 0.25
	probe_agent.target_desired_distance = 0.25
	probe_agent.avoidance_enabled = false
	probe_agent.target_position = probe_target
	probe_agent.navigation_layers = maxi(1, nav_layer_for(current_species))
	probe_agent.set_navigation_map(_nav_map())


func _make_agent(body: Node3D, cfg: SpeciesConfig, layer: int) -> NavigationAgent3D:
	var a := NavigationAgent3D.new()
	a.name = "NavAgent"
	a.navigation_layers = maxi(1, layer)
	a.radius = cfg.capsule_radius + AGENT_RADIUS_MARGIN
	a.height = cfg.capsule_height() + AGENT_HEIGHT_MARGIN
	a.max_speed = cfg.sprint_speed
	a.path_desired_distance = 0.25
	a.target_desired_distance = 0.25
	a.avoidance_enabled = false
	body.add_child(a)
	a.set_navigation_map(_nav_map())
	return a


# ---------------------------------------------------------------------------
# 显示开关
# ---------------------------------------------------------------------------

## 碰撞形状显示开/关。**两件事一起做**：打开引擎开关 + 自绘线框（原因见文件末尾说明）。
func toggle_collision_debug() -> bool:
	collision_debug_on = not collision_debug_on
	_apply_collision_debug()
	_rebuild_collision_mesh()
	print("DBG|collision_debug=%s|engine_hint=%s|selfdraw_shapes=%d" % [
		"on" if collision_debug_on else "off", str(collision_debug_enabled()), collision_shapes_drawn
	])
	return collision_debug_on


## 碰撞形状显示的**引擎开关**：`SceneTree.debug_collisions_hint`。
## 实测（T013，`Docs/Evidence/T013.md`）：
##   * `Viewport.DEBUG_DRAW_*` 只有 0..4（DISABLED/UNSHADED/LIGHTING/OVERDRAW/WIREFRAME），**没有碰撞形状项**
##     —— 原规格 D3 写的 `Viewport.DEBUG_DRAW_COLLISION_SHAPES` 在 4.7 不存在（解析期即报错）。
##   * `PhysicsServer3D` **没有** 任何 debug 方法（探针实测 methods 为空）。
##   * 因此用 `debug_collisions_hint`；它在本环境（命令行运行）**是否真的画出形状**由像素差判据给出结论。
func _apply_collision_debug() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.debug_collisions_hint = collision_debug_on


## 直接问引擎（不读我们自己的标志位）：碰撞调试显示是否真的开着
func collision_debug_enabled() -> bool:
	var tree := get_tree()
	return tree != null and tree.debug_collisions_hint


## 导航路径显示开/关。返回新状态。
func toggle_path_display() -> bool:
	path_display_on = not path_display_on
	if path_mesh != null:
		path_mesh.visible = path_display_on
	if path_display_on:
		_rebuild_path_mesh()
	else:
		# 关掉就**立刻**清零 HUD 上的路径数字，不残留上一次的值（否则关掉后 HUD 还显示旧点数）
		last_path_points = 0
		last_path_length = 0.0
		var im := path_mesh.mesh as ImmediateMesh if path_mesh != null else null
		if im != null:
			im.clear_surfaces()
	print("DBG|path_display=%s" % ("on" if path_display_on else "off"))
	return path_display_on


func path_display_enabled() -> bool:
	return path_display_on


## 调试 HUD 开/关。返回新状态。
func toggle_hud() -> bool:
	hud_on = not hud_on
	if hud != null:
		hud.visible = hud_on
	print("DBG|hud=%s" % ("on" if hud_on else "off"))
	return hud_on


func hud_enabled() -> bool:
	return hud_on and hud != null and hud.visible


# ---------------------------------------------------------------------------
# 路径可视化（自己画，见文件头说明）
# ---------------------------------------------------------------------------

func _rebuild_path_mesh() -> void:
	if path_mesh == null:
		return
	var im := path_mesh.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	last_path_points = 0
	last_path_length = 0.0
	if not path_display_on:
		return
	if main_agent != null and is_instance_valid(main_agent):
		var main_path := main_agent.get_current_navigation_path()
		if main_path.size() < 2:
			# **实测坑**：`NavigationAgent3D` 的路径在"刚切完物种"或"只跑了 process 帧"时会短暂为空
			# （同一时刻用服务端查询却有完整路径）。为了不让路径显示一闪一闪，
			# 退回**服务端查询**：同一张地图、同一个图层、起点 = 玩家位置、终点 = 代理目标。
			# 仍然是我们自己画的线（不是引擎调试视图），只是数据来源换成服务端。
			var from: Vector3 = player.global_position if (
				player != null and is_instance_valid(player)
			) else LEGACY_PROBE_FROM
			main_path = _query(from, main_agent.target_position, nav_layer_for(current_species))
		last_path_points = main_path.size()
		last_path_length = path_length_of(main_path)
		_draw_path(im, main_path, _main_mat)
	_ensure_probe_agent()
	if probe_agent != null and is_instance_valid(probe_agent):
		var probe_path := probe_agent.get_current_navigation_path()
		if probe_path.size() < 2:
			# 探针的起点是固定车道端点（锚点位置），不是玩家位置
			probe_path = _query(LEGACY_PROBE_FROM, probe_agent.target_position,
				nav_layer_for(current_species))
		_draw_path(im, probe_path, _probe_mat)


func _draw_path(im: ImmediateMesh, path: PackedVector3Array, mat: StandardMaterial3D) -> void:
	if path.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(1, path.size()):
		im.surface_add_vertex(path[i - 1] + Vector3.UP * PATH_LIFT)
		im.surface_add_vertex(path[i] + Vector3.UP * PATH_LIFT)
	im.surface_end()


## 当前玩家路径点数（路径显示关时为 0）
func path_point_count() -> int:
	return last_path_points


## 当前玩家路径长度（米；路径显示关时为 0）
func path_length() -> float:
	return last_path_length


# ---------------------------------------------------------------------------
# 参数记录与询问
# ---------------------------------------------------------------------------

## 当前物种的移动参数（全部来自 `resources/species/*.tres`，不另立一份数）
func movement_parameters() -> Dictionary:
	if player == null or player.species_config == null:
		return {}
	var c := player.species_config
	return {
		"species_id": c.species_id,
		"walk_speed": c.walk_speed,
		"sprint_speed": c.sprint_speed,
		"crouch_speed": c.crouch_speed,
		"jump_velocity": c.jump_velocity,
		"max_step_height": c.max_step_height,
		"max_acceleration": c.max_acceleration,
		"capsule_radius": c.capsule_radius,
		"capsule_half_height": c.capsule_half_height,
		"capsule_height": c.capsule_height(),
		"crouch_half_height": c.crouch_half_height,
		"camera_offset_z": c.camera_offset_z,
		"fov": c.fov,
		"can_jump": c.can_jump,
		"nav_layer": nav_layer_for(c.species_id),
	}


## 进入关卡时打印一次的那一行
func params_line() -> String:
	var p := movement_parameters()
	if p.is_empty():
		return "PARAMS|<none>"
	return "PARAMS|%s|walk=%.3f|sprint=%.3f|crouch=%.3f|jump=%.3f|step=%.3f|accel=%.1f|r=%.3f|half_h=%.3f|h=%.3f|crouch_half=%.3f|cam=%.3f|fov=%.1f|nav_layer=%d" % [
		p["species_id"], p["walk_speed"], p["sprint_speed"], p["crouch_speed"], p["jump_velocity"],
		p["max_step_height"], p["max_acceleration"], p["capsule_radius"], p["capsule_half_height"],
		p["capsule_height"], p["crouch_half_height"], p["camera_offset_z"], p["fov"], p["nav_layer"],
	]


## 周期记录一行机器可读的移动状态（打印并返回）
func record_movement_line() -> String:
	mov_lines += 1
	var line := mov_line()
	print(line)
	return line


func mov_line() -> String:
	if player == null:
		return "MOV|species=<none>|frame=%d" % _frame
	var d := player.debug_state()
	var reason := "none"
	if player.climb != null and not player.climb.last_probe.is_empty():
		reason = str(player.climb.last_probe.get("reason", player.climb.last_probe.keys()))
	return "MOV|frame=%d|species=%s|pos=(%.3f, %.3f, %.3f)|vel=(%.3f, %.3f, %.3f)|wish=%.2f|stance=%s|on_floor=%s|headroom=%s|step_reason=%s|nav_points=%d|nav_len=%.2f|hp=%.1f|hunger=%.1f|thirst=%.1f|stamina=%.1f|iact=%s|iact_state=%s|iact_progress=%.2f" % [
		_frame, d["species_id"], d["position"].x, d["position"].y, d["position"].z,
		d["velocity"].x, d["velocity"].y, d["velocity"].z, d["wish_speed"],
		"crouch" if d["is_crouching"] else "stand", str(d["on_floor"]),
		"free" if d["headroom_free"] else "blocked", reason, last_path_points, last_path_length,
		float(d.get("health", -1.0)), float(d.get("hunger", -1.0)),
		float(d.get("thirst", -1.0)), float(d.get("stamina", -1.0)),
		_interaction_id(d), _interaction_state(d), _interaction_progress(d),
	]


## 当前交互目标 ID（无目标为 `-`）。**只显示一个**目标（T016：不列出全部候选）
func _interaction_id(d: Dictionary) -> String:
	var id := String(d.get("interaction_target_id", ""))
	return id if not id.is_empty() else "-"


## 交互动作状态（`idle` / `interacting`）
func _interaction_state(d: Dictionary) -> String:
	var st: Dictionary = d.get("interaction", {})
	return String(st.get("state", "idle"))


## 交互进度 0..1（`duration == 0` 立即式不会出现中间值）
func _interaction_progress(d: Dictionary) -> float:
	var st: Dictionary = d.get("interaction", {})
	return float(st.get("progress", 0.0))


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _refresh_hud() -> void:
	if hud_label != null:
		hud_label.text = hud_text()


func hud_text() -> String:
	var lines := PackedStringArray()
	lines.append("=== DEBUG (T013) 调试入口，不是正式界面 ===")
	if player == null or player.species_config == null:
		lines.append("species: <none>")
		return "\n".join(lines)
	var d := player.debug_state()
	var p := movement_parameters()
	lines.append("species: %s   stance: %s   speed: %.2f m/s   on_floor: %s" % [
		p["species_id"], "crouch" if d["is_crouching"] else "stand", d["wish_speed"], str(d["on_floor"])
	])
	lines.append("pos: (%.2f, %.2f, %.2f)   capsule r=%.3f h=%.3f" % [
		d["position"].x, d["position"].y, d["position"].z, p["capsule_radius"], p["capsule_height"]
	])
	lines.append("headroom: %s%s" % [
		"free" if d["headroom_free"] else "blocked",
		"  (stand blocked)" if d["stance_blocked_by_headroom"] else ""
	])
	var reason := "none"
	if player.climb != null and not player.climb.last_probe.is_empty():
		reason = str(player.climb.last_probe)
	lines.append("step_climb.last_probe: %s" % reason)
	lines.append("nav: layer=%d target=%s points=%d len=%.2f m" % [
		p["nav_layer"], str(main_agent.target_position) if main_agent != null else "<none>",
		last_path_points, last_path_length
	])
	var pr := probe_report()
	if not pr.is_empty():
		lines.append("probe(legacy2 猫跨屏障): own_layer=%d len=%.2f crosses_hole=%s | other_layer=%d len=%.2f crosses_hole=%s" % [
			pr["own_layer"], pr["own_len"], str(pr["own_crosses_hole"]),
			pr["other_layer"], pr["other_len"], str(pr["other_crosses_hole"])
		])
	lines.append("toggles: collision_debug=%s (engine_hint=%s selfdraw_shapes=%d)  path=%s  hud=%s" % [
		"on" if collision_debug_on else "off", str(collision_debug_enabled()), collision_shapes_drawn,
		"on" if path_display_on else "off", "on" if hud_on else "off"
	])
	if player.survival != null:
		# 生存状态（T014）：数值来自 `WorldDirector` 的世界时间；暂停时不会下降
		# 警告/危机标记（T015）：只读布尔量，阈值与扣血规则都在 `SurvivalController` 里
		var ss: SurvivalState = player.survival.state
		var warn := "none"
		if player.survival.is_low_hunger() and player.survival.is_low_thirst():
			warn = "hunger+thirst"
		elif player.survival.is_low_hunger():
			warn = "hunger"
		elif player.survival.is_low_thirst():
			warn = "thirst"
		var crisis := "none"
		if player.survival.is_starving() and player.survival.is_dehydrated():
			crisis = "exhaustion"
		elif player.survival.is_starving():
			crisis = "starvation"
		elif player.survival.is_dehydrated():
			crisis = "dehydration"
		lines.append("survival: health=%.1f hunger=%.1f thirst=%.1f stamina=%.1f  world_time=%.1f  warn=%s crisis=%s" % [
			ss.health, ss.hunger, ss.thirst, ss.stamina, player.world_time_now(), warn, crisis
		])
	lines.append("params: walk=%.2f sprint=%.2f crouch=%.2f jump=%.2f step=%.3f accel=%.0f cam=%.3f fov=%.0f can_jump=%s" % [
		p["walk_speed"], p["sprint_speed"], p["crouch_speed"], p["jump_velocity"],
		p["max_step_height"], p["max_acceleration"], p["camera_offset_z"], p["fov"], str(p["can_jump"])
	])
	if player.interaction != null:
		# 交互（T016）：**只显示一个**目标；拒绝理由与计数来自 `InteractionDetector`
		var ist: Dictionary = player.interaction.stats()
		var itarget := player.interaction.current_target_id()
		lines.append("interact: target=%s allowed=%s state=%s progress=%.2f reason=%s skipped=%d commits=%d cancels=%d" % [
			itarget if not itarget.is_empty() else "<none>", str(ist["allowed"]), str(ist["state"]),
			float(ist["progress"]), str(ist["deny_reason"]), int(ist["skipped"]),
			int(ist["commits"]), int(ist["cancels"])
		])
	lines.append("keys: F1=cat  F2=mouse  F3=collision  F4=path  F5=hud  (WASD/Space/Shift/Ctrl 同正式操作)")
	return "\n".join(lines)


# ---------------------------------------------------------------------------
# 遗留项 ② 探针（只记录与可视化，不擅自加跳跃链接）
# ---------------------------------------------------------------------------

## 用**固定车道端点**（T012 实测）问两层导航：本物种层能过去吗？另一层呢？
## `force` 忽略缓存。缓存 TTL 见 `PROBE_CACHE_FRAMES`（HUD 每 5 帧刷新，不能每次都问导航服务器）。
func probe_report(force: bool = false) -> Dictionary:
	if not force and _probe_cache_frame >= 0 and _frame - _probe_cache_frame <= PROBE_CACHE_FRAMES:
		return _probe_cache
	var map := _nav_map()
	if map == RID() or not map.is_valid():
		return {}
	var own := nav_layer_for(current_species)
	var layers := nav_layers_present()
	var other := 0
	for l in layers:
		if l != own:
			other = l
			break
	var own_path := _query(LEGACY_PROBE_FROM, probe_target, own)
	var other_path := _query(LEGACY_PROBE_FROM, probe_target, other) if other > 0 else PackedVector3Array()
	_probe_cache = {
		"from": LEGACY_PROBE_FROM,
		"target": probe_target,
		"own_layer": own,
		"own_len": path_length_of(own_path),
		"own_points": own_path.size(),
		"own_crosses_hole": path_crosses_hole(own_path),
		"other_layer": other,
		"other_len": path_length_of(other_path),
		"other_points": other_path.size(),
		"other_crosses_hole": path_crosses_hole(other_path),
	}
	_probe_cache_frame = _frame
	return _probe_cache


func _query(from: Vector3, to: Vector3, layer: int) -> PackedVector3Array:
	var map := _nav_map()
	if layer <= 0 or map == RID() or not map.is_valid():
		return PackedVector3Array()
	NavigationServer3D.map_force_update(map)
	return NavigationServer3D.map_get_path(map, from, to, true, layer)


## 路径是否穿过鼠洞口车道（|x−26.5| ≤ 0.25 且 z ∈ [18.5, 19.5]）。
## 线段与中点都查，避免"点恰好落在区间外"漏判。
func path_crosses_hole(path: PackedVector3Array) -> bool:
	for i in path.size():
		if _in_hole_lane(path[i]):
			return true
		if i > 0 and _in_hole_lane((path[i - 1] + path[i]) * 0.5):
			return true
	return false


func _in_hole_lane(p: Vector3) -> bool:
	return absf(p.x - HOLE_X) <= HOLE_HALF_W and p.z >= BARRIER_Z_MIN and p.z <= BARRIER_Z_MAX


# ---------------------------------------------------------------------------
# 关卡 / 配置查询
# ---------------------------------------------------------------------------

func _config_pool() -> Array[SpeciesConfig]:
	var pool: Array[SpeciesConfig] = []
	if cat_config != null:
		pool.append(cat_config)
	if mouse_config != null:
		pool.append(mouse_config)
	return pool


func _config_for(species_id: StringName) -> SpeciesConfig:
	for c in _config_pool():
		if c.species_id == species_id:
			return c
	return null


func _config_index(cfg: SpeciesConfig) -> int:
	var pool := _config_pool()
	for i in pool.size():
		if pool[i] == cfg:
			return i
	return 0


## 该物种的导航层：**从关卡反查**（`NavigationRegion3D.metadata/species_id`），不写死数字
func nav_layer_for(species_id: StringName) -> int:
	if level == null:
		return 0
	for n in level.get_children():
		var r := n as NavigationRegion3D
		if r != null and StringName(r.get_meta("species_id", &"")) == species_id:
			return r.navigation_layers
	return 0


## 关卡里出现过的所有导航层（去重、升序）
func nav_layers_present() -> Array[int]:
	var out: Array[int] = []
	if level == null:
		return out
	for n in level.get_children():
		var r := n as NavigationRegion3D
		if r == null:
			continue
		if not out.has(r.navigation_layers):
			out.append(r.navigation_layers)
	out.sort()
	return out


func _nav_map() -> RID:
	if level == null or level.get_world_3d() == null:
		return RID()
	return level.get_world_3d().get_navigation_map()


func _spawn_position(cfg: SpeciesConfig) -> Vector3:
	for n in get_tree().get_nodes_in_group("spawn_points"):
		var m := n as Node3D
		if m != null and StringName(m.get_meta("species", &"")) == cfg.species_id:
			return m.global_position
	# 没有出生点标记时的兜底：放到原点上方"胶囊底贴 y=0"
	return Vector3(0.0, cfg.capsule_half_height + 0.02, 0.0)


## 该物种的补给点（元数据 `species` 等于本物种或 `Both`）；找不到返回 null
func _supply_target(species_id: StringName) -> Node3D:
	for n in get_tree().get_nodes_in_group("supply_points"):
		var m := n as Node3D
		if m == null:
			continue
		var s := StringName(m.get_meta("species", &""))
		if s == species_id or s == &"Both":
			return m
	return null


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func path_length_of(path: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


# ---------------------------------------------------------------------------
# 碰撞形状可视化（F3）
#
# **为什么不只靠引擎开关**（实测，见 `Docs/Evidence/T013.md` §5）：
#   引擎里唯一相关的是 `SceneTree.debug_collisions_hint`；本环境（命令行运行）打开它之后画面
#   **逐字节不变**（两张 PNG 的 MD5 都是 `64DC75C7…`）→ 运行时看不到任何碰撞形状。
#   `Viewport.debug_draw` 没有碰撞形状项（实测只有 0..4：DISABLED/UNSHADED/LIGHTING/OVERDRAW/WIREFRAME），
#   `PhysicsServer3D` 没有任何 debug 方法（探针实测方法表里 debug 项为空）。
# 所以 F3 同时做两件事：
#   * 打开引擎开关（编辑器调试运行下才有效果，本环境**无法验证**，如实记录）
#   * **自己画**线框，保证本环境下真的可见 —— 诚实标注：这是自绘线框，不是引擎调试视图
# ---------------------------------------------------------------------------

func _build_collision_mesh() -> void:
	_collision_mesh = MeshInstance3D.new()
	_collision_mesh.name = "DebugCollisionMesh"
	_collision_mesh.mesh = ImmediateMesh.new()
	_collision_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_collision_mesh.visible = false
	add_child(_collision_mesh)
	_collision_mat = _line_material(COLLISION_WIRE_COLOR)


## 重建碰撞线框（F3 切换、切换物种后调用）
func _rebuild_collision_mesh() -> void:
	if _collision_mesh == null:
		return
	var im := _collision_mesh.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()
	collision_shapes_drawn = 0
	_collision_mesh.visible = collision_debug_on
	if not collision_debug_on:
		return
	var shapes := _collect_collision_shapes()
	if shapes.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES, _collision_mat)
	for cs in shapes:
		if cs.disabled or cs.shape == null:
			continue
		if _add_shape_wire(im, cs) > 0:
			collision_shapes_drawn += 1
	im.surface_end()
	print("DBG|collision_wire_shapes=%d" % collision_shapes_drawn)


## 关卡（含玩家，因为玩家是关卡的子节点）里所有 `CollisionShape3D`
func _collect_collision_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	if level == null:
		return out
	_collect_collision_shapes_in(level, out)
	return out


func _collect_collision_shapes_in(node: Node, out: Array[CollisionShape3D]) -> void:
	var cs := node as CollisionShape3D
	if cs != null:
		out.append(cs)
	for c in node.get_children():
		_collect_collision_shapes_in(c, out)


## 把一个 `CollisionShape3D` 画成线框。返回画出的线段数（0 = 该形状类型未支持）。
## 支持：`BoxShape3D`（12 条棱）、`CapsuleShape3D`（上下两个圆 + 12 条竖线）、
## `SphereShape3D`（3 个大圆）；其余类型（如 `WorldBoundaryShape3D`）跳过并计入"未支持"。
func _add_shape_wire(im: ImmediateMesh, cs: CollisionShape3D) -> int:
	var t := cs.global_transform
	var shape := cs.shape
	var pts := PackedVector3Array()
	if shape is BoxShape3D:
		var b := shape as BoxShape3D
		var h: Vector3 = b.size * 0.5
		var c: Array[Vector3] = [
			Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
		]
		var pairs: Array = [
			[0, 1], [1, 2], [2, 3], [3, 0],
			[4, 5], [5, 6], [6, 7], [7, 4],
			[0, 4], [1, 5], [2, 6], [3, 7],
		]
		for p in pairs:
			pts.append(c[p[0]])
			pts.append(c[p[1]])
	elif shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var r := cap.radius
		var half := maxf(0.0, cap.height * 0.5 - r)
		for i in CAPSULE_SEGMENTS:
			var a0 := TAU * float(i) / float(CAPSULE_SEGMENTS)
			var a1 := TAU * float(i + 1) / float(CAPSULE_SEGMENTS)
			for y in [-half, half]:
				pts.append(Vector3(cos(a0) * r, y, sin(a0) * r))
				pts.append(Vector3(cos(a1) * r, y, sin(a1) * r))
			pts.append(Vector3(cos(a0) * r, -half, sin(a0) * r))
			pts.append(Vector3(cos(a0) * r, half, sin(a0) * r))
	elif shape is SphereShape3D:
		var sp := shape as SphereShape3D
		var sr := sp.radius
		for i in CAPSULE_SEGMENTS:
			var a0 := TAU * float(i) / float(CAPSULE_SEGMENTS)
			var a1 := TAU * float(i + 1) / float(CAPSULE_SEGMENTS)
			pts.append(Vector3(cos(a0) * sr, sin(a0) * sr, 0.0))
			pts.append(Vector3(cos(a1) * sr, sin(a1) * sr, 0.0))
			pts.append(Vector3(cos(a0) * sr, 0.0, sin(a0) * sr))
			pts.append(Vector3(cos(a1) * sr, 0.0, sin(a1) * sr))
			pts.append(Vector3(0.0, cos(a0) * sr, sin(a0) * sr))
			pts.append(Vector3(0.0, cos(a1) * sr, sin(a1) * sr))
	else:
		return 0
	for p in pts:
		im.surface_add_vertex(t * p)
	return pts.size() / 2


## 当前自绘的碰撞形状数量（F3 关闭时为 0）
func drawn_collision_shapes() -> int:
	return collision_shapes_drawn
