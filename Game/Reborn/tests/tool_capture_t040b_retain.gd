extends SceneTree
## T040b 视觉取证工具（**不是断言套件**）。
##
## 用法（必须走 `Tools/CaptureRun.ps1`，隐藏桌面 + GUI exe；不要 headless）：
##   powershell -File E:\Reborn\Tools\CaptureRun.ps1 -Script tests/tool_capture_t040b_retain.gd
##
## 场景：清空生态 → 全部区域鼠 total=0 → 在玩家前方 2 m 放一只鼠并登记到 Courtyard
## → `reconcile_region_population` 应“近处不退场、记 pending”。
## 帧：`Art/Probes/t040b_near_retained.png`（近处个体仍在）、`t040b_far_converged.png`
## （玩家走远后同一机位，个体已收敛退场）。
## 固定机位：相机挂在关卡根上，不跟随玩家，两帧机位一致。

const RES := Vector2i(1280, 720)
const MAIN := "res://scenes/core/main.tscn"
const BODY_SCENE := "res://scenes/characters/animal_body.tscn"
const MOUSE_ID := &"Mouse"
const CAT_ID := &"Cat"
const REGION_IDS: Array[String] = ["Courtyard", "Creek", "Roots", "Grass"]
const PNG_ROOT := "E:/Reborn/Art/Probes"


func _initialize() -> void:
	root.size = RES
	await _run()
	print("CAP|t040b|done")
	quit(0)


func _run() -> void:
	await process_frame
	var mouse := load("res://resources/species/mouse.tres") as SpeciesConfig
	var packed := load(MAIN) as PackedScene
	if mouse == null or packed == null:
		print("CAP|t040b|ERROR|load_failed")
		return
	var main := packed.instantiate()
	root.add_child(main)
	root.size = RES
	await _frames(3)
	var entry := main as MainEntry
	if entry == null:
		print("CAP|t040b|ERROR|main_root_not_entry")
		return
	var wd := root.get_node_or_null("/root/WorldDirector")
	var gs := root.get_node_or_null("/root/GameState")
	gs.set("test_mode", true)
	gs.call("unlock_species", MOUSE_ID)
	var picked := entry.select_species(CAT_ID)
	for _i in 240:
		if entry.ecology != null and entry.ecology.is_setup_done():
			var note := String((entry.ecology.spawn_report() as Dictionary).get("note", ""))
			if note != "nav_not_ready" and note != "retry_pending":
				break
		await physics_frame
	print("CAP|t040b|setup|picked=%s|player=%s" % [str(picked), entry.player.global_position])

	# 只保留一只“用手摆的”近距个体，数量全由它决定。
	for b in entry.ecology.npc_bodies():
		b.ai_enabled = false
	entry.ecology.clear()
	await _frames(2)
	for rid in REGION_IDS:
		_set_total(wd, StringName(rid), MOUSE_ID, 0, 0.0)

	var near := await _spawn(entry.level, mouse, entry.player.global_position + Vector3(2.0, 0.0, 0.0))
	var reg: bool = wd.call("register_region_body", &"Courtyard", MOUSE_ID, near)
	var player_pos := entry.player.global_position
	var rep: Dictionary = wd.call("reconcile_region_population", player_pos)
	print("CAP|t040b|near_state|registered=%s|removed=%d|pending=%d|body=%s|distance=%.2f" % [
		str(reg), int(rep.get("removed", -1)), int(rep.get("pending_excess", -1)),
		near.global_position, near.global_position.distance_to(player_pos)])

	# 固定机位：在个体背后 3 m、高 1.4 m 看过去（玩家也在旁侧）。
	var cam := Camera3D.new()
	entry.level.add_child(cam)
	cam.global_position = near.global_position + Vector3(-2.6, 1.4, -2.2)
	cam.look_at(near.global_position + Vector3(0.6, 0.0, 0.0), Vector3.UP)
	cam.fov = 60.0
	cam.current = true
	await _frames(20)
	var p1 := _shot("t040b_near_retained")
	print("CAP|t040b|frame1|png=%s|near_valid=%s|pending=%d" % [
		p1, str(is_instance_valid(near)),
		int((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1))])

	# 玩家走远（个体不动）：等两次 60 帧低频重试。
	entry.player.global_position = Vector3(20.0, player_pos.y, 16.0)
	await _physics(140)
	var dist := near.global_position.distance_to(entry.player.global_position) \
		if is_instance_valid(near) else -1.0
	var p2 := _shot("t040b_far_converged")
	print("CAP|t040b|frame2|png=%s|near_valid=%s|pending=%d|player=%s|distance=%.2f|active=%d" % [
		p2, str(is_instance_valid(near)),
		int((wd.get("last_reconcile") as Dictionary).get("pending_excess", -1)),
		entry.player.global_position, dist,
		int(wd.call("region_active_count", &"Courtyard", MOUSE_ID))])


func _set_total(wd: Node, region_id: StringName, species_id: StringName, total: int, next: float) -> void:
	var recs = wd.get("region_records")
	if not (recs is Dictionary):
		return
	var rec: Dictionary = (recs as Dictionary).get("%s|%s" % [String(region_id), String(species_id)], {})
	if rec.is_empty():
		return
	rec["total_count"] = total
	rec["next_recover_at"] = next


func _spawn(level: Node, cfg: SpeciesConfig, pos: Vector3) -> AnimalBody:
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as AnimalBody
	body.species_config = cfg
	body.player_controlled = false
	body.ai_enabled = false
	level.add_child(body)
	body.global_position = pos
	body.velocity = Vector3.ZERO
	await _frames(1)
	return body


func _shot(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(PNG_ROOT)
	var out := "%s/%s.png" % [PNG_ROOT, name]
	var img: Image = root.get_texture().get_image()
	var err := img.save_png(out)
	if err != 0:
		print("CAP|t040b|ERROR|save_png|%s|err=%d" % [out, err])
		return "<err:%d>" % err
	return out


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _physics(n: int) -> void:
	for _i in n:
		await physics_frame
