@tool
extends RefCounted

const Config := preload("res://core/npc_generation/generation_config.gd")
const DIR := "res://authoring/npc_generation/templates"
const BUNDLED := ["template_rogue", "template_disciple", "template_prodigy", "template_elder", "template_custom"]

static func load_all(path: String = DIR) -> Dictionary:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"rows": {}, "error": "缺少生成模板目录：" + path}
	var directory := DirAccess.open(path)
	if directory == null:
		return {"rows": {}, "error": "无法打开生成模板目录"}
	var rows := {}
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var loaded := load_one(path.path_join(file_name))
			if not loaded.error.is_empty():
				return {"rows": {}, "error": loaded.error}
			var id: String = loaded.config.id
			if rows.has(id):
				return {"rows": {}, "error": "生成模板 ID 重复：" + id}
			rows[id] = loaded.config
		file_name = directory.get_next()
	return {"rows": rows, "error": ""}

static func load_one(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "找不到生成模板：" + path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取生成模板"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "生成模板 JSON 无效：" + path}
	var config := Config.normalize(parser.data)
	if config.id.strip_edges().is_empty():
		return {"error": "生成模板缺少 ID：" + path}
	return {"error": "", "config": config}

static func write_one(config: Dictionary, path: String) -> String:
	var normalized := Config.normalize(config)
	var directory := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return "无法创建模板目录"
	var staged := path + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return "无法写入临时模板文件"
	file.store_string(JSON.stringify(normalized, "\t") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return "写入生成模板失败"
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), ProjectSettings.globalize_path(path))
	return "" if error == OK else "无法替换生成模板文件"

static func path_for(id: String, directory: String = DIR) -> String:
	return directory.path_join(id + ".json")

static func copy_as(config: Dictionary, new_id: String, new_name: String, directory: String = DIR) -> String:
	var id := new_id.strip_edges()
	if not id.is_valid_filename() or id.is_empty() or "/" in id or "\\" in id:
		return "模板 ID 不合法"
	var copy: Dictionary = Config.normalize(config)
	copy.id = id
	copy.name = new_name.strip_edges() if not new_name.strip_edges().is_empty() else id
	copy.erase("seed")
	return write_one(copy, path_for(id, directory))

static func delete_one(id: String, directory: String = DIR) -> String:
	if id in BUNDLED:
		return "内置模板不能删除"
	var path := path_for(id, directory)
	if not FileAccess.file_exists(path):
		return "找不到生成模板：" + id
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return "" if error == OK else "无法删除生成模板"
