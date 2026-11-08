extends RefCounted

const Mental = preload("res://gameplay/character/mental_attributes.gd")
const Cultivation = preload("res://gameplay/cultivation/cultivation_system.gd")
const ACTIONS := ["auction_enter","auction_bid","auction_watch","auction_pass","auction_interact","auction_next"]
const MOODS := ["watch","hesitate","out","angry","deterred","quiet","guarded"]
const ROLES := ["normal","player","price","conflict","success","failure"]
const ACTION_NAMES := {"spirit":"神识威慑","threat":"言语威胁","provoke":"出言挑衅","persuade":"传音劝退","bribe":"传音收买","pressure":"以势压人"}
const HOSTILE := ["spirit","threat","provoke","pressure"]

static func session(s: Dictionary, id: String) -> Dictionary:
	return s.get("auctions",{}).get(id,{})

static func schedule(s: Dictionary, definition: Dictionary, data: Dictionary) -> Dictionary:
	var plan: Dictionary = definition.schedule
	var day := int(int(s.hours) / int(data.rules.hours_day))
	var elapsed := day-int(plan.first_day)
	var cycle := int(elapsed / int(plan.period_days)) if elapsed >= 0 else -1
	var open := elapsed >= 0 and elapsed % int(plan.period_days) < int(plan.duration_days)
	var next := int(plan.first_day)+(cycle+1)*int(plan.period_days)
	return {"cycle":cycle,"open":open,"next_day":next+1}

static func entry_reason(s: Dictionary, definition: Dictionary, data: Dictionary) -> String:
	if s.player.location != definition.location:
		return "请先前往举办地点"
	if not s.battle.is_empty():
		return "请先结束当前战斗"
	if s.player.age >= s.player.lifespan:
		return "角色寿元已尽"
	var a := session(s,definition.id)
	if not a.is_empty() and a.phase != "finished":
		return ""
	var window := schedule(s,definition,data)
	if not window.open:
		return "尚未开场，下次开放为世界第 %d 日" % window.next_day
	if not a.is_empty() and a.cycle == window.cycle:
		return "本期已结束，下次开放为世界第 %d 日" % window.next_day
	if s.player.realm < definition.entry.min_realm:
		return "修为未达到入场要求"
	if s.player.spirit_stones < definition.entry.fee:
		return "灵石不足以支付入场费"
	return ""

static func increment(price: int, basis_points: int) -> int:
	return maxi(1,ceili(price*basis_points/10000.0))

static func minimum(a: Dictionary, lot: Dictionary, rules: Dictionary) -> int:
	return int(lot.start) if a.leader.is_empty() else int(a.price)+increment(int(a.price),int(rules.minimum_bps))

static func proposed(a: Dictionary, lot: Dictionary, rules: Dictionary, mode: String, custom: int) -> int:
	if mode == "custom":
		return custom
	if mode == "quick" and not a.leader.is_empty():
		return int(a.price)+increment(int(a.price),int(rules.quick_bps))
	return minimum(a,lot,rules)

static func actor_name(s: Dictionary, a: Dictionary, id: String, public: bool = false) -> String:
	if id.is_empty():
		return "暂无出价"
	if id == "player":
		return "匿名修士" if a.anonymous and public else s.player.name
	return s.npcs[id].name

