extends RefCounted
## Monster template persistence and validation for the in-game monster editor.
## This service reads and writes the existing res://data/monsters/monsters.json
## table. Battle snapshots, player saves and runtime instances are never touched.

const MonsterConfig = preload("res://core/monster_config.gd")

const PATH := "res://data/monsters/monsters.json"
const SKILLS_PATH := "res://data/monsters/skills.json"
const ID_PATTERN := "^[a-z][a-z0-9_]{2,63}$"
const RANK_LABELS := {"normal": "普通", "elite": "精英", "boss": "首领"}
const RANK_ORDER := ["normal", "elite", "boss"]
const REALM_MIN := 1
const REALM_MAX := 9
const NAME_MAX := 32
const DESCRIPTION_MAX := 500
const BASIC_SKILL := "beast_skill_basic_attack"
const SKILL_EFFECT_TYPES := ["damage", "status", "stat", "heal", "shield", "mana", "cleanse", "phase"]
const SKILL_TARGET_LABELS := {
	"enemy": "单体敌人", "self": "自身", "random_enemy": "随机敌人",
	"lowest_enemy": "生命最低敌人", "all_enemies": "全体敌人",
}
const STATUS_MODE_LABELS := {"stack": "叠加", "refresh": "刷新", "replace": "替换"}
const STAT_LABELS := {"attack": "攻击", "defense": "防御", "speed": "速度", "crit": "暴击"}
const STAT_LIMITS := {
	"hp": [1, 999999],
	"mp": [0, 999999],
	"attack": [0, 99999],
	"defense": [0, 99999],
	"speed": [0, 99999],
}

static var _id_regex: RegEx

static func _regex() -> RegEx:
	if _id_regex == null:
		_id_regex = RegEx.new()
		_id_regex.compile(ID_PATTERN)
	return _id_regex

static func valid_id(value: Variant) -> bool:
	return value is String and _regex().search(value) != null

static func valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number) and number >= minimum and number <= maximum

