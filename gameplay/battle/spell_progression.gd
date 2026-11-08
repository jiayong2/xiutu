extends RefCounted

const TITLES := ["初窥门径", "略有小成", "驾轻就熟", "融会贯通", "登峰造极"]
const AFFIX_LEVELS := [3, 5]

static func grant_trials(player: Dictionary, spells: Dictionary) -> void:
	for id in spells:
		if spells[id].get("trial", false) and not player.spells.has(id):
			player.spells[id] = 1

static func maximum(spell: Dictionary) -> int:
	return spell.levels.size() if spell.has("levels") else 3

static func effects(spell: Dictionary, level: int) -> Dictionary:
	var result := {}
	for index in range(level):
		result.merge(spell.levels[index], true)
	return result

static func affix_slots(level: int) -> int:
	return int(level >= AFFIX_LEVELS[0]) + int(level >= AFFIX_LEVELS[1])

static func supports_affixes(spell: Dictionary) -> bool:
	return spell.id == "skill_spirit_bolt" or spell.get("target","") in ["enemy","all","chain"]

static func growth(player: Dictionary, id: String, gain: int, data: Dictionary) -> Dictionary:
	var level := int(player.spells[id])
	var cap := maximum(data.spells[id])
	var target := int(data.spell_growth.per_level)
	var before := int(player.get("spell_mastery", {}).get(id, 0))
	var total := mini(before + gain, (cap - level) * target)
	var next := level + int(total / target)
	return {"before":level,"level":next,"gain":maxi(0,total-before),"progress":total % target,"target":target}

static func add_mastery(player: Dictionary, id: String, gain: int, data: Dictionary) -> Dictionary:
	var result := growth(player, id, gain, data)
	player.spells[id] = result.level
	if not player.has("spell_mastery"):
		player.spell_mastery = {}
	player.spell_mastery[id] = result.progress
	return result

static func validate_player(player: Dictionary, data: Dictionary) -> bool:
	var mastery: Variant = player.get("spell_mastery", {})
	var affixes: Variant = player.get("spell_affixes", {})
	var pending: Variant = player.get("spell_affix_pending", {})
	if not mastery is Dictionary or not affixes is Dictionary or not pending is Dictionary:
		return false
	for id in mastery:
		if not player.spells.has(id) or not data.spells[id].has("levels") or not _whole(mastery[id], 0, int(data.spell_growth.per_level)-1):
			return false
		if player.spells[id] == maximum(data.spells[id]) and mastery[id] != 0:
			return false
	for id in affixes:
		if not player.spells.has(id) or not supports_affixes(data.spells[id]) or not affixes[id] is Dictionary:
			return false
		var equipped := {}
		for slot in affixes[id]:
			if not slot is String or not slot.is_valid_int() or str(int(slot)) != slot or not _whole(int(slot), 0, affix_slots(int(player.spells[id]))-1) or not data.spell_growth.affixes.has(affixes[id][slot]):
				return false
			var key: String = affixes[id][slot]
			if equipped.has(key):
				return false
			equipped[key] = true
	if not pending.is_empty():
		var id: Variant = pending.get("id")
		if not id is String or not player.spells.has(id) or not supports_affixes(data.spells[id]) or not pending.get("token") is String:
			return false
		if not _whole(pending.get("slot"), 0, affix_slots(int(player.spells[id]))-1) or not pending.get("candidates") is Array or pending.candidates.is_empty():
			return false
		var seen := {}
		for key in pending.candidates:
			if not key is String or not data.spell_growth.affixes.has(key) or seen.has(key) or key in affixes.get(id,{}).values():
				return false
			seen[key] = true
	return true

