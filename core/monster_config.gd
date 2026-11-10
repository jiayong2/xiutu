extends RefCounted
## Shared monster configuration validation.
##
## The same constants are intended for the future in-game monster, skill,
## behaviour and loot editors. Validation never mutates the tables.

const RANKS := ["normal", "elite", "boss"]
const EFFECT_TYPES := ["damage", "status", "stat", "heal", "shield", "mana", "cleanse", "phase"]
const SKILL_TARGETS := ["enemy", "self", "random_enemy", "lowest_enemy", "all_enemies"]
const STATS := ["attack", "defense", "speed", "crit"]
const CONDITION_TYPES := [
	"always", "hp_below", "hp_above", "mp_at_least",
	"self_status", "self_not_status", "target_status", "target_not_status",
	"action_every", "turn_every", "turn_at_least",
	"skill_uses_below", "skill_uses_at_least", "phase",
	"ally_count_at_least", "enemy_count_at_least", "has_available_skill",
]
const ACTIONS := ["attack", "skill", "defend", "charge", "flee", "heal", "buff"]
const CONDITION_MODES := ["all", "any"]
const TARGETS := ["self", "enemy", "random_enemy", "lowest_enemy", "all_enemies"]
const ALLY_TARGETS := ["ally", "lowest_ally", "all_allies"]
const TRIGGER_EVENTS := ["battle_start", "hp_below", "turn_start"]
const SCOPES := ["player", "npc", "monster"]

static func validate(tables: Dictionary) -> String:
	var skills: Dictionary = tables.get("monster_skills", {})
	for skill in skills.values():
		var error := validate_skill(skill, tables)
		if not error.is_empty():
			return error
	for monster in tables.monsters.values():
		var error := validate_monster(monster, tables, skills)
		if not error.is_empty():
			return error
	return ""

static func validate_skill(skill: Variant, tables: Dictionary) -> String:
	if not skill is Dictionary:
		return "妖兽技能配置无效"
	var id := str(skill.get("id", ""))
	if id.is_empty() or not id.is_valid_identifier():
		return "妖兽技能缺少有效 ID"
	if not skill.get("name") is String or skill.name.strip_edges().is_empty():
		return "妖兽技能缺少名称：" + id
	if not _int(skill.get("mp", 0), 0):
		return "妖兽技能灵力消耗无效：" + id
	if not _int(skill.get("cooldown", 0), 0):
		return "妖兽技能冷却无效：" + id
	if str(skill.get("target", "enemy")) not in SKILL_TARGETS:
		return "妖兽技能目标不支持：" + id
	if skill.has("scope"):
		if not skill.scope is Array or skill.scope.is_empty():
			return "妖兽技能适用范围无效：" + id
		for scope in skill.scope:
			if str(scope) not in SCOPES:
				return "妖兽技能适用范围无效：" + id
	if skill.has("ordinary") and not skill.ordinary is bool:
		return "妖兽技能普通攻击标记无效：" + id
	if not skill.get("effects") is Array or skill.effects.is_empty():
		return "妖兽技能缺少效果：" + id
	for effect in skill.effects:
		var error := validate_effect(effect, tables)
		if not error.is_empty():
			return "%s / %s" % [id, error]
	return ""

