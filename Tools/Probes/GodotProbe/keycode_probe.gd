extends SceneTree
## 键码探针：打印工程配置需要的键码常量，并回读本工程的 InputMap 实际绑定。
## 目的：不允许凭记忆把魔法数字写进 project.godot。

func _initialize() -> void:
	# 直接引用引擎常量，不可能抄错
	print("KEYCODE|ESCAPE=%d" % KEY_ESCAPE)
	print("KEYCODE|W=%d" % KEY_W)
	print("KEYCODE|A=%d" % KEY_A)
	print("KEYCODE|S=%d" % KEY_S)
	print("KEYCODE|D=%d" % KEY_D)
	print("KEYCODE|E=%d" % KEY_E)
	print("KEYCODE|SPACE=%d" % KEY_SPACE)
	print("KEYCODE|SHIFT=%d" % KEY_SHIFT)
	print("KEYCODE|CTRL=%d" % KEY_CTRL)
	print("KEYCODE|TAB=%d" % KEY_TAB)
	print("KEYCODE|MOUSE_BUTTON_LEFT=%d" % MOUSE_BUTTON_LEFT)

	print("--- 本工程 InputMap 实际绑定 ---")
	for action in [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "sprint", "crouch", "interact", "pounce", "pause",
	]:
		if not InputMap.has_action(action):
			print("INPUTMAP|%s|MISSING" % action)
			continue
		var codes: Array[String] = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				codes.append("key:%d" % (ev as InputEventKey).physical_keycode)
			elif ev is InputEventMouseButton:
				codes.append("mouse:%d" % (ev as InputEventMouseButton).button_index)
			else:
				codes.append(ev.get_class())
		print("INPUTMAP|%s|%s" % [action, ",".join(codes)])
	quit()
