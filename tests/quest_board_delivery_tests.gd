extends SceneTree

const ID := "quest_test_collect_002"
const NOTICE := "notice_qinglan_test_collect_002"
const PHARMACY := "quest_test_collect_001"
const ITEM := "herb_spirit_grass"
const TOWN := "town_qinglan"
const OUTSKIRTS := "area_qinglan_outskirts"
const BOARD = preload("res://gameplay/quest/town_announcements.gd")
var op: RefCounted
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func act(action: String, args: Dictionary = {}, key: String = "") -> bool:
	return op.request(action,args,key).success

func trade(action: String, quantity: int) -> bool:
	return act(action,{"shop":"shop_qinglan_baicao","item":ITEM,"quantity":quantity})

func travel(place: String) -> bool:
	return act("travel",{"id":place})

func npc(option: String) -> bool:
	return act("npc_option",{"npc":"npc_shen_baicao","option":PHARMACY+":"+option})

func accept() -> bool:
	return act("accept_announcement",{"id":NOTICE})

func claim(round_number: int = 1, key: String = "") -> bool:
	return act("claim_announcement",{"id":NOTICE,"round":round_number},key)

func runtime() -> Dictionary:
	return op.snapshot().quests.get(ID,{})

func stock() -> int:
	return int(op.snapshot().player.inventory.get(ITEM,0))

func progress(id: String = ID) -> int:
	return op.quests.objective_count(op.snapshot(),id,op.data.quests[id].objectives[0])

func status() -> String:
	return BOARD.status(op.data.announcements[NOTICE],op.snapshot(),op.data,op.quests)

func reload() -> bool:
	var saves := preload("res://core/save_service.gd").new()
	var path := saves.write(op.export_save(),"user://test_saves/quest_board_delivery")
	return not path.is_empty() and op.restore_save(saves.read(path)).is_empty()

