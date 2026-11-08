extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")

const GROWTH_ATTRIBUTES := {"qi": ["qi_sea", "meridians"], "body": ["bones", "physique"]}
const Mental = preload("res://gameplay/character/mental_attributes.gd")
const NURTURE_DENOMINATOR := 3600000
const LAYERS := ["一","二","三","四","五","六","七","八","九"]
const MAX_LEVEL := 81

func validate_growth_rules(rules: Dictionary) -> String:
	for key in ["body_max_level", "body_required", "attribute_start", "attribute_cap",
			"attribute_cap_per_breakthrough", "nurture_per_point"]:
		if not _whole(rules.get(key)) or rules[key] <= 0:
			return "修炼成长配置无效：" + key
	if rules.attribute_start > rules.attribute_cap:
		return "修炼属性初值超出上限"
	var mental: Variant = rules.get("mental")
	if not mental is Dictionary:
		return "缺少识海和神魂配置"
	for field in ["initial","npc_first_tier_step","attack_weights","defense_weights"]:
		if not mental.get(field) is Dictionary:
			return "识海和神魂配置无效"
		for key in Mental.KEYS:
			var value: Variant = mental[field].get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or (field in ["initial","npc_first_tier_step"] and not _whole(value)):
				return "识海和神魂参数无效"
	for field in ["base_chance","difference_scale","min_chance","max_chance","tier_modifier","modifier_cap"]:
		var value: Variant = mental.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0:
			return "神识威慑公式配置无效"
	if mental.min_chance > mental.max_chance or mental.max_chance > 100 or not mental.get("personality_modifier") is Dictionary or not mental.get("mood_modifier") is Dictionary:
		return "神识威慑修正配置无效"
	if rules.body_max_level != MAX_LEVEL:
		return "体修总层数必须与九阶配置一致"
	for key in ["extra_cap_per_new_tier","major_foundation_gap"]:
		if not _whole(rules.get(key)):
			return "无效境界成长配置：" + key
	var foundation: Variant = rules.get("character_foundation")
	if not foundation is Dictionary:
		return "缺少角色根基属性配置"
	for key in ["initial_aptitude","initial_blood","mp_per_qi_sea","hp_per_physique","blood_per_physique",
			"attack_per_bone","bones_per_defense","spell_bps_per_meridian"]:
		if not _whole(foundation.get(key)) or foundation[key]>100:
			return "无效角色根基属性参数：" + key
	if foundation.initial_blood<=0 or foundation.bones_per_defense<=0:
		return "气血初值及防御换算必须大于零"
	var quality: Variant = rules.get("breakthrough_quality")
	if not quality is Dictionary or not _whole(quality.get("per_extra_technique_level")):
		return "突破品质配置缺失"
	for route in GROWTH_ATTRIBUTES:
		var scores: Variant = quality.get(route)
		if not scores is Dictionary or not _whole(scores.get("middle_score")) or not _whole(scores.get("high_score")) or scores.middle_score>=scores.high_score:
			return "突破品质分数无效：" + route
	return ""

func validate_realm_tiers(data: Dictionary) -> String:
	if data.realm_tiers.size() != 9:
		return "境界配置必须包含九阶"
	var previous_lifespan := 0
	for index in range(1,10):
		var row: Variant = data.realm_tiers.get("tier_%d" % index)
		if not row is Dictionary:
			return "缺少境界阶位 %d" % index
		for key in ["qi","body"]:
			if not row.get(key) is String or row[key].is_empty():
				return "缺少境界名：" + key
			var resources: Variant = row.get(key+"_materials")
			if not resources is Dictionary:
				return "境界材料定义无效"
			for item in resources:
				if not data.items.has(item) or not _whole(resources[item]) or resources[item] <= 0:
					return "境界材料引用或数量无效：" + item
		for key in ["lifespan","qi_start","qi_step","body_start","body_step"]:
			if not _whole(row.get(key)):
				return "无效境界参数：" + key
		if row.lifespan <= previous_lifespan or row.qi_start<=0 or row.body_start<=0:
			return "境界寿元或修为参数无效"
		previous_lifespan = int(row.lifespan)
		if not row.get("qi_growth") is Array or row.qi_growth.size()!=5:
			return "法修战斗属性成长定义无效"
		for value in row.qi_growth:
			if not _whole(value):
				return "法修战斗属性成长值无效"
	return ""

