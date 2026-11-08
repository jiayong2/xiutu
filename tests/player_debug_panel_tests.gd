extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
	print("%s %s" % ["PASS" if condition else "FAIL", description])

func run() -> void:
	var manager := root.get_node("GameManager")
	var op: RefCounted = manager.operations
	var error: String = op.new_game("属性测试", "金", manager.repository.starting_character(), 1, "mountain_origin")
	check(error.is_empty(), "isolated character")
	var fixture: Dictionary = op.export_save()
	fixture.state.player.techniques.technique_iron_body = 1
	fixture.state.player.technique_slots.append("technique_iron_body")
	fixture.state.player.techniques.technique_fire_breath = 1
	fixture.state.player.technique_slots.append("technique_fire_breath")
	check(op.restore_save(fixture).is_empty(), "passive technique fixture")
	var before: Dictionary = op.snapshot()
	var initial_stats: Dictionary = op.stats()
	var values := {"hp":200, "mp":20, "attack":51, "defense":25, "speed":2, "spirit_stones":456}
	for invalid in [-1, 3.5, "100", 2147483648]:
		var bad := values.duplicate()
		bad.spirit_stones = invalid
		check(not op.request("debug_set_player_values", bad).success and op.snapshot() == before, "invalid input is atomic")

	var main: Control = load("res://ui/main/main.tscn").instantiate()
	main.page = "主界面"
	root.add_child(main)
	var panel := main.get_node("PlayerDebugPanel")
	var f12 := InputEventKey.new()
	f12.keycode = KEY_F12
	f12.pressed = true
	root.push_input(f12)
	await process_frame
	check(panel.visible and paused, "F12 opens and pauses")
	var clock_before: Dictionary = op.clock_status()
	await create_timer(1.1).timeout
	check(op.clock_status() == clock_before, "paused world clock")
	var fields: Dictionary = panel._fields
	var read_correct: bool = fields.spirit_stones.text == str(before.player.spirit_stones)
	for key in before.player.base:
		read_correct = read_correct and fields[key].text == str(before.player.base[key])
	check(read_correct, "reads all six live fields")
	var frame: Control = panel.get_child(0).get_child(0)
	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = resolution
		await process_frame
		await process_frame
		check(frame.size.x >= 620 and frame.get_rect().get_center().distance_to(panel.size / 2) < 2 and panel.get_global_rect().encloses(frame.get_global_rect()), "centered panel at %s" % resolution)
	var buttons := {}
	for button in panel.find_children("*", "Button", true, false):
		buttons[button.text] = button
	for key in values:
		fields[key].text = str(values[key])
	fields.speed.text = "2.5"
	buttons["应用修改"].pressed.emit()
	check(op.snapshot() == before, "invalid UI input preserves all fields")
	fields.speed.text = "2"
	buttons["应用修改"].pressed.emit()
	await process_frame
	check(main.content.get_node("HomeView").field("Wallet").text == "灵石 456", "main wallet refreshes while paused")
	var after: Dictionary = op.snapshot()
	var totals: Dictionary = op.stats()
	check(panel.visible and fields.spirit_stones.text == "456" and after.player.spirit_stones == 456, "applies while open and reads real wallet")
	check(after.player.base == {"hp":200, "mp":20, "attack":51, "defense":25, "speed":2}, "updates exactly the five base values")
	check(totals.hp > 200 and totals.hp != initial_stats.hp and after.player.hp == before.player.hp, "HP uses bonuses and does not heal")
	check(totals.mp == 20 and after.player.mp == 20, "MP recalculates and clamps")
	check(totals.attack - 51 == initial_stats.attack - before.player.base.attack and totals.attack >= 57, "attack keeps equipped weapon and technique bonuses")
	check(totals.defense - 25 == initial_stats.defense - before.player.base.defense and totals.defense > 25, "defense keeps passive technique bonus")
	check(after.npcs == before.npcs and after.player.techniques == before.player.techniques, "NPCs and techniques remain intact")
	fields.hp.text = "999"
	buttons["重新读取"].pressed.emit()
	check(fields.hp.text == "200", "reload discards draft")
	fields.hp.text = "999"
	root.push_input(f12)
	check(not panel.visible and not paused and op.snapshot().player.base.hp == 200, "F12 closes and discards draft")
	paused = true
	root.push_input(f12)
	buttons["×"].pressed.emit()
	check(paused, "close restores previous paused state")
	paused = false
	root.push_input(f12)
	fields.hp.text = "999"
	buttons["取消"].pressed.emit()
	check(not panel.visible and not paused and op.snapshot().player.base.hp == 200, "cancel discards only draft values")

	var weapon: String = after.player.equipped.weapon
	check(op.request("unequip", {"id":weapon}).success and op.snapshot().player.base == after.player.base and op.stats().attack < totals.attack, "equipment change preserves base")
	var path: String = manager.saves.write(op.export_save(), "user://test_saves/player_debug")
	check(not path.is_empty(), "writes isolated save")
	check(op.restore_save(manager.saves.read(path)).is_empty() and op.snapshot().player.base == after.player.base and op.snapshot().player.spirit_stones == 456, "save round-trip")
	check(op.stats().hp == totals.hp and op.stats().attack < totals.attack, "reload does not stack bonuses")
	var lower := values.duplicate()
	lower.hp = 35
	lower.spirit_stones = 0
	check(op.request("debug_set_player_values", lower).success and op.snapshot().player.hp == op.stats().hp and op.snapshot().player.spirit_stones == 0, "lower maximum clamps HP and accepts zero balance")
	check(op.request("debug_set_player_values", values).success, "raise maximum again")
	check(op.request("travel", {"id":"area_qinglan_outskirts"}).success and op.request("challenge").success and op.request("begin_battle").success, "enters real battle")
	check(op.snapshot().battle.round_order == ["enemy", "player"], "battle initiative uses new speed")
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
