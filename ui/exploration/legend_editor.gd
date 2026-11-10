extends PanelContainer

signal closed

const Config = preload("res://core/exploration/legend_config.gd")
const Exploration = preload("res://gameplay/exploration_run.gd")
const Symbols = preload("res://addons/exploration_map/legend.gd")
const MapData = preload("res://core/exploration/map_data.gd")

var catalog := {}
var config_path := Config.PATH
var map_directory := MapData.DIRECTORY
var rows := {}
var saved := {}
var allocations := {}
var saved_allocations := {}
var maps := {}
var map_id := ""
var template_counts := {}
var templates := {}
var category_filter := ""
var active_id := ""
var loading_fields := false
var pending: Callable
var load_error := ""
var map_errors: Array[String] = []

func _ready() -> void:
	var read_path := Config.author_read_path() if config_path == Config.PATH else config_path
	var result := Config.read(catalog, read_path)
	load_error = result.get("error", "")
	rows = result.get("rows", {})
	saved = rows.duplicate(true)
	allocations = result.get("allocations", {})
	saved_allocations = allocations.duplicate(true)
	%Save.disabled = not load_error.is_empty()
	%Add.disabled = not load_error.is_empty()
	var filters := {"": "全部", "妖兽": "妖兽", "资源": "资源", "宝箱": "宝箱", "传送": "传送", "其他": "其他"}
	var group := ButtonGroup.new()
	for key in filters:
		var button := Button.new()
		button.text = filters[key]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = key.is_empty()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_filter_list.bind(key))
		%Filter.add_child(button)
	for symbol in Config.TYPES:
		_add_option(%Symbol, symbol, Symbols.title(symbol))
	_add_options(%Trigger, {"arrival": "到达触发", "interact": "主动交互"})
	_add_options(%Respawn, {"none": "不刷新", "reenter": "重新进入时", "interval": "按游戏时间间隔"})
	%Respawn.set_item_disabled(2, true)
	_add_options(%Completion, {"cleared": "标记已完成", "hide": "隐藏图例"})
	%Search.text_changed.connect(func(_value: String) -> void: _refresh_list())
	%Maps.item_selected.connect(_show_map)
	%AllocationType.item_selected.connect(func(_index: int) -> void: _show_allocations())
	%AllocationTotal.value_changed.connect(_set_allocation_total)
	%ApplyAllocation.pressed.connect(_check_allocations)
	%LootMode.item_selected.connect(_change_loot_mode)
	%AddLoot.pressed.connect(_add_loot)
	%Add.pressed.connect(_add_row.bind(false))
	%AddBinding.pressed.connect(_add_binding)
	%Copy.pressed.connect(_add_row.bind(true))
	%Remove.pressed.connect(_confirm_remove)
	%Check.pressed.connect(_check)
	%Save.pressed.connect(_save)
	%Back.pressed.connect(request_close)
	%Confirm.confirmed.connect(func() -> void: pending.call())
	%Preview.draw.connect(_draw_preview)
	%Name.text_changed.connect(_change_name)
	%Symbol.item_selected.connect(_change_symbol)
	%TargetType.item_selected.connect(_change_target_type)
	var option_fields := {"Target": "target_id", "Trigger": "trigger_type",
		"Respawn": "respawn_mode", "Completion": "completion_behavior"}
	for field in option_fields:
		var option: OptionButton = get_node("%" + field)
		option.item_selected.connect(_option_changed.bind(option, option_fields[field]))
	var numeric_fields := {"Level": "level", "Count": "enemy_count", "Interval": "respawn_interval"}
	for field in numeric_fields:
		var spin: SpinBox = get_node("%" + field)
		spin.value_changed.connect(_set_field.bind(numeric_fields[field]))
	%Blocks.toggled.connect(_set_field.bind("blocks_movement"))
	%Repeat.toggled.connect(_set_field.bind("repeatable"))
	_load_maps()
	if active_id.is_empty():
		_select_row(str(rows.keys()[0]) if not rows.is_empty() else "")
	_status(load_error if not load_error.is_empty() else "配置草稿 · 尚未接入探索结算")

