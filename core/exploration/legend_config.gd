extends RefCounted

const MapData = preload("res://core/exploration/map_data.gd")
const Symbols = preload("res://core/exploration/symbols.gd")
const SPIRIT_STONES := "$spirit_stones"
const PATH := "res://authoring/exploration/legends.json"
const LEGACY_PATH := "user://exploration_config/legends.json"
const TYPES := {
	"M01": "妖兽", "M02": "妖兽", "M03": "妖兽",
	"O03": "资源", "O04": "资源", "O07": "资源",
	"O01": "宝箱", "O02": "宝箱", "O08": "宝箱", "S01": "传送",
}
const TARGETS := {"monster": "monsters", "item": "items", "event": "events"}
const BEHAVIORS := {"M01": "encounter", "M02": "encounter", "M03": "encounter",
	"O01": "reward", "O02": "reward", "O08": "reward", "O03": "herb", "O04": "ore",
	"O07": "spring", "S01": "portal"}

static func behavior(definition: Dictionary) -> String:
	return definition.get("behavior", BEHAVIORS.get(definition.get("symbol", ""), ""))

static func enemy_multiplier(definition: Dictionary) -> float:
	return float(definition.get("enemy_stat_multiplier", 1.2 if definition.symbol == "M02" else 1.0))

static func author_read_path() -> String:
	if FileAccess.file_exists(PATH) or not FileAccess.file_exists(LEGACY_PATH):
		return PATH
	return LEGACY_PATH

static func create(id: String) -> Dictionary:
	return {"legend_id": id, "name": "新图例", "category": TYPES.M01, "symbol": "M01",
		"target_type": "monster", "target_id": "", "level": 1, "enemy_count": 1,
		"blocks_movement": true, "trigger_type": "arrival", "respawn_mode": "none",
		"respawn_interval": 0, "repeatable": false, "completion_behavior": "cleared",
		"loot_table_id": "", "loot": []}

static func validate(rows: Dictionary, catalog: Dictionary) -> String:
	for id in rows:
		var row: Variant = rows[id]
		if not MapData.valid_id(id) or not row is Dictionary or row.get("legend_id") != id:
			return "图例 ID 无效：%s" % id
		if row.has("template_map_id") and not MapData.valid_id(row.template_map_id):
			return "%s：所属模板地图 ID 无效。" % id
		var symbol: Variant = row.get("symbol")
		if not symbol is String or not TYPES.has(symbol) or row.get("category") != TYPES[symbol]:
			return "%s：图例类型无效。" % id
		if not row.get("name") is String or row.name.strip_edges().is_empty():
			return "%s：请填写图例名称。" % id
		var event_kind: Variant = row.get("behavior", BEHAVIORS[symbol])
		if not event_kind is String or event_kind not in BEHAVIORS.values():
			return "%s：玩法行为无效。" % row.name
		if (event_kind == "encounter") != (row.category == "妖兽"):
			return "%s：玩法行为与图例类别不符。" % row.name
		var multiplier: Variant = row.get("enemy_stat_multiplier", 1.0)
		if not MapData.number(multiplier, 1.0, 1.2) or (multiplier != 1.0 and multiplier != 1.2):
			return "%s：敌人强化倍率无效。" % row.name
		var target: Variant = row.get("target_type")
		if not target is String or not row.get("target_id") is String:
			return "%s：绑定字段无效。" % row.name
		if row.category == "妖兽" and target != "monster":
			return "%s：请绑定已有妖兽。" % row.name
		if row.category != "妖兽" and target not in ["none", "item", "event"]:
			return "%s：绑定类型与图例不符。" % row.name
		if (target == "none" and not row.target_id.is_empty()) or (target != "none" and 				not catalog.get(TARGETS[target], {}).has(row.target_id)):
			return "%s：请选择有效的绑定对象。" % row.name
		if not _integer(row.get("level"), 1, 999) or not _integer(row.get("enemy_count"), 1, 99) 				or not _integer(row.get("respawn_interval"), 0, 999999) 				or (row.get("respawn_mode") == "interval" and row.respawn_interval < 1):
			return "%s：等级、数量或刷新间隔无效。" % row.name
		if not row.get("blocks_movement") is bool or not row.get("repeatable") is bool 				or row.get("trigger_type") not in ["arrival", "interact"] 				or row.get("respawn_mode") not in ["none", "reenter", "interval"] 				or row.get("completion_behavior") not in ["cleared", "hide"] 				or row.get("loot_table_id") not in ["", id]:
			return "%s：行为字段无效。" % row.name
		var loot_issue := validate_loot(row.get("loot", []), catalog)
		if not loot_issue.is_empty():
			return "%s：%s" % [row.name, loot_issue]
	return ""

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return MapData.number(value, minimum, maximum) and float(value) == floorf(float(value))

