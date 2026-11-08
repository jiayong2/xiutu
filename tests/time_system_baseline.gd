extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func run() -> void:
	var gm: Node=root.get_node("GameManager");gm.new_game("时间基线验收","木")
	var original: Dictionary=gm.operations.export_save()
	var clock=load("res://core/time_system.gd").new()
	var random_a=load("res://core/random_service.gd").new();random_a.initialize(1);random_a.restore(original.random)
	var random_b=load("res://core/random_service.gd").new();random_b.initialize(1);random_b.restore(original.random)
	var batch: Dictionary=original.state.duplicate(true)
	var monthly: Dictionary=original.state.duplicate(true)
	var started: int=Time.get_ticks_usec()
	clock.advance(batch,360*10*24,gm.operations.data,random_a)
	var elapsed_us: int=Time.get_ticks_usec()-started
	for month in range(120):clock.advance(monthly,720,gm.operations.data,random_b)
	check(batch==monthly,"10 years batch equals 120 monthly settlements")
	check(random_a.snapshot()==random_b.snapshot(),"world random streams remain identical")
	check(batch.hours==original.state.hours+86400,"10 year calendar exact")
	check(batch.player.age==original.state.player.age+10,"player age exact")
	check(batch.npcs.npc_qin_shoushan.age==35,"NPC age advances through real month rules")
	check(batch.npcs.npc_qin_shoushan.realm == 0 and batch.npcs.npc_qin_shoushan.cultivation == 0,"mortal NPC does not cultivate")
	check(batch.npcs.npc_lin_zhaoxi.realm>original.state.npcs.npc_lin_zhaoxi.realm,"NPC genuinely grows")
	check(batch.prices.town_qinglan>=9000 and batch.prices.town_qinglan<=11000,"existing economy bounded")
	check(gm.operations.export_save()==original,"audit never changes live state")
	print("TIME BASELINE: %d checks, %d failures; 10-year settlement %d microseconds" % [checks,failures,elapsed_us])
	quit(0 if failures==0 else 1)
