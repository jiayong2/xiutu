extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(category: String,key: String)
const HOVER := preload("res://ui/character/equipment_hover.gd")
const CATEGORIES: Array[String]=["全部","丹药","功法","法术","装备","材料","任务物品"]
var service: RefCounted
var inventory_holder: Dictionary
var read_only := false
var data: Dictionary
var category: String="全部"
var selected: String=""
var return_page: String="主界面"
var entries: Dictionary={}
var item_tiles: Dictionary={}
var command: String=""
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():navigate.emit(return_page))
	for i in range(CATEGORIES.size()):field("Category%d" % i).pressed.connect(_category.bind(CATEGORIES[i]))
	field("Action").pressed.connect(_act)
	field("ItemScroll").resized.connect(_columns)
func bind_data(operations: RefCounted,saved_category: String="全部",key: String="",source: String="主界面",message: String="") -> void:
	service=operations;inventory_holder=service.snapshot().player;data=service.data;category=saved_category;selected=key;return_page=source
	read_only = false
	field("Title").text = "背包"
	field("Wallet").show()
	field("Wallet").text="灵石：%d" % inventory_holder.spirit_stones;field("Message").text=message
	_refresh()
func bind_npc(operations: RefCounted, npc: Dictionary, saved_category: String, key: String) -> void:
	service = operations
	data = service.data
	inventory_holder = npc
	category = saved_category
	selected = key
	return_page = "人物互动"
	read_only = true
	field("Title").text = "%s的背包" % npc.get("name", "人物")
	field("Wallet").hide()
	field("Message").text = ""
	_refresh()
func _columns() -> void:
	field("ItemGrid").columns=maxi(1,int((field("ItemScroll").size.x-16+8)/(144+8)))
func _category(value: String) -> void:
	if category==value:return
	category=value
	_refresh()
func _select(key: String) -> void:
	if key==selected:return
	if item_tiles.has(selected):_style(item_tiles[selected],false)
	selected=key
	_style(item_tiles[selected],true)
	_detail();selection_changed.emit(category,selected)
func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()
func _style(node: Control,active: bool) -> void:
	var style:=StyleBoxFlat.new();style.bg_color=Color("70988a") if active else Color("415b67")
	node.add_theme_stylebox_override("normal",style)
	var hover:=style.duplicate();hover.bg_color=style.bg_color.lightened(.1);node.add_theme_stylebox_override("hover",hover)
func _refresh() -> void:
	entries.clear();item_tiles.clear()
	var items: Dictionary = inventory_holder.get("inventory", {})
	var equipment: Dictionary = inventory_holder.get("equipment_instances", {})
	var equipped: Array = inventory_holder.get("equipped", {}).values() if not read_only else []
	for id in items:
		var count: int=int(items[id])
		var stack: int=int(data.items[id].stack_limit)
		var index:=0
		while count>0:
			var key: String="%s:%d" % [id,index]
			entries[key]={"id":id,"quantity":mini(count,stack),"total":items[id],"instance":""}
			count-=stack;index+=1
	for instance in equipment:
		entries["instance:"+instance]={"id":equipment[instance],"quantity":1,"total":1,"instance":instance}
	var visible_keys: Array=[]
	for key in entries:
		if category=="全部" or service.inventory.display_category(entries[key].id,data)==category:visible_keys.append(key)
	if selected not in visible_keys:selected=""
	for i in range(CATEGORIES.size()):_style(field("Category%d" % i),CATEGORIES[i]==category)
	_clear(field("ItemGrid"))
	for key in visible_keys:
		var entry: Dictionary=entries[key]
		var tile: Button=preload("res://ui/character/inventory_item_slot.tscn").instantiate()
		tile.custom_minimum_size=Vector2(144,152);tile.size_flags_horizontal=Control.SIZE_FILL
		tile.add_theme_font_size_override("font_size",20)
		tile.text="

%s
×%d%s" % [data.items[entry.id].name,entry.quantity," · 已装备" if entry.instance in equipped else ""]
		tile.tooltip_text=data.items[entry.id].name;_style(tile,key==selected);tile.pressed.connect(_select.bind(key))
		if data.equipment.has(entry.id):
			HOVER.attach(tile,data.equipment[entry.id],inventory_holder,entry.instance,data.rules)
		field("ItemGrid").add_child(tile)
		item_tiles[key]=tile
	if visible_keys.is_empty():
		var empty:=Label.new();empty.text="当前分类没有物品";field("ItemGrid").add_child(empty)
	_columns();_detail();selection_changed.emit(category,selected)
func _detail() -> void:
	field("Action").visible=false;field("Action").disabled=true;command=""
	field("Icon").visible=not selected.is_empty()
	field("Reason").text=""
	if selected.is_empty():
		field("ItemName").text="请选择物品";field("ItemType").text="";field("ItemQuantity").text="";field("Description").text="点击物品查看详情";return
	var entry: Dictionary=entries[selected]
	var item: Dictionary=data.items[entry.id]
	var display: String=service.inventory.display_category(entry.id,data)
	field("ItemName").text=item.name;field("ItemType").text="类型："+display
	field("ItemQuantity").text="当前数量：%d" % entry.quantity
	var lines: Array[String]=[item.description]
	if int(entry.total)>int(entry.quantity):lines.append("同类持有：%d" % entry.total)
	var effect: Variant=item.use_effect
	if not entry.instance.is_empty() and data.equipment.has(entry.id):
		var definition: Dictionary=data.equipment[entry.id]
		lines.append_array(HOVER.details(definition,inventory_holder,entry.instance,data.rules))
		if not read_only:
			var equipped: bool=entry.instance in inventory_holder.equipped.values()
			command="unequip" if equipped else "equip";field("Action").text="卸下" if equipped else "装备"
	elif display in ["丹药","功法","法术"]:
		if not read_only:
			command="use_item";field("Action").text="学习" if display in ["功法","法术"] else "使用"
		if effect is Dictionary and effect.has("learn"):
			var definition: Dictionary=data.techniques.get(effect.learn,data.spells.get(effect.learn,{}))
			lines.append("学习："+str(definition.name))
			if not read_only:
				lines.append("已学习" if inventory_holder.techniques.has(effect.learn) or inventory_holder.spells.has(effect.learn) else "尚未学习")
		elif effect is Dictionary and effect.has("stat"):lines.append("恢复%s %d" % ["生命" if effect.stat=="hp" else "灵力",effect.amount])
	field("Description").text="

".join(lines)
	if not command.is_empty():
		var result: Dictionary=service.inventory_action_quote(command,{"id":entry.instance if not entry.instance.is_empty() else entry.id})
		field("Action").visible=true;field("Action").disabled=not result.success
		_style(field("Action"),true)
		field("Reason").text="" if result.success else result.message
func _act() -> void:
	if selected.is_empty() or field("Action").disabled or command.is_empty():return
	var entry: Dictionary=entries[selected]
	action_requested.emit(command,{"id":entry.instance if not entry.instance.is_empty() else entry.id})
