@tool
extends RefCounted

const Config := preload("res://core/npc_generation/generation_config.gd")
const Model := preload("res://core/npc_definitions.gd")
const Equipment := preload("res://gameplay/inventory/equipment_values.gd")
const Spells := preload("res://gameplay/battle/spell_progression.gd")
const STREAM := "world"
const ARTIFACT_SLOTS := 4

static func apply(random: RefCounted, config: Dictionary, npc: Dictionary, data: Dictionary) -> String:
	var gear := pick_equipment(random, config.equipment, npc, data)
	if not gear.error.is_empty():
		return gear.error
	npc.equipment_instances = gear.instances
	npc.equipped = gear.equipped
	var artifacts := pick_artifacts(random, config.artifacts, npc, data)
	if not artifacts.error.is_empty():
		return artifacts.error
	npc.artifact_ids = artifacts.ids
	npc.artifact_slots = artifacts.slots
	var techniques := pick_skills(random, config.techniques, npc, data, "techniques")
	if not techniques.error.is_empty():
		return techniques.error
	npc.techniques = techniques.learned
	npc.technique_slots = techniques.slots
	var spells := pick_skills(random, config.spells, npc, data, "spells")
	if not spells.error.is_empty():
		return spells.error
	npc.spells = spells.learned
	npc.spell_slots = spells.slots
	npc.spell_mastery = {}
	return ""

static func pick_equipment(random: RefCounted, rules: Dictionary, npc: Dictionary, data: Dictionary) -> Dictionary:
	var span := Config.range_of(rules.get("count"))
	var required: Array = Config.string_ids(rules.get("required_ids"))
	if span.max <= 0 and required.is_empty():
		return {"error": "", "instances": {}, "equipped": {}}
	if required.size() > span.max:
		return {"error": "必带装备数量超出总数量上限"}
	var needed: int = random.integer(STREAM, span.min, span.max)
	needed = maxi(needed, required.size())
	if needed > Equipment.SLOTS.size():
		return {"error": "装备数量超过槽位上限 %d" % Equipment.SLOTS.size()}
	var instances := {}
	var equipped := {}
	for id in required:
		var error := _wear(id, npc, data, rules, instances, equipped, true)
		if not error.is_empty():
			return {"error": error, "instances": {}, "equipped": {}}
	var remaining := needed - equipped.size()
	for _step in remaining:
		var pool := _equipment_pool(npc, data, rules, equipped.keys())
		if pool.is_empty():
			return {"error": "符合境界条件的装备不足，要求 %d 件，当前仅 %d 件。" % [needed, equipped.size()]}
		var preferred := _preferred_gear(pool, data, Config.major_tier(int(npc.realm)))
		var pick_from: Array = preferred if not preferred.is_empty() else pool
		var id: String = str(_weighted_gear(random, pick_from, data, rules.get("quality_weights", {})))
		var error := _wear(id, npc, data, rules, instances, equipped, true)
		if not error.is_empty():
			return {"error": error, "instances": {}, "equipped": {}}
	return {"error": "", "instances": instances, "equipped": equipped}

static func pick_artifacts(random: RefCounted, rules: Dictionary, npc: Dictionary, data: Dictionary) -> Dictionary:
	var span := Config.range_of(rules.get("count"))
	var required: Array = Config.string_ids(rules.get("required_ids"))
	if span.max <= 0 and required.is_empty():
		return {"error": "", "ids": [], "slots": []}
	if span.max > ARTIFACT_SLOTS:
		return {"error": "法宝数量超过槽位上限 %d" % ARTIFACT_SLOTS}
	if required.size() > span.max:
		return {"error": "必带法宝数量超出总数量上限"}
	var needed: int = maxi(random.integer(STREAM, span.min, span.max), required.size())
	if needed > ARTIFACT_SLOTS:
		return {"error": "法宝数量超过槽位上限 %d" % ARTIFACT_SLOTS}
	var ids: Array = []
	for id in required:
		if id in Config.string_ids(rules.get("excluded_ids")) or not data.artifacts.has(id):
			return {"error": "必带法宝不合法：" + id}
		if not _artifact_allowed(data.artifacts[id], npc, rules):
			return {"error": "必带法宝不满足境界或品质：" + id}
		ids.append(id)
	var pool: Array = []
	for id in data.artifacts:
		if id in ids or id in Config.string_ids(rules.get("excluded_ids")):
			continue
		if _artifact_allowed(data.artifacts[id], npc, rules):
			pool.append(id)
	var remaining := needed - ids.size()
	if pool.size() < remaining:
		return {"error": "符合条件的法宝不足，要求 %d 件，当前仅 %d 件。" % [needed, ids.size() + pool.size()]}
	for _step in remaining:
		var preferred := _preferred_artifacts(pool, data, npc, rules)
		var pick_from: Array = preferred if not preferred.is_empty() else pool
		var id: String = str(_weighted_artifact(random, pick_from, data, rules, npc))
		ids.append(id)
		pool.erase(id)
	var slots: Array = ids.duplicate()
	if slots.size() > ARTIFACT_SLOTS:
		slots = slots.slice(0, ARTIFACT_SLOTS)
	return {"error": "", "ids": ids, "slots": slots}

