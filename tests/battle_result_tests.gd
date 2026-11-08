extends SceneTree
var failures:=0
var checks:=0
var gm: Node
var main: Control
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
func result_view() -> Control:return main.content.get_node("BattleResultOverlay")
func finish(kind: String) -> Dictionary:
	gm.new_game("结算验收","火")
	var payload: Dictionary=gm.operations.export_save()
	payload.state.player.location="area_qinglan_outskirts"
	gm.operations.battle.start(payload.state,"monster_gray_wolf",gm.operations.data,"result_fixture")
	if kind=="win":payload.state.battle.enemy.hp=1;payload.state.player.cultivation=100
	if kind=="lose":payload.state.player.hp=1;payload.state.battle.enemy.speed=999
	check(gm.operations.restore_save(payload).is_empty(),"battle fixture valid")
	check(gm.request("battle_action",{"kind":"attack"}).success,"real settlement action")
	var report: Dictionary=gm.operations.snapshot().battle_report
	check(report.result==kind,"expected result")
	main.page="战斗";main._refresh()
	return report
func run() -> void:
	gm=root.get_node("GameManager");gm.set_process(false);gm.new_game("结算验收","火")
	root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();root.add_child(main)
	var report: Dictionary=finish("win");await settle()
	var view:=result_view()
	check(view.field("ResultPanel").size==Vector2(960,620),"panel exact design size")
	check(view.field("ResultPanel").position.is_equal_approx(Vector2(240,75)),"panel centered")
	check((view.field("ResultPanel").size*view.field("ResultPanel").scale).is_equal_approx(Vector2(1440,930)),"result enlarged by fifty percent")
	check(view.field("GrowthList").get_child_count()==1,"real single growth")
	check(report.growth[0].gain==0 and gm.operations.snapshot().player.realm==1,"no invented cultivation or automatic promotion")
	check(report.drops.get("material_wolf_fang",0)>0,"actual wolf tooth awarded")
	check(main.content.has_node("BattlePage"),"battle remains background")
	root.get_texture().get_image().save_png("res://docs/screenshots/result_win.png")
	var before: Dictionary=gm.operations.export_save()
	view.field("DetailButton").pressed.emit();await settle()
	check(view.field("Details").visible and not view.field("Content").visible,"details replace content")
	check(view.field("ResultPanel").size==Vector2(960,620),"details keep panel size")
	view.field("DetailButton").pressed.emit()
	view.bind_data(report,gm.operations.data)
	check(before==gm.operations.export_save(),"reopen and details never award")
	var save=load("res://core/save_service.gd").new()
	var path: String=save.write(before,"user://test_saves")
	check(not path.is_empty() and gm.operations.restore_save(save.read(path)).is_empty(),"unconfirmed report disk roundtrip")
	await settle();view=result_view()
	check(not gm.operations.snapshot().battle_report.confirmed,"pending remains after load")
	view.field("ConfirmButton").pressed.emit();await settle()
	check(main.page=="地点场景" and gm.operations.snapshot().player.location==report.return_location,"confirm returns origin")
	check(gm.operations.snapshot().player.inventory==before.state.player.inventory and gm.operations.snapshot().player.spirit_stones==before.state.player.spirit_stones,"confirm no rewards")
	check(not gm.request("confirm_battle_result",{"id":report.id}).success,"duplicate confirm rejected")
	var confirmed: Dictionary=gm.operations.export_save()
	check(gm.operations.restore_save(confirmed).is_empty(),"confirmed load");await settle()
	check(not main.content.has_node("BattleResultOverlay"),"confirmed overlay stays closed")
	report=finish("lose");await settle();view=result_view()
	check(report.money==-12 and report.drops.is_empty(),"existing defeat penalty no loot")
	check(report.return_location=="town_qinglan","defeat safe return")
	root.get_texture().get_image().save_png("res://docs/screenshots/result_lose.png")
	view.field("ConfirmButton").pressed.emit();await settle()
	check(main.page=="地点场景" and gm.operations.snapshot().player.location=="town_qinglan","defeat confirmation safe location")
	report=finish("win");await settle();view=result_view()
	# UI-only fixtures; never passed into state or save service.
	var fixture: Dictionary=report.duplicate(true)
	fixture.growth=[]
	for i in range(3):fixture.growth.append({"name":"布局测试"+str(i+1),"realm":1,"type":"亲密成长" if i==2 else "修为","gain":i+1,"current":20,"target":100})
	fixture.drops={}
	for id in gm.operations.data.items:fixture.drops[id]=2
	view.bind_data(fixture,gm.operations.data);await settle()
	check(view.field("GrowthList").get_child_count()==3,"three growth recipients independent types")
	check(view.field("LootScroll").get_v_scroll_bar().max_value>view.field("LootScroll").size.y,"many loot scrolls internally")
	check(view.field("ResultPanel").size==Vector2(960,620),"many items fixed panel")
	root.get_texture().get_image().save_png("res://docs/screenshots/result_team_loot.png")
	fixture.growth=fixture.growth.slice(0,2)
	view.bind_data(fixture,gm.operations.data);await settle()
	check(view.field("GrowthList").get_child_count()==2,"only eligible recipients shown")
	fixture.drops={"material_wolf_fang":1};view.bind_data(fixture,gm.operations.data);await settle()
	check(view.field("LootGrid").get_child_count()==1,"one loot fixed grid")
	fixture.drops={};view.bind_data(fixture,gm.operations.data);await settle()
	check(view.field("Empty").visible,"empty loot message")
	for i in range(12):fixture.growth.append(fixture.growth[0].duplicate())
	view.bind_data(fixture,gm.operations.data);await settle()
	check(view.field("GrowthScroll").get_v_scroll_bar().max_value>view.field("GrowthScroll").size.y,"many growth rows internal scroll")
	root.size=Vector2i(1280,720);await settle()
	check(view.get_global_rect().encloses(view.field("ConfirmButton").get_global_rect()),"small window confirm visible")
	check(view.field("ResultPanel").scale.x==view.field("ResultPanel").scale.y,"uniform scaling")
	root.get_texture().get_image().save_png("res://docs/screenshots/result_1280.png")
	var bad: Dictionary=gm.operations.export_save();bad.state.battle_report.drops["missing_item"]=1
	check(not gm.operations.restore_save(bad).is_empty(),"bad loot reference rejected")
	var expired: Dictionary=before.duplicate(true);expired.state.player.age=expired.state.player.lifespan
	check(gm.operations.restore_save(expired).is_empty(),"expired report restores")
	check(gm.request("confirm_battle_result",{"id":expired.state.battle_report.id}).success,"expiry cannot trap result confirmation")
	var legacy: Dictionary=before.duplicate(true);legacy.state.erase("battle_report")
	check(gm.operations.restore_save(legacy).is_empty(),"legacy save compatible")
	print("RESULT UI: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
