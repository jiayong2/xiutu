extends SceneTree
const OPS=preload("res://core/operation_service.gd")
var data: Dictionary
var base: Dictionary
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func fresh() -> RefCounted:
	var op:=OPS.new();op.configure(data);op.new_game("时间验收","木",base,17);return op
func run() -> void:
	var gm: Node=root.get_node("GameManager");gm.set_process(false)
	data=gm.catalog.tables.duplicate(true);base=gm.repository.starting_character()
	var op:=fresh();var original: Dictionary=op.export_save()
	for i in range(24*60):op.advance_realtime(60)
	check(op.snapshot().hours==32 and op.snapshot().time_seconds==0,"idle time one day exact")
	check(op.snapshot().player.cultivation==10,"natural cultivation follows the calibrated spirit flow")
	var batch:=fresh();batch.restore_save(original);batch.advance_realtime(86400)
	check(op.snapshot()==batch.snapshot() and op.random.snapshot()==batch.random.snapshot(),"minute and batch natural identical state and RNG")
	op=fresh();check(op.request("practice",{"days":1}).success,"practice accepts")
	check(op.snapshot().player.cultivation==22 and op.snapshot().hours==32,"practice day follows spirit flow without double natural gain")
	op=fresh();op.request("travel",{"id":"cave_qinglan"})
	var before: Dictionary=op.export_save();var preview: Dictionary=op.retreat_preview(0,0,1)
	check(op.export_save()==before,"retreat preview pure including RNG")
	check(op.request("retreat",{"days":1},"retreat_once").success,"one day retreat")
	check(op.snapshot().player.cultivation==48 and op.snapshot().hours==32,"retreat day follows the cave spirit pool")
	check(preview.after==op.snapshot().player.cultivation and preview.elapsed==86400,"preview and execution match")
	before=op.export_save();check(not op.request("retreat",{"days":1},"retreat_once").success and op.export_save()==before,"retreat duplicate ID rejected")
	var started: int=Time.get_ticks_usec();check(op.request("retreat",{"days":3600}).success,"ten year retreat immediate")
	var elapsed: int=Time.get_ticks_usec()-started
	check(op.snapshot().player.cultivation==100 and op.snapshot().player.realm==1,"cap and no auto breakthrough")
	check(op.snapshot().hours==32+86400,"full selected duration advances despite cap")
	check(op.snapshot().npcs.npc_lin_zhaoxi.realm>before.state.npcs.npc_lin_zhaoxi.realm,"actual NPC growth")
	check(op.snapshot().retreat_report.groups.npc.size()>0 and op.snapshot().retreat_report.groups.economy.size()>0,"real world report categories")
	check(elapsed<1000000,"ten years under one second")
	op=fresh();op.request("travel",{"id":"cave_qinglan"});preview=op.retreat_preview(0,0,0,true)
	check(preview.success,"target preview")
	check(op.request("retreat_target",{}).success,"target retreat")
	check(op.snapshot().player.cultivation==100 and op.snapshot().retreat_report.elapsed==preview.elapsed,"exact target completion")
	check(op.snapshot().retreat_report.elapsed<3*86400,"target leaves before three days")
	var previous: Dictionary=op.snapshot();var last_second:=fresh();var saved: Dictionary=last_second.export_save();saved.state.player.location="cave_qinglan";last_second.restore_save(saved)
	last_second.clock.advance_seconds(saved.state,preview.elapsed-1,last_second.data,last_second.random,"retreat")
	check(saved.state.player.cultivation<100,"target minimal exact second")
	# Legacy overflow is preserved, not silently removed on the new cap rule.
	op=fresh();saved=op.export_save();saved.state.player.cultivation=450;op.restore_save(saved);op.advance_realtime(86400)
	check(op.snapshot().player.cultivation==450,"old overflow preserved")
	check(op.request("promote",{}).success and op.snapshot().player.realm==2,"manual one realm only")
	# Formation upkeep changes rate at the actual month boundary, not at the start/end of retreat.
	var large_data: Dictionary=data.duplicate(true);large_data.realms.qi_1.required=1000000
	var big:=OPS.new();big.configure(large_data);big.new_game("分段验收","木",base,17)
	saved=big.export_save();saved.state.player.location="cave_qinglan";saved.state.formation=true;saved.state.player.spirit_stones=10;big.restore_save(saved)
	var small:=OPS.new();small.configure(large_data);small.restore_save(saved)
	big.clock.advance(big._state,90*24,big.data,big.random,"retreat")
	for hour in range(90*24):small.clock.advance(small._state,1,small.data,small.random,"retreat")
	check(big.snapshot()==small.snapshot() and big.random.snapshot()==small.random.snapshot(),"segmented efficiency and world exactly match hourly path")
	check(not big.snapshot().formation and big.snapshot().player.spirit_stones==0,"upkeep disables without negative balance")
	# Lifespan stops an excessively long requested interval, with an actual interruption report.
	op=fresh();op.request("travel",{"id":"cave_qinglan"});op.request("retreat",{"days":1000000})
	check(op.snapshot().player.age==op.snapshot().player.lifespan,"lifespan boundary respected")
	check(op.snapshot().retreat_report.interrupted and op.snapshot().retreat_report.reason=="寿元已尽","real lifespan interruption")
	before=op.export_save();check(not op.request("practice",{"days":1}).success and op.export_save()==before,"no operations after death")
	op=fresh();saved=op.export_save();saved.state.player.location="cave_qinglan";saved.state.hours=(100-18)*360*24-1;saved.state.time_seconds=3599;saved.state.player.age=99;op.restore_save(saved)
	op.request("retreat_target",{})
	check(op.snapshot().player.cultivation<100 and op.snapshot().retreat_report.interrupted,"target interrupted when lifespan prevents completion")
	# Save/load retains sub-hour time and fractional cultivation. Missing legacy fields remain valid.
	op=fresh();op.advance_realtime(1234);saved=op.export_save();var loaded:=fresh();check(loaded.restore_save(saved).is_empty(),"fractional save valid")
	op.advance_realtime(4321);loaded.advance_realtime(4321);check(op.export_save()==loaded.export_save(),"save restore exact time and yield")
	saved=original.duplicate(true)
	for key in ["time_seconds","cultivation_fraction","time_paused","idle_pause_enabled"]:saved.state.erase(key)
	check(loaded.restore_save(saved).is_empty(),"legacy save compatible")
	loaded.advance_realtime(3600);check(loaded.snapshot().hours==9,"legacy clock resumes without offline catch-up")
	var save_service=load("res://core/save_service.gd").new()
	saved=op.export_save();var save_path: String=save_service.write(saved,"user://test_saves")
	check(not save_path.is_empty() and loaded.restore_save(save_service.read(save_path)).is_empty() and loaded.export_save()==saved,"actual disk save round trip exact")
	for bad_key in ["time_seconds","cultivation_fraction","time_paused"]:
		var invalid: Dictionary=saved.duplicate(true)
		invalid.state[bad_key]="invalid"
		var live_before: Dictionary=loaded.export_save()
		check(not loaded.restore_save(invalid).is_empty() and loaded.export_save()==live_before,"invalid time field rejected atomically "+bad_key)
	var invalid_rules: Dictionary=data.time_rules.duplicate(true);invalid_rules.game_seconds_per_real_second=0
	check(not op.clock.validate_rules(invalid_rules).is_empty(),"invalid time configuration rejected")
	op=fresh();op.request("accept",{"id":"quest_qinglan_001"});op.request("travel",{"id":"cave_qinglan"})
	saved=op.export_save();saved.state.hours=74*360*24;saved.state.player.age=92
	for npc in saved.state.npcs.values():npc.age=99
	op.restore_save(saved);var risky_preview: Dictionary=op.retreat_preview(2,0,0)
	check(risky_preview.success and not risky_preview.warnings.is_empty(),"real quest-giver death forecast warns before retreat")
	# The live clock has no manual, idle, battle or page pause gates.
	gm.new_game("持续时间验收","木");gm.advance_session(600)
	check(gm.operations.snapshot().hours==18,"ten idle minutes never pause world")
	var continuous: Dictionary=gm.operations.export_save();continuous.state.time_paused=true;continuous.state.idle_pause_enabled=true
	check(gm.operations.restore_save(continuous).is_empty(),"old paused save loads")
	check(not gm.operations.snapshot().has("time_paused") and not gm.operations.snapshot().has("idle_pause_enabled"),"old pause flags cleared")
	var before_hour: int=gm.operations.snapshot().hours;gm.advance_session(60)
	check(gm.operations.snapshot().hours==before_hour+1,"old pause flags cannot stop world")
	check(not gm.operations.request("time_pause").success and not gm.operations.request("idle_pause",{"enabled":true}).success,"removed pause operations unavailable")
	var combat: Dictionary=gm.operations.export_save();gm.operations.battle.start(combat.state,"monster_mountain_boar",gm.operations.data,"continuous_battle");gm.operations.restore_save(combat)
	var before_battle: Dictionary=gm.operations.snapshot().battle.duplicate(true);before_hour=gm.operations.snapshot().hours;gm.advance_session(60)
	check(gm.operations.snapshot().hours==before_hour+1 and gm.operations.snapshot().battle==before_battle,"time runs in battle without executing extra turns")
	print("WORLD TIME: %d checks, %d failures; ten years %d microseconds" % [checks,failures,elapsed]);quit(0 if failures==0 else 1)
