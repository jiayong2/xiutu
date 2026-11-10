extends PanelContainer
## Shared building layer; all business actions return through the residence controller.
signal closed
signal action_chosen(action_id: String)
var entry_message := ""

func field(key: String) -> Node:
	return find_child(key, true, false)

func _ready() -> void:
	field("BuildingClose").pressed.connect(_close)

func show_building(view: Dictionary) -> void:
	var title := str(view.get("name", "建筑"))
	entry_message = "进入" + title
	field("BuildingName").text = title
	field("InfoTitle").text = title + "信息"
	field("InfoName").text = title
	field("BuildingMeta").text = "所属区域：" + str(view.get("area_name", ""))
	field("BuildingDescription").text = str(view.get("description", ""))
	field("BuildingStatus").text = str(view.get("access_text", "开放状态：未核实"))
	field("SceneTitle").text = title + "场景"
	field("SceneSymbol").text = "◇"
	field("SceneDescription").text = str(view.get("description", ""))
	var names: PackedStringArray = []
	for keeper in view.get("keepers", []):
		names.append(str(keeper.get("name", "未知人物")))
	field("BuildingKeepers").text = "负责：" + ("、".join(names) if not names.is_empty() else "暂无")
	var actions: VBoxContainer = field("BuildingActions")
	_clear(actions)
	var notes: PackedStringArray = []
	if not str(view.get("notice", "")).is_empty():
		notes.append(str(view.notice))
	for action in view.get("actions", []):
		var reason := str(action.get("message", ""))
		if not reason.is_empty() and not notes.has(reason):
			notes.append(reason)
		if str(action.get("type", "")) != "NPC_INTERACT":
			actions.add_child(_action_row(action))
	if actions.get_child_count() == 0:
		_add_note(actions, "可与右侧在场人物交谈。")
	field("Announcement").text = "\n\n".join(notes) if not notes.is_empty() else "可用事务与交谈入口见本页。"
	var people: VBoxContainer = field("PeopleList")
	_clear(people)
	for person in view.get("people", []):
		var card: Button = preload("res://ui/sect/building_npc_card.tscn").instantiate()
		card.get_node("Content/Details/Heading/Name").text = str(person.name)
		card.get_node("Content/Details/Realm").text = str(person.realm)
		card.get_node("Content/Details/Caption").text = "%s · %s" % [person.identity, person.relation]
		var badge: Label = card.get_node("Content/Details/Heading/Rank")
		badge.text = str(person.rank)
		var colors := {"天骄":"9a5c14", "人杰":"74499d", "精英":"31678c", "良才":"28775b"}
		badge.add_theme_color_override("font_color", Color(colors.get(person.rank, "46645a")))
		var action: Dictionary = person.get("action", {})
		card.tooltip_text = "%s · %s\n%s\n%s · %s" % [person.name, person.rank, person.realm, person.identity, person.relation]
		if not action.is_empty():
			card.set_meta("action_label", str(action.label))
			card.pressed.connect(func(): action_chosen.emit(str(action.id)))
		else:
			card.disabled = true
			card.tooltip_text += "\n此人物暂无建筑交谈入口。"
		people.add_child(card)
	field("PeopleTitle").text = "附近人物　%d 人" % view.get("people", []).size()
	if people.get_child_count() == 0:
		_add_note(people, "暂无人物在此。")
	show_feedback("")
	visible = true
	field("ActionScroll").scroll_vertical = 0
	field("InfoScroll").scroll_vertical = 0
	field("PeopleScroll").scroll_vertical = 0

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()

func _add_note(parent: Node, text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_theme_font_size_override("font_size", 22)
	if parent.name == "PeopleList":
		note.add_theme_color_override("font_color", Color(0.15, 0.30, 0.23, 1))
	parent.add_child(note)

func show_feedback(text: String) -> void:
	field("BuildingFeedback").text = entry_message + "\n\n" + (text if not text.is_empty() else "暂无其他动态。")

func _action_row(action: Dictionary) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.text = str(action.get("label", "功能"))
	button.clip_text = true
	button.tooltip_text = button.text
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 24)
	button.pressed.connect(func(): action_chosen.emit(str(action.get("id", ""))))
	column.add_child(button)
	var reason := str(action.get("message", ""))
	if not reason.is_empty():
		_add_note(column, reason)
	return column

func _close() -> void:
	visible = false
	closed.emit()

