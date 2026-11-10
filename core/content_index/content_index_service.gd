@tool
extends RefCounted
## Read-only content index over the existing ContentCatalog tables.
## Does not write game data and does not keep a second content database.

const Catalog := preload("res://core/content_catalog.gd")
const Locations := preload("res://core/world_locations.gd")
const NpcDefinitions := preload("res://core/npc_definitions.gd")
const Fortunes := preload("res://gameplay/character/player_fortunes.gd")
const Relations := preload("res://core/content_index/content_relations.gd")
const Validator := preload("res://core/content_index/content_validator.gd")

const ITEM_SUB := {
	"材料": "material", "灵草": "material", "种子": "material", "战利品": "material",
	"丹药": "pill",
	"装备": "equipment", "防具": "equipment", "武器": "equipment",
	"法宝": "artifact",
}
const ITEM_SUB_LABEL := {
	"material": "材料", "pill": "丹药", "equipment": "装备", "artifact": "法宝", "other": "其他物品",
}
const CATEGORY_LABEL := {
	"town": "城镇", "sect": "宗门", "wild": "野外区域", "building": "建筑", "map": "探索地图",
	"npc": "NPC", "monster": "妖兽",
	"quest": "任务", "event": "世界事件", "dialogue": "对话",
	"item": "物品", "technique": "功法", "spell": "法术", "realm": "境界",
	"fortune_innate": "先天气运", "fortune_acquired": "后天气运",
}
const SOURCE_FILES := {
	"prototype": "res://data/world/prototype.json",
	"npc_overrides": "res://data/world/npc_overrides.json",
	"items": "res://data/items/items.json",
	"equipment": "res://data/items/equipment.json",
	"artifacts": "res://data/items/artifacts.json",
	"monsters": "res://data/monsters/monsters.json",
	"monster_skills": "res://data/monsters/skills.json",
	"quests": "res://data/quests/quests.json",
	"events": "res://data/world/events.json",
	"shops": "res://data/towns/shops.json",
	"inns": "res://data/towns/inns.json",
	"auctions": "res://data/towns/auctions.json",
	"announcements": "res://data/towns/announcements.json",
	"sect_areas": "res://data/world/sect_areas.json",
	"exploration_maps": "res://data/world/exploration_maps.json",
	"techniques": "res://data/skills/techniques.json",
	"spells": "res://data/skills/spells.json",
	"realms": "res://data/cultivation/realms.json",
	"realm_tiers": "res://data/cultivation/realm_tiers.json",
	"fortunes": "res://data/fortunes/catalog.gd",
	"home_view": "res://ui/main/home_view.gd",
}

var tables: Dictionary = {}
var records: Dictionary = {}
var issues: Array = []
var error := ""
var loaded_ok := false

func refresh(from_tables: Dictionary = {}) -> bool:
	error = ""
	records.clear()
	issues.clear()
	if from_tables.is_empty():
		var catalog := Catalog.new()
		loaded_ok = catalog.load_all(false)
		if not loaded_ok:
			error = catalog.error
			tables = catalog.tables.duplicate(true)
		else:
			tables = catalog.tables
			_load_overrides()
	else:
		tables = from_tables
		loaded_ok = true
		if not tables.has("npc_overrides"):
			_load_overrides()
	_index_all()
	Relations.attach(self)
	issues = Validator.collect(self)
	_apply_issue_status()
	return error.is_empty()

func get_record(key: String) -> Dictionary:
	return records.get(key, {})

func find_by_id(id: String, kind: String = "") -> Dictionary:
	if not kind.is_empty():
		return records.get("%s:%s" % [kind, id], {})
	var matches: Array = []
	for record in records.values():
		if str(record.get("id", "")) == id:
			matches.append(record)
	if matches.size() == 1:
		return matches[0]
	return {}

func list_category(category: String, subcategory: String = "") -> Array:
	var rows: Array = []
	for record in records.values():
		if str(record.category) != category:
			continue
		if not subcategory.is_empty() and str(record.get("subcategory", "")) != subcategory:
			continue
		rows.append(record)
	return rows

func list_region(region_id: String, include_related: bool = true) -> Array:
	var rows: Array = []
	for record in records.values():
		if region_id in record.get("region_ids", []):
			var copy: Dictionary = record.duplicate(true)
			copy.membership = "direct"
			rows.append(copy)
		elif include_related and region_id in record.get("related_region_ids", []):
			var copy: Dictionary = record.duplicate(true)
			copy.membership = "related"
			rows.append(copy)
	return rows

