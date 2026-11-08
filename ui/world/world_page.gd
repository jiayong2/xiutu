extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal place_selected(id: String)
signal npc_requested(id: String)
signal shop_requested(id: String)
@export_enum("world","location","npc") var mode := "world"
var quest_api := preload("res://gameplay/quest/quest_system.gd").new()
var state: Dictionary={}
var data: Dictionary={}
var selected_place := "town_qinglan"
var selected_npc := "npc_qin_shoushan"
const PLACES := preload("res://core/world_locations.gd").BASE_NAMES
const DESCRIPTIONS:={"town_qinglan":"商店、任务、客栈与人物交互","cave_qinglan":"修炼、灵田与炼丹","area_qinglan_outskirts":"采集与妖兽遭遇；狼首挑战","town_yunxi":"云溪药阁与第二城镇"}
var building_actions: Array=[]
var nearby_ids: Array=[]
var places: Dictionary

static func place_name(id: String, tables: Dictionary) -> String:
	for sect in tables.get("prototype",{}).get("sects",[]):
		var residence: Dictionary=sect.get("residence",{})
		if residence.get("location_id","")==id and not id.is_empty():
			return residence.name
	return PLACES.get(id,id)

func field(id: String) -> Node:return find_child(id,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():
		if mode=="location" and not GameManager.operations.sect_at_location(state.player.location).is_empty():
			navigate.emit("宗门")
		else:
			navigate.emit("主界面" if mode=="world" else "地图" if mode=="location" else "地点场景"))
	if mode=="world":
		for entry in field("IndexList").get_children():
			var id := str(entry.name).trim_prefix("Index_")
			field(id).pressed.connect(_select_place.bind(id))
			entry.pressed.connect(_select_place.bind(id))
		field("Enter").pressed.connect(func():action_requested.emit("travel",{"id":selected_place}))
	elif mode=="location":
		for i in range(4):
			field("Building"+str(i)).pressed.connect(_building.bind(i))
			field("Npc"+str(i)).pressed.connect(_npc.bind(i))
		field("Tasks").pressed.connect(func():navigate.emit("任务"))
		field("Other").pressed.connect(func():navigate.emit("主界面"))
		field("ViewPlace").pressed.connect(func():field("LocationHint").text=_description(state.player.location))
		field("Activity").pressed.connect(_activity)
	else:
		field("Talk").pressed.connect(func():action_requested.emit("talk",{"id":selected_npc}))
		field("Tasks").pressed.connect(func():navigate.emit("任务"))
		field("End").pressed.connect(func():navigate.emit("地点场景"))
func bind_data(snapshot: Dictionary,tables: Dictionary,stats: Dictionary,place: String="",npc: String="",message: String="",dialogue: String="",previous_option: String="") -> void:
	state=snapshot;data=tables
	places=PLACES.duplicate()
	for sect in data.prototype.sects:
		var residence: Dictionary=sect.get("residence",{})
		if not residence.is_empty() and field(residence.location_id)!=null:
			places[residence.location_id]=residence.name
	selected_place=place if places.has(place) else str(state.player.location)
	selected_npc=npc if not npc.is_empty() else "npc_qin_shoushan"
	field("GameTime").text=preload("res://core/time_system.gd").new().format_date(state,data)
	field("Status").text=message
	if mode=="npc":_dialogue(dialogue,previous_option);return
	if mode=="world":
		field("PageTitle").text="世界地图"
		field("Status").text="选择地点查看详情；移动按现有时间规则执行" if message.is_empty() else message
		_place_detail()
		return
	var p: Dictionary=state.player
	var cultivation := preload("res://gameplay/cultivation/cultivation_system.gd").new()
	field("Identity").text="%s\n%s" % [p.name,cultivation.realm_name(p.realm,"qi",data)]
	field("Vitals").text="生命 %d / %d\n灵力 %d / %d" % [p.hp,stats.hp,p.mp,stats.mp]
	var target: int=cultivation.requirement(p,"qi",data)
	var required: String=str(target) if target>0 else "当前上限"
	field("Progress").text="修为 %d / %s" % [p.cultivation,required]
	field("CurrentPlace").text="当前地点\n"+PLACES.get(p.location,p.location)
	field("Wallet").text="灵石 %d" % p.spirit_stones
	if mode=="location":
		field("Identity").text+=" · %s灵根" % p.root
		for id in ["Progress","CurrentPlace","Wallet"]:field(id).visible=false
	if mode=="world":_place_detail()
	else:_location()
