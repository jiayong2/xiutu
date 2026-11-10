@tool
extends RefCounted

const Model := preload("res://core/npc_definitions.gd")

static func commit(npcs: Array, data: Dictionary, overrides: Dictionary, path: String = Model.PATH) -> Dictionary:
	if npcs.is_empty():
		return {"error": "没有可保存的人物", "rows": overrides}
	var roster: Dictionary = Model.roster(data, overrides)
	var merged: Dictionary = overrides.duplicate(true)
	for npc in npcs:
		if not npc is Dictionary or str(npc.get("id", "")).is_empty():
			return {"error": "生成结果缺少 NPC ID", "rows": overrides}
		var id: String = npc.id
		if roster.has(id) or merged.has(id):
			return {"error": "拒绝覆盖已有 NPC：" + id, "rows": overrides}
		var known: Dictionary = roster.duplicate()
		known.merge(merged, true)
		known[id] = npc
		var error := Model.validate(npc, data, known)
		if not error.is_empty():
			return {"error": "%s · %s" % [id, error], "rows": overrides}
		merged[id] = npc
	var error := Model.write_definitions(merged, data, path)
	if not error.is_empty():
		return {"error": error, "rows": overrides}
	var loaded := Model.load_definitions(data, path)
	if not loaded.error.is_empty():
		return {"error": loaded.error, "rows": overrides}
	return {"error": "", "rows": loaded.rows}
