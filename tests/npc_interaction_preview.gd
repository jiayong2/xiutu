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
func popup() -> Control:return main.npc_overlay
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("人物弹窗验收","金")
	root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="主界面";root.add_child(main);await settle()
	var base: Control=main.content.get_node("HomeView")
	base.field("Npcs").get_child(0).pressed.emit()
	for frame in range(4):
		await RenderingServer.frame_post_draw
		check(popup().field("Panel").size==Vector2(1100,610),"first-open rendered frame "+str(frame))
		await process_frame
	await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/npc_popup_first_open.png")
	check(popup().field("Panel").size==Vector2(1100,610),"FIRST OPEN fixed popup dimensions")
	check(popup().get_global_rect().encloses(popup().field("Panel").get_global_rect()),"FIRST OPEN fully visible before interaction")
	check((popup().field("Panel").size*popup().field("Panel").scale).is_equal_approx(Vector2(1650,915)),"enlarged popup display size")
	check(popup().field("Feedback").size.y>=152,"taller chat region")
	check(main.page=="主界面" and popup()!=null,"town NPC opens overlay without page switch")
	check(main.content.get_node("HomeView")==base,"same background instance")
	check(popup().field("Actions").get_child_count()==12,"twelve fixed choices")
	for button in popup().field("Actions").get_children():check(not button.disabled,"clickable "+button.text)
	check(popup().field("Realm").text=="凡人" and popup().field("Relation").text=="关系：陌生","mortal realm and stranger relationship")
	var before: Dictionary=gm.operations.export_save()
	for kind in ["打听","赠礼","请教","论道","切磋","邀请","拜师","其他"]:
		popup()._interact(kind)
		check(popup().field("Feedback").text.contains("尚未开放"),"honest placeholder "+kind)
	check(before==gm.operations.export_save(),"placeholders preserve all state")
	popup()._interact("交易")
	check(popup().field("Feedback").text.contains("没有可交易"),"nonmerchant specific refusal")
	check(popup()!=null and popup().field("Actions").visible,"refusal keeps interaction")
	popup()._interact("交谈");await settle()
	check(popup().field("Subpanel").visible and popup().field("Feedback").text.contains("秦守山"),"talk existing data inside popup")
	check(gm.operations.snapshot().quests.is_empty(),"ordinary talk no quest grant")
	popup().back();popup()._interact("任务")
	check(popup().field("QuestOptions").get_child_count()>=1,"actual NPC quest options")
	popup().field("QuestOptions").get_child(0).pressed.emit();await settle()
	check(gm.operations.snapshot().quests.has("quest_qinglan_001"),"accept original quest")
	popup().field("QuestOptions").get_child(0).pressed.emit();await settle()
	check(gm.operations.snapshot().quests.quest_qinglan_001.current_objective_id=="investigate_tracks","designated dialogue stage retained")
	popup().back()
	root.get_texture().get_image().save_png("res://docs/screenshots/npc_popup_town_1920.png")
	popup().close();await settle()
	check(main.content.get_node("HomeView")==base and main.page=="主界面","close preserves original page")
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution;await settle()
		for repetition in range(3):
			main.open_npc_interaction("npc_qin_shoushan")
			await RenderingServer.frame_post_draw
			check(popup().field("Panel").size==Vector2(1100,610),"repeat open fits before interaction")
			check(popup().get_global_rect().encloses(popup().field("Feedback").get_global_rect()),"first-frame feedback visible")
			check(popup().field("Panel").get_global_rect().encloses(popup().field("Action11").get_global_rect()),"first-frame twelfth button visible")
			popup().close();await settle()
	main._open_shop("shop_qinglan_general");await settle()
	base=main.content.get_node("ShopHome")
	base.field("KeeperTalk").pressed.emit();await settle()
	check(main.page=="商店" and popup().npc_id=="npc_liu_qinghe","shop same overlay")
	popup()._interact("交易");await settle()
	check(popup().trade!=null,"merchant real trade")
	var trade: Control=popup().trade
	trade._select("item_healing_powder")
	var money: int=gm.operations.snapshot().player.spirit_stones
	trade.field("Confirm").pressed.emit();await settle()
	check(gm.operations.snapshot().player.spirit_stones==money-20,"trade real and once")
	popup().back();await settle()
	check(popup().trade==null and popup()!=null,"escape secondary trade first")
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await settle()
		check(popup().get_global_rect().encloses(popup().field("Panel").get_global_rect()),"popup fully visible")
		check(popup().field("Panel").size==Vector2(1100,610),"fixed popup dimensions")
		check(popup().field("NpcName").get_global_rect().end.y<=popup().field("Figure").get_global_rect().position.y,"name above portrait")
		check(popup().field("Relation").get_global_rect().position.y>=popup().field("Figure").get_global_rect().end.y,"relationship below portrait")
		root.get_texture().get_image().save_png("res://docs/screenshots/npc_popup_shop_%d.png" % resolution.x)
	popup()._interact("交谈");await settle();popup().back()
	check(popup().field("Actions").visible,"local conversation return")
	popup().close();await settle()
	check(main.content.get_node("ShopHome")==base,"store background preserved after trade")
	main.open_npc_interaction("npc_yunxi_keeper");await settle();popup()._interact("交谈")
	check(popup().field("Feedback").text.contains("不在此处"),"remote NPC specific refusal")
	popup()._interact("交易")
	check(popup().field("Feedback").text.contains("不在此处"),"remote merchant denied")
	popup().close();await settle()
	check(gm.operations.restore_save(gm.operations.export_save()).is_empty(),"save compatible")
	# Isolated placement fixtures exercise shared entry without adding formal NPCs.
	var payload: Dictionary=gm.operations.export_save()
	payload.state.sect="sect_qingyue";payload.state.npcs.npc_qin_shoushan.sect="sect_qingyue"
	gm.operations.restore_save(payload);main.sect_tab="Npc";main._navigate("宗门");await settle()
	var sect: Control=main.content.get_node("SectPage")
	sect.field("NpcList").get_child(0).pressed.emit();await settle()
	check(popup()!=null and main.page=="宗门","sect reuses same popup")
	popup().close();await settle();check(main.content.get_node("SectPage")==sect,"sect original page preserved")
	for location in ["cave_qinglan","area_qinglan_outskirts"]:
		payload=gm.operations.export_save();payload.state.player.location=location;payload.state.npcs.npc_qin_shoushan.location=location
		gm.operations.restore_save(payload);main._navigate("主界面");await settle()
		main.content.get_node("HomeView").field("Npcs").get_child(0).pressed.emit();await settle()
		check(popup()!=null and popup().npc_id=="npc_qin_shoushan","same popup at "+location)
		var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true
		popup()._interact("交谈");await settle();main._unhandled_key_input(key);await settle()
		check(popup()!=null and popup().field("Actions").visible,"ESC local conversation first")
		main._unhandled_key_input(key);await settle();check(main.npc_overlay==null,"ESC closes overlay second")
	print("NPC POPUP: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
