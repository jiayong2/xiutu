extends SceneTree
var main: Control
var gm: Node
var n:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	n+=1
	if not ok:failures+=1;push_error(title)
	print("%s %s" % ["PASS" if ok else "FAIL",title])
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func view() -> Control:return main.content.get_node("CavePage")
func run() -> void:
	gm=root.get_node("GameManager");gm.set_process(false);gm.new_game("洞府验收","金")
	gm.request("travel",{"id":"cave_qinglan"})
	root.size=Vector2i(1920,1080);main=load("res://ui/main/main.tscn").instantiate();main.page="洞府";root.add_child(main);await settle()
	var page:=view()
	check(page.tab=="Overview","default overview")
	check(page.field("PlotGrid").get_child_count()==4,"preserves four real plots")
	var before: Dictionary=gm.operations.export_save()
	root.get_texture().get_image().save_png("res://docs/screenshots/cave_overview_1920x1080.png")
	page._tab("Retreat");page._duration(2,3,15)
	check(page.preview.days==825,"existing calendar combines years months days")
	check(before==gm.operations.export_save(),"previews preserve world random and resources")
	page._duration(0,0,0);check(page.field("StartRetreat").disabled,"zero duration disabled")
	page._duration(0,0,10)
	var expected: Dictionary=page.preview.duplicate()
	var hours: int=gm.operations.snapshot().hours
	page.field("StartRetreat").pressed.emit();await settle();page=view()
	check(gm.operations.snapshot().player.cultivation==expected.after,"actual cultivation matches preview")
	check(gm.operations.snapshot().hours==hours+240,"actual time advances once")
	check(page.field("StartRetreat").text=="开始闭关","required button text")
	for duration in [[0,0,1],[0,0,10],[0,1,0],[0,3,0],[1,0,0],[10,0,0]]:
		page._duration(duration[0],duration[1],duration[2]);check(page.preview.success,"shortcut duration valid")
	await settle();root.get_texture().get_image().save_png("res://docs/screenshots/cave_retreat_1920x1080.png")
	page._tab("Fields");check(page.field("SeedList").get_child(0).text.contains("没有"),"empty seed inventory")
	var saved: Dictionary=gm.operations.export_save();saved.state.player.inventory.seed_spirit_grass=2;saved.state.player.inventory.herb_spirit_grass=0
	gm.operations.restore_save(saved);await settle();page=view();page._tab("Fields")
	before=gm.operations.export_save();page._plot(1);page._seed("herb_spirit_grass")
	check(before==gm.operations.export_save(),"plot and seed selection read-only")
	page._field_action();await settle();page=view()
	check(gm.operations.snapshot().player.inventory.seed_spirit_grass==1,"plant consumes one seed")
	check(not gm.operations.snapshot().plots[1].is_empty(),"plant updates selected plot")
	check(page.field("FieldAction").disabled,"growing plot cannot harvest")
	root.get_texture().get_image().save_png("res://docs/screenshots/cave_fields_1920x1080.png")
	page._tab("Retreat");page._duration(0,0,3);page.field("StartRetreat").pressed.emit();await settle();page=view();page._tab("Fields")
	check(not page.field("FieldAction").disabled,"time matures planted crop")
	page._field_action();await settle();page=view()
	check(gm.operations.snapshot().player.inventory.herb_spirit_grass==3,"harvest real yield")
	check(gm.operations.snapshot().plots[1].is_empty(),"harvest clears plot")
	var result: Dictionary=gm.request("harvest",{"plot":1})
	check(not result.success and gm.operations.snapshot().player.inventory.herb_spirit_grass==3,"harvest cannot duplicate")
	page._tab("Alchemy");page._recipe("recipe_qi_gathering")
	check(not page.field("Craft").disabled,"existing recipe enabled with materials")
	page.field("Craft").pressed.emit();await settle();page=view()
	check(gm.operations.snapshot().player.inventory.pill_qi_gathering==1,"craft retains real output")
	root.get_texture().get_image().save_png("res://docs/screenshots/cave_alchemy_1920x1080.png")
	check(page.field("Craft").disabled,"craft unavailable after materials consumed")
	before=gm.operations.export_save()
	for tab in ["Overview","Retreat","Fields","Alchemy","WarehousePage"]:page._tab(tab)
	check(before==gm.operations.export_save(),"tabs read-only")
	check(gm.operations.restore_save(before).is_empty(),"save compatible");await settle();page=view()
	root.size=Vector2i(1280,720);page._tab("Retreat");await settle()
	check(page.get_global_rect().encloses(page.field("StartRetreat").get_global_rect()),"small window main action visible")
	root.get_texture().get_image().save_png("res://docs/screenshots/cave_retreat_1280x720.png")

	# Direct input commits without a shortcut; no state changes during edit.
	page._tab("Retreat");await settle();before=gm.operations.export_save()
	page.field("Days").get_line_edit().text="17"
	page.field("Days").apply();await settle()
	check(int(page.field("Days").value)==17,"direct numeric input")
	check(before==gm.operations.export_save(),"direct input does not advance time")
	page._duration(1,0,0);var year_preview: Dictionary=page.preview.duplicate()
	page.field("StartRetreat").pressed.emit();await settle();page=view()
	check(gm.operations.snapshot().player.age==year_preview.age,"actual year age matches TimeSystem preview")
	check(gm.operations.snapshot().player.cultivation==year_preview.after,"year retreat uses unchanged gain formula")
	page._tab("Fields")
	for i in range(20):page.field("PlotGrid").add_child(load("res://ui/cave/field_card.tscn").instantiate())
	await settle()
	check(page.field("PlotScroll").get_v_scroll_bar().max_value>page.field("PlotScroll").size.y,"future plot cards scroll inside panel")
	check(page.field("PlotGrid").columns==2,"plot grid retains two columns")
	check(page.get_global_rect().encloses(page.field("FieldAction").get_global_rect()),"plot overflow leaves management action visible")

	before=gm.operations.export_save()
	check(not gm.operations.request("retreat",{"days":-1}).success,"negative retreat rejected")
	check(gm.operations.snapshot()==before.state,"invalid retreat no state mutation")
	var probe: RefCounted=gm.operations.get_script().new();probe.configure(gm.operations.data);probe.restore_save(before)
	probe.request("travel",{"id":"town_qinglan"})
	check(not probe.retreat_preview(0,1,0).success,"outside cave preview explains restriction")
	check(not probe.request("retreat",{"days":30}).success,"outside cave retreat rejected")
	page.field("Back").pressed.emit();await settle();check(main.page=="地点场景","return location")
	print("CAVE UI: %d checks, %d failures" % [n,failures]);quit(0 if failures==0 else 1)