func search(rows: Array, needle: String) -> Array:
	var text := needle.strip_edges().to_lower()
	if text.is_empty():
		return rows
	var found: Array = []
	for record in rows:
		var hay := "%s %s %s" % [record.get("name", ""), record.get("id", ""), record.get("key", "")]
		if hay.to_lower().contains(text):
			found.append(record)
	return found

func sort_rows(rows: Array, mode: String) -> Array:
	var copy := rows.duplicate()
	match mode:
		"id":
			copy.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
		"category":
			copy.sort_custom(func(a, b): return str(a.get("category_label", "")) < str(b.get("category_label", "")))
		"region":
			copy.sort_custom(func(a, b): return _region_text(a) < _region_text(b))
		"status":
			copy.sort_custom(func(a, b): return str(a.get("status", "")) < str(b.get("status", "")))
		_:
			copy.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
	return copy

func count_category(category: String, subcategory: String = "") -> int:
	return list_category(category, subcategory).size()

func region_groups() -> Dictionary:
	var groups := {
		"town": [],
		"sect": [],
		"wild": [],
	}
	for record in records.values():
		if record.category in groups:
			groups[record.category].append(record)
	for key in groups:
		groups[key].sort_custom(func(a, b): return str(a.name) < str(b.name))
	return groups

func region_name(region_id: String) -> String:
	var names: Dictionary = Locations.names(tables)
	if names.has(region_id):
		return str(names[region_id])
	var record: Dictionary = records.get("town:%s" % region_id, records.get("wild:%s" % region_id, records.get("sect:%s" % region_id, {})))
	if not record.is_empty():
		return str(record.name)
	return region_id

func stats() -> Dictionary:
	var towns := count_category("town")
	var wild := count_category("wild")
	var maps := count_category("map")
	var sects := count_category("sect")
	var items := 0
	var fortunes := 0
	for record in records.values():
		if record.category == "item":
			items += 1
		elif str(record.category).begins_with("fortune"):
			fortunes += 1
	return {
		"town_map": towns + wild + maps + sects,
		"building": count_category("building"),
		"npc_monster": count_category("npc") + count_category("monster"),
		"quest_event": count_category("quest") + count_category("event"),
		"item_equip": items,
		"tech_fortune": count_category("technique") + count_category("spell") + fortunes,
		"npc": count_category("npc"),
		"monster": count_category("monster"),
		"quest": count_category("quest"),
		"event": count_category("event"),
		"dialogue": count_category("dialogue"),
		"technique": count_category("technique"),
		"spell": count_category("spell"),
		"realm": count_category("realm"),
		"fortune_innate": count_category("fortune_innate"),
		"fortune_acquired": count_category("fortune_acquired"),
		"issues": issues.size(),
		"total": records.size(),
	}

func region_counts(region_id: String) -> Dictionary:
	var counts := {
		"building": 0, "npc": 0, "quest": 0, "monster": 0, "item": 0, "event": 0, "dialogue": 0,
	}
	for record in list_region(region_id, false):
		if counts.has(record.category):
			counts[record.category] += 1
		elif record.category == "item":
			counts.item += 1
	return counts

func export_markdown() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# 《仙途》内容目录")
	lines.append("")
	var summary: Dictionary = stats()
	lines.append("条目总数：%d；待检查：%d" % [summary.total, summary.issues])
	lines.append("")
	var grouped := {}
	for record in sort_rows(records.values(), "category"):
		var label: String = record.category_label
		if record.category == "item":
			label = ITEM_SUB_LABEL.get(record.subcategory, "物品")
		if not grouped.has(label):
			grouped[label] = []
		grouped[label].append(record)
	for label in grouped:
		lines.append("## %s（%d）" % [label, grouped[label].size()])
		lines.append("")
		for record in grouped[label]:
			lines.append("- %s `%s` · %s · %s" % [record.name, record.id, _region_text(record), record.status])
		lines.append("")
	if not issues.is_empty():
		lines.append("## 数据检查异常")
		lines.append("")
		for issue in issues:
			lines.append("- %s `%s`：%s（%s）" % [issue.get("name", ""), issue.get("id", ""), issue.reason, issue.source])
		lines.append("")
	return "\n".join(lines)