static func pick_skills(random: RefCounted, rules: Dictionary, npc: Dictionary, data: Dictionary, table_key: String) -> Dictionary:
	var span := Config.range_of(rules.get("count"))
	var required: Array = Config.string_ids(rules.get("required_ids"))
	if span.max <= 0 and required.is_empty():
		return {"error": "", "learned": {}, "slots": []}
	var table: Dictionary = data.get(table_key, {})
	if required.size() > span.max:
		return {"error": "必带%s数量超出总数量上限" % _skill_label(table_key)}
	var needed: int = maxi(random.integer(STREAM, span.min, span.max), required.size())
	var learned := {}
	for id in required:
		if not table.has(id) or id in Config.string_ids(rules.get("excluded_ids")):
			return {"error": "必带%s不存在或已排除：%s" % [_skill_label(table_key), id]}
		if not _skill_allowed(table[id], npc, rules, table_key, true):
			return {"error": "必带%s不满足当前人物条件：%s" % [_skill_label(table_key), id]}
		learned[id] = _skill_level(random, table[id], rules)
	var pool: Array = []
	for id in table:
		if learned.has(id) or id in Config.string_ids(rules.get("excluded_ids")):
			continue
		if _skill_allowed(table[id], npc, rules, table_key, false):
			pool.append(id)
	var remaining := needed - learned.size()
	if remaining > 0 and pool.size() < remaining:
		return {"error": "符合条件的%s不足，要求 %d 个，当前仅 %d 个。" % [_skill_label(table_key), needed, learned.size() + pool.size()]}
	for _step in remaining:
		var preferred := _preferred_skills(pool, table, npc, rules, table_key)
		var pick_from: Array = preferred if not preferred.is_empty() else pool
		var id: String = str(_weighted_skill(random, pick_from, table, npc, rules, table_key))
		learned[id] = _skill_level(random, table[id], rules)
		pool.erase(id)
	var equipped_span := Config.range_of(rules.get("equipped"), 0, Model.SLOT_LIMIT)
	var slot_count: int = clampi(random.integer(STREAM, equipped_span.min, equipped_span.max), 0, mini(Model.SLOT_LIMIT, learned.size()))
	var slots: Array = []
	var learned_ids: Array = learned.keys()
	for id in required:
		if slots.size() >= slot_count:
			break
		if id in learned_ids:
			slots.append(id)
	for id in learned_ids:
		if slots.size() >= slot_count:
			break
		if id not in slots:
			slots.append(id)
	return {"error": "", "learned": learned, "slots": slots}

