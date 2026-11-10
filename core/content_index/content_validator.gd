@tool
extends RefCounted
## Collects content issues without mutating tables or auto-fixing data.

const NpcDefinitions := preload("res://core/npc_definitions.gd")
const Locations := preload("res://core/world_locations.gd")
const MonsterConfig := preload("res://core/monster_config.gd")

static func collect(index) -> Array:
	var issues: Array = []
	var tables: Dictionary = index.tables
	_missing_and_duplicate(index, issues)
	_quests(index, tables, issues)
	_npcs(index, tables, issues)
	_shops(index, tables, issues)
	_monsters(index, tables, issues)
	_skills(index, tables, issues)
	return issues

static func _issue(issues: Array, index, kind: String, id: String, reason: String, source: String) -> void:
	var key := "%s:%s" % [kind, id]
	var record: Dictionary = index.records.get(key, {})
	issues.append({
		"key": key,
		"id": id,
		"name": str(record.get("name", id)),
		"kind": kind,
		"reason": reason,
		"source": source,
	})

static func _missing_and_duplicate(index, issues: Array) -> void:
	var seen := {}
	for record in index.records.values():
		if str(record.id).strip_edges().is_empty():
			_issue(issues, index, record.kind, record.id, "缺少必填 ID", record.source)
		var table_key := "%s/%s" % [record.source_table, record.id]
		if seen.has(table_key):
			_issue(issues, index, record.kind, record.id, "重复 ID", record.source)
		else:
			seen[table_key] = true

static func _quests(index, tables: Dictionary, issues: Array) -> void:
	var roster: Dictionary = NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	var items: Dictionary = tables.get("items", {})
	var monsters: Dictionary = tables.get("monsters", {})
	var events: Dictionary = tables.get("events", {})
	for quest in _values(tables.get("quests", {})):
		var source := "res://data/quests/quests.json"
		var giver := str(quest.get("giver_npc_id", ""))
		if not giver.is_empty() and not roster.has(giver):
			_issue(issues, index, "quest", quest.id, "任务引用不存在的 NPC：" + giver, source)
		var required := str(quest.get("required_item", ""))
		if not required.is_empty() and not items.has(required):
			_issue(issues, index, "quest", quest.id, "任务引用不存在的物品：" + required, source)
		for item_id in quest.get("rewards", {}):
			if not items.has(item_id):
				_issue(issues, index, "quest", quest.id, "任务奖励物品不存在：" + str(item_id), source)
		for objective in quest.get("objectives", []):
			if not objective is Dictionary:
				continue
			var target := str(objective.get("target_id", ""))
			match str(objective.get("objective_type", "")):
				"TALK_OPTION", "REPORT_NPC":
					if not roster.has(target):
						_issue(issues, index, "quest", quest.id, "任务目标 NPC 不存在：" + target, source)
				"ITEM_DELIVERY", "ITEM_POSSESSION":
					if not items.has(target):
						_issue(issues, index, "quest", quest.id, "任务目标物品不存在：" + target, source)
				"KILL_ENEMY":
					if not monsters.has(target):
						_issue(issues, index, "quest", quest.id, "任务目标妖兽不存在：" + target, source)
				"COMPLETE_EVENT":
					if not events.has(target):
						_issue(issues, index, "quest", quest.id, "任务事件不存在：" + target, source)

static func _npcs(index, tables: Dictionary, issues: Array) -> void:
	var places: Dictionary = Locations.names(tables)
	var roster: Dictionary = NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	for npc in roster.values():
		if not npc is Dictionary:
			continue
		var location := str(npc.get("location", ""))
		var source := "res://data/world/npc_overrides.json" if tables.get("npc_overrides", {}).has(npc.id) else "res://data/world/prototype.json"
		if location.is_empty():
			_issue(issues, index, "npc", npc.id, "NPC 缺少所属地区", source)
		elif not places.has(location):
			_issue(issues, index, "npc", npc.id, "NPC 引用不存在的地区：" + location, source)

static func _shops(index, tables: Dictionary, issues: Array) -> void:
	var items: Dictionary = tables.get("items", {})
	var roster: Dictionary = NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	for shop in _values(tables.get("shops", {})):
		var source := "res://data/towns/shops.json"
		var npc_id := str(shop.get("npc_id", ""))
		if not npc_id.is_empty() and not roster.has(npc_id):
			_issue(issues, index, "building", shop.id, "商店人物不存在：" + npc_id, source)
		for item_id in shop.get("stock", {}):
			if not items.has(item_id):
				_issue(issues, index, "building", shop.id, "商店商品 ID 无效：" + str(item_id), source)
			elif int(shop.stock[item_id]) <= 0:
				_issue(issues, index, "building", shop.id, "商店商品数量无效：" + str(item_id), source)

static func _monsters(index, tables: Dictionary, issues: Array) -> void:
	var items: Dictionary = tables.get("items", {})
	var skills: Dictionary = tables.get("monster_skills", {})
	for monster in _values(tables.get("monsters", {})):
		var source := "res://data/monsters/monsters.json"
		for skill_id in monster.get("skill_ids", []):
			if not skills.has(skill_id):
				_issue(issues, index, "monster", monster.id, "妖兽技能引用无效：" + str(skill_id), source)
		var loot: Variant = monster.get("loot", {})
		if loot is Dictionary:
			for entry in loot.get("entries", []):
				if not entry is Dictionary:
					continue
				var item_id := str(entry.get("item_id", ""))
				if item_id.is_empty() or not items.has(item_id):
					_issue(issues, index, "monster", monster.id, "妖兽掉落物品 ID 无效：" + item_id, source)

static func _skills(index, tables: Dictionary, issues: Array) -> void:
	var statuses: Dictionary = tables.get("spell_growth", {}).get("statuses", {})
	for spell in _values(tables.get("spells", {})):
		var status := str(spell.get("status", ""))
		if not status.is_empty() and not statuses.has(status):
			_issue(issues, index, "spell", spell.id, "法术效果引用无效：" + status, "res://data/skills/spells.json")
		for level in spell.get("levels", []):
			if not level is Dictionary:
				continue
			for key in level:
				var value: Variant = level[key]
				if value is String and not statuses.has(value):
					_issue(issues, index, "spell", spell.id, "法术等级效果引用无效：" + str(value), "res://data/skills/spells.json")
	for skill in _values(tables.get("monster_skills", {})):
		var error := MonsterConfig.validate_skill(skill, tables)
		if not error.is_empty():
			_issue(issues, index, "spell", str(skill.get("id", "")), "功法或法术效果引用无效：" + error, "res://data/monsters/skills.json")
	for technique in _values(tables.get("techniques", {})):
		if str(technique.get("cultivation_route", "")) not in ["qi", "body"]:
			_issue(issues, index, "technique", technique.id, "功法缺少有效修炼路线", "res://data/skills/techniques.json")

static func _values(table: Variant) -> Array:
	if table is Dictionary:
		return table.values()
	if table is Array:
		return table
	return []
