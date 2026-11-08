extends Control

signal closed
signal refresh_requested
signal accept_requested(id: String)
signal claim_requested(id: String, round_number: int)
signal tasks_requested(quest_id: String)
signal place_requested(place_id: String)

const BOARD = preload("res://gameplay/quest/town_announcements.gd")
const ROW = preload("res://ui/quest/town_board_row.tscn")
const PLACES = preload("res://ui/world/world_page.gd").PLACES
const STATUS := {
	"AVAILABLE": ["可接取", &"StatusAvailable"],
	"ACTIVE": ["已接取", &"StatusActive"],
	"READY_TO_TURN_IN": ["待交付", &"StatusActive"],
	"COMPLETED": ["已完成", &"StatusDone"],
	"EXPIRED": ["已过期", &"StatusExpired"],
	"LOCKED": ["条件不足", &"StatusLocked"],
	"READ_ONLY": ["可查看", &"BoardMuted"]
}

var quests := BOARD.QUESTS.new()
var clock := BOARD.CLOCK.new()
var cultivation := preload("res://gameplay/cultivation/cultivation_system.gd").new()
var state: Dictionary
var data: Dictionary
var town := ""
var category := ""
var selected := ""
var visible_rows: Array[Dictionary] = []
var buttons: Dictionary = {}

func field(key: String) -> Node:
	return find_child(key, true, false)

func _ready() -> void:
	field("PreviewCard").queue_free()
	field("Close").pressed.connect(func(): closed.emit())
	field("Leave").pressed.connect(func(): closed.emit())
	field("Refresh").pressed.connect(func(): refresh_requested.emit())
	field("MyTasks").pressed.connect(func(): tasks_requested.emit(""))
	field("Place").pressed.connect(_show_place)
	field("Primary").pressed.connect(_primary)
	var filters: Array[Node] = field("Filters").get_children()
	var categories: Array = [""] + BOARD.CATEGORIES.keys()
	for i in filters.size():
		filters[i].pressed.connect(_filter.bind(categories[i]))

func bind_data(snapshot: Dictionary, tables: Dictionary) -> void:
	data = tables
	sync(snapshot)

func sync(snapshot: Dictionary, feedback: String = "") -> void:
	state = snapshot
	var location: String = state.player.location
	if town != location:
		town = location
		category = ""
		selected = ""
	field("BoardTitle").text = PLACES.get(town, town) + " · 公告栏"
	if not feedback.is_empty():
		field("Feedback").text = feedback
	_refresh()

func _filter(value: String) -> void:
	if category != value:
		category = value
		field("ListScroll").scroll_vertical = 0
		field("Feedback").text = ""
	_refresh()

func _select(id: String) -> void:
	if not buttons.has(id):
		return
	if selected != id:
		selected = id
		field("DetailScroll").scroll_vertical = 0
		field("Feedback").text = ""
	_highlight()
	_detail()

func _refresh() -> void:
	var rows: Array[Dictionary] = []
	var today := 0
	var day_hours := int(data.rules.hours_day)
	var current_day := floori(float(state.hours) / day_hours)
	for row in data.announcements.values():
		if row.town_id != town or not BOARD.is_published(row, state):
			continue
		if BOARD.status(row, state, data, quests) in ["LOCKED", "COOLDOWN"]:
			continue
		if row.has("created_at") and floori(float(row.created_at) / day_hours) == current_day:
			today += 1
		if category.is_empty() or row.category == category:
			rows.append(row)
	var active := 0
	for quest in state.quests.values():
		if quest.status in ["ACTIVE", "READY_TO_TURN_IN"]:
			active += 1
	field("Summary").text = "今日新增 %d 条 · 已接取 %d 项（未设上限）" % [today, active]
	field("Count").text = "共 %d 条" % rows.size()
	var filter_buttons: Array[Node] = field("Filters").get_children()
	var categories: Array = [""] + BOARD.CATEGORIES.keys()
	for i in filter_buttons.size():
		filter_buttons[i].set_pressed_no_signal(category == categories[i])

	if rows != visible_rows:
		var container := field("Rows")
		for button in buttons.values():
			container.remove_child(button)
			button.queue_free()
		buttons.clear()
		for row in rows:
			var button: Button = ROW.instantiate()
			container.add_child(button)
			button.pressed.connect(_select.bind(row.id))
			buttons[row.id] = button
		visible_rows = rows
	if not buttons.has(selected):
		selected = "" if rows.is_empty() else rows[0].id
		field("DetailScroll").scroll_vertical = 0
	for row in rows:
		_update_row(row, buttons[row.id])
	_highlight()
	_detail()

func _highlight() -> void:
	for id in buttons:
		buttons[id].set_pressed_no_signal(id == selected)

