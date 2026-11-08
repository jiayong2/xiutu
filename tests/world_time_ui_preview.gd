extends SceneTree
var gm: Node
var main: Control
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("世界时间验收","木")
	root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="主界面";root.add_child(main);await settle()
	var home: Control=main.content.get_node("HomeView")
	check(home.field("WorldTime").visible and home.field("TimeRate")==null and home.field("PauseTime")==null and home.field("LocationAura").text.contains("吐纳"),"date and natural rate visible without speed badge or pause")
	var initial: int=gm.operations.clock.seconds(gm.operations.snapshot())
	# Genuine idle engine frames, with no submitted action.
	var timer:=create_timer(1.15);await timer.timeout;await settle()
	check(gm.operations.clock.seconds(gm.operations.snapshot())>initial,"real stationary engine advances clock")
	check(main.content.get_node("HomeView")==home,"live tick preserves page identity")
	gm.set_process(false);gm.advance_session(180)
	check(gm.operations.snapshot().player.cultivation>=1,"stationary automatic cultivation")
	var before: Dictionary=gm.operations.export_save()
	var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=true;main._unhandled_key_input(key)
	gm.advance_session(600)
	check(gm.operations.snapshot().hours==before.state.hours+10,"space and long inactivity cannot pause world")
	# NPC interaction, decision popup, and settings pause the same real clock.
	main.open_npc_interaction("npc_qin_shoushan");await settle();before=gm.operations.export_save();gm.advance_session(60)
	check(gm.operations.snapshot().hours==before.state.hours+1,"NPC UI keeps time running")
	main.npc_overlay.close();await settle()
	var confirmation:=ConfirmationDialog.new();main.add_child(confirmation);confirmation.dialog_text="测试决策";confirmation.popup_centered();await settle()
	before=gm.operations.export_save();gm.advance_session(60);check(gm.operations.snapshot().hours==before.state.hours+1,"confirmation window keeps time running")
	confirmation.hide();confirmation.queue_free();await settle()
	main._navigate("设置");await settle();before=gm.operations.export_save();gm.advance_session(60)
	check(gm.operations.snapshot().hours==before.state.hours+1,"settings keeps time running")
	main._navigate("背包");await settle();var inventory: Node=main.content.get_node("InventoryPage");gm.advance_session(60)
	check(gm.operations.clock.seconds(gm.operations.snapshot())>int(before.state.hours)*3600+int(before.state.time_seconds),"inventory keeps time running")
	check(main.content.get_node("InventoryPage")==inventory,"inventory selection not recreated by tick")
	main._navigate("地图");await settle()
	var map_page: Control=main.content.get_child(main.content.get_child_count()-1)
	var map_time_before: String=map_page.field("GameTime").text
	gm.advance_session(10)
	check(map_page.field("GameTime").text!=map_time_before,"map minute display updates in place")
	# Battle and its result phases block ambient time; explicit battle cost remains in battle rules.
	var fixture: Dictionary=gm.operations.export_save();gm.operations.battle.start(fixture.state,"monster_mountain_boar",gm.operations.data,"ui_time_battle");gm.operations.restore_save(fixture)
	main.page="战斗";main._refresh();await settle();before=gm.operations.export_save();gm.advance_session(60)
	check(gm.operations.snapshot().hours==before.state.hours+1 and gm.operations.snapshot().battle.turn==before.state.battle.turn,"battle time runs without extra turns")
	gm.new_game("闭关界面验收","木");gm.request("travel",{"id":"cave_qinglan"});main.page="洞府";main._refresh();await settle()
	var cave: Control=main.content.get_node("CavePage");cave._tab("Retreat");cave._duration(10,0,0);await settle()
	before=gm.operations.export_save();gm.advance_session(60);check(gm.operations.snapshot().hours==before.state.hours+1,"retreat decision clock continues")
	check(cave.preview.after==100 and cave.preview.elapsed==3600*24*3600,"ten years preview capped but full duration")
	check(cave.get_global_rect().encloses(cave.field("StartRetreat").get_global_rect()),"retreat action in bounds")
	root.get_texture().get_image().save_png("res://docs/screenshots/time_retreat_preview.png")
	cave.field("StartRetreat").pressed.emit();cave.field("StartRetreat").pressed.emit();await settle()
	check(main.retreat_overlay!=null and is_instance_valid(main.retreat_overlay),"real retreat opens report")
	var report: Control=main.retreat_overlay
	check(report.report.gain==100 and report.report.elapsed==3600*24*3600,"report exact ten year outcome")
	before=gm.operations.export_save();report.field("Tab_npc").pressed.emit();await settle()
	check(report.field("Details").text.contains("炼气"),"actual NPC changes shown")
	report.field("Tab_all").pressed.emit();await settle()
	gm.advance_session(60);check(gm.operations.snapshot().hours==before.state.hours+1 and gm.operations.snapshot().retreat_report==before.state.retreat_report,"report browsing keeps time running without repeating settlement")
	root.get_texture().get_image().save_png("res://docs/screenshots/time_retreat_report.png")
	root.size=Vector2i(1280,720);await settle()
	check(report.get_global_rect().encloses(report.field("Panel").get_global_rect()),"small window report fits")
	root.get_texture().get_image().save_png("res://docs/screenshots/time_report_small.png")
	root.size=Vector2i(1920,1080);await settle()
	report.field("Close").pressed.emit();await settle();check(main.content.has_node("CavePage"),"report returns original cave")
	# Target mode gets the exact end time, independently of old shortcut inputs.
	gm.new_game("目标闭关验收","木");gm.request("travel",{"id":"cave_qinglan"});main.page="洞府";main._refresh();await settle();cave=main.content.get_node("CavePage");cave._tab("Retreat")
	cave.field("TargetRetreat").button_pressed=true;await settle();check(cave.preview.success and cave.preview.elapsed<259200,"target mode preview")
	cave.field("StartRetreat").pressed.emit();await settle();check(gm.operations.snapshot().player.cultivation==100,"target executes to cap")
	main.retreat_overlay.close();await settle()
	gm.new_game("风险预告验收","木");gm.request("travel",{"id":"cave_qinglan"});main.cave_view_state={};main.page="洞府";main._refresh();await settle()
	cave=main.content.get_node("CavePage");cave._tab("Retreat");cave._duration(100,0,0);await settle()
	check(not cave.preview.warnings.is_empty(),"lifespan risk displayed before retreat")
	before=gm.operations.export_save();cave.field("StartRetreat").pressed.emit();await settle()
	var warnings: Array=cave.find_children("*","ConfirmationDialog",true,false)
	check(warnings.size()==1 and warnings[0].visible,"risky retreat requires explicit confirmation")
	check(gm.operations.export_save()==before,"risk prompt does not advance time")
	warnings[0].canceled.emit();await settle()
	check(not cave.retreat_busy and gm.operations.export_save()==before,"cancel risk keeps world unchanged")
	root.size=Vector2i(1280,720);main.message="";main.page="主界面";main._refresh();await settle();home=main.content.get_node("HomeView")
	check(home.get_global_rect().encloses(home.field("WorldTime").get_global_rect()),"small window date fits")
	root.get_texture().get_image().save_png("res://docs/screenshots/time_home_small.png")
	main.queue_free();await settle()
	print("WORLD TIME UI: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