func export_json() -> String:
	var payload := {
		"total": records.size(),
		"stats": stats(),
		"entries": [],
		"issues": issues.duplicate(true),
	}
	for record in sort_rows(records.values(), "id"):
		payload.entries.append({
			"id": record.id,
			"name": record.name,
			"category": record.category,
			"subcategory": record.get("subcategory", ""),
			"region_ids": record.get("region_ids", []),
			"related_region_ids": record.get("related_region_ids", []),
			"source": record.source,
			"status": record.status,
		})
	return JSON.stringify(payload, "\t")

func write_export(path: String, as_json: bool) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "无法写入：" + path
	file.store_string(export_json() if as_json else export_markdown())
	return ""

func editor_for(record: Dictionary) -> String:
	match str(record.get("category", "")):
		"npc":
			return "npc"
		"monster":
			return "monster"
		"item":
			if record.get("subcategory", "") == "artifact" and str(record.get("source_table", "")) == "artifacts":
				if not tables.get("items", {}).has(record.id):
					return ""
			return "item"
		"technique", "spell":
			return str(record.category)
		_:
			return ""

func _load_overrides() -> void:
	var authored: Dictionary = NpcDefinitions.load_definitions(tables)
	if authored.get("rows") is Dictionary:
		tables.npc_overrides = authored.rows
		if not str(authored.get("error", "")).is_empty() and error.is_empty():
			error = str(authored.error)
		return
	var file := FileAccess.open(NpcDefinitions.PATH, FileAccess.READ)
	if file == null:
		tables.npc_overrides = {}
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) == OK and parser.data is Dictionary:
		tables.npc_overrides = parser.data
	else:
		tables.npc_overrides = {}

func _index_all() -> void:
	var names: Dictionary = Locations.names(tables)
	for location_id in names:
		var kind := _location_kind(location_id)
		_add(kind, location_id, names[location_id], kind, "", [location_id], "prototype" if kind != "town" else "prototype")
	for sect in tables.get("prototype", {}).get("sects", []):
		if not sect is Dictionary or not sect.get("id") is String:
			continue
		var residence: Dictionary = sect.get("residence", {})
		var region: Array = []
		if residence.get("location_id") is String:
			region = [residence.location_id]
			if not records.has("sect:%s" % residence.location_id) and not names.has(residence.location_id):
				_add("sect", residence.location_id, str(residence.get("name", sect.name)), "sect", "", region, "prototype")
		_add("sect", sect.id, str(sect.get("name", sect.id)), "sect", "", region, "prototype")
	_index_buildings()
	_index_maps()
	_index_npcs()
	_index_monsters()
	_index_quests()
	_index_events()
	_index_items()
	_index_techniques()
	_index_spells()
	_index_realms()
	_index_fortunes()
	_index_dialogues()

func _index_buildings() -> void:
	for shop in _values(tables.get("shops", {})):
		_add("building", shop.id, str(shop.get("name", shop.id)), "building", "shop", _array(shop.get("location", "")), "shops", {"npc_id": str(shop.get("npc_id", ""))})
	for inn in _values(tables.get("inns", {})):
		_add("building", inn.id, str(inn.get("name", inn.id)), "building", "inn", _array(inn.get("location", "")), "inns", {"npc_id": str(inn.get("owner_npc_id", ""))})
	for auction in _values(tables.get("auctions", {})):
		_add("building", auction.id, str(auction.get("name", auction.id)), "building", "auction", _array(auction.get("location", "")), "auctions")
	for town_id in ["town_qinglan", "town_yunxi"]:
		_add("building", "building_board_%s" % town_id, "公告栏", "building", "board", [town_id], "home_view")
	_add("building", "building_qinglan_guard", "镇守府", "building", "guard", ["town_qinglan"], "home_view", {"npc_id": "npc_qin_shoushan"})
	_add("building", "building_yunxi_talisman", "符箓阁", "building", "talisman", ["town_yunxi"], "home_view", {"npc_id": "npc_lu_zhifu"})
	_add("building", "building_yunxi_tianji", "天机楼", "building", "tianji", ["town_yunxi"], "home_view")
	for sect in tables.get("prototype", {}).get("sects", []):
		var sect_id := str(sect.get("id", ""))
		var residence_id := str(sect.get("residence", {}).get("location_id", ""))
		var areas: Variant = tables.get("sect_areas", {}).get(sect_id, [])
		if not areas is Array:
			continue
		for area in areas:
			if not area is Dictionary:
				continue
			for card in area.get("cards", []):
				if not card is Dictionary or not card.get("id") is String:
					continue
				var building_id := "%s:%s:%s" % [sect_id, area.get("id", ""), card.id]
				_add("building", building_id, str(card.get("name", card.id)), "building", "sect", _array(residence_id), "sect_areas", {
					"sect_id": sect_id, "area_id": str(area.get("id", "")), "keepers": card.get("keepers", []),
				})