static func read_rows(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"rows": [], "error": "找不到妖兽数据文件：%s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"rows": [], "error": "无法读取妖兽数据文件：%s（错误 %s）" % [path, FileAccess.get_open_error()]}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"rows": [], "error": "%s 第 %d 行 JSON 无效：%s" % [path, parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Array:
		return {"rows": [], "error": "妖兽数据根节点必须是数组：%s" % path}
	var rows: Array = []
	var ids := {}
	for index in parser.data.size():
		var value: Variant = parser.data[index]
		if not value is Dictionary:
			return {"rows": [], "error": "第 %d 条妖兽不是对象：%s" % [index + 1, path]}
		var row: Dictionary = value.duplicate(true)
		var id: Variant = row.get("id")
		if not valid_id(id):
			return {"rows": [], "error": "第 %d 条妖兽 ID 无效：%s" % [index + 1, str(id)]}
		if ids.has(id):
			return {"rows": [], "error": "妖兽 ID 重复：%s" % id}
		ids[id] = true
		_normalize_row(row)
		rows.append(row)
	return {"rows": rows, "error": ""}

static func read_skills(path := SKILLS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"rows": [], "error": "找不到妖兽技能库文件：%s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"rows": [], "error": "无法读取妖兽技能库：%s（错误 %s）" % [path, FileAccess.get_open_error()]}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"rows": [], "error": "%s 第 %d 行 JSON 无效：%s" % [path, parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Array:
		return {"rows": [], "error": "妖兽技能库根节点必须是数组：%s" % path}
	var rows: Array = []
	var ids := {}
	for index in parser.data.size():
		var value: Variant = parser.data[index]
		if not value is Dictionary:
			return {"rows": [], "error": "第 %d 条妖兽技能不是对象：%s" % [index + 1, path]}
		var row: Dictionary = value.duplicate(true)
		var id: Variant = row.get("id")
		if not valid_id(id):
			return {"rows": [], "error": "第 %d 条妖兽技能 ID 无效：%s" % [index + 1, str(id)]}
		if ids.has(id):
			return {"rows": [], "error": "妖兽技能 ID 重复：%s" % id}
		ids[id] = true
		for key in ["mp", "cooldown"]:
			if row.has(key) and (row[key] is int or row[key] is float) and is_finite(float(row[key])):
				row[key] = int(row[key])
		rows.append(row)
	return {"rows": rows, "error": ""}

static func write_rows(rows: Array, catalog: Dictionary, path := PATH) -> Dictionary:
	var issues := validate_rows(rows, catalog)
	if not issues.is_empty():
		return {"success": false, "message": str(issues[0].get("message", "配置无效")), "issues": issues, "warning": ""}
	if path.begins_with("res://") and not OS.has_feature("editor"):
		return {"success": false, "message": "导出版本中的 res:// 静态配置为只读；请在 Godot 编辑器中运行本工具。", "issues": [], "warning": ""}
	var warning := ""
	if path.begins_with("res://"):
		warning = _backup(path)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return {"success": false, "message": "无法创建妖兽数据目录：%s" % path.get_base_dir(), "issues": [], "warning": warning}
	var staged := path + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return {"success": false, "message": "无法写入临时文件：%s（错误 %s）" % [staged, FileAccess.get_open_error()], "issues": [], "warning": warning}
	file.store_string(JSON.stringify(rows, "  ") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(staged)
		return {"success": false, "message": "写入临时文件失败（错误 %s）；原文件未改动。" % write_error, "issues": [], "warning": warning}
	var rename_error := DirAccess.rename_absolute(staged, path)
	if rename_error != OK:
		DirAccess.remove_absolute(staged)
		return {"success": false, "message": "替换妖兽数据文件失败（错误 %s）；原文件未改动。" % rename_error, "issues": [], "warning": warning}
	return {"success": true, "message": "已保存 %d 只妖兽。" % rows.size(), "issues": [], "warning": warning}

static func write_tables(monsters: Array, skills: Array, catalog: Dictionary,
		monsters_path := PATH, skills_path := SKILLS_PATH, write_skills := true) -> Dictionary:
	var issues := validate_rows(monsters, catalog, skills)
	if not issues.is_empty():
		return {"success": false, "message": str(issues[0].get("message", "配置无效")), "issues": issues, "warning": ""}
	var touches_res := monsters_path.begins_with("res://") or (write_skills and skills_path.begins_with("res://"))
	if touches_res and not OS.has_feature("editor"):
		return {"success": false, "message": "导出版本中的 res:// 静态配置为只读；请在 Godot 编辑器中运行本工具。", "issues": [], "warning": ""}
	var warning := ""
	var previous_skills_text := FileAccess.get_file_as_string(skills_path) if write_skills else ""
	if monsters_path.begins_with("res://"):
		warning += _backup(monsters_path)
	if write_skills and skills_path.begins_with("res://"):
		warning += _backup(skills_path)
	if write_skills:
		var skill_error := _write_text(skills_path, JSON.stringify(skills, "  ") + "\n")
		if not skill_error.is_empty():
			return {"success": false, "message": "写入技能库失败：" + skill_error, "issues": [], "warning": warning}
	var monster_error := _write_text(monsters_path, JSON.stringify(monsters, "  ") + "\n")
	if not monster_error.is_empty():
		if write_skills:
			var restore_error := _write_text(skills_path, previous_skills_text)
			if not restore_error.is_empty():
				return {"success": false, "message": "写入妖兽表失败：%s；技能库回滚也失败：%s" % [monster_error, restore_error], "issues": [], "warning": warning}
			return {"success": false, "message": "写入妖兽表失败：%s；技能库已回滚，妖兽表未改动。" % monster_error, "issues": [], "warning": warning}
		return {"success": false, "message": "写入妖兽表失败：" + monster_error, "issues": [], "warning": warning}
	var message := "已保存 %d 只妖兽。" % monsters.size()
	if write_skills:
		message = "已保存 %d 只妖兽、%d 个技能。" % [monsters.size(), skills.size()]
	return {"success": true, "message": message, "issues": [], "warning": warning}

static func validate_rows(rows: Array, catalog: Dictionary, skill_rows: Array = []) -> Array:
	var issues: Array = []
	if rows.is_empty():
		issues.append(_issue(0, "", "rows", "妖兽表不能为空。"))
		return issues
	var tables := catalog.duplicate(true)
	tables["monsters"] = rows_to_index(rows)
	if not skill_rows.is_empty():
		tables["monster_skills"] = rows_to_index(skill_rows)
	var ids := {}
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary:
			issues.append(_issue(index + 1, "", "row", "第 %d 条妖兽不是有效对象。" % (index + 1)))
			continue
		var id: Variant = row.get("id")
		if valid_id(id):
			if ids.has(id):
				issues.append(_issue(index + 1, str(id), "id", "妖兽 ID 重复：%s" % id))
			else:
				ids[id] = true
		issues.append_array(validate_row(row, tables, index + 1))
	if not skill_rows.is_empty():
		issues.append_array(validate_skill_rows(skill_rows, tables))
	if issues.is_empty():
		var monster_error := MonsterConfig.validate(tables)
		if not monster_error.is_empty():
			issues.append(_issue(0, "", _field_for(monster_error), monster_error))
	return issues

static func validate_row(row: Dictionary, catalog: Dictionary, row_number: int = 0) -> Array:
	var issues: Array = []
	var id := str(row.get("id", ""))
	var prefix := "第 %d 条妖兽" % row_number if row_number > 0 else "妖兽"
	if not valid_id(row.get("id")):
		issues.append(_issue(row_number, id, "id", "%s ID 无效：%s" % [prefix, str(row.get("id", ""))]))
	if not row.get("name") is String or str(row.get("name", "")).strip_edges().is_empty():
		issues.append(_issue(row_number, id, "name", "%s（%s）缺少妖兽名称。" % [prefix, id]))
	elif str(row.get("name", "")).strip_edges().length() > NAME_MAX:
		issues.append(_issue(row_number, id, "name", "%s（%s）名称不能超过 %d 字。" % [prefix, id, NAME_MAX]))
	if row.has("description"):
		if not row.get("description") is String:
			issues.append(_issue(row_number, id, "description", "%s（%s）描述必须是文本。" % [prefix, id]))
		elif str(row.get("description", "")).length() > DESCRIPTION_MAX:
			issues.append(_issue(row_number, id, "description", "%s（%s）描述不能超过 %d 字。" % [prefix, id, DESCRIPTION_MAX]))
	if not valid_integer(row.get("realm", null), REALM_MIN, REALM_MAX):
		issues.append(_issue(row_number, id, "realm", "%s（%s）境界必须是 %d–%d 的整数。" % [prefix, id, REALM_MIN, REALM_MAX]))
	if not row.get("rank") is String or str(row.get("rank", "")) not in RANK_ORDER:
		issues.append(_issue(row_number, id, "rank", "%s（%s）身份必须是普通、精英或首领。" % [prefix, id]))
	for stat in STAT_LIMITS:
		var limits: Array = STAT_LIMITS[stat]
		if not valid_integer(row.get(stat, null), int(limits[0]), int(limits[1])):
			issues.append(_issue(row_number, id, stat, "%s（%s）%s必须是 %d–%d 的整数。" % [
				prefix, id, _stat_label(stat), int(limits[0]), int(limits[1])]))
	if not issues.is_empty():
		return issues
	var deep := MonsterConfig.validate_monster(row, catalog, catalog.get("monster_skills", {}))
	if not deep.is_empty():
		issues.append(_issue(row_number, id, _field_for(deep), "%s（%s）%s" % [prefix, id, deep]))
	return issues

static func validate_skill_rows(skills: Array, tables: Dictionary) -> Array:
	var issues: Array = []
	var ids := {}
	for index in skills.size():
		var skill: Variant = skills[index]
		if not skill is Dictionary:
			issues.append(_skill_issue(index + 1, "", "row", "第 %d 条妖兽技能不是有效对象。" % (index + 1)))
			continue
		var id: Variant = skill.get("id")
		if valid_id(id):
			if ids.has(id):
				issues.append(_skill_issue(index + 1, str(id), "id", "妖兽技能 ID 重复：%s" % id))
			else:
				ids[id] = true
		issues.append_array(validate_skill_row(skill, tables, index + 1))
	return issues

static func validate_skill_row(skill: Dictionary, tables: Dictionary, row_number: int = 0) -> Array:
	var issues: Array = []
	var id := str(skill.get("id", ""))
	var prefix := "第 %d 个妖兽技能" % row_number if row_number > 0 else "妖兽技能"
	if not valid_id(skill.get("id")):
		issues.append(_skill_issue(row_number, id, "id", "%s ID 无效：%s" % [prefix, str(skill.get("id", ""))]))
	if not skill.get("name") is String or str(skill.get("name", "")).strip_edges().is_empty():
		issues.append(_skill_issue(row_number, id, "name", "%s（%s）缺少技能名称。" % [prefix, id]))
	elif str(skill.get("name", "")).strip_edges().length() > NAME_MAX:
		issues.append(_skill_issue(row_number, id, "name", "%s（%s）技能名称不能超过 %d 字。" % [prefix, id, NAME_MAX]))
	if skill.has("description"):
		if not skill.get("description") is String:
			issues.append(_skill_issue(row_number, id, "description", "%s（%s）技能描述必须是文本。" % [prefix, id]))
		elif str(skill.get("description", "")).length() > DESCRIPTION_MAX:
			issues.append(_skill_issue(row_number, id, "description", "%s（%s）技能描述不能超过 %d 字。" % [prefix, id, DESCRIPTION_MAX]))
	if not valid_integer(skill.get("mp", 0), 0, 999999):
		issues.append(_skill_issue(row_number, id, "mp", "%s（%s）MP 消耗必须是 0–999,999 的整数。" % [prefix, id]))
	if not valid_integer(skill.get("cooldown", 0), 0, 9999):
		issues.append(_skill_issue(row_number, id, "cooldown", "%s（%s）冷却必须是 0–9,999 的整数。" % [prefix, id]))
	if str(skill.get("target", "enemy")) not in MonsterConfig.SKILL_TARGETS:
		issues.append(_skill_issue(row_number, id, "target", "%s（%s）技能目标无效：%s" % [prefix, id, str(skill.get("target", ""))]))
	if skill.has("scope"):
		if not skill.scope is Array or skill.scope.is_empty():
			issues.append(_skill_issue(row_number, id, "scope", "%s（%s）技能适用范围必须是数组。" % [prefix, id]))
		else:
			for scope in skill.scope:
				if str(scope) not in MonsterConfig.SCOPES:
					issues.append(_skill_issue(row_number, id, "scope", "%s（%s）技能适用范围无效：%s" % [prefix, id, str(scope)]))
	if skill.has("ordinary") and not skill.ordinary is bool:
		issues.append(_skill_issue(row_number, id, "ordinary", "%s（%s）普通攻击标记必须是布尔值。" % [prefix, id]))
	if not skill.get("effects") is Array or skill.effects.is_empty():
		issues.append(_skill_issue(row_number, id, "effects", "%s（%s）至少需要一个效果组件。" % [prefix, id]))
	else:
		for index in skill.effects.size():
			var effect: Variant = skill.effects[index]
			var error := MonsterConfig.validate_effect(effect, tables)
			if not error.is_empty():
				issues.append(_skill_issue(row_number, id, "effects", "%s（%s）第 %d 个效果：%s" % [prefix, id, index + 1, error]))
	if not issues.is_empty():
		return issues
	var deep := MonsterConfig.validate_skill(skill, tables)
	if not deep.is_empty():
		issues.append(_skill_issue(row_number, id, "skill", "%s（%s）%s" % [prefix, id, deep]))
	return issues

static func create_behavior_draft(existing_ids: Dictionary) -> Dictionary:
	return {
		"id": next_id("rule_new", existing_ids),
		"name": "新行为规则",
		"priority": 100,
		"enabled": true,
		"condition_mode": "all",
		"conditions": [{"type": "hp_below", "value": 50}],
		"action": "attack",
		"target": "enemy",
		"chance": 1.0,
		"max_uses": 0,
		"cooldown": 0,
		"on_fail": "continue",
	}

static func copy_behavior_draft(source: Dictionary, existing_ids: Dictionary) -> Dictionary:
	var rule: Dictionary = source.duplicate(true)
	rule.id = next_id(str(source.get("id", "rule")) + "_copy", existing_ids)
	var name := str(source.get("name", "行为规则"))
	rule.name = name.substr(0, NAME_MAX - 2) + "副本"
	return rule

static func create_trigger_draft(existing_ids: Dictionary) -> Dictionary:
	return {
		"id": next_id("trigger_new", existing_ids),
		"name": "新特殊机制",
		"event": "battle_start",
		"enabled": true,
		"once": true,
		"max_uses": 1,
		"conditions": [],
		"effects": [{"type": "stat", "stat": "attack", "value": 0.1, "turns": 99, "layers": 1, "target": "self"}],
	}

static func copy_trigger_draft(source: Dictionary, existing_ids: Dictionary) -> Dictionary:
	var trigger: Dictionary = source.duplicate(true)
	trigger.id = next_id(str(source.get("id", "trigger")) + "_copy", existing_ids)
	var name := str(source.get("name", "特殊机制"))
	trigger.name = name.substr(0, NAME_MAX - 2) + "副本"
	return trigger

static func create_skill_draft(existing_ids: Dictionary) -> Dictionary:
	return {
		"id": next_id("beast_skill_new", existing_ids),
		"name": "新妖兽技能",
		"description": "",
		"scope": ["monster"],
		"mp": 0,
		"cooldown": 0,
		"target": "enemy",
		"ordinary": false,
		"effects": [{"type": "damage", "power": 1.0}],
	}

static func copy_skill_draft(source: Dictionary, existing_ids: Dictionary) -> Dictionary:
	var skill: Dictionary = source.duplicate(true)
	skill.id = next_id(str(source.get("id", "beast_skill")) + "_copy", existing_ids)
	var name := str(source.get("name", "妖兽技能"))
	skill.name = name.substr(0, NAME_MAX - 2) + "副本"
	if not skill.has("scope"):
		skill.scope = ["monster"]
	return skill

static func skill_references(skill_id: String, monster_rows: Array) -> Array:
	var result: Array = []
	if skill_id.is_empty():
		return result
	for monster in monster_rows:
		if not monster is Dictionary:
			continue
		var monster_id := str(monster.get("id", ""))
		var monster_name := str(monster.get("name", monster_id))
		var skill_ids: Variant = monster.get("skill_ids", [])
		if skill_ids is Array and skill_id in skill_ids:
			result.append({"monster_id": monster_id, "monster_name": monster_name, "detail": "技能列表"})
		var behaviors: Variant = monster.get("behaviors", [])
		if not behaviors is Array:
			continue
		for behavior in behaviors:
			if not behavior is Dictionary:
				continue
			if str(behavior.get("skill", "")) == skill_id:
				result.append({"monster_id": monster_id, "monster_name": monster_name,
					"detail": "行为规则 " + str(behavior.get("id", ""))})
			var conditions: Variant = behavior.get("conditions", [])
			if not conditions is Array:
				continue
			for condition in conditions:
				if condition is Dictionary and str(condition.get("skill", "")) == skill_id:
					result.append({"monster_id": monster_id, "monster_name": monster_name,
						"detail": "行为条件 " + str(behavior.get("id", ""))})
	return result

static func replace_skill_reference(monster: Dictionary, old_id: String, new_id: String) -> int:
	var changed := 0
	var skill_ids: Variant = monster.get("skill_ids", [])
	if skill_ids is Array:
		for index in skill_ids.size():
			if str(skill_ids[index]) == old_id:
				skill_ids[index] = new_id
				changed += 1
	var behaviors: Variant = monster.get("behaviors", [])
	if not behaviors is Array:
		return changed
	for behavior in behaviors:
		if not behavior is Dictionary:
			continue
		if str(behavior.get("skill", "")) == old_id:
			behavior["skill"] = new_id
			changed += 1
		var conditions: Variant = behavior.get("conditions", [])
		if not conditions is Array:
			continue
		for condition in conditions:
			if condition is Dictionary and str(condition.get("skill", "")) == old_id:
				condition["skill"] = new_id
				changed += 1
	return changed

static func remove_skill_from_monster(monster: Dictionary, skill_id: String) -> bool:
	var skill_ids: Variant = monster.get("skill_ids", [])
	if not skill_ids is Array:
		return false
	var index: int = int(skill_ids.find(skill_id))
	if index < 0:
		return false
	skill_ids.remove_at(index)
	return true

static func create_draft(existing_ids: Dictionary, skills: Dictionary = {}) -> Dictionary:
	var skill_id := BASIC_SKILL if skills.has(BASIC_SKILL) else ""
	if skill_id.is_empty() and not skills.is_empty():
		skill_id = str(skills.keys()[0])
	var behavior := {
		"id": "new_basic_attack",
		"priority": 100,
		"enabled": true,
		"conditions": [{"type": "always"}],
		"action": "skill" if not skill_id.is_empty() else "attack",
		"target": "enemy",
		"chance": 1.0,
		"max_uses": 0,
		"cooldown": 0,
		"on_fail": "continue",
	}
	if not skill_id.is_empty():
		behavior["skill"] = skill_id
	return {
		"id": next_id("monster_new", existing_ids),
		"name": "新妖兽",
		"description": "",
		"hp": 50,
		"mp": 0,
		"attack": 10,
		"defense": 3,
		"speed": 10,
		"realm": 1,
		"rank": "normal",
		"skill_ids": [] if skill_id.is_empty() else [skill_id],
		"behaviors": [behavior],
		"loot": {"money": [0, 0], "entries": []},
	}

static func copy_draft(source: Dictionary, existing_ids: Dictionary) -> Dictionary:
	var row: Dictionary = source.duplicate(true)
	row.id = next_id(str(source.get("id", "monster")) + "_copy", existing_ids)
	var name := str(source.get("name", "妖兽"))
	row.name = name.substr(0, NAME_MAX - 2) + "副本"
	if not row.has("description"):
		row.description = str(source.get("description", ""))
	return row

static func next_id(base: String, existing_ids: Dictionary) -> String:
	var candidate := base
	var suffix := 2
	while existing_ids.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate

static func ids_of(rows: Array) -> Dictionary:
	var result := {}
	for row in rows:
		if row is Dictionary and row.get("id") is String:
			result[row.id] = true
	return result

static func rows_to_index(rows: Array) -> Dictionary:
	var result := {}
	for row in rows:
		if row is Dictionary and row.get("id") is String:
			result[row.id] = row
	return result

static func rank_label(value: String) -> String:
	return str(RANK_LABELS.get(value, value))

static func rank_rank(value: String) -> int:
	var index := RANK_ORDER.find(value)
	return index if index >= 0 else RANK_ORDER.size()

static func realm_label(level: int, catalog: Dictionary) -> String:
	if catalog.is_empty():
		return "境界 %d" % level
	return preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(level, "qi", catalog)

static func _stat_label(stat: String) -> String:
	return {"hp": "最大生命", "mp": "最大灵力", "attack": "基础攻击", "defense": "基础防御", "speed": "基础速度"}.get(stat, stat)

static func _issue(row_number: int, monster_id: String, field: String, message: String) -> Dictionary:
	return {"row": row_number, "id": monster_id, "field": field, "message": message, "group": "monster"}

static func _skill_issue(row_number: int, skill_id: String, field: String, message: String) -> Dictionary:
	return {"row": row_number, "id": skill_id, "field": field, "message": message, "group": "skill"}

static func _field_for(message: String) -> String:
	# Behaviour messages can also mention skills; classify the behaviour first so
	# the editor points at the rule list rather than the monster skill list.
	if message.contains("行为") or message.contains("条件") or message.contains("动作"):
		return "behaviors"
	if message.contains("技能"):
		return "skill_ids"
	if message.contains("被动"):
		return "passives"
	if message.contains("触发"):
		return "triggers"
	if message.contains("掉落") or message.contains("物品") or message.contains("灵石"):
		return "loot"
	if message.contains("境界"):
		return "realm"
	if message.contains("身份"):
		return "rank"
	return "config"

static func _normalize_row(row: Dictionary) -> void:
	for key in ["hp", "mp", "attack", "defense", "speed", "realm"]:
		if row.has(key) and (row[key] is int or row[key] is float):
			if is_finite(float(row[key])):
				row[key] = int(row[key])

static func _write_text(path: String, text: String) -> String:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return "无法创建数据目录：%s" % path.get_base_dir()
	var staged := path + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return "无法写入临时文件：%s（错误 %s）" % [staged, FileAccess.get_open_error()]
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(staged)
		return "写入临时文件失败（错误 %s）；原文件未改动。" % write_error
	var rename_error := DirAccess.rename_absolute(staged, path)
	if rename_error != OK:
		DirAccess.remove_absolute(staged)
		return "替换数据文件失败（错误 %s）；原文件未改动。" % rename_error
	return ""

static func _backup(path: String) -> String:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return ""
	var text := source.get_as_text()
	source.close()
	var directory := "user://monster_editor_backups"
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "备份目录创建失败；已继续使用临时文件写入。"
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var destination := directory.path_join("%s_%s.json" % [path.get_file().get_basename(), stamp])
	var target := FileAccess.open(destination, FileAccess.WRITE)
	if target == null:
		return "无法写入备份文件；已继续使用临时文件写入。"
	target.store_string(text)
	target.flush()
	var error := target.get_error()
	target.close()
	return "" if error == OK else "备份文件写入失败（错误 %s）；已继续使用临时文件写入。" % error
