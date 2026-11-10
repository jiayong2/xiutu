extends Control
## In-game developer item database editor (stage 1).
## UI only submits requests; ItemDatabase validates and writes the existing items.json.

signal closed

const ItemDatabase = preload("res://core/items/item_database.gd")
const ItemReferences = preload("res://core/items/item_references.gd")
const Catalog = preload("res://core/content_catalog.gd")
const EquipmentValues = preload("res://gameplay/inventory/equipment_values.gd")

const CATEGORY_GROUPS := [
	{"key": "all", "label": "全部物品", "types": []},
	{"key": "pill", "label": "丹药", "types": ["丹药"]},
	{"key": "herb", "label": "药材", "types": ["灵草"]},
	{"key": "ore", "label": "矿石 / 材料", "types": ["材料"]},
	{"key": "beast", "label": "妖兽材料", "types": ["战利品"]},
	{"key": "equip", "label": "装备", "types": ["装备", "防具", "武器"]},
	{"key": "artifact", "label": "法宝", "types": ["法宝"]},
	{"key": "function", "label": "功能道具", "types": ["消耗品", "种子", "秘籍"]},
	{"key": "quest", "label": "任务物品", "types": []},
	{"key": "other", "label": "其他", "types": []},
]
const SOURCE_GROUPS := ["shops", "monsters", "routes", "quests", "recipes", "auction",
	"initial", "exploration", "npc", "herbs", "inns"]

var catalog: Dictionary = {}
var runtime: Dictionary = {}
var data_path := ItemDatabase.PATH
var propagate_to_game := true

var _rows: Array = []
var _saved_rows: Array = []
var _active_id := ""
var _dirty := false
var _loading_form := false
var _load_failed := false
var _can_edit := true
var _category_filter := "all"
var _category_buttons: Dictionary = {}
var _quest_items: Dictionary = {}
var _reference_map: Dictionary = {}
var _icon_cache: Dictionary = {}
var _pending_transition: Callable = Callable()
var _pending_delete_id := ""
var _pending_delete_is_draft := false
var _refreshing_tree := false

func _ready() -> void:
	if catalog.is_empty():
		var loaded := Catalog.new()
		if loaded.load_all():
			catalog = loaded.tables
		else:
			catalog = {}
	_can_edit = not catalog.is_empty() and (not data_path.begins_with("res://") or OS.has_feature("editor"))
	var loaded_rows := ItemDatabase.read_rows(data_path)
	if not str(loaded_rows.get("error", "")).is_empty():
		_load_failed = true
		_rows = []
		_saved_rows = []
		_set_status("载入失败：" + str(loaded_rows.error), true)
		%Save.disabled = true
		%New.disabled = true
	else:
		_rows = loaded_rows.rows
		_saved_rows = _rows.duplicate(true)
	if catalog.is_empty():
		_set_status("内容目录未加载，编辑器只读；请先修复启动校验。", true)
	_set_tab_titles()
	_configure_tree()
	_populate_static_filters()
	_connect_signals()
	_populate_type_options()
	_populate_rarity_options()
	_reference_map = ItemReferences.all_references(catalog, runtime)
	_rebuild_quest_items()
	_rebuild_categories()
	_update_edit_capability()
	_refresh_list()
	_update_stats()
	if _rows.is_empty():
		_clear_form()
		if _load_failed:
			_set_status("载入失败，编辑器只读；请检查数据文件或恢复备份。", true)
		else:
			_set_status("物品表为空；请检查 %s。" % data_path, true)
	else:
		_select_row(_rows[0].id)
		var mode := "开发模式可写"
		if not _can_edit:
			mode = "只读 · 内容目录未加载" if catalog.is_empty() else "只读 · 导出版本"
		_set_status("数据源：%s · 已加载 %d 件物品（%s）。" % [data_path, _rows.size(), mode])
	_update_dirty_ui()

func _set_tab_titles() -> void:
	var titles := ["基础资料", "属性效果", "获取途径", "关联引用", "测试预览"]
	for index in titles.size():
		%Tabs.set_tab_title(index, titles[index])

func _configure_tree() -> void:
	%Tree.select_mode = Tree.SELECT_ROW
	%Tree.column_titles_visible = true
	%Tree.hide_root = true
	%Tree.set_column_title(0, "图标")
	%Tree.set_column_title(1, "名称")
	%Tree.set_column_title(2, "ID")
	%Tree.set_column_title(3, "类别")
	%Tree.set_column_title(4, "品质")
	%Tree.set_column_expand(0, false)
	%Tree.set_column_custom_minimum_width(0, 48)
	%Tree.set_column_expand(1, true)
	%Tree.set_column_custom_minimum_width(1, 120)
	%Tree.set_column_clip_content(1, true)
	%Tree.set_column_expand(2, false)
	%Tree.set_column_custom_minimum_width(2, 230)
	%Tree.set_column_clip_content(2, true)
	%Tree.set_column_expand(3, false)
	%Tree.set_column_custom_minimum_width(3, 80)
	%Tree.set_column_expand(4, false)
	%Tree.set_column_custom_minimum_width(4, 64)
	%CategoryList.add_theme_constant_override("separation", 5)

func _connect_signals() -> void:
	%Search.text_changed.connect(_on_search_changed)
	%QualityFilter.item_selected.connect(_on_filter_changed)
	%StatusFilter.item_selected.connect(_on_filter_changed)
	%SortFilter.item_selected.connect(_on_filter_changed)
	%Tree.item_selected.connect(_on_tree_item_selected)
	%New.pressed.connect(_request_new)
	%Copy.pressed.connect(_request_copy)
	%Delete.pressed.connect(_request_delete)
	%Reset.pressed.connect(_reset_current)
	%Save.pressed.connect(_on_save_pressed)
	%Check.pressed.connect(_run_check)
	%Close.pressed.connect(request_close)
	%ItemId.text_changed.connect(_on_form_changed)
	%ItemName.text_changed.connect(_on_form_changed)
	%ItemType.item_selected.connect(_on_form_changed)
	%ItemRarity.item_selected.connect(_on_form_changed)
	%BuyPrice.value_changed.connect(_on_form_changed)
	%SellPrice.value_changed.connect(_on_form_changed)
	%StackLimit.value_changed.connect(_on_form_changed)
	%Description.text_changed.connect(_on_form_changed)
	%UnsavedDialog.confirmed.connect(func() -> void: _resolve_pending("save"))
	%UnsavedDialog.custom_action.connect(_on_unsaved_custom)
	%UnsavedDialog.canceled.connect(_cancel_pending)
	%UnsavedDialog.add_button("放弃修改", true, "discard")
	%DeleteDialog.confirmed.connect(_confirm_delete)
	%DeleteDialog.canceled.connect(_on_delete_canceled)

