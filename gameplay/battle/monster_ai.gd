extends RefCounted
## Data-driven monster behaviour resolver.
##
## A monster may opt into this path with a non-empty `behaviors` array. The
## resolver never inspects a monster ID: every decision comes from saved data.

const CONDITION_TYPES := [
	"always", "hp_below", "hp_above", "mp_at_least",
	"self_status", "self_not_status", "target_status", "target_not_status",
	"action_every", "turn_every", "turn_at_least",
	"skill_uses_below", "skill_uses_at_least", "phase",
	"ally_count_at_least", "enemy_count_at_least", "has_available_skill",
]
const ACTION_TYPES := ["attack", "skill", "defend", "charge", "flee", "heal", "buff"]
const TARGETS := ["self", "enemy", "random_enemy", "lowest_enemy", "all_enemies"]
const ALLY_TARGETS := ["ally", "lowest_ally", "all_allies"]
const TRIGGER_EVENTS := ["battle_start", "hp_below", "turn_start"]

static func configured(monster: Dictionary) -> bool:
	var behaviors: Variant = monster.get("behaviors", [])
	return behaviors is Array and not behaviors.is_empty()

static func ensure_state(b: Dictionary) -> void:
	if not b.get("enemy_ai") is Dictionary:
		b["enemy_ai"] = {}
	var ai: Dictionary = b["enemy_ai"]
	for key in ["uses", "cooldowns", "rule_cooldowns", "trigger_uses"]:
		if not ai.get(key) is Dictionary:
			ai[key] = {}
	for key in ["actions"]:
		if not (ai.get(key) is int or ai.get(key) is float):
			ai[key] = 0
	if not ai.get("phase") is String:
		ai["phase"] = ""

static func begin_action(b: Dictionary) -> void:
	ensure_state(b)
	var ai: Dictionary = b.enemy_ai
	ai.actions = int(ai.actions) + 1
	for key in ai.cooldowns.keys():
		ai.cooldowns[key] = maxi(0, int(ai.cooldowns[key]) - 1)
	for key in ai.rule_cooldowns.keys():
		ai.rule_cooldowns[key] = maxi(0, int(ai.rule_cooldowns[key]) - 1)

static func choose(b: Dictionary, monster: Dictionary, data: Dictionary, random: RefCounted) -> Dictionary:
	ensure_state(b)
	var rules: Array = monster.get("behaviors", [])
	if rules.is_empty():
		return fallback()
	var ordered: Array = []
	for index in rules.size():
		if rules[index] is Dictionary:
			ordered.append({"rule": rules[index], "index": index})
	ordered.sort_custom(func(a: Dictionary, b_item: Dictionary) -> bool:
		var pa := int(a.rule.get("priority", 0))
		var pb := int(b_item.rule.get("priority", 0))
		return pa > pb if pa != pb else int(a.index) < int(b_item.index)
	)
	for entry in ordered:
		var rule: Dictionary = entry.rule
		if rule.get("enabled", true) != true:
			continue
		var rule_id := str(rule.get("id", ""))
		var max_uses := int(rule.get("max_uses", 0))
		if max_uses > 0 and int(b.enemy_ai.uses.get(rule_id, 0)) >= max_uses:
			continue
		if int(rule.get("cooldown", 0)) > 0 and int(b.enemy_ai.rule_cooldowns.get(rule_id, 0)) > 0:
			continue
		if not conditions_met(b, rule.get("conditions", []), monster, str(rule.get("condition_mode", "all"))):
			continue
		var action := str(rule.get("action", "attack"))
		var skill: Dictionary = {}
		if action in ["skill", "heal", "buff"]:
			var skill_id := str(rule.get("skill", ""))
			skill = b.get("enemy_skills", {}).get(skill_id, {})
			if skill.is_empty() or not skill_available(b, skill):
				if rule.get("on_fail", "continue") == "fallback":
					return fallback()
				continue
		if random.roll("battle") >= float(rule.get("chance", 1.0)):
			if rule.get("on_fail", "continue") == "fallback":
				return fallback()
			continue
		var label := str(rule.get("name", ""))
		if label.is_empty():
			if action in ["skill", "heal", "buff"]:
				label = str(skill.get("name", "特殊攻击"))
			else:
				label = {"attack": "普通攻击", "defend": "防御", "charge": "蓄力", "flee": "逃跑"}.get(action, "特殊攻击")
		return {
			"action": "skill" if action in ["heal", "buff"] else action,
			"skill": skill,
			"skill_id": str(skill.get("id", "")),
			"target": str(rule.get("target", "enemy")),
			"rule": rule,
			"label": label,
		}
	return fallback()

static func fallback() -> Dictionary:
	return {"action": "attack", "skill": {}, "skill_id": "", "target": "enemy", "rule": {}, "label": "普通攻击"}

static func skill_available(b: Dictionary, skill: Dictionary) -> bool:
	if b.status.has("silence") or b.status.has("seal"):
		return false
	if int(skill.get("mp", 0)) > int(b.enemy.get("mp", 0)):
		return false
	var skill_id := str(skill.get("id", ""))
	return int(b.enemy_ai.cooldowns.get(skill_id, 0)) <= 0