static func _whole(value: Variant, minimum: int, maximum_value: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floorf(float(value)) and value >= minimum and value <= maximum_value

static func percent(value: float) -> String:
	return "%d%%" % roundi(value * 100)

static func affix_effect(entry: Dictionary) -> String:
	var value: Variant = percent(entry.value) if "%s" in entry.effect else int(entry.value)
	return entry.effect % value

static func effect_lines(spell: Dictionary, level: int, config: Dictionary) -> Array:
	var lines: Array = []
	if not spell.has("levels"):
		if spell.heal > 0:
			lines.append(["heal", "恢复 %d 点生命" % int(spell.heal + (level-1)*10)])
		elif spell.guard > 0:
			lines.append(["guard", "防御 +%d" % int(spell.guard + (level-1)*2)])
		else:
			lines.append(["damage", "造成%s攻击力伤害" % percent(spell.multiplier + (level-1)*.1)])
		if not spell.status.is_empty():
			lines.append(["control", "命中时有概率施加%s" % config.statuses[spell.status].name])
		return lines
	var e := effects(spell, level)
	if e.has("power"):
		var hits := int(e.get("hits",1))
		lines.append(["damage", "造成%s攻击力伤害" % percent(e.power) if hits == 1 else "%d 段攻击，每段造成%s攻击力伤害" % [hits, percent(e.power)]])
	if e.has("shield"):
		lines.append(["guard", "获得攻击力%s的岩盾，持续%d次自身后续行动" % [percent(e.shield), config.statuses.rock_shield.turns]])
	var labels := {
		"status":["control","施加%s"],"armor_bonus":["combo","目标已破甲时增伤%s"],"self_status":["combo","施法后获得1层%s"],
		"mark_pierce":["combo","目标已有剑痕时无视%s防御"],"extra_poison":["control","目标已中毒时额外施加%d层中毒"],
		"poison_echo":["combo","目标已有%d层中毒时立即额外结算一次中毒伤害"],"wet_mana":["heal","目标已潮湿时恢复%d点灵力"],
		"wet_bonus":["combo","目标已潮湿时追加%s攻击力水伤"],"burn_intent":["combo","目标已有灼烧时获得%d层炎势"],
		"extra_burn":["control","目标已有至少%d层灼烧时额外施加1层"],"reduction":["guard","岩盾存在时直接伤害降低%s"],
		"rebound":["combo","岩盾被击破时反震%s攻击力固定伤害"],"extra_hit":["combo","施法有%s概率追加一段"],
		"extra_hit_status":["combo","成功追加攻击后获得1层%s"],"mark_crit":["damage","目标已有雷印时暴击率提高%d个百分点"],
		"crit_mark":["control","暴击时额外施加%d层雷印"],"wet_chill":["control","目标已潮湿时额外施加%d层寒意"],
		"chill_bonus":["combo","目标每有1层寒意增伤%s，最多15%%"],
		"pierce":["damage","无视目标%s防御"],"consume_enemy":["combo","消耗目标全部%s"],"detonate":["combo","每层被消耗状态追加%s攻击力伤害"],
		"consume_status":["control","达到层数条件时施加%s"],"consume_threshold":["normal","触发状态至少需消耗%d层"],
		"consume_crit_damage":["normal","消耗%d层时强化本次暴击伤害"],"crit_damage":["damage","暴击伤害倍率增加%s"],
		"consume_leech":["normal","消耗%d层时从引爆伤害吸血"],"leech_special":["heal","引爆吸血比例%s，受最大生命限制"],
		"periodic_mana":["heal","灵泉每次行动结束恢复%d点灵力"],"mana":["heal","立即恢复%d点灵力"],
		"spring_discount":["heal","灵泉期间法术少消耗%d点灵力"],"consume_self_status":["combo","达到层数条件时自身获得%s"],
		"consume_self_threshold":["normal","获取自身状态至少需消耗%d层"],"consume_self_layers":["combo","自身状态获得%d层"],
		"shield_damage_bonus":["combo","自身有岩盾时增伤%s"],"shock_repair":["guard","攻击已有震荡的目标时恢复攻击力%s的岩盾"],
		"speed":["combo","速度增加%s"],"dodge":["guard","闪避率增加%s"],"dodge_counter":["combo","闪避后反击，造成%s攻击力伤害"],
		"dodge_wind":["combo","闪避后获得%d层风势"],"consume_crit":["normal","消耗%d层时提高本次暴击率"],"crit_bonus":["damage","暴击率增加%s"],
		"slow":["control","使目标速度降低%s"],"seal":["control","消耗%d层寒意尝试封脉"],"seal_weaken":["control","封脉成功后目标下一次直接攻击伤害降低%s"],
		"secondary_status":["control","同时施加1层%s"],"layers":["control","主要状态施加%d层"],"hit_intent":["combo","命中后获得%d层剑意"],
		"consume_self":["combo","消耗自身全部%s"],"self_bonus":["combo","每层被消耗状态使本次直接伤害增加%s"],"kill_mana":["heal","击败目标后恢复%d点灵力"],
		"execute":["combo","目标生命低于%s时追加一段"],"execute_hit":["damage","斩击造成%s攻击力伤害"],
		"heal":["heal","恢复攻击力%s的生命"],"periodic_heal":["heal","生机每次恢复攻击力%s的生命"],"low_heal":["heal","低于30%%生命时，立即治疗量额外提高%s"],
		"cleanse":["heal","生命低于30%%时清除%d个可驱散持续伤害状态"],
		"leech":["heal","恢复实际直接生命伤害的%s"],"poison_leech":["heal","目标已中毒时，吸血提高至%s"],"poison_mana":["heal","目标有至少3层中毒时恢复%d点灵力"],
		"wet_weaken":["control","命中已潮湿目标时，其下一次直接攻击伤害降低%s"],"next_discount":["heal","下一次耗灵主动法术减少%d点灵力消耗"],
		"poison_bonus":["combo","目标已中毒时追加%s攻击力火伤"],"burn_bonus":["combo","目标已有灼烧时追加%s攻击力伤害"],
		"self_crit_threshold":["normal","消耗%d层自身状态时增加暴击率"],"self_crit":["damage","本次法术暴击率增加%s"],
		"hit_repair":["guard","受到直接攻击后恢复攻击力%s的岩盾"],"hit_rebound":["combo","有岩盾时受击反震%s攻击力固定伤害"],
		"shield_break_bonus":["combo","对敌方护盾的伤害提高%s"],"shield_break_status":["control","击破敌方护盾时施加%s"],"shield_break_gain":["guard","击破敌方护盾时获得攻击力%s的岩盾"],
		"wind_bonus":["combo","每层风势提高本法术伤害%s"],"wind_consume":["combo","达到%d层风势时消耗并追加一段"],"wind_hit":["damage","额外风刃造成%s攻击力伤害"],
		"self_layers":["combo","自身状态获得%d层"],"wind_discount":["heal","下一次风系攻击法术少消耗%d点灵力"],"wind_crit":["damage","下一次风系攻击暴击率增加%s"],
		"wind_mana":["heal","下一次风系法术命中至少2段时恢复%d点灵力"],
		"bounce":["damage","弹射保留前一目标%s伤害，最多弹射2次"],"wet_status":["control","命中潮湿目标时施加%s"],
		"electrified_bonus":["combo","命中已感电目标时追加%s攻击力雷伤"],"thunder_echo":["combo","引雷期间主动攻击法术追加一次%s攻击力雷伤"],
		"echo_mark":["control","引雷追加伤害有%s概率施加雷印"],"echo_mana":["heal","引雷命中已感电目标时恢复%d点灵力"],
		"hit_chill":["control","受到直接攻击时给攻击者施加%d层寒意"],"chill_mana":["heal","冰甲受击施加寒意时恢复%d点灵力"],
		"rebound_chill":["control","冰甲击破时给攻击者施加%d层寒意"],
		"consume_pierce_threshold":["combo","消耗至少%d层寒意时触发穿透"],"consume_pierce":["damage","触发时无视%s防御"]}
	for key in labels:
		if not e.has(key):
			continue
		var value: Variant = e[key]
		if value is String:
			value = config.statuses[value].name
		elif key == "mark_crit":
			value = roundi(value*100)
		elif "%s" in labels[key][1]:
			value = percent(value)
		lines.append([labels[key][0], labels[key][1] % value])
	return lines
