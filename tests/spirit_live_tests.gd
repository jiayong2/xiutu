extends SceneTree

const Ops := preload("res://core/operation_service.gd")
const UNIT := 36000000
var checks := 0
var failures := 0
var data: Dictionary
var base: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(title)

func fresh() -> RefCounted:
	var op := Ops.new()
	op.configure(data)
	op.new_game("灵气正式验收","木",base,17)
	return op

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	data=gm.catalog.tables
	base=gm.repository.starting_character()
	var op := fresh()
	var before: Dictionary = op.export_save()
	var spirit: RefCounted = op.clock.spirit
	check(spirit.grade(before.state,"town_qinglan",data)=="灵气平常","Qinglan starts at its real grade")
	check(op.request("release_spirit_stones",{"count":1},"stone").success,"release a stone")
	var state: Dictionary = op.snapshot()
	check(state.player.spirit_stones==119 and state.spirit.pools.town_qinglan.stock-before.state.spirit.pools.town_qinglan.stock==50*UNIT
		and spirit.grade(state,"town_qinglan",data)=="灵气浓郁","one stone charges once and visibly changes concentration")
	check(not op.request("release_spirit_stones",{"count":1},"stone").success and op.snapshot()==state,"duplicate release rejected")
	check(not op.request("release_spirit_stones",{"count":2}).success and op.snapshot()==state,"overflow rejected without spending")
	var elevated: Dictionary = op.export_save()
	var fine := fresh()
	fine.restore_save(elevated)
	op.advance_realtime(24*3600)
	for minute in range(24*60):
		fine.advance_realtime(60)
	check(op.snapshot()==fine.snapshot(),"whole day and minute ticks match after a stone release")
	check(op.snapshot().spirit.pools.town_qinglan.stock<state.spirit.pools.town_qinglan.stock,"temporary concentration falls with time")

	op=fresh()
	check(op.request("travel",{"id":"town_yunxi"}).success and op.request("travel",{"id":"cave_qinglan"}).success
		and op.request("formation").success,"formation uses the existing Yunxi unlock and cave entry")
	before=op.export_save()
	var old_pool: Dictionary = before.state.spirit.pools.cave_qinglan
	var segment: Dictionary = op.clock.advance_seconds(op._state,3600,data,op.random,"none")
	var new_pool: Dictionary = op.snapshot().spirit.pools.cave_qinglan
	check(old_pool.stock+old_pool.surrounding==new_pool.stock+new_pool.surrounding and new_pool.stock>old_pool.stock,
		"formation transfers from the surrounding pool without creating energy")
	check(segment.ledger.processed==0,"non-cultivating time does not process spiritual energy")
	var preview: Dictionary=op.retreat_preview(0,0,1)
	before=op.export_save()
	check(op.request("retreat",{"days":1},"actual-retreat").success,"cave retreats on new model")
	var report: Dictionary=op.snapshot().retreat_report
	var ledger: Dictionary=report.spirit_ledger
	check(preview.after==report.after and preview.report.spirit_ledger==ledger,"preview and commit share a ledger")
	check(ledger.processed==ledger.loss+ledger.cultivation+ledger.nurture+ledger.returned and ledger.nurture>0,
		"all processed energy is allocated or returned exactly once")
	check(op.snapshot().spirit.pools.cave_qinglan.surrounding<before.state.spirit.pools.cave_qinglan.surrounding,
		"real retreat takes energy from the surrounding stock while the formation runs")

	var balances := {}
	for focus in ["refinement","balance","nurture"]:
		op=fresh()
		op.request("cultivation_focus",{"route":"qi","focus":focus})
		var amounts: Dictionary=op.advance_realtime(86400).ledger
		balances[focus]=amounts
	check(balances.refinement.processed==balances.nurture.processed and balances.refinement.cultivation>balances.balance.cultivation
		and balances.balance.cultivation>balances.nurture.cultivation and balances.refinement.nurture<balances.balance.nurture
		and balances.balance.nurture<balances.nurture.nurture,"inclinations reallocate the same energy")

	op=fresh()
	var old: Dictionary=op.export_save()
	old.state.erase("spirit")
	old.state.cultivation_fraction=432000000
	old.state.player.growth.body_fraction=216000000
	old.state.player.growth.nurture_fraction={"qi":3600000,"body":0}
	check(op.restore_save(old).is_empty(),"legacy fractions migrate")
	state=op.snapshot()
	check(state.spirit.progress.qi.cultivation==UNIT and state.spirit.progress.body.cultivation==UNIT/2
		and state.spirit.progress.qi.nurture==UNIT and not state.has("cultivation_fraction"),"old half points and nurture are preserved without a second balance")
	var invalid: Dictionary=op.export_save()
	invalid.state.spirit.pools.town_qinglan.stock=-1
	check(not op.restore_save(invalid).is_empty() and op.snapshot()==state,"negative reservoir fails atomically")
	var save_service=load("res://core/save_service.gd").new()
	var saved: Dictionary=op.export_save()
	var path: String=save_service.write(saved,"user://test_saves")
	check(not path.is_empty() and op.restore_save(save_service.read(path)).is_empty() and op.export_save()==saved,
		"actual disk save retains reservoir and partial energy")
	print("LIVE SPIRIT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
