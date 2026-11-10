extends RefCounted
## Effect definitions, instances and the executors SkillEngine already runs.
## A definition describes parameters. An instance stores one spell's numbers.
## The executor is always one of the registered SkillEngine effect types.

const EXECUTORS := ["damage", "status", "heal", "shield", "mana", "cleanse"]
const CATEGORIES := ["伤害", "恢复", "防护", "增益", "减益", "控制", "特殊"]
const TRIGGERS := ["instant", "duration"]

static func fallback() -> Array:
	return [
		_damage("effect_direct_damage", "直接伤害", "按攻击系数走统一伤害公式，基础伤害在命中后追加。", 1.0, 0, 1, false),
		_damage("effect_multi_hit", "连续攻击", "同一伤害公式连续结算多次。", 0.55, 0, 2, false),
		_damage("effect_lifesteal", "吸血", "造成直接伤害后按比例治疗施法者。", 1.0, 0, 1, true),
		_status("effect_poison", "中毒", "伤害", "poison", "持续伤害。每回合先按攻击力、层数和状态表系数结算，再追加每层额外伤害。"),
		_status("effect_burn", "灼烧", "伤害", "burn", "持续伤害。结算方式与中毒相同，使用灼烧状态表。"),
		_status("effect_bleed", "流血", "伤害", "bleed", "持续伤害。结算方式与中毒相同，使用流血状态表。"),
		_heal("effect_heal", "生命恢复", false),
		_heal("effect_regen", "持续恢复", true),
		_mana("effect_mana", "灵力恢复", false),
		_shield(),
		_status("effect_reduction", "减伤", "防护", "damage_reduction", "施加减伤。层数使用状态表系数，额外减免写入 flat。"),
		_status("effect_attack_up", "攻击提升", "增益", "attack_up", "每层先使用状态表攻击提升，flat 为额外比例。"),
		_status("effect_defense_up", "防御提升", "增益", "defense_up", "每层先使用状态表防御提升，flat 为额外比例。"),
		_status("effect_speed_up", "速度提升", "增益", "speed_up", "每层先使用状态表速度提升，flat 为额外比例。"),
		_status("effect_crit_up", "暴击提升", "增益", "crit_up", "每层先使用状态表暴击提升，flat 为额外比例。"),
		_status("effect_vulnerability", "易伤", "减益", "vulnerability", "施加易伤。倍率读取状态表，不另写一套增伤公式。"),
		_status("effect_armor_break", "破甲", "减益", "armor_break", "施加破甲。每层比例读取状态表。"),
		_status("effect_slow", "减速", "减益", "slow", "施加迟缓。速度结算读取状态表与战斗侧修正。"),
		_status("effect_attack_down", "攻击降低", "减益", "attack_down", "施加攻击降低。每层比例读取状态表，flat 为额外比例。"),
		_status("effect_stun", "眩晕", "控制", "stun", "施加眩晕。是否跳过行动由现有状态结算决定。"),
		_status("effect_silence", "沉默", "控制", "silence", "施加禁术。现有施法拦截读取该状态。"),
		_status("effect_root", "缠绕", "控制", "root", "施加缠绕。逃跑等限制读取该状态。"),
		_cleanse(),
		_mana("effect_mana_drain", "资源削减", true),
	]

static func by_id(rows: Array) -> Dictionary:
	var index := {}
	for row in rows:
		if row is Dictionary and row.get("id") is String:
			index[row.id] = row
	return index

static func find(rows: Array, id: String) -> Dictionary:
	var found: Variant = by_id(rows).get(id, {})
	return found if found is Dictionary else {}

static func instance_from(definition: Dictionary) -> Dictionary:
	var row := {"effect_id": str(definition.get("id", "")), "type": str(definition.get("executor", ""))}
	if definition.has("status"):
		row["status"] = str(definition.status)
	if bool(definition.get("drain", false)):
		row["drain"] = true
	for param in definition.get("parameters", []):
		if param is Dictionary:
			row[str(param.id)] = param.get("default")
	return row

