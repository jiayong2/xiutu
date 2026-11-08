extends RefCounted
## S00 bootstrap contract only; no runtime character or inventory creation.
var _starting_character: Dictionary = {}
var last_error := ""

func load_starting_character(path: String = "res://data/characters/starting_character.json") -> bool:
	_starting_character.clear()
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "%s: cannot open (%s)" % [path, FileAccess.get_open_error()]
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		last_error = "%s:%s: %s" % [path, parser.get_error_line(), parser.get_error_message()]
		return false
	last_error = validate(parser.data)
	if not last_error.is_empty():
		last_error = "%s: %s" % [path, last_error]
		return false
	_starting_character = parser.data.duplicate(true)
	return true

func starting_character() -> Dictionary:
	return _starting_character.duplicate(true)

func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "root must be an object"
	for key in ["id", "test_name", "origin_id", "realm_id", "location_id"]:
		if not value.get(key) is String or value[key].is_empty():
			return "%s must be a nonempty string" % key
	for key in ["schema_version", "age", "lifespan", "hp", "mp", "attack", "defense", "speed", "cultivation", "cultivation_required", "spirit_stones"]:
		var number: Variant = value.get(key)
		if not (number is float or number is int):
			return "%s must be numeric" % key
		if not is_finite(float(number)) or number < 0 or floor(float(number)) != number:
			return "%s must be a nonnegative integer" % key
	if value.schema_version != 1:
		return "unsupported schema_version"
	if value.age > value.lifespan or value.hp <= 0 or value.cultivation_required <= 0:
		return "invalid age, hp or cultivation_required"
	return ""