static func validate_effect(effect: Variant, tables: Dictionary) -> String:
	if not effect is Dictionary:
		return "效果配置无效"
	var kind := str(effect.get("type", ""))
	if kind not in EFFECT_TYPES:
		return "不支持的效果类型：" + kind
	if effect.has("chance") and not _number(effect.chance, 0.0, 1.0):
		return "效果触发概率无效"
	if effect.has("target") and str(effect.target) not in ["self", "enemy"]:
		return "效果目标无效"
	if effect.has("turns") and not _int(effect.turns, 1):
		return "效果持续回合无效"
	if effect.has("layers") and not _int(effect.layers, 1):
		return "效果层数无效"
	if effect.has("mode") and str(effect.mode) not in ["stack", "refresh", "replace"]:
		return "效果叠加方式无效"
	if effect.has("requires_hit") and not effect.requires_hit is bool:
		return "效果命中标记无效"
	match kind:
		"damage":
			if not _number(effect.get("power", 0), 0.0, 99.0):
				return "伤害倍率无效"
			if effect.has("hits") and not _int(effect.hits, 1):
				return "攻击段数无效"
			if effect.has("flat") and not _int(effect.flat, 0):
				return "固定伤害无效"
			if effect.has("percent_max_hp") and not _number(effect.percent_max_hp, 0.0, 1.0):
				return "百分比伤害无效"
			if effect.has("can_crit") and not effect.can_crit is bool:
				return "暴击标记无效"
			if effect.has("lifesteal") and not _number(effect.lifesteal, 0.0, 1.0):
				return "吸血比例无效"
		"status":
			var status := str(effect.get("status", ""))
			if not tables.spell_growth.statuses.has(status):
				return "不存在的状态：" + status
		"stat":
			if str(effect.get("stat", "")) not in STATS:
				return "不支持的属性：" + str(effect.get("stat", ""))
			if not _number(effect.get("value", 0), -1.0, 1.0):
				return "属性修正值无效"
			if effect.has("flat") and not _number(effect.flat, -999.0, 999.0):
				return "属性固定修正无效"
		"heal":
			if effect.has("amount") and not _int(effect.amount, 0):
				return "治疗固定值无效"
			if effect.has("power") and not _number(effect.power, 0.0, 99.0):
				return "治疗倍率无效"
			if effect.has("percent_max_hp") and not _number(effect.percent_max_hp, 0.0, 1.0):
				return "治疗百分比无效"
		"shield":
			if effect.has("power") and not _number(effect.power, 0.0, 99.0):
				return "护盾倍率无效"
			if effect.has("percent_max_hp") and not _number(effect.percent_max_hp, 0.0, 1.0):
				return "护盾百分比无效"
		"mana":
			if effect.has("amount") and not _int(effect.amount, 0):
				return "灵力数值无效"
			if effect.has("percent") and not _number(effect.percent, 0.0, 1.0):
				return "灵力百分比无效"
			if effect.has("drain") and not effect.drain is bool:
				return "灵力抽取标记无效"
		"cleanse":
			if effect.has("count") and not _int(effect.count, 1):
				return "驱散数量无效"
			if effect.has("statuses"):
				if not effect.statuses is Array:
					return "驱散状态列表无效"
				for status in effect.statuses:
					if not tables.spell_growth.statuses.has(str(status)):
						return "不存在的状态：" + str(status)
		"phase":
			if not effect.get("value") is String or effect.value.is_empty():
				return "阶段名称无效"
	return ""

static func validate_monster(monster: Dictionary, tables: Dictionary, skills: Dictionary) -> String:
	var id := str(monster.get("id", ""))
	if monster.has("realm") and not _int(monster.realm, 0):
		return "妖兽境界无效：" + id
	if monster.has("rank") and str(monster.rank) not in RANKS:
		return "妖兽身份无效：" + id
	var skill_ids: Array = []
	if monster.has("skill_ids"):
		if not monster.skill_ids is Array:
			return "妖兽技能列表无效：" + id
		for skill_id in monster.skill_ids:
			if not skill_id is String or not skills.has(skill_id):
				return "妖兽引用不存在的技能：" + id
			if skill_id in skill_ids:
				return "妖兽技能重复：" + id
			skill_ids.append(skill_id)
	if monster.has("behaviors"):
		if not monster.behaviors is Array:
			return "妖兽行为列表无效：" + id
		var behavior_ids := {}
		for behavior in monster.behaviors:
			var error := validate_behavior(behavior, tables, skill_ids, behavior_ids)
			if not error.is_empty():
				return "%s / %s" % [id, error]
	if monster.has("passives"):
		if not monster.passives is Array:
			return "妖兽被动列表无效：" + id
		for effect in monster.passives:
			var error := validate_effect(effect, tables)
			if not error.is_empty():
				return "%s 被动：%s" % [id, error]
			if str(effect.get("type", "")) == "damage":
				return "%s 被动暂不支持伤害效果" % id
	if monster.has("triggers"):
		if not monster.triggers is Array:
			return "妖兽触发列表无效：" + id
		var trigger_ids := {}
		for trigger in monster.triggers:
			var error := validate_trigger(trigger, tables, skill_ids, trigger_ids)
			if not error.is_empty():
				return "%s / %s" % [id, error]
	if not monster.get("loot") is Dictionary or monster.loot.is_empty():
		return "妖兽缺少掉落表：" + id
	var loot_error := validate_loot(monster.loot, tables, id)
	if not loot_error.is_empty():
		return loot_error
	return ""

