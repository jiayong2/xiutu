extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(mode: String,category: String,key: String,quantity: int)
const HOVER := preload("res://ui/character/equipment_hover.gd")
@export var row_height: int = 64
var mode: String="购买"
var category: String="全部"
var selected: String=""
var quantity: int=1
var shop_id: String
var state: Dictionary
var data: Dictionary
var service: RefCounted
var entries: Dictionary={}
var quotes: Dictionary={}
var item_rows: Dictionary={}
func field(id: String) -> Node:return find_child(id,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():navigate.emit("地点场景"))
	field("Buy").pressed.connect(_mode.bind("购买"));field("Sell").pressed.connect(_mode.bind("出售"))
	field("Minus").pressed.connect(_quantity.bind(-1));field("Plus").pressed.connect(_quantity.bind(1))
	field("Maximum").pressed.connect(func():quantity=maxi(1,int(quotes.get(selected,{}).get("maximum",0)));_detail();_remember())
	field("Confirm").pressed.connect(_confirm)
func bind_data(operations: RefCounted,id: String,saved_mode: String="购买",saved_category: String="全部",key: String="",count: int=1,message: String="") -> void:
	service=operations;state=service.snapshot();data=service.data;shop_id=id
	mode=saved_mode;category=saved_category;selected=key;quantity=count
	field("ShopName").text=data.shops[id].name;field("Wallet").text="灵石 %d" % state.player.spirit_stones
	field("Status").text=message;_refresh()
func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()
func _refresh() -> void:
	entries.clear();quotes.clear();item_rows.clear()
	var source: Dictionary=state.stocks[shop_id] if mode=="购买" else state.player.inventory
	for id in source:
		if mode=="出售" and source[id]<=0:continue
		entries[id]={"item":id,"count":int(source[id]),"instance":""}
	if mode=="出售":
		for instance in state.player.equipment_instances:entries[instance]={"item":state.player.equipment_instances[instance],"count":1,"instance":instance}
	var categories: Array=["全部"]
	for entry in entries.values():
		var type: String=data.items[entry.item].type
		if type not in categories:categories.append(type)
	if category not in categories:category="全部"
	_clear(field("Categories"))
	for value in categories:
		var button:=Button.new();button.text=value;button.custom_minimum_size.y=48
		button.modulate=Color.WHITE if value==category else Color("9fafb8")
		button.pressed.connect(_category.bind(value));field("Categories").add_child(button)
	var visible_keys:=[]
	for key in entries:
		if category=="全部" or data.items[entries[key].item].type==category:visible_keys.append(key)
	if selected not in visible_keys:selected=str(visible_keys[0]) if not visible_keys.is_empty() else "";quantity=1
	_clear(field("ItemList"))
	for key in visible_keys:
		var entry: Dictionary=entries[key]
		var unit: int=service.shop.unit_price(state,data,shop_id,entry.item,mode=="购买")
		var button:=Button.new();button.name="Item_"+key;button.custom_minimum_size.y=row_height
		var style:=StyleBoxFlat.new();style.bg_color=Color("4d776e") if key==selected else Color("344c56")
		button.add_theme_stylebox_override("normal",style)
		var row:=HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);row.offset_left=8;row.offset_right=-8
		row.add_theme_constant_override("separation",16);button.add_child(row)
		for i in range(4):
			if i==0:
				var icon:=ColorRect.new();icon.color=Color("809ba3");icon.custom_minimum_size=Vector2(40,40)
				icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
				row.add_child(icon);continue
			var label:=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE
			label.text=["□",data.items[entry.item].name,str(unit),str(entry.count)][i]
			if i==1:
				label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			else:label.custom_minimum_size.x=field("PriceHeading" if i==2 else "CountHeading").custom_minimum_size.x
			row.add_child(label)
		if data.equipment.has(entry.item):
			HOVER.attach(button,data.equipment[entry.item],state.player,entry.instance,data.rules)
		button.pressed.connect(_select.bind(key));field("ItemList").add_child(button)
		item_rows[key]=button
	if visible_keys.is_empty():
		var empty:=Label.new();empty.text="此分类暂无商品";field("ItemList").add_child(empty)
	field("CountHeading").text="库存" if mode=="购买" else "持有"
	field("Buy").modulate=Color.WHITE if mode=="购买" else Color("9fafb8")
	field("Sell").modulate=Color.WHITE if mode=="出售" else Color("9fafb8")
	_detail();_remember()