static func gear_config_errors(rules: Dictionary, field: String, data: Dictionary, table_key: String, slot_limit: int) -> Array:
	var issues: Array = []
	var span := Config.range_of(rules.get("count"))
	if span.min < 0 or span.max < span.min:
		issues.append({"code": "RANGE", "message": "数量范围无效", "field": field + ".count"})
	if span.max > slot_limit:
		issues.append({"code": "SLOTS", "message": "数量超过槽位上限 %d" % slot_limit, "field": field + ".count"})
	var mode := str(rules.get("realm_mode", "down_one"))
	if mode not in Config.REALM_MODES:
		issues.append({"code": "MODE", "message": "境界匹配模式无效", "field": field + ".realm_mode"})
	if mode == "absolute":
		var low := int(rules.get("realm_min", 0))
		var high := int(rules.get("realm_max", 9))
		if low < 0 or high > 9 or low > high:
			issues.append({"code": "RANGE", "message": "绝对境界范围无效", "field": field})
	for key in ["min_quality", "max_quality"]:
		var quality := str(rules.get(key, ""))
		if not quality.is_empty() and Config.gear_rank(quality) < 0:
			issues.append({"code": "QUALITY", "message": "装备品质不是现有品质：" + quality, "field": field + "." + key})
	if Config.gear_rank(str(rules.get("min_quality", ""))) >= 0 and Config.gear_rank(str(rules.get("max_quality", ""))) >= 0:
		if Config.gear_rank(rules.min_quality) > Config.gear_rank(rules.max_quality):
			issues.append({"code": "QUALITY", "message": "最低品质高于最高品质", "field": field})
	var table: Dictionary = data.get(table_key, {})
	var required: Array = Config.string_ids(rules.get("required_ids"))
	var excluded: Array = Config.string_ids(rules.get("excluded_ids"))
	for id in required:
		if id in excluded:
			issues.append({"code": "CONFLICT", "message": "必带与排除冲突：" + id, "field": field})
		if not table.has(id):
			issues.append({"code": "REF", "message": "必带引用不存在：" + id, "field": field + ".required_ids"})
	if required.size() > span.max:
		issues.append({"code": "COUNT", "message": "必带数量超出上限", "field": field + ".required_ids"})
	return issues

static func skill_config_errors(rules: Dictionary, field: String, data: Dictionary, table_key: String) -> Array:
	var issues: Array = []
	var span := Config.range_of(rules.get("count"))
	if span.min < 0 or span.max < span.min:
		issues.append({"code": "RANGE", "message": "数量范围无效", "field": field + ".count"})
	_range_issue(issues, rules.get("equipped"), 0, Model.SLOT_LIMIT, "装配数量", field + ".equipped")
	_range_issue(issues, rules.get("level"), 1, 5, "等级", field + ".level")
	if table_key == "techniques":
		for key in ["min_rarity", "max_rarity"]:
			var rarity := str(rules.get(key, ""))
			if not rarity.is_empty() and Config.rarity_rank(rarity) < 0:
				issues.append({"code": "QUALITY", "message": "功法品阶不是现有品阶：" + rarity, "field": field + "." + key})
	var table: Dictionary = data.get(table_key, {})
	var required: Array = Config.string_ids(rules.get("required_ids"))
	var excluded: Array = Config.string_ids(rules.get("excluded_ids"))
	for id in required:
		if id in excluded:
			issues.append({"code": "CONFLICT", "message": "必带与排除冲突：" + id, "field": field})
		if not table.has(id):
			issues.append({"code": "REF", "message": "必带引用不存在：" + id, "field": field + ".required_ids"})
	if required.size() > span.max:
		issues.append({"code": "COUNT", "message": "必带数量超出上限", "field": field + ".required_ids"})
	return issues

static func _range_issue(issues: Array, value: Variant, low: int, high: int, label: String, field: String) -> void:
	var span := Config.range_of(value, low, high)
	if span.min > span.max or span.min < low or span.max > high:
		issues.append({"code": "RANGE", "message": "%s范围无效" % label, "field": field})

static func allowed_tiers(npc_tier: int, rules: Dictionary) -> Array:
	var mode := str(rules.get("realm_mode", "down_one"))
	if mode == "any":
		return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
	if mode == "absolute":
		return _span(int(rules.get("realm_min", 0)), int(rules.get("realm_max", 9)))
	if mode == "strict":
		return [npc_tier]
	if mode == "up_one":
		return _span(maxi(0, npc_tier - 1), mini(9, npc_tier + 1))
	return _span(maxi(0, npc_tier - 1), npc_tier)

