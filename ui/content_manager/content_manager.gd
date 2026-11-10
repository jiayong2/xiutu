extends Control
## Developer content index. Read-only over ContentCatalog; UI never writes game data.

signal closed
signal editor_requested(kind: String, id: String)

const IndexService := preload("res://core/content_index/content_index_service.gd")

const BG := Color("102B30")
const PANEL := Color("193B40")
const SECONDARY := Color("254D50")
const GROUP := Color("295755")
const BTN := Color("275658")
const BTN_ON := Color("397D70")
const TEXT := Color("E1F4EA")
const MUTED := Color("A6C9C2")
const BORDER := Color("3D6965")
const BORDER_ON := Color("84C8B1")
const BORDER_OFF := Color("477D75")
const BTN_TEXT := Color("F0FFF5")

const NAV := [
	{"title": "世界与地点", "items": [
		{"id": "town", "label": "城镇"}, {"id": "sect", "label": "宗门"},
		{"id": "wild", "label": "野外区域"}, {"id": "building", "label": "建筑"},
		{"id": "map", "label": "探索地图"},
	]},
	{"title": "人物与生物", "items": [
		{"id": "npc", "label": "NPC"}, {"id": "monster", "label": "妖兽"},
	]},
	{"title": "任务与事件", "items": [
		{"id": "quest", "label": "任务"}, {"id": "event", "label": "世界事件"},
		{"id": "dialogue", "label": "对话"},
	]},
	{"title": "物品与装备", "items": [
		{"id": "item:material", "label": "材料"}, {"id": "item:pill", "label": "丹药"},
		{"id": "item:equipment", "label": "装备"}, {"id": "item:artifact", "label": "法宝"},
		{"id": "item:other", "label": "其他物品"},
	]},
	{"title": "修炼与战斗", "items": [
		{"id": "technique", "label": "功法"}, {"id": "spell", "label": "法术"},
		{"id": "realm", "label": "境界"},
	]},
	{"title": "气运", "items": [
		{"id": "fortune_innate", "label": "先天气运"},
		{"id": "fortune_acquired", "label": "后天气运"},
	]},
]
const PAGE_SIZE := 16
const REGION_TAGS := [
	{"id": "building", "label": "建筑"}, {"id": "npc", "label": "NPC"},
	{"id": "quest", "label": "任务"}, {"id": "monster", "label": "妖兽"},
	{"id": "item", "label": "物品"}, {"id": "event", "label": "事件"},
]

var catalog: Dictionary = {}
var index := IndexService.new()
var mode := "category"
var nav_id := "building"
var region_id := "town_qinglan"
var region_tag := ""
var search_text := ""
var sort_mode := "name"
var issues_only := false
var page := 0
var visible_rows: Array = []
var selected_key := ""
var category_buttons: Dictionary = {}
var region_buttons: Dictionary = {}
var chip_normal: StyleBoxFlat
var chip_on: StyleBoxFlat
var chip_off: StyleBoxFlat

func _ready() -> void:
	_styles()
	%Export.pressed.connect(_on_export)
	%Refresh.pressed.connect(reload_from_disk)
	%Close.pressed.connect(request_close)
	%ModeCategory.pressed.connect(func(): _set_mode("category"))
	%ModeRegion.pressed.connect(func(): _set_mode("region"))
	%Search.text_changed.connect(func(text): search_text = text; page = 0; _refresh_list())
	%Sort.item_selected.connect(func(i): sort_mode = str(%Sort.get_item_metadata(i)); _refresh_list())
	%IssuesOnly.toggled.connect(func(on): issues_only = on; page = 0; _refresh_list())
	%Prev.pressed.connect(func(): page = maxi(page - 1, 0); _render_page())
	%Next.pressed.connect(func(): page += 1; _render_page())
	%Tree.item_selected.connect(_on_tree_selected)
	%OpenEditor.pressed.connect(_on_open_editor)
	%ExportKind.clear()
	%ExportKind.add_item("Markdown 清单")
	%ExportKind.set_item_metadata(0, "md")
	%ExportKind.add_item("JSON 索引")
	%ExportKind.set_item_metadata(1, "json")
	%ExportKind.select(0)
	%Sort.clear()
	for pair in [["名称排序", "name"], ["ID 排序", "id"], ["分类排序", "category"], ["地区排序", "region"], ["状态排序", "status"]]:
		%Sort.add_item(pair[0])
		%Sort.set_item_metadata(%Sort.item_count - 1, pair[1])
	_build_category_nav()
	if catalog.is_empty():
		reload_from_disk()
	else:
		refresh_index()