static func compile(instance: Dictionary, definition: Dictionary) -> Dictionary:
	var row := instance.duplicate(true)
	row["effect_id"] = str(definition.get("id", instance.get("effect_id", "")))
	row["type"] = str(definition.get("executor", ""))
	if definition.has("status"):
		row["status"] = str(definition.status)
	if bool(definition.get("drain", false)):
		row["drain"] = true
	return row

static func validate_instance(instance: Dictionary, definition: Dictionary) -> String:
	if instance.has("enabled") and not instance.enabled is bool:
		return "效果 enabled 必须是布尔值"
	if instance.has("node_id") and not _valid_id(instance.node_id):
		return "效果 node_id 格式无效"
	if definition.is_empty():
		return "效果定义不存在：" + str(instance.get("effect_id", ""))
	if instance.get("type") != definition.get("executor"):
		return "效果实例 type 与定义 executor 不一致"
	if str(definition.get("executor", "")) not in EXECUTORS:
		return "效果 %s 绑定了未注册执行器 %s" % [definition.get("id", ""), definition.get("executor", "")]
	for param in definition.get("parameters", []):
		if not param is Dictionary:
			return "效果 %s 的参数定义无效" % definition.get("id", "")
		var key := str(param.get("id", ""))
		if not instance.has(key):
			if bool(param.get("required", false)):
				return "效果 %s 缺少参数 %s" % [definition.get("id", ""), key]
			continue
		var message := _check_value(instance[key], param)
		if not message.is_empty():
			return "效果 %s 的%s：%s" % [definition.get("id", ""), param.get("name", key), message]
	return ""

static func validate_definition(row: Dictionary, growth: Dictionary = {}) -> String:
	if not _valid_id(row.get("id")):
		return "效果 ID 无效：" + str(row.get("id", ""))
	if str(row.get("name", "")).strip_edges().is_empty():
		return "效果 %s 缺少名称" % row.id
	if str(row.get("category", "")) not in CATEGORIES:
		return "效果 %s 的分类无效" % row.id
	if str(row.get("executor", "")) not in EXECUTORS:
		return "效果 %s 的执行器无效" % row.id
	if str(row.get("trigger", "")) not in TRIGGERS:
		return "效果 %s 的触发方式无效" % row.id
	if row.get("executor") == "status":
		var status := str(row.get("status", ""))
		if status.is_empty() or not growth.get("statuses", {}).has(status):
			return "效果 %s 的状态未在状态表注册：%s" % [row.id, status]
	if not row.get("parameters") is Array or row.parameters.is_empty():
		return "效果 %s 至少需要一个参数" % row.id
	var seen := {}
	for param in row.parameters:
		if not param is Dictionary or not _valid_id(param.get("id")):
			return "效果 %s 存在无效参数 ID" % row.id
		if seen.has(param.id):
			return "效果 %s 的参数 ID 重复：%s" % [row.id, param.id]
		seen[param.id] = true
		if str(param.get("type", "")) not in ["int", "float", "percent", "bool", "enum"]:
			return "效果 %s 的参数类型无效：%s" % [row.id, param.id]
		if param.type != "bool" and param.type != "enum":
			if not _number(param.get("min")) or not _number(param.get("max")) or float(param.min) > float(param.max):
				return "效果 %s 的参数范围无效：%s" % [row.id, param.id]
			var default_error := _check_value(param.get("default"), param)
			if not default_error.is_empty():
				return "效果 %s 的默认值无效：%s" % [row.id, default_error]
	return ""