func execute(s: Dictionary, action: String, args: Dictionary, data: Dictionary, random: RefCounted, inventory: RefCounted) -> String:
	var id: Variant = args.get("id")
	if not id is String or not data.auctions.has(id):
		return "拍卖会不存在"
	var definition: Dictionary = data.auctions[id]
	if s.player.location != definition.location:
		return "请先前往举办地点"
	var rules: Dictionary = data.auction_rules
	if action == "auction_enter":
		return _enter(s,definition,args,data,random)
	var a := session(s,id)
	if a.is_empty() or a.phase == "finished":
		return "当前无进行中的拍卖"
	definition = a.terms
	if not args.get("cycle") is int or not args.get("step") is int or args.cycle != a.cycle or args.step != a.step:
		return "竞拍状态已更新，请重新确认操作"
	if action == "auction_next":
		if a.phase != "settled":
			return "当前拍品尚未结算"
		a.step += 1
		if a.index+1 == definition.lots.size():
			a.phase = "finished"
			_log(a,rules,"normal","本场拍卖结束。")
			return ""
		a.index += 1
		_open_lot(s,a,definition,data,random)
		return ""
	if a.phase != "bidding":
		return "该拍品已落槌"
	var lot: Dictionary = definition.lots[a.index]
	var force_call := int(a.round) >= int(definition.round_limit)
	match action:
		"auction_bid":
			var amount: Variant = args.get("amount")
			if a.withdrawn or a.leader == "player" or force_call or a.restricted:
				return "当前无法再次出价"
			if not amount is int or amount < minimum(a,lot,rules) or amount > int(rules.max_price):
				return "出价低于最低有效出价或超出上限"
			if s.player.spirit_stones < amount:
				return "可用灵石不足"
			var rival: String = a.leader
			_hold_bid(s,a,"player",amount)
			if not rival.is_empty():
				_change_relation(s,rival,s.player.id,int(rules.relation.rivalry))
			_log(a,rules,"player","%s出价 %d 灵石。" % [actor_name(s,a,"player",true),amount])
		"auction_pass":
			if a.withdrawn:
				return "你已退出当前拍品"
			a.withdrawn = true
			a.restricted = false
			if not a.leader.is_empty() and a.leader != "player":
				_change_relation(s,a.leader,s.player.id,int(rules.relation.yield))
			_log(a,rules,"player","你放弃继续争夺当前拍品。有效最高出价仍按原价结算。" if a.leader=="player" else "你放弃继续争夺当前拍品。")
		"auction_interact":
			var error := _interact(s,a,definition,args,data,random)
			if not error.is_empty():
				return error
		"auction_watch":
			a.restricted = false
		_:
			return "无效拍卖操作"
	a.step += 1
	while a.calls < 3:
		var npc_turn: bool = a.round < definition.round_limit
		a.round += 1
		if npc_turn and _npc_bid(s,a,definition,lot,rules,random):
			if not a.withdrawn:
				return ""
			continue
		if a.restricted:
			return ""
		a.calls += 1
		_log(a,rules,"normal","%s第 %d 次询价，还有道友出价吗？" % [definition.host.name,a.calls])
	return _settle(s,a,lot,definition,data,inventory)

func _enter(s: Dictionary, definition: Dictionary, args: Dictionary, data: Dictionary, random: RefCounted) -> String:
	var a := session(s,definition.id)
	if not a.is_empty() and a.phase != "finished":
		return "拍卖已经入场，可继续原场次"
	var error := entry_reason(s,definition,data)
	if not error.is_empty():
		return error
	var anonymous: Variant = args.get("anonymous",false)
	var box: Variant = args.get("box",false)
	if not anonymous is bool or not box is bool or (anonymous and not definition.entry.anonymous) or (box and definition.entry.box_fee < 0):
		return "该入场方式不可用"
	var fee := int(definition.entry.fee)+(int(definition.entry.box_fee) if box else 0)
	if s.player.spirit_stones < fee:
		return "灵石不足以支付入场费"
	s.player.spirit_stones -= fee
	_record_income(s,definition.id,fee,0)
	a = {"cycle":schedule(s,definition,data).cycle,"terms":definition.duplicate(true),"phase":"bidding","index":0,"step":0,"round":0,"calls":0,"leader":"","price":0,
		"withdrawn":false,"anonymous":anonymous,"box":box,"entry_paid":fee,"warnings":0,"interactions":0,"actors":{},"log":[],"history":[]}
	if not s.has("auctions"):
		s.auctions = {}
	s.auctions[definition.id] = a
	_log(a,data.auction_rules,"normal","%s开场。%s" % [definition.name,"你进入雅间。" if box else ""])
	_open_lot(s,a,definition,data,random)
	return ""