func request_close() -> void:
	closed.emit()

func reload_from_disk() -> void:
	catalog = {}
	refresh_index()

func refresh_index() -> void:
	index.refresh(catalog)
	catalog = index.tables
	_fill_stats()
	_build_region_nav()
	page = 0
	_refresh_list()
	_select_current()

func focus_record(key: String) -> void:
	var record: Dictionary = index.get_record(key)
	if record.is_empty():
		return
	if record.category in ["town", "sect", "wild"] and mode == "region":
		region_id = record.id
	else:
		mode = "category"
		nav_id = record.category if record.category != "item" else "item:%s" % record.subcategory
	selected_key = key
	_set_mode(mode)
	_select_row(key)

func _set_mode(next: String) -> void:
	mode = next
	%CategoryNav.visible = mode == "category"
	%RegionNav.visible = mode == "region"
	_paint_mode()
	page = 0
	_refresh_list()

func _fill_stats() -> void:
	var stats: Dictionary = index.stats()
	%StatTown.text = "城镇 / 地图  %d" % stats.town_map
	%StatBuilding.text = "建筑  %d" % stats.building
	%StatNpc.text = "NPC / 妖兽  %d" % stats.npc_monster
	%StatQuest.text = "任务 / 事件  %d" % stats.quest_event
	%StatItem.text = "物品 / 装备  %d" % stats.item_equip
	%StatTech.text = "功法 / 气运  %d" % stats.tech_fortune

func _build_category_nav() -> void:
	_clear(%CategoryNav)
	category_buttons.clear()
	for group in NAV:
		%CategoryNav.add_child(_group_title(group.title))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.add_theme_constant_override("v_separation", 5)
		%CategoryNav.add_child(flow)
		for item in group.items:
			var button := _chip(item.label)
			button.pressed.connect(_select_nav.bind(item.id))
			flow.add_child(button)
			category_buttons[item.id] = button

func _build_region_nav() -> void:
	_clear(%RegionNav)
	region_buttons.clear()
	var groups: Dictionary = index.region_groups()
	for pair in [["town", "城镇"], ["sect", "宗门"], ["wild", "野外区域"]]:
		%RegionNav.add_child(_group_title(pair[1]))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 5)
		flow.add_theme_constant_override("v_separation", 5)
		%RegionNav.add_child(flow)
		for record in groups.get(pair[0], []):
			var button := _chip(str(record.name))
			button.pressed.connect(_select_region.bind(str(record.id)))
			flow.add_child(button)
			region_buttons[record.id] = button

func _select_nav(id: String) -> void:
	nav_id = id
	page = 0
	_refresh_list()

func _select_region(id: String) -> void:
	region_id = id
	region_tag = ""
	page = 0
	_refresh_list()

func _refresh_list() -> void:
	_paint_nav()
	var rows: Array = []
	if mode == "region":
		%CenterTitle.text = "%s · 全部内容" % index.region_name(region_id)
		rows = index.list_region(region_id, true)
		if not region_tag.is_empty():
			var filtered: Array = []
			for record in rows:
				if str(record.category) == region_tag:
					filtered.append(record)
			rows = filtered
		_fill_region_tags()
	else:
		var title := _nav_label(nav_id)
		%CenterTitle.text = "%s · 内容目录" % title
		rows = _rows_for_nav(nav_id)
		_fill_category_tags(rows)
	rows = index.search(rows, search_text)
	if issues_only:
		var flagged: Array = []
		for record in rows:
			if str(record.status) == "待检查":
				flagged.append(record)
		rows = flagged
	visible_rows = index.sort_rows(rows, sort_mode)
	if page * PAGE_SIZE >= visible_rows.size():
		page = 0
	_configure_columns()
	_render_page()
	%CountLabel.text = "显示 %d 项" % visible_rows.size()

func _rows_for_nav(id: String) -> Array:
	if id.begins_with("item:"):
		return index.list_category("item", id.get_slice(":", 1))
	return index.list_category(id)

func _fill_region_tags() -> void:
	_clear(%Tags)
	var counts: Dictionary = index.region_counts(region_id)
	for tag in REGION_TAGS:
		var button := _chip("%s %d" % [tag.label, int(counts.get(tag.id, 0))])
		button.toggle_mode = true
		button.button_pressed = region_tag == tag.id
		button.pressed.connect(func():
			region_tag = "" if region_tag == tag.id else tag.id
			page = 0
			_refresh_list()
		)
		%Tags.add_child(button)

