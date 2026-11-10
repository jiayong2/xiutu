@tool
extends RefCounted
var tables: Dictionary = {}
var error := ""
const PATHS := {"time_rules":"balance/time_rules", "progression":"cultivation/progression", "spirit_flow":"cultivation/spirit_flow", "realm_tiers":"cultivation/realm_tiers", "inns":"towns/inns", "events":"world/events", "items":"items/items", "equipment":"items/equipment", "techniques":"skills/techniques", "spells":"skills/spells", "monster_skills":"monsters/skills", "herbs":"cave/herbs", "recipes":"cave/recipes", "monsters":"monsters/monsters", "quests":"quests/quests", "shops":"towns/shops", "realms":"cultivation/realms", "rules":"balance/rules", "prototype":"world/prototype"}

func load_all(validate: bool = true) -> bool:
	tables.clear()
	var paths := PATHS.duplicate()
	paths["exploration_maps"] = "world/exploration_maps"
	paths["artifacts"] = "items/artifacts"
	paths["announcements"] = "towns/announcements"
	paths["sect_areas"] = "world/sect_areas"
	paths.merge({"auctions":"towns/auctions","auction_rules":"balance/auction_rules"})
	paths.merge({"spell_trials":"skills/spell_trials", "spell_trials_stage2":"skills/spell_trials_stage2", "spell_trials_stage3":"skills/spell_trials_stage3", "spell_growth":"skills/spell_growth"})
	for table in paths:
		var path: String = "res://data/%s.json" % paths[table]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			error = "Missing configuration: " + path
			return false
		var json := JSON.new()
		if json.parse(f.get_as_text()) != OK:
			error = "%s:%s %s" % [path, json.get_error_line(), json.get_error_message()]
			return false
		var rows: Variant = json.data
		if rows is Dictionary:
			tables[table] = rows
			continue
		if not rows is Array:
			error = "Expected table array: " + path
			return false
		var index := {}
		for row in rows:
			if not row is Dictionary or not row.get("id") is String or index.has(row.id):
				error = "Invalid or duplicate ID: " + path
				return false
			index[row.id] = row
		tables[table] = index
	for stage in ["spell_trials","spell_trials_stage2","spell_trials_stage3"]:
		for id in tables[stage]:
			var spell: Dictionary = tables[stage][id]
			if tables.spells.has(id) or spell.element not in tables.rules.roots or spell.levels.size() != 5 or spell.mp < 0 or spell.cd < 0 or spell.target not in ["enemy","self","ally","all","chain"]:
				error = "法术试学配置无效：" + id
				return false
			for level in spell.levels:
				for key in level:
					var value: Variant = level[key]
					if (value is String and not tables.spell_growth.statuses.has(value)) or (not value is String and (not (value is float or value is int) or not is_finite(float(value)) or value < 0)):
						error = "法术等级效果配置无效：" + id + " / " + key
						return false
			tables.spells[id] = spell
	for item in tables.items.values():
		if item.buy_price < 0 or item.sell_price < 0 or item.stack_limit < 1:
			error = "Invalid price/stack: " + item.id
			return false
	for shop in tables.shops.values():
		for id in shop.stock:
			if not tables.items.has(id) or shop.stock[id] <= 0:
				error = "Invalid shop reference: " + id
				return false
	var route_ids: Dictionary = {}
	for route in tables.prototype.outskirts_routes:
		if route_ids.has(route.id) or str(route.id).is_empty() or str(route.name).is_empty():
			error = "Invalid outskirts route: " + str(route.id)
			return false
		route_ids[route.id] = true
		if route.has("unavailable"):
			continue
		if route.has("outcomes") or route.has("encounter"):
			error = "Legacy outskirts encounter fields are not supported: " + route.id
			return false
		if not _valid_encounters(route.get("encounters"), tables, route):
			error = "Invalid outskirts encounters: " + route.id
			return false
		if route.has("mining"):
			if not route.mining is Array or route.mining.is_empty() or route.has("herbs"):
				error = "Invalid mining route: " + route.id
				return false
			var encounter_chance: Variant = route.get("encounter_chance")
			if not (encounter_chance is int or encounter_chance is float) or encounter_chance < 1 or encounter_chance > 100 or encounter_chance != int(encounter_chance):
				error = "Invalid mining encounter chance: " + route.id
				return false
			for entry in route.encounters:
				if entry.get("type") != "monster":
					error = "Mining routes only allow monster encounters: " + route.id
					return false
			var ores: Dictionary = {}
			for ore in route.mining:
				if not ore is Dictionary or not ore.get("item_id") is String or not tables.items.has(ore.item_id) or tables.items[ore.item_id].type != "材料" or ores.has(ore.item_id):
					error = "Invalid mining item: " + route.id
					return false
				var chance: Variant = ore.get("chance")
				if not (chance is int or chance is float) or chance < 1 or chance > 100 or chance != int(chance):
					error = "Invalid mining chance: " + route.id
					return false
				ores[ore.item_id] = true
			continue
		if route.has("encounter_chance"):
			error = "Exploration routes cannot set encounter_chance: " + route.id
			return false
		for herb in route.get("herbs", []):
			if not tables.herbs.has(herb) or not tables.items.has(herb):
				error = "Invalid outskirts herb: " + str(herb)
				return false
	if not _valid_encounters(tables.prototype.get("outskirts_default_encounters"), tables, {"herbs": tables.prototype.get("outskirts_default_herbs", [])}):
		error = "Invalid default outskirts encounters"
		return false
	for herb in tables.prototype.get("outskirts_default_herbs", []):
		if not tables.herbs.has(herb) or not tables.items.has(herb):
			error = "Invalid default outskirts herb: " + str(herb)
			return false
	for recipe in tables.recipes.values():
		for id in recipe.materials.keys() + [recipe.output]:
			if not tables.items.has(id):
				error = "Invalid recipe reference: " + id
				return false
	for npc in tables.prototype.npcs:
		var realm_validation := preload("res://core/npc_definitions.gd").realm_error(npc)
		if not realm_validation.is_empty():
			error = str(npc.id) + " · " + realm_validation
			return false
	if not validate:
		return true
	var spell_error: String = preload("res://core/skills/skill_database.gd").validate_runtime_spells(tables.spells, tables.spell_growth)
	if not spell_error.is_empty():
		error = spell_error
		return false
	if not validate_references():
		return false
	var authored := preload("res://core/npc_definitions.gd").load_definitions(tables)
	error = authored.error
	if error.is_empty():
		tables.npc_overrides = authored.rows
		error = preload("res://core/sect_building.gd").validate(tables)
	return error.is_empty()