static func item_tiers(definition: Dictionary) -> Array:
	if definition.get("recommended_realm") is Array and not definition.recommended_realm.is_empty():
		var result: Array = []
		for value in definition.recommended_realm:
			result.append(int(value))
		return result
	if definition.has("realm"):
		var value := int(definition.realm)
		return [value] if value <= 9 else [Config.major_tier(value)]
	return [0]

static func _equipment_pool(npc: Dictionary, data: Dictionary, rules: Dictionary, filled_slots: Array) -> Array:
	var result: Array = []
	var allowed := allowed_tiers(Config.major_tier(int(npc.realm)), rules)
	var slots: Array = rules.get("slots", []) + rules.get("types", [])
	for id in data.equipment:
		if id in Config.string_ids(rules.get("excluded_ids")):
			continue
		var row: Dictionary = data.equipment[id]
		var slot: String = str(row.get("slot", ""))
		if slot in filled_slots:
			continue
		if not slots.is_empty() and slot not in slots:
			continue
		if not _quality_ok(str(row.get("quality", "")), rules):
			continue
		if not _tiers_overlap(item_tiers(row), allowed):
			continue
		if not Model.equipment_error(npc, id, data).is_empty():
			continue
		result.append(id)
	return result

static func _wear(id: String, npc: Dictionary, data: Dictionary, rules: Dictionary, instances: Dictionary, equipped: Dictionary, must_wear: bool) -> String:
	if not data.equipment.has(id):
		return "装备不存在：" + id
	var row: Dictionary = data.equipment[id]
	var slot: String = str(row.slot)
	if equipped.has(slot):
		return "装备槽位重复：" + slot
	if not _quality_ok(str(row.get("quality", "")), rules) and id not in Config.string_ids(rules.get("required_ids")):
		return "装备品质不在范围内：" + id
	if not _tiers_overlap(item_tiers(row), allowed_tiers(Config.major_tier(int(npc.realm)), rules)):
		return "装备境界不匹配：" + id
	var error := Model.equipment_error(npc, id, data)
	if not error.is_empty():
		return error + "：" + id
	var instance := _unique_instance(instances)
	instances[instance] = id
	if must_wear:
		equipped[slot] = instance
	return ""

static func _unique_instance(instances: Dictionary) -> String:
	var index := instances.size()
	var id := "gear_%02d" % index
	while instances.has(id):
		index += 1
		id = "gear_%02d" % index
	return id

static func _preferred_gear(pool: Array, data: Dictionary, npc_tier: int) -> Array:
	var result: Array = []
	for id in pool:
		if npc_tier in item_tiers(data.equipment[id]):
			result.append(id)
	return result

static func _artifact_allowed(row: Dictionary, npc: Dictionary, rules: Dictionary) -> bool:
	if not _quality_ok(str(row.get("quality", "")), rules):
		return false
	return _tiers_overlap(item_tiers(row), allowed_tiers(Config.major_tier(int(npc.realm)), rules))

static func _preferred_artifacts(pool: Array, data: Dictionary, npc: Dictionary, rules: Dictionary) -> Array:
	var npc_tier := Config.major_tier(int(npc.realm))
	var same: Array = []
	for id in pool:
		if npc_tier in item_tiers(data.artifacts[id]):
			same.append(id)
	if not same.is_empty():
		return same
	if rules.get("match_route", false) != true:
		return []
	var matched: Array = []
	var root: String = str(npc.get("profile", {}).get("root", ""))
	for id in pool:
		if _element_root(data.artifacts[id]) == root:
			matched.append(id)
	return matched

static func _skill_allowed(row: Dictionary, _npc: Dictionary, rules: Dictionary, table_key: String, required: bool) -> bool:
	if required or table_key != "techniques":
		return true
	var rarity := str(row.get("rarity", ""))
	if str(rules.get("min_rarity", "")).is_empty() and str(rules.get("max_rarity", "")).is_empty():
		return true
	if rarity.is_empty():
		return false
	return Config.quality_allowed(rarity, str(rules.get("min_rarity", "")), str(rules.get("max_rarity", "")), Config.TECHNIQUE_RARITIES)