func gather_to(quantity: int) -> bool:
	if not travel(OUTSKIRTS):
		return false
	# Isolate the exploration outcome while keeping the real route and herb table.
	var weights: Array = op.data.rules.exploration_weights
	op.data.rules.exploration_weights = [0,0,0,25,0]
	for attempt in range(40):
		if stock() >= quantity or not act("explore",{"route":"stone_path"}):
			break
	op.data.rules.exploration_weights = weights
	return stock() >= quantity and travel(TOWN)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var gm := root.get_node("GameManager")
	gm.new_game("公告栏材料验收","金")
	op = gm.operations
	var initial: Dictionary = op.export_save()
	initial.state.player.spirit_stones = 500
	check(op.restore_save(initial).is_empty() and reload(), "save without the new task loads")
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	root.add_child(main)
	main._navigate("公告栏")
	await process_frame
	await process_frame
	var board: Control = main.content.get_node("TownBoard")
	board._select(NOTICE)
	check(board.buttons.has(NOTICE) and board.field("Description").text==op.data.quests[ID].description and "×50" in board.field("Rewards").text, "posting, detail and reward use existing board fields")
	var before: Dictionary = op.snapshot()
	board.field("Leave").pressed.emit()
	await process_frame
	check(op.snapshot()==before and runtime().is_empty(), "leaving without accepting does not create progress")
	main._navigate("公告栏")
	await process_frame
	await process_frame
	board = main.content.get_node("TownBoard")
	board._select(NOTICE)
	board.field("Primary").pressed.emit()
	check(runtime().round==1 and progress()==0 and "0/5" in board.field("Facts").text and not accept(), "accept into round one with 0/5 and reject duplicate")
	board.field("Primary").pressed.emit()
	await process_frame
	await process_frame
	var panel: Control = main.content.get_node("TaskPage")
	check(ID in panel.visible_ids() and panel.selected_id==ID and "青石山道" in panel.field("Clue").text and "青岚镇公告栏" in panel.field("Related").text, "existing task list shows task, verified clue and destination")
	check(trade("buy",2) and progress()==2 and reload() and progress()==2, "purchase and active disk reload show 2/5")
	check(trade("buy",3) and progress()==5 and status()=="READY_TO_TURN_IN" and reload(), "purchase reaches 5/5; ready state reloads")
	check(trade("sell",3) and progress()==2 and status()=="ACTIVE", "sale rolls readiness back to 2/5")
	check(gather_to(5) and progress()==5 and status()=="READY_TO_TURN_IN", "real Stone Path collection restores readiness")
	if stock()>5: trade("sell",stock()-5)
	check(npc("accept") and progress(PHARMACY)==3 and progress()==5, "both quests count the same preowned herbs")
	var stones: int = op.snapshot().player.spirit_stones
	check(npc("deliver") and stock()==2 and progress()==2 and runtime().status=="ACTIVE" and op.snapshot().player.spirit_stones==stones+30, "pharmacy reward independent; board progress immediately drops")
	before = op.snapshot()
	check(not claim() and op.snapshot()==before and not npc("accept"), "stale delivery cannot double-spend; pharmacy stays one-time")
	check(trade("buy",3) and progress()==5 and travel("cave_qinglan") and act("craft",{"id":"recipe_qi_gathering"}) and stock()==3 and progress()==3 and status()=="ACTIVE", "alchemy consumption rolls progress back")
	check(gather_to(8), "gather surplus for delivery")
	if stock()>8: trade("sell",stock()-8)
	check(stock()==8 and progress()==5 and status()=="READY_TO_TURN_IN", "eight herbs show 5/5")
	check(travel("town_yunxi") and not claim() and stock()==8 and travel(TOWN), "wrong town cannot submit or deduct herbs")
	check(not act("claim",{"id":ID}) and stock()==8, "generic claim cannot bypass the board")
	main._navigate("公告栏")
	await process_frame
	await process_frame
	board = main.content.get_node("TownBoard")
	board._select(NOTICE)
	check(board.field("Primary").text=="交付委托" and "5/5" in board.field("Facts").text, "board displays live 5/5 and hand-in")
	stones = op.snapshot().player.spirit_stones
	board.field("Primary").pressed.emit()
	var completed := runtime()
	var day: int = int(op.clock.calendar_units(op.data).day_hours)*3600
	check(stock()==3 and op.snapshot().player.spirit_stones==stones+50 and completed.status=="COMPLETED" and completed.completed_count==1, "round one deducts exactly five, keeps three and grants exactly 50")
	check(not board.buttons.has(NOTICE) and completed.last_completed_time==op.clock.seconds(op.snapshot()) and completed.next_available_time==completed.last_completed_time+3*day, "posting hides and three-day cooldown starts at reward")
	check(reload() and runtime()==completed and not claim() and not accept() and stock()==3, "completed cooldown and duplicate rejection persist on disk")
	check(travel("cave_qinglan"), "reach cave during cooldown")
	var retreat_start: int = op.clock.seconds(op.snapshot())
	check(act("retreat",{"days":1}) and op.clock.seconds(op.snapshot())==retreat_start+day and travel(TOWN), "retreat advances the shared clock")
	op.advance_realtime(completed.last_completed_time+2*day-op.clock.seconds(op.snapshot()))
	check(status()=="COOLDOWN" and not accept(), "two full game days cannot reopen")
	op.advance_realtime(day-1)
	check(status()=="COOLDOWN" and not accept(), "still hidden just before cutoff")
	op.advance_realtime(1)
	check(status()=="AVAILABLE" and runtime()==completed and stock()==3, "exact cutoff reopens without auto-accept or reward")
	check(accept() and runtime().round==2 and runtime().completed_count==1 and progress()==3 and reload() and progress()==3, "round two uses leftover herbs and persists")
	check(trade("buy",2) and progress()==5 and not claim(1), "round two can fill requirement; stale round rejected")
	stones = op.snapshot().player.spirit_stones
	check(claim(2,"board_delivery_round_two") and stock()==0 and op.snapshot().player.spirit_stones==stones+50 and runtime().completed_count==2, "round two deducts five and rewards exactly 50")
	check(status()=="COOLDOWN" and runtime().next_available_time==op.clock.seconds(op.snapshot())+3*day and not claim(2,"board_delivery_round_two"), "round two starts its own cooldown and request replay fails")
	var tables: Dictionary = op.data.duplicate(true)
	var fixture: Dictionary = op.snapshot()
	fixture.quests.erase(ID)
	var objective: Dictionary = tables.quests[ID].objectives[0]
	objective.target_id = "item_healing_powder"
	objective.required_count = 1
	check(preload("res://gameplay/quest/quest_validation.gd").new().validate(tables).is_empty() and BOARD.validate(tables).is_empty() and BOARD.accept(NOTICE,fixture,tables,op.quests).is_empty() and BOARD.claim(NOTICE,1,fixture,tables,op.quests,op.inventory).is_empty(), "alternate item and quantity work through configuration")
	print("Board delivery: %d checks, %d failures" % [checks,failures])
	quit(failures)
