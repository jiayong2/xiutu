extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")

func plant(s: Dictionary, plot: int, herb: String, data: Dictionary, inventory: RefCounted) -> String:
	if plot < 0 or plot >= s.plots.size() or not s.plots[plot].is_empty() or not data.herbs.has(herb):
		return "灵田不可用或灵草不存在"
	var h: Dictionary = data.herbs[herb]
	var error: String = inventory.remove(s.player,h.seed_id,1)
	if not error.is_empty():
		return error
	var speed := Fortunes.modifier(s.player,"plant_speed")
	var growth_hours := ceili(float(h.days) * float(data.rules.hours_day) * 100.0 / maxf(1,100 + speed))
	s.plots[plot] = {"herb":herb,"planted_at":s.hours,"ready_at":s.hours + growth_hours}
	return ""

func harvest(s: Dictionary, plot: int, data: Dictionary, inventory: RefCounted) -> String:
	if plot < 0 or plot >= s.plots.size() or s.plots[plot].is_empty():
		return "灵田为空"
	var planted: Dictionary = s.plots[plot]
	if s.hours < planted.ready_at:
		return "灵草尚未成熟"
	inventory.add(s.player,planted.herb,int(data.herbs[planted.herb].yield_count),data)
	s.plots[plot] = {}
	return ""

func craft(s: Dictionary, recipe: String, data: Dictionary, inventory: RefCounted) -> String:
	if not data.recipes.has(recipe):
		return "丹方不存在"
	var r: Dictionary = data.recipes[recipe]
	if s.player.spirit_stones < r.cost:
		return "灵石不足"
	for id in r.materials:
		if s.player.inventory.get(id,0) < r.materials[id]:
			return "材料不足"
	for id in r.materials:
		inventory.remove(s.player,id,int(r.materials[id]))
	s.player.spirit_stones -= r.cost
	inventory.add(s.player,r.output,1,data)
	return ""
