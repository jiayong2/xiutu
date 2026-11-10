extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(selected: String,category: String)
signal npc_requested(id: String)
@export var task_item_scene: PackedScene=preload("res://ui/quest/task_list_item.tscn")
const HEADER_COLOR := Color("#85B8AD")
const TITLE_COLOR := "#274D46"
const TYPE_COLOR := "#547970"
const SUGGESTED_REALM_COLOR := "#A56B20"
const REWARD_COLOR := "#B77724"
const OBJECTIVE_COLOR := "#315E52"
const HINT_COLOR := "#6D8880"
const MUTED_COLOR := "#899B95"
const PROGRESS_COLOR := "#287F9C"
const ACTIVE_COLOR := "#2879A5"
const COMPLETED_COLOR := "#39834D"
const FAILURE_COLOR := "#B65B54"
var selected_id: String=""
var category: String="全部"
var state: Dictionary={}
var data: Dictionary={}
var quest_api:=preload("res://gameplay/quest/quest_system.gd").new()
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	var header: Control = field("Header")
	header.draw.connect(func(): header.draw_rect(Rect2(Vector2.ZERO, header.size), HEADER_COLOR))
	header.resized.connect(header.queue_redraw)
	field("Back").pressed.connect(func():navigate.emit("主界面"))
	for button in field("Filters").get_children():button.pressed.connect(_filter.bind(button.text))
	field("Primary").pressed.connect(_primary)
	field("Guide").pressed.connect(func():navigate.emit("地图"))
	field("Talk").pressed.connect(func():npc_requested.emit(data.quests[selected_id].giver_npc_id))
	field("Track").pressed.connect(func():action_requested.emit("track_quest",{"id":selected_id}))
	field("Abandon").pressed.connect(func():action_requested.emit("abandon_quest",{"id":selected_id}))
func bind_data(snapshot: Dictionary,tables: Dictionary,selected: String="",filter_name: String="全部",message: String="") -> void:
	state=snapshot;data=tables;selected_id=selected
	category=filter_name if filter_name in ["全部","进行中","已完成"] else "全部"
	field("Status").text=message;_refresh()
func _status_label(value: String) -> String:
	return {"LOCKED":"未解锁","AVAILABLE":"可接取","ACTIVE":"进行中","READY_TO_TURN_IN":"可交付","COMPLETED":"已完成","FAILED":"已失败","EXPIRED":"已过期"}.get(value,value)
func _status(id: String) -> String:return quest_api.status(state,id,data)
func _display_status(id: String, value: String) -> String:
	if value=="COMPLETED" and str(data.quests[id].get("repeat_rule",""))=="DAILY":return "今日已完成"
	return "进行中" if value=="READY_TO_TURN_IN" and data.quests[id].has("delivery_dialogue") else _status_label(value)
func _status_color(value: String) -> String:
	match value:
		"ACTIVE", "READY_TO_TURN_IN": return ACTIVE_COLOR
		"COMPLETED": return COMPLETED_COLOR
		"FAILED", "EXPIRED": return FAILURE_COLOR
		_: return MUTED_COLOR

func _ink(value: String, color: String) -> String:
	return "[color=%s]%s[/color]" % [color, value]

func _literal(value: String) -> String:
	return value.replace("[", "[lb]")

func _objective_description(objective: Dictionary) -> String:
	var description: String = objective.description
	if objective.objective_type in ["ITEM_POSSESSION", "ITEM_DELIVERY"]:
		var item_name: String = data.items[objective.target_id].name
		var amount := str(int(objective.required_count))
		for unit in ["份", "枚", "个", "件", ""]:
			var phrase: String = amount + unit + item_name
			if description.contains(phrase):
				return _literal(description).replace(_literal(phrase), _ink(_literal(phrase), REWARD_COLOR))
		return _literal(description).replace(_literal(item_name), _ink(_literal(item_name), REWARD_COLOR))
	return _literal(description)
func visible_ids() -> Array:
	var ids: Array=[]
	for id in data.quests:
		if not state.quests.has(id):
			continue
		var value:=_status(id)
		if value in ["LOCKED","AVAILABLE"]:
			continue
		if category=="全部" or category=="进行中" and value in ["ACTIVE","READY_TO_TURN_IN"] or category=="已完成" and value=="COMPLETED":ids.append(id)
	return ids
