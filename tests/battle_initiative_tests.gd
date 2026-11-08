extends SceneTree

const Status = preload("res://gameplay/battle/battle_status.gd")
var checks := 0
var failures := 0
var gm: Node
var op: RefCounted

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fixture(speed: int, setup: Callable = Callable()) -> void:
	gm.new_game("先手验收","冰")
	var save: Dictionary = op.export_save()
	var s: Dictionary = save.state
	s.player.location = "area_qinglan_outskirts"
	op.battle.start(s,"monster_gray_wolf",op.data,"initiative_fixture")
	s.battle.enemy.speed = speed
	s.battle.enemy.hp = 500
	if setup.is_valid():
		setup.call(s)
	check(op.restore_save(save).is_empty(),"initiative fixture restores")

func actors(b: Dictionary) -> Array:
	return b.events.map(func(event: Dictionary): return [event.actor,int(event.turn)])

func run() -> void:
	gm = root.get_node("GameManager")
	op = gm.operations
	gm.set_process(false)
	fixture(30)
	var initial: Dictionary = op.snapshot()
	check(op.request("begin_battle").success,"fast encounter starts without a player attack")
	var opened: Dictionary = op.snapshot()
	check(actors(opened.battle)==[["enemy",1]] and opened.player.hp<initial.player.hp and opened.battle.enemy.hp==500,"only fast enemy acts at opening")
	check(op.battle.waiting_order(opened.battle)==["player"],"opening waits on player")
	check(not op.request("begin_battle").success and op.snapshot()==opened,"begin cannot replay initiative")
	check(op.restore_save(op.export_save()).is_empty() and op.snapshot()==opened,"mid-round restore does not replay the enemy")
	var before_invalid: Dictionary = op.random.snapshot()
	check(not op.request("battle_action",{"kind":"spell","id":"not_equipped"}).success and op.snapshot()==opened and op.random.snapshot()==before_invalid,"invalid input preserves pending player turn")
	check(op.request("battle_action",{"kind":"attack"}).success,"player can attack after the opener")
	var acted: Dictionary = op.snapshot()
	check(actors(acted.battle)==[["player",1],["enemy",2]],"player action comes before the next enemy attack")
	check(acted.battle.log_entries.filter(func(e: Dictionary): return e.type=="round").map(func(e: Dictionary): return int(e.turn))==[1,2],"each round has one log header")

	fixture(12)
	initial = op.snapshot()
	check(op.request("begin_battle").success and op.snapshot().battle.events.is_empty() and op.snapshot().player.hp==initial.player.hp,"speed tie waits for player without damage")
	check(op.request("battle_action",{"kind":"defend"}).success and actors(op.snapshot().battle)==[["player",1],["enemy",1]],"player-first enemy responds in the same round")

	fixture(14,func(s: Dictionary): s.player.spell_slots = ["skill_ice_seal"])
	check(op.request("begin_battle").success and actors(op.snapshot().battle)==[["enemy",1]],"fast enemy acts before ice seal")
	check(op.request("battle_action",{"kind":"spell","id":"skill_ice_seal"}).success,"ice seal cast")
	acted = op.snapshot()
	check(actors(acted.battle)==[["player",1]] and op.battle.waiting_order(acted.battle)==["player","enemy"],"slow changes next round without another enemy hit")
	check(op.request("battle_action",{"kind":"attack"}).success and actors(op.snapshot().battle)==[["player",2],["enemy",2]],"new player-first order applies next round")

	fixture(14,func(s: Dictionary):
		Status.apply(s.battle,"wind_step",op.data.spell_growth,20,1,{"effects":{"speed":.2}})
		s.battle.status.wind_step.turns = 1)
	check(op.request("begin_battle").success and op.snapshot().battle.events.is_empty(),"temporary speed buff starts player first")
	check(op.request("battle_action",{"kind":"attack"}).success and actors(op.snapshot().battle)==[["player",1],["enemy",1],["enemy",2]],"expired speed can place two enemy actions across different rounds")

	fixture(30,func(s: Dictionary): s.player.hp = 1)
	check(op.request("begin_battle").success and op.snapshot().battle.is_empty(),"lethal opener uses standard settlement")
	var report: Dictionary = op.snapshot().battle_report
	check(report.result=="lose" and actors(report.background.battle)==[["enemy",1]],"no player action after lethal opener")
	check(not op.request("begin_battle").success,"defeat cannot settle twice")

	fixture(30,func(s: Dictionary):
		s.battle.phase = "active"
		s.battle.turn = 6)
	check(op.request("begin_battle").success and actors(op.snapshot().battle)==[["enemy",7]],"legacy active save starts only its next round")

	fixture(30)
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	main.page = "战斗"
	root.add_child(main)
	await process_frame
	var view: Control = main.content.get_node("BattlePage")
	check(view.field("Attack").disabled,"prepare UI keeps attacks locked")
	var prepare_log: String = view.field("Log").text
	view.field("Begin").pressed.emit()
	check(view.playing and view.field("Attack").disabled and view.field("TurnOrder").current_id=="enemy","opening animation shows enemy with buttons locked")
	check(view.field("Log").text==prepare_log,"log does not show a later action before animation")
	view.skip_animations()
	await process_frame
	await process_frame
	check(not view.playing and not view.field("Attack").disabled and view.active_actor=="player" and view.field("TurnOrder").current_id=="player","skipping opening returns UI to player")
	check(view.field("TurnOrder").get_node("CurrentMarker").text.contains("等待指令"),"waiting marker distinguishes command input")
	check(view.field("Log").text.contains("普通攻击"),"finished action appears in log")
	view.field("Attack").pressed.emit()
	check(view.playing and view.field("Attack").disabled and view.field("TurnOrder").current_id=="player","player attack animation starts first")
	view.skip_animations()
	await process_frame
	await process_frame
	check(view.field("TurnOrder").current_id=="player" and not view.field("Attack").disabled,"next decision does not stop on monster")
	main.queue_free()
	print("BATTLE INITIATIVE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