static func read(catalog: Dictionary, path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"rows": {}, "allocations": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法读取图例配置。"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "图例配置格式无效。原文件已保留。"}
	var version: Variant = parser.data.get("version")
	if (version != 1 and version != 2) or not parser.data.get("legends") is Dictionary:
		return {"error": "图例配置格式无效。原文件已保留。"}
	var issue := validate(parser.data.legends, catalog)
	var allocations: Variant = parser.data.get("allocations", {})
	if not allocations is Dictionary:
		return {"error": "地图分配格式无效。"}
	if issue.is_empty():
		issue = validate_allocations(allocations, parser.data.legends)
	return {"rows": parser.data.legends, "allocations": allocations} if issue.is_empty() else {"error": issue}

static func write(rows: Dictionary, catalog: Dictionary, path := PATH, allocations := {}) -> String:
	var issue := validate(rows, catalog)
	if issue.is_empty():
		issue = validate_allocations(allocations, rows)
	if not issue.is_empty():
		return issue
	return MapData.write_json(path, {"version": 2, "legends": rows, "allocations": allocations})

static func validate_loot(loot: Variant, catalog: Dictionary) -> String:
	if not loot is Array:
		return "掉落表格式无效。"
	for entry in loot:
		if not entry is Dictionary:
			return "掉落条目格式无效。"
		var item: Variant = entry.get("item_id")
		if not item is String or (item != SPIRIT_STONES and not catalog.items.has(item)):
			return "请选择有效的掉落物品。"
		if not _integer(entry.get("min"), 0, 999999) or not _integer(entry.get("max"), 0, 999999) or entry.min > entry.max:
			return "掉落数量范围无效，最小数量不能超过最大数量。"
		if not MapData.number(entry.get("chance"), 0, 100):
			return "掉落概率须在 0% 至 100% 内。"
	return ""

static func validate_allocations(allocations: Dictionary, rows: Dictionary, maps := {}) -> String:
	for map_id in allocations:
		var allocation: Variant = allocations[map_id]
		if not MapData.valid_id(map_id) or not allocation is Dictionary or not allocation.get("totals") is Dictionary or not allocation.get("counts") is Dictionary:
			return "地图分配格式无效：%s" % map_id
		var sums := {}
		var total := 0
		for id in allocation.counts:
			var count: Variant = allocation.counts[id]
			if not rows.has(id) or not _integer(count, 1, 1000):
				return "%s：图例分配无效或引用已不存在：%s" % [map_id, id]
			if rows[id].get("template_map_id", map_id) != map_id:
				return "%s：不能分配其他地图的专属图例：%s" % [map_id, id]
			var symbol: String = rows[id].symbol
			sums[symbol] = sums.get(symbol, 0) + int(count)
			total += int(count)
		for symbol in allocation.totals:
			var expected: Variant = allocation.totals[symbol]
			if not TYPES.has(symbol) or not _integer(expected, 0, 1000) or sums.get(symbol, 0) != expected:
				return "%s · %s：目标 %s，已分配 %d。" % [map_id, Symbols.title(str(symbol)), expected, sums.get(symbol, 0)]
		for symbol in sums:
			if not allocation.totals.has(symbol):
				return "%s · %s：请先设置目标数量。" % [map_id, Symbols.title(symbol)]
		if maps.has(map_id):
			var capacity := 0
			for node in maps[map_id].nodes:
				var symbol: String = node.get("icon_id", "")
				if symbol.is_empty() or TYPES.has(symbol):
					capacity += 1
			if total > capacity:
				return "%s：共分配 %d 格，可配置的格子上限为 %d。" % [map_id, total, capacity]
	return ""