func _add_option(option: OptionButton, value: String, label: String) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, value)

func _add_options(option: OptionButton, values: Dictionary) -> void:
	for key in values:
		_add_option(option, key, values[key])

func _select_option(option: OptionButton, value: String) -> void:
	option.select(-1)
	for index in option.item_count:
		if option.get_item_metadata(index) == value:
			option.select(index)
			return

func _refresh_list() -> void:
	var query: String = %Search.text.strip_edges().to_lower()
	_clear_children(%List)
	var visible_rows := templates.duplicate()
	for id in rows:
		if rows[id].get("template_map_id", map_id) == map_id:
			visible_rows[id] = rows[id]
	var groups := {}
	for id in visible_rows:
		var row: Dictionary = visible_rows[id]
		if not category_filter.is_empty() and row.category != category_filter:
			continue
		var title := Symbols.title(row.symbol)
		if not query.is_empty() and not (title.to_lower().contains(query) or row.name.to_lower().contains(query) or id.contains(query)):
			continue
		var current: String = groups.get(row.symbol, "")
		if current.is_empty() or id == active_id or (current != active_id and rows.has(id) and not rows.has(current)):
			groups[row.symbol] = id
	var active_symbol: String = _active_row().get("symbol", "")
	for symbol in groups:
		var id: String = groups[symbol]
		var card := Button.new()
		card.custom_minimum_size.y = 50
		card.toggle_mode = true
		card.set_pressed_no_signal(symbol == active_symbol)
		card.tooltip_text = Symbols.title(symbol)
		card.pressed.connect(_select_row.bind(id))
		%List.add_child(card)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(line)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8
		line.offset_right = -10
		var icon := PanelContainer.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.add_theme_stylebox_override("panel", get_theme_stylebox("normal", "LineEdit"))
		line.add_child(icon)
		icon.add_child(_symbol_preview(symbol, 26))
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = Symbols.title(symbol)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		if template_counts.has(symbol):
			var count := Label.new()
			count.mouse_filter = Control.MOUSE_FILTER_IGNORE
			count.text = str(template_counts[symbol])
			line.add_child(count)

func _symbol_preview(symbol: String, side: int) -> Control:
	var preview := Control.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = Vector2(side, side)
	preview.draw.connect(func() -> void:
		Symbols.paint(preview, symbol, Rect2(Vector2.ZERO, preview.size)))
	return preview

func _filter_list(key: String) -> void:
	category_filter = key
	_refresh_list()

func _active_row() -> Dictionary:
	return rows.get(active_id, templates.get(active_id, {}))

func _editable_row() -> Dictionary:
	if not rows.has(active_id) and templates.has(active_id) and Config.TYPES.has(templates[active_id].symbol):
		rows[active_id] = templates[active_id].duplicate(true)
	return rows.get(active_id, {})

func _select_row(id: String) -> void:
	active_id = id
	var row := _active_row()
	if not row.is_empty() and Config.TYPES.has(row.symbol):
		_select_option(%AllocationType, row.symbol)
	_refresh_fields()
	_refresh_list()
	_show_allocations()

