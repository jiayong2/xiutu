extends RefCounted
## Minimal NPC combat policy.
##
## Equipped, learned spells are tried in slot order. The first affordable
## offensive spell is cast. A support spell is used only when no offensive
## spell is ready and current life is at or below half. Otherwise the NPC
## attacks, or defends when life is at or below 35% and nothing can be cast.
## Items, unlearned spells and unequipped spells are never selected.

const LOW_HP := 0.35
const SUPPORT_HP := 0.50

static func choose(battle: Dictionary, data: Dictionary, mana_cost: Callable) -> Dictionary:
	var enemy: Dictionary = battle.get("enemy", {})
	var attack := {"action": "attack", "skill": {}, "label": "普通攻击"}
	if battle.get("status", {}).has("silence") or battle.get("status", {}).has("seal"):
		return _fallback(battle, attack)
	var learned: Dictionary = enemy.get("spells", {}) if enemy.get("spells") is Dictionary else {}
	var slots: Array = enemy.get("spell_slots", []) if enemy.get("spell_slots") is Array else []
	var cooldowns: Dictionary = {}
	if battle.get("enemy_ai") is Dictionary and battle.enemy_ai.get("cooldowns") is Dictionary:
		cooldowns = battle.enemy_ai.cooldowns
	var support := {}
	var first_attack := {}
	var priority := {}
	for id in slots:
		var spell_id := str(id)
		if not learned.has(spell_id) or not data.get("spells", {}).has(spell_id):
			continue
		if int(cooldowns.get(spell_id, 0)) > 0:
			continue
		var spell: Dictionary = data.spells[spell_id]
		if int(enemy.get("mp", 0)) < int(mana_cost.call(spell)):
			continue
		var policy := str(spell.get("ai", {}).get("policy", "")) if spell.get("ai") is Dictionary else ""
		if policy in ["self_low_hp", "no_shield", "self_status"] and not _policy_allows(battle, spell):
			continue
		if policy == "target_status" and _policy_allows(battle, spell) and _offensive(spell) and priority.is_empty():
			priority = spell
		if _offensive(spell) and first_attack.is_empty():
			first_attack = spell
		elif support.is_empty() and not _offensive(spell):
			support = spell
	if not priority.is_empty():
		return {"action": "spell", "skill": priority, "label": str(priority.get("name", "法术"))}
	if not first_attack.is_empty():
		return {"action": "spell", "skill": first_attack, "label": str(first_attack.get("name", "法术"))}
	if not support.is_empty() and _hp_ratio(battle) <= SUPPORT_HP:
		return {"action": "spell", "skill": support, "label": str(support.get("name", "法术"))}
	return _fallback(battle, attack)

static func _fallback(battle: Dictionary, attack: Dictionary) -> Dictionary:
	if _hp_ratio(battle) <= LOW_HP:
		return {"action": "defend", "skill": {}, "label": "防御"}
	return attack

static func _hp_ratio(battle: Dictionary) -> float:
	var maximum := maxi(1, int(battle.get("enemy_max_hp", 1)))
	return float(int(battle.get("enemy", {}).get("hp", 0))) / float(maximum)

static func _policy_allows(battle: Dictionary, spell: Dictionary) -> bool:
	var ai: Dictionary = spell.get("ai", {})
	match str(ai.get("policy", "")):
		"self_low_hp":
			return _hp_ratio(battle) <= float(ai.get("hp", SUPPORT_HP))
		"no_shield":
			return not battle.get("status", {}).has("enemy_shield")
		"self_status":
			return battle.get("status", {}).has(str(ai.get("status", "")))
		"target_status":
			var status := str(ai.get("status", ""))
			var statuses: Dictionary = battle.get("status", {})
			return statuses.has(status) or statuses.has("player_" + status)
		_:
			return true

static func _offensive(spell: Dictionary) -> bool:
	if str(spell.get("target", "")) in ["enemy", "all", "chain"]:
		return true
	if spell.has("levels") and spell.levels is Array and not spell.levels.is_empty() and spell.levels[0] is Dictionary:
		return spell.levels[0].has("power")
	return float(spell.get("multiplier", 0.0)) > 0.0
