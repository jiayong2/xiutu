extends RefCounted
## Synchronous authoring-only transaction. Journal is durable before targets change.
## No power-loss/fsync guarantee. Do not run concurrent writers.
var fault: Callable

static func commit(texts: Dictionary, journal: String) -> Dictionary:
	return new().save(texts, journal)

static func recover(journal: String) -> String:
	return new().restore(journal)

func _fail(stage: String, index: int) -> bool:
	return fault.is_valid() and bool(fault.call(stage, index))

func _write(path: String, text: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "无法写入：" + path
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(path) != text:
		return "写入回读不一致：" + path
	return ""

func _remove(path: String) -> String:
	if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK:
		return "无法清理：" + path
	return ""

func save(texts: Dictionary, journal: String) -> Dictionary:
	if FileAccess.file_exists(journal):
		return _result(false, "存在未完成事务，请先重新加载恢复：" + journal)
	var rows: Array = []
	for path in texts:
		if path == journal or FileAccess.file_exists(str(path) + ".skill_stage"):
			return _result(false, "存在保留文件/路径冲突：" + str(path))
		var original := ""
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				return _result(false, "无法读取原文件：" + str(path))
			var bytes := file.get_buffer(file.get_length())
			file.close()
			original = bytes.get_string_from_utf8()
			if original.to_utf8_buffer() != bytes:
				return _result(false, "原文件不是可无损往返的UTF-8，阻止覆盖：" + str(path))
		rows.append({"path": path, "existed": FileAccess.file_exists(path), "original": original, "hash": original.sha256_text(), "next": texts[path]})
	# Journal includes exact original text and complete target manifest, never overwritten.
	if _fail("backup", 0):
		return _result(false, "注入备份失败")
	var error := _write(journal, JSON.stringify({"version": 1, "rows": rows}))
	if not error.is_empty():
		return _result(false, error + "；保留恢复记录供人工检查：" + journal)
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var parser := JSON.new()
		if parser.parse(row.next) != OK:
			return _abort(journal, "待提交JSON无效：" + row.path)
		if _fail("prepare", i):
			return _abort(journal, "注入临时写入失败：" + row.path)
		error = _write(row.path + ".skill_stage", row.next)
		if not error.is_empty():
			return _abort(journal, error)
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		if _fail("commit", i):
			return _abort(journal, "注入提交失败：" + row.path)
		error = _remove(row.path)
		if error.is_empty() and DirAccess.rename_absolute(row.path + ".skill_stage", row.path) != OK:
			error = "替换失败：" + row.path
		if not error.is_empty():
			return _abort(journal, error)
		if _fail("crash", i):
			return _result(false, "模拟中断；保留事务：" + journal)
	for row in rows:
		if FileAccess.get_file_as_string(row.path) != row.next:
			return _abort(journal, "提交回读失败：" + row.path)
	error = _remove(journal)
	if not error.is_empty():
		return _abort(journal, error)
	var result := _result(true, "保存成功")
	result["files"] = texts.keys()
	return result

func _abort(journal: String, reason: String) -> Dictionary:
	var error := restore(journal)
	return _result(false, reason + ("；已完整回滚" if error.is_empty() else "；回滚失败，需要人工恢复：" + error))

func restore(journal: String) -> String:
	if not FileAccess.file_exists(journal):
		return ""
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(journal)) != OK or not parser.data is Dictionary or parser.data.get("version") != 1 or not parser.data.get("rows") is Array:
		return "事务记录损坏，保留原件：" + journal
	var rows: Array = parser.data.rows
	for row in rows:
		if not row is Dictionary or not row.get("path") is String or not row.get("original") is String or not row.get("existed") is bool or row.original.sha256_text() != row.get("hash"):
			return "事务记录校验失败：" + journal
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		if _fail("rollback", i):
			return "注入恢复失败；恢复记录：" + journal
		var error := _write(row.path, row.original) if row.existed else _remove(row.path)
		if not error.is_empty():
			return error + "；恢复记录：" + journal
		error = _remove(row.path + ".skill_stage")
		if not error.is_empty():
			return error + "；恢复记录：" + journal
	return _remove(journal)

func _result(success: bool, message: String) -> Dictionary:
	return {"success": success, "message": message, "warning": ""}