func _refresh_fields() -> void:
	var row := _active_row()
	var editable := not row.is_empty() and Config.TYPES.has(row.symbol)
	%Fields.visible = not row.is_empty()
	%DetailForm.visible = editable
	%Settings.visible = editable
	%Copy.disabled = not editable
	%Remove.disabled = not rows.has(active_id)
	%Preview.queue_redraw()
	if row.is_empty():
		%DetailTitle.text = "图例详细配置 · 请新增或选择图例"
		return
	%DetailTitle.text = row.name
	if not editable:
		%DetailTitle.text += " · 地图标记"
		return
	loading_fields = true
	if %Name.text != row.name:
		%Name.text = row.name
	%StableId.text = row.legend_id if rows.has(active_id) else "地图图例 · 待绑定"
	%Symbol.disabled = templates.has(active_id)
	_select_option(%Symbol, row.symbol)
	%TargetType.clear()
	if row.category == "妖兽":
		_add_option(%TargetType, "monster", "已有妖兽")
	else:
		_add_options(%TargetType, {"none": "无绑定", "item": "已有物品"})
		if row.target_type == "event":
			_add_option(%TargetType, "event", "已有事件（未接入）")
			%TargetType.set_item_disabled(2, true)
	_select_option(%TargetType, row.target_type)
	%Target.clear()
	_add_option(%Target, "", "请选择绑定对象")
	var table: Dictionary = catalog.get(Config.TARGETS.get(row.target_type, ""), {})
	for id in table:
		_add_option(%Target, id, "%s · %s" % [table[id].name, id])
	_select_option(%Target, row.target_id)
	%Target.visible = row.target_type != "none"
	%TargetLabel.visible = %Target.visible
	%TargetTypeCell.visible = row.category != "妖兽"
	for field in [%LevelCell, %CountCell]:
		field.visible = row.category == "妖兽"
	%Level.set_value_no_signal(row.level)
	%Count.set_value_no_signal(row.enemy_count)
	%Interval.set_value_no_signal(row.respawn_interval)
	%Blocks.set_pressed_no_signal(row.blocks_movement)
	%Repeat.set_pressed_no_signal(row.repeatable)
	%Level.editable = false
	%Interval.editable = false
	%Blocks.disabled = true
	%Repeat.disabled = true
	%Trigger.disabled = true
	%Target.disabled = row.target_type == "event"
	_select_option(%Trigger, row.trigger_type)
	_select_option(%Respawn, row.respawn_mode)
	_select_option(%Completion, row.completion_behavior)
	_update_interval_visibility()
	_show_loot()
	_show_bindings(row.symbol)
	var references := _referencing_maps(active_id)
	if not references.is_empty():
		%DetailTitle.text += " · 全局定义，引用地图：%s" % "、".join(references)
	%Preview.queue_redraw()
	loading_fields = false

func _draw_preview() -> void:
	var row := _active_row()
	if not row.is_empty():
		Symbols.paint(%Preview, row.symbol, Rect2(Vector2.ZERO, %Preview.size))

func _change_name(value: String) -> void:
	_set_field(value, "name")
	_refresh_list()
	_show_bindings(_active_row().symbol)

func _change_symbol(index: int) -> void:
	var row := _editable_row()
	if not _referencing_maps(active_id).is_empty():
		_select_option(%Symbol, row.symbol)
		_status("此定义已被地图引用。可复制后更改类型，再调整地图分配。")
		return
	row.symbol = %Symbol.get_item_metadata(index)
	var previous: String = row.category
	row.category = Config.TYPES[row.symbol]
	row.erase("behavior")
	row.erase("enemy_stat_multiplier")
	if (previous == "妖兽") != (row.category == "妖兽"):
		row.target_type = "monster" if row.category == "妖兽" else "none"
		row.target_id = ""
		row.blocks_movement = row.category == "妖兽"
		row.trigger_type = "arrival" if row.category in ["妖兽", "传送"] else "interact"
	_select_row(active_id)
	_status("")

func _change_target_type(index: int) -> void:
	var row := _editable_row()
	row.target_type = %TargetType.get_item_metadata(index)
	row.target_id = ""
	_refresh_fields()
	_status("")

func _option_changed(index: int, option: OptionButton, key: String) -> void:
	_set_field(option.get_item_metadata(index), key)
	if key == "respawn_mode":
		_update_interval_visibility()
	elif key == "target_id":
		var row := _active_row()
		var target: Dictionary = catalog.get(Config.TARGETS.get(row.target_type, ""), {}).get(row.target_id, {})
		if not target.is_empty() and row.name == _binding_draft_name(row.symbol):
			row.name = target.name
		_use_template_count()
		_refresh_fields()
		_refresh_list()
		_show_allocations()

func _update_interval_visibility() -> void:
	%IntervalCell.visible = _active_row().respawn_mode == "interval"

func _set_field(value: Variant, key: String) -> void:
	if not loading_fields:
		var row := _editable_row()
		if row.is_empty():
			return
		row[key] = value
		_status("")

