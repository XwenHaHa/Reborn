extends SceneTree
## ART09 阶段 A 契约：视觉令牌、布局栅格、关键图资产、以及菜单里的同值别名。
##
## 目的：把「展板颜色/尺寸/字体/天空球」变成可断言的真源，避免 UI 里再散落魔法数。
## 运行：`godot --headless --path <proj> --script 'res://tests/run_art09_tokens.gd' --quit-after 30000`

var _checks := 0
var _fails := 0

func _initialize() -> void:
	_run()
	print("SUMMARY|checks=%d|failures=%d" % [_checks, _fails])
	print("RESULT|%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)


func _run() -> void:
	# --- 栅格 ---
	_check("design_size_is_1280x720", BoardTokens.DESIGN == Vector2i(1280, 720))
	_check("rail_left_at_1280", is_equal_approx(BoardTokens.rail_left(1280.0), 900.0))
	var metrics := BoardTokens.layout_metrics(Vector2(1280.0, 720.0))
	_check("metrics_button_size",
		(metrics["button"] as Vector2).is_equal_approx(Vector2(300.0, 52.0)))
	_check("metrics_card_height",
		is_equal_approx((metrics["card"] as Vector2).y, BoardTokens.CARD_H))
	_check("metrics_thumb_side", is_equal_approx(float(metrics["thumb"]), 64.0))
	print("TOKENS|rail_left=%.0f|center_width=%.0f|card=%s|thumb=%.0f" % [
		metrics["rail_left"], metrics["center_width"], str(metrics["card"]), metrics["thumb"],
	])

	# --- 字号阶必须单调（展板：书法 > 英文 > 副标题 > 正文 > 注释）---
	_check("font_scale_title_gt_latin",
		BoardTokens.FONT_TITLE > BoardTokens.FONT_TITLE_LATIN)
	_check("font_scale_card_name_gt_tag",
		BoardTokens.FONT_CARD_NAME > BoardTokens.FONT_CARD_TAG)
	_check("font_scale_tag_gt_note",
		BoardTokens.FONT_CARD_TAG >= BoardTokens.FONT_CARD_NOTE)

	# --- 书法字体：SystemFont + 中文候选优先 ---
	var font := BoardTokens.title_font()
	_check("title_font_exists", font != null)
	if font != null:
		_check("title_font_is_system_font", font is SystemFont)
		var names := (font as SystemFont).font_names
		_check("title_font_prefers_kai", names.size() > 0
			and (String(names[0]).contains("行楷") or String(names[0]).contains("Xingkai")))

	# --- 关键图：天空球 HDRI 必须在库；headless 下不强制解码 GPU 纹理 ---
	_check("sky_hdri_registered", ResourceLoader.exists(BoardTokens.ASSET_SKY_HDRI))
	if DisplayServer.get_name() != "headless":
		var tex := load(BoardTokens.ASSET_SKY_HDRI) as Texture2D
		_check("sky_hdri_loads", tex != null)
		if tex != null:
			var size := tex.get_size()
			print("TOKENS|sky_hdri=%dx%d" % [size.x, size.y])
			_check("sky_hdri_is_panorama", size.x > size.y)

	# --- 菜单里的同值别名：令牌改了而菜单没跟上，这里就会红 ---
	_check("menu_accent_matches_token",
		_color_close(MainMenu.COLOR_ACCENT, BoardTokens.GOLD, 0.03))
	_check("menu_thumb_matches_token", MainMenu.PREVIEW_PX == int(BoardTokens.THUMB))
	_check("menu_supersample_matches_token",
		MainMenu.PREVIEW_SUPERSAMPLE == BoardTokens.THUMB_SUPERSAMPLE)


func _color_close(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol \
		and absf(a.b - b.b) <= tol and absf(a.a - b.a) <= tol


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("ASSERT|%s|%s" % [label, "PASS" if ok else "FAIL"])
