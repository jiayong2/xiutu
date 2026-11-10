@tool
extends RefCounted

const Config := preload("res://core/npc_generation/generation_config.gd")
const Model := preload("res://core/npc_definitions.gd")
const Fortunes := preload("res://core/npc_generation/generation_fortunes.gd")
const Loadout := preload("res://core/npc_generation/generation_loadout.gd")
const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const World := preload("res://world/world_simulator.gd")
const Locations := preload("res://core/world_locations.gd")
const Character := preload("res://gameplay/character/character_system.gd")
const Equipment := preload("res://gameplay/inventory/equipment_values.gd")

static func config_errors(config: Dictionary, data: Dictionary) -> Array:
	var issues: Array = []
	if int(config.get("schema_version", 0)) != Config.SCHEMA_VERSION:
		issues.append(_issue("SCHEMA", "生成模板版本不受支持", "schema_version"))
	if not Config.whole_in(config.get("count"), Config.COUNT_MIN, Config.COUNT_MAX):
		issues.append(_issue("COUNT", "生成数量必须为 %d～%d" % [Config.COUNT_MIN, Config.COUNT_MAX], "count"))
	if config.has("seed") and not Config._is_whole(config.seed):
		issues.append(_issue("SEED", "随机种子必须是整数", "seed"))
	var identity: Dictionary = config.get("identity", {})
	_range_errors(issues, identity.get("age"), 0, 100000, "年龄", "identity.age")
	_range_errors(issues, identity.get("lifespan"), 1, 100000, "寿元", "identity.lifespan")
	_range_errors(issues, identity.get("wealth"), 0, 100000000, "灵石", "identity.wealth")
	if int(identity.get("male_weight", 0)) < 0 or int(identity.get("female_weight", 0)) < 0:
		issues.append(_issue("GENDER", "性别权重不能为负", "identity.gender"))
	if int(identity.get("male_weight", 0)) + int(identity.get("female_weight", 0)) <= 0:
		issues.append(_issue("GENDER", "性别权重之和必须大于 0", "identity.gender"))
	var places := Locations.names(data)
	for location in identity.get("location_ids", []):
		if not location is String or not places.has(location):
			issues.append(_issue("LOCATION", "所在地不存在：" + str(location), "identity.location_ids"))
	var sects := Config.sect_names(data)
	for sect in identity.get("sect_names", []):
		if not sect is String or not sects.has(sect):
			issues.append(_issue("SECT", "宗门名称不在现有列表中：" + str(sect), "identity.sect_names"))
	var known_roles := Config.collect_roles(data, data.get("npc_overrides", {}))
	for role in identity.get("roles", []):
		if not role is String or role.strip_edges().is_empty():
			issues.append(_issue("ROLE", "身份不能为空字符串", "identity.roles"))
		elif not known_roles.has(role):
			issues.append(_issue("ROLE", "身份不是现有合法值：" + str(role), "identity.roles"))
	var cultivation: Dictionary = config.get("cultivation", {})
	_range_errors(issues, cultivation.get("qi_realm"), 0, Cultivation.MAX_LEVEL, "法修境界", "cultivation.qi_realm")
	_range_errors(issues, cultivation.get("body_realm"), 0, Cultivation.MAX_LEVEL, "体修境界", "cultivation.body_realm")
	_range_errors(issues, cultivation.get("cultivation_ratio"), 0, 100, "修为比例", "cultivation.cultivation_ratio")
	if str(cultivation.get("route", "")) not in Config.ROUTES:
		issues.append(_issue("ROUTE", "修炼方向无效", "cultivation.route"))
	var route := str(cultivation.get("route", "random"))
	var qi := Config.range_of(cultivation.get("qi_realm"))
	var body := Config.range_of(cultivation.get("body_realm"))
	if route == "qi_primary" and body.min > qi.max:
		issues.append(_issue("ROUTE", "法修为主时体修下限不能高于法修上限", "cultivation.route"))
	if route == "body_primary" and qi.min > body.max:
		issues.append(_issue("ROUTE", "体修为主时法修下限不能高于体修上限", "cultivation.route"))
	var roots: Array = cultivation.get("roots", [])
	for root in roots:
		if not data.rules.roots.has(root):
			issues.append(_issue("ROOT", "灵根不在现有八系中：" + str(root), "cultivation.roots"))
	for rank in cultivation.get("ranks", []):
		if rank not in Character.NPC_RANKS:
			issues.append(_issue("RANK", "天资评级无效：" + str(rank), "cultivation.ranks"))
	if cultivation.get("ranks", []).is_empty():
		issues.append(_issue("RANK", "至少选择一种天资评级", "cultivation.ranks"))
	var foundation: Dictionary = cultivation.get("foundation", {})
	for key in Config.FOUNDATION_KEYS:
		_range_errors(issues, foundation.get(key), 0, 100000, key, "cultivation.foundation." + key)
	var stats: Dictionary = config.get("base_stats", {})
	for key in Config.STAT_KEYS:
		_range_errors(issues, stats.get(key), 0, 100000, key, "base_stats." + key)
	var age := Config.range_of(identity.get("age"))
	var life := Config.range_of(identity.get("lifespan"), 1, 1)
	var max_tier_life := _tier_lifespan(int(qi.max), data)
	var effective_life := maxi(int(life.max), max_tier_life)
	if age.min >= effective_life:
		issues.append(_issue("AGE", "年龄下限不低于对应境界寿元，无法生成存活人物", "identity.age"))
	issues.append_array(Fortunes.catalog_errors(config.get("innate_fortune", {}), "innate_fortune", ["innate"], false))
	issues.append_array(Fortunes.catalog_errors(config.get("acquired_fortune", {}), "acquired_fortune", ["acquired"], config.get("acquired_fortune", {}).get("allow_negative", false) == true))
	issues.append_array(Loadout.gear_config_errors(config.get("equipment", {}), "equipment", data, "equipment", Equipment.SLOTS.size()))
	issues.append_array(Loadout.gear_config_errors(config.get("artifacts", {}), "artifacts", data, "artifacts", Loadout.ARTIFACT_SLOTS))
	issues.append_array(Loadout.skill_config_errors(config.get("techniques", {}), "techniques", data, "techniques"))
	issues.append_array(Loadout.skill_config_errors(config.get("spells", {}), "spells", data, "spells"))
	return issues