func _detail() -> void:
	var empty:=selected.is_empty()
	field("Information").visible=not empty
	field("Confirm").text="确认购买" if mode=="购买" else "确认出售"
	if empty:
		field("DetailTitle").text="请选择商品";field("Reason").text="此分类暂无商品";field("Confirm").disabled=true
		field("Total").text="总价：—";field("Minus").disabled=true;field("Plus").disabled=true;field("Maximum").disabled=true;return
	field("DetailTitle").text="商品详情"
	var entry: Dictionary=entries[selected]
	var item: Dictionary=data.items[entry.item]
	if not quotes.has(selected):
		quotes[selected]=service.trade_quote(shop_id,entry.item,mode=="购买",1,entry.instance)
	var maximum: int=int(quotes[selected].maximum)
	quantity=clampi(quantity,1,maxi(1,maximum))
	field("ItemName").text=item.name;field("ItemType").text=item.type;field("Description").text=item.description
	var effects:=[]
	if item.use_effect is Dictionary:
		if item.use_effect.has("stat"):effects.append("恢复%s %d" % ["生命" if item.use_effect.stat=="hp" else "灵力",item.use_effect.amount])
		elif item.use_effect.has("learn"):
			var target: String=item.use_effect.learn
			var definition: Dictionary=data.techniques.get(target,data.spells.get(target,{}))
			effects.append("学习："+str(definition.get("name",target)))
	if data.equipment.has(entry.item):
		effects.append_array(HOVER.details(data.equipment[entry.item],state.player,entry.instance,data.rules))
	field("Effect").text="\n".join(effects)
	field("UnitPrice").text="单价：%d 灵石" % quotes[selected].unit
	field("Holding").text="%s：%d · 当前持有：%d" % ["库存" if mode=="购买" else "可出售数量",entry.count,state.player.inventory.get(entry.item,0) if entry.instance.is_empty() else 1]
	field("Quantity").text=str(quantity);field("Total").text="总价：%d 灵石" % (int(quotes[selected].unit)*quantity)
	field("Confirm").disabled=maximum<1
	field("Reason").text=quotes[selected].reason if maximum<1 else "这是任务材料，出售前需确认" if quotes[selected].confirmation else ""
	field("Minus").disabled=quantity<=1;field("Plus").disabled=quantity>=maximum;field("Maximum").disabled=maximum<1
func _mode(value: String) -> void:mode=value;category="全部";selected="";quantity=1;_refresh()
func _category(value: String) -> void:
	quantity=1
	if category==value:
		_detail();_remember()
		return
	category=value
	_refresh()
func _select(key: String) -> void:
	if key!=selected:
		_set_row_selected(selected,false)
		selected=key
		_set_row_selected(selected,true)
	quantity=1
	_detail();_remember()
func _set_row_selected(key: String,active: bool) -> void:
	if item_rows.has(key):
		var style: StyleBoxFlat=item_rows[key].get_theme_stylebox("normal")
		style.bg_color=Color("4d776e") if active else Color("344c56")
func _quantity(delta: int) -> void:quantity+=delta;_detail();_remember()
func _remember() -> void:selection_changed.emit(mode,category,selected,quantity)
func _confirm() -> void:
	if selected.is_empty() or field("Confirm").disabled:return
	var entry: Dictionary=entries[selected]
	var args: Dictionary={"shop":shop_id,"item":entry.item,"quantity":quantity}
	var action: String="buy" if mode=="购买" else "sell"
	if not entry.instance.is_empty():action="sell_equipment";args.id=entry.instance
	action_requested.emit(action,args)
