extends SceneTree
var n:=0
var failures:=0
var main: Control
var gm: Node
func _initialize() -> void:call_deferred("run")
func check(ok: bool,t: String) -> void:
	n+=1
	if not ok:failures+=1;push_error(t)
	print("%s %s" % ["PASS" if ok else "FAIL",t])
func settle() -> void:
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
func view() -> Control:return main.content.get_node("ShopPage")
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("无名散修","金");root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="商店交易";root.add_child(main);await settle()
	var page:=view();var before: Dictionary=gm.operations.snapshot()
	check(page.field("ShopName").text=="青岚杂货铺","shared shop title")
	page._category("种子");check(page.field("ItemList").get_child_count()==4,"real category filter")
	page._category("全部");page._select("item_aura_powder");page._quantity(1)
	check(page.field("Total").text.contains("36"),"quantity total")
	check(gm.operations.snapshot()==before,"quotes selection and quantity read-only")
	page._confirm();await settle();page=view()
	check(gm.operations.snapshot().player.spirit_stones==84 and gm.operations.snapshot().stocks.shop_qinglan_general.item_aura_powder==8,"real purchase settled")
	check(page.field("Wallet").text.contains("84") and page.selected=="item_aura_powder","UI refresh retains selected item")
	page._select("equip_green_wood_sword");check(page.quotes[page.selected].maximum==1,"wallet limits max quantity")
	page._quantity(5);check(page.quantity==1,"quantity clamps to affordable maximum")
	root.get_texture().get_image().save_png("res://docs/screenshots/shop_buy_1920x1080.png")
	page._mode("出售");page._select("item_aura_powder")
	check(page.field("UnitPrice").text.contains("9"),"sell price distinct")
	page._confirm();await settle();page=view()
	check(gm.operations.snapshot().player.spirit_stones==93,"sell settles real money")
	page._select("starting_sword");check(page.field("Confirm").disabled and page.field("Reason").text.contains("卸下"),"equipped item protected")
	var payload: Dictionary=gm.operations.export_save();payload.state.player.inventory.material_wolf_fang=1
	gm.operations.restore_save(payload);await settle();page=view();page._select("material_wolf_fang")
	check(page.field("Reason").text.contains("任务材料"),"task material warning specific")
	before=gm.operations.snapshot();page._confirm();await settle()
	check(before==gm.operations.snapshot(),"task material opens confirmation without sale")
	for child in main.get_children():
		if child is ConfirmationDialog:child.hide();child.queue_free()
	page=view();page._select("item_healing_powder");check(not page.field("Reason").text.contains("任务材料"),"normal consumables no task warning")
	root.get_texture().get_image().save_png("res://docs/screenshots/shop_sell_1920x1080.png")
	payload=gm.operations.export_save();payload.state.player.spirit_stones=0;gm.operations.restore_save(payload);await settle();page=view();page._mode("购买");page._select("item_aura_powder")
	check(page.field("Confirm").disabled,"insufficient money disabled")
	payload=gm.operations.export_save();payload.state.player.spirit_stones=500;payload.state.stocks.shop_qinglan_general.item_aura_powder=0;gm.operations.restore_save(payload);await settle();page=view();page._select("item_aura_powder")
	check(page.field("Confirm").disabled,"empty stock disabled")
	payload=gm.operations.export_save();payload.state.stocks.shop_qinglan_general.item_aura_powder=10;payload.state.prices.town_qinglan=11000;gm.operations.restore_save(payload);await settle();page=view();page._select("item_aura_powder")
	check(page.quotes[page.selected].unit==20,"dynamic demand price preserved")
	payload=gm.operations.export_save()
	for id in gm.catalog.tables.items:
		if not gm.catalog.tables.equipment.has(id):payload.state.player.inventory[id]=1
	gm.operations.restore_save(payload);await settle();page=view();page._mode("出售");await settle()
	check(page.field("ItemScroll").get_v_scroll_bar().max_value>page.field("ItemScroll").size.y,"large sell inventory scrolls")
	payload=gm.operations.export_save();payload.state.npcs.npc_liu_qinghe.wealth=0
	gm.operations.restore_save(payload);await settle();page=view();page._select("item_aura_powder")
	check(page.field("Confirm").disabled and page.field("Reason").text.contains("商人"),"merchant balance restriction")
	main.selected_shop="shop_qinglan_spells";main._refresh();await settle();check(view().field("ShopName").text=="青岚术法铺","same scene serves second shop")
	root.size=Vector2i(1280,720);await settle();page=view()
	check(page.get_global_rect().encloses(page.field("Confirm").get_global_rect()),"small resolution fixed confirm visible")
	root.get_texture().get_image().save_png("res://docs/screenshots/shop_1280x720.png")
	page.field("Back").pressed.emit();await settle();check(main.page=="商店" and main.content.has_node("ShopHome"),"return to shop home")
	print("SHOP UI: %d checks, %d failures" % [n,failures]);quit(0 if failures==0 else 1)
