@tool
extends RefCounted
## Bidirectional ID relations for the content index. No name matching.

static func attach(index) -> void:
	var tables: Dictionary = index.tables
	_shops(index, tables)
	_inns(index, tables)
	_quests(index, tables)
	_npcs(index, tables)
	_monsters(index, tables)
	_items(index, tables)
	_maps(index, tables)
	_events(index, tables)
	_announcements(index, tables)
	_sect_buildings(index, tables)
	_dialogues(index)

static func _link(index, from_kind: String, from_id: String, to_kind: String, to_id: String, label: String, related_region: bool = false) -> void:
	if from_id.is_empty() or to_id.is_empty():
		return
	var from_key := "%s:%s" % [from_kind, from_id]
	var to_key := "%s:%s" % [to_kind, to_id]
	var from_record: Dictionary = index.records.get(from_key, {})
	var to_record: Dictionary = index.records.get(to_key, {})
	if from_record.is_empty() or to_record.is_empty():
		return
	_add_edge(from_record, to_record, label)
	_add_edge(to_record, from_record, label)
	if related_region:
		for region in from_record.get("region_ids", []):
			_push_related(to_record, str(region))
		for region in to_record.get("region_ids", []):
			_push_related(from_record, str(region))

static func _add_edge(record: Dictionary, other: Dictionary, label: String) -> void:
	for existing in record.relations:
		if existing.key == other.key:
			return
	record.relations.append({
		"key": other.key,
		"id": other.id,
		"name": other.name,
		"kind": other.kind,
		"category": other.category,
		"label": label,
	})

static func _push_related(record: Dictionary, region_id: String) -> void:
	if region_id.is_empty() or region_id in record.get("region_ids", []) or region_id in record.get("related_region_ids", []):
		return
	record.related_region_ids.append(region_id)

static func _shops(index, tables: Dictionary) -> void:
	for shop in _values(tables.get("shops", {})):
		_link(index, "building", shop.id, "npc", str(shop.get("npc_id", "")), "店铺人物")
		_link(index, "building", shop.id, "town", str(shop.get("location", "")), "所在城镇")
		_link(index, "building", shop.id, "wild", str(shop.get("location", "")), "所在地点")
		for item_id in shop.get("stock", {}):
			_link(index, "building", shop.id, "item", str(item_id), "在售", true)

static func _inns(index, tables: Dictionary) -> void:
	for inn in _values(tables.get("inns", {})):
		_link(index, "building", inn.id, "npc", str(inn.get("owner_npc_id", "")), "店主")
		for npc_id in inn.get("npc_list", []):
			_link(index, "building", inn.id, "npc", str(npc_id), "店内人物")

static func _quests(index, tables: Dictionary) -> void:
	for quest in _values(tables.get("quests", {})):
		_link(index, "quest", quest.id, "npc", str(quest.get("giver_npc_id", "")), "委托人")
		_link(index, "quest", quest.id, "npc", str(quest.get("target", "")), "任务对象")
		_link(index, "quest", quest.id, "item", str(quest.get("required_item", "")), "所需物品")
		_link(index, "quest", quest.id, "quest", str(quest.get("previous", "")), "前置任务")
		for item_id in quest.get("rewards", {}):
			_link(index, "quest", quest.id, "item", str(item_id), "奖励", true)
		for objective in quest.get("objectives", []):
			if not objective is Dictionary:
				continue
			var target := str(objective.get("target_id", ""))
			match str(objective.get("objective_type", "")):
				"TALK_OPTION", "REPORT_NPC":
					_link(index, "quest", quest.id, "npc", target, "目标人物")
				"ITEM_DELIVERY", "ITEM_POSSESSION":
					_link(index, "quest", quest.id, "item", target, "目标物品", true)
				"KILL_ENEMY":
					_link(index, "quest", quest.id, "monster", target, "击杀目标", true)
				"COMPLETE_EVENT":
					_link(index, "quest", quest.id, "event", target, "调查事件")
			var contact := str(objective.get("completion_condition", {}).get("npc_id", ""))
			_link(index, "quest", quest.id, "npc", contact, "交付人物")

static func _npcs(index, tables: Dictionary) -> void:
	var roster: Dictionary = preload("res://core/npc_definitions.gd").roster(tables, tables.get("npc_overrides", {}))
	for npc in roster.values():
		if not npc is Dictionary:
			continue
		_link(index, "npc", npc.id, "town", str(npc.get("location", "")), "所在地点")
		_link(index, "npc", npc.id, "wild", str(npc.get("location", "")), "所在地点")
		_link(index, "npc", npc.id, "sect", str(npc.get("location", "")), "所在地点")
		_link(index, "npc", npc.id, "sect", str(npc.get("sect", "")), "所属宗门")
		var building := str(npc.get("sect_building", ""))
		if not building.is_empty():
			var sect := str(npc.get("sect", ""))
			var area := str(npc.get("sect_area", ""))
			_link(index, "npc", npc.id, "building", "%s:%s:%s" % [sect, area, building], "活动建筑")
		var profile: Dictionary = npc.get("profile", {})
		var loadout: Dictionary = npc.get("loadout", profile.get("loadout", {}))
		for slot in loadout.get("equipment", {}):
			_link(index, "npc", npc.id, "item", str(loadout.equipment[slot]), "装配", true)
		for instance in npc.get("equipment_instances", {}).values():
			if instance is Dictionary:
				_link(index, "npc", npc.id, "item", str(instance.get("item_id", "")), "持有装备", true)
		for technique_id in npc.get("techniques", {}):
			_link(index, "npc", npc.id, "technique", str(technique_id), "功法")
		for spell_id in npc.get("spells", {}):
			_link(index, "npc", npc.id, "spell", str(spell_id), "法术")
		for fortune_id in npc.get("fortune_ids", []):
			_link(index, "npc", npc.id, "fortune_innate", str(fortune_id), "气运")
			_link(index, "npc", npc.id, "fortune_acquired", str(fortune_id), "气运")