func _fill_category_tags(rows: Array) -> void:
	_clear(%Tags)
	var chip := _chip("%s %d" % [_nav_label(nav_id), rows.size()])
	chip.disabled = true
	%Tags.add_child(chip)
	if not index.issues.is_empty() and nav_id != "":
		var flagged := 0
		for record in rows:
			if str(record.status) == "待检查":
				flagged += 1
		if flagged > 0:
			%Tags.add_child(_chip("待检查 %d" % flagged))

func _configure_columns() -> void:
	var extra := _extra_title()
	%Tree.columns = 5 if extra.is_empty() else 5
	%Tree.set_column_title(0, "名称")
	%Tree.set_column_title(1, "类型")
	%Tree.set_column_title(2, extra if not extra.is_empty() else "地区")
	%Tree.set_column_title(3, "地区" if not extra.is_empty() else "数据")
	%Tree.set_column_title(4, "数据" if not extra.is_empty() else "")
	for i in %Tree.columns:
		%Tree.set_column_expand(i, i == 0)
		%Tree.set_column_custom_minimum_width(i, 90 if i > 0 else 140)
	%Tree.set_column_title(4, "数据" if not extra.is_empty() else " ")

func _extra_title() -> String:
	if mode == "region":
		return ""
	match nav_id:
		"npc":
			return "境界"
		"monster":
			return "境界"
		"quest":
			return "任务类型"
		"item:equipment", "item:artifact", "item:pill", "item:material", "item:other":
			return "品质"
		"technique":
			return "路线"
		"spell":
			return "属性"
		_:
			return ""

func _render_page() -> void:
	%Tree.clear()
	var root: TreeItem = %Tree.create_item()
	var start := page * PAGE_SIZE
	var stop := mini(start + PAGE_SIZE, visible_rows.size())
	var extra := _extra_title()
	for i in range(start, stop):
		var record: Dictionary = visible_rows[i]
		var item: TreeItem = %Tree.create_item(root)
		item.set_text(0, str(record.name))
		item.set_text(1, str(record.category_label))
		var region_text := _region_label(record)
		var status := str(record.status)
		if record.get("membership", "") == "related" and status != "待检查":
			status = "仅关联"
		if extra.is_empty():
			item.set_text(2, region_text)
			item.set_text(3, status)
		else:
			item.set_text(2, _extra_value(record))
			item.set_text(3, region_text)
			item.set_text(4, status)
		item.set_metadata(0, record.key)
		item.set_custom_bg_color(0, SECONDARY)
		item.set_custom_bg_color(1, SECONDARY)
		item.set_custom_bg_color(2, SECONDARY)
		item.set_custom_bg_color(3, SECONDARY)
		item.set_custom_bg_color(4, SECONDARY)
		if record.key == selected_key:
			item.select(0)
	var pages := maxi(ceili(float(visible_rows.size()) / float(PAGE_SIZE)), 1)
	%PageLabel.text = "上一页  %d / %d  下一页" % [page + 1, pages]
	%Prev.disabled = page <= 0
	%Next.disabled = start + PAGE_SIZE >= visible_rows.size()
	if %Tree.get_selected() == null and stop > start:
		%Tree.get_root().get_first_child().select(0)
		_on_tree_selected()

func _on_tree_selected() -> void:
	var item: TreeItem = %Tree.get_selected()
	if item == null:
		return
	_show_detail(str(item.get_metadata(0)))

func _select_row(key: String) -> void:
	selected_key = key
	for i in visible_rows.size():
		if str(visible_rows[i].key) == key:
			page = int(i / PAGE_SIZE)
			break
	_render_page()
	_show_detail(key)

func _select_current() -> void:
	if not selected_key.is_empty() and index.records.has(selected_key):
		_select_row(selected_key)
		return
	if not visible_rows.is_empty():
		_show_detail(str(visible_rows[0].key))

