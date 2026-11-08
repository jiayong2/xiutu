extends RefCounted
## Reports are state differences of a committed interval, never random flavour text.
static func build(before: Dictionary,after: Dictionary,interval: Dictionary,requested: int,id: String,data: Dictionary) -> Dictionary:
	var groups: Dictionary={"cultivation":[],"npc":[],"sect":[],"economy":[],"world":[],"quest":[]}
	var cultivation := preload("res://gameplay/cultivation/cultivation_system.gd").new()
	var route: String = interval.get("route","qi")
	var current: int = cultivation.progress(after.player,route)
	var required: int = cultivation.requirement(after.player,route,data)
	var title: String = "炼体修为" if route=="body" else "修为"
	groups.cultivation.append("%s %d → %d（+%d），境界保持不变，突破需手动确认。" % [title,cultivation.progress(before.player,route),current,interval.gain])
	for entry in [["qi_sea","气海"],["meridians","经脉"],["bones","筋骨"],["physique","体魄"]]:
		var old_value: int = before.player.growth.attributes[entry[0]]
		var new_value: int = after.player.growth.attributes[entry[0]]
		if new_value > old_value:
			groups.cultivation.append("%s温养：%d → %d。" % [entry[1],old_value,new_value])
	if required>0 and current>=required:groups.cultivation.append("已达瓶颈；剩余闭关时间照常推进，不再积累有效修为。")
	for npc_id in after.npcs:
		var old: Dictionary=before.npcs[npc_id];var npc: Dictionary=after.npcs[npc_id]
		if old.alive and not npc.alive:groups.npc.append("%s寿元已尽。" % npc.name)
		if npc.realm!=old.realm:groups.npc.append("%s：炼气%d层 → 炼气%d层。" % [npc.name,old.realm,npc.realm])
		if npc.cultivation!=old.cultivation:groups.npc.append("%s修为：%d → %d。" % [npc.name,old.cultivation,npc.cultivation])
		if npc.location!=old.location:groups.npc.append("%s已迁往%s。" % [npc.name,{"town_qinglan":"青岚镇","town_yunxi":"云溪城"}.get(npc.location,npc.location)])
	for town in after.prices:
		if before.prices.get(town,10000)!=after.prices[town]:groups.economy.append("%s物价系数：%.2f → %.2f。" % [{"town_qinglan":"青岚镇","town_yunxi":"云溪城"}.get(town,town),before.prices.get(town,10000)/10000.0,after.prices[town]/10000.0])
	for shop_id in after.stocks:
		if before.stocks[shop_id]!=after.stocks[shop_id]:groups.economy.append("%s库存已按原月度补货规则更新。" % data.shops[shop_id].name)
	if before.player.spirit_stones!=after.player.spirit_stones:groups.economy.append("灵石：%d → %d（原聚灵阵维护结算）。" % [before.player.spirit_stones,after.player.spirit_stones])
	if before.formation and not after.formation:groups.world.append("聚灵阵因维护费不足关闭，洞府不再汇聚周围灵气。")
	for index in range(after.plots.size()):
		var plot: Dictionary=after.plots[index]
		if not plot.is_empty() and before.hours<plot.ready_at and after.hours>=plot.ready_at:groups.world.append("灵田%d的%s已经成熟。" % [index+1,data.items[plot.herb].name])
	return {"id":id,"start":interval.start,"end":interval.end,"requested":requested,"elapsed":interval.elapsed,"gain":interval.gain,"after":current,"age":after.player.age,"realm":after.player.growth.body_level if route=="body" else after.player.realm,"route":route,"interrupted":interval.interrupted,"reason":interval.reason,"groups":groups,"spirit_ledger":interval.ledger}