static func _monsters(index, tables: Dictionary) -> void:
	for monster in _values(tables.get("monsters", {})):
		for skill_id in monster.get("skill_ids", []):
			_link(index, "monster", monster.id, "spell", str(skill_id), "技能")
		var loot: Variant = monster.get("loot", {})
		if loot is Dictionary:
			for entry in loot.get("entries", []):
				if entry is Dictionary:
					_link(index, "monster", monster.id, "item", str(entry.get("item_id", "")), "掉落", true)
		for route in tables.get("prototype", {}).get("outskirts_routes", []):
			if not route is Dictionary:
				continue
			for encounter in route.get("encounters", []):
				if encounter is Dictionary and str(encounter.get("type", "")) == "monster" and str(encounter.get("monster_id", "")) == monster.id:
					_link(index, "monster", monster.id, "map", str(route.id), "探索遭遇", true)

static func _items(index, tables: Dictionary) -> void:
	for item in _values(tables.get("items", {})):
		var effect: Variant = item.get("use_effect")
		if effect is Dictionary and effect.get("learn") is String:
			_link(index, "item", item.id, "technique", str(effect.learn), "秘籍")
			_link(index, "item", item.id, "spell", str(effect.learn), "秘籍")
	for herb in _values(tables.get("herbs", {})):
		_link(index, "item", str(herb.get("id", "")), "item", str(herb.get("seed_id", "")), "种子")
	for recipe in _values(tables.get("recipes", {})):
		_link(index, "item", str(recipe.get("output", "")), "item", str(recipe.get("output", "")), "丹方产物")
		for material_id in recipe.get("materials", {}):
			_link(index, "item", str(recipe.get("output", "")), "item", str(material_id), "丹方材料")

static func _maps(index, tables: Dictionary) -> void:
	for definition in _values(tables.get("exploration_maps", {})):
		_link(index, "map", str(definition.get("id", "")), "wild", str(definition.get("location_id", "")), "所属地点")
	for route in tables.get("prototype", {}).get("outskirts_routes", []):
		if not route is Dictionary:
			continue
		for herb in route.get("herbs", []):
			_link(index, "map", str(route.id), "item", str(herb), "采集", true)
		for ore in route.get("mining", []):
			if ore is Dictionary:
				_link(index, "map", str(route.id), "item", str(ore.get("item_id", "")), "采矿", true)

static func _events(index, tables: Dictionary) -> void:
	for event in _values(tables.get("events", {})):
		_link(index, "event", event.id, "wild", str(event.get("location_id", "")), "发生地点")
		_link(index, "event", event.id, "town", str(event.get("location_id", "")), "发生地点")

static func _announcements(index, tables: Dictionary) -> void:
	for notice in _values(tables.get("announcements", {})):
		_link(index, "quest", str(notice.get("quest_id", "")), "town", str(notice.get("town_id", "")), "公告栏")
		_link(index, "quest", str(notice.get("quest_id", "")), "building", "building_board_%s" % str(notice.get("town_id", "")), "公告栏")

static func _sect_buildings(index, tables: Dictionary) -> void:
	for sect in tables.get("prototype", {}).get("sects", []):
		var sect_id := str(sect.get("id", ""))
		var areas: Variant = tables.get("sect_areas", {}).get(sect_id, [])
		if not areas is Array:
			continue
		for area in areas:
			if not area is Dictionary:
				continue
			for card in area.get("cards", []):
				if not card is Dictionary:
					continue
				var building_id := "%s:%s:%s" % [sect_id, area.get("id", ""), card.get("id", "")]
				for keeper in card.get("keepers", []):
					_link(index, "building", building_id, "npc", str(keeper), "负责人")
				_link(index, "building", building_id, "sect", sect_id, "所属宗门")

static func _dialogues(index) -> void:
	for record in index.records.values():
		if record.category != "dialogue":
			continue
		var npc_id := str(record.get("fields", {}).get("npc_id", ""))
		var quest_id := str(record.get("fields", {}).get("quest_id", ""))
		_link(index, "dialogue", record.id, "npc", npc_id, "对话人物")
		_link(index, "dialogue", record.id, "quest", quest_id, "所属任务")

static func _values(table: Variant) -> Array:
	if table is Dictionary:
		return table.values()
	if table is Array:
		return table
	return []
