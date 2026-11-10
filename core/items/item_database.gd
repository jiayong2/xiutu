extends RefCounted
## Item template persistence and validation for the in-game item database editor.
## This is a service over the existing res://data/items/items.json table; it is not a
## second item database. Runtime inventory instances continue to store item IDs.

const ItemReferences = preload("res://core/items/item_references.gd")

const PATH := "res://data/items/items.json"
const ID_PATTERN := "^[a-z][a-z0-9_]{2,63}$"
const RARITY_ORDER := ["common", "uncommon", "rare"]
const RARITY_LABELS := {"common": "凡品", "uncommon": "良品", "rare": "珍品"}
const TYPE_ORDER := ["丹药", "消耗品", "灵草", "材料", "战利品", "装备", "防具", "武器", "法宝", "种子", "秘籍"]
const TYPE_PREFIXES := {
	"丹药": "pill_", "消耗品": "item_", "灵草": "herb_", "材料": "material_",
	"战利品": "material_", "装备": "equip_", "防具": "equip_", "武器": "equip_",
	"法宝": "artifact_", "种子": "seed_", "秘籍": "book_",
}
const DEFAULT_STACK := {"装备": 1, "防具": 1, "武器": 1, "法宝": 1}

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
		return {"rows": [], "error": "找不到物品数据文件：%s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"rows": [], "error": "无法读取物品数据文件：%s（错误 %s）" % [path, FileAccess.get_open_error()]}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"rows": [], "error": "%s 第 %d 行 JSON 无效：%s" % [path, parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Array:
		return {"rows": [], "error": "物品数据根节点必须是数组：%s" % path}
	var rows: Array = []
	var ids := {}
	for index in parser.data.size():
		var value: Variant = parser.data[index]
		if not value is Dictionary:
			return {"rows": [], "error": "第 %d 条物品不是对象：%s" % [index + 1, path]}
		var row: Dictionary = value.duplicate(true)
		var id: Variant = row.get("id")
		if not valid_id(id):
			return {"rows": [], "error": "第 %d 条物品 ID 无效：%s" % [index + 1, str(id)]}
		if ids.has(id):
			return {"rows": [], "error": "物品 ID 重复：%s" % id}
		ids[id] = true
		_normalize_row(row)
		rows.append(row)
	return {"rows": rows, "error": ""}

static func write_rows(rows: Array, catalog: Dictionary, path := PATH) -> Dictionary:
	var issue := validate_rows(rows, catalog)
	if not issue.is_empty():
		return {"success": false, "message": issue, "warning": ""}
	if path.begins_with("res://") and not OS.has_feature("editor"):
		return {"success": false, "message": "导出版本中的 res:// 静态配置为只读；请在 Godot 编辑器中运行本工具。", "warning": ""}
	var warning := ""
	if path.begins_with("res://"):
		warning = _backup(path)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return {"success": false, "message": "无法创建物品数据目录：%s" % path.get_base_dir(), "warning": warning}
	var staged := path + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return {"success": false, "message": "无法写入临时文件：%s（错误 %s）" % [staged, FileAccess.get_open_error()], "warning": warning}
	file.store_string(JSON.stringify(rows, "  ") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(staged)
		return {"success": false, "message": "写入临时文件失败（错误 %s）；原文件未改动。" % write_error, "warning": warning}
	var rename_error := DirAccess.rename_absolute(staged, path)
	if rename_error != OK:
		DirAccess.remove_absolute(staged)
		return {"success": false, "message": "替换物品数据文件失败（错误 %s）；原文件未改动。" % rename_error, "warning": warning}
	return {"success": true, "message": "已保存 %d 件物品。" % rows.size(), "warning": warning}

static func validate_rows(rows: Array, catalog: Dictionary) -> String:
	if rows.is_empty():
		return "物品表不能为空。"
	var ids := {}
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary:
			return "第 %d 条物品不是有效对象。" % (index + 1)
		var id: Variant = row.get("id")
		if not valid_id(id):
			return "物品 ID 必须为 3–64 位小写英文、数字或下划线，且以字母开头：%s" % str(id)
		if ids.has(id):
			return "物品 ID 重复：%s" % id
		ids[id] = true
		var issue := validate_row(row, catalog, index + 1)
		if not issue.is_empty():
			return issue
	return ItemReferences.catalog_error(catalog, ids)

static func validate_row(row: Dictionary, catalog: Dictionary, row_number: int = 0) -> String:
	var prefix := "第 %d 条物品" % row_number if row_number > 0 else "物品"
	var id: Variant = row.get("id")
	if not valid_id(id):
		return "%s ID 无效：%s" % [prefix, str(id)]
	var name: Variant = row.get("name")
	if not name is String or name.strip_edges().is_empty():
		return "%s（%s）缺少物品名称。" % [prefix, id]
	if name.strip_edges().length() > 32:
		return "%s（%s）名称不能超过 32 字。" % [prefix, id]
	var type: Variant = row.get("type")
	if not type is String or type.strip_edges().is_empty():
		return "%s（%s）缺少一级分类。" % [prefix, id]
	if type.strip_edges().length() > 16:
		return "%s（%s）一级分类不能超过 16 字。" % [prefix, id]
	var rarity: Variant = row.get("rarity")
	if not rarity is String or rarity.strip_edges().is_empty():
		return "%s（%s）缺少物品品质。" % [prefix, id]
	var buy_price: Variant = row.get("buy_price")
	if not valid_integer(buy_price, 0, 99999999):
		return "%s（%s）购买价格必须是 0–99,999,999 的整数。" % [prefix, id]
	var sell_price: Variant = row.get("sell_price")
	if not valid_integer(sell_price, 0, 99999999):
		return "%s（%s）出售价格必须是 0–99,999,999 的整数。" % [prefix, id]
	if sell_price > buy_price:
		return "%s（%s）出售价格不能高于购买价格。" % [prefix, id]
	var stack_limit: Variant = row.get("stack_limit")
	if not valid_integer(stack_limit, 1, 9999):
		return "%s（%s）最大堆叠必须是 1–9,999 的整数。" % [prefix, id]
	var description: Variant = row.get("description", "")
	if not description is String:
		return "%s（%s）物品描述必须是文本。" % [prefix, id]
	if description.length() > 500:
		return "%s（%s）物品描述不能超过 500 字。" % [prefix, id]
	var effect: Variant = row.get("use_effect")
	if not (effect is Dictionary or effect == null):
		return "%s（%s）use_effect 必须是对象或 null。" % [prefix, id]
	if effect is Dictionary:
		if effect.has("stat"):
			if not effect.stat is String or effect.stat not in ["hp", "mp"]:
				return "%s（%s）恢复效果只能使用 hp 或 mp。" % [prefix, id]
			if not valid_integer(effect.get("amount"), 1, 999999):
				return "%s（%s）恢复效果数值必须是正整数。" % [prefix, id]
		if effect.has("learn"):
			var target: Variant = effect.learn
			if not target is String or target.is_empty():
				return "%s（%s）学习目标不能为空。" % [prefix, id]
			if not catalog.get("techniques", {}).has(target) and not catalog.get("spells", {}).has(target):
				return "%s（%s）学习目标“%s”不存在于功法或法术表。" % [prefix, id, target]
		for key in effect:
			if key not in ["stat", "amount", "learn"] and effect[key] is float and not is_finite(effect[key]):
				return "%s（%s）效果参数 %s 不是有效数值。" % [prefix, id, str(key)]
	return ""

static func create_draft(existing_ids: Dictionary, type := "材料") -> Dictionary:
	var item_type := type if type is String and not type.strip_edges().is_empty() else "材料"
	var row := {
		"id": next_id(prefix_for(item_type) + "new", existing_ids),
		"name": "新物品",
		"type": item_type,
		"buy_price": 0,
		"sell_price": 0,
		"description": "",
		"rarity": "common",
		"stack_limit": int(DEFAULT_STACK.get(item_type, 99)),
		"use_effect": null,
	}
	return row

static func copy_draft(source: Dictionary, existing_ids: Dictionary) -> Dictionary:
	var row: Dictionary = source.duplicate(true)
	var base: String = str(source.get("id", "item")) + "_copy"
	row.id = next_id(base, existing_ids)
	var name: String = str(source.get("name", "物品"))
	row.name = (name + "副本").substr(0, 32)
	if not row.has("use_effect"):
		row.use_effect = null
	return row

static func next_id(base: String, existing_ids: Dictionary) -> String:
	var candidate := base
	var suffix := 2
	while existing_ids.has(candidate):
		candidate = "%s_%d" % [base, suffix]
		suffix += 1
	return candidate

static func prefix_for(type: String) -> String:
	return str(TYPE_PREFIXES.get(type, "item_"))

static func types(rows: Array) -> Array[String]:
	var found := {}
	for row in rows:
		if row is Dictionary and row.get("type") is String and not row.type.is_empty():
			found[row.type] = true
	var result: Array[String] = []
	for value in TYPE_ORDER:
		if found.has(value):
			result.append(value)
			found.erase(value)
	var remaining: Array[String] = []
	for value in found:
		remaining.append(str(value))
	remaining.sort()
	result.append_array(remaining)
	return result

static func rarities(rows: Array) -> Array[String]:
	var found := {}
	for row in rows:
		if row is Dictionary and row.get("rarity") is String and not row.rarity.is_empty():
			found[row.rarity] = true
	var result: Array[String] = []
	for value in RARITY_ORDER:
		if found.has(value):
			result.append(value)
			found.erase(value)
	var remaining: Array[String] = []
	for value in found:
		remaining.append(str(value))
	remaining.sort()
	result.append_array(remaining)
	return result

static func rarity_label(value: String) -> String:
	return str(RARITY_LABELS.get(value, value))

static func rarity_rank(value: String) -> int:
	var index := RARITY_ORDER.find(value)
	return index if index >= 0 else RARITY_ORDER.size()

static func is_tradable(row: Dictionary) -> bool:
	return int(row.get("sell_price", 0)) > 0

static func is_usable(row: Dictionary) -> bool:
	if row.get("id", "") == "pill_qi_gathering":
		return true
	var effect: Variant = row.get("use_effect")
	return effect is Dictionary and (effect.has("learn") or effect.has("stat"))

static func is_equipment_like(row: Dictionary) -> bool:
	return str(row.get("type", "")) in ["装备", "防具", "武器", "法宝"]

static func ids_of(rows: Array) -> Dictionary:
	var result := {}
	for row in rows:
		if row is Dictionary and row.get("id") is String:
			result[row.id] = true
	return result

static func _normalize_row(row: Dictionary) -> void:
	for key in ["buy_price", "sell_price", "stack_limit"]:
		if row.has(key) and (row[key] is int or row[key] is float):
			if is_finite(float(row[key])):
				row[key] = int(row[key])

static func _backup(path: String) -> String:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return ""
	var text := source.get_as_text()
	source.close()
	var directory := "user://item_editor_backups"
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