static func validate_behavior(behavior: Variant, tables: Dictionary, skill_ids: Array, seen: Dictionary) -> String:
	if not behavior is Dictionary:
		return "行为规则无效"
	var id := str(behavior.get("id", ""))
	if id.is_empty() or not id.is_valid_identifier():
		return "行为规则缺少有效 ID"
	if seen.has(id):
		return "行为规则重复：" + id
	seen[id] = true
	if not _int(behavior.get("priority", 0), -2147483648):
		return "行为优先级无效：" + id
	if behavior.has("enabled") and not behavior.enabled is bool:
		return "行为启用标记无效：" + id
	if behavior.has("conditions"):
		var error := validate_conditions(behavior.conditions, tables, skill_ids)
		if not error.is_empty():
			return "%s / %s" % [id, error]
	if behavior.has("condition_mode") and str(behavior.condition_mode) not in CONDITION_MODES:
		return "不支持的条件组合方式：" + id
	var action := str(behavior.get("action", "attack"))
	if action not in ACTIONS:
		return "不支持的行为动作：" + id
	var target := str(behavior.get("target", "enemy"))
	if target in ALLY_TARGETS:
		return "当前一对一战斗不支持友方目标：" + id
	if target not in TARGETS:
		return "不支持的行为目标：" + id
	if behavior.has("chance") and not _number(behavior.chance, 0.0, 1.0):
		return "行为触发概率无效：" + id
	if behavior.has("max_uses") and not _int(behavior.max_uses, 0):
		return "行为次数限制无效：" + id
	if behavior.has("cooldown") and not _int(behavior.cooldown, 0):
		return "行为冷却无效：" + id
	if behavior.has("on_fail") and str(behavior.on_fail) not in ["continue", "fallback"]:
		return "行为失败处理无效：" + id
	if action in ["skill", "heal", "buff"]:
		var skill := str(behavior.get("skill", ""))
		if skill.is_empty() or skill not in skill_ids or not tables.get("monster_skills", {}).has(skill):
			return "行为引用不存在的技能：" + id
	return ""

static func validate_conditions(conditions: Variant, tables: Dictionary, skill_ids: Array) -> String:
	var rows: Array = conditions if conditions is Array else [conditions]
	for condition in rows:
		if not condition is Dictionary:
			return "行为条件无效"
		var kind := str(condition.get("type", "always"))
		if kind not in CONDITION_TYPES:
			return "不支持的行为条件：" + kind
		match kind:
			"hp_below", "hp_above":
				if not _number(condition.get("value", 100), 0.0, 100.0):
					return "生命比例条件无效"
			"mp_at_least":
				if not _int(condition.get("value", 0), 0):
					return "灵力条件无效"
			"self_status", "self_not_status", "target_status", "target_not_status":
				if not tables.spell_growth.statuses.has(str(condition.get("status", ""))):
					return "条件引用不存在的状态：" + str(condition.get("status", ""))
				if condition.has("side") and str(condition.side) not in ["player", "enemy"]:
					return "状态条件阵营无效"
			"action_every", "turn_every":
				if not _int(condition.get("value", 0), 1):
					return "行动周期条件无效"
			"turn_at_least", "ally_count_at_least", "enemy_count_at_least":
				if not _int(condition.get("value", 0), 0):
					return "计数条件无效"
			"skill_uses_below", "skill_uses_at_least":
				if str(condition.get("skill", "")) not in skill_ids:
					return "条件引用不存在的技能：" + str(condition.get("skill", ""))
				if not _int(condition.get("value", 0), 0):
					return "技能次数条件无效"
			"phase":
				if not condition.get("value") is String or condition.value.is_empty():
					return "阶段条件无效"
	return ""

