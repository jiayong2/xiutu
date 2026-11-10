extends RefCounted
## Author-only documents. Never loaded as playable content.
const Transaction := preload("res://core/skills/skill_file_transaction.gd")
const Database := preload("res://core/skills/skill_database.gd")

static func read(path: String) -> Dictionary:
	var error := Transaction.recover(path + ".transaction.json")
	if not error.is_empty():
		return {"error": error}
	if not FileAccess.file_exists(path):
		return {"error": "", "rows": []}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"error": "作者文件解析失败，保留原文件：" + path}
	if not parser.data is Array:
		return {"error": "作者文件必须是数组：" + path}
	var validation := _validate_rows(parser.data)
	if not validation.is_empty():
		return {"error": validation + "：" + path}
	return {"error": "", "rows": parser.data}

static func _validate_rows(rows: Array) -> String:
	var seen := {}
	for row in rows:
		if not row is Dictionary or not Database.valid_id(row.get("id")) or not row.get("payload") is Dictionary:
			return "作者文件含损坏记录，禁止覆盖"
		if str(row.get("kind", "")) not in ["technique", "spell", "effect"]:
			return "作者记录模式无效"
		if seen.has(row.id):
			return "作者记录ID重复：" + str(row.id)
		seen[row.id] = true
	return ""

static func write(path: String, rows: Array) -> Dictionary:
	var previous := read(path)
	if not previous.error.is_empty():
		return {"success": false, "message": previous.error}
	var validation := _validate_rows(rows)
	if not validation.is_empty():
		return {"success": false, "message": validation}
	var error := Database._json_safe(rows, "authoring")
	if not error.is_empty():
		return {"success": false, "message": error}
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return {"success": false, "message": "无法创建作者目录"}
	return Transaction.commit({path: JSON.stringify(rows, "\t")}, path + ".transaction.json")

static func merge(target: Dictionary, template: Dictionary, overwrite: bool, protect_identity: bool = true) -> Dictionary:
	var result := target.duplicate(true)
	for key in template:
		if protect_identity and key in ["id", "_source", "_persisted", "_draft", "_token", "node_id"]:
			continue
		if result.get(key) is Dictionary and template[key] is Dictionary:
			result[key] = merge(result[key], template[key], overwrite, false)
		elif overwrite or not result.has(key) or result[key] == null or (result[key] is String and result[key].is_empty()) or (result[key] is Array and result[key].is_empty()):
			result[key] = template[key].duplicate(true) if template[key] is Dictionary or template[key] is Array else template[key]
	return result