func _populate_static_filters() -> void:
	%StatusFilter.clear()
	var statuses := [
		["全部状态", ""], ["可堆叠", "stack"], ["唯一物品", "unique"],
		["可使用", "usable"], ["已引用", "referenced"], ["未引用", "unreferenced"],
	]
	for entry in statuses:
		_add_option(%StatusFilter, entry[0], entry[1])
	%SortFilter.clear()
	var sorts := [
		["默认顺序", "default"], ["名称", "name"], ["ID", "id"],
		["品质", "rarity"], ["购买价格", "price"], ["堆叠数量", "stack"],
	]
	for entry in sorts:
		_add_option(%SortFilter, entry[0], entry[1])
	%StatusFilter.select(0)
	%SortFilter.select(0)
	_populate_quality_filter()

func _populate_quality_filter() -> void:
	var current := _selected_metadata(%QualityFilter)
	%QualityFilter.clear()
	_add_option(%QualityFilter, "全部品质", "")
	var values := ItemDatabase.rarities(_rows)
	for value in values:
		_add_option(%QualityFilter, ItemDatabase.rarity_label(value), value)
	_select_option(%QualityFilter, current)
	if %QualityFilter.selected < 0:
		%QualityFilter.select(0)

func _populate_type_options() -> void:
	var current := _selected_metadata(%ItemType)
	%ItemType.clear()
	for value in ItemDatabase.types(_rows):
		_add_option(%ItemType, value, value)
	if not current.is_empty() and not _option_has(%ItemType, current):
		_add_option(%ItemType, current, current)
	if not current.is_empty():
		_select_option(%ItemType, current)

func _populate_rarity_options() -> void:
	var current := _selected_metadata(%ItemRarity)
	%ItemRarity.clear()
	for value in ItemDatabase.rarities(_rows):
		_add_option(%ItemRarity, ItemDatabase.rarity_label(value), value)
	if not current.is_empty() and not _option_has(%ItemRarity, current):
		_add_option(%ItemRarity, ItemDatabase.rarity_label(current), current)
	if not current.is_empty():
		_select_option(%ItemRarity, current)

