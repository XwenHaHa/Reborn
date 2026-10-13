extends Node
## Reborn / Godot 能力探针主场景脚本
##
## 验证项：
##   1. 纯文本 .tscn 能被引擎解析并实例化
##   2. GDScript 能执行
##   3. 能读回引擎真实状态（版本、渲染器、物理、节点树）
##   4. 能创建并检查 3D 物理体与碰撞形状（P1 身体/导航的前置）
##   5. 逐条输出机器可读的 PROBE| 行，便于写入证据文件

const P := "PROBE|"


func _ready() -> void:
	_emit_engine_facts()
	_emit_node_tree()
	_probe_3d_physics()
	print(P + "probe_complete=1")
	get_tree().quit()


func _emit_engine_facts() -> void:
	print(P + "godot_version=" + str(Engine.get_version_info().string))
	var vi: Dictionary = Engine.get_version_info()
	print(P + "godot_major_minor=%d.%d" % [vi.major, vi.minor])
	print(P + "renderer=" + str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")))
	print(P + "display_driver=" + DisplayServer.get_name())
	print(P + "audio_driver=" + AudioServer.get_driver_name())
	print(P + "physics_engine=" + str(Engine.physics_ticks_per_second) + "hz")
	print(P + "main_scene=" + str(ProjectSettings.get_setting("application/run/main_scene", "unset")))


func _emit_node_tree() -> void:
	var names: Array[String] = []
	for child in get_children():
		names.append("%s(%s)" % [child.name, child.get_class()])
	print(P + "root_children=" + "|".join(names))
	print(P + "node_count=" + str(_count_nodes(self)))


func _count_nodes(n: Node) -> int:
	var total := 1
	for c in n.get_children():
		total += _count_nodes(c)
	return total


## P1（身体/导航）的前置验证：能否以脚本创建 CharacterBody3D + 胶囊碰撞，
## 并读回真实的碰撞尺寸。Parameters.md 里 Cat 胶囊半径 16 / 半高 24（单位 cm）。
func _probe_3d_physics() -> void:
	var body := CharacterBody3D.new()
	body.name = "ProbeBody"

	var shape := CollisionShape3D.new()
	shape.name = "ProbeShape"  # 显式命名；否则加入场景树时会被加上 @ 后缀
	var capsule := CapsuleShape3D.new()
	# Godot 用米；UE 用厘米。16cm 半径 / 24cm 半高 → 0.16m / 0.24m
	capsule.radius = 0.16
	capsule.height = 0.48  # CapsuleShape3D.height 是含两端半球的总高 = 2*(半高)
	shape.shape = capsule

	body.add_child(shape)
	add_child(body)

	# 读回引擎实际持有的值，而不是回显我们写入的值
	var readback := shape.shape as CapsuleShape3D
	print(P + "created_body_class=" + body.get_class())
	print(P + "shape_node_name=" + str(shape.name))
	print(P + "capsule_radius_m=%.4f" % readback.radius)
	print(P + "capsule_height_m=%.4f" % readback.height)
	print(P + "capsule_radius_cm=%.1f" % (readback.radius * 100.0))
	print(P + "capsule_total_height_cm=%.1f" % (readback.height * 100.0))
	print(P + "body_in_tree=" + str(body.is_inside_tree()))
	print(P + "collision_layer_default=" + str(body.collision_layer))
	print(P + "collision_mask_default=" + str(body.collision_mask))
	print(P + "body_children=" + "|".join(body.get_children().map(func(c: Node) -> String: return c.name)))