static func npc_errors(npc: Dictionary, config: Dictionary, data: Dictionary, known: Dictionary) -> Array:
	var issues: Array = []
	var definition_error := Model.validate(npc, data, known)
	if not definition_error.is_empty():
		issues.append(_issue("DEFINE", definition_error, "npc"))
	var identity: Dictionary = config.get("identity", {})
	var cultivation: Dictionary = config.get("cultivation", {})
	_in_range(issues, npc.get("age"), identity.get("age"), "年龄", "age")
	_in_range(issues, npc.get("wealth"), identity.get("wealth"), "灵石", "wealth")
	var qi := Config.range_of(cultivation.get("qi_realm"))
	var body := Config.range_of(cultivation.get("body_realm"))
	if not (int(npc.get("realm", -1)) >= qi.min and int(npc.realm) <= qi.max):
		issues.append(_issue("REALM", "法修境界超出配置范围", "realm"))
	var body_level := body_level_of(str(npc.get("profile", {}).get("body_realm", "")), data)
	if body_level < body.min or body_level > body.max:
		issues.append(_issue("BODY", "体修境界超出配置范围", "profile.body_realm"))
	var profile: Dictionary = npc.get("profile", {})
	if profile.get("gender") not in ["男", "女"]:
		issues.append(_issue("GENDER", "性别必须为男或女", "profile.gender"))
	var allowed_roots: Array = cultivation.get("roots", [])
	if allowed_roots.is_empty():
		allowed_roots = data.rules.roots
	if profile.get("root") not in allowed_roots:
		issues.append(_issue("ROOT", "灵根不在候选范围", "profile.root"))
	if profile.get("rank") not in cultivation.get("ranks", []):
		issues.append(_issue("RANK", "天资评级不在候选范围", "profile.rank"))
	var base: Dictionary = profile.get("base", {})
	for key in Config.STAT_KEYS:
		_in_range(issues, base.get(key), config.get("base_stats", {}).get(key), key, "profile.base." + key)
	var foundation: Dictionary = profile.get("foundation", {})
	for key in Config.FOUNDATION_KEYS:
		_in_range(issues, foundation.get(key), cultivation.get("foundation", {}).get(key), key, "profile.foundation." + key)
	if int(npc.get("age", 0)) >= World.npc_lifespan(npc, data):
		issues.append(_issue("LIFESPAN", "年龄不小于有效寿元", "age"))
	if not str(npc.get("name", "")).strip_edges().is_empty() and str(npc.name).length() > 24:
		issues.append(_issue("NAME", "姓名超过 24 字", "name"))
	issues.append_array(Fortunes.npc_errors(npc, config.get("innate_fortune", {}), ["innate"], false, "innate_fortune"))
	issues.append_array(Fortunes.npc_errors(npc, config.get("acquired_fortune", {}), ["acquired"], config.get("acquired_fortune", {}).get("allow_negative", false) == true, "acquired_fortune"))
	issues.append_array(_gear_npc_errors(npc, config, data))
	issues.append_array(_skill_npc_errors(npc, config))
	return issues

