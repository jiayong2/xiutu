extends RefCounted

const Auction = preload("res://gameplay/auction/auction_system.gd")
const Mental = preload("res://gameplay/character/mental_attributes.gd")
const PHASES := ["bidding","settled","finished"]

static func whole(value: Variant, minimum: int = 0, maximum: int = 1000000000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floorf(float(value)) and value >= minimum and value <= maximum

static func numbers(row: Dictionary, keys: Array, minimum: int, maximum: int) -> bool:
	for key in keys:
		if not whole(row.get(key),minimum,maximum):
			return false
	return true

static func config(data: Dictionary) -> String:
	var rules: Dictionary = data.auction_rules
	if not numbers(rules,["max_price","minimum_bps","quick_bps","log_limit","participant_limit","lot_limit"],1,100000000):
		return "拍卖规则数值无效"
	if rules.quick_bps < rules.minimum_bps or rules.quick_bps > 10000 or rules.log_limit > 500 or rules.participant_limit > 100 or rules.lot_limit > 100:
		return "拍卖规则范围无效"
	if not whole(rules.get("opening_bids"),1,3):
		return "拍卖开场出价轮数无效"
	if not numbers(rules,["interest_bonus_bps","disinterest_bps","anger_bonus_bps","cautious_exit_bps","realm_step_bps","pressure_contribution_bps","relationship_step_bps","warning_bps"],0,10000):
		return "拍卖心理或警告规则无效"
	for key in ["personalities","base_interaction_bps","relation"]:
		if not rules.get(key) is Dictionary:
			return "拍卖互动规则无效"
	if not numbers(rules.base_interaction_bps,["threat","provoke","persuade","bribe","pressure"],0,10000) or not numbers(rules.relation,Auction.ACTION_NAMES.keys()+["rivalry","yield"],-100,100):
		return "拍卖互动概率或关系无效"
	if not whole(rules.get("spirit_exit_headroom_bps"),0,10000) or not rules.get("counter_styles") is Array:
		return "拍卖神识交锋规则无效"
	for style in rules.counter_styles:
		if not rules.personalities.has(style):
			return "拍卖反向威压性格无效"
	for style in rules.personalities.values():
		if not style is Dictionary or not numbers(style,["value_bps","chance_bps"],1,20000) or not numbers(style,["resistance","grudge"],1,100):
			return "拍卖性格配置无效"
	for auction in data.auctions.values():
		if not definition(auction,data):
			return "拍卖会配置无效："+auction.id
	return ""

static func definition(d: Dictionary, data: Dictionary) -> bool:
	var rules: Dictionary = data.auction_rules
	for key in ["name","id","location","scale"]:
		if not d.get(key) is String or d[key].is_empty():
			return false
	for key in ["schedule","entry","host"]:
		if not d.get(key) is Dictionary:
			return false
	if not data.spirit_flow.locations.has(d.location) or not d.host.get("name") is String or not d.host.get("portrait","") is String:
		return false
	if not whole(d.schedule.get("first_day")) or not numbers(d.schedule,["period_days","duration_days"],1,100000) or d.schedule.duration_days > d.schedule.period_days:
		return false
	if not whole(d.entry.get("min_realm"),1,81) or not whole(d.entry.get("fee"),0,rules.max_price) or not whole(d.entry.get("box_fee"),-1,rules.max_price) or not d.entry.get("anonymous") is bool:
		return false
	if not whole(d.get("commission_bps"),0,10000) or not numbers(d,["round_limit","interaction_limit","warning_limit"],1,100) or not whole(d.get("bribe"),0,rules.max_price):
		return false
	if not d.get("lots") is Array or d.lots.is_empty() or d.lots.size() > rules.lot_limit or not d.get("participants") is Array or d.participants.size() > rules.participant_limit:
		return false
	var npc_ids := {}
	for npc in data.prototype.npcs:
		npc_ids[npc.id] = true
	var seen := {}
	for profile in d.participants:
		if not profile is Dictionary or not npc_ids.has(profile.get("id")) or seen.has(profile.id) or not rules.personalities.has(profile.get("style")) or not whole(profile.get("budget_bps"),1,10000) or not profile.get("interest") is Array:
			return false
		for interest in profile.interest:
			if not interest is String:
				return false
		seen[profile.id] = true
	for lot in d.lots:
		if not lot is Dictionary or not data.items.has(lot.get("item")) or not whole(lot.get("quantity"),1,99) or not numbers(lot,["start","value"],1,rules.max_price):
			return false
		if lot.quantity > data.items[lot.item].stack_limit:
			return false
		for key in ["quality","category","rarity"]:
			if not lot.get(key) is String or lot[key].is_empty():
				return false
	return true

static func state(s: Dictionary, data: Dictionary) -> String:
	for npc in s.npcs.values():
		if not npc is Dictionary or not npc.get("relations",{}) is Dictionary:
			return "人物关系记录无效"
		var attributes: Variant = npc.get("attributes",{})
		if not attributes is Dictionary:
			return "人物根基属性无效"
		for key in Mental.KEYS:
			if attributes.has(key) and not whole(attributes[key],0,1000000):
				return "人物识海或神魂无效"
		var stock: Variant = npc.get("inventory",{})
		var equipment: Variant = npc.get("equipment_instances",{})
		if not stock is Dictionary or not equipment is Dictionary:
			return "人物拍卖持有物无效"
		for id in stock:
			if not data.items.has(id) or data.equipment.has(id) or not whole(stock[id],1):
				return "人物拍卖物品无效"
		for id in equipment:
			if not id is String or id.is_empty() or not data.equipment.has(equipment[id]):
				return "人物拍卖装备无效"
	var sessions: Variant = s.get("auctions",{})
	if not sessions is Dictionary:
		return "拍卖存档结构无效"
	for id in sessions:
		if not data.auctions.has(id) or not _session(sessions[id],id,s,data):
			return "拍卖场次记录无效："+str(id)
	var accounts: Variant = s.get("auction_accounts",{})
	if not accounts is Dictionary:
		return "拍卖账目无效"
	for id in accounts:
		if not data.auctions.has(id) or not accounts[id] is Dictionary or not numbers(accounts[id],["fees","sales"],0,1000000000000):
			return "拍卖账目数值无效"
	return ""

static func _session(a: Variant, id: String, s: Dictionary, data: Dictionary) -> bool:
	var rules: Dictionary = data.auction_rules
	if not a is Dictionary or not a.get("terms") is Dictionary or a.terms.get("id") != id or not definition(a.terms,data):
		return false
	var d: Dictionary = a.terms
	if a.get("phase") not in PHASES or not numbers(a,["cycle","step","entry_paid"],0,1000000000):
		return false
	if not whole(a.get("index"),0,d.lots.size()-1) or not whole(a.get("round"),0,int(d.round_limit)+3) or not whole(a.get("calls"),0,3):
		return false
	if not whole(a.get("warnings"),0,d.warning_limit) or not whole(a.get("interactions"),0,d.interaction_limit) or not whole(a.get("price"),0,rules.max_price):
		return false
	for key in ["anonymous","box","withdrawn","restricted"]:
		if not a.get(key) is bool:
			return false
	if (a.anonymous and not d.entry.anonymous) or (a.box and d.entry.box_fee < 0) or a.entry_paid != d.entry.fee+(d.entry.box_fee if a.box else 0):
		return false
	if not a.get("actors") is Dictionary or not a.get("history") is Array or not a.get("log") is Array or a.log.size() > rules.log_limit:
		return false
	var roster := {}
	for profile in d.participants:
		roster[profile.id] = true
	for actor_id in a.actors:
		var actor: Variant = a.actors[actor_id]
		if not roster.has(actor_id) or not s.npcs.has(actor_id) or not actor is Dictionary or actor.get("mood") not in Auction.MOODS or not whole(actor.get("budget")) or not whole(actor.get("ceiling"),0,int(actor.budget)) or not actor.get("used") is Array:
			return false
		if not whole(actor.get("bids",0),0,d.round_limit):
			return false
		var used := {}
		for action in actor.used:
			if not Auction.ACTION_NAMES.has(action) or used.has(action):
				return false
			used[action] = true
	var leader: Variant = a.get("leader")
	if not leader is String or (leader != "" and leader != "player" and not a.actors.has(leader)):
		return false
	if (leader == "" and a.price != 0) or (leader != "" and a.price < d.lots[int(a.index)].start):
		return false
	var settled: bool = a.phase != "bidding"
	if (settled and a.calls != 3) or (not settled and a.calls >= 3) or (a.phase == "finished" and a.index != d.lots.size()-1):
		return false
	if a.history.size() != int(a.index)+int(settled):
		return false
	for index in range(a.history.size()):
		var receipt: Variant = a.history[index]
		var lot: Dictionary = d.lots[index]
		if not receipt is Dictionary or receipt.get("item") != lot.item or receipt.get("quantity") != lot.quantity or not numbers(receipt,["price","commission"],0,rules.max_price):
			return false
		var winner: Variant = receipt.get("winner")
		if not winner is String or (winner != "" and winner != "player" and not roster.has(winner)):
			return false
		if receipt.price < (0 if winner.is_empty() else lot.start) or (winner.is_empty() and receipt.price != 0) or receipt.commission != floori(receipt.price*d.commission_bps/10000.0):
			return false
	if settled and (a.history.back().winner != leader or a.history.back().price != a.price):
		return false
	for event in a.log:
		if not event is Dictionary or event.get("role") not in Auction.ROLES or not event.get("text") is String:
			return false
	return true
