extends SceneTree
var checks:=0
var failures:=0
var gm: Node
var main: Control
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
func inn() -> Control:return main.content.get_node("InnPage")
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("客栈验收","金");root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="主界面";root.add_child(main);await settle()
	var catalog=load("res://core/content_catalog.gd").new();catalog.load_all()
	catalog.tables.inns.inn_qinglan.npc_list=["missing_npc"]
	check(not catalog.validate_references(),"invalid inn NPC reference rejected")
	var before: Dictionary=gm.operations.export_save()
	for button in main.content.get_node("HomeView").field("Buildings").get_children():
		if button.text == "悦来客栈":
			button.pressed.emit()
			break
	await settle()
	check(main.page=="客栈" and inn().field("HomeContent").visible,"town enters inn homepage")
	check(before==gm.operations.export_save(),"enter no automatic payment")
	check(not inn().field("Secondary").visible,"no automatic action")
	check(inn().field("ShopName").text=="悦来客栈","configured inn title")
	check(inn().field("Announcement").text.contains("周掌柜"),"configured innkeeper")
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await settle()
		for key in ["Header","ShopInfo","ShopCenter","NearbyPanel","NewsPanel","Back","Stay","Meal","Rumors","Observe"]:
			check(inn().get_global_rect().encloses(inn().field(key).get_global_rect()),"visible "+key)
		root.get_texture().get_image().save_png("res://docs/screenshots/inn_home_%d.png" % resolution.x)
	var left: Node=inn().field("ShopInfo");var right: Node=inn().field("NearbyPanel")
	inn().field("Meal").pressed.emit();await settle()
	check(inn().tab=="meal" and inn().field("SecondaryBody").get_child(0).text.contains("尚未开放"),"meal honest placeholder")
	check(before==gm.operations.export_save(),"meal placeholder no mutation")
	check(inn().field("ShopInfo")==left and inn().field("NearbyPanel")==right,"only center changes")
	inn().field("ReturnHome").pressed.emit();inn().field("Observe").pressed.emit();await settle()
	check(inn().tab=="observe" and inn().field("SecondaryBody").get_child(0).text==inn().inn.observation,"configured observation")
	inn().field("ReturnHome").pressed.emit();inn().field("Rumors").pressed.emit();await settle()
	check(inn().field("SecondaryBody").get_child_count()>=2,"rumor list static distinction")
	check(gm.operations.snapshot().quests.is_empty(),"rumors never accept task")
	inn().field("ReturnHome").pressed.emit()
	var payload: Dictionary=gm.operations.export_save();payload.state.player.hp=1;payload.state.player.mp=0;gm.operations.restore_save(payload);await settle()
	inn().field("Stay").pressed.emit();await settle()
	check(inn().field("RoomSelect").item_count==1,"only approved existing room")
	root.get_texture().get_image().save_png("res://docs/screenshots/inn_stay_1280.png")
	var hour: int=gm.operations.snapshot().hours;var money: int=gm.operations.snapshot().player.spirit_stones
	var cultivation: int=gm.operations.snapshot().player.cultivation
	var id: String=inn().operation_id
	inn().field("ConfirmStay").pressed.emit();await settle()
	var after: Dictionary=gm.operations.snapshot()
	check(after.player.spirit_stones==money-10 and after.hours==hour+24,"real payment and TimeSystem")
	check(after.player.hp==gm.operations.stats().hp and after.player.mp==gm.operations.stats().mp,"full real recovery")
	check(after.player.cultivation==mini(100,cultivation+11),"only unified natural breathing during one day, no inn bonus")
	inn().field("ConfirmStay").pressed.emit();await settle()
	check(after==gm.operations.snapshot(),"repeated confirm no duplicate settlement")
	check(not gm.request("inn_stay",{"inn":"inn_qinglan","room":"room_existing"},id).success,"duplicate operation rejected")
	var saves=load("res://core/save_service.gd").new();var path: String=saves.write(gm.operations.export_save(),"user://test_saves")
	check(gm.operations.restore_save(saves.read(path)).is_empty() and gm.operations.snapshot()==after,"lodging disk roundtrip exact")
	check(not gm.request("inn_stay",{"inn":"inn_qinglan","room":"room_existing"},id).success and gm.operations.snapshot()==after,"saved operation remains idempotent")
	inn().field("ReturnHome").pressed.emit();await settle()
	gm.operations.data.inns.inn_qinglan.available_rooms[0].available=false
	before=gm.operations.export_save()
	check(not gm.request("inn_stay",{"inn":"inn_qinglan","room":"room_existing"}).success and before.state==gm.operations.snapshot(),"closed room atomic")
	gm.operations.data.inns.inn_qinglan.available_rooms[0].available=true
	payload=gm.operations.export_save();payload.state.player.spirit_stones=0;gm.operations.restore_save(payload);await settle()
	inn().field("Stay").pressed.emit();await settle();before=gm.operations.export_save()
	inn().field("ConfirmStay").pressed.emit();await settle()
	check(before.state==gm.operations.snapshot(),"insufficient money atomic")
	check(main.message.contains("灵石"),"clear failure")
	before=gm.operations.export_save()
	check(not gm.request("inn_stay",{"inn":"inn_qinglan","room":"missing"}).success and before.state==gm.operations.snapshot(),"unavailable room atomic")
	# Existing NPC placed in inn only for isolated UI test.
	payload=gm.operations.export_save();payload.state.npcs.npc_qin_shoushan.inn_id="inn_qinglan";gm.operations.restore_save(payload);await settle()
	inn()._tab("home");inn().field("Npcs").get_child(0).pressed.emit();await settle()
	var base: Control=inn()
	check(main.npc_overlay!=null and main.page=="客栈","inn uses unified NPC popup")
	main.npc_overlay.close();await settle()
	check(inn()==base,"closing NPC preserves original inn")
	var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true
	inn().field("Observe").pressed.emit();await settle();main._unhandled_key_input(key);await settle()
	check(inn().tab=="home","escape secondary to inn home")
	main._unhandled_key_input(key);await settle();check(main.content.has_node("HomeView") and gm.operations.snapshot().player.location=="town_qinglan","escape inn to original town")
	gm.request("travel",{"id":"town_yunxi"});await settle();main._navigate("客栈");await settle()
	check(inn().inn.id=="inn_yunxi" and inn().field("Back").text=="返回云溪城","second inn same UI")
	print("INN UI: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