func _add_row(copy: bool) -> void:
	var id := "legend_" + Crypto.new().generate_random_bytes(12).hex_encode()
	var row: Dictionary = _active_row().duplicate(true) if copy else Config.create(id)
	row.legend_id = id
	row.erase("template_map_id")
	if not row.loot_table_id.is_empty():
		row.loot_table_id = id
	if copy:
		row.name += "（副本）"
	rows[id] = row
	%Search.clear()
	%Filter.get_child(0).button_pressed = true
	category_filter = ""
	_select_row(id)
	_status("")

func _binding_draft_name(symbol: String) -> String:
	return Symbols.title(symbol) + "（新增绑定）"

func _show_bindings(symbol: String) -> void:
	_clear_children(%Bindings)
	for id in rows:
		var row: Dictionary = rows[id]
		if row.symbol != symbol or row.get("template_map_id", map_id) != map_id:
			continue
		var line := HBoxContainer.new()
		%Bindings.add_child(line)
		var title := Label.new()
		title.text = ("当前 · " if id == active_id else "") + row.name
		var target: Dictionary = catalog.get(Config.TARGETS.get(row.target_type, ""), {}).get(row.target_id, {})
		if not target.is_empty() and row.name != target.name:
			title.text += " · " + target.name
		title.tooltip_text = title.text
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(title)
		var edit := Button.new()
		edit.text = "编辑"
		edit.disabled = id == active_id
		edit.pressed.connect(_select_row.bind(id))
		line.add_child(edit)
		var remove := Button.new()
		remove.text = "删除"
		remove.pressed.connect(_confirm_remove_binding.bind(id))
		line.add_child(remove)
	if %Bindings.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "选择下方的绑定对象后会显示在这里。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		%Bindings.add_child(empty)

func _confirm_remove_binding(id: String) -> void:
	var count := 0
	for key in allocations:
		if not allocations[key].counts.has(id):
			continue
		if key != map_id:
			_status("此绑定还被其他地图引用，请先调整这些地图：%s" % "、".join(_referencing_maps(id)))
			return
		count = int(allocations[key].counts[id])
	var prompt := "删除绑定「%s」？" % rows[id].name
	if count > 0:
		prompt += "\n会移除当前地图的 %d 格分配。目标格数保留，删除后可分给其他绑定。" % count
	_confirm(prompt, _remove_binding.bind(id))

func _remove_binding(id: String) -> void:
	var symbol: String = rows[id].symbol
	if allocations.has(map_id):
		allocations[map_id].counts.erase(id)
	rows.erase(id)
	if active_id != id:
		_select_row(active_id)
		_status("已删除绑定。")
		return
	for other in rows:
		if rows[other].symbol == symbol and rows[other].get("template_map_id", map_id) == map_id:
			_select_row(other)
			_status("已删除绑定。")
			return
	for template_id in templates:
		if templates[template_id].symbol == symbol:
			_select_row(template_id)
			_status("已删除绑定。")
			return
	_select_row("")
	_status("已删除绑定。")

func _add_binding() -> void:
	var current := _active_row()
	if current.is_empty() or not Config.TYPES.has(current.symbol):
		return
	if current.target_type != "none" and current.target_id.is_empty():
		%Target.grab_focus()
		_status("请先为当前绑定选择对象，再添加下一项。")
		return
	var id := "legend_" + Crypto.new().generate_random_bytes(12).hex_encode()
	var row := current.duplicate(true)
	row.legend_id = id
	row.name = _binding_draft_name(row.symbol)
	row.target_id = ""
	if row.target_type == "none":
		row.target_type = "item"
	if not map_id.is_empty():
		row.template_map_id = map_id
	row.loot_table_id = ""
	row.loot = []
	rows[id] = row
	%Search.clear()
	_select_row(id)
	%Target.grab_focus()
	_status("请选择新绑定的对象，然后在右栏分配格数。")

func _confirm_remove() -> void:
	if rows.has(active_id):
		var references := _referencing_maps(active_id)
		if not references.is_empty():
			_status("无法删除。请先移除以下地图的分配：%s" % "、".join(references))
			return
		_confirm("删除图例配置「%s」？" % rows[active_id].name, _remove.bind(active_id))

