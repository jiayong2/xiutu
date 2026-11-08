extends RefCounted
const Cultivation = preload("res://gameplay/cultivation/cultivation_system.gd")
const Character = preload("res://gameplay/character/character_system.gd")
const OPTIONS: Array[String]=["交谈","打听","赠礼","交易","请教","论道","切磋","邀请","拜师","任务","查看","其他"]
func evaluate(state: Dictionary,data: Dictionary,id: String,kind: String,previous_option: String="") -> Dictionary:
	if kind not in OPTIONS:return {"kind":"reject","message":"无效互动请求。"}
	if kind in ["打听","赠礼","请教","论道","切磋","邀请","拜师","其他"]:
		return {"kind":"unavailable","message":"该互动功能尚未开放。"}
	var npc: Dictionary=state.npcs.get(id,{})
	if npc.is_empty():return {"kind":"reject","message":"没有此人物的信息。"}
	if not npc.alive:return {"kind":"reject","message":"此人已故，无法回应。"}
	if npc.location!=state.player.location:return {"kind":"reject","message":"对方已不在此处，现在无法与你交流。"}
	if sect_area_restricted(npc,data):return {"kind":"reject","message":"尚未获得此人物所在区域的通行权限。"}
	if not state.battle.is_empty():return {"kind":"reject","message":"请先结束当前战斗。"}
	if kind=="交易":
		for shop in data.shops.values():
			if shop.npc_id==id and shop.location==npc.location:return {"kind":"trade","shop":shop.id,"message":"可以，看看店里的货物吧。"}
		return {"kind":"reject","message":"我目前没有可交易的货物。"}
	if kind=="任务":
		var quests := preload("res://gameplay/quest/quest_system.gd").new()
		var options := quests.dialogue_options(state,id,data,previous_option)
		var line := quests.dialogue_line(state,id,data)
		if line.is_empty():
			line = "看看这些委托吧。" if not options.is_empty() else "我目前没有可委托你的事情。"
		return {"kind":"quests","options":options,"message":line}
	if kind=="查看":return {"kind":"info"}
	return {"kind":"talk","message":""}

static func sect_area_restricted(npc: Dictionary, data: Dictionary) -> bool:
	var area_id: String = npc.get("sect_area", "")
	if area_id.is_empty():
		return false
	for area in data.sect_areas.get(npc.get("sect", ""), []):
		if area.id == area_id:
			return not area.restriction.is_empty()
	return true
func presentation(state: Dictionary,data: Dictionary,id: String) -> Dictionary:
	var npc: Dictionary=state.npcs.get(id,{})
	var identity: String=npc.get("role","身份未记录")
	for shop in data.shops.values():
		if shop.npc_id==id:identity=shop.name+"掌柜";break
	if identity=="身份未记录":
		for quest in data.quests.values():
			if quest.giver_npc_id==id:identity="委托发布者";break
	var realm := Cultivation.npc_realm_label(npc,data)
	var profile: Dictionary = {}
	for definition in data.prototype.npcs:
		if definition.id == id:
			profile = definition.get("profile", {})
			break
	profile = npc.get("profile", profile)
	return {"name":npc.get("name","未知人物"),"identity":identity,"realm":realm,
		"rank":Character.npc_rank(profile),"relation":"关系：" + relation_label(npc,state.player.id)}

static func relation_label(npc: Dictionary, other_id: String) -> String:
	var value: Variant = npc.get("relations", {}).get(other_id, 0)
	if value is int or value is float or (value is String and value.is_valid_float()):
		var score := float(value)
		if score < 0: return "冷淡"
		if score > 0: return "友善"
		return "陌生"
	return str(value) if value is String and not value.is_empty() else "陌生"

func summary(state: Dictionary,data: Dictionary,id: String) -> String:
	var info: Dictionary=presentation(state,data,id)
	return "%s · %s\n%s · %s" % [info.name,info.realm,info.identity,info.relation.replace("关系：","关系")]
