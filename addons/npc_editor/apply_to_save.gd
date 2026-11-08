extends SceneTree

const Saves := preload("res://core/save_service.gd")
const RESULT_PREFIX := "NPC_SAVE_RESULT "

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		_finish("缺少目标存档或 NPC 草稿。")
		return
	var manager := root.get_node("GameManager")
	manager.set_process(false)
	if not manager.boot_ok:
		_finish(manager.repository.last_error)
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var drafts: Variant = request.get("drafts") if request is Dictionary else null
	if not drafts is Array or drafts.is_empty():
		_finish("NPC 草稿名单为空或无效。")
		return
	var ids := {}
	for draft in drafts:
		if not draft is Dictionary or not draft.get("id") is String or ids.has(draft.id):
			_finish("NPC 草稿无效或人物重复。")
			return
		ids[draft.id] = true
	var saves := Saves.new()
	var payload := saves.read(args[0])
	if not saves.error.is_empty():
		_finish(saves.error)
		return
	var expected_checksum := saves.source_checksum
	if request.get("source_checksum") != expected_checksum:
		_finish("存档在选择后发生变化。请重新读取该存档再修改。")
		return
	var operations: RefCounted = manager.operations
	var error: String = operations.restore_save(payload)
	if not error.is_empty():
		_finish(error)
		return
	var existing_npcs: Dictionary = operations.snapshot().npcs
	for draft in drafts:
		var result: Dictionary = operations.request("debug_import_npc", {"definition":draft,"refresh":existing_npcs.has(draft.id),"edit_saved_npc":true})
		if not result.success:
			_finish("%s：%s" % [draft.get("name",draft.id),result.message])
			return
	# Copy back only the edited NPCs after the whole batch succeeds.
	var updated_npcs: Dictionary = operations.snapshot().npcs
	for id in ids:
		payload.state.npcs[id] = updated_npcs[id]
	error = operations.validate_save(payload)
	if not error.is_empty():
		_finish(error)
		return
	error = saves.replace_with_npc_backup(args[0],payload,expected_checksum)
	_finish(error,args[0] if error.is_empty() else "")

func _finish(error: String, path: String = "") -> void:
	# Windows may decode child-process output using its local code page.
	# ASCII JSON escapes keep this result readable by old and new editor panels.
	var message := JSON.stringify({"path":path,"error":error})
	var escaped := PackedStringArray()
	for index in range(message.length()):
		var code := message.unicode_at(index)
		if code < 128:
			escaped.append(message[index])
		elif code <= 0xffff:
			escaped.append("\\u%04x" % code)
		else:
			code -= 0x10000
			escaped.append("\\u%04x\\u%04x" % [0xd800 + (code >> 10),0xdc00 + (code & 0x3ff)])
	print(RESULT_PREFIX + "".join(escaped))
	quit(0 if error.is_empty() and not path.is_empty() else 1)