func _remove(id: String) -> void:
	rows.erase(id)
	_select_row(str(rows.keys()[0]) if not rows.is_empty() else "")
	_status("")

func _load_maps() -> void:
	%Maps.clear()
	map_errors.clear()
	for filename in DirAccess.get_files_at(map_directory):
		if filename.get_extension() != "json":
			continue
		var result := MapData.read(map_directory.path_join(filename))
		if result.has("map"):
			if maps.has(result.map.map_id):
				map_errors.append("%s：地图 ID 重复" % filename)
				continue
			maps[result.map.map_id] = result.map
			%Maps.add_item(result.map.map_name)
			%Maps.set_item_metadata(%Maps.item_count - 1, result.map)
		else:
			map_errors.append("%s：%s" % [filename, result.error])
	if %Maps.item_count > 0:
		_show_map(0)
	else:
		%AllocationTotal.editable = false
		%ApplyAllocation.disabled = true
	if %Maps.item_count == 0 and not map_errors.is_empty():
		%MapNote.text += "\n未载入：%s" % "、".join(map_errors)

func _show_map(index: int) -> void:
	var map: Dictionary = %Maps.get_item_metadata(index)
	map_id = map.map_id
	template_counts = {}
	for node in map.nodes:
		var symbol: String = node.get("icon_id", "")
		if not symbol.is_empty():
			template_counts[symbol] = template_counts.get(symbol, 0) + 1
	templates.clear()
	_clear_children(%MapSymbols)
	for symbol in Symbols.ICONS:
		if not template_counts.has(symbol):
			continue
		var id: String = "map_%s_%s" % [map_id.sha256_text().left(24), symbol.to_lower()]
		var row := Config.create(id)
		row.name = Symbols.title(symbol)
		row.symbol = symbol
		row.category = Config.TYPES.get(symbol, "其他")
		row.template_map_id = map_id
		if row.category != "妖兽":
			row.target_type = "item" if row.category == "资源" and symbol != "O07" else "none"
			row.blocks_movement = false
			row.trigger_type = "arrival" if symbol == "S01" else "interact"
		templates[id] = row
		var card := Button.new()
		card.custom_minimum_size.y = 42
		card.pressed.connect(_select_row.bind(id))
		%MapSymbols.add_child(card)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(line)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 10
		line.offset_right = -10
		var title := Label.new()
		title.text = row.name
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(title)
		var badge := Label.new()
		badge.text = str(template_counts[symbol])
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(badge)
	%AllocationType.clear()
	for symbol in Config.TYPES:
		_add_option(%AllocationType, symbol, "%s（模板 %d）" % [Symbols.title(symbol), template_counts.get(symbol, 0)])
	%AllocationType.select(0)
	var total := 0
	for amount in template_counts.values():
		total += int(amount)
	%MapSummary.text = "%s\n事件格 %d / %d%s" % [map.map_id, total, map.nodes.size(),
		" · 未设入口" if map.entry_node_id.is_empty() else ""]
	var first := ""
	for id in templates:
		if Config.TYPES.has(templates[id].symbol):
			first = id
			break
	_select_row(first if not first.is_empty() else str(templates.keys()[0]) if not templates.is_empty() else "")

func _check() -> void:
	var issue := Config.validate(rows, catalog) if load_error.is_empty() else load_error
	if issue.is_empty():
		issue = Exploration.preflight_allocations(maps, rows, allocations)
	_status("已验证 %d 条图例定义" % rows.size() if issue.is_empty() else issue)

func _save() -> void:
	if not load_error.is_empty():
		_status(load_error)
		return
	var issue := Exploration.preflight_allocations(maps, rows, allocations)
	if issue.is_empty():
		issue = Config.write(rows, catalog, config_path, allocations)
	if issue.is_empty():
		saved = rows.duplicate(true)
		saved_allocations = allocations.duplicate(true)
	_status("已保存 %d 条图例定义" % rows.size() if issue.is_empty() else issue)

