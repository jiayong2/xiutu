@tool
extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")

func add(p: Dictionary, id: String, quantity: int, data: Dictionary, next_id: String = "") -> String:
	if not data.items.has(id) or quantity <= 0:
		return "无效物品或数量"
	if data.equipment.has(id):
		for i in range(quantity):
			p.equipment_instances[next_id + "_" + str(i)] = id
	else:
		p.inventory[id] = int(p.inventory.get(id,0)) + quantity
	return ""

func remove(p: Dictionary, id: String, quantity: int) -> String:
	if quantity <= 0 or p.inventory.get(id,0) < quantity:
		return "物品不足"
	p.inventory[id] -= quantity
	if p.inventory[id] == 0:
		p.inventory.erase(id)
	return ""

func use(p: Dictionary, id: String, data: Dictionary, stats: Dictionary, day: int) -> String:
	if p.inventory.get(id,0) <= 0:
		return "物品不足"
	var effect: Variant = data.items[id].use_effect
	if effect is Dictionary and effect.has("learn"):
		var learned: Dictionary = p.techniques if data.techniques.has(effect.learn) else p.spells
		if learned.has(effect.learn):
			return "已经学会，不可重复学习"
		if data.techniques.has(effect.learn):
			var minimum := int(data.techniques[effect.learn].get("realm_min", 0))
			if minimum > 0 and int(p.get("realm", 1)) < minimum:
				return "境界不足，无法学习"
		learned[effect.learn] = 1
	elif id == "pill_qi_gathering":
		if p.realm > 9 or p.last_pill_day == day:
			return "仅炼气期可用，每日限一颗"
		p.cultivation += data.rules.pill_gain
		p.last_pill_day = day
	elif effect is Dictionary and effect.has("stat"):
		if p[effect.stat] >= stats[effect.stat]:
			return "生命或灵力已满"
		var percent := Fortunes.modifier(p,"pill_recovery") if data.items[id].type == "丹药" else 0
		var amount := roundi(float(effect.amount) * (100 + percent) / 100.0)
		p[effect.stat] = mini(int(stats[effect.stat]),int(p[effect.stat])+amount)
	else:
		return "该物品不能直接使用"
	return remove(p,id,1)

## Presentation mapping for the inventory; static types remain unchanged.
func display_category(id: String,data: Dictionary) -> String:
	var item: Dictionary=data.items[id]
	if data.equipment.has(id):return "装备"
	var effect: Variant=item.use_effect
	if effect is Dictionary and effect.has("learn"):
		return "功法" if data.techniques.has(effect.learn) else "法术"
	if item.type in ["丹药","消耗品"]:return "丹药"
	for quest in data.quests.values():
		if quest.get("required_item","")==id:return "任务物品"
	return "材料"
