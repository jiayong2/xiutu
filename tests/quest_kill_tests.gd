extends SceneTree

const BOARD = preload("res://gameplay/quest/town_announcements.gd")
const ID := "quest_test_kill_001"
const NOTICE := "notice_qinglan_test_kill_001"
const WOLF := "monster_gray_wolf"
const OUTSKIRTS := "area_qinglan_outskirts"
const TOWN := "town_qinglan"
var op: RefCounted
var failures := 0
var checks := 0
var day := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func act(action: String, args: Dictionary = {}, key: String = "") -> bool:
	return op.request(action,args,key).success

func runtime() -> Dictionary:
	return op.snapshot().quests.get(ID,{})

func progress() -> int:
	return int(runtime().get("objectives",{}).get("kill_wolves",{}).get("current_count",0))

func status() -> String:
	return BOARD.status(op.data.announcements[NOTICE],op.snapshot(),op.data,op.quests)

func accept() -> bool:
	return act("accept_announcement",{"id":NOTICE})

func claim(round_number: int = 1, key: String = "") -> bool:
	return act("claim_announcement",{"id":NOTICE,"round":round_number},key)

func travel(place: String) -> bool:
	return act("travel",{"id":place})

func encounter(index: int) -> bool:
	var weights: Array = op.data.rules.exploration_weights
	var forced := [0,0,0,0,0]
	forced[index] = 100
	op.data.rules.exploration_weights = forced
	var success := act("explore")
	op.data.rules.exploration_weights = weights
	return success

func win(index: int, key: String = "") -> bool:
	return encounter(index) and act("battle_action",{"kind":"attack"},key) and op.snapshot().battle_report.result == "win"

