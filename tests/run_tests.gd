extends SceneTree
const Repository = preload("res://core/data_repository.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
	print("%s: %s" % ["PASS" if condition else "FAIL", description])

func _run() -> void:
	var repo := Repository.new()
	check(repo.load_starting_character(), "production bootstrap loads")
	var original := repo.starting_character()
	check(original.spirit_stones == 120 and original.hp == 120, "documented baseline")
	var copy := repo.starting_character()
	copy.hp = 1
	check(repo.starting_character().hp == 120, "configuration reads are isolated")
	for invalid in [null, [], {"id": ""}]:
		check(not repo.validate(invalid).is_empty(), "invalid root/required fields rejected")
	for invalid in [-1, 1.5, "120", true]:
		var candidate := original.duplicate(true)
		candidate.spirit_stones = invalid
		check(not repo.validate(candidate).is_empty(), "invalid numeric field rejected")
	check(not repo.load_starting_character("res://tests/missing.json"), "missing file fails explicitly")
	check(repo.starting_character().is_empty() and not repo.last_error.is_empty(), "failed load clears stale data")
	check(not repo.load_starting_character("res://tests/fixtures/malformed.json"), "malformed JSON rejected")
	var manager := root.get_node("GameManager")
	check(manager.boot_ok, "autoload boot ready")
	var log_service := root.get_node("AppLog")
	log_service.write("WARN", "test", "S00 log verification", "test-log")
	check(log_service.snapshot().back().operation_id == "test-log", "structured log recorded")
	var log_file := FileAccess.open("user://s00.log", FileAccess.READ)
	check(log_file != null and log_file.get_as_text().contains("test-log"), "log flushed to disk")
	var scene := load("res://ui/main/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	check(not main.debug_panel.visible, "debug initially hidden")
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	main._unhandled_key_input(key)
	check(main.debug_panel.visible, "F1 opens debug")
	main._unhandled_key_input(key)
	check(not main.debug_panel.visible, "F1 closes debug")
	main.queue_free()
	print("S00: %s checks, %s failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
