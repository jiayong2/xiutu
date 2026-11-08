extends RefCounted

const SLOTS := {"weapon":"武器","head":"头冠","armor":"法衣","wrist":"护腕","waist":"腰带","shoes":"灵靴","necklace":"项链","ring":"戒指"}
const STATS := {"hp":"生命","mp":"灵力","attack":"攻击","defense":"防御","speed":"速度","spirit_sea":"识海","soul":"神魂"}
const TRAIT_TEXT := {
	"attack":"攻击额外+%d", "mp":"灵力上限额外+%d", "burn_damage":"灼烧伤害+%d%%",
	"shield_damage":"对护盾伤害+%d%%", "control_resist":"控制抗性+%d%%",
	"wood_reduction":"受到的木系伤害降低%d%%", "final_reduction":"受到的最终伤害降低%d%%",
	"critical":"暴击率+%d%%", "defense_ignore":"忽略目标%d%%防御", "opening_shield":"战斗开始时获得%d点护盾",
	"dodge":"闪避率+%d%%", "deterrence":"神识威慑效果+%d%%",
	"healing_received":"受到治疗效果+%d%%", "five_element_damage":"金木水火土伤害+%d%%"
}

static func equip_error(definition: Dictionary, realm: int) -> String:
	if definition.is_empty():
		return "装备定义不存在"
	if definition.has("realm") and realm < definition.realm:
		return "境界不足"
	return ""

static func level(player: Dictionary, instance: String) -> int:
	return int(player.get("equipment_nurture", {}).get(instance, 0))

static func factor(definition: Dictionary, player: Dictionary, rules: Dictionary) -> float:
	if not definition.has("recommended_realm"):
		return 1.0
	var tier := ceili(float(player.get("realm", 1)) / 9.0)
	return float(rules.equipment_overrealm_factor) if tier < int(definition.recommended_realm[0]) else 1.0

static func base_stats(definition: Dictionary, player: Dictionary, instance: String, rules: Dictionary) -> Dictionary:
	if not definition.has("base_stats"):
		return {"hp":definition.hp,"attack":definition.attack,"defense":definition.defense}
	var values: Dictionary = definition.base_stats.duplicate()
	var growth := 1.0 + float(rules.equipment_growth_percent[level(player, instance)]) / 100.0
	var scale := factor(definition, player, rules)
	for key in values:
		if values[key] > 0:
			values[key] = roundi(values[key] * scale * (growth if key not in ["spirit_sea","soul"] else 1.0))
	return values

static func trait_amount(definition: Dictionary, entry: Dictionary, player: Dictionary, rules: Dictionary) -> int:
	return roundi(float(entry.amount) * factor(definition, player, rules))