func _open_lot(s: Dictionary, a: Dictionary, definition: Dictionary, data: Dictionary, random: RefCounted) -> void:
	var lot: Dictionary = definition.lots[a.index]
	var rules: Dictionary = data.auction_rules
	a.phase = "bidding"
	a.round = 0
	a.calls = 0
	a.leader = ""
	a.price = 0
	a.withdrawn = false
	a.restricted = false
	a.interactions = 0
	a.actors = {}
	for profile in definition.participants:
		var npc: Dictionary = s.npcs[profile.id]
		if not npc.alive:
			continue
		var personality: Dictionary = rules.personalities[profile.style]
		var interest: bool = lot.category in profile.interest
		var realm_bonus := mini(1200,int(npc.realm)*60)
		var demand := int(personality.value_bps)+realm_bonus+(int(rules.interest_bonus_bps) if interest else -int(rules.disinterest_bps))
		var budget := floori(int(npc.wealth)*int(profile.budget_bps)/10000.0)
		var ceiling := mini(budget,floori(int(lot.value)*demand/10000.0))
		a.actors[profile.id] = {"mood":"watch" if interest else "quiet","ceiling":ceiling,"budget":budget,"used":[],"bids":0}
	_log(a,rules,"normal","%s介绍第 %d 件拍品「%s」×%d，起拍 %d 灵石。" % [definition.host.name,a.index+1,data.items[lot.item].name,lot.quantity,lot.start])
	for index in range(mini(int(rules.opening_bids),int(definition.round_limit))):
		if not _npc_bid(s,a,definition,lot,rules,random):
			break
		a.round += 1

func _npc_bid(s: Dictionary, a: Dictionary, definition: Dictionary, lot: Dictionary, rules: Dictionary, random: RefCounted) -> bool:
	var amount := minimum(a,lot,rules)
	var candidates: Dictionary = {}
	var total_weight := 0
	for profile in definition.participants:
		var id: String = profile.id
		if not a.actors.has(id) or id == a.leader:
			continue
		var actor: Dictionary = a.actors[id]
		var npc: Dictionary = s.npcs[id]
		if actor.mood in ["out","deterred"]:
			continue
		if not npc.alive or amount > mini(int(actor.ceiling),int(npc.wealth)) or amount > int(rules.max_price):
			actor.mood = "out"
			var reason := "已离席" if not npc.alive else "手头灵石不够" if amount > int(npc.wealth) else "认为再加价不划算"
			_log(a,rules,"normal","%s%s，退出竞价。" % [npc.name,reason])
			continue
		var style: Dictionary = rules.personalities[profile.style]
		var headroom := int(actor.ceiling)-amount
		var interest: bool = lot.category in profile.interest
		var rival: String = s.player.id if a.leader=="player" else a.leader
		var relation := _relation(npc,rival)
		var odds := int(style.chance_bps)+(900 if interest else -1900)-relation*int(rules.relationship_step_bps)
		if actor.mood == "angry":
			odds += int(rules.anger_bonus_bps)
		elif actor.mood == "hesitate":
			odds -= 1800
		if profile.style == "cautious" and amount*10000 >= int(actor.ceiling)*int(rules.cautious_exit_bps):
			odds -= 3200
		odds = clampi(odds,500,9800)
		if random.integer("auction",1,10000) > odds:
			if actor.mood == "watch":
				actor.mood = "hesitate"
				_log(a,rules,"normal","%s看着拍品，略显犹豫。" % npc.name)
			continue
		var relative_headroom := headroom*100/maxi(1,int(actor.ceiling))
		var weight := maxi(1,(odds/100+relative_headroom)/(1+int(actor.get("bids",0))))
		candidates[id] = weight
		total_weight += weight
	if candidates.is_empty():
		return false
	var ticket: int = random.integer("auction",1,total_weight)
	for id in candidates:
		ticket -= int(candidates[id])
		if ticket > 0:
			continue
		var actor: Dictionary = a.actors[id]
		actor.bids = int(actor.get("bids",0))+1
		if actor.mood == "quiet":
			actor.mood = "watch"
		_hold_bid(s,a,id,amount)
		_log(a,rules,"price","%s出价 %d 灵石。%s" % [s.npcs[id].name,amount,"“这件拍品，我还想争一争。”" if actor.mood=="angry" else ""])
		return true
	return false

func _hold_bid(s: Dictionary, a: Dictionary, bidder: String, amount: int) -> void:
	if not a.leader.is_empty():
		_wallet_delta(s,a.leader,int(a.price))
	_wallet_delta(s,bidder,-amount)
	a.leader = bidder
	a.price = amount
	a.calls = 0

