@tool
extends RefCounted

const Equipment := preload("res://gameplay/inventory/equipment_values.gd")
const Fortunes := preload("res://gameplay/character/player_fortunes.gd")
const NPC_BASE_KEYS := ["hp","mp","attack","defense","speed"]
const NPC_RANKS := ["天骄","人杰","精英","良才","普通","凡人"]

static func npc_rank(profile: Dictionary) -> String:
	var rank: Variant = profile.get("rank", "普通")
	return rank if rank in NPC_RANKS else "普通"
const APTITUDE_KEYS := ["constitution","spirituality","insight","luck","charm","mind"]
const ROOT_QUALITIES := {"ordinary":"普通灵根","fine":"优良灵根","superior":"上乘灵根","heavenly":"天灵根"}

func initialize_traits(data: Dictionary) -> Dictionary:
	var aptitudes := {}
	for key in APTITUDE_KEYS:
		aptitudes[key] = int(data.progression.character_foundation.initial_aptitude)
	return {"root_quality":"ordinary","aptitudes":aptitudes}

func validate_traits(traits: Variant) -> bool:
	if not traits is Dictionary or traits.get("root_quality") not in ROOT_QUALITIES.keys() or not traits.get("aptitudes") is Dictionary:
		return false
	for key in APTITUDE_KEYS:
		var value: Variant = traits.aptitudes.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value != floor(float(value)) or value < 0 or value > 100:
			return false
	return true

func foundation_bonuses(p: Dictionary, data: Dictionary) -> Dictionary:
	var rules: Dictionary = data.progression.character_foundation
	var start: int = int(data.progression.attribute_start)
	var attributes: Dictionary = p.get("growth",{}).get("attributes",{})
	var physique: int = maxi(0,int(attributes.get("physique",start))-start)
	var bones: int = maxi(0,int(attributes.get("bones",start))-start)
	var sea: int = maxi(0,int(attributes.get("qi_sea",start))-start)
	var meridians: int = maxi(0,int(attributes.get("meridians",start))+Fortunes.modifier(p,"stat","meridians","fixed")-start)
	return {"hp":physique*int(rules.hp_per_physique),"mp":sea*int(rules.mp_per_qi_sea),
		"attack":bones*int(rules.attack_per_bone),"defense":int(bones/int(rules.bones_per_defense)),
		"blood":physique*int(rules.blood_per_physique),"spell_bps":meridians*int(rules.spell_bps_per_meridian)}

func initialize(base: Dictionary, rules: Dictionary, name: String, root: String, identity: String) -> Dictionary:
	return {"id":identity, "name":name.strip_edges(), "root":root, "realm":1,
		"base":{"hp":base.hp,"mp":base.mp,"attack":base.attack,"defense":base.defense,"speed":base.speed},
		"hp":base.hp,"mp":base.mp,"cultivation":base.cultivation,"spirit_stones":base.spirit_stones,
		"age":base.age,"lifespan":base.lifespan,"location":base.location_id,
		"inventory":rules.initial_items.duplicate(true),"equipment_instances":{"starting_sword":rules.initial_equipment},
		"equipped":{"weapon":"starting_sword"},"techniques":rules.initial_techniques.duplicate(true),
		"technique_slots":rules.initial_techniques.keys(),"spells":rules.initial_spells.duplicate(true),
		"spell_slots":rules.initial_spells.keys(),"last_pill_day":-1}

func stats(p: Dictionary, data: Dictionary, sources: Variant = null) -> Dictionary:
	var result: Dictionary = p.base.duplicate(true)
	result.fire = 0.0
	result.blood = int(data.progression.character_foundation.initial_blood)
	if sources != null:
		for key in result:
			sources[key] = {"基础值": result[key]}
	for instance in p.equipped.values():
		var id: String = p.equipment_instances[instance]
		var definition: Dictionary = data.equipment[id]
		var label := "装备 · " + str(data.items[id].name) if sources != null else ""
		var values := Equipment.base_stats(definition,p,str(instance),data.rules)
		for key in values:
			if result.has(key):
				_add_bonus(result, sources, key, values[key], label)
		for entry in definition.get("traits", []):
			var key: String = entry.type
			var amount := Equipment.trait_amount(definition,entry,p,data.rules)
			if key in ["attack","mp"]:
				_add_bonus(result,sources,key,amount,label)
			elif key not in ["control_resist","wood_reduction","deterrence"]:
				if not result.has("equipment_effects"):
					result.equipment_effects = {}
				result.equipment_effects[key] = result.equipment_effects.get(key,0) + amount
	for id in p.technique_slots:
		var definition: Dictionary = data.techniques[id]
		var level: int = int(p.techniques[id])
		var label := "功法 · %s Lv.%d" % [definition.name, level] if sources != null else ""
		for key in ["hp","defense","attack","fire"]:
			_add_bonus(result, sources, key, technique_amount(definition, key, level), label)
		for key in ["mp", "speed", "critical", "critical_damage"]:
			if definition.has(key) or definition.has(key + "_step") or technique_level_row(definition, level).has(key):
				if not result.has(key):
					result[key] = 0
					if sources != null:
						sources[key] = {}
				_add_bonus(result, sources, key, technique_amount(definition, key, level), label)
		var percents: Variant = definition.get("percents", {})
		if percents is Dictionary and not percents.is_empty():
			var snapshot := {}
			for key in percents:
				snapshot[str(key)] = result.get(key, 0)
			for key in percents:
				if not result.has(key):
					continue
				var ratio := float(percents[key])
				var percent_override: Dictionary = technique_level_row(definition, level).get("percents", {})
				if percent_override.has(key):
					ratio = float(percent_override[key])
				_add_bonus(result, sources, key, roundi(float(snapshot[key]) * ratio), label)
	var foundation := foundation_bonuses(p,data)
	for key in ["hp","mp","attack","defense","blood"]:
		_add_bonus(result, sources, key, foundation[key], "修炼根基")
	for key in ["hp","mp","blood","attack","defense","speed"]:
		var fixed := Fortunes.modifier(p,"stat",key,"fixed")
		var percent := Fortunes.modifier(p,"stat",key)
		_add_bonus(result,sources,key,fixed + roundi(float(result[key] + fixed) * percent / 100.0),"天赋与气运")
	result.spell_bps = foundation.spell_bps
	return result

