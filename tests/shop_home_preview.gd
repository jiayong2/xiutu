extends SceneTree
var checks:=0
var failures:=0
var main: Control
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
func home() -> Control:return main.content.get_node("ShopHome")
func esc() -> void:
	var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;main._unhandled_key_input(key)
func run() -> void:
	var gm: Node=root.get_node("GameManager");gm.new_game("店铺首页验收","金")
	root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="主界面";root.add_child(main);await settle()
	main.content.get_node("HomeView").field("Buildings").get_child(0).pressed.emit();await settle()
	check(main.page=="商店" and main.content.has_node("ShopHome"),"town enters shop home")
	check(not main.content.has_node("ShopPage") and home().find_child("ItemList",true,false)==null,"no automatic products")
	check(home().field("ShopName").text=="青岚杂货铺","configured title")
	check(home().field("Npcs").get_child_count()==1,"only actual associated keeper")
	check(home().field("NpcInfo").text.contains("柳青禾"),"actual existing keeper")
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await settle()
		for key in ["Header","ShopInfo","ShopCenter","NearbyPanel","NewsPanel","Back","Buy","Sell","KeeperTalk","Observe"]:
			check(home().get_global_rect().encloses(home().field(key).get_global_rect()),"visible "+key)
		root.get_texture().get_image().save_png("res://docs/screenshots/shop_home_%d.png" % resolution.x)
	var before: Dictionary=gm.operations.export_save()
	main._command("buy",{"shop":"shop_qinglan_general","item":"item_healing_powder","quantity":99});await settle()
	check(main.message.contains("失败") and main.message.contains("不足"),"specific failed purchase feedback")
	check(gm.operations.snapshot()==before.state,"failed purchase no state change")
	before=gm.operations.export_save()
	home().field("Npcs").get_child(0).pressed.emit()
	check(before==gm.operations.export_save(),"npc selection read-only")
	home().field("Buy").pressed.emit();await settle()
	var trade: Control=main.content.get_node("ShopPage")
	check(main.page=="商店交易" and trade.mode=="购买","buy requires explicit action")
	trade._select("item_healing_powder")
	var money: int=gm.operations.snapshot().player.spirit_stones
	trade.field("Confirm").pressed.emit();await settle()
	check(gm.operations.snapshot().player.spirit_stones==money-20,"original real purchase")
	check(main.message.contains("购买凝血散") and main.message.contains("成功"),"specific purchase feedback")
	main.content.get_node("ShopPage").field("Back").pressed.emit();await settle()
	check(main.content.has_node("ShopHome"),"trade back returns shop home")
	home().field("Sell").pressed.emit();await settle();trade=main.content.get_node("ShopPage")
	check(trade.mode=="出售","sell explicit mode")
	trade._select("item_healing_powder");trade.field("Confirm").pressed.emit();await settle()
	check(main.message.contains("出售凝血散") and main.message.contains("成功"),"specific sale feedback")
	esc();await settle();check(main.content.has_node("ShopHome"),"trade escape returns shop")
	home().field("KeeperTalk").pressed.emit();await settle()
	check(main.page=="商店" and main.npc_overlay.npc_id=="npc_liu_qinghe","unified dialogue keeper")
	main.npc_overlay._interact("交谈");await settle()
	esc();await settle()
	esc();await settle();check(main.content.has_node("ShopHome"),"dialogue escape returns shop")
	home().field("Observe").pressed.emit();await settle()
	check(main.observation_panel.visible,"observation simple panel")
	esc();await settle();check(not main.observation_panel.visible and main.page=="商店","observation escape closes only overlay")
	esc();await settle();check(main.content.has_node("HomeView") and gm.operations.snapshot().player.location=="town_qinglan","home escape returns town")
	main._open_shop("shop_qinglan_spells");await settle()
	check(home().field("ShopName").text=="青岚术法铺" and home().field("NpcInfo").text.contains("赵山河"),"other shop loads same home")
	var payload: Dictionary=gm.operations.export_save();payload.state.npcs.npc_zhao_shanhe.location="town_yunxi";gm.operations.restore_save(payload);await settle()
	check(home().field("Buy").disabled and home().field("Npcs").get_child_count()==0,"absent keeper no phantom npcs or trade")
	check(gm.operations.restore_save(gm.operations.export_save()).is_empty(),"save compatible")
	main._navigate("地点场景");gm.request("travel",{"id":"town_yunxi"});await settle()
	main._open_shop("shop_yunxi");await settle()
	check(home().field("ShopName").text=="云溪药阁" and home().field("Back").text=="返回云溪城","third shop and correct return")
	home().field("KeeperTalk").pressed.emit();await settle()
	main.npc_overlay.field("Close").pressed.emit();await settle()
	check(main.content.has_node("ShopHome"),"dialogue end button returns shop")
	home().field("Back").pressed.emit();await settle()
	check(gm.operations.snapshot().player.location=="town_yunxi" and main.content.has_node("HomeView"),"shop exit preserves Yunxi town")
	print("SHOP HOME: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)

