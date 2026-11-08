extends Control
signal close_requested
signal map_requested(location: String)
signal residence_requested(location: String)
signal npc_requested(id: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(tab: String,selected: String)

const TABS: Array[String]=["Overview","Mission","Library","Treasury","Rank","Npc"]
const WORLD_PAGE = preload("res://ui/world/world_page.gd")

var service: RefCounted
var state: Dictionary
var data: Dictionary
var tab: String="Overview"
var selected: String=""
var sects: Dictionary={}
var npc_selected: String=""
var donation_pending := false
var residence_location := ""

func field(key: String) -> Node:return find_child(key,true,false)

func _ready() -> void:
	field("NpcAction").pressed.connect(func():npc_requested.emit(npc_selected))
	field("Back").pressed.connect(func():close_requested.emit())
	field("Close").pressed.connect(func():close_requested.emit())
	field("SectMap").pressed.connect(func():
		if not field("SectMap").disabled:
			map_requested.emit(residence_location))
	field("VisitSect").pressed.connect(_visit_sect)
	for key in TABS:field(key+"Tab").pressed.connect(_tab.bind(key))
	field("EnterMissions").pressed.connect(_tab.bind("Mission"))
	field("Join").pressed.connect(func():
		if not field("Join").disabled:action_requested.emit("join_sect",{"id":selected}))
	field("Details").pressed.connect(_show_details)
	field("Donate").pressed.connect(_confirm_donation)
	field("DonationDialog").canceled.connect(func():donation_pending=false)
	field("DonationDialog").confirmed.connect(_submit_donation)

func bind_data(operations: RefCounted,saved_tab: String="Overview",key: String="",message: String="") -> void:
	service=operations;state=service.snapshot();data=service.data;tab=saved_tab;selected=key
	sects.clear()
	for definition in data.prototype.sects:sects[definition.id]=definition
	field("Message").text=message
	var member := sects.has(state.sect)
	field("SelectionPage").visible=not member
	field("StatusBar").visible=member
	field("InternalPage").visible=member
	if member:
		selected=state.sect
		_internal()
	else:
		_selection()
	_refresh_residence()
	_tab(tab)

func _style(node: Control,active: bool) -> void:
	node.theme_type_variation = &"PrimaryButton" if active else &""

func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()

func _select(id: String) -> void:
	selected=id
	_selection()
	_refresh_residence()
	selection_changed.emit(tab,selected)

func _selection() -> void:
	if not sects.has(selected):selected=str(sects.keys()[0]) if not sects.is_empty() else ""
	_clear(field("SectList"))
	for id in sects:
		var button:=Button.new();button.text=sects[id].name;button.custom_minimum_size.y=88
		_style(button,id==selected);button.pressed.connect(_select.bind(id));field("SectList").add_child(button)
	field("Join").disabled=true
	if selected.is_empty():field("SectName").text="暂无宗门";return
	var definition: Dictionary=sects[selected]
	field("SectName").text=definition.name
	field("Introduction").text=_introduction(definition,true)
	field("JoinConditions").text="当前境界：%s\n\n申请宗门：%s\n\n要求：炼气%d层\n\n需已开放云溪城\n\n同时只能加入一个宗门" % [_realm(state.player.realm),definition.name,data.prototype.sect_join_realm]
	var result: Dictionary=service.inventory_action_quote("join_sect",{"id":selected})
	field("Join").disabled=not result.success;field("JoinReason").text="已满足入门条件" if result.success else result.message
	_style(field("Join"),true)

func _refresh_residence() -> void:
	var definition: Dictionary=sects.get(selected,{})
	var residence: Dictionary=definition.get("residence",{})
	residence_location=residence.get("location_id","")
	var current_place := WORLD_PAGE.place_name(state.player.location,data)
	field("Title").text=definition.get("name","宗门")
	field("CurrentLocation").text="当前位置："+current_place
	var membership: String=service.sect_member_title(selected)
	if membership.is_empty():
		membership="未加入此宗门"
	field("SectMap").disabled=residence_location.is_empty()
	field("SectMap").tooltip_text="宗门驻地尚未加入世界地图" if residence_location.is_empty() else "在世界地图查看"+residence.name
	if residence_location.is_empty():
		field("SectLocation").text="宗门所在地待开放"
		field("ResidenceText").text="驻地尚未加入世界地图，暂无可用路线或旅行耗时。\n当前地点：%s　｜　身份：%s" % [current_place,membership]
		field("VisitSect").text="驻地尚未开放"
		field("VisitSect").disabled=true
		field("VisitSect").tooltip_text=field("SectMap").tooltip_text
		return
	var arrived: bool=state.player.location==residence_location
	var reason: String
	if arrived:
		reason=service.sect_residence_access(residence_location)
	else:
		var quote: Dictionary=service.inventory_action_quote("travel",{"id":residence_location})
		reason="" if quote.success else quote.message
	var hours: int=service.travel_hours(state.player.location,residence_location)
	var travel_status := "已抵达山门" if arrived else "未抵达 · 旅行耗时：%d小时" % hours
	var access := ("可进入外门区域" if arrived else "可前往山门") if reason.is_empty() else reason
	field("SectLocation").text=residence.name
	field("ResidenceText").text="%s　｜　%s\n%s　｜　%s" % [residence.name,travel_status,membership,access]
	field("VisitSect").text="进入宗门驻地" if arrived else "前往宗门" if state.sect==selected else "前往山门"
	field("VisitSect").disabled=not reason.is_empty()
	field("VisitSect").tooltip_text=reason

func _visit_sect() -> void:
	if field("VisitSect").disabled:
		return
	if state.player.location==residence_location:
		residence_requested.emit(residence_location)
	else:
		field("VisitSect").disabled=true
		action_requested.emit("travel",{"id":residence_location})

func _introduction(definition: Dictionary, include_background: bool) -> String:
	var fields := {"description":"宗门简介","specialty":"宗门特色","direction":"修炼方向"}
	if include_background:
		fields["background"]="宗门背景"
	var lines: Array[String]=[]
	for key in fields:
		var value := str(definition.get(key,"")).strip_edges()
		if not value.is_empty():
			lines.append("%s：%s" % [fields[key],value])
	return "\n\n".join(lines) if not lines.is_empty() else "宗门资料尚未录入。"

func _show_details() -> void:
	var definition: Dictionary=sects[selected]
	var dialog: AcceptDialog=field("DetailsDialog")
	dialog.title="%s · 宗门详情" % definition.name
	dialog.dialog_text=_introduction(definition,true)
	dialog.popup_centered_clamped(Vector2i(640,250))

func _confirm_donation() -> void:
	if donation_pending or field("Donate").disabled:
		return
	donation_pending=true
	var dialog: ConfirmationDialog=field("DonationDialog")
	dialog.dialog_text="当前灵石：%d，当前贡献：%d\n确认捐献 %d 灵石，获得 %d 贡献？" % [
		state.player.spirit_stones,state.contribution,data.prototype.sect_donation,data.prototype.sect_contribution]
	dialog.popup_centered(Vector2i(600,200))

func _submit_donation() -> void:
	if not donation_pending:
		return
	donation_pending=false
	field("Donate").disabled=true
	action_requested.emit("donate",{})

func _realm(level: int) -> String:return preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(level,"qi",data)

func _tab(value: String) -> void:
	tab=value if value in TABS else "Overview"
	for key in TABS:
		field(key+"Page").visible=key==tab
		_style(field(key+"Tab"),key==tab)
	selection_changed.emit(tab,selected)

func _internal() -> void:
	var definition: Dictionary=sects[selected]
	var title: String=service.sect_member_title(selected)
	field("MemberRank").text=title
	field("Contribution").text=str(state.contribution)
	field("SectLevel").text="未开放"
	field("SalaryStatus").text="未开放"
	field("SummaryText").text="%s\n所在地：%s\n\n%s" % [definition.name,definition.get("residence",{}).get("name","待开放"),_introduction(definition,false)]
	field("SalaryText").text="身份：%s · %s\n当前贡献：%d\n俸禄与晋升规则尚未开放" % [definition.name,title,state.contribution]
	field("ClaimSalary").disabled=true;field("ClaimSalary").tooltip_text="尚无俸禄发放规则及领取接口"
	field("MissionSummaryText").text="当前宗门：%s　｜　宗门事务尚未开放" % definition.name
	var result: Dictionary=service.inventory_action_quote("donate",{})
	field("Donate").disabled=not result.success
	field("Donate").tooltip_text="%d 灵石 = %d 贡献" % [data.prototype.sect_donation,data.prototype.sect_contribution] if result.success else result.message
	for key in ["Mission","Library","Treasury","Rank","Npc"]:_clear(field(key+"List"))
	_empty("MissionList","暂无已定义宗门任务")
	field("MissionDetail").text="宗门事务暂未开放"
	_empty("LibraryList","暂无宗门秘籍兑换清单")
	field("LibraryDetail").text="秘籍贡献兑换暂未开放"
	_empty("TreasuryList","暂无宗门宝库库存")
	field("TreasuryDetail").text="宗门宝库兑换暂未开放"
	_empty("RankList","职位与试炼暂未开放")
	field("RankDetail").text="当前身份：%s\n晋升与试炼暂未开放" % title
	_npcs()

func _empty(key: String,text: String) -> void:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;field(key).add_child(label)
func _npcs() -> void:
	var ids: Array[String]=[]
	for id in state.npcs:
		var npc: Dictionary=state.npcs[id]
		if npc.get("sect",npc.get("sect_id",""))!=state.sect:continue
		if not npc.get("alive",true):continue
		if preload("res://world/npc_interaction.gd").sect_area_restricted(npc,data):continue
		ids.append(id)
		var button:=Button.new();button.text=preload("res://world/npc_interaction.gd").new().summary(state,data,id);button.custom_minimum_size.y=84;button.clip_text=true;button.tooltip_text=button.text;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.add_theme_font_size_override("font_size",22)
		button.pressed.connect(func():_npc(id);npc_requested.emit(id));field("NpcList").add_child(button)
	if ids.is_empty():
		field("NpcAction").disabled=true
		_empty("NpcList","暂无已记录的宗门人物")
		field("NpcDetail").text="暂无可交互的宗门人物。"
	else:_npc(ids[0])
func _npc(id: String) -> void:
	npc_selected=id
	var npc: Dictionary=state.npcs[id]
	field("NpcDetail").text="%s

身份：%s
境界：%s
状态：%s" % [npc.name,npc.get("role","未定义"),preload("res://world/npc_interaction.gd").new().presentation(state,data,id).realm,"存活" if npc.alive else "已故"]
	# No new dialogue or affiliation rules are invented.
	field("NpcAction").disabled=false
	field("NpcAction").tooltip_text="打开统一人物交互"