func validate_references() -> bool:
	var monster_error: String = preload("res://core/monster_config.gd").validate(tables)
	if not monster_error.is_empty():
		error = monster_error
		return false
	var auction_error: String = preload("res://gameplay/auction/auction_validation.gd").config(tables)
	if not auction_error.is_empty():
		error = auction_error
		return false
	var time_error: String=preload("res://core/time_system.gd").new().validate_rules(tables.time_rules)
	if not time_error.is_empty():error=time_error;return false
	var growth_error: String = preload("res://gameplay/cultivation/cultivation_system.gd").new().validate_growth_rules(tables.progression)
	if not growth_error.is_empty():
		error = growth_error
		return false
	var realm_error: String = preload("res://gameplay/cultivation/cultivation_system.gd").new().validate_realm_tiers(tables)
	if not realm_error.is_empty():
		error = realm_error
		return false
	var spirit_error: String = preload("res://gameplay/cultivation/spirit_flow_simulation.gd").validate(tables.spirit_flow,tables.techniques,tables.rules.roots)
	if not spirit_error.is_empty():
		error = spirit_error
		return false
	var residence_ids: Dictionary = tables.spirit_flow.locations.duplicate()
	for sect in tables.prototype.sects:
		if not sect.has("residence"):
			continue
		var residence: Variant = sect.residence
		if not residence is Dictionary or not residence.get("location_id") is String or residence.location_id.is_empty() or residence_ids.has(residence.location_id) or not residence.get("name") is String or residence.name.strip_edges().is_empty():
			error = "宗门驻地地点配置无效：" + sect.id
			return false
		var hours: Variant = residence.get("travel_hours")
		if not (hours is int or hours is float) or not is_finite(float(hours)) or hours <= 0 or hours != floor(float(hours)):
			error = "宗门驻地旅行耗时无效：" + sect.id
			return false
		residence_ids[residence.location_id] = true
		if not _validate_sect_areas(sect.id):
			return false
	for technique in tables.techniques.values():
		if technique.get("cultivation_route") not in ["qi", "body"]:
			error = "功法缺少有效修炼路线：" + technique.id
			return false
	for inn in tables.inns.values():
		if inn.location not in ["town_qinglan","town_yunxi"] or not inn.available_rooms is Array or not inn.menu_items is Array or not inn.npc_list is Array:
			error="Invalid inn configuration: "+inn.id;return false
		var seen: Dictionary={}
		for room in inn.available_rooms:
			if not room is Dictionary or not room.get("id") is String or seen.has(room.id) or not room.get("available") is bool or room.get("action")!="inn":
				error="Invalid inn room: "+inn.id;return false
			seen[room.id]=true
		for npc_id in inn.npc_list+[inn.owner_npc_id]:
			if str(npc_id).is_empty():continue
			var found: bool=false
			for npc in tables.prototype.npcs:
				if npc.id==npc_id:found=true
			if not found:error="Invalid inn NPC: "+str(npc_id);return false
	for definition in tables.equipment.values():
		if not tables.items.has(definition.id) or not preload("res://gameplay/inventory/equipment_values.gd").SLOTS.has(definition.slot):
			error = "Invalid equipment reference: " + definition.id
			return false
	for npc in tables.prototype.npcs:
		var profile: Dictionary = npc.get("profile", {})
		if profile.has("base") and not preload("res://gameplay/character/character_system.gd").valid_npc_loadout(profile.get("loadout"), tables):
			error = "Invalid NPC loadout: " + npc.id
			return false
	for h in tables.herbs.values():
		if not tables.items.has(h.id) or not tables.items.has(h.seed_id) or h.days <= 0 or h.yield_count <= 0:
			error = "Invalid herb reference: " + h.id
			return false
	for quest in tables.quests.values():
		if not quest.previous.is_empty() and not tables.quests.has(quest.previous):
			error = "Invalid quest prerequisite: " + quest.id
			return false
		for id in quest.rewards:
			if not tables.items.has(id) or quest.rewards[id] <= 0:
				error = "Invalid quest reward: " + quest.id
				return false
	for item in tables.items.values():
		if item.use_effect is Dictionary and item.use_effect.has("learn"):
			var id: String = item.use_effect.learn
			if not tables.techniques.has(id) and not tables.spells.has(id):
				error = "Invalid book target: " + item.id
				return false
	var quest_error: String = preload("res://gameplay/quest/quest_validation.gd").new().validate(tables)
	if not quest_error.is_empty():
		error = quest_error
		return false
	error = preload("res://gameplay/quest/town_announcements.gd").validate(tables)
	if not error.is_empty():
		return false
	error = preload("res://gameplay/exploration_run.gd").validate_catalog(tables)
	if not error.is_empty():
		return false
	return true

