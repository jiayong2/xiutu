extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")

func unit_price(s: Dictionary, data: Dictionary, shop_id: String, item: String, buying: bool) -> int:
	var p: Dictionary = s.player
	if not buying:
		var sale_percent := Fortunes.modifier(p,"sell_price")
		return maxi(0,floori(data.items[item].sell_price * (100 + sale_percent) / 100.0))
	var purchase_percent := Fortunes.modifier(p,"buy_price")
	return maxi(0,ceili(data.items[item].buy_price * s.prices.get(data.shops[shop_id].location,10000) * (100 + purchase_percent) / 1000000.0))

func trade_error(s: Dictionary, data: Dictionary, args: Dictionary, buying: bool) -> String:
	var shop_id: String = args.get("shop", "")
	var item: String = args.get("item", "")
	var qty: Variant = args.get("quantity", 1)
	if not qty is int or qty <= 0 or qty > 99 or not data.shops.has(shop_id) or not data.items.has(item):
		return "无效商品、商店或数量"
	var shop: Dictionary = data.shops[shop_id]
	var npc: Dictionary = s.npcs[shop.npc_id]
	if not npc.alive or npc.location != shop.location or s.player.location != shop.location:
		return "商人不在此处或已死亡"
	if buying:
		if item == "book_technique_fire_breath" and s.quests.get("quest_qinglan_002",{}).get("status","") != "COMPLETED":
			return "完成青岚除患后解锁"
		if item.begins_with("book_") and (s.player.techniques.has(item.substr(5)) or s.player.spells.has(item.substr(5))):
			return "已学秘籍不可重复购买"
		var price: int = unit_price(s,data,shop_id,item,true) * qty
		if s.stocks[shop_id].get(item,0) < qty or s.player.spirit_stones < price:
			return "库存或灵石不足"
	else:
		if item == "material_wolf_fang" and not args.get("confirmed",false):
			return "这是任务材料，请确认后出售"
		var payout: int = unit_price(s,data,shop_id,item,false) * qty
		if npc.wealth < payout:
			return "商人灵石不足"
		if s.player.inventory.get(item,0) < qty:
			return "物品不足"
	return ""

func trade(s: Dictionary, data: Dictionary, args: Dictionary, buying: bool, inventory: RefCounted, operation: String) -> String:
	var error := trade_error(s,data,args,buying)
	if not error.is_empty():
		return error
	var shop_id: String = args.shop
	var item: String = args.item
	var qty: int = args.get("quantity",1)
	var npc: Dictionary = s.npcs[data.shops[shop_id].npc_id]
	var total := unit_price(s,data,shop_id,item,buying) * qty
	if buying:
		s.player.spirit_stones -= total
		npc.wealth += total
		s.stocks[shop_id][item] -= qty
		inventory.add(s.player,item,qty,data,operation)
	else:
		inventory.remove(s.player,item,qty)
		s.player.spirit_stones += total
		npc.wealth -= total
	return ""