func _filter(value: String) -> void:category=value;_refresh()
func _select(id: String) -> void:selected_id=id;_refresh()
func _refresh() -> void:
	for filter in field("Filters").get_children():
		filter.theme_type_variation = &"TaskFilterSelected" if filter.text == category else &"TaskFilter"
	for child in field("TaskList").get_children():field("TaskList").remove_child(child);child.queue_free()
	var ids:=visible_ids()
	if selected_id not in ids:selected_id=str(ids[0]) if not ids.is_empty() else ""
	for id in ids:
		var button: Button=task_item_scene.instantiate();button.name=id
		var quest: Dictionary = data.quests[id]
		var status := _status(id)
		button.text="%s
%s · %s" % [quest.title,quest.quest_type,_display_status(id,status)]
		button.theme_type_variation = &"TaskRowSelected" if id == selected_id else &"TaskRow"
		button.get_node("Caption").text = "%s\n%s · %s" % [
			_ink("[b][font_size=21]%s[/font_size][/b]" % _literal(quest.title), TITLE_COLOR),
			_ink(_literal(quest.quest_type), TYPE_COLOR),
			_ink(_display_status(id,status), _status_color(status))
		]
		button.pressed.connect(_select.bind(id));field("TaskList").add_child(button)
	_detail();selection_changed.emit(selected_id,category)
func availability() -> Dictionary:
	if selected_id.is_empty():return {"text":"暂无任务","disabled":true,"action":"","reason":""}
	var value:=_status(selected_id)
	if data.quests[selected_id].completion_mode=="BOARD":
		return {"text":"返回公告栏交付" if value=="READY_TO_TURN_IN" else _status_label(value),"disabled":true,"reason":"","action":""}
	if value in ["AVAILABLE","LOCKED","FAILED"]:
		var error: String=quest_api.requirement_error(state,selected_id,data)
		var via_dialogue: bool=data.quests[selected_id].has("delivery_dialogue")
		return {"text":"前往人物对话" if via_dialogue else "接取任务","disabled":not error.is_empty(),"reason":error,"action":"report" if via_dialogue else "accept"}
	return {"text":"向发布者交付" if value=="READY_TO_TURN_IN" else "进行中" if value=="ACTIVE" else _status_label(value),"disabled":value!="READY_TO_TURN_IN","reason":"","action":"report"}
func _detail() -> void:
	var empty:=selected_id.is_empty()
	field("DetailScroll").visible=not empty
	for key in ["Guide","Talk","Track","Abandon"]:field(key).visible=not empty
	var status := "" if empty else _status(selected_id)
	var title: String = "暂无任务" if empty else data.quests[selected_id].title
	field("TaskTitle").text = _ink("[b]%s[/b]" % _literal(title), TITLE_COLOR)
	if not empty:
		field("TaskTitle").text += " · " + _ink("[b]%s[/b]" % _display_status(selected_id,status), _status_color(status))
	var available:=availability()
	field("Primary").text=available.text;field("Primary").disabled=available.disabled;field("ActionReason").text=available.reason
	field("ActionReason").visible=not available.reason.is_empty()
	if empty:return
	field("Talk").visible=_status(selected_id) in ["ACTIVE","READY_TO_TURN_IN"]
	var q: Dictionary=data.quests[selected_id]
	field("TaskType").text = _ink(_literal(q.quest_type), TYPE_COLOR)
	if q.recommended_realm > 0:
		field("TaskType").text += " · " + _ink("建议炼气%d层" % q.recommended_realm, SUGGESTED_REALM_COLOR)
	field("Description").text=q.description
	var separate_clue: bool=q.has("delivery_dialogue") or q.has("dialogue") or q.completion_mode=="BOARD" and q.objectives.size()==1
	if q.completion_mode=="BOARD":
		field("Talk").hide()
	var clue: String=q.objectives[0].hint if separate_clue else ""
	field("ClueHeading").visible=not clue.is_empty()
	field("Clue").visible=not clue.is_empty()
	field("Clue").text=clue
	var lines: Array[String]=[]
	for o in q.objectives:
		var r: Dictionary=state.quests.get(selected_id,{}).get("objectives",{}).get(o.objective_id,{"status":"INACTIVE","current_count":0})
		var marker: String = {"INACTIVE":"未激活","ACTIVE":"当前目标","COMPLETED":"已完成"}.get(r.status,r.status)
		var progress_color: String = {"INACTIVE":MUTED_COLOR,"ACTIVE":PROGRESS_COLOR,"COMPLETED":COMPLETED_COLOR,"FAILED":FAILURE_COLOR}.get(r.status,MUTED_COLOR)
		if status in ["FAILED", "EXPIRED"] and r.status == "ACTIVE":
			progress_color = FAILURE_COLOR
		var line := "%s %s %s" % [
			_ink(_objective_description(o), OBJECTIVE_COLOR),
			"" if separate_clue else _ink(_literal("[%s]" % marker), progress_color),
			_ink("%d/%d" % [quest_api.objective_count(state,selected_id,o),o.required_count], progress_color)
		]
		if not separate_clue:
			line += "\n" + _ink("[font_size=18]%s[/font_size]" % _literal(o.hint), HINT_COLOR)
		lines.append(line)
	field("Objective").text="

