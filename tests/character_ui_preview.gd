extends SceneTree
var main: Control
var gm: Node
var failures:=0
var count:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	count+=1
	if not ok:failures+=1;push_error(title)
	print("%s %s" % ["PASS" if ok else "FAIL",title])
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func view() -> Control:return main.content.get_node("CharacterPage")
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("无名散修","金");root.size=Vector2i(1920,1080)
	# Compare page actions against a fixed clock while preserving normal game timing.
	gm.set_process(false)
	main=load("res://ui/main/main.tscn").instantiate();main.page="角色";root.add_child(main);await settle()
	var page:=view()
	check(page.tab=="info" and page.field("InfoPage").visible,"default information")
	check(page.field("CharacterName").text=="无名散修","real name")
	check(page.field("Aptitude4").text=="识海 10 / 20" and page.field("Aptitude5").text=="神魂 10 / 20","mental attributes shown from real growth")
	check(page.field("Health").value==120 and page.field("Mana").value==40,"real resource bars")
	check(page.field("Radar").values==[20,20,20,20,20,20],"radar reads real starting aptitude values")
	check(page.field("TalentGrid").get_child(0).text=="暂无先天天赋" and page.field("StatusGrid").get_child(0).text=="暂无后天气运","separate empty states")
	check(page.field("CombatGrid").get_child(0).tooltip_text.contains("青木剑"),"real equipment tooltip source")
	check(page.field("CombatGrid").get_child(0).tooltip_text.contains("24"),"final attack tooltip")
	await settle();root.get_texture().get_image().save_png("res://docs/screenshots/character_info_1920x1080.png")
	var before: Dictionary=gm.operations.export_save()
	page._tab("equipment");page._category("weapon",true)
	check(page.category=="weapon" and page.selected=="starting_sword","weapon slot selects category and equipped instance")
	check(page.field("EquipmentSlots").get_child_count()==8,"eight target equipment slots")
	check(page.field("EquipmentSlots").get_child(3).disabled,"unsupported shoes disabled")
	page._category("armor");check(page.selected.is_empty() and page.field("EquipmentAction").disabled,"armor category clears hidden weapon operation")
	page._category("");check(page.category.is_empty(),"all clears slot highlight")
	page._select("starting_sword")
	check(before==gm.operations.export_save(),"selection and probes never mutate state")
	page._act();await settle();page=view()
	check(gm.operations.stats().attack==20,"unequip updates actual attributes")
	check(page.selected=="starting_sword" and page.field("EquipmentAction").text=="装备","selection retained after unequip")
	page._act();await settle();page=view()
	check(gm.operations.stats().attack==24,"equip restores actual attributes")
	# Additional existing definitions in isolated fixture; no player save written.
	var payload: Dictionary=gm.operations.export_save()
	payload.state.player.equipment_instances.test_robe="equip_cloth_robe"
	payload.state.player.equipment_instances.test_iron="equip_iron_sword"
	gm.operations.restore_save(payload);await settle();page=view();page._tab("equipment")
	page._category("weapon");page._select("test_iron")
	check(page.field("EquipmentAction").disabled and page.field("EquipmentReason").text.contains("境界"),"realm requirement enforced")
	page._category("armor");check(page.selected.is_empty(),"category change clears incompatible selection")
	page._select("test_robe");page._act();await settle();page=view()
	check(gm.operations.stats().defense==11,"armor adds only configured defense")
	page._category("");check(page.selected=="test_robe","all preserves selected visible item")
	await settle();root.get_texture().get_image().save_png("res://docs/screenshots/character_equipment_1920x1080.png")
	before=gm.operations.export_save()
	page._tab("artifact");await settle()
	check(page.field("ArtifactPage").visible,"artifact placeholder tab")
	check(before==gm.operations.export_save(),"artifact tab has no state changes")
	root.get_texture().get_image().save_png("res://docs/screenshots/character_artifact_1920x1080.png")
	page._tab("info");await settle();check(page.field("CombatGrid").get_child(1).text.contains("11"),"info reflects equipped armor")
	var saved: Dictionary=gm.operations.export_save();check(gm.operations.restore_save(saved).is_empty(),"save remains compatible");await settle();page=view()
	for tab in ["info","equipment","artifact"]:
		page._tab(tab);await settle()
		check(page.get_global_rect().encloses(page.field("Content").get_global_rect()),tab+" content within page")
	root.size=Vector2i(1280,720);page._tab("equipment");await settle()
	check(page.get_global_rect().encloses(page.field("EquipmentAction").get_global_rect()),"small window action visible")
	root.get_texture().get_image().save_png("res://docs/screenshots/character_equipment_1280x720.png")
	page._tab("info");await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/character_info_1280x720.png")

	for key in ["Talent","Status"]:
		var grid: HFlowContainer=page.field(key+"Grid")
		for i in range(36):
			var tile:=Button.new();tile.custom_minimum_size=Vector2(90,30);tile.text="测试占位";grid.add_child(tile)
		await settle()
		check(page.field(key+"Scroll").get_v_scroll_bar().max_value>page.field(key+"Scroll").size.y,key+" independent scrolling")
	check(page.field("RootPanel").get_global_rect().end.y<=page.get_global_rect().end.y,"root remains within page after scroll overflow")
	page._tab("equipment");await settle()
	check(page.field("Categories").size.y<=64,"categories remain one row")
	for button in page.field("Categories").get_children():button.custom_minimum_size.x=160
	await settle()
	check(page.field("CategoryScroll").get_h_scroll_bar().max_value>page.field("CategoryScroll").size.x,"category bar horizontal scrolling")
	page._tab("info")
	page.field("Radar").set_values([13,10,12,8,0,0]);await settle()
	check(page.field("Radar").values.size()==6,"radar supports supplied values without creating game attributes")
	page.field("Radar").set_values([])
	page.field("Back").pressed.emit();await settle();check(main.page=="主界面","return works")
	print("CHARACTER UI: %d checks, %d failures" % [count,failures]);quit(0 if failures==0 else 1)
