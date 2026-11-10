@tool
extends RefCounted

const PATH := "res://data/world/npc_names.json"
const MAX_ATTEMPTS := 48

static func load_table(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "缺少 NPC 姓名表：" + path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取 NPC 姓名表"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "NPC 姓名表 JSON 无效"}
	var rows: Dictionary = parser.data
	for key in ["surnames", "given_male", "given_female", "given_shared"]:
		if not rows.get(key) is Array or rows[key].is_empty():
			return {"error": "NPC 姓名表缺少有效列表：" + key}
		for entry in rows[key]:
			if not entry is String or entry.strip_edges().is_empty():
				return {"error": "NPC 姓名表含空名称：" + key}
	return {"error": "", "rows": rows}

static func pick(random: RefCounted, table: Dictionary, gender: String, used: Dictionary) -> Dictionary:
	if table.is_empty():
		return {"error": "姓名表未加载"}
	var surnames: Array = table.surnames
	var given: Array = table.given_shared.duplicate()
	if gender == "女":
		given.append_array(table.given_female)
	else:
		given.append_array(table.given_male)
	if surnames.is_empty() or given.is_empty():
		return {"error": "姓名候选不足"}
	for _attempt in MAX_ATTEMPTS:
		var surname: String = _choice(random, surnames)
		var first: String = _choice(random, given)
		var name := surname + first
		if random.integer("world", 0, 9) >= 3:
			var second: String = _choice(random, given)
			if second != first:
				name = surname + first + second
		if name.length() > 24 or used.has(name):
			continue
		return {"error": "", "name": name}
	return {"error": "无法生成不重复姓名"}

static func _choice(random: RefCounted, items: Array) -> String:
	return str(items[random.integer("world", 0, items.size() - 1)])
