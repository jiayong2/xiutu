extends RefCounted
## Static and runtime reference lookup for monster deletion protection.
## Historical saves are intentionally outside this scan and the UI states that boundary.

const AUTHORING_LEGENDS := "res://authoring/exploration/legends.json"
const FORTUNE_SOURCE := "res://data/fortunes/catalog.gd"
const BATTLE_SOURCE := "res://core/operation_service.gd"

static func query(monster_id: String, catalog: Dictionary, runtime: Dictionary = {}) -> Dictionary:
	var groups: Array = []
	if monster_id.is_empty():
		return {"total": 0, "groups": groups}
	_add_routes(groups, monster_id, catalog)
	_add_quests(groups, monster_id, catalog)
	_add_exploration(groups, monster_id, catalog)
	_add_source(groups, monster_id, FORTUNE_SOURCE, "气运目录", "静态气运目标引用", "fortunes")
	_add_source(groups, monster_id, BATTLE_SOURCE, "战斗事件脚本", "OperationService 静态事件引用", "code")
	_add_runtime(groups, monster_id, runtime)
	var total := 0
	for group in groups:
		total += group.rows.size()
	return {"total": total, "groups": groups}

static func _add_routes(groups: Array, monster_id: String, catalog: Dictionary) -> void:
	var rows: Array = []
	var prototype: Dictionary = catalog.get("prototype", {})
	var entries: Array = prototype.get("outskirts_default_encounters", [])
	_scan_encounters(rows, entries, monster_id, "默认探索遭遇")
	for route in prototype.get("outskirts_routes", []):
		if not route is Dictionary:
			continue
		_scan_encounters(rows, route.get("encounters", []), monster_id,
			"路线：%s（%s）" % [str(route.get("name", route.get("id", ""))), str(route.get("id", ""))])
	if not rows.is_empty():
		groups.append({"key": "routes", "title": "探索路线与默认遭遇", "rows": rows})

static func _scan_encounters(rows: Array, entries: Variant, monster_id: String, label: String) -> void:
	if not entries is Array:
		return
	for entry in entries:
		if entry is Dictionary and str(entry.get("type", "")) == "monster" and str(entry.get("monster_id", "")) == monster_id:
			rows.append({"label": label, "detail": "遭遇权重 %d" % int(entry.get("weight", 0))})

static func _add_quests(groups: Array, monster_id: String, catalog: Dictionary) -> void:
	var rows: Array = []
	for quest in catalog.get("quests", {}).values():
		if not quest is Dictionary:
			continue
		var matched := str(quest.get("target", "")) == monster_id
		var detail := "任务目标" if matched else ""
		for objective in quest.get("objectives", []):
			if objective is Dictionary and str(objective.get("target_id", "")) == monster_id:
				matched = true
				detail = "任务子目标 %s" % str(objective.get("type", "目标"))
		if matched:
			rows.append({"label": "%s（%s）" % [str(quest.get("title", quest.get("id", ""))), str(quest.get("id", ""))], "detail": detail})
	if not rows.is_empty():
		groups.append({"key": "quests", "title": "任务目标", "rows": rows})

static func _add_exploration(groups: Array, monster_id: String, catalog: Dictionary) -> void:
	var rows: Array = []
	for map in catalog.get("exploration_maps", {}).values():
		if not map is Dictionary:
			continue
		var path := str(map.get("config_path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var parsed := _read_legends(path)
		_scan_legends(rows, parsed, monster_id, "地图 %s" % str(map.get("id", "")))
	_scan_legends(rows, _read_legends(AUTHORING_LEGENDS), monster_id, "作者草稿 legends.json")
	if not rows.is_empty():
		groups.append({"key": "exploration", "title": "探索地图图例", "rows": rows})

static func _read_legends(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	return data.get("legends", {}) if data.get("legends", {}) is Dictionary else {}

static func _scan_legends(rows: Array, legends: Dictionary, monster_id: String, source: String) -> void:
	for legend in legends.values():
		if legend is Dictionary and str(legend.get("target_type", "")) == "monster" and str(legend.get("target_id", "")) == monster_id:
			rows.append({"label": "%s · %s" % [source, str(legend.get("name", legend.get("legend_id", "")))], "detail": "图例 ID %s" % str(legend.get("legend_id", ""))})

static func _add_source(groups: Array, monster_id: String, path: String, title: String, detail: String, key: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	# Match quoted IDs so a short new ID cannot collide with ordinary words in code.
	if not text.contains("\"%s\"" % monster_id) and not text.contains("'%s'" % monster_id):
		return
	groups.append({"key": key, "title": title, "rows": [{"label": path.get_file(), "detail": detail}]})

static func _add_runtime(groups: Array, monster_id: String, runtime: Dictionary) -> void:
	var rows: Array = []
	var battle: Dictionary = runtime.get("battle", {})
	if str(battle.get("monster", "")) == monster_id:
		rows.append({"label": "当前战斗", "detail": "战斗实例正在使用该妖兽"})
	var run: Dictionary = runtime.get("exploration_run", {})
	var assigned: Dictionary = run.get("assigned", {})
	for node_id in assigned:
		var target: Dictionary = assigned[node_id]
		if target is Dictionary and str(target.get("target_type", "")) == "monster" and str(target.get("target_id", "")) == monster_id:
			rows.append({"label": "当前探索：%s" % str(node_id), "detail": "未完成的探索节点"})
	if not rows.is_empty():
		groups.append({"key": "runtime", "title": "当前运行状态", "rows": rows})
