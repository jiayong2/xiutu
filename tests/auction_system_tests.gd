extends SceneTree

const Auction = preload("res://gameplay/auction/auction_system.gd")
const Mental = preload("res://gameplay/character/mental_attributes.gd")
const Random = preload("res://core/random_service.gd")
var op: RefCounted
var id := "auction_yunxi"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func current() -> Dictionary:
	return Auction.session(op.snapshot(),id)

func submit(action: String, details: Dictionary = {}, token: String = "") -> Dictionary:
	var a := current()
	var args := details.duplicate()
	args.merge({"id":id,"cycle":a.get("cycle",-1),"step":a.get("step",-1)})
	return op.request(action,args,token)

func finish_lot() -> void:
	for index in range(40):
		if current().phase != "bidding":
			break
		var result := submit("auction_watch")
		if not result.success:
			check(false,result.message)
			break
	check(current().phase=="settled" and current().calls==3,"three calls settle in bounded rounds")

func run() -> void:
	var gm: Node = root.get_node("GameManager")
	check(gm.boot_ok and gm.new_game("验收修士","木").is_empty(),"boot and start")
	if not gm.boot_ok:
		quit(1)
		return
	gm.set_process(false)
	op = gm.operations
	var data: Dictionary = op.data
	var mental: Dictionary = data.progression.mental
	var rules: Dictionary = data.auction_rules
	var initial: Dictionary = op.export_save()
	check(Mental.effective(initial.state.player).spirit_sea == 10 and Mental.effective(initial.state.player).soul == 10,"player uses official growth attributes")
	check(initial.state.npcs.npc_qin_shoushan.attributes == {"spirit_sea":10,"soul":10},"NPC initial values generated from realm")
	var normal := {"spirit_sea":10,"soul":10}
	check(is_equal_approx(Mental.chance(normal,normal,0,"","",mental),50),"same realm and attributes give 50 percent")
	check(is_equal_approx(Mental.chance({"spirit_sea":20,"soul":30},normal,0,"","",mental),74),"weighted pressure and resistance")
	check(Mental.chance(normal,normal,3,"cautious","hesitate",mental)==80,"modifiers capped at +30")
	check(Mental.chance(normal,normal,-3,"competitive","guarded",mental)==20,"modifiers capped at -30")
	check(Mental.chance({"spirit_sea":200,"soul":200},normal,-5,"competitive","guarded",mental)==95,"attribute advantage survives realm gap")
	check(Mental.chance(normal,{"spirit_sea":200,"soul":200},5,"cautious","hesitate",mental)==5,"chance floor")
	var legacy := initial.duplicate(true)
	legacy.state.player.growth.attributes.erase("spirit_sea")
	legacy.state.player.growth.attributes.erase("soul")
	legacy.state.spirit.hour_attributes.erase("spirit_sea")
	legacy.state.spirit.hour_attributes.erase("soul")
	legacy.state.npcs.npc_qin_shoushan.erase("attributes")
	legacy.state.npcs.npc_liu_qinghe.attributes = {"spirit_sea":83,"soul":81}
	legacy.random.erase("auction")
	check(op.restore_save(legacy).is_empty(),"old save without auction data restores")
	check(op.snapshot().player.growth.attributes.soul==10 and op.snapshot().npcs.npc_liu_qinghe.attributes.soul==81,"migration fills missing values and preserves explicit NPC values")
	check(not submit("auction_enter").success,"venue rejects remote admission")
	check(op.request("travel",{"id":"town_yunxi"}).success,"normal travel reaches auction venue")
	var ready: Dictionary = op.export_save()
	ready.state.player.spirit_stones = 500
	check(op.restore_save(ready).is_empty(),"funded fixture")
	var outside: Dictionary = ready.state.duplicate(true)
	outside.hours = 4*24
	check(not Auction.schedule(outside,data.auctions[id],data).open and not Auction.entry_reason(outside,data.auctions[id],data).is_empty(),"schedule uses world calendar")
	check(Auction.proposed({"price":2400,"leader":"player"},{"start":2000},rules,"standard",0)==2640 and Auction.proposed({"price":2400,"leader":"player"},{"start":2000},rules,"quick",0)==2880,"10 and 20 percent")
	check(Auction.increment(21,1000)==3,"integer upward rounding")
	check(submit("auction_enter",{"anonymous":true}).success,"anonymous admission")
	var opened := current()
	check(opened.anonymous and not opened.leader.is_empty(),"NPC makes opening bid")
	check(not submit("auction_enter").success,"repeat entry cannot restart")
	check(op.restore_save(op.export_save()).is_empty(),"active auction round-trip")
	var before: Dictionary = op.snapshot()
	var rng_before: Dictionary = op.random.snapshot()
	check(not submit("auction_bid",{"amount":1}).success and not submit("auction_bid",{"amount":501}).success,"low and unaffordable bids rejected")
	check(op.snapshot()==before and op.random.snapshot()==rng_before,"invalid bids roll back all state and randomness")
	check(submit("auction_bid",{"amount":130},"player-auction-bid").success,"valid funded bid")
	var leading := current()
	check(leading.leader=="player" and op.snapshot().player.spirit_stones==370,"winning bid reserves price")
	check(op.snapshot().npcs[opened.leader].wealth==ready.state.npcs[opened.leader].wealth,"outbid NPC receives full refund")
	check(not submit("auction_bid",{"amount":150},"player-auction-bid").success,"same request rejected")
	check(not op.request("auction_watch",{"id":id,"cycle":opened.cycle,"step":opened.step}).success,"stale action rejected")
	var path: String = gm.saves.write(op.export_save(),"user://auction_test_saves")
	check(not path.is_empty() and op.restore_save(gm.saves.read(path)).is_empty(),"escrow survives disk save")
	if not path.is_empty():
		DirAccess.remove_absolute(path)
	finish_lot()
	var paid: Dictionary = op.snapshot()
	check(paid.player.inventory.pill_healing==1 and paid.player.spirit_stones==370,"player receives lot and pays exactly once")
	check(paid.auction_accounts[id].fees==6 and paid.auction_accounts[id].sales==124,"commission and proceeds reconcile")
	check(not submit("auction_watch").success and op.snapshot()==paid,"settled lot cannot be paid twice")
	check(submit("auction_next").success and current().index==1,"second lot opens")
	check(submit("auction_pass").success and current().withdrawn,"withdrawal applies to current lot")
	finish_lot()
	var sold := current()
	var winner: String = sold.history[1].winner
	check(not winner.is_empty() and winner!="player","NPC wins second lot")
	if not winner.is_empty() and winner!="player":
		check(op.snapshot().npcs[winner].inventory.material_spirit_iron==2,"NPC holds the actual won items")
	check(submit("auction_next").success and not current().withdrawn,"third lot resets withdrawal")
	finish_lot()
	var third: Dictionary = current().history[2]
	if third.winner not in ["","player"]:
		check("equip_iron_sword" in op.snapshot().npcs[third.winner].equipment_instances.values(),"NPC holds unique auction equipment")
	check(submit("auction_next").success and current().phase=="finished","final lot closes the event")
	check(not submit("auction_enter").success,"finished cycle cannot be farmed")
	check(op.restore_save(op.export_save()).is_empty(),"finished auction and NPC holdings load")
	_test_interactions(ready)
	_test_refund_and_bribe(ready)
	_test_reuse_and_growth(ready)
	print("AUCTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_interactions(ready: Dictionary) -> void:
	check(op.restore_save(ready).is_empty() and submit("auction_enter").success,"reset interaction test")
	var npc := "npc_yunxi_keeper"
	var start: Dictionary = op.export_save()
	check(submit("auction_interact",{"kind":"threat","target":npc}).success,"valid target interaction")
	check(op.snapshot().npcs[npc].relations[ready.state.player.id]<0,"threat changes existing relation")
	check(not submit("auction_interact",{"kind":"threat","target":npc}).success,"duplicate action rejected on same target")
	var saved: Dictionary = op.export_save()
	check(op.restore_save(saved).is_empty() and op.snapshot().npcs[npc].relations==saved.state.npcs[npc].relations,"relationship survives restore")
	check(not submit("auction_interact",{"kind":"pressure","target":npc}).success,"sect pressure requires membership")
	var countered := false
	var held := false
	var rng := Random.new()
	for seed in range(1,35):
		var fixture := start.duplicate(true)
		var a: Dictionary = fixture.state.auctions[id]
		var target_id := "npc_qin_shoushan"
		fixture.state.npcs[target_id].attributes = {"spirit_sea":100,"soul":100}
		a.actors[target_id].mood = "watch"
		a.actors[target_id].ceiling = a.actors[target_id].budget
		a.terms.participants[1].interest = ["丹药"]
		rng.initialize(seed)
		fixture.random.auction = rng.snapshot().auction
		if not op.restore_save(fixture).is_empty():
			continue
		var result := submit("auction_interact",{"kind":"spirit","target":target_id})
		if result.success and current().restricted:
			check(not submit("auction_bid",{"amount":200}).success,"successful counter blocks bid")
			check(submit("auction_watch").success and not current().restricted,"one watch clears auction restriction")
			check(not submit("auction_interact",{"kind":"spirit","target":target_id}).success,"spirit action is once per lot and target")
			countered = true
			break
	for seed in range(1,35):
		var fixture := start.duplicate(true)
		var a: Dictionary = fixture.state.auctions[id]
		fixture.state.npcs[npc].attributes = {"spirit_sea":0,"soul":0}
		a.actors[npc].mood = "hesitate"
		a.actors[npc].ceiling = a.actors[npc].budget
		rng.initialize(seed)
		fixture.random.auction = rng.snapshot().auction
		if not op.restore_save(fixture).is_empty():
			continue
		var result := submit("auction_interact",{"kind":"spirit","target":npc})
		if result.success and result.message.contains("仍可能继续出价") and current().actors[npc].mood=="hesitate":
			held = true
			break
	check(countered,"strong NPC counter-pressure exercised")
	check(held,"successful pressure can leave NPC bidding")

func _test_refund_and_bribe(ready: Dictionary) -> void:
	check(op.restore_save(ready).is_empty() and submit("auction_enter").success,"reset escrow and whisper test")
	var start: Dictionary = op.export_save()
	var rng := Random.new()
	var refunded := false
	var bribed := false
	for seed in range(1,35):
		var fixture := start.duplicate(true)
		var a: Dictionary = fixture.state.auctions[id]
		for actor in a.actors.values():
			actor.mood = "watch"
			actor.ceiling = actor.budget
		rng.initialize(seed)
		fixture.random.auction = rng.snapshot().auction
		if not op.restore_save(fixture).is_empty():
			continue
		var amount := Auction.minimum(a,a.terms.lots[0],op.data.auction_rules)
		if submit("auction_bid",{"amount":amount}).success and current().leader!="player":
			check(op.snapshot().player.spirit_stones==ready.state.player.spirit_stones,"NPC overbid returns player escrow immediately")
			check(current().price > amount,"response bid exceeds player price")
			refunded = true
			break
	for seed in range(1,35):
		var fixture := start.duplicate(true)
		var a: Dictionary = fixture.state.auctions[id]
		var target := "npc_yunxi_keeper"
		a.actors[target].mood = "watch"
		rng.initialize(seed)
		fixture.random.auction = rng.snapshot().auction
		if not op.restore_save(fixture).is_empty():
			continue
		var result := submit("auction_interact",{"kind":"bribe","target":target})
		if result.success and current().actors[target].mood=="out":
			var after: Dictionary = op.snapshot()
			var after_lot := current()
			var old_wealth := int(fixture.state.npcs[target].wealth)+(int(a.price) if a.leader==target else 0)
			var new_wealth := int(after.npcs[target].wealth)+(int(after_lot.price) if after_lot.leader==target else 0)
			check(new_wealth-old_wealth == a.terms.bribe and ready.state.player.spirit_stones-after.player.spirit_stones==a.terms.bribe,"bribe transfers actual stones only on acceptance")
			bribed = true
			break
	check(refunded and bribed,"player refund and whisper purchase both exercised")

func _test_reuse_and_growth(ready: Dictionary) -> void:
	check(op.restore_save(ready).is_empty(),"restore test baseline")
	var fixture: Dictionary = op.export_save()
	var npc: Dictionary = fixture.state.npcs.npc_lin_zhaoxi
	npc.cultivation = int(op.data.realms["qi_%d" % int(npc.realm)].required)-1
	var month_start: int = op.clock.calendar_units(op.data).month_days*24
	fixture.state.hours = month_start-1
	check(op.restore_save(fixture).is_empty(),"monthly fixture")
	var before_npc: Dictionary = op.snapshot().npcs.npc_lin_zhaoxi.attributes
	op.advance_realtime(3600)
	check(op.snapshot().npcs.npc_lin_zhaoxi.attributes.spirit_sea==before_npc.spirit_sea+5,"NPC breakthrough increases persisted spirit sea")
	check(op.restore_save(ready).is_empty(),"restore before long cultivation")
	var growth_before: Dictionary = op.snapshot().player.growth.attributes
	op.advance_realtime(40*24*3600)
	var grown: Dictionary = op.snapshot().player.growth.attributes
	check(grown.spirit_sea > growth_before.spirit_sea and grown.soul > growth_before.soul and grown.spirit_sea<=20,"existing cultivation grows both attributes within cap")
	check(op.restore_save(ready).is_empty(),"restore before config variant")
	var alternate: Dictionary = op.data.auctions[id].duplicate(true)
	alternate.id = "auction_fixture"
	alternate.name = "验收坊市"
	alternate.scale = "大型"
	alternate.entry.box_fee = 10
	alternate.participants = []
	op.data.auctions[alternate.id] = alternate
	id = alternate.id
	check(submit("auction_enter",{"box":true}).success and current().box and op.snapshot().player.spirit_stones==490,"second venue uses same engine and configured box")
	finish_lot()
	check(current().history[0].winner=="" and current().history[0].price==0,"empty room lot passes with no payment")
