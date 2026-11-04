extends SceneTree
## ART14：角色材质现状探针（headless）。
##
## 目的：把"现在是哪一项读作塑料"从主观描述变成可核对的材质参数清单。
## 只读，不改任何资产；对每个物种打印每个网格面的：
##   材质类、albedo 贴图、normal 贴图、metallic / roughness / specular、
##   是否双面/透明、顶点色、贴图过滤，以及"是否有任何次表面/毛绒近似"。
##
## 用法：
##   `& $g --headless --path $proj --script 'res://tests/tool_probe_art14_materials.gd' --quit-after 60000`

const A14CharacterMaterial := preload("res://scripts/characters/character_material.gd")

const SPECIES_DIR := "res://resources/species"


func _initialize() -> void:
	for p in _species_paths():
		var cfg := load(p) as SpeciesConfig
		if cfg == null or cfg.visual_scene == null:
			continue
		var inst := cfg.visual_scene.instantiate()
		root.add_child(inst)
		var sid := String(cfg.species_id)
		var meshes := _meshes_of(inst)
		print("PROBE|species=%s|meshes=%d|asset=%s" % [sid, meshes.size(), cfg.visual_scene.resource_path])
		for mi in meshes:
			print("PROBE|species=%s|mesh=%s|surfaces=%d" % [sid, String(mi.name), mi.mesh.get_surface_count()])
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				print("PROBE|species=%s|mesh=%s|surf=%d|SLOT|material_override=%s|mesh_mat=%s|override=%s" % [
					sid, String(mi.name), s,
					str(mi.material_override), str(mi.mesh.surface_get_material(s)),
					str(mi.get_surface_override_material(s)),
				])
				_dump(sid, String(mi.name), s, mat)
		if OS.get_cmdline_user_args().has("apply"):
			A14CharacterMaterial.apply_to(inst, cfg)
			for mi2 in meshes:
				for s2 in mi2.mesh.get_surface_count():
					var after := mi2.get_active_material(s2)
					print("PROBE|species=%s|mesh=%s|surf=%d|AFTER|class=%s|shader=%s" % [
						sid, String(mi2.name), s2, after.get_class() if after != null else "null",
						(after as ShaderMaterial).shader.resource_path if after is ShaderMaterial else "<none>",
					])
		inst.queue_free()
	print("PROBE|done")
	quit(0)


func _dump(sid: String, mesh_name: String, surface: int, mat: Material) -> void:
	var prefix := "PROBE|species=%s|mesh=%s|surf=%d" % [sid, mesh_name, surface]
	if mat == null:
		print("%s|MAT|null" % prefix)
		return
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		print("%s|MAT|ShaderMaterial|shader=%s" % [
			prefix, sm.shader.resource_path if sm.shader != null else "<null>",
		])
		return
	var std := mat as StandardMaterial3D
	if std == null:
		print("%s|MAT|%s" % [prefix, mat.get_class()])
		return
	var albedo_tex := std.albedo_texture
	var normal_tex := std.normal_texture
	var detail_tex := std.detail_albedo
	print("%s|MAT|StandardMaterial3D|albedo=%s|albedo_tex=%s" % [
		prefix, str(std.albedo_color),
		albedo_tex.resource_path if albedo_tex != null else "<null>",
	])
	print("%s|PBR|metallic=%.3f|roughness=%.3f|metallic_specular=%.3f|specular_mode=%d" % [
		prefix, std.metallic, std.roughness, std.metallic_specular, std.specular_mode,
	])
	print("%s|SURF|normal=%s|normal_scale=%.3f|detail=%s|rim=%s|rim_tint=%.3f" % [
		prefix, normal_tex.resource_path if normal_tex != null else "<null>",
		std.normal_scale, str(detail_tex), str(std.rim_enabled), std.rim,
	])
	print("%s|FLAGS|cull=%d|transparency=%d|shading=%d|vertex_color=%s|ao=%s|uv1_scale=%s" % [
		prefix, std.cull_mode, std.transparency, std.shading_mode,
		str(std.vertex_color_use_as_albedo), str(std.ao_enabled), str(std.uv1_scale),
	])


func _species_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SPECIES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			out.append(SPECIES_DIR + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _meshes_of(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for child in n.get_children():
		out.append_array(_meshes_of(child))
	return out
