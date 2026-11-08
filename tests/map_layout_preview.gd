extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(6):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
func run() -> void:
	var gm: Node=root.get_node("GameManager");gm.set_process(false);gm.new_game("地图布局验收","金")
	var main=load("res://ui/main/main.tscn").instantiate();main.page="地图";root.add_child(main)
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await settle()
		var page: Control=main.content.get_node("WorldMap")
		check(page.field("Body").get_child_count()==3,"three columns")
		check(page.field("Header").get_global_rect().encloses(page.field("GameTime").get_global_rect()),"time in header")
		check(page.field("GameTime").text.contains("08:00"),"actual game time")
		for key in ["IndexPanel","CenterPanel","RightPanel","Footer","Enter","Back"]:
			check(page.get_global_rect().encloses(page.field(key).get_global_rect()),"visible "+key)
		var before: Dictionary=gm.operations.export_save()
		for id in page.places:
			page.field("Index_"+id).pressed.emit();await settle()
			check(page.selected_place==id and page.field("PlaceName").text==page.places[id],"index detail sync "+id)
			check(page.field("Canvas").get_global_rect().encloses(page.field(id).get_global_rect()),"node visible "+id)
			var left: StyleBoxFlat=page.field("Index_"+id).get_theme_stylebox("normal")
			var node: StyleBoxFlat=page.field(id).get_theme_stylebox("normal")
			check(left.bg_color==node.bg_color,"matching selection "+id)
		var gate: Control=page.field("sect_qingyue_gate")
		for id in page.PLACES:
			check(not gate.get_global_rect().intersects(page.field(id).get_global_rect()),"gate does not overlap "+id)
		check(before==gm.operations.export_save(),"all selections read only")
		page.field("town_qinglan").pressed.emit();await settle()
		check(page.field("Enter").text=="进入当前地点","current enter label")
		if DisplayServer.get_name()!="headless":
			root.get_texture().get_image().save_png("res://docs/screenshots/map_index_%d.png" % resolution.x)
	var page: Control=main.content.get_node("WorldMap")
	page.field("Back").pressed.emit();await settle()
	check(main.content.has_node("HomeView") and gm.operations.snapshot().player.location=="town_qinglan","back actual current location")
	main._navigate("地图");await settle();page=main.content.get_node("WorldMap")
	page.field("Index_town_yunxi").pressed.emit();await settle()
	check(page.field("TravelCondition").text.contains("1日"),"existing travel duration")
	var hour: int=gm.operations.snapshot().hours
	page.field("Enter").pressed.emit();await settle()
	check(gm.operations.snapshot().hours==hour+24 and gm.operations.snapshot().player.location=="town_yunxi","travel existing settlement")
	check(main.content.has_node("HomeView"),"travel enters shared location main")
	main._navigate("地图");await settle();page=main.content.get_node("WorldMap")
	check(page.field("GameTime").text.contains("2日"),"date refresh after travel")
	page._select_place("area_qinglan_outskirts")
	check(page.field("Environment").text.contains("野外"),"wild environment actual rule")
	check(page.field("Aura").text==gm.operations.clock.spirit.grade(gm.operations.snapshot(),page.selected_place,gm.operations.data),"map shows the current reservoir grade")
	check(gm.operations.restore_save(gm.operations.export_save()).is_empty(),"save compatible")
	await settle();page=main.content.get_node("WorldMap")
	var gate_id := "sect_qingyue_gate"
	page.field("Index_"+gate_id).pressed.emit()
	check(page.field("Enter").disabled and page.field("UnlockStatus").text.contains("炼气"),"map enforces gate realm requirement")
	var eligible: Dictionary=gm.operations.export_save()
	eligible.state.player.realm=2
	gm.operations.restore_save(eligible)
	await settle();page=main.content.get_node("WorldMap")
	check(page.selected_place==gate_id and not page.field("Enter").disabled,"map refresh enables eligible gate travel")
	hour=gm.operations.snapshot().hours
	page.field("Enter").pressed.emit();await settle()
	check(gm.operations.snapshot().player.location==gate_id and gm.operations.snapshot().hours==hour+36,"map travel uses same gate route")
	check(main.content.has_node("HomeView"),"gate arrival opens actual location home")
	print("MAP LAYOUT: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
