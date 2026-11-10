extends RefCounted
## Structured presentation of the authoritative database validation.
const Database := preload("res://core/skills/skill_database.gd")
static func inspect(bundle: Dictionary, growth: Dictionary) -> Array:
	var records := []
	for message in Database.validate_bundle(bundle, growth):
		var field := "effects"
		for entry in [["ID", "id"], ["名称", "name"], ["五行", "element"], ["灵力", "mp"], ["消耗", "mp"], ["冷却", "cd"], ["目标", "target"], ["策略", "ai"], ["成长", "growth"]]:
			if str(message).contains(entry[0]):
				field = entry[1]
		var pattern := RegEx.new()
		pattern.compile("effects\\[(\\d+)\\]")
		var matched := pattern.search(message)
		var node := int(matched.get_string(1)) if matched != null else -1
		if node >= 0: field = "effects"
		records.append({"severity": "error", "message": message, "field": field, "node_index": node})
	if records.is_empty():
		records.append({"severity": "info", "message": "当前配置通过运行时校验", "field": "", "node_index": -1})
	return records
