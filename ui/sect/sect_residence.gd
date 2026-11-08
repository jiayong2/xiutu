@tool
extends Control

signal overview_requested(tab: String)
signal map_requested

const AREA_CONFIG := "res://data/world/sect_areas.json"
const CARD_SCENE := preload("res://ui/sect/residence_card.tscn")

@export_enum("外门区域", "内门区域", "宗门核心区", "后山禁地") var editor_area := 0:
	set(value):
		editor_area = value
		if Engine.is_editor_hint() and is_node_ready():
			_preview()

var service: RefCounted
var location := ""
var areas: Array = []
var area_index := 0
var is_member := false

func field(key: String) -> Node:
	return find_child(key, true, false)

func _ready() -> void:
	if Engine.is_editor_hint():
		_preview()
		return
	for button in field("AreaButtons").get_children():
		button.pressed.connect(_select_area.bind(button.get_index()))
	for card in field("Cards").get_children():
		_connect_card(card)
	field("Back").pressed.connect(func(): overview_requested.emit("Overview"))
	field("ReturnOuter").pressed.connect(_select_area.bind(0))
	field("People").pressed.connect(_show_people)
	field("Leave").pressed.connect(_leave)

func bind_data(operations: RefCounted, place: String) -> void:
	service = operations
	location = place
	var snapshot: Dictionary = service.snapshot()
	var sect: Dictionary = service.sect_at_location(location)
	areas = service.data.sect_areas[sect.id]
	var title: String = service.sect_member_title(sect.id)
	is_member = not title.is_empty()
	field("Title").text = sect.name + " · 宗门驻地"
	field("Identity").text = "当前身份：访客"
	if is_member:
		field("Identity").text = "当前身份：%s　｜　贡献：%d" % [title,snapshot.contribution]
	_render(0)

func _preview() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(AREA_CONFIG))
	if config is Dictionary and config.has("sect_qingyue"):
		areas = config.sect_qingyue
		_render(editor_area)

func _select_area(index: int) -> void:
	if index < 0 or index >= areas.size() or not _at_residence():
		return
	_render(index)
	field("CardScroll").scroll_vertical = 0

func _render(index: int) -> void:
	area_index = index
	var area: Dictionary = areas[index]
	var restricted: bool = not area.restriction.is_empty()
	var buttons := field("AreaButtons").get_children()
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		var entry: Dictionary = areas[i]
		var locked: bool = not entry.restriction.is_empty()
		button.text = entry.name + (" · 锁定" if locked else "")
		button.tooltip_text = entry.restriction
		button.theme_type_variation = &"LockedAreaButton" if locked else &"AreaButton"
		button.set_pressed_no_signal(i == index)

	var prefix := "布局预览 · " if restricted else ""
	field("CardTitle").text = prefix + area.name + " · " + area.heading
	field("NoticeTitle").text = "通行限制" if restricted else "区域近况"
	field("NoticeText").text = area.restriction if restricted else "暂无新的宗门消息。"
	field("AreaStatus").text = "当前区域：%s　｜　%s" % [
		areas[0].name, "预览%s · 未取得通行权限" % area.name if restricted else "通行权限：已获得"]
	field("ReturnOuter").visible = restricted
	field("People").visible = not restricted
	field("People").disabled = not is_member
	field("People").tooltip_text = "" if is_member else "加入本宗后可查看宗门人物。"
	_render_cards(area.cards, restricted)

func _render_cards(entries: Array, restricted: bool) -> void:
	var grid: GridContainer = field("Cards")
	while grid.get_child_count() < entries.size():
		var card := CARD_SCENE.instantiate()
		grid.add_child(card)
		if not Engine.is_editor_hint():
			_connect_card(card)
	for i in range(grid.get_child_count()):
		var card: Control = grid.get_child(i)
		card.visible = i < entries.size()
		if not card.visible:
			continue
		var entry: Dictionary = entries[i]
		var kind: String = entry.get("entry", "")
		var undiscovered := kind == "undiscovered" and not Engine.is_editor_hint()
		var open := not restricted and kind == "gate"
		var card_name: Label = card.get_node("Body/Row/CardName")
		var description: Label = card.get_node("Body/CardDescription")
		var button: Button = card.get_node("Body/Row/CardAction")
		card_name.text = "未知区域" if undiscovered else entry.name
		card_name.tooltip_text = card_name.text
		description.text = "发现线索后显示" if undiscovered else entry.description
		button.text = "出山门" if open else "尚未发现" if undiscovered else "未获通行" if restricted else "尚未开放"
		button.disabled = not open
		button.tooltip_text = "返回世界地图" if open else "当前没有可用的进入方式。"
		card.modulate = Color("e2ebe5") if restricted else Color.WHITE

func _connect_card(card: Node) -> void:
	card.get_node("Body/Row/CardAction").pressed.connect(_card_pressed.bind(card.get_index()))

func _card_pressed(index: int) -> void:
	if not _at_residence():
		return
	var area: Dictionary = areas[area_index]
	if area.restriction.is_empty() and index < area.cards.size() and area.cards[index].get("entry", "") == "gate":
		_leave()

func _at_residence() -> bool:
	return service != null and service.sect_residence_access(location).is_empty()

func _show_people() -> void:
	if _at_residence() and is_member and areas[area_index].restriction.is_empty():
		overview_requested.emit("Npc")

func _leave() -> void:
	if _at_residence():
		map_requested.emit()