static func record_plan(b: Dictionary, plan: Dictionary) -> void:
	ensure_state(b)
	var ai: Dictionary = b.enemy_ai
	var rule: Dictionary = plan.get("rule", {})
	if not rule.is_empty():
		var rule_id := str(rule.get("id", ""))
		if not rule_id.is_empty():
			ai.uses[rule_id] = int(ai.uses.get(rule_id, 0)) + 1
			if int(rule.get("cooldown", 0)) > 0:
				ai.rule_cooldowns[rule_id] = int(rule.get("cooldown", 0))
	if plan.get("action", "") == "skill":
		var skill: Dictionary = plan.get("skill", {})
		var skill_id := str(skill.get("id", ""))
		if not skill_id.is_empty():
			ai.uses[skill_id] = int(ai.uses.get(skill_id, 0)) + 1

static func conditions_met(b: Dictionary, conditions: Variant, monster: Dictionary, mode := "all") -> bool:
	if conditions is Dictionary:
		conditions = [conditions]
	if not conditions is Array:
		return false
	if conditions.is_empty():
		return true
	if mode == "any":
		for condition in conditions:
			if condition is Dictionary and condition_met(b, condition, monster):
				return true
		return false
	for condition in conditions:
		if not condition is Dictionary:
			return false
		if not condition_met(b, condition, monster):
			return false
	return true

static func condition_met(b: Dictionary, condition: Dictionary, monster: Dictionary) -> bool:
	var kind := str(condition.get("type", "always"))
	match kind:
		"always":
			return true
		"hp_below":
			return _hp_percent(b) <= float(condition.get("value", 100))
		"hp_above":
			return _hp_percent(b) >= float(condition.get("value", 0))
		"mp_at_least":
			return int(b.enemy.get("mp", 0)) >= int(condition.get("value", 0))
		"self_status":
			return b.status.has(_status_id(str(condition.get("status", "")), "enemy"))
		"self_not_status":
			return not b.status.has(_status_id(str(condition.get("status", "")), "enemy"))
		"target_status":
			return b.status.has(_status_id(str(condition.get("status", "")), str(condition.get("side", "player"))))
		"target_not_status":
			return not b.status.has(_status_id(str(condition.get("status", "")), str(condition.get("side", "player"))))
		"action_every":
			var every := int(condition.get("value", 0))
			return every > 0 and int(b.enemy_ai.actions) % every == 0
		"turn_every":
			var turns := int(condition.get("value", 0))
			return turns > 0 and int(b.turn) % turns == 0
		"turn_at_least":
			return int(b.turn) >= int(condition.get("value", 0))
		"skill_uses_below":
			return int(b.enemy_ai.uses.get(str(condition.get("skill", "")), 0)) < int(condition.get("value", 0))
		"skill_uses_at_least":
			return int(b.enemy_ai.uses.get(str(condition.get("skill", "")), 0)) >= int(condition.get("value", 0))
		"phase":
			return str(b.enemy_ai.get("phase", "")) == str(condition.get("value", ""))
		"ally_count_at_least":
			return 0 >= int(condition.get("value", 1))
		"enemy_count_at_least":
			return 1 >= int(condition.get("value", 1))
		"has_available_skill":
			for skill in b.get("enemy_skills", {}).values():
				if skill is Dictionary and skill_available(b, skill):
					return true
			return false
	return false

static func pending_triggers(b: Dictionary, monster: Dictionary, event: String) -> Array:
	ensure_state(b)
	var result: Array = []
	for trigger in monster.get("triggers", []):
		if not trigger is Dictionary or trigger.get("enabled", true) != true:
			continue
		if str(trigger.get("event", "")) != event:
			continue
		var trigger_id := str(trigger.get("id", ""))
		var max_uses := int(trigger.get("max_uses", 1 if trigger.get("once", true) else 0))
		if max_uses > 0 and int(b.enemy_ai.trigger_uses.get(trigger_id, 0)) >= max_uses:
			continue
		if not conditions_met(b, trigger.get("conditions", []), monster):
			continue
		result.append(trigger)
	return result

static func mark_trigger(b: Dictionary, trigger: Dictionary) -> void:
	ensure_state(b)
	var trigger_id := str(trigger.get("id", ""))
	b.enemy_ai.trigger_uses[trigger_id] = int(b.enemy_ai.trigger_uses.get(trigger_id, 0)) + 1

static func set_phase(b: Dictionary, phase: String) -> void:
	ensure_state(b)
	b.enemy_ai.phase = phase

static func _hp_percent(b: Dictionary) -> float:
	var maximum := float(b.get("enemy_max_hp", b.enemy.get("hp", 1)))
	if maximum <= 0:
		return 0.0
	return float(b.enemy.get("hp", 0)) * 100.0 / maximum

static func _status_id(status: String, side: String) -> String:
	if status.is_empty():
		return status
	return "player_" + status if side == "player" and not status.begins_with("player_") else status