func _wallet_delta(s: Dictionary, id: String, delta: int) -> void:
	if id == "player":
		s.player.spirit_stones += delta
	else:
		s.npcs[id].wealth += delta

func _settle(s: Dictionary, a: Dictionary, lot: Dictionary, definition: Dictionary, data: Dictionary, inventory: RefCounted) -> String:
	var winner: String = a.leader
	var fee := floori(int(a.price)*int(definition.commission_bps)/10000.0)
	if not winner.is_empty():
		var owner: Dictionary = s.player if winner=="player" else s.npcs[winner]
		if not owner.has("inventory"):
			owner.inventory = {}
		if not owner.has("equipment_instances"):
			owner.equipment_instances = {}
		var instance := "%s:%s:%d:%d" % [s.player.id,definition.id,a.cycle,a.index]
		var error: String = inventory.add(owner,lot.item,int(lot.quantity),data,instance)
		if not error.is_empty():
			return error
		_record_income(s,definition.id,fee,int(a.price)-fee)
		a.history.append({"winner":winner,"price":a.price,"commission":fee,"item":lot.item,"quantity":lot.quantity})
		_log(a,data.auction_rules,"success","落槌！%s以 %d 灵石拍下「%s」×%d。" % [actor_name(s,a,winner,true),a.price,data.items[lot.item].name,lot.quantity])
	else:
		a.history.append({"winner":"","price":0,"commission":0,"item":lot.item,"quantity":lot.quantity})
		_log(a,data.auction_rules,"normal","三次询价无人出价，「%s」流拍。" % data.items[lot.item].name)
	a.phase = "settled"
	s.last_result = a.log.back().text if s.last_result.is_empty() else s.last_result+"\n"+a.log.back().text
	return ""

func _record_income(s: Dictionary, id: String, fee: int, sale: int) -> void:
	if not s.has("auction_accounts"):
		s.auction_accounts = {}
	if not s.auction_accounts.has(id):
		s.auction_accounts[id] = {"fees":0,"sales":0}
	s.auction_accounts[id].fees += fee
	s.auction_accounts[id].sales += sale

static func interaction_reason(s: Dictionary, a: Dictionary, definition: Dictionary, kind: String, target: String) -> String:
	if not ACTION_NAMES.has(kind):
		return "无效互动"
	if a.phase != "bidding" or a.withdrawn or a.restricted or a.round >= definition.round_limit:
		return "当前无法干预竞拍"
	if a.interactions >= definition.interaction_limit or a.warnings >= definition.warning_limit:
		return "本轮互动已达上限，或拍卖行已禁止你干预"
	if not a.actors.has(target) or not s.npcs[target].alive or a.actors[target].mood in ["out","deterred"]:
		return "请先选择仍可参与竞价的修士"
	if kind in a.actors[target].used:
		return "本件拍品已对该目标使用此互动"
	if kind == "pressure" and s.sect.is_empty():
		return "加入宗门后可使用此互动"
	if kind == "bribe" and s.player.spirit_stones < definition.bribe:
		return "可用灵石不足"
	return ""

