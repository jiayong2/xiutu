extends SceneTree
var gm: Node
var main: Control
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
func view() -> Control:return main.content.get_node("InventoryPage")
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("背包验收","金");root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="地点场景";root.add_child(main);await settle();main._navigate("背包");await settle()
	var page:=view()
	check(page.category=="全部","default all")
	check(page.field("Wallet").text=="灵石：120","real currency only")
	check(page.field("ItemPanelTitle").text=="物品栏","item heading no extra statistics")
	check(page.entries.size()==3,"initial real items includes equipment instance")
	page._category("丹药");await settle()
	check(page.field("ItemGrid").get_child_count()==2,"two consumables two tiles")
	var before: Dictionary=gm.operations.export_save();page._select("item_healing_powder:0")
	check(before==gm.operations.export_save(),"selection and availability read-only")
	check(page.field("Action").text=="使用" and page.field("Action").disabled,"full health disables healing with reason")
	await settle()
	check(page.field("Header").size.y<=80,"header remains compact")
	check(page.field("ItemName").text=="凝血散","selected details visible")
	root.get_texture().get_image().save_png("res://docs/screenshots/inventory_1920x1080.png")
	var payload: Dictionary=gm.operations.export_save();payload.state.player.hp=30;payload.state.player.inventory.item_healing_powder=1
	payload.state.player.inventory.book_technique_iron_body=1;payload.state.player.inventory.book_skill_fire_bolt=1
	payload.state.player.inventory.herb_spirit_grass=205;payload.state.player.inventory.material_wolf_fang=1
	gm.operations.restore_save(payload);await settle();page=view();page._category("丹药");page._select("item_healing_powder:0");page._act();await settle();page=view()
	check(gm.operations.snapshot().player.hp==70,"real item effect")
	check(not gm.operations.snapshot().player.inventory.has("item_healing_powder"),"last item consumed")
	check(page.selected.is_empty(),"depleted stack selection cleared")
	page._category("功法");page._select("book_technique_iron_body:0")
	check(page.field("Action").text=="学习","technique book learns")
	page._act();await settle();page=view()
	check(gm.operations.snapshot().player.techniques.has("technique_iron_body"),"real technique learned")
	page._category("法术");page._select("book_skill_fire_bolt:0");page._act();await settle();page=view()
	check(gm.operations.snapshot().player.spells.has("skill_fire_bolt"),"real spell learned")
	page._category("材料")
	check(page.entries["herb_spirit_grass:0"].quantity==99 and page.entries["herb_spirit_grass:1"].quantity==99 and page.entries["herb_spirit_grass:2"].quantity==7,"205 split into 99 99 7")
	page._select("herb_spirit_grass:2");check(not page.field("Action").visible,"materials have no use button")
	page._category("任务物品");page._select("material_wolf_fang:0")
	check(not page.field("Action").visible,"task materials protected from generic use")
	page._category("装备");check(page.selected.is_empty(),"category clears hidden selection")
	page._select("instance:starting_sword");check(page.field("Action").text=="卸下","equipment instance action")
	page._act();await settle();page=view();check(gm.operations.stats().attack==20,"unequip updates stats")
	page._act();await settle();page=view();check(gm.operations.stats().attack==24,"equip updates stats")
	page._category("全部");check(page.selected=="instance:starting_sword","all preserves visible selected instance")
	before=gm.operations.export_save();check(gm.operations.restore_save(before).is_empty(),"save compatible");await settle();page=view()
	payload=gm.operations.export_save()
	for id in gm.catalog.tables.items:
		if not gm.catalog.tables.equipment.has(id):payload.state.player.inventory[id]=205
	gm.operations.restore_save(payload);await settle();page=view();page._category("全部");await settle()
	check(page.field("ItemScroll").get_v_scroll_bar().max_value>page.field("ItemScroll").size.y,"many real item stacks scroll")
	page._select("item_aura_powder:0");page.field("Description").text="长描述\n".repeat(150);await settle()
	check(page.field("DescriptionScroll").get_v_scroll_bar().max_value>page.field("DescriptionScroll").size.y,"description scroll independent")
	check(page.get_global_rect().encloses(page.field("Action").get_global_rect()),"long description leaves action visible")
	root.size=Vector2i(1280,720);await settle();check(page.get_global_rect().encloses(page.field("Action").get_global_rect()),"small window usable")
	page._detail();await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/inventory_1280x720.png")
	page.field("Back").pressed.emit();await settle();check(main.page=="地点场景","returns to source location")
	print("INVENTORY UI: %d checks, %d failures" % [n,failures]);quit(0 if failures==0 else 1)