func _status(message: String) -> void:
	%Status.text = ("未保存 · " if _is_dirty() else "") + message

func _is_dirty() -> bool:
	return rows != saved or allocations != saved_allocations

func request_close() -> void:
	if _is_dirty():
		_confirm("图例配置有未保存的修改。放弃修改并返回？", _close)
	else:
		_close()

func _confirm(prompt: String, action: Callable) -> void:
	pending = action
	%Confirm.dialog_text = prompt
	%Confirm.popup_centered()

func _close() -> void:
	closed.emit()

func _clear_children(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _show_loot() -> void:
	var row := _active_row()
	var custom: bool = not row.loot_table_id.is_empty()
	%LootMode.clear()
	_add_option(%LootMode, "", "引用现有妖兽掉落" if row.target_type == "monster" else "无专属掉落")
	_add_option(%LootMode, active_id, "使用图例专属掉落")
	_select_option(%LootMode, row.loot_table_id)
	%AddLoot.visible = custom
	_clear_children(%LootRows)
	%LootNote.text = "每条独立判定。专属掉落只影响引用此定义的事件。"
	if not custom:
		_show_inherited_loot(row)
		return
	for index in row.get("loot", []).size():
		_build_loot_row(row.loot[index], index)

func _show_inherited_loot(row: Dictionary) -> void:
	var monster: Dictionary = catalog.get("monsters", {}).get(row.target_id, {}) if row.target_type == "monster" else {}
	if monster.is_empty():
		return
	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var loot: Dictionary = monster.get("loot", {})
	var money: Array = loot.get("money", [0, 0])
	var lines := PackedStringArray(["原始掉落（只读）", "灵石 %d–%d · 100%%" % [int(money[0]), int(money[1])]])
	for entry in loot.get("entries", []):
		if not entry is Dictionary:
			continue
		var minimum := int(entry.get("min", 1))
		var maximum := int(entry.get("max", minimum))
		var chance: float = 100.0 if bool(entry.get("guaranteed", false)) else snappedf(float(entry.get("chance", 0.0)) * 100.0, 0.01)
		var line := "%s %d–%d · %s%%" % [catalog.items[entry.item_id].name, minimum, maximum, str(chance)]
		if entry.get("once") is String:
			line += " · 单次"
		lines.append(line)
	summary.text = "\n".join(lines)
	%LootRows.add_child(summary)

func _change_loot_mode(index: int) -> void:
	_set_field(%LootMode.get_item_metadata(index), "loot_table_id")
	_show_loot()

func _add_loot() -> void:
	var row: Dictionary = rows[active_id]
	if not row.has("loot"):
		row.loot = []
	row.loot.append({"item_id": Config.SPIRIT_STONES, "min": 1, "max": 1, "chance": 100})
	_use_template_count()
	_show_loot()
	_show_allocations()
	_status("已添加条目，可修改数量和概率。")

func _build_loot_row(entry: Dictionary, index: int) -> void:
	var container := VBoxContainer.new()
	%LootRows.add_child(container)
	var top := HBoxContainer.new()
	container.add_child(top)
	var picker := OptionButton.new()
	picker.fit_to_longest_item = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(picker)
	_add_option(picker, Config.SPIRIT_STONES, "灵石（货币）")
	for id in catalog.items:
		_add_option(picker, id, catalog.items[id].name)
	_select_option(picker, entry.item_id)
	picker.item_selected.connect(func(choice: int) -> void:
		entry.item_id = picker.get_item_metadata(choice)
		_status(""))
	var remove := Button.new()
	remove.text = "删除"
	remove.pressed.connect(func() -> void:
		rows[active_id].loot.remove_at(index)
		_show_loot()
		_status(""))
	top.add_child(remove)
	var numbers := HBoxContainer.new()
	container.add_child(numbers)
	for key in ["min", "max", "chance"]:
		var label := Label.new()
		label.text = {"min": "最少", "max": "最多", "chance": "概率 %"}[key]
		numbers.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = 100 if key == "chance" else 999999
		spin.step = 0.1 if key == "chance" else 1.0
		spin.value = entry[key]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		numbers.add_child(spin)
		spin.value_changed.connect(func(value: float) -> void:
			entry[key] = value
			_status(Config.validate_loot(rows[active_id].loot, catalog)))
	container.add_child(HSeparator.new())

func _referencing_maps(id: String) -> PackedStringArray:
	var references := PackedStringArray()
	for key in allocations:
		if allocations[key].counts.has(id):
			references.append(maps[key].map_name if maps.has(key) else key)
	return references

func _allocation() -> Dictionary:
	if not allocations.has(map_id):
		allocations[map_id] = {"totals": {}, "counts": {}}
	return allocations[map_id]

func _show_allocations() -> void:
	if map_id.is_empty() or %AllocationType.selected < 0:
		return
	var symbol: String = %AllocationType.get_selected_metadata()
	var allocation: Dictionary = allocations.get(map_id, {"totals": {}, "counts": {}})
	%AllocationTotal.set_value_no_signal(allocation.totals.get(symbol, template_counts.get(symbol, 0)))
	_clear_children(%Counts)
	for id in rows:
		var definition: Dictionary = rows[id]
		if definition.symbol != symbol or (definition.get("template_map_id", map_id) != map_id and not allocation.counts.has(id)):
			continue
		var line := HBoxContainer.new()
		%Counts.add_child(line)
		var label := Label.new()
		var target: Dictionary = catalog.get(Config.TARGETS.get(definition.target_type, ""), {}).get(definition.target_id, {})
		label.text = definition.name
		if not target.is_empty() and target.name != definition.name:
			label.text += " · " + target.name
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = label.text + "\n" + id
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var count := SpinBox.new()
		count.max_value = 1000
		count.value = allocation.counts.get(id, 0)
		count.value_changed.connect(_set_allocation_count.bind(id))
		line.add_child(count)
	if %Counts.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "点左栏图例，选择绑定对象。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		%Counts.add_child(empty)
	_update_allocation_note()

func _set_allocation_total(value: float) -> void:
	if map_id.is_empty() or %AllocationType.selected < 0:
		return
	_allocation().totals[%AllocationType.get_selected_metadata()] = int(value)
	_update_allocation_note()
	_status("")

func _set_allocation_count(value: float, id: String) -> void:
	var allocation := _allocation()
	var symbol: String = rows[id].symbol
	if not allocation.totals.has(symbol):
		allocation.totals[symbol] = int(%AllocationTotal.value)
	if value > 0:
		allocation.counts[id] = int(value)
	else:
		allocation.counts.erase(id)
	_update_allocation_note()
	_status("")

func _update_allocation_note() -> void:
	var symbol: String = %AllocationType.get_selected_metadata()
	var allocation: Dictionary = allocations.get(map_id, {"totals": {}, "counts": {}})
	var sum := 0
	for id in allocation.counts:
		if rows.has(id) and rows[id].symbol == symbol:
			sum += int(allocation.counts[id])
	var total: int = int(%AllocationTotal.value)
	if not allocation.totals.has(symbol):
		%MapNote.text = "模板 %d 格 · 尚未配置分配" % total
	else:
		%MapNote.text = "已分配 %d / 目标 %d%s" % [sum, total, " · 数量不一致" if sum != total else ""]
	if not map_errors.is_empty():
		%MapNote.text += "\n未载入：%s" % "、".join(map_errors)

func _check_allocations() -> void:
	var issue := Exploration.preflight_allocations(maps, rows, allocations)
	_status("地图分配检查通过。保存全部后写入配置。" if issue.is_empty() else issue)

func _use_template_count() -> void:
	if not templates.has(active_id):
		return
	var row: Dictionary = rows[active_id]
	if row.target_id.is_empty() and row.get("loot", []).is_empty():
		return
	var allocation := _allocation()
	var symbol: String = row.symbol
	if allocation.totals.has(symbol):
		return
	var count: int = template_counts[symbol]
	allocation.totals[symbol] = count
	allocation.counts[active_id] = count
	_status("已绑定 %s · 使用模板的 %d 格" % [row.name, count])