func _show_detail(key: String) -> void:
	selected_key = key
	var record: Dictionary = index.get_record(key)
	_clear(%Relations)
	if record.is_empty():
		%DetailName.text = "未选择"
		%DetailMeta.text = ""
		%OpenEditor.disabled = true
		return
	%DetailName.text = str(record.name)
	var lines := PackedStringArray()
	lines.append("%s · %s" % [record.category_label, _region_label(record)])
	lines.append("ID：%s" % record.id)
	lines.append("分类：%s" % record.category_label)
	lines.append("所属地区：%s" % _region_label(record))
	lines.append("数据来源：%s" % record.source)
	if record.get("membership", "") == "related":
		lines.append("关系：仅通过商店、掉落或任务关联，不属于该地区专属内容")
	if not record.get("issue_reasons", []).is_empty():
		lines.append("检查：%s" % "；".join(record.issue_reasons))
	%DetailMeta.text = "\n".join(lines)
	for relation in record.get("relations", []):
		var chip := _chip(str(relation.name))
		chip.tooltip_text = "%s · %s" % [relation.label, relation.id]
		chip.pressed.connect(func(): focus_record(str(relation.key)))
		%Relations.add_child(chip)
	if record.get("relations", []).is_empty():
		var empty := Label.new()
		empty.text = "无已登记的 ID 引用"
		empty.add_theme_color_override("font_color", MUTED)
		empty.add_theme_font_size_override("font_size", 13)
		%Relations.add_child(empty)
	var editor := index.editor_for(record)
	%OpenEditor.disabled = editor.is_empty()
	%OpenEditor.tooltip_text = "打开对应编辑器" if editor else "当前分类没有对应的游戏内编辑器"

func _on_open_editor() -> void:
	var record: Dictionary = index.get_record(selected_key)
	var editor := index.editor_for(record)
	if editor.is_empty():
		return
	editor_requested.emit(editor, str(record.id))

func _on_export() -> void:
	var as_json: bool = str(%ExportKind.get_selected_metadata()) == "json"
	var path := "user://xiantu_content_index.json" if as_json else "user://xiantu_content_index.md"
	var error := index.write_export(path, as_json)
	%ExportStatus.text = error if not error.is_empty() else "已导出 %s" % path

func _extra_value(record: Dictionary) -> String:
	var fields: Dictionary = record.get("fields", {})
	match str(record.category):
		"npc", "monster":
			return str(fields.get("realm", "—"))
		"quest":
			return str(fields.get("quest_type", "—"))
		"item":
			return str(fields.get("quality", fields.get("rarity", "—")))
		"technique":
			return "体修" if str(record.subcategory) == "body" else "法修"
		"spell":
			return str(fields.get("element", "—"))
		_:
			return "—"

func _region_label(record: Dictionary) -> String:
	var ids: Array = record.get("region_ids", [])
	if ids.is_empty():
		var related: Array = record.get("related_region_ids", [])
		if related.is_empty():
			return "—"
		return index.region_name(str(related[0]))
	return index.region_name(str(ids[0]))

func _nav_label(id: String) -> String:
	for group in NAV:
		for item in group.items:
			if item.id == id:
				return item.label
	return id

func _paint_mode() -> void:
	_apply_toggle(%ModeCategory, mode == "category")
	_apply_toggle(%ModeRegion, mode == "region")

func _paint_nav() -> void:
	for id in category_buttons:
		_apply_toggle(category_buttons[id], mode == "category" and id == nav_id)
	for id in region_buttons:
		_apply_toggle(region_buttons[id], mode == "region" and id == region_id)

func _apply_toggle(button: Button, on: bool) -> void:
	button.add_theme_stylebox_override("normal", chip_on if on else chip_off)
	button.add_theme_stylebox_override("hover", chip_on if on else chip_off)
	button.add_theme_stylebox_override("pressed", chip_on)
	button.add_theme_color_override("font_color", BTN_TEXT)

func _chip(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 27)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", BTN_TEXT)
	button.add_theme_stylebox_override("normal", chip_off)
	button.add_theme_stylebox_override("hover", chip_on)
	button.add_theme_stylebox_override("pressed", chip_on)
	button.add_theme_stylebox_override("focus", chip_off)
	return button

func _group_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_stylebox_override("normal", _box(GROUP, 6, 4, 0))
	return label

func _styles() -> void:
	chip_off = _box(BTN, 10, 4, 1, BORDER_OFF)
	chip_on = _box(BTN_ON, 10, 4, 1, BORDER_ON)
	chip_normal = chip_off
	%ModeCategory.custom_minimum_size = Vector2(0, 32)
	%ModeRegion.custom_minimum_size = Vector2(0, 32)
	_apply_toggle(%ModeCategory, true)
	_apply_toggle(%ModeRegion, false)
	%Tree.hide_root = true
	%Tree.column_titles_visible = true
	%Tree.select_mode = Tree.SELECT_ROW
	%Tree.add_theme_font_size_override("font_size", 13)
	%Tree.add_theme_constant_override("v_separation", 3)

func _box(color: Color, x: int, y: int, border: int = 0, border_color: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = x
	box.content_margin_right = x
	box.content_margin_top = y
	box.content_margin_bottom = y
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	if border > 0:
		box.border_width_left = border
		box.border_width_top = border
		box.border_width_right = border
		box.border_width_bottom = border
		box.border_color = border_color
	return box

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()