func _index_maps() -> void:
	for definition in _values(tables.get("exploration_maps", {})):
		_add("map", str(definition.get("id", "")), str(definition.get("entry_label", definition.get("id", ""))), "map", "exploration", _array(definition.get("location_id", "")), "exploration_maps")
	for route in tables.get("prototype", {}).get("outskirts_routes", []):
		if not route is Dictionary or not route.get("id") is String:
			continue
		_add("map", str(route.id), str(route.get("name", route.id)), "map", "route", ["area_qinglan_outskirts"], "prototype")

func _index_npcs() -> void:
	var roster: Dictionary = NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	for npc in roster.values():
		if not npc is Dictionary or not npc.get("id") is String:
			continue
		var source := "npc_overrides" if tables.get("npc_overrides", {}).has(npc.id) else "prototype"
		var extra := {
			"realm": npc.get("realm", 0),
			"role": str(npc.get("role", "")),
			"sect": str(npc.get("sect", "")),
			"sect_building": str(npc.get("sect_building", "")),
		}
		_add("npc", npc.id, str(npc.get("name", npc.id)), "npc", str(npc.get("role", "NPC")), _array(npc.get("location", "")), source, extra)

func _index_monsters() -> void:
	for monster in _values(tables.get("monsters", {})):
		var extra := {"realm": monster.get("realm", 0), "rank": str(monster.get("rank", ""))}
		_add("monster", monster.id, str(monster.get("name", monster.id)), "monster", str(monster.get("rank", "")), [], "monsters", extra)

func _index_quests() -> void:
	for quest in _values(tables.get("quests", {})):
		var regions: Array = []
		for objective in quest.get("objectives", []):
			if objective is Dictionary:
				_push_unique(regions, str(objective.get("target_location_id", "")))
		var giver: Dictionary = _npc(str(quest.get("giver_npc_id", "")))
		_push_unique(regions, str(giver.get("location", "")))
		_add("quest", quest.id, str(quest.get("title", quest.get("name", quest.id))), "quest", str(quest.get("quest_type", "")), regions, "quests", {"quest_type": str(quest.get("quest_type", ""))})

func _index_events() -> void:
	for event in _values(tables.get("events", {})):
		_add("event", event.id, str(event.get("name", event.id)), "event", "world", _array(event.get("location_id", "")), "events")

func _index_items() -> void:
	var equipment: Dictionary = tables.get("equipment", {})
	var artifacts: Dictionary = tables.get("artifacts", {})
	for item in _values(tables.get("items", {})):
		var type_name := str(item.get("type", ""))
		var sub: String = ITEM_SUB.get(type_name, "other")
		var extra := {"type": type_name, "rarity": str(item.get("rarity", "")), "quality": str(item.get("rarity", ""))}
		if equipment.has(item.id) and equipment[item.id] is Dictionary:
			extra.quality = str(equipment[item.id].get("quality", extra.quality))
			extra.slot = str(equipment[item.id].get("slot", ""))
		_add("item", item.id, str(item.get("name", item.id)), "item", sub, [], "items", extra)
	for artifact in _values(artifacts):
		if records.has("item:%s" % artifact.id):
			continue
		_add("item", artifact.id, str(artifact.get("name", artifact.id)), "item", "artifact", [], "artifacts", {"quality": str(artifact.get("quality", "")), "type": "法宝"})

func _index_techniques() -> void:
	for technique in _values(tables.get("techniques", {})):
		_add("technique", technique.id, str(technique.get("name", technique.id)), "technique", str(technique.get("cultivation_route", "")), [], "techniques", {"rarity": str(technique.get("rarity", ""))})

