extends SceneTree

const Auction = preload("res://gameplay/auction/auction_system.gd")
var checks := 0
var failures := 0
var output := ""
var main: Control
var gm: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> void:
	await settle()
	var image := root.get_texture().get_image()
	check(image.get_size()==root.size and image.save_png(output.path_join(name+".png"))==OK,name+" screenshot")

func page() -> Control:
	return main.content.get_node("AuctionPage")

func building() -> Button:
	var home: Control = main.content.get_node("HomeView")
	for entry in home.field("Buildings").get_children():
		if entry is Button and entry.text=="云溪城拍卖会":
			return entry
	return null

func layout(view: Control, size: Vector2i) -> void:
	root.size = size
	await settle()
	for key in ["TitleBar","Participants","Core","Interaction","Activity","Close","HostPortrait","Bid","Pass","Watch"]:
		var control: Control = view.field(key)
		check(control.is_visible_in_tree() and view.get_global_rect().encloses(control.get_global_rect()),"%s %s stays inside page" % [size,key])
	var host: Control = view.field("HostPortrait")
	check(host.size.is_equal_approx(Vector2(118,118)),"host portrait stays square and fixed")
	var bid: Rect2 = view.field("Bid").get_global_rect()
	var leave: Rect2 = view.field("Pass").get_global_rect()
	check(is_equal_approx(bid.position.y,leave.position.y) and bid.end.x < leave.position.x,"bid and pass share one bottom row")
	for adjacent in [["Participants","Core"],["Core","Interaction"],["Columns","Activity"]]:
		check(not view.field(adjacent[0]).get_global_rect().intersects(view.field(adjacent[1]).get_global_rect()),"panels have no overlap")
	check(view.field("InteractionScroll").get_global_rect().encloses(view.field("Pressure").get_global_rect()),"fifth interaction is fully visible")
	check(view.field("QuoteRow").get_global_rect().encloses(view.field("Quote").get_global_rect()),"bid preview stays visible")

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	gm = root.get_node("GameManager")
	check(gm.boot_ok and gm.new_game("云溪验收","水").is_empty(),"test starts")
	if not gm.boot_ok:
		quit(1)
		return
	gm.set_process(false)
	var op: RefCounted = gm.operations
	main = load("res://ui/main/main.tscn").instantiate()
	main.page = "主界面"
	root.size = Vector2i(1920,1080)
	root.add_child(main)
	await settle()
	check(building()==null,"Qinglan does not list Yunxi auction")
	check(op.request("travel",{"id":"town_yunxi"}).success,"real travel to Yunxi")
	await settle()
	var entrance := building()
	check(entrance!=null and not entrance.disabled,"Yunxi building has active auction entry")
	await capture("auction-yunxi-building")
	entrance.pressed.emit()
	await settle()
	var view := page()
	check(view.field("Title").text=="云溪城拍卖会" and view.field("Lobby").visible,"real building opens configured lobby")
	view.field("Anonymous").button_pressed = true
	view.field("Enter").pressed.emit()
	await settle()
	check(view.a.phase=="bidding" and view.a.anonymous and view.field("ParticipantsList").get_child_count()==4,"enter with four live NPCs")
	check(view.field("Spirit").disabled,"interactions require a target")
	view.field("ParticipantsList").get_child(0).pressed.emit()
	check(view.target=="npc_yunxi_keeper" and view.field("ParticipantsList").get_child(0).theme_type_variation==&"Selected","NPC can be selected")
	await layout(view,Vector2i(1920,1080))
	await capture("auction-1920")
	view.field("Custom").pressed.emit()
	view.field("CustomInput").text = "1"
	view.field("CustomInput").text_changed.emit("1")
	check(view.field("Bid").disabled,"invalid custom bid is disabled")
	view.field("Quick").pressed.emit()
	check(view.field("Quote").text.contains(str(Auction.proposed(view.a,view.lot,op.data.auction_rules,"quick",0))),"quick preview uses real quote")
	view.field("Standard").pressed.emit()
	await layout(view,Vector2i(1280,720))
	await capture("auction-1280")
	view.field("Spirit").pressed.emit()
	await settle()
	check(view.field("ResultDialog").visible and view.field("ResultDialog").dialog_text.contains("神识威慑"),"spirit result appears in dialog")
	check(view.field("ActivityLog").text.contains("神识威慑"),"spirit result also appears in activity")
	await capture("auction-interaction-1280")
	view.field("ResultDialog").hide()
	var saved: Dictionary = Auction.session(op.snapshot(),"auction_yunxi")
	view.field("Close").pressed.emit()
	await settle()
	check(main.page=="地点场景" and Auction.session(op.snapshot(),"auction_yunxi")==saved,"close returns to location without resetting round")
	building().pressed.emit()
	await settle()
	view = page()
	check(view.a==saved,"reopening resumes same state")
	view.field("Rules").pressed.emit()
	await settle()
	check(view.field("InfoDialog").visible and view.field("InfoText").text.contains("5.0%"),"rules display configured commission")
	view.field("InfoDialog").hide()
	view.field("Pass").pressed.emit()
	check(view.a.phase=="settled" and view.field("Next").visible and view.field("ResultDialog").visible,"one pass reaches result and next lot control")
	view.field("ResultDialog").hide()
	view.field("Next").pressed.emit()
	check(view.a.index==1 and not view.a.withdrawn,"next lot lets player bid again")
	var alternate: Dictionary = op.data.auctions.auction_yunxi.duplicate(true)
	alternate.id = "auction_ui_fixture"
	alternate.name = "验收坊市拍卖"
	alternate.scale = "大型"
	alternate.participants = []
	alternate.lots = [alternate.lots[2]]
	op.data.auctions[alternate.id] = alternate
	main.selected_auction = alternate.id
	main._refresh()
	await settle()
	view = page()
	check(view.field("Title").text==alternate.name and view.field("Count").text.contains("1"),"second configuration uses the same scene")
	check(view.field("ParticipantsList").get_child_count()==0,"second configuration drives NPC count")
	print("AUCTION UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
