extends SceneTree
var gm: Node
var main: Control
var n:=0
var failures:=0
const GATE := "sect_qingyue_gate"
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	n+=1
	if not ok:failures+=1;push_error(title)
	print("%s %s" % ["PASS" if ok else "FAIL",title])
func settle() -> void:
	for i in range(5):await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
func capture(filename: String) -> void:
	if DisplayServer.get_name()!="headless":
		root.get_texture().get_image().save_png("res://docs/screenshots/"+filename)
func view() -> Control:return main.content.get_node("SectPage")
func colors(node: Node) -> bool:
	if node is Button:
		for key in ["normal","hover","pressed","disabled","focus","hover_pressed"]:
			var box: StyleBoxFlat=node.get_theme_stylebox(key)
			if box.bg_color.r+box.bg_color.g+box.bg_color.b<0.5:return false
	for child in node.get_children():
		if not colors(child):return false
	return true
func overview_controls_fit(page: Control) -> bool:
	var keys := ["Title","SectLocation","CurrentLocation","SectMap","Back","StatusBar",
		"ResidencePanel","VisitSect","Tabs","SummaryPanel","SalaryPanel","Details",
		"ClaimSalary","MissionSummaryText","EnterMissions","Donate","DonateMaterials","Close"]
	var bounds := page.get_global_rect()
	for key in keys:
		var control: Control=page.field(key)
		if not control.is_visible_in_tree() or not bounds.encloses(control.get_global_rect()):
			return false
	for row in [["Title","SectLocation","CurrentLocation","SectMap","Back"],
		["OverviewTab","MissionTab","LibraryTab","TreasuryTab","RankTab","NpcTab"],
		["MissionSummaryText","EnterMissions","Donate","DonateMaterials","Close"],
		["Header","StatusBar","ResidencePanel","Tabs","SectContent","Footer"]]:
		for index in range(row.size()-1):
			var first: Rect2=page.field(row[index]).get_global_rect()
			var next: Rect2=page.field(row[index+1]).get_global_rect()
			if first.intersects(next):
				return false
	return true
func residence_controls_fit(page: Control) -> bool:
	var previous: Control
	for key in ["Header","Navigation","CardTitle","CardScroll","Notice","Footer"]:
		var control: Control=page.field(key)
		if not page.get_global_rect().encloses(control.get_global_rect()):
			return false
		if previous!=null and previous.get_global_rect().intersects(control.get_global_rect()):
			return false
		previous=control
	var scroll: Control=page.field("CardScroll")
	for card in page.field("Cards").get_children():
		if card.visible and not scroll.get_global_rect().encloses(card.get_global_rect()):
			return false
	return true
