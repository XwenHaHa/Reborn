extends SceneTree
## T043 打包环境探针（SelfTest 包内运行，不进发行包）。
## 只打印脱敏后的路径形态与包特征，不写存档、不记录个人路径。
##   & '<console.exe>' --headless --main-pack '<RebornSelfTest.pck>' --script 'res://tests/tool_t043_package_probe.gd'


func _initialize() -> void:
	# Godot 在 Windows 返回正斜杠路径，USERPROFILE 常是反斜杠：先统一再脱敏，
	# 保证日志里不出现个人目录（T043 要求只记录路径形态）。
	var home := OS.get_environment("USERPROFILE").replace("\\", "/")
	var user_dir := OS.get_user_data_dir().replace("\\", "/")
	var exe := OS.get_executable_path().replace("\\", "/")
	if home != "":
		user_dir = user_dir.replace(home, "<user>")
		exe = exe.replace(home, "<user>")
	print("PROBE|template=%s|debug=%s|user_dir=%s|exe=%s" % [
		str(OS.has_feature("template")), str(OS.is_debug_build()), user_dir, exe
	])
	print("PROBE|project_name=%s|save_path_shape=%s" % [
		ProjectSettings.get_setting("application/config/name", ""),
		user_dir.path_join("savegame_v1.json") if user_dir != "" else "<none>"
	])
	quit(0)