func _update_row(row: Dictionary, button: Button) -> void:
	var quest: Dictionary = data.quests.get(row.get("quest_id", ""), {})
	var title := _title(row, quest)
	var rewards := _rewards(quest)
	var summary: Array[String] = []
	if quest.get("money", 0) > 0:
		summary.append("灵石 ×%d" % quest.money)
	var item_count: int = quest.get("rewards", {}).size()
	if item_count > 0:
		summary.append("道具 %d 种" % item_count)
	var status: Array = STATUS[BOARD.status(row, state, data, quests)]
	button.find_child("Category").text = BOARD.CATEGORIES[row.category]
	button.find_child("RowTitle").text = title
	button.find_child("RowTime").text = _remaining(row)
	button.find_child("RowReward").text = " · ".join(summary)
	var status_label: Label = button.find_child("RowStatus")
	status_label.text = status[0]
	status_label.theme_type_variation = status[1]
	button.tooltip_text = "\n".join([title + " · " + status[0]] + rewards)

func _detail() -> void:
	var row: Dictionary = data.announcements.get(selected, {})
	var quest: Dictionary = data.quests.get(row.get("quest_id", ""), {})
	var empty := row.is_empty()
	var location: String = row.get("location_id", "")
	field("DetailTitle").text = "暂无榜文" if empty else _title(row, quest)
	field("TextHeading").visible = not empty
	field("Divider").visible = not empty
	field("Place").visible = not location.is_empty()
	field("Place").disabled = not PLACES.has(location)
	field("Primary").visible = not quest.is_empty()
	field("Reason").text = ""
	field("Reason").hide()
	field("RewardPanel").hide()
	if empty:
		field("Facts").text = ""
		field("Description").text = "当前城镇暂无榜文。" if category.is_empty() else "该分类暂无榜文。"
		return

	var facts: Array[String] = ["公告类型　" + BOARD.CATEGORIES[row.category]]
	var status := BOARD.status(row, state, data, quests)
	var publisher: String = row.get("publisher_id", quest.get("giver_npc_id", ""))
	if not publisher.is_empty():
		facts.append("发布者　" + state.npcs.get(publisher, {}).get("name", publisher))
	if not location.is_empty():
		facts.append("相关地点　" + PLACES.get(location, location))
	if not quest.is_empty():
		facts.append("建议修为　" + cultivation.realm_name(int(quest.recommended_realm), "qi", data))
		var objective: Dictionary = quests.current(state, quest.id, data)
		if objective.is_empty() and (status in ["AVAILABLE", "LOCKED"] or quest.completion_mode == "BOARD"):
			objective = quest.objectives[0]
		if not objective.is_empty():
			var progress := 0
			if status != "AVAILABLE" and state.quests.has(quest.id):
				progress = quests.objective_count(state,quest.id,objective)
			facts.append("委托目标　%s（%d/%d）" % [objective.description, progress, objective.required_count])
	if row.has("expires_at") or not quest.is_empty():
		facts.append("榜文期限　" + _remaining(row))
	field("Facts").text = "\n".join(facts)
	field("Description").text = quest.get("description", row.get("description", ""))
	var rewards := _rewards(quest)
	field("RewardPanel").visible = not rewards.is_empty()
	field("Rewards").text = "\n".join(rewards)

	var primary: Button = field("Primary")
	primary.disabled = status not in ["AVAILABLE", "ACTIVE", "READY_TO_TURN_IN"]
	primary.text = {"AVAILABLE": "接取委托", "ACTIVE": "查看进度", "READY_TO_TURN_IN": "查看进度", "LOCKED": "不可接取"}.get(status, STATUS[status][0])
	if status == "READY_TO_TURN_IN" and quest.completion_mode == "BOARD":
		primary.text = "交付委托"
	if status == "LOCKED":
		field("Reason").text = quests.requirement_error(state, quest.id, data)
		field("Reason").show()

func _remaining(row: Dictionary) -> String:
	if not row.has("expires_at"):
		return "长期有效"
	var seconds := int(row.expires_at) * 3600 - clock.seconds(state)
	if seconds <= 0:
		return "榜文期限已结束"
	var hours := ceili(float(seconds) / 3600)
	var day_hours := int(data.rules.hours_day)
	return "剩余 %d 日 %d 时" % [hours / day_hours, hours % day_hours] if hours >= day_hours else "剩余 %d 时" % hours

func _title(row: Dictionary, quest: Dictionary) -> String:
	return quest.get("title", row.get("title", ""))

func _rewards(quest: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if quest.get("money", 0) > 0:
		lines.append("灵石 ×%d" % quest.money)
	for id in quest.get("rewards", {}):
		lines.append("%s ×%d" % [data.items[id].name, quest.rewards[id]])
	return lines

func _primary() -> void:
	if selected.is_empty():
		return
	var row: Dictionary = data.announcements[selected]
	match BOARD.status(row, state, data, quests):
		"AVAILABLE": accept_requested.emit(selected)
		"READY_TO_TURN_IN":
			if data.quests[row.quest_id].completion_mode == "BOARD":
				claim_requested.emit(selected,int(state.quests[row.quest_id].get("round",0)))
			else:
				tasks_requested.emit(row.quest_id)
		"ACTIVE": tasks_requested.emit(row.quest_id)

func _show_place() -> void:
	var location: String = data.announcements.get(selected, {}).get("location_id", "")
	if PLACES.has(location):
		place_requested.emit(location)