static func describe(instance: Dictionary, definition: Dictionary, growth: Dictionary = {}) -> String:
	if not bool(instance.get("enabled", true)):
		return "已禁用 · " + str(definition.get("name", instance.get("effect_id", "")))
	if definition.is_empty():
		return "未绑定效果定义"
	var parts: PackedStringArray = []
	match str(definition.get("executor", "")):
		"damage":
			parts.append("攻击系数 %d%%" % roundi(float(instance.get("power", 0)) * 100.0))
			if int(instance.get("flat", 0)) != 0:
				parts.append("基础伤害 %d" % int(instance.flat))
			if int(instance.get("hits", 1)) > 1:
				parts.append("%d 段" % int(instance.hits))
			if float(instance.get("lifesteal", 0)) > 0.0:
				parts.append("吸血 %d%%" % roundi(float(instance.lifesteal) * 100.0))
		"heal":
			if float(instance.get("percent_max_hp", 0)) > 0.0:
				parts.append("恢复最大生命 %d%%" % roundi(float(instance.percent_max_hp) * 100.0))
			if int(instance.get("amount", 0)) > 0:
				parts.append("恢复生命 %d" % int(instance.amount))
			if float(instance.get("power", 0)) > 0.0:
				parts.append("恢复攻击力 %d%%" % roundi(float(instance.power) * 100.0))
			if float(instance.get("periodic", 0)) > 0.0:
				parts.append("之后每回合恢复攻击力 %d%%" % roundi(float(instance.periodic) * 100.0))
		"shield":
			if float(instance.get("percent_max_hp", 0)) > 0.0:
				parts.append("追加最大生命 %d%% 护盾" % roundi(float(instance.percent_max_hp) * 100.0))
			parts.append("护盾攻击系数 %d%%" % roundi(float(instance.get("power", 0)) * 100.0))
			if int(instance.get("turns", 0)) > 0:
				parts.append("%d 回合" % int(instance.turns))
		"mana":
			parts.append("%s灵力 %d" % ["削减" if bool(instance.get("drain", false)) else "恢复", int(instance.get("amount", 0))])
		"cleanse":
			parts.append("净化 %d 个负面状态" % int(instance.get("count", 1)))
		"status":
			var status := str(definition.get("status", ""))
			var rule: Dictionary = growth.get("statuses", {}).get(status, {})
			parts.append(str(rule.get("name", definition.get("name", status))))
			parts.append("概率 %d%%" % roundi(float(instance.get("chance", 1.0)) * 100.0))
			parts.append("%d 回合" % int(instance.get("turns", rule.get("turns", 1))))
			if int(instance.get("layers", 1)) != 1:
				parts.append("%d 层" % int(instance.layers))
			if int(instance.get("flat", 0)) != 0:
				parts.append("额外 %s" % instance.flat)
			if float(rule.get("value", 0)) != 0.0:
				parts.append("状态表每层 %d%%" % roundi(float(rule.value) * 100.0))
		_:
			parts.append(str(definition.get("name", "")))
	return "，".join(parts)

static func _check_value(value: Variant, param: Dictionary) -> String:
	match str(param.get("type", "")):
		"bool":
			if not value is bool:
				return "必须是布尔值"
		"enum":
			if not value is String or not param.get("options", []).has(value):
				return "不在可选枚举内"
		"int":
			if not _whole(value, int(param.get("min", 0)), int(param.get("max", 0))):
				return "必须是 %s 到 %s 的整数" % [param.get("min", 0), param.get("max", 0)]
		"float", "percent":
			if not _number(value) or float(value) < float(param.get("min", 0)) or float(value) > float(param.get("max", 0)):
				return "必须介于 %s 和 %s" % [param.get("min", 0), param.get("max", 0)]
		_:
			return "未知参数类型"
	return ""

static func _valid_id(value: Variant) -> bool:
	if not value is String:
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z][a-z0-9_]{2,63}$")
	return regex.search(value) != null

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and int(value) >= minimum and int(value) <= maximum

static func _param(id: String, name: String, type: String, default: Variant, minimum: float, maximum: float, scales := false) -> Dictionary:
	return {"id": id, "name": name, "type": type, "default": default, "min": minimum, "max": maximum, "unit": "%" if type == "percent" else "", "required": true, "scales": scales}

static func _enum_param(id: String, name: String, default: String, options: Array) -> Dictionary:
	return {"id": id, "name": name, "type": "enum", "default": default, "options": options, "required": true, "scales": false}