static func validate_trigger(trigger: Variant, tables: Dictionary, skill_ids: Array, seen: Dictionary) -> String:
	if not trigger is Dictionary:
		return "触发规则无效"
	var id := str(trigger.get("id", ""))
	if id.is_empty() or not id.is_valid_identifier():
		return "触发规则缺少有效 ID"
	if seen.has(id):
		return "触发规则重复：" + id
	seen[id] = true
	if str(trigger.get("event", "")) not in TRIGGER_EVENTS:
		return "不支持的触发事件：" + id
	if trigger.has("enabled") and not trigger.enabled is bool:
		return "触发启用标记无效：" + id
	if trigger.has("once") and not trigger.once is bool:
		return "触发单次标记无效：" + id
	if trigger.has("max_uses") and not _int(trigger.max_uses, 0):
		return "触发次数限制无效：" + id
	var error := validate_conditions(trigger.get("conditions", []), tables, skill_ids)
	if not error.is_empty():
		return "%s / %s" % [id, error]
	if not trigger.get("effects") is Array or trigger.effects.is_empty():
		return "触发规则缺少效果：" + id
	for effect in trigger.effects:
		error = validate_effect(effect, tables)
		if not error.is_empty():
			return "%s / %s" % [id, error]
		if str(effect.get("type", "")) == "damage":
			return "触发规则暂不支持伤害效果：" + id
	return ""

static func validate_loot(loot: Variant, tables: Dictionary, monster_id: String) -> String:
	if not loot is Dictionary:
		return "妖兽掉落表无效：" + monster_id
	if loot.has("money"):
		if not loot.money is Array or loot.money.size() != 2 or not _int(loot.money[0], 0) or not _int(loot.money[1], 0) or int(loot.money[1]) < int(loot.money[0]):
			return "妖兽掉落灵石区间无效：" + monster_id
	# An explicit empty array means this monster drops no items. The array is still
	# required so that a missing loot table cannot be mistaken for "no drops".
	if not loot.get("entries") is Array:
		return "妖兽掉落表缺少条目列表：" + monster_id
	for entry in loot.entries:
		if not entry is Dictionary:
			return "妖兽掉落条目无效：" + monster_id
		var item := str(entry.get("item_id", ""))
		if not tables.items.has(item):
			return "妖兽掉落引用不存在的物品：" + monster_id
		if not _int(entry.get("min", 1), 1) or not _int(entry.get("max", 1), 1) or int(entry.get("max", 1)) < int(entry.get("min", 1)):
			return "妖兽掉落数量无效：" + monster_id
		if entry.has("chance") and not _number(entry.chance, 0.0, 1.0):
			return "妖兽掉落概率无效：" + monster_id
		if entry.has("guaranteed") and not entry.guaranteed is bool:
			return "妖兽掉落必得标记无效：" + monster_id
		if entry.has("independent") and entry.independent != true:
			return "暂不支持非独立掉落判定：" + monster_id
		if entry.has("once") and (not entry.once is String or entry.once.strip_edges().is_empty()):
			return "妖兽掉落单次标记无效：" + monster_id
		if entry.has("legacy_flag") and (not entry.legacy_flag is String or entry.legacy_flag.strip_edges().is_empty()):
			return "妖兽掉落旧档标记无效：" + monster_id
		if entry.has("conditions"):
			var conditions: Variant = entry.conditions
			if not conditions is Dictionary:
				return "妖兽掉落条件无效：" + monster_id
			if conditions.has("rank"):
				if not conditions.rank is Array:
					return "妖兽掉落身份条件无效：" + monster_id
				for rank in conditions.rank:
					if str(rank) not in RANKS:
						return "妖兽掉落身份条件无效：" + monster_id
			if conditions.has("realm_min") and not _int(conditions.realm_min, 0):
				return "妖兽掉落境界条件无效：" + monster_id
	return ""

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _int(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and int(value) >= minimum
