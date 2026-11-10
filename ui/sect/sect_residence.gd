@tool
extends Control

signal overview_requested(tab: String)
signal map_requested
signal npc_requested(id: String)
signal shop_requested(id: String)

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
var panel_area := ""
var panel_building := ""

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
	var panel := field("BuildingPanel")
	panel.action_chosen.connect(_building_action)
	panel.closed.connect(func() -> void: panel.visible = false)
	field("LibraryPanel").closed.connect(func(): field("LibraryPanel").hide())

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
	if field("LibraryPanel") != null:
		field("LibraryPanel").hide()
	var area: Dictionary = areas[index]
	var restricted: bool = _area_locked(area)
	var buttons := field("AreaButtons").get_children()
	for i in range(buttons.size()):
		var button: Button = buttons[i]
		var entry: Dictionary = areas[i]
		var locked: bool = _area_locked(entry)
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
	var panel := field("BuildingPanel")
	if panel != null:
		panel.visible = false
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
		var card_name: Label = card.get_node("Body/Text/CardName")
		var description: Label = card.get_node("Body/Text/CardDescription")
		var button: Button = card.get_node("Body/CardAction")
		card_name.text = "未知区域" if undiscovered else entry.name
		card_name.tooltip_text = card_name.text
		description.text = "发现线索后显示" if undiscovered else entry.description
		button.text = "未发现" if undiscovered else "进入"
		button.disabled = undiscovered
		button.tooltip_text = "发现线索后显示" if undiscovered else "进入建筑"
		card.modulate = Color("e2ebe5") if restricted else Color.WHITE

func _connect_card(card: Node) -> void:
	card.get_node("Body/CardAction").pressed.connect(_card_pressed.bind(card.get_index()))

func _card_pressed(index: int) -> void:
	if not _at_residence():
		return
	var area: Dictionary = areas[area_index]
	if index < 0 or index >= area.cards.size():
		return
	var card: Dictionary = area.cards[index]
	if str(card.get("entry", "")) == "undiscovered":
		return
	panel_area = str(area.id)
	panel_building = str(card.id)
	field("BuildingPanel").show_building(_building_view())

func _building_view() -> Dictionary:
	var view: Dictionary = service.sect_building_view(location, panel_area, panel_building)
	var snapshot: Dictionary = service.snapshot()
	var open: bool = service.sect_area_accessible(location, panel_area)
	view["access_text"] = "开放状态：可进入" if open else "通行受限 · 仅查看建筑资料"
	view["people"] = []
	var interaction := preload("res://world/npc_interaction.gd").new()
	if open:
		for id in snapshot.npcs:
			var npc: Dictionary = snapshot.npcs[id]
			if not npc.get("alive", true) or npc.get("location", "") != location or npc.get("sect", "") != view.get("sect_id", "") or npc.get("sect_area", "") != panel_area or npc.get("sect_building", "") != panel_building:
				continue
			var info: Dictionary = interaction.presentation(snapshot, service.data, id)
			var action := {}
			for candidate in view.get("actions", []):
				if candidate.get("type", "") == "NPC_INTERACT" and candidate.get("npc_id", "") == id:
					action = candidate
					break
			view.people.append({"name": info.name, "realm": info.realm, "identity": info.identity,
				"rank": info.rank, "relation": info.relation.trim_prefix("关系："), "action": action})
	if panel_area == "outer" and panel_building == "library" and open:
		view.actions = view.actions.filter(func(action: Dictionary) -> bool: return action.get("type", "") != "LIBRARY")
		view.actions.push_front({"id": "view_shelf", "label": "查看书架", "message": "", "type": "UI"})
		view["notice"] = "书架可查看现有功法；研读与取出尚未开放。"
	return view

func _building_action(action_id: String) -> void:
	if not _at_residence():
		return
	if action_id == "view_shelf":
		if panel_area == "outer" and panel_building == "library" and service.sect_area_accessible(location, panel_area):
			field("LibraryPanel").show_library(service.data.techniques)
		return
	var result: Dictionary = service.sect_building_use(location, panel_area, panel_building, action_id)
	var panel: Node = field("BuildingPanel")
	if not result.get("ok", false):
		panel.show_feedback(str(result.get("message", "无法执行。")))
		return
	match str(result.get("action", "")):
		"npc":
			panel.show_feedback("")
			npc_requested.emit(str(result.get("npc_id", "")))
		"sect_exam":
			var armed: Dictionary = service.request("sect_exam_entry")
			if not armed.get("success", false):
				panel.show_feedback(str(armed.get("message", "现在不能参加考核。")))
			else:
				panel.show_feedback("")
				npc_requested.emit(str(result.get("npc_id", "")))
		"map":
			map_requested.emit()
		"shop":
			shop_requested.emit(str(result.get("shop_id", "")))
		"quest_location":
			var dialog := ConfirmationDialog.new()
			add_child(dialog)
			dialog.dialog_text = str(result.get("message", ""))
			dialog.ok_button_text = str(result.get("confirm", "确认"))
			dialog.confirmed.connect(func():
				var acted: Dictionary = service.request("confirm_location_objective", {"id": str(result.get("quest_id", "")), "option": str(result.get("option_id", ""))})
				panel.show_feedback(str(acted.get("message", "")))
				if acted.get("success", false):
					panel.show_building(_building_view())
				dialog.queue_free())
			dialog.canceled.connect(dialog.queue_free)
			dialog.popup_centered()
		_:
			panel.show_feedback("该功能尚未开放。")

func _area_locked(area: Dictionary) -> bool:
	if Engine.is_editor_hint() or service == null:
		return not str(area.get("restriction", "")).is_empty()
	return not service.sect_area_accessible(location, str(area.get("id", "")))

func _at_residence() -> bool:
	return service != null and service.sect_residence_access(location).is_empty()

func _show_people() -> void:
	if _at_residence() and is_member and areas[area_index].restriction.is_empty():
		overview_requested.emit("Npc")

func _leave() -> void:
	if _at_residence():
		map_requested.emit()