func _select_place(id: String) -> void:
	if state.is_empty() or not places.has(id):return
	selected_place=id;_place_detail();place_selected.emit(id)

func _description(id: String) -> String:
	return DESCRIPTIONS.get(id,"宗门山门，通行需满足入门条件。")

func _place_detail() -> void:
	field("PlaceName").text=places[selected_place]
	field("PlaceDescription").text=_description(selected_place)
	# Use the existing travel operation on a disposable snapshot for availability.
	var probe:=preload("res://core/operation_service.gd").new()
	probe.configure(data)
	probe.restore_save(GameManager.operations.export_save())
	var result: Dictionary=probe.request("travel",{"id":selected_place})
	field("UnlockStatus").text="已开放" if result.success else result.message
	field("UnlockStatus").autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	field("Enter").disabled=not result.success
	field("Enter").text="进入当前地点" if selected_place==state.player.location else "前往此地点"
	refresh_aura(state)
	var environment := "野外" if selected_place=="area_qinglan_outskirts" else "安全" if PLACES.has(selected_place) else "山门"
	field("Environment").text="环境："+environment
	var hours: int=GameManager.operations.travel_hours(state.player.location,selected_place)
	var duration := "%d日" % (hours/24.0) if hours%24==0 else "%d小时" % hours
	field("TravelCondition").text="已在此处，进入场景" if selected_place==state.player.location else "旅行耗时"+duration if hours>0 else "移动不消耗旅行时间"
	for id in places:
		for button in [field(id),field("Index_"+id)]:
			var style:=StyleBoxFlat.new()
			style.bg_color=Color("729b89") if id==selected_place else Color("4a6b78")
			style.set_corner_radius_all(6)
			style.set_border_width_all(2 if id==state.player.location else 0)
			style.border_color=Color("c5d9dd")
			button.add_theme_stylebox_override("normal",style)
			button.text=places[id]
			button.tooltip_text=places[id]+("（当前地点）" if id==state.player.location else "")
func refresh_aura(snapshot: Dictionary) -> void:
	state=snapshot
	field("Aura").text=GameManager.operations.clock.spirit.grade(state,selected_place,data)

func _location() -> void:
	var id: String=state.player.location
	var sect: Dictionary=GameManager.operations.sect_at_location(id)
	var name_at_place := place_name(id,data)
	field("PageTitle").text=name_at_place+" · 地点场景" if sect.is_empty() else sect.name+" · 宗门驻地"
	field("CenterTitle").text=name_at_place+"场景占位" if sect.is_empty() else name_at_place
	nearby_ids.clear()
	for npc in state.npcs.values():
		if npc.location==id and npc.alive:nearby_ids.append(npc.id)
	for i in range(4):
		var button: Button=field("Npc"+str(i))
		button.visible=i<nearby_ids.size()
		if button.visible:button.text=state.npcs[nearby_ids[i]].name
	building_actions.clear()
	for shop in data.shops.values():
		if shop.location==id:building_actions.append({"label":shop.name,"shop":shop.id})
	if id in ["town_qinglan","town_yunxi"]:building_actions.append({"label":"客栈","action":"inn"})
	elif id=="cave_qinglan":
		building_actions.append({"label":"修炼室","page":"修炼"})
		building_actions.append({"label":"灵田","page":"洞府"})
		building_actions.append({"label":"炼丹房","page":"洞府"})
	elif id=="area_qinglan_outskirts":
		building_actions.append({"label":"山外围探索","action":"explore"})
		for event in data.events.values():
			if event.location_id==id:building_actions.append({"label":"调查"+event.name,"event":event.id})
		building_actions.append({"label":"狼首挑战（建议二层+补给）","action":"challenge"})
	for i in range(4):
		var button: Button=field("Building"+str(i))
		button.disabled=i>=building_actions.size()
		button.text="场景空白区域" if button.disabled else building_actions[i].label
	if not sect.is_empty():
		field("BuildingGrid").hide()
		field("Activity").hide()
		field("Back").text="返回宗门总览"
		field("LocationHint").text="已进入山门。宗门内部区域尚未开放。"
	else:
		field("Activity").text="客栈休息" if id in ["town_qinglan","town_yunxi"] else "修炼" if id=="cave_qinglan" else "开始探索"
		field("LocationHint").text="休息消耗%d灵石与%d日，恢复生命与灵力。" % [data.rules.inn_cost,data.rules.inn_days] if id in ["town_qinglan","town_yunxi"] else "选择场景区域进行交互。"
