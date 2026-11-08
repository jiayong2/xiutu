extends Control
signal navigate(destination: String)
signal trade_requested(mode: String)
signal dialogue_requested(id: String)
signal observation(text: String)
var selected_npc: String=""
var shop: Dictionary
var data: Dictionary
var state: Dictionary
func field(id: String) -> Node:return find_child(id,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():navigate.emit("地点场景"))
	field("Buy").pressed.connect(func():trade_requested.emit("购买"))
	field("Sell").pressed.connect(func():trade_requested.emit("出售"))
	field("KeeperTalk").pressed.connect(func():dialogue_requested.emit(shop.npc_id))
	field("NpcTalk").pressed.connect(func():dialogue_requested.emit(selected_npc))
	field("Observe").pressed.connect(func():observation.emit(shop.get("environment","暂无环境描述")))
func bind_data(snapshot: Dictionary,tables: Dictionary,id: String,messages: Array) -> void:
	state=snapshot;data=tables;shop=data.shops[id]
	var p: Dictionary=state.player
	field("Identity").text="%s · %s" % [p.name,preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(p.realm,"qi",data)]
	var place: String=preload("res://ui/world/world_page.gd").PLACES[shop.location]
	field("Location").text="当前位置：%s · %s" % [place,shop.name]
	field("Wallet").text="灵石 %d" % p.spirit_stones
	field("WorldTime").text=preload("res://core/time_system.gd").new().format_date(state,data)
	field("ShopName").text=shop.name;field("CenterTitle").text=shop.name
	var keeper: Dictionary=state.npcs[shop.npc_id]
	var open: bool=keeper.alive and keeper.location==shop.location and p.location==shop.location
	field("ShopState").text=shop.get("shop_type","类型未定义")+" · "+("营业中" if open else "掌柜不在或无法营业")
	field("Introduction").text=shop.get("description","暂无店铺介绍")
	field("Announcement").text="店铺公告\n\n"+str(shop.get("announcement","暂无公告"))
	field("Environment").text=shop.get("environment","暂无环境描述")
	field("Back").text="返回"+place
	for key in ["Buy","Sell","KeeperTalk"]:
		field(key).disabled=not open
		field(key).tooltip_text="" if open else "掌柜不在此处或已故"
	for key in ["Npcs","Messages"]:
		for child in field(key).get_children():field(key).remove_child(child);child.queue_free()
	var ids: Array=[]
	for npc in state.npcs.values():
		if not npc.alive or npc.location!=shop.location or p.location!=shop.location:continue
		if npc.id!=shop.npc_id and npc.get("shop_id","")!=id:continue
		ids.append(npc.id)
		var button:=Button.new();button.text=preload("res://world/npc_interaction.gd").new().summary(state,data,npc.id)
		button.custom_minimum_size.y=84;button.clip_text=true;button.tooltip_text=button.text;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.add_theme_font_size_override("font_size",22);button.pressed.connect(_select.bind(npc.id));field("Npcs").add_child(button)
	field("NpcTitle").text="附近人物 · %d人" % ids.size()
	selected_npc=selected_npc if selected_npc in ids else shop.npc_id if shop.npc_id in ids else str(ids[0]) if not ids.is_empty() else ""
	_select(selected_npc)
	var entries: Array=messages.duplicate()
	for i in range(state.news.size()-1,-1,-1):entries.push_front(state.news[i])
	if entries.is_empty():entries.append("暂无世界消息")
	for i in range(entries.size()-1,-1,-1):
		var label:=Label.new();label.text=str(entries[i]);label.custom_minimum_size.y=56;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.max_lines_visible=2;label.tooltip_text=label.text;label.add_theme_font_size_override("font_size",20);field("Messages").add_child(label)
func _select(id: String) -> void:
	selected_npc=id
	field("NpcTalk").disabled=id.is_empty()
	field("NpcInfo").text="暂无店内人物" if id.is_empty() else state.npcs[id].name+"\n"+("店主" if id==shop.npc_id else "店内人物")