func initialize_growth(data: Dictionary) -> Dictionary:
	var attributes := {}
	for route in GROWTH_ATTRIBUTES:
		for key in GROWTH_ATTRIBUTES[route]:
			attributes[key] = int(data.progression.attribute_start)
	for key in Mental.KEYS:
		attributes[key] = int(data.progression.mental.initial[key])
	return {"body_level": 0, "body_cultivation": 0,
		"attributes": attributes,
		"focus": {"qi": "balance", "body": "balance"}}

func validate_growth(p: Dictionary, data: Dictionary) -> String:
	if not p.has("growth"):
		return "" # Save predates the cultivation growth fields.
	var growth: Variant = p.growth
	if not growth is Dictionary or not growth.get("attributes") is Dictionary or not growth.get("focus") is Dictionary:
		return "修炼成长存档结构无效"
	if growth.has("breakthrough_quality"):
		if not growth.breakthrough_quality is Dictionary:
			return "突破品质记录无效"
		for route in growth.breakthrough_quality:
			if route not in ["qi","body"] or growth.breakthrough_quality[route] not in ["base","middle","high"]:
				return "突破品质记录无效"
	for key in ["body_level", "body_cultivation"]:
		if not _whole(growth.get(key)):
			return "炼体进度无效"
	var quality: Dictionary = growth.get("breakthrough_quality",{})
	if (quality.has("qi") and p.realm < 10) or (quality.has("body") and growth.body_level < 10):
		return "突破品质与当前境界不符"
	if growth.body_level > MAX_LEVEL or growth.body_cultivation > requirement(p,"body",data):
		return "炼体进度超限"
	if not _whole(growth.get("body_fraction",0)) or growth.get("body_fraction",0) >= int(data.rules.hours_day) * 3600 * 10000:
		return "炼体修为余数超限"
	if growth.has("nurture_fraction") and not growth.nurture_fraction is Dictionary:
		return "旧温养余量结构无效"
	for key in Mental.KEYS:
		if growth.attributes.has(key):
			var value: Variant = growth.attributes[key]
			if not _whole(value) or value < data.progression.mental.initial[key] or value > Mental.cap(key,attribute_cap(p,"qi",data),data.progression):
				return "识海或神魂无效：" + key
	for route in GROWTH_ATTRIBUTES:
		if growth.focus.get(route) not in ["refinement", "balance", "nurture"]:
			return "修炼倾向无效：" + route
		for key in GROWTH_ATTRIBUTES[route]:
			var value: Variant = growth.attributes.get(key)
			if not _whole(value) or value < data.progression.attribute_start or value > attribute_cap(p, route, data):
				return "修炼属性无效：" + key
		var fraction: Variant = growth.get("nurture_fraction",{}).get(route,0)
		if not _whole(fraction) or fraction >= int(data.progression.nurture_per_point) * NURTURE_DENOMINATOR:
			return "温养余数无效：" + route
	return ""

func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and floor(float(value)) == value

func attribute_cap(p: Dictionary, route: String, data: Dictionary) -> int:
	var breakthroughs: int = int(p.growth.body_level) if route == "body" else int(p.realm) - 1
	var tier: int = tier_index(int(p.growth.body_level) if route=="body" else int(p.realm))
	var major_bonus: int = maxi(0,tier - (1 if route=="body" else 2)) * int(data.progression.extra_cap_per_new_tier)
	return int(data.progression.attribute_cap) + breakthroughs * int(data.progression.attribute_cap_per_breakthrough) + major_bonus

