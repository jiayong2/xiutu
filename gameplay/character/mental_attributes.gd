extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")

const Equipment := preload("res://gameplay/inventory/equipment_values.gd")
const KEYS := ["spirit_sea","soul"]

static func initialize_player(player: Dictionary, rules: Dictionary) -> void:
	for key in KEYS:
		if not player.growth.attributes.has(key):
			player.growth.attributes[key] = int(rules.initial[key])

static func initialize_npc(npc: Dictionary, rules: Dictionary) -> void:
	if not npc.has("attributes"):
		npc.attributes = {}
	for key in KEYS:
		if not npc.attributes.has(key):
			npc.attributes[key] = int(rules.initial[key])+mini(9,int(npc.realm))*int(rules.npc_first_tier_step[key])

static func advance_npc(npc: Dictionary, previous_realm: int, rules: Dictionary) -> void:
	var gained := mini(9,int(npc.realm))-mini(9,previous_realm)
	for key in KEYS:
		npc.attributes[key] += gained*int(rules.npc_first_tier_step[key])

static func effective(actor: Dictionary, data: Dictionary = {}) -> Dictionary:
	var attributes: Dictionary = actor.growth.attributes if actor.has("growth") else actor.attributes
	var result := attributes.duplicate()
	for key in KEYS:
		result[key] = maxi(0,int(attributes[key]) + Fortunes.modifier(actor,"stat",key,"fixed"))
	result.fortune_intimidation = Fortunes.modifier(actor,"intimidation","","个百分点")
	var boost := 0
	if not data.is_empty():
		for instance in actor.get("equipped",{}).values():
			var item: Dictionary = data.equipment[actor.equipment_instances[instance]]
			var values := Equipment.base_stats(item,actor,str(instance),data.rules)
			for key in KEYS:
				result[key] += int(values.get(key,0))
			for entry in item.get("traits",[]):
				if entry.type == "deterrence":
					boost += Equipment.trait_amount(item,entry,actor,data.rules)
	result.equipment_intimidation = boost / 100.0
	return result

static func cap(key: String, qi_cap: int, progression: Dictionary) -> int:
	return int(progression.mental.initial[key])+qi_cap-int(progression.attribute_start)

static func chance(attacker: Dictionary, defender: Dictionary, tier_gap: int, personality: String, mood: String, rules: Dictionary) -> float:
	var attack := float(attacker.spirit_sea)*float(rules.attack_weights.spirit_sea)+float(attacker.soul)*float(rules.attack_weights.soul)
	var resistance := float(defender.spirit_sea)*float(rules.defense_weights.spirit_sea)+float(defender.soul)*float(rules.defense_weights.soul)
	var modifier := tier_gap*float(rules.tier_modifier)
	modifier += float(rules.personality_modifier.get(personality,0))+float(rules.mood_modifier.get(mood,0))
	modifier = clampf(modifier,-float(rules.modifier_cap),float(rules.modifier_cap))
	var chance_before_cap := float(rules.base_chance)+float(rules.difference_scale)*(attack-resistance)+modifier+float(attacker.get("fortune_intimidation",0))
	return clampf(chance_before_cap*(1.0+float(attacker.get("equipment_intimidation",0))),float(rules.min_chance),float(rules.max_chance))