static func valid_npc_loadout(loadout: Variant, data: Dictionary) -> bool:
	if not loadout is Dictionary or not loadout.get("equipment") is Dictionary or not loadout.get("techniques") is Dictionary:
		return false
	if loadout.techniques.size() > 10:
		return false
	for id in loadout.techniques:
		var level: Variant = loadout.techniques[id]
		if not data.techniques.has(id) or not (level is int or level is float) or level != floor(float(level)) or level < 1 or level > 5:
			return false
	for slot in loadout.equipment:
		var id: Variant = loadout.equipment[slot]
		if not id is String or not data.equipment.has(id) or data.equipment[id].slot != slot:
			return false
	return true

func npc_stats(npc: Dictionary, profile: Dictionary, data: Dictionary, sources: Dictionary = {}) -> Dictionary:
	var base: Dictionary = profile.get("base", {}).duplicate()
	base.merge(_npc_base(int(npc.realm),data))
	base.merge({"critical":data.rules.crit_chance, "critical_damage":data.rules.crit_multiplier, "dodge":0.0})
	var attributes: Dictionary = profile.get("foundation", {}).duplicate()
	attributes.merge(npc.get("attributes", {}), true)
	var loadout: Dictionary = npc.get("loadout", profile.get("loadout", {"equipment":{}, "techniques":{}}))
	var equipment: Dictionary = loadout.equipment
	var techniques: Dictionary = loadout.techniques
	var actor := {"base":base, "growth":{"attributes":attributes},
		"fortunes":npc.get("fortunes",{}), "equipped":{}, "equipment_instances":equipment, "technique_slots":techniques.keys(), "techniques":techniques}
	for slot in equipment:
		actor.equipped[slot] = slot
	if not profile.has("loadout"):
		actor.realm = npc.realm
	if npc.get("authored", false):
		for key in ["realm","equipped","equipment_instances","equipment_nurture","techniques","technique_slots"]:
			actor[key] = npc[key]
	var result := stats(actor, data, sources)
	for fortune in profile.get("innate_fortune", []) + profile.get("acquired_fortune", []):
		for key in fortune.bonuses:
			_add_bonus(result, sources, key, fortune.bonuses[key], "气运 · " + str(fortune.name))
	for key in profile.get("stat_overrides", {}):
		var override: Variant = profile.stat_overrides[key]
		_add_bonus(result, sources, key, override - result[key], "手动覆盖")
	return result

func _npc_base(realm: int, data: Dictionary) -> Dictionary:
	if realm <= 0:
		return data.prototype.npc_mortal_base
	var base: Dictionary = data.prototype.npc_cultivator_base.duplicate()
	for level in range(1,realm):
		var tier := 1 + int(level / 9)
		var growth: Array = data.realms["qi_%d" % level].growth if level <= 9 else data.realm_tiers["tier_%d" % tier].qi_growth
		for index in range(NPC_BASE_KEYS.size()):
			base[NPC_BASE_KEYS[index]] += int(growth[index])
	return base

static func technique_level_row(definition: Dictionary, level: int) -> Dictionary:
	var table: Variant = definition.get("level_overrides", {})
	if not table is Dictionary:
		return {}
	var row: Variant = table.get(str(level), {})
	return row if row is Dictionary else {}

static func technique_amount(definition: Dictionary, key: String, level: int) -> Variant:
	var override := technique_level_row(definition, level)
	if override.has(key):
		return override[key]
	return definition.get(key, 0) + definition.get(key + "_step", 0) * (level - 1)

func _add_bonus(result: Dictionary, sources: Variant, key: String, amount: Variant, label: String) -> void:
	result[key] += amount
	if sources != null and amount != 0:
		sources[key][label] = sources[key].get(label, 0) + amount