".join(lines)
	var current: Dictionary=quest_api.current(state,selected_id,data)
	var npc: Dictionary=state.npcs.get(q.giver_npc_id,{})
	field("Related").text="发布者：%s · %s
%s" % [npc.get("name","无"),_place(npc.get("location","")),"人物已故，暂不可接触" if not npc.get("alive",false) else "目标地点："+_place(current.get("target_location_id",""))]
	if q.has("turn_in_label"):
		field("Related").text="发布者：%s\n交付地点：%s" % [npc.get("name","无"),q.turn_in_label]
		if not npc.get("alive",false):field("Related").text+="\n人物已故，暂不可接触"
	if q.has("delivery_shop_id"):
		var shop: Dictionary=data.shops[q.delivery_shop_id]
		field("Related").text="委托人：%s\n交付地点：%s · %s" % [npc.get("name","无"),_place(shop.location),shop.name]
		if not npc.get("alive",false):
			field("Related").text+="\n人物已故，暂不可接触"
	if q.completion_mode=="BOARD":
		for row in data.announcements.values():
			if row.get("quest_id","")==q.id:
				var board_name := _place(row.town_id) + "公告栏"
				field("Related").text="委托来源：%s\n交付地点：%s" % [board_name,board_name]
				break
	if not separate_clue and available.reason.is_empty():
		field("ActionReason").text=current.get("hint","可自由探索或查看其他任务")
	field("Talk").text="前往人物对话"
	field("Talk").disabled=npc.is_empty() or not npc.get("alive",false) or npc.get("location","")!=state.player.location
	field("Talk").tooltip_text="请先移动到发布者当前所在地点" if field("Talk").disabled else ""
	if not current.is_empty() and current.objective_type in ["TALK_OPTION","REPORT_NPC","ITEM_DELIVERY"] and not current.target_location_id.is_empty() and npc.get("location","")!=current.target_location_id:
		field("Related").text+="\n发布者已离开目标地点，请留意其行踪，返回目标地点后再交谈。"
	if _status(selected_id)=="FAILED":field("ActionReason").text=state.quests[selected_id].get("failure_reason","任务已放弃，可重新接取")
	field("ActionReason").visible=not field("ActionReason").text.is_empty()
	field("Track").text="已追踪" if state.get("tracked_quest_id","")==selected_id else "追踪任务"
	field("Abandon").disabled=_status(selected_id) not in ["ACTIVE","READY_TO_TURN_IN"]
	var rewards: Array[String] = ["灵石 " + _ink("×%d" % q.money, REWARD_COLOR)]
	if int(q.get("contribution",0))>0:rewards.append("宗门贡献 " + _ink("×%d" % int(q.contribution), REWARD_COLOR))
	for id in q.rewards:
		rewards.append(_literal(data.items[id].name) + " " + _ink("×%d" % q.rewards[id], REWARD_COLOR))
	field("Rewards").text="
".join(rewards)
func _primary() -> void:
	var available:=availability()
	if available.disabled:return
	if available.action=="report":npc_requested.emit(data.quests[selected_id].giver_npc_id)
	else:action_requested.emit(available.action,{"id":selected_id})
func _place(id: String) -> String:
	return {"town_qinglan":"青岚镇","town_yunxi":"云溪城","cave_qinglan":"青岚小洞府","area_qinglan_outskirts":"青岚山外围","sect_qingyue_gate":"青岳山门","":"无指定地点"}.get(id,id)