func _building(index: int) -> void:
	if index>=building_actions.size():return
	var entry: Dictionary=building_actions[index]
	if entry.has("shop"):shop_requested.emit(entry.shop)
	elif entry.has("page"):navigate.emit(entry.page)
	elif entry.has("event"): _investigation(entry.event)
	else:action_requested.emit(entry.action,{})
func _activity() -> void:
	var id: String=state.player.location
	if id=="cave_qinglan":navigate.emit("修炼")
	else:action_requested.emit("inn" if id in ["town_qinglan","town_yunxi"] else "explore",{})
func _npc(index: int) -> void:
	if index<nearby_ids.size():npc_requested.emit(nearby_ids[index])
func _dialogue(text: String,previous_option: String) -> void:
	var npc: Dictionary=state.npcs.get(selected_npc,{})
	var valid: bool=not npc.is_empty() and npc.alive and npc.location==state.player.location
	var npc_name: String=npc.get("name","未知人物")
	field("PageTitle").text="人物交互 · "+npc_name
	var role: String={"npc_qin_shoushan":"青岚镇巡守 / 新手委托","npc_liu_qinghe":"杂货铺掌柜","npc_zhao_shanhe":"术法与兵器商人","npc_yunxi_keeper":"药阁掌柜"}.get(selected_npc,"")
	field("NpcIdentity").text=npc_name+" · "+role
	field("PortraitText").text=npc_name+"\nNPC立绘矩形占位"
	field("DialogueText").text=text if not text.is_empty() else "点击「交谈」开始对话。" if valid else "人物不在此处或已故。"
	field("Talk").disabled=not valid
	field("Tasks").disabled=not valid or selected_npc!="npc_qin_shoushan"
	if not text.is_empty():field("Status").text="交谈内容已更新"
	for child in field("QuestOptions").get_children():field("QuestOptions").remove_child(child);child.queue_free()
	for option in quest_api.dialogue_options(state,selected_npc,data,previous_option):
		var button:=Button.new();button.text=option.label;button.custom_minimum_size.y=48
		var box:=StyleBoxFlat.new();box.bg_color=Color("415b67");button.add_theme_stylebox_override("normal",box)
		button.pressed.connect(func():action_requested.emit("npc_option",{"npc":selected_npc,"option":option.id}))
		field("QuestOptions").add_child(button)

func _investigation(id: String) -> void:
	var definition: Dictionary=data.events[id]
	var dialog:=ConfirmationDialog.new()
	dialog.title=definition.name;dialog.dialog_text=definition.description+"\n\n辨认并记录将消耗 %d 小时" % definition.options[0].hours
	dialog.cancel_button_text="暂不调查"
	dialog.ok_button_text=definition.options[0].label
	dialog.confirmed.connect(func():action_requested.emit("investigate",{"id":id,"option":definition.options[0].id});dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog);dialog.popup_centered(Vector2i(720,360))
