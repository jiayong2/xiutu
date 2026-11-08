extends Control
signal closed
signal command(action: String,args: Dictionary)
const PANEL_SIZE := Vector2(1100,610)
const DISPLAY_SCALE := 1.5
var service: RefCounted
var npc_id: String
var api:=preload("res://world/npc_interaction.gd").new()
var sub_kind: String=""
var previous_option := ""
var profile: Control
var trade: Control
var trade_shop: String=""
var trade_state: Dictionary={}
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	resized.connect(_fit);_fit()
	field("Close").pressed.connect(close)
	field("Continue").pressed.connect(_main_options)
	for i in range(12):field("Action"+str(i)).pressed.connect(_interact.bind(api.OPTIONS[i]))
func bind_data(operations: RefCounted,id: String) -> void:
	service=operations;npc_id=id;refresh_data()
	# Initial container minimum sizes settle after entering the scene tree.
	call_deferred("_fit")
func refresh_data() -> void:
	var snapshot: Dictionary=service.snapshot()
	var info: Dictionary=api.presentation(snapshot,service.data,npc_id)
	if profile!=null and snapshot.npcs.has(npc_id):
		profile.bind_data(snapshot,service.data,npc_id)
	field("NpcName").text=info.name;field("Relation").text=info.relation;field("Realm").text=info.realm;field("Identity").text="身份："+info.identity
func _fit() -> void:
	var panel: Control=field("Panel")
	panel.size=PANEL_SIZE
	var factor: float=minf(DISPLAY_SCALE,minf((size.x-32)/PANEL_SIZE.x,(size.y-32)/PANEL_SIZE.y))
	panel.scale=Vector2.ONE*maxf(.1,factor);panel.position=(size-PANEL_SIZE*panel.scale)/2
func _feedback(text: String) -> void:field("Feedback").text=field("NpcName").text+"：\n"+text
func _interact(kind: String) -> void:
	var result: Dictionary=api.evaluate(service.snapshot(),service.data,npc_id,kind)
	if result.kind=="talk":
		previous_option=""
		sub_kind="talk";_subview()
		command.emit("talk",{"id":npc_id})
		_quest_options()
	elif result.kind=="quests":
		previous_option=""
		sub_kind="quests";_subview();_feedback(result.message);_quest_options()
	elif result.kind=="trade":
		_feedback(result.message);_trade(result.shop)
	elif result.kind=="info":
		profile=preload("res://ui/npc/npc_profile.tscn").instantiate()
		add_child(profile)
		profile.bind_data(service.snapshot(),service.data,npc_id)
		profile.closed.connect(_close_profile)
		field("Panel").hide()
	else:_feedback(result.message)
func _subview() -> void:
	field("Actions").hide();field("Subpanel").show();call_deferred("_fit")
func _main_options() -> void:
	sub_kind="";field("Subpanel").hide();field("Actions").show();call_deferred("_fit")
func _quest_options() -> void:
	for child in field("QuestOptions").get_children():field("QuestOptions").remove_child(child);child.queue_free()
	var result: Dictionary=api.evaluate(service.snapshot(),service.data,npc_id,"任务",previous_option)
	for option in result.get("options",[]):
		var button:=Button.new();button.text=option.label;button.custom_minimum_size.y=48;button.clip_text=true;button.tooltip_text=option.label
		button.pressed.connect(func():command.emit("npc_option",{"npc":npc_id,"option":option.id}));field("QuestOptions").add_child(button)
func receive(result: Dictionary, option_id: String="") -> void:
	if result.success and not option_id.is_empty():
		previous_option=option_id
	refresh_data();_feedback(result.message)
	if not sub_kind.is_empty():_quest_options()
	if trade!=null and is_instance_valid(trade):
		trade.bind_data(service,trade_shop,trade_state.get("mode","购买"),trade_state.get("category","全部"),trade_state.get("key",""),int(trade_state.get("quantity",1)),result.message)
func _trade(shop: String) -> void:
	trade_shop=shop
	trade=preload("res://ui/shop/shop_page.tscn").instantiate();add_child(trade)
	trade.navigate.connect(func(_destination: String):_close_trade())
	trade.action_requested.connect(func(action: String,args: Dictionary):command.emit(action,args))
	trade.selection_changed.connect(func(mode: String,category: String,key: String,quantity: int):trade_state={"mode":mode,"category":category,"key":key,"quantity":quantity})
	trade.bind_data(service,shop)
func _close_trade() -> void:
	if trade!=null and is_instance_valid(trade):remove_child(trade);trade.queue_free()
	trade=null
	call_deferred("_fit")
func _close_profile() -> void:
	remove_child(profile)
	profile.queue_free()
	profile=null
	field("Panel").show()
	field("Action10").grab_focus()

func back() -> void:
	if profile!=null:_close_profile()
	elif trade!=null and is_instance_valid(trade):_close_trade()
	elif not sub_kind.is_empty():_main_options()
	else:close()
func close() -> void:
	closed.emit()
	queue_free()