func run() -> void:
	gm=root.get_node("GameManager");gm.set_process(false);gm.new_game("宗门验收","金");root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="宗门";root.add_child(main);await settle()
	var page:=view()
	check(page.field("SelectionPage").visible and not page.field("InternalPage").visible,"unaffiliated sees selection only")
	check(page.field("SectList").get_child_count()==3,"three existing sects")
	check(page.field("Join").disabled,"low realm join unavailable")
	check(page.field("ResidencePanel").visible and page.field("VisitSect").disabled and not page.field("SectMap").disabled,"map can locate gate before visitor is eligible")
	var locked: Dictionary=gm.operations.export_save()
	var denied: Dictionary=gm.request("travel",{"id":GATE})
	var after_denial: Dictionary=gm.operations.export_save()
	check(not denied.success and after_denial.state==locked.state and after_denial.random==locked.random,"direct request cannot bypass locked gate")
	var low_realm: Dictionary=locked.duplicate(true)
	low_realm.state.mvp1=true
	gm.operations.restore_save(low_realm)
	var realm_denial: Dictionary=gm.request("travel",{"id":GATE})
	check(not realm_denial.success and realm_denial.message.contains("炼气"),"opening Yunxi alone cannot bypass realm requirement")
	gm.operations.restore_save(locked)
	await settle();page=view()
	page.residence_requested.emit(GATE);await settle();page=view()
	check(main.page=="宗门","cannot open residence remotely")
	var before: Dictionary=gm.operations.export_save();page._select("sect_baicao")
	check(page.field("SectName").text=="百草谷","selection updates detail")
	check(page.field("Title").text=="百草谷" and page.field("ResidenceText").text.contains("未加入此宗门"),"residence tracks viewed sect without granting membership")
	check(page.field("VisitSect").disabled and page.field("SectMap").disabled,"unconfigured other sect has no route")
	check(before==gm.operations.export_save(),"selection and quote read-only")
	check(colors(page),"all button states have colored backgrounds")
	capture("sect_selection_1920x1080.png")
	# Approved existing fixture, no formal player save writes.
	var payload: Dictionary=gm.operations.export_save();payload.state.player.realm=2
	gm.operations.restore_save(payload);await settle();page=view()
	check(page.field("Join").disabled and page.field("JoinReason").text.contains("云溪"),"existing Yunxi prerequisite retained")
	payload=gm.operations.export_save();payload.state.mvp1=true
	gm.operations.restore_save(payload);await settle();page=view();page._select("sect_qingyue")
	check(not page.field("VisitSect").disabled and page.field("VisitSect").text=="前往山门","eligible unaffiliated visitor can travel")
	page.field("SectMap").pressed.emit();await settle()
	var map: Control=main.content.get_node("WorldMap")
	check(map.selected_place==GATE and map.field("TravelCondition").text.contains("12小时"),"overview map targets correct node and route")
	check(map.field("Canvas").get_global_rect().encloses(map.field(GATE).get_global_rect()),"gate map marker fits canvas")
	map.field("Back").pressed.emit();await settle();page=view()
	var visitor_start: Dictionary=gm.operations.export_save()
	page.field("VisitSect").pressed.emit();await settle();page=view()
	check(gm.operations.snapshot().player.location==GATE and gm.operations.snapshot().hours==visitor_start.state.hours+12,"visitor travels through real location and time")
	check(gm.operations.snapshot().sect.is_empty() and not page.field("StatusBar").visible,"travel grants no membership")
	check(page.field("VisitSect").text=="进入宗门驻地","arrival changes action to residence entry")
	var arrived: Dictionary=gm.operations.export_save()
	page.field("VisitSect").pressed.emit();await settle()
	check(main.page=="宗门驻地" and main.content.has_node("SectResidence"),"visitor opens residence at actual gate")
	var residence: Control=main.content.get_node("SectResidence")
	check(residence.field("AreaButtons").get_child_count()==4 and residence.field("Cards").columns==3,"four area tabs and three card columns")
	check(residence.field("Identity").text.contains("访客") and not residence.field("Identity").text.contains("外门弟子") and residence.field("People").disabled,"visitor has no disciple identity or member entry")
	check(residence_controls_fit(residence),"1920x1080 residence cards and controls fit")
	var first_cards: Array[Node]=residence.field("Cards").get_children()
	for index in [1,2,3]:
		residence.field("Area%d" % index).pressed.emit();await settle()
		check(residence.field("CardTitle").text.begins_with("布局预览") and residence.field("NoticeTitle").text=="通行限制","locked area %d explains restriction" % index)
		check(residence.field("AreaStatus").text.contains("当前区域：外门区域"),"preview does not change actual area %d" % index)
		check(residence.field("Cards").get_children()==first_cards and first_cards[0].get_node("Body/Row/CardAction").disabled,"area %d reuses cards and blocks entry" % index)
	check(first_cards[8].get_node("Body/Row/CardName").text=="未知区域","undiscovered site is concealed")
	root.size=Vector2i(1280,720);await settle()
	check(residence_controls_fit(residence),"1280x720 residence preview cards and controls fit")
	root.size=Vector2i(1920,1080);await settle()
	residence.field("ReturnOuter").pressed.emit();await settle()
	check(not residence.field("ReturnOuter").visible and not first_cards[8].get_node("Body/Row/CardAction").disabled,"return to outer enables gate card")
	check(gm.operations.export_save()==arrived,"opening residence has no additional travel or settlement")
	residence.field("Back").pressed.emit();await settle();page=view()
	check(main.page=="宗门","residence returns to overview")
	page.field("VisitSect").pressed.emit();await settle()
	residence=main.content.get_node("SectResidence")
	residence.field("Cards").get_child(8).get_node("Body/Row/CardAction").pressed.emit();await settle()
	check(main.page=="地图" and main.content.get_node("WorldMap").selected_place==GATE and gm.operations.export_save()==arrived,"gate card returns to map without moving player")
	main._navigate("宗门");await settle()
	check(gm.operations.restore_save(visitor_start).is_empty(),"previous saves remain readable")
	await settle();page=view()
	check(not page.field("Join").disabled,"eligible real join")
	page.field("Join").pressed.emit();await settle();page=view()
	check(gm.operations.snapshot().sect=="sect_qingyue","real membership")
	check(page.field("InternalPage").visible and not page.field("SelectionPage").visible,"join switches to internal")
	check(page.field("Title").text=="青岳宗","real sect title")
	check(page.field("CurrentLocation").text=="当前位置：青岚镇" and not page.field("VisitSect").disabled,"joining does not move player and own member can travel")
	check(page.field("Tabs").columns==6,"six tabs on one row")
	check(overview_controls_fit(page),"1920x1080 overview controls fit without overlap")
	page.field("Details").pressed.emit()
	check(page.field("DetailsDialog").visible and page.field("DetailsDialog").dialog_text.contains("尚未录入"),"detail displays truthful empty state")
	page.field("DetailsDialog").hide()
	check(not gm.request("join_sect",{"id":"sect_baicao"}).success,"cannot join second sect")
	check(page.field("ClaimSalary").disabled,"unconfirmed salary disabled")
	check(page.field("MemberRank").text=="外门弟子" and page.field("SalaryText").text.contains("外门弟子") and page.field("ResidenceText").text.contains("外门弟子"),"joining shows outer disciple across overview")
	check(page.field("SectLevel").text=="未开放" and gm.operations.sect_member_title("sect_baicao").is_empty(),"no sect level or rank for another sect")
	var money: int=gm.operations.snapshot().player.spirit_stones
	check(page.field("DonateMaterials").disabled,"undefined material donation disabled")
	page.field("Donate").pressed.emit()
	var dialog: ConfirmationDialog=page.field("DonationDialog")
	check(dialog.visible and gm.operations.snapshot().player.spirit_stones==money,"opening confirmation does not charge")
	dialog.hide()
	dialog.canceled.emit()
	check(gm.operations.snapshot().player.spirit_stones==money,"cancel keeps balance")
	page.field("Donate").pressed.emit()
	dialog.hide()
	dialog.confirmed.emit()
	dialog.confirmed.emit()
	await settle();page=view()
	check(gm.operations.snapshot().player.spirit_stones==money-10 and gm.operations.snapshot().contribution==1,"donation costs ten grants one")
	check(page.field("Contribution").text=="1","contribution display refreshes")
	check(colors(page),"internal all button states colored")
	capture("sect_overview_1920x1080.png")
	before=gm.operations.export_save()
	for key in ["Mission","Library","Treasury","Rank","Npc"]:
		page._tab(key);await settle()
		check(page.field(key+"Page").visible and page.field(key+"Action").disabled,key+" placeholder safe")
		capture("sect_"+key.to_lower()+"_1920x1080.png")
	check(before==gm.operations.export_save(),"all tabs preserve state")
	check(page.field("NpcList").get_child_count()==1,"no invented sect NPCs")
	check(gm.request("travel",{"id":"town_yunxi"}).success,"existing travel changes the real place")
	await settle();page=view()
	check(page.field("CurrentLocation").text=="当前位置：云溪城" and page.field("ResidenceText").text.contains("36小时"),"Yunxi route adds original day to mountain travel")
	var yunxi_hour: int=gm.operations.snapshot().hours
	page.field("VisitSect").pressed.emit();await settle();page=view()
	check(gm.operations.snapshot().player.location==GATE and gm.operations.snapshot().hours==yunxi_hour+36,"member reaches gate in 36 hours from Yunxi")
	var gate_save: Dictionary=gm.operations.export_save()
	check(gm.operations.restore_save(gate_save).is_empty(),"save at gate is readable")
	await settle();page=view()
	check(page.field("VisitSect").text=="进入宗门驻地" and not page.field("VisitSect").disabled and page.field("ResidenceText").text.contains("可进入外门区域"),"gate save restores usable outer entry")
	check(page.field("MemberRank").text=="外门弟子" and page.field("Contribution").text=="1","existing save restores disciple identity and contribution")
	page.field("VisitSect").pressed.emit();await settle()
	residence=main.content.get_node("SectResidence")
	check(residence.field("Identity").text.contains("外门弟子") and residence.field("Identity").text.contains("贡献：1") and not residence.field("People").disabled,"disciple sees actual contribution and people shortcut")
	check(residence.field("Area0").button_pressed and residence.field("AreaStatus").text.contains("通行权限：已获得"),"own disciple defaults to open outer area")
	residence.field("People").pressed.emit();await settle();page=view()
	check(page.field("NpcPage").visible,"member shortcut reuses existing people tab")
	main._navigate("地点场景");await settle()
	var home: Control=main.content.get_node("HomeView")
	check(home.field("WorldMap").text.contains("青岳山") and home.field("ReleaseStone").disabled,"home recognizes gate without opening cultivation services")
	var residence_entry: Button=home.field("Buildings").get_child(0)
	check(residence_entry.text=="宗门驻地" and not residence_entry.disabled,"gate home offers direct residence entry")
	var before_entry: Dictionary=gm.operations.export_save()
	residence_entry.pressed.emit();await settle()
	check(main.page=="宗门驻地" and main.content.has_node("SectResidence") and gm.operations.export_save()==before_entry,"gate home opens residence without travel")
	main.content.get_node("SectResidence").field("Back").pressed.emit();await settle();page=view()
	check(page.field("OverviewPage").visible,"residence still links to sect overview")
	page.field("Back").pressed.emit();await settle()
	check(main.page=="地点场景","closing overview returns to gate home")
	var gate_hour: int=gm.operations.snapshot().hours
	gm.operations.advance_realtime(3600)
	check(gm.operations.snapshot().hours==gate_hour+1,"world time continues safely at gate")
	main._navigate("宗门");await settle();page=view()
	var other_member: Dictionary=gate_save.duplicate(true)
	other_member.state.sect="sect_baicao"
	gm.operations.restore_save(other_member);await settle();page=view()
	check(not gm.operations.sect_residence_access(GATE).is_empty(),"other sect membership fails gate entry")
	var departure_hour: int=gm.operations.snapshot().hours
	check(gm.request("travel",{"id":"town_qinglan"}).success and gm.operations.snapshot().hours==departure_hour+12,"leaving the gate remains available and costs 12 hours")
	check(not gm.request("travel",{"id":GATE}).success,"other sect membership fails gate travel")
	check(gm.operations.restore_save(before).is_empty(),"save compatible");await settle();page=view()
	check(page.field("CurrentLocation").text=="当前位置：青岚镇" and page.field("Contribution").text=="1","load restores real location and contribution")
	page._tab("Overview");root.size=Vector2i(1280,720);await settle()
	check(page.get_global_rect().encloses(page.field("Donate").get_global_rect()),"small window donate visible")
	check(page.get_global_rect().encloses(page.field("ClaimSalary").get_global_rect()),"small window salary visible")
	check(page.get_global_rect().encloses(page.field("VisitSect").get_global_rect()),"small window residence button visible")
	check(overview_controls_fit(page),"1280x720 overview controls fit without overlap")
	capture("sect_overview_1280x720.png")
	payload=gm.operations.export_save();payload.state.player.spirit_stones=0;gm.operations.restore_save(payload);await settle();page=view()
	check(page.field("Donate").disabled,"insufficient stones disables donation")
	page.field("Back").pressed.emit();await settle();check(main.page=="地点场景","return location")
	main._navigate("主界面");await settle()
	main._navigate("宗门");await settle();page=view()
	page.field("Close").pressed.emit();await settle();check(main.page=="主界面","close returns to previous page")
	print("SECT UI: %d checks, %d failures" % [n,failures]);quit(0 if failures==0 else 1)