func _valid_encounters(value: Variant, tables: Dictionary, route: Dictionary) -> bool:
	if not value is Array or value.is_empty():
		return false
	var total := 0
	for entry in value:
		if not entry is Dictionary:
			return false
		var weight: Variant = entry.get("weight")
		if not (weight is int or weight is float) or weight < 0 or weight != int(weight):
			return false
		total += int(weight)
		match str(entry.get("type", "")):
			"monster":
				if not entry.get("monster_id") is String or not tables.monsters.has(entry.monster_id):
					return false
			"gather":
				if route.get("herbs", []).is_empty():
					return false
			"spring":
				pass
			_:
				return false
	return total > 0

func _validate_sect_areas(sect_id: String) -> bool:
	var areas: Variant = tables.sect_areas.get(sect_id)
	if not areas is Array or areas.size()!=4:
		error = "宗门驻地区域配置无效：" + sect_id
		return false
	var expected := ["outer","inner","core","back_mountain"]
	for i in range(expected.size()):
		var area: Variant = areas[i]
		if not area is Dictionary or area.get("id")!=expected[i] or not area.get("name") is String or not area.get("heading") is String or not area.get("restriction") is String or not area.get("cards") is Array:
			error = "宗门驻地区域字段无效：%s / %s" % [sect_id,expected[i]]
			return false
		if area.restriction.is_empty() != (i==0):
			error = "宗门驻地区域通行配置无效：%s / %s" % [sect_id,area.id]
			return false
		var seen := {}
		for card in area.cards:
			if not card is Dictionary or not card.get("id") is String or seen.has(card.id) or not card.get("name") is String or not card.get("description") is String or card.get("entry","") not in ["","gate","undiscovered"]:
				error = "宗门驻地卡片配置无效：%s / %s" % [sect_id,area.id]
				return false
			if card.get("entry","")=="gate" and i!=0:
				error = "山门入口必须位于外门：" + sect_id
				return false
			seen[card.id]=true
	return true

func get_table(name: String) -> Dictionary:
	return tables.get(name, {}).duplicate(true)
