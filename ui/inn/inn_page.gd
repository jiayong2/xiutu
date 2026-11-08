extends Control
signal navigate(destination: String)
signal npc_requested(id: String)
signal action_requested(action: String,args: Dictionary,operation_id: String)
signal feedback(text: String)
var service: RefCounted
var state: Dictionary
var data: Dictionary
var inn: Dictionary
var tab: String="home"
var messages: Array=[]
var submitted:=false
var operation_id: String=""
var room_id: String=""
var rumor_detail: String=""
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():navigate.emit("地点场景"))
	for pair in [["Stay","stay"],["Meal","meal"],["Rumors","rumors"],["Observe","observe"]]:field(pair[0]).pressed.connect(_tab.bind(pair[1]))
	field("ReturnHome").pressed.connect(_tab.bind("home"))
	field("NpcTalk").pressed.connect(func():
		var id: String=field("NpcTalk").get_meta("npc","")
		if not id.is_empty():npc_requested.emit(id))
func bind_data(operations: RefCounted,id: String,history: Array) -> void:
	service=operations;data=service.data;inn=data.inns[id];refresh_data(history)
func refresh_data(history: Array) -> void:
	messages=history.duplicate();state=service.snapshot()
	var p: Dictionary=state.player
	var place: String=preload("res://ui/world/world_page.gd").PLACES[inn.location]
	field("Identity").text="%s · %s" % [p.name,preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(p.realm,"qi",data)]
	field("Location").text="当前位置：%s · %s" % [place,inn.name]
	field("Wallet").text="灵石 %d" % p.spirit_stones
	field("WorldTime").text=preload("res://core/time_system.gd").new().format_date(state,data)
	field("ShopName").text=inn.name;field("CenterTitle").text=inn.name
	field("ShopState").text=inn.inn_type+" · "+("营业中" if p.location==inn.location else "不在此地点")
	field("Introduction").text=inn.description
	var owner: Dictionary=state.npcs.get(inn.owner_npc_id,{})
	field("Announcement").text="客栈状态\n掌柜：%s\n住宿：%s\n历史传闻：%d条" % [owner.get("name","暂无人物资料"),"提供客房" if inn.available_rooms.any(func(room):return room.available) else "暂无可用客房",state.news.size()]
	field("Environment").text=inn.scene_description
	field("Back").text="返回"+place
	_clear("Npcs");var ids: Array=[]
	for npc in state.npcs.values():
		if not npc.alive or npc.location!=p.location or p.location!=inn.location:continue
		if npc.id not in inn.npc_list and npc.id!=inn.owner_npc_id and npc.get("inn_id","")!=inn.id:continue
		ids.append(npc.id)
		var button:=Button.new();button.text=preload("res://world/npc_interaction.gd").new().summary(state,data,npc.id);button.custom_minimum_size.y=84;button.clip_text=true;button.tooltip_text=button.text
		button.add_theme_font_size_override("font_size",22);button.pressed.connect(func():npc_requested.emit(npc.id));field("Npcs").add_child(button)
	field("NpcTitle").text="附近人物 · %d人" % ids.size()
	field("NpcInfo").text="附近暂无人物" if ids.is_empty() else "点击人物打开统一交互"
	field("NpcTalk").visible=false
	_clear("Messages")
	var entries: Array=state.news.duplicate()+messages
	if entries.is_empty():entries.append("暂无世界消息")
	for i in range(entries.size()-1,-1,-1):_text("Messages",str(entries[i]))
	if tab=="rumors":_render_secondary()
func _clear(key: String) -> void:
	for child in field(key).get_children():field(key).remove_child(child);child.queue_free()
func _text(key: String,text: String) -> Label:
	var label:=Label.new();label.text=text;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.y=64;label.tooltip_text=text;label.add_theme_font_size_override("font_size",20);field(key).add_child(label);return label
func _tab(value: String) -> void:
	tab=value
	field("HomeContent").visible=tab=="home";field("Secondary").visible=tab!="home"
	if tab=="stay":
		submitted=false;operation_id="inn_ui_"+str(Time.get_ticks_usec());room_id=""
	if tab!="home":_render_secondary()
	if tab=="observe":feedback.emit("观察"+inn.name+"："+inn.observation)
func _render_secondary() -> void:
	_clear("SecondaryBody")
	field("SecondaryTitle").text={"stay":"住宿","meal":"用膳","rumors":"打听消息","observe":"观察客栈"}.get(tab,"")
	match tab:
		"stay":
			var select:=OptionButton.new();select.name="RoomSelect";field("SecondaryBody").add_child(select)
			for room in inn.available_rooms:
				select.add_item(room.name);select.set_item_metadata(select.item_count-1,room.id)
			if select.item_count==0:_text("SecondaryBody","暂无可用房型");return
			room_id=str(select.get_item_metadata(0))
			select.item_selected.connect(func(index: int):room_id=str(select.get_item_metadata(index));_stay_preview())
			var preview:=Label.new();preview.name="StayPreview";preview.custom_minimum_size.y=128;preview.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;field("SecondaryBody").add_child(preview)
			var confirm:=Button.new();confirm.name="ConfirmStay";confirm.text="确认入住";confirm.custom_minimum_size.y=56;confirm.disabled=submitted
			confirm.pressed.connect(_confirm_stay);field("SecondaryBody").add_child(confirm)
			_text("SecondaryBody","其他房型暂未开放。")
			_stay_preview()
		"meal":_text("SecondaryBody","用膳尚未开放，菜单与效果待确认。")
		"rumors":
			_text("SecondaryBody","以下为往日见闻，仅作历史记录，不代表当前仍在发生。")
			for i in range(state.news.size()-1,-1,-1):
				var text: String=str(state.news[i])
				var button:=Button.new();button.text=text;button.clip_text=true;button.custom_minimum_size.y=56;button.tooltip_text=text
				button.pressed.connect(func():rumor_detail=text;feedback.emit("获知公开历史记录："+text));field("SecondaryBody").add_child(button)
			var info:=Button.new();info.text="住宿说明（静态资料）";info.custom_minimum_size.y=56
			info.pressed.connect(func():rumor_detail="住宿需花费灵石和时间，可恢复生命与灵力。听闻消息不会自动接取任务。";_render_secondary());field("SecondaryBody").add_child(info)
			if not rumor_detail.is_empty():_text("SecondaryBody",rumor_detail)
		"observe":_text("SecondaryBody",inn.observation)
func _stay_preview() -> void:
	var st: Dictionary=service.stats()
	field("StayPreview").text="价格：%d 灵石\n时间：%d 日\n生命恢复至 %d；灵力恢复至 %d；不增加修为。" % [data.rules.inn_cost,data.rules.inn_days,st.hp,st.mp]
func _confirm_stay() -> void:
	if submitted:return
	submitted=true;field("ConfirmStay").disabled=true
	action_requested.emit("inn_stay",{"inn":inn.id,"room":room_id},operation_id)
func receive(result: Dictionary,history: Array) -> void:
	refresh_data(history)
	_text("SecondaryBody",result.message)
	if not result.success:
		submitted=false
		if field("ConfirmStay")!=null:field("ConfirmStay").disabled=false
func back() -> void:
	if tab!="home":_tab("home")
	else:navigate.emit("地点场景")
