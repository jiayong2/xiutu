extends SceneTree

const Auction = preload("res://gameplay/auction/auction_system.gd")
const VENUE := "auction_yunxi"
const SEEDS := 40

func _initialize() -> void:
	call_deferred("run")

func command(op: RefCounted, action: String, args: Dictionary = {}) -> Dictionary:
	var current := Auction.session(op.snapshot(),VENUE)
	args.merge({"id":VENUE,"cycle":current.get("cycle",-1),"step":current.get("step",-1)})
	return op.request(action,args)

func bidders(a: Dictionary, state: Dictionary, offset: int = 0) -> int:
	var count := 0
	for npc in state.npcs.values():
		for event in a.log.slice(offset):
			if event.role=="price" and event.text.begins_with(str(npc.name)+"出价 "):
				count += 1
				break
	return count

func run() -> void:
	var gm: Node = root.get_node("GameManager")
	var op: RefCounted = gm.operations
	var opening_multiple := 0
	var round_multiple := 0
	var pass_settled := 0
	var bid_settled := 0
	var watch_settled := 0
	var failures := 0
	for seed in range(1,SEEDS+1):
		op.new_game("拍卖模拟","金",gm.repository.starting_character(),seed)
		if not op.request("travel",{"id":"town_yunxi"}).success or not command(op,"auction_enter").success:
			failures += 1
			continue
		var state: Dictionary = op.snapshot()
		var a := Auction.session(state,VENUE)
		opening_multiple += int(bidders(a,state) >= 2)
		var opening_lines: int = a.log.size()
		for index in range(5):
			a = Auction.session(op.snapshot(),VENUE)
			var price := Auction.minimum(a,a.terms.lots[0],op.data.auction_rules)
			if a.phase!="bidding" or a.leader=="player" or price > op.snapshot().player.spirit_stones:
				break
			if not command(op,"auction_bid",{"amount":price}).success:
				failures += 1
				break
		state = op.snapshot()
		a = Auction.session(state,VENUE)
		round_multiple += int(bidders(a,state,opening_lines) >= 2)
		op.new_game("拍卖模拟","金",gm.repository.starting_character(),seed)
		op.request("travel",{"id":"town_yunxi"})
		command(op,"auction_enter")
		if not command(op,"auction_pass").success:
			failures += 1
		a = Auction.session(op.snapshot(),VENUE)
		pass_settled += int(a.phase=="settled")
		# This bid is affordable for a regular starting player and above the first lot's normal NPC caps.
		op.new_game("拍卖模拟","金",gm.repository.starting_character(),seed)
		op.request("travel",{"id":"town_yunxi"})
		command(op,"auction_enter")
		if not command(op,"auction_bid",{"amount":120}).success:
			failures += 1
			continue
		a = Auction.session(op.snapshot(),VENUE)
		bid_settled += int(a.phase=="settled" and a.calls==3 and a.history.size()==1)
		# Emulate a previous-version save with a player bid already held after the first call.
		op.new_game("拍卖模拟","金",gm.repository.starting_character(),seed)
		op.request("travel",{"id":"town_yunxi"})
		command(op,"auction_enter")
		var old: Dictionary = op.export_save()
		a = Auction.session(old.state,VENUE)
		if not a.leader.is_empty():
			old.state.npcs[a.leader].wealth += a.price
		old.state.player.spirit_stones -= 120
		a.leader = "player"
		a.price = 120
		a.calls = 1
		a.log.append({"role":"normal","text":"云溪拍卖师第 1 次询价，还有道友出价吗？"})
		for actor in a.actors.values():
			actor.erase("bids")
		if not op.restore_save(old).is_empty() or not command(op,"auction_watch").success:
			failures += 1
		a = Auction.session(op.snapshot(),VENUE)
		var all_calls: bool = a.log.any(func(event: Dictionary): return "第 2 次询价" in event.text) and a.log.any(func(event: Dictionary): return "第 3 次询价" in event.text)
		watch_settled += int(a.phase=="settled" and a.calls==3 and a.history.size()==1 and all_calls and op.snapshot().player.inventory.get("pill_healing",0)==1)
	print("AUCTION SIMULATION %d seeds: multiple opening=%d, multiple NPC bidders after opening=%d, one pass closes=%d, uncontested bid closes=%d, old first call closes by one watch=%d, errors=%d" %
		[SEEDS,opening_multiple,round_multiple,pass_settled,bid_settled,watch_settled,failures])
	var passed := failures==0 and opening_multiple>=36 and round_multiple>=30 and pass_settled==SEEDS and bid_settled==SEEDS and watch_settled==SEEDS
	quit(0 if passed else 1)
