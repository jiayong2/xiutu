extends Node
## Unified bounded diagnostic history; session log lives outside static content.
signal entry_added(entry: Dictionary)
const MAX_ENTRIES := 200
var _entries: Array[Dictionary] = []
var _file: FileAccess

func _ready() -> void:
	_file = FileAccess.open("user://s00.log", FileAccess.WRITE)
	if _file == null:
		push_error("Cannot open user://s00.log: %s" % FileAccess.get_open_error())

func write(level: String, module: String, message: String, operation_id: String = "") -> void:
	var entry := {"time": Time.get_datetime_string_from_system(), "level": level,
		"module": module, "message": message, "operation_id": operation_id}
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	var line := JSON.stringify(entry)
	print(line)
	if _file != null:
		_file.store_line(line)
		_file.flush()
	entry_added.emit(entry.duplicate(true))

func snapshot() -> Array[Dictionary]:
	return _entries.duplicate(true)
