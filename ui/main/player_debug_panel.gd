extends ColorRect

const Operations := preload("res://core/operation_service.gd")
const INK := Color("#193c35")
const CARD := Color("#fff9e9")

var _fields: Dictionary = {}
var _totals: Dictionary = {}
var _bonuses: Dictionary = {}
var _feedback: Label
var _prior_pause := false
var _prior_focus: Control

func _ready() -> void:
	name = "PlayerDebugPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.44)
	hide()

	var panel_theme := Theme.new()
	panel_theme.default_font_size = 16
	for type in ["Label", "LineEdit", "Button"]:
		panel_theme.set_color("font_color", type, INK)
	panel_theme.set_color("font_placeholder_color", "LineEdit", INK)
	panel_theme.set_color("caret_color", "LineEdit", INK)
	panel_theme.set_color("font_hover_color", "Button", INK)
	panel_theme.set_color("font_pressed_color", "Button", INK)
	panel_theme.set_color("font_focus_color", "Button", INK)
	for state in ["normal", "hover", "pressed"]:
		panel_theme.set_stylebox(state, "Button", _box(Color("#e5f0e6") if state == "normal" else Color("#bdddd1")))
	panel_theme.set_stylebox("normal", "LineEdit", _box(Color.WHITE))
	theme = panel_theme

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _panel(center, Color("#deefe8"), 14)
	panel.custom_minimum_size.x = 620
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)

	var title_bar := _panel(body, Color("#327c70"))
	var title_row := HBoxContainer.new()
	title_bar.add_child(title_row)
	var title := _label(title_row, "玩家属性调试")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(title_row, "×", close)
	_label(body, "基础属性")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for key in Operations.DEBUG_PLAYER_STATS:
		var card := _panel(grid, CARD)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var column := VBoxContainer.new()
		card.add_child(column)
		var heading := HBoxContainer.new()
		column.add_child(heading)
		_label(heading, Operations.DEBUG_PLAYER_STATS[key]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_totals[key] = _label(heading, "")
		var captions := HBoxContainer.new()
		column.add_child(captions)
		_label(captions, "基础值").custom_minimum_size.x = 132
		_label(captions, "加成")
		var row := HBoxContainer.new()
		column.add_child(row)
		_field(row, key)
		_bonuses[key] = _label(row, "")

	_label(body, "持有资源")
	var wallet := _panel(body, CARD)
	var wallet_row := HBoxContainer.new()
	wallet.add_child(wallet_row)
	_label(wallet_row, "灵石").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field(wallet_row, "spirit_stones")
	_feedback = _label(body, "")
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(actions)
	_button(actions, "重新读取", _reload)
	_button(actions, "应用修改", _apply)
	_button(actions, "取消", close)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F12:
		if visible:
			close()
		elif not _open():
			return
		get_viewport().set_input_as_handled()
	elif visible and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _open() -> bool:
	var main := get_parent()
	if main.get("page") in ["主菜单", "创建角色", "读取存档"]:
		return false
	if GameManager.operations.snapshot().is_empty():
		return false
	_prior_focus = get_viewport().gui_get_focus_owner()
	_prior_pause = get_tree().paused
	main.move_child(self, -1)
	get_tree().paused = true
	_reload()
	show()
	_fields.hp.grab_focus()
	return true

func close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = _prior_pause
	if is_instance_valid(_prior_focus) and _prior_focus.is_visible_in_tree():
		_prior_focus.grab_focus()
	_prior_focus = null

func _reload() -> void:
	var service := GameManager.operations
	var player: Dictionary = service.snapshot().player
	var totals := service.stats()
	for key in Operations.DEBUG_PLAYER_STATS:
		_fields[key].text = str(player.base[key])
		_totals[key].text = "最终 %s" % totals[key]
		_bonuses[key].text = "%+d" % int(totals[key] - player.base[key])
		_bonuses[key].tooltip_text = service.character_stat_tooltip(key)
	_fields.spirit_stones.text = str(player.spirit_stones)
	_feedback.text = "加成为当前最终值与基础值之差，含百分比和取整。"

func _apply() -> void:
	var args := {}
	for key in _fields:
		var raw: String = _fields[key].text.strip_edges()
		if not raw.is_valid_int() or raw.begins_with("-") or raw.length() > 11:
			_feedback.text = "%s须填写非负整数。" % Operations.DEBUG_PLAYER_STATS.get(key, "持有灵石")
			return
		args[key] = raw.to_int()
	var result := GameManager.request("debug_set_player_values", args)
	if result.success:
		_reload()
	_feedback.text = result.message

func _box(fill: Color, margin: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color("#88afa3")
	style.set_border_width_all(1)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style

func _panel(parent: Control, fill: Color, margin: int = 8) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(fill, margin))
	parent.add_child(panel)
	return panel

func _label(parent: Control, value: String) -> Label:
	var label := Label.new()
	label.text = value
	parent.add_child(label)
	return label

func _button(parent: Control, value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = value
	button.pressed.connect(callback)
	parent.add_child(button)

func _field(parent: Control, key: String) -> void:
	var field := LineEdit.new()
	field.custom_minimum_size.x = 132
	parent.add_child(field)
	_fields[key] = field
