extends SceneTree

const BOARD = preload("res://gameplay/quest/town_announcements.gd")
const FIRST := "notice_qinglan_001"
const SECOND := "notice_qinglan_002"
const THIRD := "notice_qinglan_003"
const WOLVES := "notice_qinglan_test_kill_001"
const QUEST := "quest_qinglan_001"
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)

func _settle() -> void:
	for i in 5:
		await process_frame

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var gm := root.get_node("GameManager")
	if not gm.boot_ok:
		push_error(gm.catalog.error)
		quit(1)
		return
	gm.new_game("公告栏验收", "金")
	var op: RefCounted = gm.operations
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	root.add_child(main)
	main._navigate("主界面")
	await _settle()
	var home: Control = main.content.get_node("HomeView")
	for button in home.field("Buildings").get_children():
		if button.text == "公告栏":
			button.pressed.emit()
	await _settle()
	var board: Control = main.content.get_node("TownBoard")
	_check(board.selected == FIRST and board.visible_rows.size() == 3 and board.buttons.has(WOLVES) and board.buttons.has("notice_qinglan_test_collect_002"), "All unlocked notices appear on entry")
	board._select(SECOND)
	_check(board.selected == FIRST and not board.buttons.has(SECOND) and not board.buttons.has(THIRD), "Locked notices have no rows or selectable details")
	board.field("Rumor").pressed.emit()
	_check(board.selected.is_empty() and not board.field("Primary").visible, "Empty filter clears detail and actions")
	board.field("All").pressed.emit()
	_check(board.selected == FIRST, "All filter restores first visible notice")
	var before: Dictionary = op.snapshot()
	board.field("Refresh").pressed.emit()
	_check(op.snapshot() == before and board.selected == FIRST, "Refresh is read-only")
	board.field("Primary").pressed.emit()
	_check(op.snapshot().quests[QUEST].status == "ACTIVE" and board.field("Primary").text == "查看进度", "Board accepts into existing quest state")
	before = op.snapshot()
	_check(not op.request("accept_announcement", {"id": FIRST}).success and op.snapshot() == before, "Duplicate acceptance is atomic")
	var saved: Dictionary = op.export_save()
	gm.new_game("另一个角色", "金")
	_check(op.restore_save(saved).is_empty(), "Restore original quest state in memory")
	board.field("Primary").pressed.emit()
	await _settle()
	_check(main.content.get_node("TaskPage").selected_id == QUEST, "View progress opens existing task page and selects the quest")
	main._navigate("主界面")
	await _settle()
	main._navigate("公告栏")
	await _settle()
	board = main.content.get_node("TownBoard")
	_check(board.field("Primary").text == "查看进度", "Reopened board derives accepted status")
	board.field("Place").pressed.emit()
	await _settle()
	_check(main.content.get_node("WorldMap").selected_place == "area_qinglan_outskirts" and op.snapshot().player.location == "town_qinglan", "Map selects the target without travelling")

	# Complete through the normal quest flow and confirm the board reflects it.
	op.request("npc_option", {"npc": "npc_qin_shoushan", "option": "ask_qinglan_disturbance"})
	op.request("travel", {"id": "area_qinglan_outskirts"})
	op.request("investigate", {"id": "event_beast_tracks", "option": "inspect_tracks"})
	op.request("travel", {"id": "town_qinglan"})
	var stones: int = op.snapshot().player.spirit_stones
	_check(op.request("npc_option", {"npc": "npc_qin_shoushan", "option": "report_quest_qinglan_001"}).success, "Normal report completes the board quest")
	_check(op.snapshot().player.spirit_stones == stones + 30, "Quest system issues the original reward")
	main._navigate("公告栏")
	await _settle()
	board = main.content.get_node("TownBoard")
	_check(board.field("Primary").disabled and board.field("Primary").text == "已完成", "Completed board action is disabled")
	_check(not op.request("accept_announcement", {"id":FIRST}).success, "Original one-time board posting cannot be accepted again")
	_check(board.buttons.has(SECOND) and not board.buttons.has(THIRD), "Completing the prerequisite reveals only the next unlocked notice")

	# Isolated fixtures exercise dated and read-only notices without adding game content.
	var tables: Dictionary = op.data.duplicate(true)
	var state: Dictionary = op.snapshot()
	tables.announcements[SECOND].expires_at = state.hours
	tables.announcements[THIRD].created_at = state.hours + 1
	for i in 24:
		var id := "fixture_%02d" % i
		tables.announcements[id] = {
			"id": id, "town_id": "town_qinglan", "category": "notice",
			"title": "测试告示 %02d" % i, "description": "仅用于验证滚动与只读榜文。",
			"created_at": state.hours
		}
	_check(BOARD.validate(tables).is_empty(), "Dated and read-only fixture data is valid")
	board.bind_data(state, tables)
	_check(board.visible_rows.size() == 28, "Future notice is hidden")
	board._select(SECOND)
	_check(board.field("Primary").disabled and board.field("Primary").text == "已过期", "Expiry takes effect at the configured hour")
	_check(not BOARD.accept(SECOND, state, tables, op.quests).is_empty(), "Expired listing is refused even through the accept API")
	board.field("Notice").pressed.emit()
	await _settle()
	_check(not board.field("Primary").visible and not board.field("RewardPanel").visible, "Read-only notice has no reward or accept controls")
	var scroll: ScrollContainer = board.field("ListScroll")
	scroll.scroll_vertical = 500
	_check(scroll.scroll_vertical > 0, "Long list scrolls")
	board.bind_data(op.snapshot(), op.data)
	board.field("All").pressed.emit()
	board._select(SECOND)
	await _check_layout(board)
	_check(op.request("travel", {"id": "town_yunxi"}).success, "Travel to second town")
	_check(board.visible_rows.is_empty() and "云溪城" in board.field("BoardTitle").text, "Town change clears notices and updates title")
	_check(not op.request("accept_announcement", {"id": SECOND}).success, "Wrong-town acceptance refused")
	print("Town board: %d checks, %d failures" % [checks, failures])
	quit(failures)

func _check_layout(board: Control) -> void:
	var arguments := OS.get_cmdline_user_args()
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = dimensions
		await _settle()
		var bounds := board.get_global_rect()
		for key in ["Frame", "Columns", "Sidebar", "ListPanel", "DetailPanel", "Primary", "FooterPanel", "Leave"]:
			var control: Control = board.field(key)
			_check(bounds.grow(1).encloses(control.get_global_rect()), "%s fits at %s" % [key, dimensions])
		if DisplayServer.get_name() != "headless" and arguments.size() == 1:
			await RenderingServer.frame_post_draw
			var path := arguments[0].path_join("xiantu-town-board-%d.png" % dimensions.x)
			var rendered := root.get_texture().get_image()
			_check(rendered.get_size() == dimensions, "Rendered viewport size matches %s" % dimensions)
			_check(rendered.save_png(path) == OK, "Captured rendered town board")