func _interact(s: Dictionary, a: Dictionary, definition: Dictionary, args: Dictionary, data: Dictionary, random: RefCounted) -> String:
	var kind: Variant = args.get("kind")
	var target: Variant = args.get("target")
	if not kind is String or not target is String:
		return "无效互动目标"
	var reason := interaction_reason(s,a,definition,kind,target)
	if not reason.is_empty():
		return reason
	var npc: Dictionary = s.npcs[target]
	var actor: Dictionary = a.actors[target]
	var rules: Dictionary = data.auction_rules
	var style: Dictionary
	var profile_id := ""
	var interested := false
	for profile in definition.participants:
		if profile.id == target:
			profile_id = profile.style
			style = rules.personalities[profile_id]
			interested = definition.lots[a.index].category in profile.interest
			break
	var odds := 0
	var mental: Dictionary = data.progression.mental
	var player_tier := Cultivation.tier_index(int(s.player.realm))
	var npc_tier := Cultivation.tier_index(int(npc.realm))
	if kind == "spirit":
		odds = roundi(Mental.chance(Mental.effective(s.player,data),Mental.effective(npc),player_tier-npc_tier,profile_id,actor.mood,mental)*100)
	else:
		odds = int(rules.base_interaction_bps[kind])-int(style.resistance)*90
		odds += clampi(int(s.player.realm)-int(npc.realm),-20,20)*int(rules.realm_step_bps)
		odds += _relation(npc,s.player.id)*int(rules.relationship_step_bps)
		if actor.mood == "hesitate":
			odds += 900
		elif actor.mood == "angry":
			odds -= 1100
		if kind == "pressure":
			odds += mini(2100,int(s.contribution)*int(rules.pressure_contribution_bps))
		odds = clampi(odds,600,9000)
	var roll: int = random.integer("auction",1,10000)
	var success := roll <= odds
	var detail := ""
	if kind == "spirit":
		if success:
			var next_price := minimum(a,definition.lots[a.index],rules)
			var funds := int(npc.wealth)+(int(a.price) if a.leader==target else 0)
			var ceiling := mini(funds,int(actor.ceiling))
			var close_to_cap := (ceiling-next_price)*10000 <= ceiling*int(rules.spirit_exit_headroom_bps)
			var exits := next_price > ceiling or (close_to_cap and (not interested or profile_id=="cautious"))
			actor.mood = "deterred" if exits else "hesitate"
			detail = "威压奏效，对方退出后续竞价。" if exits else "威压奏效，对方动摇，仍可能继续出价。"
			if exits and a.leader==target:
				detail += "有效最高价仍保留。"
		else:
			actor.mood = "guarded"
			detail = "对方抵住威压，提高了戒备。"
			if profile_id in rules.counter_styles and interested:
				var counter := Mental.chance(Mental.effective(npc),Mental.effective(s.player,data),npc_tier-player_tier,"","",mental)
				if random.integer("auction",1,10000) <= roundi(counter*100):
					a.restricted = true
					detail += "反向威压得手，你须先观望一轮。"
				else:
					detail += "对方反向释放神识，你稳住了心神。"
	elif success:
		if kind == "provoke":
			actor.mood = "angry"
			actor.ceiling = mini(int(actor.budget),int(actor.ceiling)+increment(int(actor.ceiling),int(rules.anger_bonus_bps)))
			detail = "对方动怒，出价意愿提高，仍受自身财力约束。"
		else:
			actor.mood = "deterred" if kind in HOSTILE else "out"
			detail = "对方退出后续竞价。"
			if a.leader == target:
				detail += "已给出的有效最高价仍然保留。"
		if kind == "bribe":
			s.player.spirit_stones -= int(definition.bribe)
			npc.wealth += int(definition.bribe)
	else:
		detail = "对方拒绝让步。"
	actor.used.append(kind)
	a.interactions += 1
	var relation_delta := int(rules.relation[kind])
	if relation_delta < 0:
		relation_delta *= int(style.grudge)
	elif not success:
		relation_delta = 0
	_change_relation(s,target,s.player.id,relation_delta)
	var text := "%s · %s：%s" % [ACTION_NAMES[kind],npc.name,detail]
	_log(a,rules,"success" if success and kind not in HOSTILE else "conflict" if kind in HOSTILE else "failure",text)
	if kind in HOSTILE and random.integer("auction",1,10000) <= int(rules.warning_bps)+(0 if success else 1400):
		a.warnings += 1
		var warning := "拍卖行发出警告。" if a.warnings < definition.warning_limit else "拍卖行禁止你在本场继续干预。"
		_log(a,rules,"failure",warning)
		text += warning
	s.last_result = text
	return ""

func _relation(npc: Dictionary, id: String) -> int:
	var value: Variant = npc.get("relations",{}).get(id,0)
	return clampi(int(value),-100,100) if value is int or value is float else 0

func _change_relation(s: Dictionary, npc_id: String, other: String, delta: int) -> void:
	if delta == 0:
		return
	var npc: Dictionary = s.npcs[npc_id]
	if not npc.has("relations"):
		npc.relations = {}
	npc.relations[other] = clampi(_relation(npc,other)+delta,-100,100)

func _log(a: Dictionary, rules: Dictionary, role: String, message: String) -> void:
	a.log.append({"role":role,"text":message})
	if a.log.size() > int(rules.log_limit):
		a.log.pop_front()
