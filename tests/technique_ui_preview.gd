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
func view() -> Control:return main.content.get_node("TechniquePage")
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("UI验收","金");root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="功法";root.add_child(main);await settle()
	var page:=view()
	check(page.field("SlotGrid").get_child_count()==10,"ten technique slots")
	var before: Dictionary=gm.operations.export_save()
	page._select("technique_qi_flow")
	check(before==gm.operations.export_save(),"selection and quotes read-only")
	check(page.field("Effects").text.contains("法修炼化"),"real refining role")
	var spirit: RefCounted=gm.operations.clock.spirit
	var cultivation: RefCounted=gm.operations.cultivation
	var original_profile: Dictionary=spirit.plan(gm.operations.snapshot(),"natural","qi",gm.operations.data,cultivation)
	page._act("slot");await settle();page=view()
	check(gm.operations.snapshot().player.technique_slots.is_empty(),"unequip real command")
	check(spirit.plan(gm.operations.snapshot(),"natural","qi",gm.operations.data,cultivation).is_empty(),"unequip removes refining")
	page._act("slot");await settle();page=view()
	check(not spirit.plan(gm.operations.snapshot(),"natural","qi",gm.operations.data,cultivation).is_empty(),"equip restores refining")
	check(page.field("Upgrade").disabled,"insufficient cultivation disabled")
	var payload: Dictionary=gm.operations.export_save();payload.state.player.spirit_stones=1000;payload.state.player.cultivation=1000
	gm.operations.restore_save(payload);await settle();page=view();page._act("upgrade");await settle();page=view()
	check(gm.operations.snapshot().player.techniques.technique_qi_flow==2,"upgrade real level")
	var upgraded: Dictionary=spirit.plan(gm.operations.snapshot(),"natural","qi",gm.operations.data,cultivation)
	check(upgraded.profile.refinement>original_profile.profile.refinement,"upgrade increases actual refining capacity")
	root.get_texture().get_image().save_png("res://docs/screenshots/technique_1920x1080.png")
	page._mode("spells")
	check(page.field("SlotGrid").get_child_count()==int(gm.catalog.tables.rules.initial_slots),"spell count from rule")
	check(page.field("Effects").text.contains("110%") and page.field("Mana").text.contains("灵力"),"active spell effect and mana cost")
	page.field("Upgrade").pressed.emit()
	var spell_page: Control=page.spell_page
	spell_page.field("Confirm",spell_page.subview).pressed.emit()
	spell_page.field("Cancel",spell_page.subview).pressed.emit()
	await settle();page=view()
	check(gm.operations.snapshot().player.spells.skill_spirit_bolt==2,"spell upgrades")
	var saved: Dictionary=gm.operations.export_save()
	check(gm.operations.restore_save(saved).is_empty(),"save restore accepted")
	await settle();page=view();page._mode("spells");await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/spell_1920x1080.png")
	root.size=Vector2i(1280,720);await settle()
	check(page.get_global_rect().encloses(page.field("Upgrade").get_global_rect()),"small window actions visible")
	root.get_texture().get_image().save_png("res://docs/screenshots/technique_1280x720.png")

	# Isolated fixtures cover empty state, capacity and rule-driven rendering.
	payload=gm.operations.export_save()
	for id in gm.catalog.tables.techniques:payload.state.player.techniques[id]=1
	payload.state.player.technique_slots=["technique_qi_flow","technique_iron_body","technique_green_wood"]
	gm.operations.restore_save(payload);await settle();page=view();page._mode("techniques");page._select("technique_fire_breath")
	check(page.field("Equip").disabled,"full slots disables equip")
	check(page.field("Reason").text.contains("槽位"),"capacity reason shown")
	payload=gm.operations.export_save();payload.state.player.techniques={};payload.state.player.technique_slots=[]
	gm.operations.restore_save(payload);await settle();page=view()
	check(page.selected.is_empty() and page.field("Equip").disabled and page.field("Upgrade").disabled,"empty learned state safe")
	# Extra rows remain test-only UI nodes, never formal game content.
	for i in range(20):
		var row: Button=load("res://ui/technique/technique_list_item.tscn").instantiate()
		row.text="滚动测试占位";page.field("TechniqueList").add_child(row)
	await settle()
	check(page.field("ListScroll").get_v_scroll_bar().max_value>page.field("ListScroll").size.y,"list scrolls")
	var original: int=int(gm.operations.data.rules.initial_slots)
	gm.operations.data.rules.initial_slots=4
	page.bind_data(gm.operations,"spells","","");await settle()
	check(page.field("SlotGrid").get_child_count()==4,"spell slots follow changed rule")
	gm.operations.data.rules.initial_slots=original
	page.field("Back").pressed.emit();await settle();check(main.page=="主界面","back works")
	print("TECHNIQUE UI: %d checks, %d failures" % [count,failures]);quit(0 if failures==0 else 1)