static func tier_index(level: int) -> int:
	return 1 + (maxi(1,level)-1)/9

static func npc_realm_label(npc: Dictionary, data: Dictionary) -> String:
	var level := int(npc.get("realm",-1))
	if level == 0:
		return "凡人"
	if npc.get("realm_known",false) == true:
		return realm_name(level,"qi",data)
	return "境界未知"

static func realm_name(level: int, route: String, data: Dictionary) -> String:
	if level == 0 and route=="body":
		return "凡体"
	if level < 1 or level > MAX_LEVEL:
		return "境界未知"
	var name: String = data.realm_tiers["tier_%d" % tier_index(level)][route]
	return "%s%s层" % [name,LAYERS[(level-1)%9]]

func body_realm_name(p: Dictionary, data: Dictionary) -> String:
	return realm_name(int(p.growth.body_level),"body",data)

func equipped_techniques(p: Dictionary, route: String, data: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	for id in p.technique_slots:
		var technique: Dictionary = data.techniques[id]
		if technique.cultivation_route == route:
			names.append(technique.name)
	return names

func requirement(p: Dictionary, route: String, data: Dictionary) -> int:
	var level: int = int(p.growth.body_level) if route=="body" else int(p.realm)
	if level >= MAX_LEVEL:
		return 0
	if level <= 9:
		return int(data.progression.body_required) if route=="body" else int(data.realms["qi_%d" % level].required)
	var tier: Dictionary = data.realm_tiers["tier_%d" % tier_index(level)]
	return int(tier[route+"_start"]) + ((level-1)%9) * int(tier[route+"_step"])

func progress(p: Dictionary, route: String) -> int:
	return int(p.growth.body_cultivation) if route == "body" else int(p.cultivation)

func promote_body(p: Dictionary, data: Dictionary) -> String:
	var level: int = int(p.growth.body_level)
	var required: int = requirement(p,"body",data)
	if required == 0:
		return "已达当前炼体境界上限"
	if p.growth.body_cultivation < required:
		return "炼体修为不足"
	var tier: Dictionary = data.realm_tiers["tier_%d" % tier_index(level+1)]
	if _is_major(level):
		var error: String = _check_major(p,"body",tier.body_materials,data)
		if not error.is_empty():
			return error
		_consume_materials(p,tier.body_materials)
		if level == 9:
			_record_breakthrough_quality(p,"body",data)
		p.lifespan = maxi(int(p.lifespan),int(tier.lifespan))
	p.growth.body_cultivation -= required
	p.growth.body_level += 1
	return ""

func promote(s: Dictionary, data: Dictionary, random: RefCounted) -> String:
	var p: Dictionary = s.player
	var level: int = int(p.realm)
	var required: int = requirement(p,"qi",data)
	if required == 0:
		return "已达当前法修境界上限"
	if p.cultivation < required:
		return "修为不足"
	var next_tier: Dictionary = data.realm_tiers["tier_%d" % tier_index(level+1)]
	if level == 9:
		var missing: String = _check_materials(p,next_tier.qi_materials,data)
		if not missing.is_empty():
			return missing
		_consume_materials(p,next_tier.qi_materials)
		var chance := clampf(float(data.rules.foundation_chance) + Fortunes.modifier(p,"foundation_chance","","个百分点") / 100.0,0,1)
		if random.roll("world") >= chance:
			p.cultivation = maxi(0,int(p.cultivation - data.rules.foundation_loss))
			s.last_result = "筑基失败，消耗筑基丹与修为"
			return ""
		if p.has("growth"):
			_record_breakthrough_quality(p,"qi",data)
	elif _is_major(level):
		var error: String = _check_major(p,"qi",next_tier.qi_materials,data)
		if not error.is_empty():
			return error
		_consume_materials(p,next_tier.qi_materials)
	if _is_major(level):
		p.lifespan = maxi(int(p.lifespan),int(next_tier.lifespan))
	p.cultivation -= required
	p.realm += 1
	var keys := ["hp","mp","attack","defense","speed"]
	var growth: Array = data.realms["qi_%d" % level].growth if level<=9 else next_tier.qi_growth
	for i in range(keys.size()):
		p.base[keys[i]] += int(growth[i])
	if level != 9:
		p.cultivation = mini(int(p.cultivation),requirement(p,"qi",data))
	return ""

func breakthrough_days(p: Dictionary, route: String, data: Dictionary) -> int:
	var level: int = int(p.growth.body_level) if route=="body" else int(p.realm)
	return int(data.rules.foundation_days) if _is_major(level) else 1

func breakthrough_summary(p: Dictionary, route: String, data: Dictionary) -> String:
	var required: int = requirement(p,route,data)
	if required == 0:
		return "已达当前境界上限"
	var level: int = int(p.growth.body_level) if route=="body" else int(p.realm)
	var lines := PackedStringArray(["目标：%s；需修为 %d；耗时 %d 日" % [
		realm_name(level+1,route,data),required,breakthrough_days(p,route,data)]])
	if _is_major(level):
		var materials: Dictionary = data.realm_tiers["tier_%d" % tier_index(level+1)][route+"_materials"]
		if level==9 and route=="qi":
			lines.append("基础成功率：%.0f%%" % (100.0*float(data.rules.foundation_chance)))
		else:
			var minimum: int = attribute_cap(p,route,data)-int(data.progression.major_foundation_gap)
			lines.append("%s均需达到 %d" % ["筋骨和体魄" if route=="body" else "气海和经脉",minimum])
		for id in materials:
			lines.append("%s：%d / %d" % [data.items[id].name,p.inventory.get(id,0),materials[id]])
	return "\n".join(lines)

func _is_major(level: int) -> bool:
	return level > 0 and level % 9 == 0

func _check_major(p: Dictionary, route: String, materials: Dictionary, data: Dictionary) -> String:
	var minimum: int = attribute_cap(p,route,data) - int(data.progression.major_foundation_gap)
	for key in GROWTH_ATTRIBUTES[route]:
		if p.growth.attributes[key] < minimum:
			return "%s均需达到 %d" % ["筋骨和体魄" if route=="body" else "气海和经脉",minimum]
	return _check_materials(p,materials,data)

func _check_materials(p: Dictionary, materials: Dictionary, data: Dictionary) -> String:
	for id in materials:
		if p.inventory.get(id,0) < materials[id]:
			return "需要 %s ×%d" % [data.items[id].name,materials[id]]
	return ""

func _consume_materials(p: Dictionary, materials: Dictionary) -> void:
	for id in materials:
		p.inventory[id] -= int(materials[id])

func _record_breakthrough_quality(p: Dictionary, route: String, data: Dictionary) -> void:
	if not p.growth.has("breakthrough_quality"):
		p.growth.breakthrough_quality = {}
	if p.growth.breakthrough_quality.has(route):
		return
	var rules: Dictionary = data.progression.breakthrough_quality
	var scores: Dictionary = rules[route]
	var attributes: Dictionary = p.growth.attributes
	var keys: Array = GROWTH_ATTRIBUTES[route]
	var highest := 1
	for id in p.technique_slots:
		if data.techniques[id].cultivation_route == route:
			highest = maxi(highest,int(p.techniques[id]))
	# Compare doubled scores so odd attribute totals keep their half point.
	var score_twice: int = int(attributes[keys[0]]) + int(attributes[keys[1]]) + 2 * (highest - 1) * int(rules.per_extra_technique_level)
	p.growth.breakthrough_quality[route] = "high" if score_twice >= 2 * int(scores.high_score) else "middle" if score_twice >= 2 * int(scores.middle_score) else "base"
