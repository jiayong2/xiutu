extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(mode: String,key: String)
var service: RefCounted
var mode := "techniques"
var selected := ""
var data: Dictionary
@onready var spell_page: Control = $SpellPage
func field(key: String) -> Node:
	if mode=="spells":
		var spell_field: Node=spell_page.field(key)
		if spell_field!=null:return spell_field
	return $Margin.find_child(key,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():navigate.emit("主界面"))
	field("Techniques").pressed.connect(_mode.bind("techniques"))
	field("Spells").pressed.connect(_mode.bind("spells"))
	field("Equip").pressed.connect(_act.bind("slot"))
	field("Upgrade").pressed.connect(_act.bind("upgrade"))
	spell_page.techniques_requested.connect(_mode.bind("techniques"))
	spell_page.back_requested.connect(func():navigate.emit("主界面"))
	spell_page.selected_changed.connect(func(id: String): selected=id;selection_changed.emit(mode,id))
func bind_data(operations: RefCounted,category: String,key: String,message: String) -> void:
	service=operations;data=service.data;mode=category;selected=key
	$Margin.find_child("Status").text=message
	_refresh(message)
func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()
func _mode(value: String) -> void:
	mode=value;selected="";_refresh()
func _select(key: String) -> void:
	selected=key;_refresh()
func _refresh(message: String = "") -> void:
	$Margin.visible=mode=="techniques"
	spell_page.visible=mode=="spells"
	if mode=="spells":
		spell_page.bind_data(service,selected,message)
		return
	var p: Dictionary=service.snapshot().player
	var learned: Dictionary=p.techniques
	var slots: Array=p.technique_slots
	var opened: int=int(data.rules.initial_slots)
	if not learned.has(selected):selected=str(learned.keys()[0]) if not learned.is_empty() else ""
	field("SlotTitle").text="已装备功法 · %d / %d" % [slots.size(),opened]
	field("SlotHint").text="功法上限10槽；未开放槽位暂无解锁规则"
	field("ListTitle").text="已学习功法"
	field("DetailTitle").text="功法详情"
	_style(field("Techniques"),true);_style(field("Spells"),false)
	_clear(field("SlotGrid"));_clear(field("TechniqueList"))
	for i in range(10):
		var slot: Button=preload("res://ui/technique/technique_slot.tscn").instantiate()
		var key: String=str(slots[i]) if i<slots.size() else ""
		slot.text=("%s\nLv%d" % [data[mode][key].name,learned[key]]) if not key.is_empty() else "锁定" if i>=opened else "空槽"
		slot.disabled=key.is_empty()
		if not key.is_empty():slot.pressed.connect(_select.bind(key))
		_style(slot,not key.is_empty() and key==selected)
		field("SlotGrid").add_child(slot)
	for key in learned:
		var row: Button=preload("res://ui/technique/technique_list_item.tscn").instantiate()
		row.text="■   %s   Lv%d\n%s" % [data[mode][key].name,learned[key],"已装备" if key in slots else "未装备"]
		row.pressed.connect(_select.bind(key));_style(row,key==selected)
		field("TechniqueList").add_child(row)
	if learned.is_empty():
		var empty:=Label.new();empty.text="尚未学习功法"
		field("TechniqueList").add_child(empty)
	field("Information").visible=not selected.is_empty()
	field("Equip").disabled=true;field("Upgrade").disabled=true
	field("Reason").text="请选择已学习条目"
	if not selected.is_empty():
		var info: Dictionary=service.skill_presentation(selected)
		field("Name").text=data[mode][selected].name
		field("Meta").text="Lv%d · 被动功法 · %s" % [learned[selected],"已装备" if selected in slots else "未装备"]
		field("Effects").text="当前效果\n"+info.current
		field("Next").text="下一级效果\n"+info.next
		field("Cost").text=info.cost
		field("Conditions").text="装备条件：已学习，且有开放空槽；已装备可卸下"
		field("Equip").text="卸下" if selected in slots else "装备"
		field("Equip").disabled=not info.slot.success
		field("Upgrade").disabled=not info.upgrade.success
		field("Reason").text="\n".join([str(info.slot.message) if not info.slot.success else "",str(info.upgrade.message) if not info.upgrade.success else ""]).strip_edges()
	selection_changed.emit(mode,selected)
func _style(button: Button,active: bool) -> void:
	var box:=StyleBoxFlat.new();box.bg_color=Color("608779") if active else Color("415963")
	button.add_theme_stylebox_override("normal",box)
func _act(action: String) -> void:
	if selected.is_empty():return
	if field("Equip" if action=="slot" else "Upgrade").disabled:return
	action_requested.emit(action,{"id":selected})

func sync_spells() -> void:
	if not is_instance_valid(spell_page.subview):
		spell_page.refresh_state()

