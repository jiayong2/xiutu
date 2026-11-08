@tool
extends RefCounted
const NPC_BACKUP_LIMIT := 5
var error := ""
var source_checksum := ""

func write(payload: Dictionary, directory: String = "user://saves") -> String:
	error = ""
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "无法创建存档目录"
		return ""
	# Each save is a new revision. Existing player saves and backups stay intact.
	var path := "%s/save_%s_%s.json" % [directory,Time.get_datetime_string_from_system().replace(":","-"),Time.get_ticks_usec()]
	error = _write_atomic(path,_envelope(payload))
	return path if error.is_empty() else ""

func _envelope(payload: Dictionary) -> Dictionary:
	var text := JSON.stringify(payload,"",true,true)
	return {"version":1,"checksum":text.sha256_text(),"payload":text}

func _write_atomic(path: String, envelope: Dictionary) -> String:
	var stage_error := _stage(path+".tmp",envelope)
	if not stage_error.is_empty():
		return stage_error
	return _replace_staged(path)

func _stage(path: String, envelope: Dictionary) -> String:
	var f := FileAccess.open(path,FileAccess.WRITE)
	if f == null:
		return "无法写入存档"
	f.store_string(JSON.stringify(envelope))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		DirAccess.remove_absolute(path)
		return "无法完成存档写入"
	return ""

func _replace_staged(path: String) -> String:
	if DirAccess.rename_absolute(path+".tmp",path) != OK:
		DirAccess.remove_absolute(path+".tmp")
		return "无法完成存档写入"
	return ""

func replace_with_npc_backup(path: String, payload: Dictionary, expected_checksum: String) -> String:
	var directory := path.get_base_dir().path_join("npc_backups")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "无法创建 NPC 存档备份目录。"
	var lock := directory.path_join(".write_lock")
	if DirAccess.make_dir_absolute(lock) != OK:
		return "NPC 存档备份目录正在写入或无法锁定。"
	var result := _backup_and_replace(path,payload,expected_checksum,directory)
	DirAccess.remove_absolute(lock)
	return result

func _backup_and_replace(path: String, payload: Dictionary, expected_checksum: String, directory: String) -> String:
	var original := FileAccess.get_file_as_string(path)
	if original.is_empty() or original.sha256_text() != expected_checksum:
		return "目标存档已变化，请重新选择后再试。"
	var stage_error := _stage(path+".tmp",_envelope(payload))
	if not stage_error.is_empty():
		return stage_error
	var backup: Dictionary = JSON.parse_string(original)
	var slot := ""
	var oldest_slot := ""
	var oldest_order := 0
	var newest_order := 0
	for index in range(1,NPC_BACKUP_LIMIT + 1):
		var candidate := directory.path_join("npc_backup_%d.json" % index)
		if not FileAccess.file_exists(candidate):
			if slot.is_empty():
				slot = candidate
			continue
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		var order := int(previous.get("npc_backup_order",0)) if previous is Dictionary else 0
		newest_order = maxi(newest_order,order)
		if oldest_slot.is_empty() or order < oldest_order:
			oldest_slot = candidate
			oldest_order = order
	backup.npc_backup_order = newest_order + 1
	backup.npc_backup_source = path.get_file()
	var backup_error := _write_atomic(oldest_slot if slot.is_empty() else slot,backup)
	if not backup_error.is_empty():
		DirAccess.remove_absolute(path+".tmp")
		return "备份失败，原存档未替换。"
	return _replace_staged(path)

func read(path: String) -> Dictionary:
	error = ""
	source_checksum = ""
	var f := FileAccess.open(path,FileAccess.READ)
	if f == null:
		error = "无法打开存档"
		return {}
	var source := f.get_as_text()
	var envelope: Variant = JSON.parse_string(source)
	if not envelope is Dictionary or envelope.get("version") != 1 or not envelope.get("payload") is String:
		error = "存档格式或版本不支持"
		return {}
	if envelope.get("checksum") != envelope.payload.sha256_text():
		error = "存档校验失败"
		return {}
	var payload: Variant = JSON.parse_string(envelope.payload)
	if not payload is Dictionary:
		error = "存档内容无效"
		return {}
	source_checksum = source.sha256_text()
	return payload

func list_saves(directory: String = "user://saves") -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for file in DirAccess.get_files_at(directory):
		if file.begins_with("save_") and file.ends_with(".json"):
			result.append(directory+"/"+file)
	result.sort()
	result.reverse()
	return result