static func _preferred_skills(pool: Array, table: Dictionary, npc: Dictionary, rules: Dictionary, table_key: String) -> Array:
	var result: Array = []
	var root: String = str(npc.get("profile", {}).get("root", ""))
	var route: String = str(npc.get("_generation_route", ""))
	for id in pool:
		var row: Dictionary = table[id]
		var matched := false
		if table_key == "spells" and rules.get("match_root", true) == true:
			matched = str(row.get("element", "")) in [root, "无"]
		elif table_key == "techniques" and rules.get("match_route", true) == true:
			if route == "body_primary":
				matched = row.get("cultivation_route") == "body"
			elif route == "qi_primary":
				matched = row.get("cultivation_route") == "qi"
			else:
				matched = true
		if matched:
			result.append(id)
	return result

static func _skill_level(random: RefCounted, row: Dictionary, rules: Dictionary) -> int:
	var maximum: int = Spells.maximum(row)
	if maximum <= 0:
		maximum = 3
	var span := Config.range_of(rules.get("level"), 1, maximum)
	var low: int = clampi(span.min, 1, maximum)
	var high: int = clampi(span.max, low, maximum)
	return random.integer(STREAM, low, high)

static func _quality_ok(quality: String, rules: Dictionary) -> bool:
	var minimum := str(rules.get("min_quality", ""))
	var maximum := str(rules.get("max_quality", ""))
	if minimum.is_empty() and maximum.is_empty():
		return true
	if quality.is_empty():
		return false
	return Config.quality_allowed(quality, minimum, maximum, Config.GEAR_QUALITIES)

static func _tiers_overlap(item: Array, allowed: Array) -> bool:
	for tier in item:
		if int(tier) in allowed:
			return true
	return false

static func _span(low: int, high: int) -> Array:
	var result: Array = []
	for value in range(low, high + 1):
		result.append(value)
	return result

static func _element_root(row: Dictionary) -> String:
	return str(Config.ELEMENTS.get(str(row.get("element", "")), row.get("element", "")))

static func _skill_label(table_key: String) -> String:
	return "功法" if table_key == "techniques" else "法术"

static func _weighted_gear(random: RefCounted, items: Array, data: Dictionary, weights: Variant) -> Variant:
	var mapped := {}
	for id in items:
		var quality: String = str(data.equipment[id].get("quality", ""))
		var weight := 1
		if weights is Dictionary and Config._is_whole(weights.get(quality)):
			weight = maxi(0, int(weights[quality]))
		mapped[id] = weight
	return _weighted_map(random, items, mapped)

static func _weighted_artifact(random: RefCounted, items: Array, data: Dictionary, rules: Dictionary, npc: Dictionary) -> Variant:
	var weights := {}
	for id in items:
		var weight := 1
		var quality: String = str(data.artifacts[id].get("quality", ""))
		if rules.get("quality_weights") is Dictionary and Config._is_whole(rules.quality_weights.get(quality)):
			weight = maxi(1, int(rules.quality_weights[quality]))
		if rules.get("match_route", false) == true and _element_root(data.artifacts[id]) == str(npc.get("profile", {}).get("root", "")):
			weight *= 3
		weights[id] = weight
	return _weighted_map(random, items, weights)

static func _weighted_skill(random: RefCounted, items: Array, table: Dictionary, npc: Dictionary, rules: Dictionary, table_key: String) -> Variant:
	var weights := {}
	var root: String = str(npc.get("profile", {}).get("root", ""))
	for id in items:
		var weight := 1
		if table_key == "spells" and rules.get("match_root", true) == true:
			var element: String = str(table[id].get("element", ""))
			if element == root:
				weight = 3
			elif element == "无":
				weight = 1
			else:
				weight = 1
		weights[id] = weight
	return _weighted_map(random, items, weights)

static func _weighted_map(random: RefCounted, items: Array, weights: Dictionary) -> Variant:
	var total := 0
	for id in items:
		total += maxi(0, int(weights.get(id, 1)))
	if total <= 0:
		return items[random.integer(STREAM, 0, items.size() - 1)]
	var roll: int = random.integer(STREAM, 1, total)
	var cursor := 0
	for id in items:
		cursor += maxi(0, int(weights.get(id, 1)))
		if roll <= cursor:
			return id
	return items.back()