static func _gear_npc_errors(npc: Dictionary, config: Dictionary, data: Dictionary) -> Array:
	var issues: Array = []
	var equipment: Dictionary = config.get("equipment", {})
	var span := Config.range_of(equipment.get("count"))
	if span.max > 0 or not Config.string_ids(equipment.get("required_ids")).is_empty():
		var worn: int = npc.get("equipped", {}).size()
		if worn < span.min or worn > span.max:
			issues.append(_issue("GEAR", "装备件数不在 %d～%d" % [span.min, span.max], "equipment"))
		for id in Config.string_ids(equipment.get("required_ids")):
			if id not in npc.get("equipment_instances", {}).values():
				issues.append(_issue("REQUIRED", "缺少必带装备：" + id, "equipment"))
		for instance in npc.get("equipped", {}).values():
			var item_id: String = str(npc.get("equipment_instances", {}).get(instance, ""))
			if item_id.is_empty():
				continue
			if not Loadout._tiers_overlap(Loadout.item_tiers(data.equipment.get(item_id, {})), Loadout.allowed_tiers(Config.major_tier(int(npc.realm)), equipment)):
				issues.append(_issue("REALM", "装备境界不匹配：" + item_id, "equipment"))
	var artifacts: Dictionary = config.get("artifacts", {})
	var artifact_span := Config.range_of(artifacts.get("count"))
	if artifact_span.max > 0 or not Config.string_ids(artifacts.get("required_ids")).is_empty():
		var held: int = npc.get("artifact_ids", []).size()
		if held < artifact_span.min or held > artifact_span.max:
			issues.append(_issue("GEAR", "法宝件数不在 %d～%d" % [artifact_span.min, artifact_span.max], "artifacts"))
		if npc.get("artifact_slots", []).size() > Loadout.ARTIFACT_SLOTS:
			issues.append(_issue("SLOTS", "法宝装配超过槽位上限", "artifacts"))
		for id in Config.string_ids(artifacts.get("required_ids")):
			if id not in npc.get("artifact_ids", []):
				issues.append(_issue("REQUIRED", "缺少必带法宝：" + id, "artifacts"))
	return issues

static func _skill_npc_errors(npc: Dictionary, config: Dictionary) -> Array:
	var issues: Array = []
	for pair in [["techniques", "technique_slots"], ["spells", "spell_slots"]]:
		var rules: Dictionary = config.get(pair[0], {})
		var span := Config.range_of(rules.get("count"))
		if span.max <= 0 and Config.string_ids(rules.get("required_ids")).is_empty():
			continue
		var learned: Dictionary = npc.get(pair[0], {})
		if learned.size() < span.min or learned.size() > span.max:
			issues.append(_issue("SKILL", "%s数量不在 %d～%d" % [pair[0], span.min, span.max], pair[0]))
		for id in Config.string_ids(rules.get("required_ids")):
			if not learned.has(id):
				issues.append(_issue("REQUIRED", "缺少必带：" + id, pair[0]))
		for id in npc.get(pair[1], []):
			if not learned.has(id):
				issues.append(_issue("SLOT", "已装备但未学习：" + str(id), pair[1]))
	return issues

static func body_level_of(label: String, data: Dictionary) -> int:
	if label == "凡体" or label.is_empty():
		return 0
	for level in range(1, Cultivation.MAX_LEVEL + 1):
		if Cultivation.realm_name(level, "body", data) == label:
			return level
	return -1

static func _tier_lifespan(realm: int, data: Dictionary) -> int:
	var tier: Dictionary = data.realm_tiers.get("tier_%d" % Cultivation.tier_index(maxi(0, realm)), {})
	return int(tier.get("lifespan", data.prototype.npc_lifespan))

static func _range_errors(issues: Array, value: Variant, low: int, high: int, label: String, field: String) -> void:
	var span := Config.range_of(value, low, high)
	if span.min > span.max:
		issues.append(_issue("RANGE", "%s最小值大于最大值" % label, field))
	if span.min < low or span.max > high:
		issues.append(_issue("RANGE", "%s超出允许区间 %d～%d" % [label, low, high], field))

static func _in_range(issues: Array, value: Variant, spec: Variant, label: String, field: String) -> void:
	if spec == null:
		return
	var span := Config.range_of(spec)
	if not Config._is_number(value) or int(value) < span.min or int(value) > span.max:
		issues.append(_issue("RANGE", "%s不在 %d～%d" % [label, span.min, span.max], field))

static func _issue(code: String, message: String, field: String) -> Dictionary:
	return {"code": code, "message": message, "field": field}
