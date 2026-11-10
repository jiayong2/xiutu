@tool
extends RefCounted

const PATH := "res://data/world/npc_overrides.json"
const Character := preload("res://gameplay/character/character_system.gd")
const Fortune := preload("res://gameplay/character/player_fortunes.gd")
const Mental := preload("res://gameplay/character/mental_attributes.gd")
const Equipment := preload("res://gameplay/inventory/equipment_values.gd")
const Inventory := preload("res://gameplay/inventory/inventory_system.gd")
const Spells := preload("res://gameplay/battle/spell_progression.gd")
const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const World := preload("res://world/world_simulator.gd")
const Random := preload("res://core/random_service.gd")
const Locations := preload("res://core/world_locations.gd")
const STATS := ["hp","mp","attack","defense","speed"]
const FOUNDATION := ["qi_sea","meridians","bones","physique","spirit_sea","soul"]
const SLOT_LIMIT := 10

static func uid(prefix: String) -> String:
	return prefix + Crypto.new().generate_random_bytes(12).hex_encode()

static func roster(data: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := {}
	for npc in data.prototype.npcs:
		result[npc.id] = npc
	result.merge(overrides, true)
	return result

static func draft(definition: Dictionary, data: Dictionary) -> Dictionary:
	var npc := definition.duplicate(true)
	npc.merge({"profile":{}, "age":data.prototype.npc_initial_age, "cultivation":0,
		"inventory":{}, "equipment_instances":{}, "equipped":{}, "equipment_nurture":{},
		"relations":{}, "fortune_ids":[], "artifact_ids":[], "artifact_slots":[],
		"techniques":{}, "technique_slots":[], "spells":{}, "spell_slots":[], "spell_mastery":{},
		"initial_age":data.prototype.npc_initial_age})
	var profile: Dictionary = npc.profile
	profile.rank = Character.npc_rank(profile)
	var legacy: Dictionary = npc.get("loadout",profile.get("loadout", {}))
	if not npc.get("authored", false):
		for slot in legacy.get("equipment", {}):
			npc.equipment_instances["legacy_" + slot] = legacy.equipment[slot]
			npc.equipped[slot] = "legacy_" + slot
		npc.techniques = legacy.get("techniques", {}).duplicate()
		npc.technique_slots = npc.techniques.keys()
		for id in profile.get("spells", []):
			npc.spells[id] = 1
	npc.authored = true
	npc.erase("loadout")
	profile.erase("loadout")
	profile.merge({"innate_fortune":[], "acquired_fortune":[], "contacts":{}, "foundation":{},
		"base":{}, "stat_overrides":{}})
	return npc

static func initial(definition: Dictionary, data: Dictionary) -> Dictionary:
	var npc := definition.duplicate(true)
	npc.initial_age = npc.age
	npc.wealth = data.prototype.npc_initial_wealth
	npc.alive = npc.age < World.npc_lifespan(npc, data)
	npc.attributes = npc.profile.foundation.duplicate()
	Mental.initialize_npc(npc, data.progression.mental)
	npc.fortunes = {}
	for id in npc.fortune_ids:
		Fortune.grant(npc, id, 0, "NPC 初始配置")
	fill_vitals(npc,npc.profile,data)
	return npc

static func complete_prototype(npc: Dictionary, profile: Dictionary, data: Dictionary, seed_material: String) -> void:
	# Derived per-NPC draws leave the saved world and battle streams untouched.
	var random := Random.new()
	random.initialize(hash(seed_material + ":" + npc.id))
	if not npc.has("fortunes") and profile.get("innate_fortune", []).is_empty():
		var candidates: Array = []
		for id in Fortune.DEFINITIONS:
			var fortune: Dictionary = Fortune.DEFINITIONS[id]
			if not Fortune.valid_selection(id) or fortune.duration.type != "permanent":
				continue
			if fortune.effects.any(func(effect):return effect.implemented and effect.type == "stat" and (npc.realm > 0 or "hp" in effect.targets)):
				candidates.append(id)
		if not candidates.is_empty():
			Fortune.grant(npc,candidates[random.integer("world",0,candidates.size()-1)],0,"NPC 初始配置")
	if npc.realm > 0 and not npc.has("loadout"):
		npc.loadout = _random_loadout(npc,data,random)
	fill_vitals(npc,profile,data)

static func _random_loadout(npc: Dictionary, data: Dictionary, random: RefCounted) -> Dictionary:
	var tier := Cultivation.tier_index(int(npc.realm))
	var equipment := {}
	var slots := ["weapon","armor"]
	if tier >= 2:
		slots.append("head")
	for slot in slots:
		var candidates: Array = []
		var best_tier := -1
		for definition in data.equipment.values():
			if definition.slot != slot or not equipment_error(npc,definition.id,data).is_empty():
				continue
			var required_tier: int = int(definition.recommended_realm[0]) if definition.has("recommended_realm") else 0
			if required_tier > tier or required_tier < best_tier:
				continue
			if required_tier > best_tier:
				best_tier = required_tier
				candidates.clear()
			candidates.append(definition.id)
		if not candidates.is_empty():
			equipment[slot] = candidates[random.integer("world",0,candidates.size()-1)]
	var techniques := {}
	var routes := ["qi"]
	if tier >= 2:
		routes.append("body")
	for route in routes:
		var candidates: Array = []
		for definition in data.techniques.values():
			if definition.cultivation_route == route:
				candidates.append(definition.id)
		if not candidates.is_empty():
			techniques[candidates[random.integer("world",0,candidates.size()-1)]] = mini(tier,5)
	return {"equipment":equipment,"techniques":techniques}

static func fill_vitals(npc: Dictionary, profile: Dictionary, data: Dictionary) -> void:
	var caps := Character.new().npc_stats(npc,profile,data)
	var resources: Dictionary = profile.get("resources", {})
	var keys := ["hp","mp","blood"] if npc.realm > 0 else ["hp"]
	for key in keys:
		if not npc.has(key):
			npc[key] = clampi(int(resources.get(key,caps[key])),0,int(caps[key]))

static func equipment_error(npc: Dictionary, id: String, data: Dictionary) -> String:
	return Equipment.equip_error(data.equipment.get(id, {}), int(npc.realm))

static func realm_error(npc: Dictionary) -> String:
	if not Fortune.valid_integer(npc.get("realm")) or npc.realm > Cultivation.MAX_LEVEL:
		return "无效法修境界"
	if not npc.get("realm_known",false) is bool:
		return "无效境界公开设置"
	return ""

static func validate(npc: Dictionary, data: Dictionary, known: Dictionary, check_realm: bool = true) -> String:
	for key in ["profile","inventory","equipment_instances","equipped","equipment_nurture","relations","techniques","spells"]:
		if not npc.get(key) is Dictionary:
			return "缺失配置字段 " + key
	for key in ["fortune_ids","artifact_ids","artifact_slots","technique_slots","spell_slots"]:
		if not npc.get(key) is Array:
			return "缺失配置列表 " + key
	if not npc.get("name") is String or npc.name.strip_edges().is_empty():
		return "请输入姓名"
	for key in ["age","cultivation"]:
		if not Fortune.valid_integer(npc.get(key)):
			return "无效数值 " + key
	var realm_validation := realm_error(npc)
	if not realm_validation.is_empty():
		return realm_validation
	if check_realm and not Locations.names(data).has(npc.get("location")):
		return "所在地不存在"
	for key in ["base","foundation","contacts","stat_overrides"]:
		if not npc.profile.get(key) is Dictionary:
			return "无效档案字段 " + key
	for key in STATS:
		if not npc.profile.base.is_empty() and not npc.profile.base.has(key):
			return "战斗底值需要填写全部五项"
	for group in [npc.profile.base, npc.profile.stat_overrides]:
		for key in group:
			if key not in STATS + ["blood","critical","critical_damage","dodge"] or not Fortune.valid_integer(group[key]):
				return "无效战斗属性 " + key
	if npc.profile.base.is_empty() and not npc.profile.stat_overrides.is_empty():
		return "手动覆盖需要战斗底值"
	for key in ["portrait", "illustration"]:
		var asset: Variant = npc.profile.get(key, "")
		if not asset is String or (not asset.is_empty() and not ResourceLoader.exists(asset, "Texture2D")):
			return "人物图片资源不存在 " + key
	for key in npc.profile.foundation:
		if key not in FOUNDATION or not Fortune.valid_integer(npc.profile.foundation[key]):
			return "无效根基 " + key
	for id in npc.inventory:
		if not data.items.has(id) or data.equipment.has(id) or not Fortune.valid_integer(npc.inventory[id]) or npc.inventory[id] <= 0:
			return "无效堆叠物品 " + id
	for instance in npc.equipment_instances:
		if not data.equipment.has(npc.equipment_instances[instance]):
			return "无效装备实例 " + instance
	for slot in npc.equipped:
		var id: String = npc.equipment_instances.get(npc.equipped[slot], "")
		if not data.equipment.has(id) or data.equipment[id].slot != slot:
			return "装备槽位不匹配 " + slot
		if check_realm and not equipment_error(npc, id, data).is_empty():
			return "装备境界不足 " + id
	for instance in npc.equipment_nurture:
		var row: Dictionary = data.equipment.get(npc.equipment_instances.get(instance, ""), {})
		var level: Variant = npc.equipment_nurture[instance]
		if not row.has("nurture_max") or not Fortune.valid_integer(level) or level > row.nurture_max:
			return "无效装备温养 " + instance
	for pair in [["techniques","technique_slots"],["spells","spell_slots"]]:
		for id in npc[pair[0]]:
			var row: Dictionary = data[pair[0]].get(id, {})
			var level: Variant = npc[pair[0]][id]
			if row.is_empty() or not Fortune.valid_integer(level) or level < 1 or level > row.get("levels", [0,0,0]).size():
				return "无效技能等级或引用 " + id
		var error := slots_error(npc[pair[1]], npc[pair[0]], SLOT_LIMIT)
		if not error.is_empty():
			return error
	if not Spells.validate_player(npc, data):
		return "法术熟练度无效"
	var fortune_actor := {}
	for id in npc.fortune_ids:
		var row: Dictionary = Fortune.DEFINITIONS.get(id, {})
		if row.is_empty() or row.duration.type != "permanent" or not Fortune.grant(fortune_actor, id, 0, "NPC 初始配置"):
			return "无效、互斥或非永久气运 " + str(id)
	for id in npc.artifact_ids:
		if not data.artifacts.has(id):
			return "无效法宝 " + id
	var artifact_error := slots_error(npc.artifact_slots, npc.artifact_ids, 4)
	if not artifact_error.is_empty():
		return artifact_error
	var contacts: Array = npc.profile.contacts.keys()
	for other in npc.relations.keys() + contacts:
		if other == npc.id or ((check_realm or other in contacts) and not known.has(other)):
			return "无效关系对象 " + other
	for score in npc.relations.values():
		if not (score is int or score is float) or not Fortune.valid_integer(score + 100) or score > 100:
			return "好感超出范围"
	if npc.has("duty") and not npc.duty is String:
		return "无效职责说明"
	var affiliation := _affiliation_error(npc, data)
	if not affiliation.is_empty():
		return affiliation
	return ""

static func _affiliation_error(npc: Dictionary, data: Dictionary) -> String:
	var sect_id := ""
	if npc.has("sect"):
		if not npc.sect is String:
			return "无效宗门"
		sect_id = npc.sect
		if not sect_id.is_empty():
			var known_sect := false
			for sect in data.get("prototype", {}).get("sects", []):
				if sect.get("id") == sect_id:
					known_sect = true
			if not known_sect:
				return "宗门不存在 " + sect_id
	var area_id := ""
	if npc.has("sect_area"):
		if not npc.sect_area is String:
			return "无效宗门区域"
		area_id = npc.sect_area
	var building_id := ""
	if npc.has("sect_building"):
		if not npc.sect_building is String:
			return "无效宗门建筑"
		building_id = npc.sect_building
	if area_id.is_empty() and building_id.is_empty():
		return ""
	var matched_area: Dictionary = {}
	for area in data.get("sect_areas", {}).get(sect_id, []):
		if str(area.get("id", "")) == area_id:
			matched_area = area
			break
	if not area_id.is_empty() and matched_area.is_empty():
		return "宗门区域不存在 " + area_id
	if building_id.is_empty():
		return ""
	for card in matched_area.get("cards", []):
		if str(card.get("id", "")) == building_id:
			return ""
	return "宗门建筑不存在 " + building_id

static func slots_error(slots: Array, learned: Variant, limit: int) -> String:
	if slots.size() > limit:
		return "装配槽上限 %d" % limit
	var seen := {}
	for id in slots:
		if not learned.has(id) or seen.has(id):
			return "装配引用未持有或重复 " + str(id)
		seen[id] = true
	return ""

static func load_definitions(data: Dictionary, path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"rows": {}, "error": "缺少 NPC 初始定义文件：" + path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error":"无法读取 NPC 初始定义"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error":"NPC 初始定义 JSON 无效"}
	var rows: Dictionary = parser.data
	var known := roster(data, rows)
	for id in rows:
		if not id is String or not id.begins_with("npc_") or not id.is_valid_identifier() or not rows[id] is Dictionary or rows[id].get("id") != id or rows[id].get("authored") != true:
			return {"error":"无效 NPC 初始定义 ID"}
		var error := validate(rows[id], data, known)
		if not error.is_empty():
			return {"error":"%s · %s" % [id,error]}
	return {"rows":rows,"error":""}

static func write_definitions(rows: Dictionary, data: Dictionary, path: String = PATH) -> String:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法写入临时定义文件"
	file.store_string(JSON.stringify(rows, "  ", true) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return "写入 NPC 初始定义失败"
	var result := load_definitions(data, temporary)
	if not result.error.is_empty():
		return result.error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	return "" if error == OK else "无法替换 NPC 初始定义文件（%d）" % error
