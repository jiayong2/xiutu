extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal npc_requested(id: String)
signal shop_requested(id: String)
signal auction_requested(id: String)
signal quest_requested(id: String)
signal cave_requested(tab: String)
signal route_changed(route: String)
const CULTIVATION := preload("res://gameplay/cultivation/cultivation_system.gd")
const FOCUS_BUTTONS := {"Refinement":"refinement","Balance":"balance","Nurture":"nurture"}
const FOCUS_HINTS := {"refinement":"将更多炼化灵气沉淀为修为。","balance":"按常规比例分配给修为和温养。","nurture":"将更多炼化灵气用于温养根基。"}
var cultivation := CULTIVATION.new()
var spirit := preload("res://gameplay/cultivation/spirit_cultivation.gd").new()
var route := "qi"
var state: Dictionary
var data: Dictionary
var service: RefCounted
var tracked: String=""
func field(id: String) -> Node:return find_child(id,true,false)
func _ready() -> void:
	for button in find_children("Nav_*","Button",true,false):button.pressed.connect(func():navigate.emit(str(button.get_meta("destination"))))
	field("WorldMap").pressed.connect(func():navigate.emit("地图"))
	field("CurrentTechnique").pressed.connect(func():navigate.emit("功法"))
	field("SpellPath").pressed.connect(_select_route.bind("qi"))
	field("BodyPath").pressed.connect(_select_route.bind("body"))
	field("ReleaseStone").pressed.connect(_confirm_release_stone)
	for key in FOCUS_BUTTONS:
		field(key).pressed.connect(_select_focus.bind(FOCUS_BUTTONS[key]))
	field("Practice").pressed.connect(func():navigate.emit("淬体" if route=="body" else "修炼"))
	field("Promote").pressed.connect(func():action_requested.emit("promote",{"route":route}))
	field("TaskOpen").pressed.connect(func():quest_requested.emit(tracked))

func _select_route(value: String) -> void:
	route=value
	route_changed.emit(route)
	_refresh_route()
	refresh_time(state)

func _select_focus(value: String) -> void:
	if state.player.growth.focus[route]!=value:
		action_requested.emit("cultivation_focus",{"route":route,"focus":value})

