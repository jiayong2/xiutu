@tool
extends ConfirmationDialog

signal picked(id: String)

var rows: Dictionary
var owned: Variant
var search: LineEdit
var filters := {}
var list: ItemList
var detail: TextEdit
var badge: Label
var order: CheckButton

func _ready() -> void:
	title = "资源选择"
	ok_button_text = "添加 / 选择"
	cancel_button_text = "取消"
	min_size = Vector2i(760, 520)
	var content := VBoxContainer.new()
	add_child(content)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称或资源 ID"
	search.text_changed.connect(func(_value): _refresh())
	content.add_child(search)
	var bar := HFlowContainer.new()
	content.add_child(bar)
	for key in ["type","quality","realm","polarity"]:
		var option := OptionButton.new()
		bar.add_child(option)
		filters[key] = option
		option.item_selected.connect(func(_index): _refresh())
	order = CheckButton.new()
	order.text = "倒序"
	order.toggled.connect(func(_checked): _refresh())
	bar.add_child(order)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)
	list = ItemList.new()
	list.custom_minimum_size.x = 285
	list.item_selected.connect(_show_row)
	columns.add_child(list)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(info)
	badge = Label.new()
	info.add_child(badge)
	detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(detail)
	confirmed.connect(_accept)

func choose(definitions: Dictionary, selected: Variant) -> void:
	rows = definitions
	owned = selected
	search.clear()
	for key in filters:
		var option: OptionButton = filters[key]
		option.clear()
		option.add_item({"type":"全部类型","quality":"全部品阶","realm":"全部境界","polarity":"全部正负"}[key])
		var values := {}
		for row in rows.values():
			var value := _value(row, key)
			if not value.is_empty():
				values[value] = true
		for value in values:
			option.add_item(value)
		option.visible = option.item_count > 1
	_refresh()
	popup_centered_ratio(0.70)
	search.grab_focus()

func _value(row: Dictionary, key: String) -> String:
	match key:
		"type": return str(row.get("kind", row.get("slot", row.get("category", row.get("element", row.get("cultivation_route", ""))))))
		"quality": return str(row.get("quality", row.get("rarity", row.get("tier", ""))))
		"realm": return str(row.get("recommended_realm", row.get("realm", "")))
		"polarity":
			if row.has("exclusive_group"):
				return "负面" if row.kind == "negative" else "正面"
	return ""

func _refresh() -> void:
	list.clear()
	badge.text = ""
	detail.text = ""
	get_ok_button().disabled = true
	var ids := rows.keys()
	ids.sort_custom(func(a, b): return str(rows[a].get("name", a)).naturalnocasecmp_to(str(rows[b].get("name", b))) < 0)
	if order.button_pressed:
		ids.reverse()
	for id in ids:
		var row: Dictionary = rows[id]
		var title_text: String = row.get("name", id)
		var needle := search.text.strip_edges().to_lower()
		if not needle.is_empty() and not (title_text + " " + id).to_lower().contains(needle):
			continue
		var matches := true
		for key in filters:
			var option: OptionButton = filters[key]
			if option.selected > 0 and option.get_item_text(option.selected) != _value(row, key):
				matches = false
		if not matches:
			continue
		var icon: Texture2D
		var icon_path: Variant = row.get("icon", "")
		if icon_path is String and not icon_path.is_empty() and ResourceLoader.exists(icon_path, "Texture2D"):
			icon = load(icon_path)
		var index := list.add_item(("✓ " if owned.has(id) else "") + title_text, icon)
		list.set_item_metadata(index, id)
	if list.item_count == 0:
		detail.text = "没有符合条件的资源。请清除筛选，或检查对应游戏配置库。"

func _show_row(index: int) -> void:
	var id: String = list.get_item_metadata(index)
	var row: Dictionary = rows[id]
	get_ok_button().disabled = false
	badge.text = row.get("name", id)
	badge.remove_theme_color_override("font_color")
	badge.remove_theme_stylebox_override("normal")
	if row.has("exclusive_group"):
		preload("res://ui/character/fortune_badge.gd").apply(badge, row)
		detail.text = "\n".join(preload("res://gameplay/character/player_fortunes.gd").describe(row))
		detail.text += "\n\n类别 %s\n互斥组 %s\n标签 %s\n持续 %s" % [row.group, row.exclusive_group, row.get("tags", []), row.duration.type]
	else:
		detail.text = JSON.stringify(row, "  ", true)
	detail.text += "\n\n资源 ID  " + id

func _accept() -> void:
	var indices := list.get_selected_items()
	if not indices.is_empty():
		picked.emit(list.get_item_metadata(indices[0]))