func _index_spells() -> void:
	for spell in _values(tables.get("spells", {})):
		_add("spell", spell.id, str(spell.get("name", spell.id)), "spell", str(spell.get("element", "")), [], "spells", {"element": str(spell.get("element", ""))})

func _index_realms() -> void:
	for realm in _values(tables.get("realms", {})):
		_add("realm", realm.id, str(realm.get("id", "")), "realm", "qi_stage", [], "realms")
	for tier in _values(tables.get("realm_tiers", {})):
		var name := "%s / %s" % [str(tier.get("qi", "")), str(tier.get("body", ""))]
		_add("realm", tier.id, name, "realm", "tier", [], "realm_tiers")

func _index_fortunes() -> void:
	for id in Fortunes.DEFINITIONS:
		var definition: Dictionary = Fortunes.DEFINITIONS[id]
		var kind := "fortune_innate" if str(definition.get("kind", "")) == "innate" else "fortune_acquired"
		_add(kind, id, str(definition.get("name", id)), kind, str(definition.get("quality", "")), [], "fortunes", {"quality": str(definition.get("quality", ""))})

func _index_dialogues() -> void:
	var roster: Dictionary = NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	for npc in roster.values():
		var greeting := str(npc.get("greeting", "")).strip_edges()
		if greeting.is_empty():
			continue
		_add("dialogue", "dlg_%s_greeting" % npc.id, "%s · 问候" % str(npc.get("name", npc.id)), "dialogue", "greeting", _array(npc.get("location", "")), "prototype" if not tables.get("npc_overrides", {}).has(npc.id) else "npc_overrides", {"npc_id": npc.id})
	for quest in _values(tables.get("quests", {})):
		for objective in quest.get("objectives", []):
			if not objective is Dictionary:
				continue
			if str(objective.get("objective_type", "")) not in ["TALK_OPTION", "REPORT_NPC"]:
				continue
			var label := str(objective.get("completion_condition", {}).get("label", objective.get("description", objective.get("objective_id", ""))))
			_add("dialogue", "dlg_%s_%s" % [quest.id, objective.get("objective_id", "")], label, "dialogue", "quest", _array(objective.get("target_location_id", "")), "quests", {"quest_id": quest.id, "npc_id": str(objective.get("target_id", ""))})

func _add(kind: String, id: String, name: String, category: String, subcategory: String, region_ids: Array, source_table: String, extra: Dictionary = {}) -> void:
	if id.strip_edges().is_empty():
		return
	var key := "%s:%s" % [kind, id]
	if records.has(key):
		return
	var regions: Array = []
	for region in region_ids:
		_push_unique(regions, str(region))
	var record := {
		"key": key,
		"id": id,
		"name": name if not name.strip_edges().is_empty() else id,
		"kind": kind,
		"category": category,
		"category_label": CATEGORY_LABEL.get(category, category),
		"subcategory": subcategory,
		"region_ids": regions,
		"related_region_ids": [],
		"source_table": source_table,
		"source": SOURCE_FILES.get(source_table, source_table),
		"status": "已配置",
		"fields": extra,
		"relations": [],
		"issue_reasons": [],
	}
	if category == "item":
		record.category_label = ITEM_SUB_LABEL.get(subcategory, "其他物品")
	records[key] = record

func _apply_issue_status() -> void:
	var by_key := {}
	for issue in issues:
		var key := str(issue.get("key", ""))
		if key.is_empty():
			continue
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(str(issue.reason))
	for key in by_key:
		if not records.has(key):
			continue
		records[key].status = "待检查"
		records[key].issue_reasons = by_key[key]

func _location_kind(location_id: String) -> String:
	if location_id.begins_with("town_"):
		return "town"
	if location_id.begins_with("sect_"):
		return "sect"
	return "wild"

func _npc(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	var roster: Dictionary = NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	return roster.get(id, {})

func _region_text(record: Dictionary) -> String:
	var ids: Array = record.get("region_ids", [])
	if ids.is_empty():
		return "—"
	return region_name(str(ids[0]))

func _values(table: Variant) -> Array:
	if table is Dictionary:
		return table.values()
	if table is Array:
		return table
	return []

func _array(value: Variant) -> Array:
	var text := str(value)
	return [] if text.is_empty() else [text]

func _push_unique(values: Array, value: String) -> void:
	if value.is_empty() or value in values:
		return
	values.append(value)