func reload() -> bool:
	var saves := preload("res://core/save_service.gd").new()
	var path := saves.write(op.export_save(),"user://test_saves/quest_kill")
	return not path.is_empty() and op.restore_save(saves.read(path)).is_empty()

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var gm := root.get_node("GameManager")
	gm.new_game("公告栏击杀验收","金")
	op = gm.operations
	day = int(op.clock.calendar_units(op.data).day_hours)*3600
	var wolf: Dictionary = op.data.monsters[WOLF].duplicate(true)
	for monster in [WOLF,"monster_mountain_boar"]:
		op.data.monsters[monster].hp = 1
		op.data.monsters[monster].speed = 1
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	root.add_child(main)
	main._navigate("公告栏")
	await process_frame
	await process_frame
	var board: Control = main.content.get_node("TownBoard")
	board._select(NOTICE)
	check(board.buttons.has(NOTICE) and status()=="AVAILABLE", "posting is available at Qinglan board")
	check(board.field("Description").text==op.data.quests[ID].description and "0/3" in board.field("Facts").text and "×25" in board.field("Rewards").text, "board detail binds objective and reward")
	board.field("Leave").pressed.emit()
	await process_frame
	check(runtime().is_empty() and reload(), "view and leave creates no task; pre-feature save shape loads")
	check(travel(OUTSKIRTS) and win(0) and runtime().is_empty(), "real win before acceptance creates no progress")
	check(travel(TOWN) and not act("accept",{"id":ID}), "generic acceptance cannot bypass board")
	act("confirm_battle_result",{"id":op.snapshot().battle_report.id})
	main._navigate("公告栏")
	await process_frame
	await process_frame
	board = main.content.get_node("TownBoard")
	board._select(NOTICE)
	board.field("Primary").pressed.emit()
	check(runtime().get("round")==1 and status()=="ACTIVE" and progress()==0, "board accepts round one with zero kills")
	check(not accept() and not claim(), "active duplicate acceptance and early delivery rejected")
	board.field("Primary").pressed.emit()
	await process_frame
	await process_frame
	var task: Control = main.content.get_node("TaskPage")
	check(task.selected_id==ID and ID in task.visible_ids() and "青岚镇公告栏" in task.field("Related").text and "直接探索" in task.field("Clue").text, "existing task list and detail show source and real clue")
	check(travel(OUTSKIRTS) and encounter(0) and progress()==0, "encounter alone adds nothing")
	var odds: float = op.data.rules.escape_chance
	op.data.rules.escape_chance = 1.0
	check(act("battle_action",{"kind":"escape"}) and op.snapshot().battle_report.result=="escape" and progress()==0, "escape adds nothing")
	op.data.rules.escape_chance = odds
	op.data.monsters[WOLF].attack = 99999
	op.data.monsters[WOLF].speed = 999
	check(encounter(0) and act("begin_battle") and op.snapshot().battle_report.result=="lose" and progress()==0, "defeat adds nothing")
	op.data.monsters[WOLF] = wolf.duplicate(true)
	op.data.monsters[WOLF].hp = 1
	op.data.monsters[WOLF].speed = 1
	check(travel(OUTSKIRTS) and win(1) and progress()==0, "other beast adds nothing")
	check(win(0,"wolf_win_one") and progress()==1 and op.snapshot().battle_report.drops.get("material_wolf_fang",0)>0 and reload() and progress()==1, "first kill, regular loot and 1/3 disk reload")
	check(not act("battle_action",{"kind":"attack"},"wolf_win_one") and progress()==1, "settlement retry leaves partial progress intact")
	var event_fixture: Dictionary = op.snapshot()
	event_fixture.battle = {"id":"batch_fixture"}
	event_fixture.pending_battle_result = "win"
	var batch := {"type":"KILL_ENEMY","target":WOLF,"location":OUTSKIRTS,"battle_id":"batch_fixture","count":1}
	op.quests.notify(event_fixture,batch,op.data)
	op.quests.notify(event_fixture,batch,op.data)
	check(event_fixture.quests[ID].objectives.kill_wolves.current_count==2, "same event ID cannot count twice below cap")
	event_fixture = op.snapshot()
	event_fixture.battle = {"id":"batch_fixture"}
	event_fixture.pending_battle_result = "win"
	batch.count = 2
	op.quests.notify(event_fixture,batch,op.data)
	check(event_fixture.quests[ID].objectives.kill_wolves.current_count==3, "batch event counts two defeated wolves")
	event_fixture = op.snapshot()
	event_fixture.battle = {"id":"batch_fixture"}
	event_fixture.pending_battle_result = "win"
	batch.count = 5
	op.quests.notify(event_fixture,batch,op.data)
	check(event_fixture.quests[ID].objectives.kill_wolves.current_count==3, "oversized batch is capped")
	check(win(0) and progress()==2 and reload() and progress()==2, "second kill and 2/3 disk reload")
	check(win(0) and progress()==3 and status()=="READY_TO_TURN_IN" and reload(), "third kill and ready-state disk reload")
	check(win(0) and progress()==3 and runtime().completed_count==0 and runtime().next_available_time==0, "cap and no automatic reward or cooldown")
	check(not claim() and not act("claim",{"id":ID}), "remote or generic delivery refused")
	check(travel(TOWN) and not act("claim",{"id":ID}), "generic claim cannot bypass board in town")
	act("confirm_battle_result",{"id":op.snapshot().battle_report.id})
	main._navigate("公告栏")
	await process_frame
	await process_frame
	board = main.content.get_node("TownBoard")
	board._select(NOTICE)
	var before: Dictionary = op.snapshot()
	check(board.field("Primary").text=="交付委托" and "3/3" in board.field("Facts").text, "existing primary button offers board hand-in")
	board.field("Primary").pressed.emit()
	var completed: Dictionary = runtime()
	check(op.snapshot().player.spirit_stones==before.player.spirit_stones+25 and completed.status=="COMPLETED" and completed.completed_count==1, "board claim gives exactly 25 and completes once")
	check(status()=="COOLDOWN" and completed.last_completed_time==op.clock.seconds(op.snapshot()) and completed.next_available_time==completed.last_completed_time+3*day, "cooldown starts at exact claim time")
	check(not board.buttons.has(NOTICE) and board.selected!=NOTICE, "claimed posting disappears immediately")
	check(not claim() and not accept() and reload() and runtime()==completed and not claim(), "duplicate claim and cooldown survive disk reload")
	board.sync(op.snapshot())
	board.sync(op.snapshot())
	check(runtime()==completed and not board.buttons.has(NOTICE), "board refresh keeps cooldown posting hidden")
	check(act("inn") and op.clock.seconds(op.snapshot())==completed.last_completed_time+day and not accept(), "inn advances one day but cannot reopen")
	check(travel("cave_qinglan"), "reach cave to retreat")
	var retreat_start: int = op.clock.seconds(op.snapshot())
	check(act("retreat",{"days":1}) and op.clock.seconds(op.snapshot())==retreat_start+day and status()=="COOLDOWN", "retreat advances one day but cannot reopen")
	check(travel(OUTSKIRTS) and win(0) and travel(TOWN) and runtime()==completed, "cooldown victory cannot change completed history")
	var remaining: int = completed.next_available_time-op.clock.seconds(op.snapshot())
	op.advance_realtime(remaining-1)
	check(status()=="COOLDOWN" and not accept(), "one second before exact cutoff remains closed")
	op.advance_realtime(1)
	check(status()=="AVAILABLE" and runtime()==completed, "normal world time opens exactly at deadline without auto-accept")
	board.sync(op.snapshot())
	check(board.buttons.has(NOTICE), "posting reappears after cooldown")
	check(accept() and runtime().round==2 and progress()==0 and runtime().completed_count==1, "round two resets progress and preserves completed count")
	check(travel(OUTSKIRTS) and win(0) and progress()==1 and reload() and runtime().round==2 and progress()==1, "second-round progress survives reload")
	check(win(0) and win(0) and travel(TOWN), "second round reaches hand-in")
	before = op.snapshot()
	check(not claim(1) and op.snapshot()==before, "stale prior-round claim cannot finish round two")
	check(claim(2,"round_two_claim") and runtime().completed_count==2 and op.snapshot().player.spirit_stones==before.player.spirit_stones+25, "round two rewards exactly once and accumulates history")
	check(status()=="COOLDOWN" and runtime().next_available_time==op.clock.seconds(op.snapshot())+3*day and not claim(2,"round_two_claim"), "round two starts a new three-day cooldown")
	var fixture: Dictionary = op.snapshot()
	var tables: Dictionary = op.data.duplicate(true)
	var definition: Dictionary = tables.quests[ID]
	fixture.quests.erase(ID)
	definition.objectives[0].target_id = "monster_mountain_boar"
	definition.objectives[0].required_count = 1
	definition.repeat_interval_days = 1
	check(BOARD.accept(NOTICE,fixture,tables,op.quests).is_empty(), "different kill target and count configured without code changes")
	fixture.battle = {"id":"reuse_fixture"}
	fixture.pending_battle_result = "win"
	op.quests.notify(fixture,{"type":"KILL_ENEMY","target":"monster_mountain_boar","location":OUTSKIRTS,"battle_id":"reuse_fixture","count":1},tables)
	fixture.battle = {}
	fixture.pending_battle_result = ""
	check(BOARD.claim(NOTICE,1,fixture,tables,op.quests,op.inventory).is_empty() and fixture.quests[ID].next_available_time==op.clock.seconds(fixture)+day, "configured target and alternate interval control settlement")
	definition.repeatable = false
	check(BOARD.status(tables.announcements[NOTICE],fixture,tables,op.quests)=="COMPLETED", "repeatable flag controls reopening independently")
	fixture.quests.erase(ID)
	definition.repeatable = true
	definition.objectives[0].objective_type = "VISIT_LOCATION"
	definition.objectives[0].target_id = OUTSKIRTS
	check(BOARD.accept(NOTICE,fixture,tables,op.quests).is_empty(), "board repeat accepts a different objective type")
	op.quests.notify(fixture,{"type":"VISIT_LOCATION","target":OUTSKIRTS,"location":OUTSKIRTS},tables)
	check(BOARD.claim(NOTICE,1,fixture,tables,op.quests,op.inventory).is_empty() and BOARD.status(tables.announcements[NOTICE],fixture,tables,op.quests)=="COOLDOWN", "non-kill objective shares the board cooldown")
	print("Kill quest: %d checks, %d failures" % [checks,failures])
	quit(failures)