static func _damage(id: String, name: String, text: String, power: float, flat: int, hits: int, steal: bool) -> Dictionary:
	return {
		"id": id, "name": name, "category": "伤害", "executor": "damage", "trigger": "instant",
		"targets": ["enemy"], "usage": ["spell"], "builtin": true, "summary": text,
		"parameters": [
			_param("power", "攻击系数", "percent", power, 0.0, 5.0, true),
			_param("flat", "基础伤害", "int", flat, 0, 99999, true),
			_param("hits", "攻击次数", "int", hits, 1, 8, false),
			_param("can_crit", "可暴击", "bool", true, 0, 1, false),
			_param("lifesteal", "吸血比例", "percent", 0.3 if steal else 0.0, 0.0, 1.0, true),
		],
	}

static func _status(id: String, name: String, category: String, status: String, text: String) -> Dictionary:
	return {
		"id": id, "name": name, "category": category, "executor": "status", "status": status,
		"trigger": "duration", "targets": ["enemy"] if category in ["伤害", "减益", "控制"] else ["self"],
		"usage": ["spell"], "builtin": true, "summary": text,
		"parameters": [
			_param("chance", "触发概率", "percent", 1.0, 0.0, 1.0, true),
			_param("turns", "持续回合", "int", 2, 1, 9, true),
			_param("layers", "层数", "int", 1, 1, 9, false),
			_param("flat", "额外数值", "int", 0, 0, 99999, true),
			_enum_param("mode", "叠加方式", "stack", ["stack", "refresh", "replace"]),
			_param("max_layers", "最大层数", "int", 1, 1, 9, false),
		],
	}

static func _heal(id: String, name: String, periodic: bool) -> Dictionary:
	return {
		"id": id, "name": name, "category": "恢复", "executor": "heal", "trigger": "duration" if periodic else "instant",
		"targets": ["self"], "usage": ["spell"], "builtin": true,
		"summary": "治疗走 SkillEngine 的治疗结算。" if not periodic else "立即治疗可以为 0，随后按攻击力比例持续恢复。",
		"parameters": [
			_param("amount", "固定恢复", "int", 0 if periodic else 30, 0, 99999, true),
			_param("power", "攻击系数", "percent", 0.0, 0.0, 5.0, true),
			_param("percent_max_hp", "最大生命比例", "percent", 0.0, 0.0, 1.0, true),
			_param("periodic", "每回合攻击系数", "percent", 0.1 if periodic else 0.0, 0.0, 2.0, true),
		],
	}

static func _shield() -> Dictionary:
	return {
		"id": "effect_shield", "name": "护盾", "category": "防护", "executor": "shield", "trigger": "duration",
		"targets": ["self"], "usage": ["spell"], "builtin": true,
		"summary": "护盾吸收量由攻击系数、最大生命比例和现有护盾上限共同决定。",
		"parameters": [
			_param("power", "攻击系数", "percent", 0.8, 0.0, 5.0, true),
			_param("percent_max_hp", "最大生命比例", "percent", 0.0, 0.0, 1.0, true),
			_param("turns", "持续回合", "int", 2, 1, 9, true),
		],
	}

static func _mana(id: String, name: String, drain: bool) -> Dictionary:
	return {
		"id": id, "name": name, "category": "恢复" if not drain else "特殊", "executor": "mana",
		"trigger": "instant", "drain": drain, "targets": ["enemy" if drain else "self"], "usage": ["spell"],
		"builtin": true, "summary": "按现有灵力增减结算。",
		"parameters": [_param("amount", "灵力数值", "int", 8, 0, 99999, true)],
	}

static func _cleanse() -> Dictionary:
	return {
		"id": "effect_cleanse", "name": "净化", "category": "特殊", "executor": "cleanse", "trigger": "instant",
		"targets": ["self"], "usage": ["spell"], "builtin": true,
		"summary": "按现有负面状态列表移除可驱散状态。",
		"parameters": [_param("count", "数量", "int", 1, 1, 9, false)],
	}