func _rebuild_categories() -> void:
	_clear_children(%CategoryList)
	_category_buttons.clear()
	var counts := _category_counts()
	var group := ButtonGroup.new()
	for definition in CATEGORY_GROUPS:
		var key: String = definition.key
		var button := Button.new()
		button.text = "%s  %d" % [definition.label, int(counts.get(key, 0))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34
		button.pressed.connect(_set_category.bind(key))
		%CategoryList.add_child(button)
		_category_buttons[key] = button
	_update_category_buttons()

func _update_category_buttons() -> void:
	for key in _category_buttons:
		_category_buttons[key].set_pressed_no_signal(key == _category_filter)

func category_count() -> int:
	return CATEGORY_GROUPS.size() - 1

func _category_counts() -> Dictionary:
	var counts := {}
	for definition in CATEGORY_GROUPS:
		counts[definition.key] = 0
	for row in _rows:
		if not row is Dictionary:
			continue
		counts.all = int(counts.all) + 1
		var matched := false
		for definition in CATEGORY_GROUPS:
			if definition.key in ["all", "quest", "other"]:
				continue
			if definition.types.has(row.get("type", "")):
				counts[definition.key] = int(counts[definition.key]) + 1
				matched = true
		if not matched:
			counts.other = int(counts.other) + 1
		if _quest_items.has(row.get("id", "")):
			counts.quest = int(counts.quest) + 1
	return counts

func _mapped_types() -> Array:
	var result: Array = []
	for definition in CATEGORY_GROUPS:
		for value in definition.types:
			if value not in result:
				result.append(value)
	return result

func _rebuild_quest_items() -> void:
	_quest_items.clear()
	var item_ids := ItemDatabase.ids_of(_rows)
	var quests: Variant = catalog.get("quests", {})
	if not quests is Dictionary:
		return
	for quest in quests.values():
		if not quest is Dictionary:
			continue
		var required: Variant = quest.get("required_item", "")
		if required is String and item_ids.has(required):
			_quest_items[required] = true
		var rewards: Variant = quest.get("rewards", {})
		if rewards is Dictionary:
			for item_id in rewards:
				if item_ids.has(str(item_id)):
					_quest_items[str(item_id)] = true
		var objectives: Variant = quest.get("objectives", [])
		if objectives is Array:
			for objective in objectives:
				if objective is Dictionary and objective.get("target_id") is String:
					if item_ids.has(objective.target_id):
						_quest_items[objective.target_id] = true

func _category_match(row: Dictionary, key: String) -> bool:
	if key == "all":
		return true
	if key == "quest":
		return _quest_items.has(row.get("id", ""))
	if key == "other":
		return not _mapped_types().has(row.get("type", ""))
	for definition in CATEGORY_GROUPS:
		if definition.key == key:
			return definition.types.has(row.get("type", ""))
	return true

func _filtered_rows() -> Array:
	var query: String = str(%Search.text).strip_edges().to_lower()
	var quality := _selected_metadata(%QualityFilter)
	var status := _selected_metadata(%StatusFilter)
	var result: Array = []
	for row in _rows:
		if not row is Dictionary:
			continue
		if not _category_match(row, _category_filter):
			continue
		if not quality.is_empty() and str(row.get("rarity", "")) != quality:
			continue
		if not status.is_empty() and not _status_match(row, status):
			continue
		if not query.is_empty():
			var name := str(row.get("name", "")).to_lower()
			var item_id := str(row.get("id", "")).to_lower()
			var type := str(row.get("type", "")).to_lower()
			if not (name.contains(query) or item_id.contains(query) or type.contains(query)):
				continue
		result.append(row)
	_sort_rows(result)
	return result

func _status_match(row: Dictionary, status: String) -> bool:
	match status:
		"stack":
			return int(row.get("stack_limit", 0)) > 1
		"unique":
			return int(row.get("stack_limit", 0)) == 1
		"usable":
			return ItemDatabase.is_usable(row)
		"referenced":
			return _refs(str(row.get("id", ""))).get("total", 0) > 0
		"unreferenced":
			return _refs(str(row.get("id", ""))).get("total", 0) == 0
	return true

func _sort_rows(rows: Array) -> void:
	match _selected_metadata(%SortFilter):
		"name":
			rows.sort_custom(func(a, b) -> bool: return _sort_text(a) < _sort_text(b))
		"id":
			rows.sort_custom(func(a, b) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
		"rarity":
			rows.sort_custom(func(a, b) -> bool:
				var left := ItemDatabase.rarity_rank(str(a.get("rarity", "")))
				var right := ItemDatabase.rarity_rank(str(b.get("rarity", "")))
				if left == right:
					return _sort_text(a) < _sort_text(b)
				return left < right)
		"price":
			rows.sort_custom(func(a, b) -> bool:
				var left := int(a.get("buy_price", 0))
				var right := int(b.get("buy_price", 0))
				if left == right:
					return _sort_text(a) < _sort_text(b)
				return left < right)
		"stack":
			rows.sort_custom(func(a, b) -> bool:
				var left := int(a.get("stack_limit", 0))
				var right := int(b.get("stack_limit", 0))
				if left == right:
					return _sort_text(a) < _sort_text(b)
				return left > right)

func _sort_text(row: Dictionary) -> String:
	return str(row.get("name", "")).to_lower() + "|" + str(row.get("id", ""))

func _refresh_list(select_id := "") -> void:
	if _refreshing_tree:
		call_deferred("_refresh_list", select_id)
		return
	_rebuild_item_list(select_id)

func _rebuild_item_list(select_id := "") -> void:
	if not is_instance_valid(%Tree):
		return
	var tree: Tree = %Tree
	var had_select_signal := tree.item_selected.is_connected(_on_tree_item_selected)
	if had_select_signal:
		tree.item_selected.disconnect(_on_tree_item_selected)
	var target := select_id if not select_id.is_empty() else _active_id
	_refreshing_tree = true
	tree.clear()
	var root: TreeItem = tree.create_item()
	var shown: Array = _filtered_rows()
	var selected_item: TreeItem = null
	for row in shown:
		var item: TreeItem = tree.create_item(root)
		item.set_metadata(0, row.get("id", ""))
		item.set_text(1, str(row.get("name", "")) + ("  （草稿）" if _is_draft(str(row.get("id", ""))) else ""))
		item.set_text(2, str(row.get("id", "")))
		item.set_text(3, str(row.get("type", "")))
		item.set_text(4, ItemDatabase.rarity_label(str(row.get("rarity", ""))))
		item.set_tooltip_text(1, str(row.get("name", "")))
		item.set_tooltip_text(2, str(row.get("id", "")))
		item.set_icon(0, _icon_for(str(row.get("rarity", "")), _is_draft(str(row.get("id", "")))))
		if str(row.get("id", "")) == target:
			selected_item = item
	if selected_item != null:
		selected_item.select(0)
		tree.scroll_to_item(selected_item)
	_refreshing_tree = false
	if had_select_signal:
		tree.item_selected.connect(_on_tree_item_selected)
	%ListCount.text = "显示 %d 件 · 共 %d 件 · 分类 %d" % [shown.size(), _rows.size(), category_count()]

func _sync_tree_selection(item_id := "") -> void:
	var target := item_id if not item_id.is_empty() else _active_id
	if target.is_empty() or not is_instance_valid(%Tree):
		return
	var root: TreeItem = %Tree.get_root()
	if root == null:
		return
	_refreshing_tree = true
	var item := root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == target:
			if %Tree.get_selected() != item:
				item.select(0)
			_refreshing_tree = false
			return
		item = item.get_next()
	_refreshing_tree = false

func _icon_for(rarity: String, draft: bool) -> Texture2D:
	var key := ("draft" if draft else rarity)
	if _icon_cache.has(key):
		return _icon_cache[key]
	var image := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	var fill := _rarity_color(rarity, draft)
	image.fill(fill)
	var border := fill.lightened(0.28)
	for x in 22:
		image.set_pixel(x, 0, border)
		image.set_pixel(x, 21, border)
	for y in 22:
		image.set_pixel(0, y, border)
		image.set_pixel(21, y, border)
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[key] = texture
	return texture

func _rarity_color(rarity: String, draft := false) -> Color:
	if draft:
		return Color("d6b25e")
	match rarity:
		"uncommon":
			return Color("4f9d7d")
		"rare":
			return Color("c9a85c")
		_:
			return Color("6d7f7a")

func _on_search_changed(_text: String) -> void:
	_refresh_list(_active_id)

func _on_filter_changed(_index: int) -> void:
	_refresh_list(_active_id)

func _on_tree_item_selected() -> void:
	if _refreshing_tree:
		return
	var item: TreeItem = %Tree.get_selected()
	if item == null:
		return
	# Tree blocks clear()/create_item() until item_selected returns.
	_request_select.call_deferred(str(item.get_metadata(0)))

func _set_category(key: String) -> void:
	_category_filter = key
	_update_category_buttons()
	_refresh_list(_active_id)

func _request_select(item_id: String) -> void:
	if item_id.is_empty() or item_id == _active_id:
		return
	if _row_index(item_id) < 0:
		return
	if _dirty:
		_pending_transition = func() -> void: _select_row(item_id)
		_show_unsaved()
		return
	_select_row(item_id)

func _select_row(item_id: String, keep_dirty := false) -> void:
	var index := _row_index(item_id)
	if index < 0:
		return
	_active_id = item_id
	if not keep_dirty:
		_dirty = false
	var row: Dictionary = _rows[index]
	_apply_form(row)
	_refresh_detail_views()
	_sync_tree_selection(_active_id)
	_update_dirty_ui()

func _apply_form(row: Dictionary) -> void:
	_loading_form = true
	_set_form_enabled(_can_edit)
	%ItemId.text = str(row.get("id", ""))
	%ItemId.editable = _can_edit and _is_draft(str(row.get("id", "")))
	%ItemName.text = str(row.get("name", ""))
	var item_type := str(row.get("type", ""))
	if not _option_has(%ItemType, item_type):
		_add_option(%ItemType, item_type, item_type)
	_select_option(%ItemType, item_type)
	var rarity := str(row.get("rarity", "common"))
	if not _option_has(%ItemRarity, rarity):
		_add_option(%ItemRarity, ItemDatabase.rarity_label(rarity), rarity)
	_select_option(%ItemRarity, rarity)
	%BuyPrice.value = int(row.get("buy_price", 0))
	%SellPrice.value = int(row.get("sell_price", 0))
	%StackLimit.value = int(row.get("stack_limit", 1))
	%Description.text = str(row.get("description", ""))
	%Tradeable.button_pressed = ItemDatabase.is_tradable(row)
	%Discardable.button_pressed = false
	%Usable.button_pressed = ItemDatabase.is_usable(row)
	%ItemSubtype.text = "现有数据未定义（预留扩展）"
	_update_form_meta_from_controls()
	_loading_form = false

func _set_form_enabled(enabled: bool) -> void:
	%ItemId.editable = enabled
	%ItemName.editable = enabled
	%ItemType.disabled = not enabled
	%ItemRarity.disabled = not enabled
	%BuyPrice.editable = enabled
	%SellPrice.editable = enabled
	%StackLimit.editable = enabled
	%Description.editable = enabled
	%Tradeable.disabled = true
	%Discardable.disabled = true
	%Usable.disabled = true

func _collect_form() -> void:
	if _active_id.is_empty():
		return
	var index := _row_index(_active_id)
	if index < 0:
		return
	var row: Dictionary = _rows[index]
	row["name"] = %ItemName.text
	var item_type := _selected_metadata(%ItemType)
	if not item_type.is_empty():
		row["type"] = item_type
	var rarity := _selected_metadata(%ItemRarity)
	if not rarity.is_empty():
		row["rarity"] = rarity
	row["buy_price"] = int(%BuyPrice.value)
	row["sell_price"] = int(%SellPrice.value)
	row["stack_limit"] = int(%StackLimit.value)
	row["description"] = %Description.text
	if not row.has("use_effect"):
		row["use_effect"] = null

func _on_form_changed(_value: Variant = null) -> void:
	if _loading_form or not _can_edit or _active_id.is_empty():
		return
	_collect_form()
	_dirty = true
	_update_form_meta_from_controls()
	_update_active_tree_row()
	_update_dirty_ui()

func _update_form_meta_from_controls() -> void:
	if _active_id.is_empty():
		%MetaName.text = "未选择物品"
		%MetaId.text = "物品 ID · —"
		%PreviewItem.text = "当前未选择物品"
		return
	var name: String = str(%ItemName.text).strip_edges()
	var id_text: String = str(%ItemId.text).strip_edges()
	var rarity: String = _selected_metadata(%ItemRarity)
	var draft := _is_draft(_active_id)
	%MetaName.text = name if not name.is_empty() else "未命名物品"
	var suffix := ""
	if id_text != _active_id:
		suffix = " · 保存后生效"
	if draft:
		suffix += " · 未保存草稿"
	%MetaId.text = "物品 ID · %s%s" % [id_text, suffix]
	%IconRect.color = _rarity_color(rarity, draft)
	%PreviewItem.text = "当前物品：%s（%s）" % [name if not name.is_empty() else "未命名物品", id_text]
	%EditTitle.text = "编辑物品 · %s%s" % [name if not name.is_empty() else "未命名物品", "  *" if _dirty else ""]

func _update_active_tree_row() -> void:
	var root: TreeItem = %Tree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if str(item.get_metadata(0)) == _active_id:
			item.set_text(1, str(%ItemName.text) + ("  （草稿）" if _is_draft(_active_id) else ""))
			item.set_text(2, str(%ItemId.text))
			item.set_text(3, _selected_metadata(%ItemType))
			item.set_text(4, ItemDatabase.rarity_label(_selected_metadata(%ItemRarity)))
			item.set_icon(0, _icon_for(_selected_metadata(%ItemRarity), _is_draft(_active_id)))
			return
		item = item.get_next()

func _refresh_detail_views() -> void:
	if _active_id.is_empty() or _row_index(_active_id) < 0:
		_clear_detail_views()
		return
	var row := _row(_active_id)
	_refresh_effects(row)
	_refresh_sources(_active_id)
	_refresh_refs(_active_id)
	_update_form_meta_from_controls()

func _clear_detail_views() -> void:
	_refresh_effects({})
	_refresh_sources("")
	_refresh_refs("")

func _refresh_effects(row: Dictionary) -> void:
	_clear_children(%EffectsBody)
	if row.is_empty():
		_add_text(%EffectsBody, "请选择一件物品以查看现有属性结构。")
		return
	_add_heading(%EffectsBody, "基础使用效果")
	var effect: Variant = row.get("use_effect")
	if effect == null:
		_add_text(%EffectsBody, "use_effect：null（该物品没有直接使用效果）")
	elif effect is Dictionary:
		if effect.has("learn"):
			var target := str(effect.learn)
			var target_name := target
			var kind := "未知"
			if catalog.get("techniques", {}).has(target):
				target_name = str(catalog.techniques[target].get("name", target))
				kind = "功法"
			elif catalog.get("spells", {}).has(target):
				target_name = str(catalog.spells[target].get("name", target))
				kind = "法术"
			_add_text(%EffectsBody, "学习目标：%s（%s · %s）" % [target_name, kind, target])
		if effect.has("stat"):
			var stat_name: String = "生命" if str(effect.stat) == "hp" else "灵力"
			_add_text(%EffectsBody, "恢复%s：+%d" % [stat_name, int(effect.get("amount", 0))])
		_add_text(%EffectsBody, "原始效果结构：" + JSON.stringify(effect))
	else:
		_add_text(%EffectsBody, "use_effect 结构无效：" + str(effect), Color("ef8f86"))
	_add_heading(%EffectsBody, "装备数值定义")
	var equipment: Dictionary = _catalog_table("equipment")
	if equipment.has(row.get("id", "")):
		var definition: Dictionary = equipment[row.id]
		var slot := str(definition.get("slot", ""))
		_add_text(%EffectsBody, "部位：%s（%s）" % [str(EquipmentValues.SLOTS.get(slot, slot)), slot])
		if definition.has("tier"):
			_add_text(%EffectsBody, "器阶：%s · 品质：%s · 五行：%s" % [
				str(definition.get("tier", "")), str(definition.get("quality", "")),
				str(definition.get("element", ""))])
		if definition.get("recommended_realm") is Array:
			var realms: Array = []
			for value in definition.recommended_realm:
				realms.append(str(int(value)))
			_add_text(%EffectsBody, "推荐境界档：" + ", ".join(realms))
		if definition.get("base_stats") is Dictionary:
			var stats: Array = []
			for stat in definition.base_stats:
				var value := int(definition.base_stats[stat])
				stats.append("%s %s%d" % [str(EquipmentValues.STATS.get(stat, stat)), "+" if value >= 0 else "", value])
			_add_text(%EffectsBody, "基础属性：" + ", ".join(stats))
		if definition.get("traits") is Array and not definition.traits.is_empty():
			for entry in definition.traits:
				if entry is Dictionary:
					_add_text(%EffectsBody, "特殊效果：%s · %s %d" % [
						str(entry.get("name", "未命名")), str(entry.get("type", "")),
						int(entry.get("amount", 0))])
		for key in ["hp", "attack", "defense"]:
			if definition.has(key):
				_add_text(%EffectsBody, "%s：%d" % [str(EquipmentValues.STATS.get(key, key)), int(definition[key])])
		if definition.has("realm"):
			_add_text(%EffectsBody, "装备境界要求：%d" % int(definition.realm))
	else:
		_add_text(%EffectsBody, "未找到 equipment.json 定义。该物品按基础物品处理；装备数值编辑留待第二阶段。")
	_add_heading(%EffectsBody, "法宝定义")
	var artifacts: Dictionary = _catalog_table("artifacts")
	if artifacts.has(row.get("id", "")):
		_add_text(%EffectsBody, "独立法宝表定义：" + JSON.stringify(artifacts[row.id]))
	else:
		_add_text(%EffectsBody, "未收录于独立法宝表 artifacts.json。artifacts.json 不并入 items.json，避免破坏现有法宝系统。")

func _refresh_sources(item_id: String) -> void:
	_clear_children(%SourcesBody)
	if item_id.is_empty():
		_add_text(%SourcesBody, "请选择一件物品。")
		return
	if _is_draft(item_id):
		_add_text(%SourcesBody, "草稿尚未保存，暂无获取途径。保存后可查询现有配置。")
		return
	var refs := _refs(item_id)
	var shown := 0
	for group in refs.get("groups", []):
		if str(group.get("key", "")) not in SOURCE_GROUPS:
			continue
		if group.rows.is_empty():
			continue
		_add_heading(%SourcesBody, str(group.title))
		for row in group.rows:
			_add_text(%SourcesBody, "• %s：%s" % [str(row.label), str(row.detail)])
			shown += 1
	if shown == 0:
		_add_text(%SourcesBody, "现有配置中未发现该物品的获取途径。")
	_add_text(%SourcesBody, "未覆盖来源：历史存档、authoring/ 作者草稿覆盖、战斗/探索临时状态。", Color("c7b37a"))

func _refresh_refs(item_id: String) -> void:
	_clear_children(%RefsBody)
	if item_id.is_empty():
		%RefsSummary.text = "未选择物品"
		_add_text(%RefsBody, "请选择一件物品。")
		return
	if _is_draft(item_id):
		%RefsSummary.text = "草稿未保存 · 暂无引用"
		_add_text(%RefsBody, "保存后才会进入引用查询；草稿不会写入正式数据库。")
		return
	var refs := _refs(item_id)
	var total := int(refs.get("total", 0))
	%RefsSummary.text = "引用 %d 处 · %s" % [total, "禁止删除" if total > 0 else "可删除（需二次确认）"]
	if total == 0:
		_add_text(%RefsBody, "现有静态配置与当前运行快照中未发现引用。")
	for group in refs.get("groups", []):
		if group.rows.is_empty():
			continue
		_add_heading(%RefsBody, str(group.title))
		for row in group.rows:
			_add_text(%RefsBody, "• %s：%s" % [str(row.label), str(row.detail)])

func _on_save_pressed() -> void:
	_save_current()

func _save_current() -> bool:
	if _active_id.is_empty() or not _can_edit:
		_set_status("当前不可保存：未选择物品或运行在只读模式。", true)
		return false
	_collect_form()
	var index := _row_index(_active_id)
	if index < 0:
		_set_status("当前物品已不存在，请重新选择。", true)
		return false
	var candidate: Array = _rows.duplicate(true)
	var candidate_row: Dictionary = candidate[index]
	if _is_draft(_active_id):
		candidate_row["id"] = %ItemId.text.strip_edges()
	candidate_row["name"] = str(candidate_row.get("name", "")).strip_edges()
	candidate_row["type"] = str(candidate_row.get("type", "")).strip_edges()
	candidate_row["rarity"] = str(candidate_row.get("rarity", "common")).strip_edges()
	candidate[index] = candidate_row
	var previous_saved: Array = _saved_rows.duplicate(true)
	var previous_rows: Array = _rows.duplicate(true)
	var previous_active := _active_id
	var catalog_before: Dictionary = catalog.duplicate(true)
	var result := ItemDatabase.write_rows(candidate, catalog, data_path)
	if not result.success:
		_set_status("保存失败：" + str(result.message), true)
		return false
	var new_id := str(candidate_row.get("id", previous_active))
	_rows = candidate
	_saved_rows = candidate.duplicate(true)
	_active_id = new_id
	_dirty = false
	var reload := _reload_game_data()
	if not reload.ok:
		var rollback := ItemDatabase.write_rows(previous_saved, catalog_before, data_path)
		if rollback.success:
			_rows = previous_rows
			_saved_rows = previous_saved.duplicate(true)
			_active_id = previous_active
			_dirty = false
			_reload_game_data_after_rollback()
			_set_status("保存后重新加载失败，已回滚：" + str(reload.message), true)
			_refresh_all_views()
			if _row_index(_active_id) >= 0:
				_select_row(_active_id)
			return false
		_set_status("文件已写入，但重新加载失败；回滚也失败：" + str(rollback.message) + " / " + str(reload.message), true)
		_refresh_all_views()
		return false
	var suffix := ""
	if not str(result.get("warning", "")).is_empty():
		suffix = " · " + str(result.warning)
	if ItemDatabase.is_equipment_like(candidate_row) and not _catalog_table("equipment").has(new_id):
		suffix += " · 注意：该分类尚无 equipment.json 定义，当前按基础物品处理"
	_set_status("已保存：%s（%d 件物品）%s" % [new_id, _rows.size(), suffix])
	_reference_map = ItemReferences.all_references(catalog, runtime)
	_refresh_all_views()
	_select_row(_active_id)
	return true

func _reload_game_data() -> Dictionary:
	if not propagate_to_game or data_path != ItemDatabase.PATH:
		return {"ok": true, "message": ""}
	var manager := get_node_or_null("/root/GameManager")
	if manager == null:
		return {"ok": false, "message": "GameManager 不可用，无法重新加载运行时数据"}
	if not manager.catalog.load_all():
		return {"ok": false, "message": manager.catalog.error}
	manager.operations.configure(manager.catalog.tables)
	catalog = manager.catalog.tables
	runtime = manager.operations.snapshot()
	manager.operations.changed.emit()
	return {"ok": true, "message": ""}

func _reload_game_data_after_rollback() -> void:
	if not propagate_to_game or data_path != ItemDatabase.PATH:
		return
	var manager := get_node_or_null("/root/GameManager")
	if manager == null:
		return
	if manager.catalog.load_all():
		manager.operations.configure(manager.catalog.tables)
		catalog = manager.catalog.tables
		runtime = manager.operations.snapshot()
		manager.operations.changed.emit()

func _request_new() -> void:
	_guard_or_call(Callable(self, "_new_draft"))

func _new_draft() -> void:
	var item_type := _default_new_type()
	_reset_list_filters()
	var draft := ItemDatabase.create_draft(ItemDatabase.ids_of(_rows), item_type)
	_rows.append(draft)
	_active_id = str(draft.id)
	_dirty = true
	%Tabs.current_tab = 0
	_reference_map = ItemReferences.all_references(catalog, runtime)
	_apply_form(draft)
	_refresh_all_views()
	_select_row(_active_id, true)
	_set_status("已创建未保存草稿：%s。填写后点击“保存修改”。" % _active_id)
	%ItemName.grab_focus()

func _default_new_type() -> String:
	for definition in CATEGORY_GROUPS:
		if definition.key == _category_filter and not definition.types.is_empty():
			return str(definition.types[0])
	return "材料"

func _request_copy() -> void:
	if _active_id.is_empty():
		return
	_guard_or_call(Callable(self, "_copy_active"))

func _copy_active() -> void:
	var source := _row(_active_id)
	if source.is_empty():
		return
	var draft := ItemDatabase.copy_draft(source, ItemDatabase.ids_of(_rows))
	_reset_list_filters()
	_rows.append(draft)
	_active_id = str(draft.id)
	_dirty = true
	%Tabs.current_tab = 0
	_reference_map = ItemReferences.all_references(catalog, runtime)
	_apply_form(draft)
	_refresh_all_views()
	_select_row(_active_id, true)
	var warning := ""
	if _catalog_table("equipment").has(source.get("id", "")):
		warning = "；该物品有 equipment.json 定义，副本只复制基础资料，装备数值定义未复制（第二阶段处理）"
	_set_status("已复制为草稿：%s%s。保存后写入。" % [_active_id, warning], not warning.is_empty())

func _reset_list_filters() -> void:
	_category_filter = "all"
	_update_category_buttons()
	%Search.text = ""
	%QualityFilter.select(0)
	%StatusFilter.select(0)
	%SortFilter.select(0)

func _request_delete() -> void:
	if _active_id.is_empty():
		return
	_guard_or_call(Callable(self, "_delete_active"))

func _delete_active() -> void:
	if _active_id.is_empty():
		return
	%UnsavedDialog.hide()
	%DeleteDialog.hide()
	_pending_delete_id = _active_id
	_pending_delete_is_draft = _is_draft(_active_id)
	if _pending_delete_is_draft:
		%DeleteDialog.dialog_text = "确定删除未保存草稿“%s”？此操作不会写入正式数据库。" % str(_row(_active_id).get("name", _active_id))
		%DeleteDialog.popup_centered(Vector2i(600, 240))
		return
	var refs := _refs(_active_id)
	if int(refs.get("total", 0)) > 0:
		_pending_delete_id = ""
		_show_message("无法删除", _reference_block_message(_active_id, refs), Vector2i(820, 460))
		return
	%DeleteDialog.dialog_text = "确定删除“%s”（%s）？\n将写入 %s。\n当前配置与运行快照未发现引用；历史存档未逐个检查，旧档可能仍持有该物品。" % [
		str(_row(_active_id).get("name", "")), _active_id, data_path]
	%DeleteDialog.popup_centered(Vector2i(680, 300))

func _confirm_delete() -> void:
	%DeleteDialog.hide()
	if _pending_delete_id.is_empty():
		return
	var index := _row_index(_pending_delete_id)
	if index < 0:
		_pending_delete_id = ""
		return
	if _pending_delete_is_draft:
		_rows.remove_at(index)
		_active_id = ""
		_dirty = false
		_set_status("已删除未保存草稿。")
		_reference_map = ItemReferences.all_references(catalog, runtime)
		_refresh_all_views()
		_select_first_visible()
		_pending_delete_id = ""
		return
	var removed: Dictionary = _rows[index]
	var removed_id := str(removed.get("id", _pending_delete_id))
	var previous_saved: Array = _saved_rows.duplicate(true)
	var previous_rows: Array = _rows.duplicate(true)
	var catalog_before: Dictionary = catalog.duplicate(true)
	_rows.remove_at(index)
	var result := ItemDatabase.write_rows(_rows, catalog, data_path)
	if not result.success:
		_rows.insert(index, removed)
		_set_status("删除失败：" + str(result.message), true)
		_pending_delete_id = ""
		return
	_saved_rows = _rows.duplicate(true)
	_active_id = ""
	_dirty = false
	_pending_delete_id = ""
	var reload := _reload_game_data()
	if not reload.ok:
		var restore := ItemDatabase.write_rows(previous_saved, catalog_before, data_path)
		if restore.success:
			_rows = previous_rows
			_saved_rows = previous_saved.duplicate(true)
			_active_id = removed_id
			_dirty = false
			_reload_game_data_after_rollback()
			_reference_map = ItemReferences.all_references(catalog, runtime)
			_refresh_all_views()
			if _row_index(_active_id) >= 0:
				_select_row(_active_id)
			_set_status("删除后重新加载失败，已回滚：" + str(reload.message), true)
			return
		_set_status("删除已写入，但重新加载失败；回滚也失败：" + str(restore.message) + " / " + str(reload.message), true)
	else:
		_set_status("已删除物品并保存：%s" % removed_id)
	_reference_map = ItemReferences.all_references(catalog, runtime)
	_refresh_all_views()
	_select_first_visible()

func _on_delete_canceled() -> void:
	%DeleteDialog.hide()
	_pending_delete_id = ""
	_pending_delete_is_draft = false

func _reset_current() -> void:
	if _active_id.is_empty():
		return
	var index := _row_index(_active_id)
	if index < 0:
		return
	if _is_draft(_active_id):
		_rows.remove_at(index)
		_active_id = ""
		_dirty = false
		_reference_map = ItemReferences.all_references(catalog, runtime)
		_refresh_all_views()
		_select_first_visible()
		_set_status("已丢弃未保存草稿。")
		return
	var saved_index := _saved_index(_active_id)
	if saved_index < 0:
		return
	_rows[index] = _saved_rows[saved_index].duplicate(true)
	_active_id = str(_rows[index].get("id", ""))
	_dirty = false
	_apply_form(_rows[index])
	_refresh_all_views()
	_select_row(_active_id)
	_set_status("已重置当前修改。")

func _guard_or_call(action: Callable) -> void:
	if _dirty:
		_pending_transition = action
		_show_unsaved()
	else:
		action.call()

func _show_unsaved() -> void:
	%DeleteDialog.hide()
	%MessageDialog.hide()
	%UnsavedDialog.dialog_text = "“%s”有未保存修改。\n请选择保存并继续、放弃修改，或取消。" % str(_row(_active_id).get("name", "当前物品"))
	%UnsavedDialog.popup_centered(Vector2i(620, 250))

func _on_unsaved_custom(action: StringName) -> void:
	if str(action) == "discard":
		_resolve_pending("discard")

func _resolve_pending(choice: String) -> void:
	var action := _pending_transition
	_pending_transition = Callable()
	%UnsavedDialog.hide()
	if not action.is_valid():
		return
	if choice == "save":
		if not _save_current():
			_refresh_list(_active_id)
			if not _active_id.is_empty():
				_update_active_tree_row()
			return
	elif choice == "discard":
		_discard_changes()
	action.call()

func _cancel_pending() -> void:
	_pending_transition = Callable()
	%UnsavedDialog.hide()
	_refresh_list(_active_id)
	if not _active_id.is_empty():
		_update_active_tree_row()

func _discard_changes() -> void:
	var previous := _active_id
	_rows = _saved_rows.duplicate(true)
	_dirty = false
	_active_id = ""
	_reference_map = ItemReferences.all_references(catalog, runtime)
	_refresh_all_views()
	if _row_index(previous) >= 0:
		_select_row(previous)

func focus_item(item_id: String) -> void:
	_select_row(item_id)

func request_close() -> void:
	if _dirty:
		_pending_transition = Callable(self, "_close_now")
		_show_unsaved()
		return
	_close_now()

func _close_now() -> void:
	closed.emit()

func _refresh_all_views() -> void:
	_rebuild_quest_items()
	_rebuild_categories()
	_populate_type_options()
	_populate_rarity_options()
	_populate_quality_filter()
	_refresh_list(_active_id)
	_update_stats()
	if not _active_id.is_empty() and _row_index(_active_id) >= 0:
		_refresh_detail_views()
	else:
		_clear_detail_views()
	_update_dirty_ui()

func _update_stats() -> void:
	%TotalValue.text = str(_rows.size())
	%TypeValue.text = str(category_count())
	var unused := 0
	for row in _rows:
		if _refs(str(row.get("id", ""))).get("total", 0) == 0:
			unused += 1
	%UnusedValue.text = str(unused)
	var issues: Array[String] = ItemReferences.catalog_issues(catalog, ItemDatabase.ids_of(_rows))
	var validation := ItemDatabase.validate_rows(_rows, catalog)
	if not validation.is_empty():
		issues.insert(0, validation)
	%IssueValue.text = str(issues.size())

func _update_edit_capability() -> void:
	_can_edit = not _load_failed and not catalog.is_empty() and (not data_path.begins_with("res://") or OS.has_feature("editor"))
	%New.disabled = not _can_edit
	%Export.disabled = true
	if not _can_edit:
		_set_status("只读模式：物品文件载入失败、内容目录未加载，或导出版本不能写入 res:// 静态配置。", true)

func _update_dirty_ui() -> void:
	var active := not _active_id.is_empty()
	%Save.disabled = not (_can_edit and active and _dirty)
	%Reset.disabled = not (_can_edit and active)
	%Copy.disabled = not (_can_edit and active)
	%Delete.disabled = not (_can_edit and active)
	if _dirty:
		%DirtyLabel.text = "● 未保存修改"
		%DirtyLabel.add_theme_color_override("font_color", Color("e8c878"))
	else:
		%DirtyLabel.text = "无未保存修改"
		%DirtyLabel.add_theme_color_override("font_color", Color("94a8a2"))
	if active:
		var name := str(_row(_active_id).get("name", ""))
		%EditTitle.text = "编辑物品 · %s%s" % [name if not name.is_empty() else "未命名物品", "  *" if _dirty else ""]

func _clear_form() -> void:
	_active_id = ""
	_dirty = false
	_loading_form = true
	%ItemId.text = ""
	%ItemName.text = ""
	%ItemType.select(-1)
	%ItemRarity.select(-1)
	%BuyPrice.value = 0
	%SellPrice.value = 0
	%StackLimit.value = 1
	%Description.text = ""
	%Tradeable.button_pressed = false
	%Discardable.button_pressed = false
	%Usable.button_pressed = false
	_set_form_enabled(false)
	_loading_form = false
	_clear_detail_views()
	_update_form_meta_from_controls()
	_update_dirty_ui()

func _select_first_visible() -> void:
	var shown := _filtered_rows()
	if shown.is_empty():
		_clear_form()
		_refresh_list("")
		return
	var first_id := str(shown[0].get("id", ""))
	_refresh_list(first_id)
	_select_row(first_id)

func _run_check() -> void:
	var issues: Array[String] = []
	var validation := ItemDatabase.validate_rows(_rows, catalog)
	if not validation.is_empty():
		issues.append(validation)
	for issue in ItemReferences.catalog_issues(catalog, ItemDatabase.ids_of(_rows)):
		if issue not in issues:
			issues.append(issue)
	var text := ""
	if issues.is_empty():
		text = "检查通过。\n\n物品：%d 件\n分类：%d 个\n引用来源已检查：商店、怪物掉落、地图采集、任务、配方、拍卖、初始配置、NPC 装备/背包、探索图例。\n未覆盖：历史存档、authoring 草稿覆盖、战斗/探索临时状态。" % [
			_rows.size(), ItemDatabase.types(_rows).size()]
	else:
		text = "发现 %d 个问题：\n\n" % issues.size()
		for index in mini(issues.size(), 12):
			text += "• %s\n" % issues[index]
		if issues.size() > 12:
			text += "…另有 %d 个问题。" % (issues.size() - 12)
		text += "\n保存会被阻止，直到问题修复。"
	_show_message("数据检查", text, Vector2i(820, 460))
	%IssueValue.text = str(issues.size())

func _reference_block_message(item_id: String, refs: Dictionary) -> String:
	var name := str(_row(item_id).get("name", item_id))
	var text := "无法删除“%s”（%s）：仍被 %d 处引用。\n\n" % [name, item_id, int(refs.get("total", 0))]
	var shown := 0
	for group in refs.get("groups", []):
		for row in group.rows:
			if shown >= 12:
				break
			text += "• %s：%s（%s）\n" % [str(group.title), str(row.label), str(row.detail)]
			shown += 1
		if shown >= 12:
			break
	if int(refs.get("total", 0)) > shown:
		text += "…另有 %d 处引用。\n" % (int(refs.get("total", 0)) - shown)
	text += "\n请先在对应系统移除引用；历史存档未逐个检查。"
	return text

func _show_message(title: String, text: String, size: Vector2i) -> void:
	%UnsavedDialog.hide()
	%DeleteDialog.hide()
	%MessageDialog.title = title
	%MessageDialog.dialog_text = text
	%MessageDialog.popup_centered(size)

func _refs(item_id: String) -> Dictionary:
	return _reference_map.get(item_id, {"total": 0, "groups": [], "blocking": false, "unchecked": []})

func _row(item_id: String) -> Dictionary:
	var index := _row_index(item_id)
	return _rows[index] if index >= 0 else {}

func _row_index(item_id: String) -> int:
	for index in _rows.size():
		if _rows[index] is Dictionary and str(_rows[index].get("id", "")) == item_id:
			return index
	return -1

func _saved_index(item_id: String) -> int:
	for index in _saved_rows.size():
		if _saved_rows[index] is Dictionary and str(_saved_rows[index].get("id", "")) == item_id:
			return index
	return -1

func _is_draft(item_id: String) -> bool:
	return _saved_index(item_id) < 0

func _catalog_table(name: String) -> Dictionary:
	var table: Variant = catalog.get(name, {})
	return table if table is Dictionary else {}

func _add_option(option: OptionButton, label: String, value: String) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, value)

func _option_has(option: OptionButton, value: String) -> bool:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			return true
	return false

func _select_option(option: OptionButton, value: String) -> void:
	option.select(-1)
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return

func _selected_metadata(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))

func _set_status(text: String, error := false) -> void:
	%Status.text = text
	%Status.add_theme_color_override("font_color", Color("ef8f86") if error else Color("9fd8c4"))

func _add_heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color("8fd6b8"))
	parent.add_child(label)

func _add_text(parent: Node, text: String, color := Color("b8cbc5")) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
