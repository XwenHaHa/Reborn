extends Control
## ART09-D：右上罗盘（程序化绘制，不引入图片/图标资源）。
##
## 只画玩家朝向：`hud.gd` 每帧把 `-yaw` 传进 `set_heading()`，这里不读任何游戏状态、不吃输入、
## 也不写玩法数据。指针朝北（Godot 里 0 偏航 = 面朝 −Z），玩家转身时指针反向摆动。

var heading_rad := 0.0

## 每帧调用；角度变化小于 0.002 rad 就不重绘（省一次 `queue_redraw`）
func set_heading(rad: float) -> void:
	if absf(wrapf(rad - heading_rad, -PI, PI)) < 0.002:
		return
	heading_rad = rad
	queue_redraw()


func _draw() -> void:
	var s := size
	var center := s * 0.5
	var radius := minf(s.x, s.y) * 0.5 - 1.0
	if radius <= 2.0:
		return
	draw_circle(center, radius, Color(0.020, 0.045, 0.045, 0.520))
	draw_arc(center, radius, 0.0, TAU, 64, Color(0.851, 0.588, 0.227, 0.520), 1.0, true)
	draw_arc(center, radius * 0.72, 0.0, TAU, 64, Color(0.851, 0.588, 0.227, 0.180), 1.0, true)
	for i in 4:
		var a := -PI * 0.5 + i * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		draw_line(center + dir * (radius - 2.0), center + dir * (radius - 8.0),
			Color(0.90, 0.88, 0.80, 0.800), 1.5, true)
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, Vector2(0.0, 12.0), "N", HORIZONTAL_ALIGNMENT_CENTER,
			s.x, 10, Color(0.95, 0.72, 0.32, 0.900))
	var needle := Vector2(0.0, -1.0).rotated(heading_rad)
	draw_line(center, center + needle * (radius - 12.0), Color(0.95, 0.72, 0.32, 0.950), 2.0, true)
	draw_line(center, center - needle * (radius - 16.0), Color(0.90, 0.88, 0.80, 0.420), 1.5, true)
	draw_circle(center, 2.0, Color(0.95, 0.72, 0.32, 0.950))