func _confirm_release_stone() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "释放灵石"
	dialog.dialog_text = "消耗一块灵石，将其中的灵气释放到当前地点。"
	dialog.ok_button_text = "释放"
	add_child(dialog)
	dialog.confirmed.connect(func():
		action_requested.emit("release_spirit_stones",{"count":1})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func build(snapshot: Dictionary,tables: Dictionary,status: String,operations: RefCounted=null,messages: Array=[],saved_route: String="qi") -> void:
	state=snapshot;data=tables;service=operations;route=saved_route
	var location: String = _place(state.player.location)
	field("LocationDate").text="当前地点："+location
	field("WorldMap").tooltip_text="点击打开世界地图"
	_refresh_route()
	refresh_time(snapshot)
	_task();_buildings();_npcs();_messages(status,messages)

func _refresh_route() -> void:
	var p: Dictionary = state.player
	var body: bool = route=="body"
	var equipped_names: PackedStringArray = cultivation.equipped_techniques(p,route,data)
	var technique_text: String = "、".join(equipped_names)
	var missing: String = "请先装备炼体功法" if body else "请先装备法修功法"
	field("CurrentTechnique").text=missing if equipped_names.is_empty() else technique_text
	field("CurrentTechnique").tooltip_text=field("CurrentTechnique").text+"\n点击前往功法页调整"
	var safe: bool = p.location in ["town_qinglan","town_yunxi","cave_qinglan"]
	var reason: String = "请在安全地点修炼" if not safe else missing if equipped_names.is_empty() else ""
	field("Practice").text="淬体" if body else "修炼"
	field("Practice").disabled=not reason.is_empty();field("Practice").tooltip_text=reason
	field("ProgressTitle").text="炼体修为" if body else "法修修为"
	var focus: String = p.growth.focus[route]
	field("CultivationHint").text=FOCUS_HINTS[focus] if reason.is_empty() else reason
	_highlight(field("SpellPath"),not body)
	_highlight(field("BodyPath"),body)
	for key in FOCUS_BUTTONS:
		_highlight(field(key),FOCUS_BUTTONS[key]==focus)

func _highlight(button: Button, selected: bool) -> void:
	if selected:
		button.add_theme_stylebox_override("normal",get_theme_stylebox("hover","Button"))
	else:
		button.remove_theme_stylebox_override("normal")

func _clear(key: String) -> void:
	for child in field(key).get_children():field(key).remove_child(child);child.queue_free()
func _task() -> void:
	tracked=state.get("tracked_quest_id","")
	var api:=preload("res://gameplay/quest/quest_system.gd").new()
	var active: bool=data.quests.has(tracked) and api.status(state,tracked,data) in ["ACTIVE","READY_TO_TURN_IN"]
	field("TaskOpen").text=data.quests[tracked].title if active else "暂无追踪任务"
	field("TaskOpen").clip_text=true
	field("TaskHint").text="可前往任务页选择追踪任务";field("TaskProgress").text=""
	if not active:return
	var objective: Dictionary=api.current(state,tracked,data)
	field("TaskHint").text=objective.get("hint","前往发布者报告")
	field("TaskHint").tooltip_text=field("TaskHint").text
	if not objective.is_empty():
		field("TaskProgress").text="进度：%d / %d" % [api.objective_count(state,tracked,objective),objective.required_count]
func _entry(text: String,callback: Callable,reason: String="") -> void:
	var b:=Button.new();b.text=text;b.custom_minimum_size.y=48;b.clip_text=true;b.tooltip_text=reason if not reason.is_empty() else text
	b.disabled=not reason.is_empty();b.pressed.connect(callback);field("Buildings").add_child(b)
func _quote(action: String,args: Dictionary={}) -> String:
	if service==null:return ""
	var q: Dictionary=service.inventory_action_quote(action,args)
	return "" if q.success else q.message
func _buildings() -> void:
	_clear("Buildings")
	var location: String=state.player.location
	field("BuildingTitle").text="可交互地点" if location=="area_qinglan_outskirts" else "地点建筑"
	for shop in data.shops.values():
		if shop.location!=location:continue
		var npc: Dictionary=state.npcs[shop.npc_id]
		_entry(shop.name,func():shop_requested.emit(shop.id),"" if npc.alive and npc.location==location else "商人不在此处或已故")
	for auction in data.auctions.values():
		if auction.location==location:
			_entry(auction.name,func():auction_requested.emit(auction.id))
	if location in ["town_qinglan","town_yunxi"]:
		_entry("公告栏",func():navigate.emit("公告栏"))
		for inn in data.inns.values():
			if inn.location==location:_entry(inn.name,func():navigate.emit("客栈"))
		if location=="town_qinglan":
			var guard: Dictionary = state.npcs.get("npc_qin_shoushan", {})
			var available: bool = guard.get("alive", false) and guard.get("location", "") == location
			_entry("镇守府",func():npc_requested.emit("npc_qin_shoushan"),"" if available else "秦守山目前无法接见")
		else:
			var talisman_maker: Dictionary = state.npcs.get("npc_lu_zhifu", {})
			var available: bool = talisman_maker.get("alive", false) and talisman_maker.get("location", "") == location
			_entry("符箓阁",func():npc_requested.emit("npc_lu_zhifu"),"" if available else "陆知符目前不在阁内")
			_entry("天机楼",func():navigate.emit("天机楼"))
			_entry("宗门",func():navigate.emit("宗门"))
	elif location=="cave_qinglan":
		_entry("修炼室",func():navigate.emit("修炼"))
		for pair in [["洞府总览","Overview"],["灵田","Fields"],["炼丹房","Alchemy"]]:_entry(pair[0],func():cave_requested.emit(pair[1]))
		_entry("储物室",func():cave_requested.emit("WarehousePage"))
	elif location=="area_qinglan_outskirts":
		_entry("山外围探索",func():action_requested.emit("explore",{}))
		for definition in data.prototype.outskirts_routes:
			_entry(definition.name,func():action_requested.emit("explore",{"route":definition.id}),definition.get("unavailable",""))
		for event in data.events.values():
			if event.location_id==location:_entry("调查"+event.name,_investigate.bind(event.id))
		_entry("狼首挑战（建议二层+补给）",func():action_requested.emit("challenge",{}))
	elif not service.sect_at_location(location).is_empty():
		_entry("宗门驻地",func():navigate.emit("宗门驻地"),service.sect_residence_access(location))
func _investigate(id: String) -> void:
	var definition: Dictionary=data.events[id]
	var dialog:=ConfirmationDialog.new();add_child(dialog)
	dialog.title=definition.name;dialog.dialog_text=definition.description+"\n消耗 %d 小时" % definition.options[0].hours
	dialog.ok_button_text=definition.options[0].label
	dialog.confirmed.connect(func():action_requested.emit("investigate",{"id":id,"option":definition.options[0].id});dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(720,360))
func _npcs() -> void:
	_clear("Npcs")
	var count:=0
	for npc in state.npcs.values():
		if npc.location!=state.player.location or not npc.alive:continue
		if preload("res://world/npc_interaction.gd").sect_area_restricted(npc,data):continue
		count+=1
		var info: Dictionary = preload("res://world/npc_interaction.gd").new().presentation(state,data,npc.id)
		var b: Button = preload("res://ui/main/nearby_npc_card.tscn").instantiate()
		b.get_node("Content/Details/Heading/Name").text = info.name
		var badge: Label = b.get_node("Content/Details/Heading/Rank")
		badge.text = info.rank
		var colors := {"天骄":"9a5c14", "人杰":"74499d", "精英":"31678c", "良才":"28775b"}
		badge.add_theme_color_override("font_color", Color(colors.get(info.rank, "46645a")))
		b.get_node("Content/Details/Realm").text = info.realm
		var caption := "%s · %s" % [info.identity, info.relation.trim_prefix("关系：")]
		b.get_node("Content/Details/Caption").text = caption
		b.tooltip_text = "%s · %s\n%s\n%s" % [info.name, info.rank, info.realm, caption]
		b.pressed.connect(func():npc_requested.emit(npc.id));field("Npcs").add_child(b)
	if count==0:
		var empty:=Label.new();empty.text="附近暂无可交互人物";empty.add_theme_font_size_override("font_size",20);field("Npcs").add_child(empty)
	field("NpcTitle").text="附近人物　%d 人" % count
func _messages(status: String,messages: Array) -> void:
	_clear("Messages")
	var entries: Array=[]
	for i in range(state.news.size()-1,-1,-1):entries.append(str(state.news[i]))
	for entry in messages:entries.push_front(str(entry))
	if not status.is_empty() and (entries.is_empty() or entries[0]!=status):entries.push_front(status)
	if entries.is_empty():entries.append("暂无世界消息")
	for entry in entries:
		var label:=Label.new();label.custom_minimum_size.y=56;label.text=entry;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.max_lines_visible=2
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label.tooltip_text=entry;label.add_theme_font_size_override("font_size",20);field("Messages").add_child(label)
func _realm(value: int) -> String:
	return CULTIVATION.realm_name(value,"qi",data)
func _place(id: String) -> String:return preload("res://ui/world/world_page.gd").place_name(id,data)

func refresh_time(snapshot: Dictionary) -> void:
	state=snapshot
	var p: Dictionary = state.player
	var body: bool = route=="body"
	var clock=preload("res://core/time_system.gd").new()
	field("Identity").text="%s · %s / %s" % [p.name,_realm(int(p.realm)),cultivation.body_realm_name(p,data)]
	field("WorldTime").text=clock.format_date(state,data)
	field("Wallet").text="灵石 %d" % p.spirit_stones
	field("WorldMap").text="%s · %s" % [_place(p.location),spirit.grade(state,p.location,data)]
	var can_release: bool=spirit.stone_capacity(state,data)>0
	field("ReleaseStone").disabled=p.spirit_stones<=0 or not can_release or p.age>=p.lifespan
	field("ReleaseStone").tooltip_text="灵石不足" if p.spirit_stones<=0 else "当前灵气池无法容纳一块灵石的灵气" if not can_release else "消耗一块灵石，向当前地点释放灵气"
	var required: int = cultivation.requirement(p,route,data)
	var current: int = cultivation.progress(p,route)
	field("ProgressValue").text="%d / %d%s" % [current,required," · 请手动突破" if current>=required else ""] if required>0 else "已达当前境界上限"
	field("CultivationProgress").max_value=maxi(1,required);field("CultivationProgress").value=current
	field("Promote").tooltip_text=cultivation.breakthrough_summary(p,route,data)
	var mode: String = "practice" if body else "natural"
	var trained: bool = not cultivation.equipped_techniques(p,route,data).is_empty()
	var available: bool = trained and p.age<p.lifespan and (not body or not field("Practice").disabled)
	var cap: int = cultivation.attribute_cap(p,route,data)
	var names: Array = ["筋骨","体魄"] if body else ["气海","经脉"]
	var threshold: int = int(data.progression.nurture_per_point)
	var points: float = spirit.nurture_points(state,route,data)
	for index in range(2):
		var value: int = p.growth.attributes[CULTIVATION.GROWTH_ATTRIBUTES[route][index]]
		field("GrowthValue%d" % index).text="%s    %d / %d" % [names[index],value,cap]
		field("GrowthProgress%d" % index).text="温养积累：%.1f / %d" % [points,threshold] if value<cap else "已达当前属性上限"
	var estimate: Vector2=spirit.hourly_estimate(state,mode,route,data,cultivation) if available else Vector2.ZERO
	field("LocationAura").text="%s预计 %.3f 修为/时" % ["淬体" if body else "自然吐纳",estimate.x]
	field("LocationAura").tooltip_text="体修只在主动淬体和体修闭关时结算。" if body else "在线自动吐纳只积累法修。"
	field("NurtureRate").text="根基温养：约 %.3f/时" % estimate.y
	field("CultivationStatus").text=("主动淬体或体修闭关" if body else "在线自动吐纳") if trained else "未装备对应功法"
	if p.age>=p.lifespan:
		field("CultivationStatus").text="寿元已尽，修炼停止"
