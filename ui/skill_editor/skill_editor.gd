extends Control
## In-game technique, spell, effect and battle-test editor.
## Drafts stay in memory until validation and save succeed.

signal closed

const Database := preload("res://core/skills/skill_database.gd")
const Registry := preload("res://core/skills/effect_registry.gd")
const Catalog := preload("res://core/content_catalog.gd")
const Spells := preload("res://gameplay/battle/spell_progression.gd")
const Authoring := preload("res://core/skills/skill_authoring_store.gd")
const Diagnostics := preload("res://core/skills/skill_diagnostics.gd")

const ParameterGrid := preload("res://ui/skill_editor/parameter_grid.tscn")

const EDITOR_FONT_SIZE := 19

const BG := Color("11292B")
const PANEL := Color("1D3A3C")
const FIELD := Color("305451")
const LIST := Color("294A49")
const SELECTED := Color("386E62")
const PRIMARY := Color("397468")
const TEXT := Color("E0F0EB")
const MUTED := Color("ACD0C5")
const DAMAGE := Color("FF9B8B")
const HEAL := Color("9ADDB5")
const GOLD := Color("F2CD87")
const SAVE := Color("63B59A")
const ISSUE := Color("E7A090")

const ELEMENTS := ["全部", "金", "木", "水", "火", "土", "风", "雷", "冰", "无属性"]
const SPELL_TYPES := ["伤害", "恢复", "防护", "增益", "减益", "控制", "混合"]
const TARGET_LABELS := ["自身", "敌方单体", "友方单体", "敌方群体", "友方群体"]
const TARGET_VALUES := ["self", "enemy", "ally", "all", "allies"]
const AI_LABELS := ["常规攻击", "低生命恢复", "无护盾时施放", "自身有状态", "目标存在指定状态时施放"]
const REALMS := ["全部", "不限", "炼气", "筑基", "金丹", "元婴", "化神", "炼虚", "合体", "大乘", "渡劫"]
const REALM_MIN := {"不限": 0, "炼气": 1, "筑基": 10, "金丹": 19, "元婴": 28, "化神": 37, "炼虚": 46, "合体": 55, "大乘": 64, "渡劫": 73}
const STATS := [
	{"id": "hp", "name": "最大生命", "flat": true},
	{"id": "mp", "name": "最大灵力", "flat": true},
	{"id": "attack", "name": "攻击", "flat": true},
	{"id": "defense", "name": "防御", "flat": true},
	{"id": "speed", "name": "速度", "flat": true},
	{"id": "fire", "name": "法术伤害", "ratio": true},
	{"id": "critical", "name": "暴击率", "ratio": true},
	{"id": "critical_damage", "name": "暴击伤害", "ratio": true},
]

var catalog: Dictionary = {}
var runtime: Dictionary = {}
var propagate_to_game := false
var paths: Dictionary = {}
var page := "technique"
var techniques: Array = []
var spells: Array = []
var effects: Array = []
var flow: Dictionary = {}
var selected := {"technique": "", "spell": "", "effect": ""}
var search := ""
var elements: Array = []
var grade := ""
var realm_filter := ""
var spell_type := ""
var effect_category := ""
var effect_trigger := ""
var sort_mode := "name"
var view_level := {"technique": 1, "spell": 1}
var dirty := false
var issues := PackedStringArray()
var references := {}
var battle := {}
var battle_result := {}
var list_host: VBoxContainer
var confirm: ConfirmationDialog
var notice: AcceptDialog
var effect_usage := ""
var dirty_files := {}
var spell_realm := ""
var spell_auto := {}
var spell_baselines := {}
var spell_effect_open := -1
var spell_refs_open := false
var spell_ai_open := false
var focus_field := ""
var spell_desc: TextEdit
var _ui_lock := false
var _previous_scale_size := Vector2i.ZERO
var _layout_cards: Array[PanelContainer] = []
var _undo_states: Array = []
var _redo_states: Array = []
var _last_edit_state: Dictionary = {}

func _ready() -> void:
	_previous_scale_size = get_window().content_scale_size
	get_window().content_scale_size = Vector2i.ZERO
	for index in range(1, 7):
		_layout_cards.append(get_node("%%D%d" % index))
	_paint()
	if catalog.is_empty():
		var loaded := Catalog.new()
		if loaded.load_all(false):
			catalog = loaded.tables
	_reload()
	%Validate.pressed.connect(_on_validate)
	%Save.pressed.connect(_on_save)
	%Close.pressed.connect(request_close)
	%TabTechnique.pressed.connect(_request_page.bind("technique"))
	%TabSpell.pressed.connect(_request_page.bind("spell"))
	%TabEffect.pressed.connect(_request_page.bind("effect"))
	%TabBattle.pressed.connect(_request_page.bind("battle"))
	confirm = ConfirmationDialog.new()
	confirm.ok_button_text = "确认"
	confirm.cancel_button_text = "取消"
	confirm.exclusive = false
	add_child(confirm)
	notice = AcceptDialog.new()
	notice.exclusive = false
	add_child(notice)
	_reset_battle()
	set_page("technique")

func focus_entry(kind: String, id: String) -> void:
	var target := "technique" if kind == "technique" else "spell" if kind == "spell" else page
	set_page(target)
	if not id.is_empty():
		_select(target, id)

func request_close() -> void:
	if not dirty:
		closed.emit()
		return
	_confirm("有未保存修改。关闭后这些修改会丢弃。", func() -> void: closed.emit())

func _request_page(next: String) -> void:
	if dirty and next != page:
		_confirm("当前有未保存修改。切换后修改仍保留在内存，关闭前请正式保存或保存作者草稿。继续切换？", set_page.bind(next))
	else:
		set_page(next)

func set_page(next: String) -> void:
	page = next
	search = ""
	_apply_columns()
	_style_tabs()
	_build_actions()
	_build_left()
	_build_center()
	_build_right()
	if page == "spell":
		_capture_spell_if_needed()

func _reload() -> void:
	var bundle := Database.load_bundle(_path("techniques"), _path("spells"), _path("flow"), _path("effects"), _trial_paths())
	if not bundle.error.is_empty():
		%Status.text = bundle.error
		return
	techniques = bundle.techniques
	spells = bundle.spells
	effects = bundle.effects
	flow = bundle.flow
	Database.attach_flow(techniques, flow)
	references = Database.references_for(catalog, runtime)
	dirty = false
	if selected.technique.is_empty() and not techniques.is_empty():
		selected.technique = techniques[0].id
	if selected.spell.is_empty() and not spells.is_empty():
		selected.spell = spells[0].id
	if selected.effect.is_empty() and not effects.is_empty():
		selected.effect = effects[0].id
	_undo_states.clear()
	_redo_states.clear()
	_last_edit_state = _edit_snapshot()

func _edit_snapshot() -> Dictionary:
	return {"techniques": techniques.duplicate(true), "spells": spells.duplicate(true), "effects": effects.duplicate(true), "flow": flow.duplicate(true), "dirty_files": dirty_files.duplicate(true), "dirty": dirty, "selected": selected.duplicate(true)}

func _restore_edit_state(state: Dictionary) -> void:
	techniques = state.techniques.duplicate(true)
	spells = state.spells.duplicate(true)
	effects = state.effects.duplicate(true)
	flow = state.flow.duplicate(true)
	dirty_files = state.dirty_files.duplicate(true)
	dirty = state.dirty
	selected = state.selected.duplicate(true)
	_last_edit_state = _edit_snapshot()
	_build_left()
	_build_center()
	_build_right()

func _undo_edit() -> void:
	if _undo_states.is_empty(): return
	_redo_states.append(_edit_snapshot())
	_restore_edit_state(_undo_states.pop_back())

func _redo_edit() -> void:
	if _redo_states.is_empty(): return
	_undo_states.append(_edit_snapshot())
	_restore_edit_state(_redo_states.pop_back())

func _paint() -> void:
	$Backdrop.color = BG
	$Root.add_theme_constant_override("margin_left", 12)
	$Root.add_theme_constant_override("margin_right", 12)
	$Root/Layout/Header.custom_minimum_size.y = 44
	$Root/Layout/Toolbar.custom_minimum_size.y = 56
	for node in [%Left, %Center, %Right]:
		var box := _box(PANEL, 0, 8)
		node.add_theme_stylebox_override("panel", box)
	for node in [%Title, %LeftTitle, %CenterTitle, %RightTitle, %Status, %LeftCount, %CenterMeta]:
		node.add_theme_color_override("font_color", TEXT if node in [%Title, %LeftTitle, %CenterTitle, %RightTitle] else MUTED)
		node.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
	%LeftCount.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	%CenterMeta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	%CenterMeta.custom_minimum_size = Vector2(160, 0)
	%CenterMeta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for button in [%Validate, %Close, %TabTechnique, %TabSpell, %TabEffect, %TabBattle]:
		_style_button(button, false)
		_chrome_button(button)
	_style_button(%Save, true, SAVE)
	_chrome_button(%Save)

func _style_tabs() -> void:
	var titles := {"technique": "功法列表", "spell": "法术列表", "effect": "效果库列表", "battle": "测试对象"}
	var centers := {"technique": "中央编辑区 · 纵向滚动", "spell": "中央编辑区 · 纵向滚动", "effect": "效果基础配置", "battle": "测试参数"}
	var rights := {"technique": "实时预览", "spell": "法术预览", "effect": "效果预览", "battle": "结果与日志"}
	%LeftTitle.text = titles[page]
	%CenterTitle.text = centers[page]
	%RightTitle.text = rights[page]
	%LeftCount.visible = page in ["technique", "spell"]
	%CenterMeta.visible = page == "spell"
	%SpellTools.visible = page == "spell"
	for pair in [["technique", %TabTechnique], ["spell", %TabSpell], ["effect", %TabEffect], ["battle", %TabBattle]]:
		_style_button(pair[1], pair[0] == page)
		_chrome_button(pair[1])

func _apply_columns() -> void:
	# Proportional columns (23:48:23) and 8px gaps are owned by the scene.
	pass

func _exit_tree() -> void:
	get_window().content_scale_size = _previous_scale_size

func _process(_delta: float) -> void:
	var row := _row(page) if page in ["technique", "spell", "effect"] else {}
	var file := _path("techniques" if page == "technique" else "effects" if page == "effect" else "spells")
	if page == "spell" and row.get("_source", "spells") != "spells":
		file = str(_trial_paths().get(row.get("_source"), file))
	%ResourceContext.text = "%s · %s · %s" % [row.get("name", "未选择资源"), "未保存修改" if dirty else "无未保存修改", file]
	%ResourceContext.tooltip_text = %ResourceContext.text
	%Status.tooltip_text = %Status.text

func _build_actions() -> void:
	_clear(%LeftActions)
	if page == "battle":
		%LeftActions.add_child(_action("重置", _reset_battle_form))
		return
	%LeftActions.add_child(_action("＋ 新增" if page == "spell" else "新增", _create_current))
	%LeftActions.add_child(_action("复制", _copy_current))
	%LeftActions.add_child(_action("删除", _ask_delete))
	%LeftActions.add_child(_action("模板库", _open_templates))
	%LeftActions.add_child(_action("草稿", _open_drafts))
	%LeftActions.add_child(_action("撤销", _undo_edit))
	%LeftActions.add_child(_action("重做", _redo_edit))

func _open_templates() -> void:
	_open_authoring(false)

func _open_drafts() -> void:
	_open_authoring(true)

func _open_authoring(drafts: bool) -> void:
	if page not in ["technique", "spell", "effect"]:
		return
	var path := str(paths.get("authoring", "res://authoring/skills")) + ("/drafts.json" if drafts else "/templates.json")
	var loaded := Authoring.read(path)
	if not loaded.error.is_empty():
		_notify(loaded.error)
		return
	var rows: Array = loaded.rows
	var dialog := AcceptDialog.new()
	dialog.title = "作者草稿（不进入游戏）" if drafts else "模板库"
	dialog.min_size = Vector2i(700, 500)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var query := LineEdit.new()
	query.placeholder_text = "搜索名称、分类"
	box.add_child(query)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(650, 170)
	box.add_child(list)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "模板/草稿名称"
	box.add_child(name_edit)
	var category := LineEdit.new()
	category.placeholder_text = "分类（如伤害、治疗、增益）"
	box.add_child(category)
	var payload := TextEdit.new()
	payload.custom_minimum_size = Vector2(650, 160)
	box.add_child(payload)
	var feedback := _wrapped("当前模式：%s；数据保存在 %s。JSON编辑保留扩展字段。" % [page, path])
	feedback.custom_minimum_size.x = 650
	box.add_child(feedback)
	var refill := func():
		list.clear()
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			if row.get("kind", "") != page:
				continue
			var label := "%s · %s" % [row.get("category", "未分类"), row.get("name", row.id)]
			if not query.text.is_empty() and not label.to_lower().contains(query.text.to_lower()):
				continue
			list.add_item(label)
			list.set_item_metadata(list.item_count - 1, i)
	query.text_changed.connect(func(_text): refill.call())
	list.item_selected.connect(func(index):
		var row: Dictionary = rows[int(list.get_item_metadata(index))]
		name_edit.text = str(row.get("name", ""))
		category.text = str(row.get("category", ""))
		payload.text = JSON.stringify(row.payload, "\t")
	)
	var actions := HFlowContainer.new()
	box.add_child(actions)
	var persist := func():
		var result := Authoring.write(path, rows)
		feedback.text = "已保存；重新打开可回读" if result.success else str(result.message)
		refill.call()
	var create := func():
		var data := _row(page).duplicate(true)
		if data.is_empty():
			feedback.text = "请先选择资源"
			return
		var serial := 1
		var ids := {}
		for entry in rows:
			ids[entry.id] = true
		while ids.has("author_%d" % serial):
			serial += 1
		rows.append({"id": "author_%d" % serial, "kind": page, "name": str(data.get("name", "草稿")), "category": page, "payload": data})
		persist.call()
	actions.add_child(_action("从当前资源创建", create))
	actions.add_child(_action("保存编辑", func():
		if list.get_selected_items().is_empty(): return
		var parser := JSON.new()
		if parser.parse(payload.text) != OK or not parser.data is Dictionary:
			feedback.text = "JSON无效或不是对象；未保存"
			return
		var row: Dictionary = rows[int(list.get_item_metadata(list.get_selected_items()[0]))]
		row.name = name_edit.text
		row.category = category.text
		row.payload = parser.data
		persist.call()
	))
	actions.add_child(_action("复制", func():
		if list.get_selected_items().is_empty(): return
		var row: Dictionary = rows[int(list.get_item_metadata(list.get_selected_items()[0]))].duplicate(true)
		var serial := 1
		var ids := {}
		for entry in rows: ids[entry.id] = true
		while ids.has("author_%d" % serial): serial += 1
		row.id = "author_%d" % serial
		row.name = str(row.get("name", "")) + " 副本"
		rows.append(row)
		persist.call()
	))
	actions.add_child(_action("删除", func():
		if list.get_selected_items().is_empty(): return
		var index := int(list.get_item_metadata(list.get_selected_items()[0]))
		_confirm("删除选中作者记录？正式数据不受影响。", func():
			rows.remove_at(index)
			persist.call()
		)
	))
	var apply := func(overwrite: bool):
		if list.get_selected_items().is_empty(): return
		var row: Dictionary = rows[int(list.get_item_metadata(list.get_selected_items()[0]))]
		var current := _row(page)
		if current.is_empty(): return
		var execute := func():
			var merged := Authoring.merge(current, row.payload, overwrite)
			current.merge(merged, true)
			_mark()
			_build_center()
			_on_validate()
			dialog.hide()
		if overwrite:
			_confirm("覆盖当前资源的模板字段？资源 ID 和引用身份保持不变，保存前仍须校验。", execute)
		else:
			execute.call()
	actions.add_child(_action("填充空字段", apply.bind(false)))
	actions.add_child(_action("确认覆盖应用", apply.bind(true)))
	add_child(dialog)
	dialog.add_theme_stylebox_override("panel", _box(PANEL, 4, 12))
	for control in [query, name_edit, category, payload, list]:
		_style_input(control)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	refill.call()
	dialog.popup_centered(Vector2i(720, 650))

func _build_left() -> void:
	_clear(%LeftBody)
	if page == "spell":
		_build_spell_filters()
	else:
		_clear(%SpellTools)
		%SpellTools.visible = false
	if page != "spell":
		var search_box := LineEdit.new()
		search_box.placeholder_text = "搜索名称 / ID"
		search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_input(search_box)
		search_box.text_changed.connect(func(value: String) -> void:
			search = value
			_fill_list())
		%LeftBody.add_child(search_box)
	if page == "technique":
		var flow_box := FlowContainer.new()
		flow_box.add_theme_constant_override("h_separation", 6)
		flow_box.add_theme_constant_override("v_separation", 6)
		for name in ELEMENTS:
			var chip := _action(name, _toggle_element.bind(name))
			_style_button(chip, name == "全部" and elements.is_empty() or name in elements)
			flow_box.add_child(chip)
		%LeftBody.add_child(flow_box)
		var filters := HBoxContainer.new()
		filters.add_theme_constant_override("separation", 6)
		filters.add_child(_choice("品阶", ["全部", "凡品", "黄阶"], grade, func(value: String) -> void:
			grade = "" if value == "全部" else value
			_fill_list()))
		filters.add_child(_choice("境界", REALMS, realm_filter if not realm_filter.is_empty() else "全部", func(value: String) -> void:
			realm_filter = "" if value == "全部" else value
			_fill_list()))
		filters.add_child(_choice("排序", ["名称", "ID"], "名称" if sort_mode == "name" else "ID", func(value: String) -> void:
			sort_mode = "id" if value == "ID" else "name"
			_fill_list()))
		%LeftBody.add_child(filters)
	elif page == "effect":
		var flow_box := FlowContainer.new()
		flow_box.add_theme_constant_override("h_separation", 6)
		flow_box.add_theme_constant_override("v_separation", 6)
		for name in ["全部"] + Registry.CATEGORIES:
			var chip := _action(name, _set_effect_category.bind(name))
			_style_button(chip, (name == "全部" and effect_category.is_empty()) or name == effect_category)
			flow_box.add_child(chip)
		%LeftBody.add_child(flow_box)
		var filters := HBoxContainer.new()
		filters.add_theme_constant_override("separation", 6)
		filters.add_child(_choice("触发", ["全部", "瞬时", "持续"], "全部", func(value: String) -> void:
			effect_trigger = "" if value == "全部" else ("instant" if value == "瞬时" else "duration")
			_fill_list()))
		filters.add_child(_choice("范围", ["全部", "法术", "功法"], "全部", func(value: String) -> void:
			effect_usage = "" if value == "全部" else value
			_fill_list()))
		%LeftBody.add_child(filters)
	list_host = VBoxContainer.new()
	list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_host.add_theme_constant_override("separation", 4)
	%LeftBody.add_child(list_host)
	_fill_list()

func _fill_list() -> void:
	if list_host == null or not is_instance_valid(list_host):
		return
	_clear(list_host)
	var rows := _visible_rows()
	if page in ["technique", "spell"]:
		%LeftCount.text = "共 %d 项" % rows.size()
	if rows.is_empty():
		var empty := "没有符合条件的法术" if page == "spell" else "没有符合筛选的条目"
		if page == "effect" and effect_usage == "功法":
			empty = "功法加成走属性与灵气流转，不引用战斗效果定义"
		list_host.add_child(_muted(empty))
		if page == "spell":
			list_host.add_child(_action("重置", _reset_spell_filters))
		return
	for row in rows:
		if page == "spell":
			_add_spell_row(row)
			continue
		var selected_row: bool = str(row.get("id", "")) == str(selected.get(page, ""))
		var item := PanelContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_stylebox_override("panel", _box(SELECTED if selected_row else LIST, 8, 4))
		var line := HBoxContainer.new()
		item.add_child(line)
		var name := Label.new()
		name.text = str(row.get("name", row.get("id", "")))
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.add_theme_color_override("font_color", TEXT)
		name.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
		line.add_child(name)
		var mark := Label.new()
		mark.text = _row_mark(row)
		mark.add_theme_color_override("font_color", MUTED)
		mark.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
		line.add_child(mark)
		var row_id := str(row.id)
		var edit := _action("编辑", _select_later.bind(page, row_id))
		line.add_child(edit)
		item.gui_input.connect(_on_row_input.bind(page, row_id))
		list_host.add_child(item)

func _build_center() -> void:
	# Reuse the scene-authored card containers, rebuilding only their contents.
	for card in _layout_cards:
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		_clear(card.get_node("Box/Body"))
	_clear(%CenterBody)
	if page == "technique":
		_build_technique_form()
	elif page == "spell":
		_build_spell_form()
	elif page == "effect":
		_build_effect_form()
	else:
		_build_battle_form()
	if page in ["effect", "battle"]:
		_group_parameter_fields(%CenterBody)
	if page == "effect":
		for card in %CenterBody.get_children():
			if card is PanelContainer:
				_group_parameter_fields(card.get_child(0))
	_arrange_editor_cards()

func _group_parameter_fields(body: VBoxContainer) -> void:
	var fields: Array[Control] = []
	for child in body.get_children():
		if child is VBoxContainer:
			fields.append(child)
	if fields.is_empty():
		return
	var insert_at := fields[0].get_index()
	var grid := ParameterGrid.instantiate() as GridContainer
	_clear(grid)
	body.add_child(grid)
	body.move_child(grid, insert_at)
	for field in fields:
		field.reparent(grid)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _arrange_editor_cards() -> void:
	if page not in ["technique", "spell"]:
		for card in _layout_cards:
			%CenterBody.add_child(card)
			card.owner = self
			card.hide()
		return
	var group := 0
	var markers := {"基础配置": 0, "施法参数": 1, "修炼加成": 1, "属性与效果": 2, "效果组合": 2, "等级成长": 3, "法术说明": 4, "AI施法配置": 5}
	for control in %CenterBody.get_children():
		var heading: String = control.text if control is Label else ""
		if control is HBoxContainer and control.get_child_count() > 0 and control.get_child(0) is Label:
			heading = control.get_child(0).text
		if markers.has(heading):
			group = int(markers[heading])
			if control is Label:
				%CenterBody.remove_child(control)
				control.queue_free()
				continue
		var destination := group
		if page == "technique" and control is VBoxContainer and control.get_child_count() > 0 and control.get_child(0) is Label:
			var field_title: String = control.get_child(0).text
			if field_title == "描述": destination = 4
			if field_title == "预览等级": destination = 3
		control.reparent(_layout_cards[destination].get_node("Box/Body"))
	if page == "technique":
		_layout_cards[1].get_node("Box/Title").text = "D2 修炼参数与条件"
		_layout_cards[3].get_node("Box/Body").add_child(_muted("各属性的基础值、每级成长与等级覆盖在 D3 对应属性卡中编辑。"))
		_layout_cards[5].get_node("Box/Body").add_child(_muted("功法为被动属性与成长，不使用施法或 AI 参数。扩展规则沿用现有数据，不新增配置字段。"))
	else:
		_layout_cards[1].get_node("Box/Title").text = "D2 技能战斗参数"
	for card in _layout_cards:
		%CenterBody.add_child(card)
		card.owner = self
		card.show()
	for index in [0, 1]:
		if page != "technique": continue
		var body := _layout_cards[index].get_node("Box/Body")
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 6)
		for field in body.get_children():
			if field is VBoxContainer:
				field.reparent(grid)
				field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(grid)
		body.move_child(grid, 0)

func _build_right() -> void:
	_clear(%RightBody)
	if page == "technique":
		_build_technique_preview()
	elif page == "spell":
		_build_spell_preview()
	elif page == "effect":
		_build_effect_preview()
	else:
		_build_battle_result()
	if page in ["technique", "spell"]:
		_arrange_preview_cards()

func _arrange_preview_cards() -> void:
	var groups: Array[VBoxContainer] = []
	var controls := %RightBody.get_children()
	for index in range(3):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _box(FIELD, 0, 12))
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		panel.add_child(body)
		%RightBody.add_child(panel)
		groups.append(body)
	var group := 0
	for control in controls:
		if control is Label and control.text == "引用情况": group = 1
		if control is Label and control.text == "配置检查": group = 2
		if control is Button and control.text == "验证当前配置": group = 2
		control.reparent(groups[group])

func _build_technique_form() -> void:
	var row := _row("technique")
	if row.is_empty():
		%CenterBody.add_child(_muted("先从左侧选择或新增功法"))
		return
	%CenterBody.add_child(_section("基础配置"))
	%CenterBody.add_child(_text_field("唯一 ID", str(row.id), not bool(row.get("_persisted", false)), func(value: String) -> void:
		row.id = value.strip_edges()
		_mark()))
	%CenterBody.add_child(_text_field("名称", str(row.get("name", "")), true, func(value: String) -> void:
		row.name = value
		_mark()))
	%CenterBody.add_child(_text_field("描述", str(row.get("description", "")), true, func(value: String) -> void:
		row.description = value
		_mark()))
	var flow_row: Dictionary = row.get("_flow", {})
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(_choice("品阶", Database.RARITIES, str(row.get("rarity", "凡品")), func(value: String) -> void:
		row.rarity = value
		_mark()))
	line.add_child(_choice("路线", ["法修", "体修"], "体修" if row.get("cultivation_route") == "body" else "法修", func(value: String) -> void:
		row.cultivation_route = "body" if value == "体修" else "qi"
		_mark()))
	line.add_child(_choice("五行", ["无属性"] + Database.ROOTS, _element_label(flow_row.get("element", "")), func(value: String) -> void:
		flow_row.element = "" if value == "无属性" else value
		row._flow = flow_row
		_mark()))
	line.add_child(_choice("境界", REALMS.slice(1), _realm_label(int(row.get("realm_min", 0))), func(value: String) -> void:
		row.realm_min = int(REALM_MIN.get(value, 0))
		_mark()))
	%CenterBody.add_child(line)
	%CenterBody.add_child(_spin_field("预览等级", view_level.technique, 1, 3, func(value: float) -> void:
		view_level.technique = int(value)
		_build_center()
		_build_right()))
	%CenterBody.add_child(_muted("升级上限仍是 3 级，品阶只允许升级表中的凡品和黄阶。气海、经脉、筋骨、体魄属于角色根基，不写入功法。"))
	%CenterBody.add_child(_section("属性与效果"))
	%CenterBody.add_child(_wrapped("属性门槛、前置功法：当前运行时未支持，不能配置为正式生效条件。功法保持被动属性与成长，不使用法术战斗节点。"))
	for stat in STATS:
		if stat.id in ["hp", "defense", "attack", "fire"] or row.has(stat.id) or row.has(str(stat.id) + "_step") or row.get("percents", {}).has(stat.id):
			%CenterBody.add_child(_stat_card(row, stat))
	var add := _action("添加属性 / 被动效果", _add_technique_stat)
	_style_button(add, true)
	%CenterBody.add_child(add)
	%CenterBody.add_child(_section("修炼加成"))
	%CenterBody.add_child(_spin_field("每小时炼化", int(flow_row.get("hourly", 60000)), 1, 200000, func(value: float) -> void:
		flow_row.hourly = int(value)
		row._flow = flow_row
		_mark()))
	%CenterBody.add_child(_spin_field("每级炼化成长", int(flow_row.get("hourly_step", 0)), 0, 200000, func(value: float) -> void:
		flow_row.hourly_step = int(value)
		row._flow = flow_row
		_mark()))
	%CenterBody.add_child(_spin_field("损耗", int(flow_row.get("loss", 0)), 0, 10000, func(value: float) -> void:
		flow_row.loss = int(value)
		row._flow = flow_row
		_mark()))

func _stat_card(row: Dictionary, stat: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(FIELD, 8, 4))
	var box := VBoxContainer.new()
	card.add_child(box)
	var title := HBoxContainer.new()
	box.add_child(title)
	var name := Label.new()
	name.text = str(stat.name)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_color_override("font_color", TEXT)
	title.add_child(name)
	var level := int(view_level.technique)
	var amount := Database.technique_amount(row, str(stat.id), level)
	var summary := Label.new()
	summary.text = _format_amount(stat, amount)
	summary.add_theme_color_override("font_color", HEAL if str(stat.id) in ["hp", "mp"] else TEXT)
	title.add_child(summary)
	if str(stat.id) not in ["hp", "defense", "attack", "fire"]:
		title.add_child(_action("移除", _remove_stat.bind(row, str(stat.id))))
	var ratio: bool = bool(stat.get("ratio", false))
	var base := float(row.get(stat.id, 0))
	var step := float(row.get(str(stat.id) + "_step", 0))
	box.add_child(_spin_field("1级" if not ratio else "1级(%)", (base * 100.0) if ratio else base, 0, 999999, func(value: float) -> void:
		row[stat.id] = value / 100.0 if ratio else int(value)
		_mark_preview()))
	box.add_child(_spin_field("每级成长" if not ratio else "每级(%)", (step * 100.0) if ratio else step, 0, 999999, func(value: float) -> void:
		row[str(stat.id) + "_step"] = value / 100.0 if ratio else int(value)
		_mark_preview()))
	if not ratio and str(stat.id) in ["hp", "mp", "attack", "defense", "speed"]:
		var percent := float(row.get("percents", {}).get(stat.id, 0.0))
		box.add_child(_spin_field("百分比加成(%)", percent * 100.0, 0, 500, func(value: float) -> void:
			if not row.get("percents") is Dictionary:
				row.percents = {}
			if value <= 0.0:
				row.percents.erase(stat.id)
			else:
				row.percents[stat.id] = value / 100.0
			_mark_preview()))
	var override: Dictionary = row.get("level_overrides", {}).get(str(level), {}) if row.get("level_overrides") is Dictionary else {}
	var toggle := CheckBox.new()
	toggle.text = "本级覆盖"
	toggle.button_pressed = override.has(stat.id)
	toggle.add_theme_color_override("font_color", MUTED)
	toggle.toggled.connect(func(on: bool) -> void:
		if not row.get("level_overrides") is Dictionary:
			row.level_overrides = {}
		if not row.level_overrides.get(str(level)) is Dictionary:
			row.level_overrides[str(level)] = {}
		if on:
			row.level_overrides[str(level)][stat.id] = row.get(stat.id, 0)
		else:
			row.level_overrides[str(level)].erase(stat.id)
		_mark_preview())
	box.add_child(toggle)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	for field in box.get_children():
		if field is VBoxContainer:
			field.reparent(grid)
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	box.move_child(grid, 1)
	return card

func _build_technique_preview() -> void:
	var row := _row("technique")
	if row.is_empty():
		return
	var preview: Dictionary = Database.preview_technique(row, int(view_level.technique), _player_stub(), _data())
	var title := _label(str(row.get("name", "")), EDITOR_FONT_SIZE, HEAL)
	%RightBody.add_child(title)
	%RightBody.add_child(_wrapped(str(preview.text)))
	var before: Dictionary = preview.before
	var after: Dictionary = preview.after
	%RightBody.add_child(_section("装备后属性变化"))
	for key in ["hp", "mp", "attack", "defense", "speed", "fire"]:
		if not after.has(key):
			continue
		var delta := float(after[key]) - float(before.get(key, 0))
		if delta == 0.0 and key not in ["hp", "attack", "defense"]:
			continue
		%RightBody.add_child(_label("%s %s → %s（%+s）" % [_stat_label(key), _plain(before.get(key, 0)), _plain(after[key]), _plain(delta)], EDITOR_FONT_SIZE, TEXT))
	_add_reference_block(str(row.id))
	%RightBody.add_child(_action("验证当前配置", _on_validate))

func _build_spell_form() -> void:
	spell_desc = null
	var row := _row("spell")
	%CenterMeta.text = "未选择法术" if row.is_empty() else "法术 ID：" + str(row.get("id", ""))
	%CenterMeta.tooltip_text = "" if row.is_empty() else str(row.get("id", ""))
	if row.is_empty():
		%CenterBody.add_child(_muted("先从左侧选择或新增法术"))
		return
	_token(row)
	var cap := _spell_level_cap(row)
	view_level.spell = clampi(int(view_level.spell), 1, cap)
	_build_spell_basics(row)
	_build_spell_cast(row)
	_build_spell_effects(row)
	_build_growth_section(row)
	_build_description_section(row)
	_build_ai_section(row)

func _build_spell_preview() -> void:
	var row := _row("spell")
	if row.is_empty():
		%RightBody.add_child(_muted("未选择法术"))
		return
	_refresh_auto_text()
	var level := clampi(int(view_level.spell), 1, _spell_level_cap(row))
	var rarity := str(row.get("rarity", ""))
	var element := _element_short(row.get("element", ""))
	%RightBody.add_child(_label(str(row.get("name", "")), EDITOR_FONT_SIZE, _rarity_color(rarity)))
	%RightBody.add_child(_label("%s · %s · %s · Lv.%d" % [_element_phrase(element), rarity if not rarity.is_empty() else "未标品阶", _realm_label(int(row.get("realm_min", 0))), level], EDITOR_FONT_SIZE, _element_color_of(element)))
	%RightBody.add_child(_label("施法目标：%s" % _target_label(str(row.get("target", "enemy"))), EDITOR_FONT_SIZE, TEXT))
	%RightBody.add_child(_label("灵力消耗：%d" % Database._spell_mp(row, level), EDITOR_FONT_SIZE, TEXT))
	%RightBody.add_child(_label("冷却回合：%d" % Database._spell_cd(row, level), EDITOR_FONT_SIZE, TEXT))
	%RightBody.add_child(_section("实际效果"))
	var lines := _spell_effect_lines(row, level)
	if lines.is_empty():
		%RightBody.add_child(_muted("没有可预览的效果"))
	for entry in lines:
		%RightBody.add_child(_colored_wrap(str(entry.text), _line_color(str(entry.kind))))
	if not bool(spell_auto.get(_token(row), false)) and not str(row.get("description", "")).is_empty():
		%RightBody.add_child(_section("手动说明"))
		%RightBody.add_child(_wrapped(str(row.description)))
		%RightBody.add_child(_muted("手动说明不替代上面的实际效果。"))
	_add_spell_references(str(row.id))
	%RightBody.add_child(_section("配置检查"))
	var found := _spell_issues(row)
	if row.get("effects") is Array:
		var active_count := 0
		for effect in row.effects:
			if effect is Dictionary and bool(effect.get("enabled", true)):
				active_count += 1
		if active_count == 0:
			%RightBody.add_child(_colored_wrap("警告：全部节点已禁用；施法仍消耗灵力并进入冷却。", GOLD))
	%RightBody.add_child(_colored_wrap("提示：错误资源可存作者草稿；正式保存必须通过全部校验。", SAVE))
	if found.is_empty():
		%RightBody.add_child(_label("当前草稿可以通过校验", EDITOR_FONT_SIZE, HEAL))
		var simulated := Database.simulate_spell(row, level,
			{"hp": 100, "max_hp": 1000, "mp": 9999, "max_mp": 9999, "attack": 100, "root": "金", "critical": 0.0},
			{"hp": 100000, "max_hp": 100000, "defense": 0}, catalog, 11, 1)
		if str(simulated.get("error", "")).is_empty():
			%RightBody.add_child(_wrapped("运行时示例：攻击100、目标防御0、金灵根、固定种子11；本次伤害 %d，治疗 %d。概率效果是单次示例，并非期望值。" % [simulated.damage_avg, simulated.heal_avg]))
	else:
		for issue in found:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			var text := _colored_wrap(issue, ISSUE)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(text)
			line.add_child(_mini("定位", _focus_issue.bind(issue)))
			%RightBody.add_child(line)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.add_child(_action("测试法术", _test_current_spell))
	actions.add_child(_action("校验配置", _validate_current_spell))
	%RightBody.add_child(actions)

func _build_effect_form() -> void:
	var row := _row("effect")
	if row.is_empty():
		%CenterBody.add_child(_muted("先从左侧选择效果"))
		return
	%CenterBody.add_child(_text_field("效果 ID", str(row.id), not bool(row.get("builtin", false)), func(value: String) -> void:
		row.id = value.strip_edges()
		_mark()))
	%CenterBody.add_child(_text_field("名称", str(row.get("name", "")), true, func(value: String) -> void:
		row.name = value
		_mark()))
	%CenterBody.add_child(_choice("分类", Registry.CATEGORIES, str(row.get("category", "伤害")), func(value: String) -> void:
		row.category = value
		_mark()))
	%CenterBody.add_child(_label("执行器：%s" % row.get("executor", ""), EDITOR_FONT_SIZE, TEXT))
	%CenterBody.add_child(_wrapped(str(row.get("summary", ""))))
	if str(row.get("trigger", "")) == "instant":
		%CenterBody.add_child(_muted("瞬时效果不显示持续和叠加字段。"))
	%CenterBody.add_child(_section("参数定义"))
	for param in row.get("parameters", []):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(FIELD, 8, 4))
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(_label("%s · %s" % [param.get("name", ""), param.get("id", "")], EDITOR_FONT_SIZE, TEXT))
		if str(param.get("type", "")) != "bool" and str(param.get("type", "")) != "enum":
			box.add_child(_spin_field("默认值", float(param.get("default", 0)), float(param.get("min", 0)), float(param.get("max", 99999)), func(value: float) -> void:
				param.default = int(value) if str(param.type) == "int" else value
				_mark()))
			box.add_child(_spin_field("最小值", float(param.get("min", 0)), -99999, 99999, func(value: float) -> void:
				param.min = value
				_mark()))
			box.add_child(_spin_field("最大值", float(param.get("max", 0)), -99999, 999999, func(value: float) -> void:
				param.max = value
				_mark()))
		%CenterBody.add_child(card)
	%CenterBody.add_child(_muted("不能新增执行器不读取的参数。复制效果会生成新的定义 ID，已有法术实例不会跟着改变。"))

func _build_effect_preview() -> void:
	var row := _row("effect")
	if row.is_empty():
		return
	%RightBody.add_child(_label(str(row.get("name", "")), EDITOR_FONT_SIZE, _effect_color(row)))
	%RightBody.add_child(_label("%s · %s" % [row.get("category", ""), row.get("executor", "")], EDITOR_FONT_SIZE, MUTED))
	%RightBody.add_child(_wrapped(str(row.get("summary", ""))))
	var users := Database.effect_references(spells, str(row.id))
	%RightBody.add_child(_section("被引用情况"))
	%RightBody.add_child(_label("法术 %d" % users.size(), EDITOR_FONT_SIZE, TEXT))
	for user in users:
		%RightBody.add_child(_label(str(user.name), EDITOR_FONT_SIZE, MUTED))
	if users.is_empty():
		%RightBody.add_child(_muted("当前没有法术实例引用它"))
	%RightBody.add_child(_action("测试效果", _test_effect))
	%RightBody.add_child(_action("检查引用", _build_right))
	%RightBody.add_child(_action("验证当前配置", _on_validate))

func _build_battle_form() -> void:
	_ensure_battle()
	%CenterBody.add_child(_choice("测试对象", ["法术", "功法"], "功法" if battle.kind == "technique" else "法术", func(value: String) -> void:
		battle.kind = "technique" if value == "功法" else "spell"
		_build_center()
		_build_left()))
	var names: Array[String] = []
	var rows: Array = techniques if battle.kind == "technique" else spells
	for row in rows:
		names.append(str(row.name))
	if names.is_empty():
		%CenterBody.add_child(_muted("没有可测试的数据"))
		return
	var current := _battle_row()
	%CenterBody.add_child(_choice("条目", names, str(current.get("name", names[0])), func(value: String) -> void:
		for row in rows:
			if str(row.name) == value:
				battle.id = row.id
		_build_right()))
	%CenterBody.add_child(_spin_field("等级", float(battle.level), 1, 5, func(value: float) -> void: battle.level = int(value)))
	for pair in [["caster_hp", "施法者生命", 1, 99999, true], ["caster_max_hp", "施法者最大生命", 1, 99999, true], ["caster_mp", "施法者灵力", 0, 99999, true], ["caster_attack", "施法者攻击", 0, 99999, false], ["caster_defense", "施法者防御", 0, 99999, false], ["target_hp", "目标生命", 1, 99999, true], ["target_defense", "目标防御", 0, 99999, false], ["crit", "暴击率", 0, 1, false], ["crit_damage", "暴击伤害", 1, 10, false], ["seed", "随机种子", 1, 999999, true], ["times", "连续次数", 1, 200, true]]:
		%CenterBody.add_child(_spin_field(str(pair[1]), float(battle.get(pair[0], 0)), float(pair[2]), float(pair[3]), _set_battle_value.bind(str(pair[0]), bool(pair[4]))))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.add_child(_action("执行一次", _run_battle.bind(1)))
	actions.add_child(_action("连续测试", _run_battle.bind(int(battle.times))))
	actions.add_child(_action("重置", _reset_battle_form))
	%CenterBody.add_child(actions)
	%CenterBody.add_child(_muted("测试使用 SkillEngine 和统一伤害公式，不写入玩家、NPC 或存档。"))

func _build_battle_result() -> void:
	_ensure_battle()
	if battle.kind == "technique":
		var row := _find(techniques, str(battle.id))
		if row.is_empty():
			%RightBody.add_child(_muted("未选择功法"))
			return
		var preview: Dictionary = Database.preview_technique(row, int(battle.level), _battle_player(row), _data())
		%RightBody.add_child(_label(str(row.name), EDITOR_FONT_SIZE, HEAL))
		%RightBody.add_child(_wrapped(str(preview.text)))
		%RightBody.add_child(_label("生命 %s → %s" % [_plain(preview.before.hp), _plain(preview.after.hp)], EDITOR_FONT_SIZE, TEXT))
		%RightBody.add_child(_label("攻击 %s → %s" % [_plain(preview.before.attack), _plain(preview.after.attack)], EDITOR_FONT_SIZE, TEXT))
		%RightBody.add_child(_label("防御 %s → %s" % [_plain(preview.before.defense), _plain(preview.after.defense)], EDITOR_FONT_SIZE, TEXT))
		%RightBody.add_child(_muted("功法测试只比较装备前后的真实属性，不改正式角色。"))
		return
	if battle_result.is_empty():
		%RightBody.add_child(_muted("尚未执行。结果会来自本次结算。"))
		return
	if not str(battle_result.get("error", "")).is_empty():
		%RightBody.add_child(_wrapped(str(battle_result.error)))
		return
	%RightBody.add_child(_label("伤害 平均 %.1f / 最小 %d / 最大 %d" % [float(battle_result.damage_avg), int(battle_result.damage_min), int(battle_result.damage_max)], EDITOR_FONT_SIZE, DAMAGE))
	%RightBody.add_child(_label("治疗平均 %.1f · 暴击 %d · 状态命中 %d / %d" % [float(battle_result.heal_avg), int(battle_result.crits), int(battle_result.status_hits), int(battle_result.count)], EDITOR_FONT_SIZE, HEAL))
	var first: Dictionary = battle_result.runs[0]
	%RightBody.add_child(_section("首轮"))
	%RightBody.add_child(_label("伤害 %d · 治疗 %d · 灵力消耗 %d · 暴击 %s" % [int(first.damage), int(first.heal), int(first.mp_spent), "是" if first.critical else "否"], EDITOR_FONT_SIZE, TEXT))
	for id in first.statuses:
		var status: Dictionary = first.statuses[id]
		%RightBody.add_child(_label("%s · %s 回合" % [id, status.get("turns", "")], EDITOR_FONT_SIZE, GOLD))
	%RightBody.add_child(_section("执行顺序"))
	for step in first.trace:
		%RightBody.add_child(_label("%s 目标损失 %s 自身变化 %s" % [step.effect_id, step.target_loss, step.caster_gain], EDITOR_FONT_SIZE, MUTED))
	if first.trace.is_empty():
		%RightBody.add_child(_muted("旧法术和试学法术由原结算路径一次完成，没有分步追踪。"))

func _visible_rows() -> Array:
	var source: Array = techniques if page == "technique" else spells if page == "spell" else effects if page == "effect" else []
	if page == "battle":
		source = techniques if battle.get("kind", "spell") == "technique" else spells
	var rows: Array = []
	for row in source:
		if not _match_row(row):
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get(sort_mode, "")) < str(b.get(sort_mode, "")))
	return rows

func _match_row(row: Dictionary) -> bool:
	var haystack := str(row.get("name", "")) + " " + str(row.get("id", ""))
	if not search.is_empty() and search.to_lower() not in haystack.to_lower():
		return false
	if page == "spell":
		if not _spell_element_match(row):
			return false
	elif page in ["technique", "battle"] and not elements.is_empty():
		var element := _row_element(row)
		if element not in elements:
			return false
	if page == "technique" and not grade.is_empty() and str(row.get("rarity", "")) != grade:
		return false
	if page == "technique" and not realm_filter.is_empty():
		var minimum := int(row.get("realm_min", 0))
		if realm_filter == "不限" and minimum != 0:
			return false
		if realm_filter == "炼气" and (minimum < 1 or minimum > 9):
			return false
		if realm_filter not in ["不限", "炼气"] and minimum != int(REALM_MIN.get(realm_filter, -999)):
			return false
	if page == "spell" and not grade.is_empty() and str(row.get("rarity", "")) != grade:
		return false
	if page == "spell" and not spell_realm.is_empty() and _realm_label(int(row.get("realm_min", 0))) != spell_realm:
		return false
	if page == "spell" and not _spell_type_match(row):
		return false
	if page == "effect" and not effect_category.is_empty() and str(row.get("category", "")) != effect_category:
		return false
	if page == "effect" and not effect_trigger.is_empty() and str(row.get("trigger", "")) != effect_trigger:
		return false
	if page == "effect" and effect_usage == "功法":
		return false
	if page == "effect" and effect_usage == "法术" and not row.get("usage", []).has("spell"):
		return false
	return true

func _create_current() -> void:
	if page == "spell":
		if _spell_changed():
			_confirm("「%s」有未保存修改。继续会丢弃对这门法术的修改。" % _spell_name(), func() -> void:
				_revert_spell()
				_create_spell_row())
			return
		_create_spell_row()
		return
	if page == "technique":
		var row := Database.blank_technique(techniques)
		techniques.append(row)
		selected.technique = row.id
	elif page == "effect":
		var row := Database.blank_effect(effects)
		effects.append(row)
		selected.effect = row.id
	_mark()
	_build_left()
	_build_center()
	_build_right()

func _copy_current() -> void:
	if page == "spell":
		_copy_spell()
		return
	var row := _row(page)
	if row.is_empty():
		return
	var rows: Array = techniques if page == "technique" else effects
	var copy := Database.duplicate_row(row, rows)
	rows.append(copy)
	selected[page] = copy.id
	_mark()
	_build_left()
	_build_center()
	_build_right()

func _ask_delete() -> void:
	if page == "spell":
		_ask_delete_spell()
		return
	var row := _row(page)
	if row.is_empty():
		_notify("先选择要删除的条目")
		return
	if page == "effect" and bool(row.get("builtin", false)):
		_notify("内置效果定义不能删除。可以复制后再修改副本。")
		return
	var users: Array = references.get(row.id, [])
	if page == "effect":
		users = Database.effect_references(spells, str(row.id))
	if not users.is_empty():
		var lines := PackedStringArray()
		for user in users:
			lines.append("%s · %s" % [user.get("kind", user.get("kind", "引用")), user.get("label", user.get("name", ""))])
		_notify("仍被引用，不能删除：\n" + "\n".join(lines))
		return
	_confirm("删除 %s？此操作会在保存后写入数据。" % row.get("name", row.id), _delete_current)

func _delete_current() -> void:
	var rows: Array = techniques if page == "technique" else spells if page == "spell" else effects
	var id := str(selected.get(page, ""))
	for index in range(rows.size()):
		if str(rows[index].id) == id:
			rows.remove_at(index)
			break
	selected[page] = str(rows[0].id) if not rows.is_empty() else ""
	_mark()
	_build_left()
	_build_center()
	_build_right()

func _on_validate() -> void:
	issues = Database.validate_bundle(_bundle(), catalog.get("spell_growth", {}))
	%Status.text = "校验通过" if issues.is_empty() else "\n".join(issues)
	_build_right()
	if page == "spell" or issues.is_empty():
		return
	if not issues.is_empty():
		%RightBody.add_child(_section("校验结果"))
		for issue in issues:
			%RightBody.add_child(_wrapped(issue))

func _on_save() -> void:
	issues = Database.validate_bundle(_bundle(), catalog.get("spell_growth", {}))
	if not issues.is_empty():
		%Status.text = "\n".join(issues)
		_on_validate()
		return
	if dirty_files.is_empty():
		%Status.text = "没有需要写入的修改"
		return
	var save_paths := _save_paths()
	save_paths["include"] = dirty_files.duplicate()
	var result := Database.save_bundle(_bundle(), catalog.get("spell_growth", {}), save_paths)
	if not result.success:
		%Status.text = str(result.message)
		return
	dirty = false
	dirty_files.clear()
	_reload()
	var reload_message := _reload_game()
	%Status.text = str(result.message) + reload_message
	_build_left()
	_build_center()
	_build_right()
	spell_baselines.clear()
	_capture_spell_if_needed()

func _reload_game() -> String:
	if not propagate_to_game:
		return " 保存已写入文件；当前测试没有热更新运行中的游戏。"
	var manager := get_node_or_null("/root/GameManager")
	if manager == null:
		return " 文件已保存。重新进入游戏或重载配置后生效。"
	if not manager.catalog.load_all():
		return " 文件已保存，但运行时重载失败：" + str(manager.catalog.error)
	manager.operations.configure(manager.catalog.tables)
	catalog = manager.catalog.tables
	runtime = manager.operations.snapshot()
	references = Database.references_for(catalog, runtime)
	return " 运行时配置已重新加载。正在进行的战斗和已生成快照不会回溯。"

func _run_battle(times: int) -> void:
	_ensure_battle()
	if battle.kind == "technique":
		_build_right()
		%Status.text = "功法测试已按角色属性公式计算"
		return
	var row := _battle_row()
	if row.is_empty():
		%Status.text = "没有可测试的法术"
		return
	var data := _data()
	data.rules = data.rules.duplicate(true)
	data.rules.crit_chance = float(battle.crit)
	data.rules.crit_multiplier = float(battle.crit_damage)
	var caster := {"hp": int(battle.caster_hp), "max_hp": int(battle.caster_max_hp), "mp": int(battle.caster_mp), "max_mp": int(battle.caster_mp), "attack": float(battle.caster_attack), "defense": float(battle.caster_defense), "root": "金", "critical": 0.0, "critical_damage": 0.0}
	var target := {"hp": int(battle.target_hp), "max_hp": int(battle.target_hp), "defense": float(battle.target_defense), "attack": 10, "mp": 0}
	battle_result = Database.simulate_spell(row, int(battle.level), caster, target, data, int(battle.seed), maxi(1, times))
	%Status.text = "测试完成，未写入存档" if str(battle_result.get("error", "")).is_empty() else str(battle_result.error)
	_build_right()

func _bundle() -> Dictionary:
	var flow_copy := flow.duplicate(true)
	flow_copy.techniques = {}
	for row in techniques:
		var current: Dictionary = row.get("_flow", {})
		flow_copy.techniques[row.id] = {"element": str(current.get("element", "")), "hourly": int(current.get("hourly", 60000)), "hourly_step": int(current.get("hourly_step", 2500)), "loss": int(current.get("loss", 2000))}
	return {"techniques": techniques, "spells": spells, "effects": effects, "flow": flow_copy}

func _save_paths() -> Dictionary:
	return {"techniques": _path("techniques"), "spells": _path("spells"), "flow": _path("flow"), "effects": _path("effects"), "trials": _trial_paths()}

func _path(key: String) -> String:
	var defaults := {"techniques": Database.TECHNIQUE_PATH, "spells": Database.SPELL_PATH, "flow": Database.FLOW_PATH, "effects": Database.EFFECT_PATH}
	return str(paths.get(key, defaults[key]))

func _trial_paths() -> Dictionary:
	if paths.get("trials") is Dictionary:
		return paths.trials
	return Database.TRIAL_PATHS

func _data() -> Dictionary:
	var data := catalog.duplicate(true)
	data.techniques = {}
	for row in techniques:
		data.techniques[row.id] = Database._public_row(row)
	return data

func _row(kind: String) -> Dictionary:
	return _find(techniques if kind == "technique" else spells if kind == "spell" else effects, str(selected.get(kind, "")))

func _find(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == id:
			return row
	return {}

func _on_row_input(event: InputEvent, kind: String, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_later(kind, id)

func _select_later(kind: String, id: String) -> void:
	_select.call_deferred(kind, id)

func _select(kind: String, id: String) -> void:
	if kind == "spell" and id != str(selected.get("spell", "")) and _spell_changed():
		_confirm("「%s」有未保存修改。切换后会丢弃这些修改。" % _spell_name(), func() -> void:
			_revert_spell()
			_select_now(kind, id))
		return
	_select_now(kind, id)

func _select_now(kind: String, id: String) -> void:
	if kind == "battle":
		battle.id = id
		_build_center()
		_build_right()
		return
	var switched := kind != "spell" or id != str(selected.get("spell", ""))
	selected[kind] = id
	if kind == "spell" and switched:
		spell_effect_open = -1
		focus_field = ""
		view_level.spell = 1
	_fill_list()
	_build_center()
	_build_right()
	if kind == "spell":
		_capture_spell_if_needed()

func _toggle_element(name: String) -> void:
	if name == "全部":
		elements.clear()
	elif name in elements:
		elements.erase(name)
	else:
		elements.append(name)
	_build_left()

func _set_effect_category(name: String) -> void:
	effect_category = "" if name == "全部" else name
	_build_left()

func _add_technique_stat() -> void:
	var row := _row("technique")
	if row.is_empty():
		return
	for stat in STATS:
		if not row.has(stat.id) and str(stat.id) not in ["hp", "defense", "attack", "fire"]:
			row[stat.id] = 0
			row[str(stat.id) + "_step"] = 0
			_mark()
			_build_center()
			return
	_notify("可计算的属性都已在列表中")

func _remove_stat(row: Dictionary, key: String) -> void:
	row.erase(key)
	row.erase(key + "_step")
	if row.get("percents") is Dictionary:
		row.percents.erase(key)
	_mark()
	_build_center()
	_build_right()

func _pick_effect() -> void:
	_begin_add_effect()

func _move_effect(spell: Dictionary, index: int, delta: int) -> void:
	var next := index + delta
	if next < 0 or next >= spell.effects.size():
		return
	var item: Variant = spell.effects[index]
	spell.effects.remove_at(index)
	spell.effects.insert(next, item)
	_swap_growth_index(spell, index, next)
	if spell_effect_open == index:
		spell_effect_open = next
	elif spell_effect_open == next:
		spell_effect_open = index
	_mark()
	_build_center()

func _remove_effect(spell: Dictionary, index: int) -> void:
	spell.effects.remove_at(index)
	_shift_growth_after_remove(spell, index)
	if spell_effect_open == index:
		spell_effect_open = -1
	elif spell_effect_open > index:
		spell_effect_open -= 1
	_mark()
	_build_center()
	_build_right()

func _batch_growth() -> void:
	_open_batch()

func _set_effect_value(value: Variant, effect: Dictionary, spell: Dictionary, index: int, key: String, param_type: String) -> void:
	var stored: Variant = value
	if param_type == "percent":
		stored = float(value) / 100.0
	elif param_type == "int":
		stored = int(value)
	elif param_type == "bool":
		stored = bool(value)
	if int(view_level.spell) <= 1:
		effect[key] = stored
	else:
		_store_level_override(spell, index, key, stored)
	_mark()

func _set_battle_value(value: float, key: String, integer: bool) -> void:
	battle[key] = int(value) if integer else value

func _store_level_override(spell: Dictionary, index: int, key: String, value: Variant) -> void:
	if int(view_level.spell) <= 1:
		return
	if not spell.get("growth") is Array:
		spell.growth = [{}, {}, {}]
	while spell.growth.size() < int(view_level.spell):
		spell.growth.append({})
	var slot: int = int(view_level.spell) - 1
	if not spell.growth[slot] is Dictionary:
		spell.growth[slot] = {}
	if not spell.growth[slot].get("effects") is Dictionary:
		spell.growth[slot].effects = {}
	if not spell.growth[slot].effects.get(str(index)) is Dictionary:
		spell.growth[slot].effects[str(index)] = {}
	spell.growth[slot].effects[str(index)][key] = value

func _grown_effect(spell: Dictionary, effect: Dictionary, index: int) -> Dictionary:
	var copy := effect.duplicate(true)
	if int(view_level.spell) <= 1 or not spell.get("growth") is Array:
		return copy
	var slot := int(view_level.spell) - 1
	if slot >= spell.growth.size() or not spell.growth[slot] is Dictionary:
		return copy
	var patch: Variant = spell.growth[slot].get("effects", {}).get(str(index), {})
	if patch is Dictionary:
		copy.merge(patch, true)
	return copy

func _test_effect() -> void:
	var definition := _row("effect")
	if definition.is_empty():
		return
	var spell := Database.blank_spell(spells, effects)
	spell.name = definition.name + "测试"
	spell.effects = [Registry.instance_from(definition)]
	spell._persisted = false
	spells.append(spell)
	selected.spell = spell.id
	battle.kind = "spell"
	battle.id = spell.id
	dirty = true
	dirty_files["spells"] = true
	%Status.text = "已生成未保存的测试法术"
	set_page("battle")

func _add_reference_block(id: String) -> void:
	var users: Array = references.get(id, [])
	%RightBody.add_child(_section("引用情况"))
	if users.is_empty():
		%RightBody.add_child(_muted("已检查物品学习、原型 NPC、NPC 覆盖、妖兽技能和当前快照，没有找到引用。历史存档文件未逐个扫描。"))
		return
	var counts := {}
	for user in users:
		counts[user.kind] = int(counts.get(user.kind, 0)) + 1
	for kind in counts:
		%RightBody.add_child(_label("%s：%d" % [kind, counts[kind]], EDITOR_FONT_SIZE, TEXT))
	for user in users:
		%RightBody.add_child(_label("%s · %s" % [user.kind, user.label], EDITOR_FONT_SIZE, MUTED))

func _reset_battle() -> void:
	battle = {"kind": "spell", "id": "", "level": 1, "caster_hp": 200, "caster_max_hp": 200, "caster_mp": 80, "caster_attack": 40, "caster_defense": 8, "target_hp": 300, "target_defense": 4, "crit": 0.0, "crit_damage": 1.5, "seed": 7, "times": 20}

func _ensure_battle() -> void:
	if battle.is_empty():
		_reset_battle()
	if str(battle.id).is_empty():
		var rows: Array = techniques if battle.kind == "technique" else spells
		if not rows.is_empty():
			battle.id = rows[0].id

func _reset_battle_form() -> void:
	_reset_battle()
	battle_result = {}
	_build_center()
	_build_right()

func _battle_row() -> Dictionary:
	_ensure_battle()
	return _find(techniques if battle.kind == "technique" else spells, str(battle.id))

func _battle_player(row: Dictionary) -> Dictionary:
	var player := _player_stub()
	player.base.hp = int(battle.get("caster_max_hp", 200))
	player.base.attack = int(battle.get("caster_attack", 40))
	player.base.defense = int(battle.get("caster_defense", 8))
	player.techniques = {row.id: int(battle.level)}
	player.technique_slots = [row.id]
	return player

func _player_stub() -> Dictionary:
	return {"base": {"hp": 120, "mp": 60, "attack": 18, "defense": 6, "speed": 10}, "equipped": {}, "equipment_instances": {}, "growth": {"attributes": {}}, "fortunes": {}, "realm": 1, "techniques": {}, "technique_slots": []}

func _mark() -> void:
	if _ui_lock:
		return
	if not _last_edit_state.is_empty():
		_undo_states.append(_last_edit_state)
		if _undo_states.size() > 100:
			_undo_states.pop_front()
	_redo_states.clear()
	dirty = true
	if page == "technique":
		dirty_files["techniques"] = true
		dirty_files["flow"] = true
	elif page == "spell":
		dirty_files["spells"] = true
		dirty_files[str(_row("spell").get("_source", "spells"))] = true
		_refresh_auto_text()
	elif page == "effect":
		dirty_files["effects"] = true
	%Status.text = "有未保存修改"
	if page == "spell" and list_host != null and is_instance_valid(list_host):
		_fill_list()
	_build_right()
	_last_edit_state = _edit_snapshot()

func _mark_preview() -> void:
	dirty = true
	%Status.text = "有未保存修改"
	_build_right()

func _notify(text: String) -> void:
	if confirm != null and confirm.visible:
		confirm.hide()
	notice.dialog_text = text
	notice.popup_centered()

func _row_mark(row: Dictionary) -> String:
	if page == "technique":
		return str(row.get("rarity", ""))
	if page == "spell":
		return str(row.get("spell_type", _legacy_type(row)))
	if page == "effect":
		return str(row.get("category", ""))
	return ""

func _row_element(row: Dictionary) -> String:
	if page == "technique" or (page == "battle" and battle.get("kind") == "technique"):
		return _element_label(row.get("_flow", {}).get("element", ""))
	return _element_label(row.get("element", ""))

func _legacy_type(row: Dictionary) -> String:
	if float(row.get("heal", 0)) > 0.0:
		return "恢复"
	if float(row.get("guard", 0)) > 0.0:
		return "防护"
	if row.has("effects"):
		return str(row.get("spell_type", "伤害"))
	return "伤害"

func _element_label(value: Variant) -> String:
	var text := str(value)
	return "无属性" if text.is_empty() or text == "无" else text

func _realm_label(minimum: int) -> String:
	if minimum <= 0:
		return "不限"
	for name in REALMS:
		if int(REALM_MIN.get(name, -1)) == minimum:
			return name
	if minimum <= 9:
		return "炼气"
	return "炼气"

func _format_amount(stat: Dictionary, amount: float) -> String:
	if bool(stat.get("ratio", false)):
		return "%+d%%" % roundi(amount * 100.0)
	return "%+d" % roundi(amount)

func _stat_label(key: String) -> String:
	return {"hp": "生命", "mp": "灵力", "attack": "攻击", "defense": "防御", "speed": "速度", "fire": "法术伤害"}.get(key, key)

func _plain(value: Variant) -> String:
	return str(snapped(float(value), 0.01))

func _effect_color(definition: Dictionary) -> Color:
	match str(definition.get("category", "")):
		"伤害", "减益":
			return DAMAGE
		"恢复", "防护", "增益":
			return HEAL
		_:
			return GOLD

func _build_spell_filters() -> void:
	_clear(%SpellTools)
	%SpellTools.visible = true
	var search_box := LineEdit.new()
	search_box.placeholder_text = "搜索法术名称 / ID"
	search_box.text = search
	search_box.custom_minimum_size.y = 30
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(search_box)
	search_box.text_changed.connect(func(value: String) -> void:
		search = value
		_fill_list())
	%SpellTools.add_child(search_box)
	var chips := FlowContainer.new()
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	for label in ["全部", "金", "木", "水", "火", "土", "风", "雷", "冰", "无"]:
		var stored: String = "无属性" if str(label) == "无" else str(label)
		var active: bool = elements.is_empty() if str(label) == "全部" else stored in elements
		chips.add_child(_chip(label, active, _toggle_element.bind(stored)))
	%SpellTools.add_child(chips)
	var filters := FlowContainer.new()
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 4)
	var grades: Array = ["全部品阶"]
	grades.append_array(Database.RARITIES)
	filters.add_child(_tune(_choice("品阶", grades, "全部品阶" if grade.is_empty() else grade, func(value: String) -> void:
		grade = "" if value == "全部品阶" else value
		_fill_list())))
	var realms: Array = ["全部境界"]
	realms.append_array(_qi_realms())
	filters.add_child(_tune(_choice("境界", realms, "全部境界" if spell_realm.is_empty() else spell_realm, func(value: String) -> void:
		spell_realm = "" if value == "全部境界" else value
		_fill_list())))
	var types: Array = ["全部类型"]
	types.append_array(SPELL_TYPES)
	filters.add_child(_tune(_choice("类型", types, "全部类型" if spell_type.is_empty() else spell_type, func(value: String) -> void:
		spell_type = "" if value == "全部类型" else value
		_fill_list())))
	filters.add_child(_action("重置", _reset_spell_filters))
	%SpellTools.add_child(filters)

func _reset_spell_filters() -> void:
	search = ""
	elements.clear()
	grade = ""
	spell_realm = ""
	spell_type = ""
	_build_left()

func _add_spell_row(row: Dictionary) -> void:
	var picked := str(row.get("id", "")) == str(selected.get("spell", ""))
	var item := PanelContainer.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.custom_minimum_size.y = 36
	item.tooltip_text = str(row.get("name", row.get("id", "")))
	item.add_theme_stylebox_override("panel", _box(SELECTED if picked else LIST, 6, 4))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	item.add_child(line)
	var element := _label(_element_short(row.get("element", "")), EDITOR_FONT_SIZE, _element_color_of(str(row.get("element", ""))))
	element.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	element.custom_minimum_size.x = 28
	line.add_child(element)
	var name := _label(str(row.get("name", row.get("id", ""))), EDITOR_FONT_SIZE, TEXT)
	name.tooltip_text = item.tooltip_text
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	line.add_child(name)
	var rarity := str(row.get("rarity", ""))
	var grade_label := _label(rarity if not rarity.is_empty() else "未标", EDITOR_FONT_SIZE, _rarity_color(rarity))
	grade_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	line.add_child(grade_label)
	line.add_child(_mini("编辑", _edit_spell_row.bind(str(row.id))))
	item.gui_input.connect(_on_row_input.bind("spell", str(row.id)))
	list_host.add_child(item)

func _edit_spell_row(id: String) -> void:
	_select("spell", id)
	%CenterScroll.scroll_vertical = 0

func _build_spell_basics(row: Dictionary) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_child(_fill(_track(_text_field("名称", str(row.get("name", "")), true, func(value: String) -> void:
		row.name = value
		_mark()), "name")))
	var rarity_options: Array = []
	var rarity := str(row.get("rarity", ""))
	if rarity.is_empty() or rarity not in Database.RARITIES:
		rarity_options.append("未标")
	for item in Database.RARITIES:
		rarity_options.append(item)
	grid.add_child(_fill(_track(_choice("品阶", rarity_options, rarity if rarity in rarity_options else "未标", func(value: String) -> void:
		if value == "未标":
			row.erase("rarity")
		else:
			row.rarity = value
		_mark()), "rarity")))
	var element_options: Array = ["无"]
	element_options.append_array(Database.ROOTS)
	var element := str(row.get("element", "无"))
	if element.is_empty():
		element = "无"
	grid.add_child(_fill(_track(_choice("五行", element_options, element if element in element_options else "无", func(value: String) -> void:
		row.element = value
		_mark()), "element")))
	grid.add_child(_fill(_track(_choice("适用境界", _qi_realms(), _realm_label(int(row.get("realm_min", 0))), func(value: String) -> void:
		var minimum := int(REALM_MIN.get(value, 0))
		if minimum <= 0:
			row.erase("realm_min")
		else:
			row.realm_min = minimum
		_mark()), "realm")))
	var type_now := str(row.get("spell_type", ""))
	if type_now.is_empty() or type_now not in SPELL_TYPES:
		type_now = _legacy_type(row) if _legacy_type(row) in SPELL_TYPES else "伤害"
	grid.add_child(_fill(_track(_choice("法术类型", SPELL_TYPES, type_now, func(value: String) -> void:
		row.spell_type = value
		_mark()), "type")))
	var cap := _spell_level_cap(row)
	var cap_field := _spin_field("等级上限", cap, 1, cap if row.has("levels") else 3, func(value: float) -> void:
		if row.has("levels"):
			return
		row.max_level = clampi(int(value), 1, 3)
		if not row.get("growth") is Array:
			row.growth = []
		while row.growth.size() < int(row.max_level):
			row.growth.append({})
		view_level.spell = clampi(int(view_level.spell), 1, int(row.max_level))
		_mark()
		_build_center())
	if row.has("levels"):
		_lock_spin(cap_field)
	grid.add_child(_fill(_track(cap_field, "level")))
	%CenterBody.add_child(grid)
	var persisted := bool(row.get("_persisted", false))
	%CenterBody.add_child(_track(_text_field("法术 ID", str(row.get("id", "")), not persisted, func(value: String) -> void:
		_rename_spell(row, value)), "id"))
	%CenterBody.add_child(_muted("品阶只有升级表中的凡品、黄阶。五行是八灵根或无属性。适用境界会随法术保存；当前学习仍由物品或存档授予，不按这个门槛拦截。"))

func _build_spell_cast(row: Dictionary) -> void:
	%CenterBody.add_child(_section("施法参数"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_child(_fill(_target_field(row)))
	grid.add_child(_fill(_track(_spin_field("灵力消耗", float(row.get("mp", 0)), 0, 9999, func(value: float) -> void:
		row.mp = int(value)
		_mark()), "mp")))
	grid.add_child(_fill(_track(_spin_field("冷却回合", float(row.get("cd", row.get("cooldown", 0))), 0, 99, func(value: float) -> void:
		row.cd = int(value)
		_mark()), "cd")))
	grid.add_child(_fill(_read_only_text("其他资源消耗", "无。施法只检查灵力。")))
	grid.add_child(_fill(_read_only_text("施法条件", "无独立条件。由灵力、冷却、沉默和封脉拦截。")))
	grid.add_child(_fill(_read_only_text("学习条件", _learn_text(row))))
	%CenterBody.add_child(grid)
	%CenterBody.add_child(_muted("友方单体、敌方群体、友方群体没有可执行的多目标战斗，下拉里已禁用。"))

func _build_spell_effects(row: Dictionary) -> void:
	var bar := _section_bar("效果组合")
	var add := _action("＋ 添加效果", _begin_add_effect)
	_style_button(add, true)
	bar.add_child(add)
	%CenterBody.add_child(_track(bar, "effects"))
	if row.has("levels"):
		%CenterBody.add_child(_muted("试学法术按等级字典累加。效果库实例不能写进同一张表，可以复制为新法术后再组合。"))
		%CenterBody.add_child(_trial_card(row))
		return
	if not row.get("effects") is Array:
		%CenterBody.add_child(_muted("当前仍按原字段结算。卡片修改的是伤害系数、治疗、护体和附加状态。"))
		if not _legacy_has_payload(row):
			%CenterBody.add_child(_muted("尚未配置法术效果"))
			%CenterBody.add_child(_action("＋ 添加第一个效果", _begin_add_effect))
		%CenterBody.add_child(_legacy_card(row))
		return
	if row.effects.is_empty():
		%CenterBody.add_child(_muted("尚未配置法术效果"))
		%CenterBody.add_child(_action("＋ 添加第一个效果", _begin_add_effect))
		return
	var index := 0
	for effect in row.effects:
		%CenterBody.add_child(_ordered_card(row, effect, index))
		index += 1

func _build_growth_section(row: Dictionary) -> void:
	var cap := _spell_level_cap(row)
	view_level.spell = clampi(int(view_level.spell), 1, cap)
	var bar := _section_bar("等级成长")
	var level := OptionButton.new()
	level.custom_minimum_size = Vector2(96, 28)
	for index in cap:
		level.add_item("等级 %d" % [index + 1])
	level.selected = view_level.spell - 1
	level.item_selected.connect(func(index: int) -> void:
		view_level.spell = index + 1
		_build_center()
		_build_right())
	bar.add_child(level)
	bar.add_child(_action("成长配置", _open_growth))
	bar.add_child(_action("批量设置", _open_batch))
	%CenterBody.add_child(_track(bar, "growth"))
	var bits: PackedStringArray = ["等级 %d" % view_level.spell, "灵力 %d" % Database._spell_mp(row, view_level.spell), "冷却 %d" % Database._spell_cd(row, view_level.spell)]
	for entry in _spell_effect_lines(row, view_level.spell):
		bits.append(str(entry.text))
	%CenterBody.add_child(_wrapped(" | ".join(bits)))
	if row.has("levels"):
		%CenterBody.add_child(_muted("试学法术后一级覆盖同名字段。正式熟练度仍以等级表长度为准。"))
	elif not row.has("effects"):
		%CenterBody.add_child(_muted("旧法术沿用原公式：伤害系数每级 +0.1，治疗每级 +10，护体每级 +2。"))
	elif int(view_level.spell) > 1:
		%CenterBody.add_child(_muted("当前显示这一级覆盖后的结果。在效果卡片里修改，会写入这一级覆盖。"))

func _build_description_section(row: Dictionary) -> void:
	%CenterBody.add_child(_section("法术说明"))
	var key := _token(row)
	var auto := bool(spell_auto.get(key, false))
	var toggle := CheckBox.new()
	toggle.text = "自动生成说明"
	toggle.button_pressed = auto
	toggle.add_theme_color_override("font_color", TEXT)
	toggle.toggled.connect(func(on: bool) -> void:
		if _ui_lock:
			return
		if on:
			spell_auto[key] = true
			_refresh_auto_text(true)
		else:
			spell_auto.erase(key)
		_mark()
		_build_center())
	%CenterBody.add_child(toggle)
	spell_desc = TextEdit.new()
	spell_desc.custom_minimum_size = Vector2(0, 72)
	spell_desc.placeholder_text = "手动说明。右侧仍显示实际效果。"
	spell_desc.editable = not auto
	spell_desc.text = str(row.get("description", ""))
	spell_desc.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
	spell_desc.add_theme_color_override("font_color", TEXT)
	spell_desc.text_changed.connect(func() -> void:
		if _ui_lock:
			return
		spell_auto.erase(key)
		row.description = spell_desc.text
		_mark())
	%CenterBody.add_child(_track(spell_desc, "description"))
	var again := _action("重新生成", _regenerate_description)
	again.disabled = not auto
	%CenterBody.add_child(again)
	%CenterBody.add_child(_muted("手动说明不会替代右侧根据效果算出的实际效果。"))

func _build_ai_section(row: Dictionary) -> void:
	var bar := _section_bar("AI施法配置")
	bar.add_child(_action("收起" if spell_ai_open else "展开", func() -> void:
		spell_ai_open = not spell_ai_open
		_build_center()))
	%CenterBody.add_child(_track(bar, "ai"))
	if not spell_ai_open:
		%CenterBody.add_child(_muted("默认收起。展开后使用现有战斗 AI 的施法策略。"))
		return
	var enabled := row.get("ai") is Dictionary
	var check := CheckBox.new()
	check.text = "启用AI使用"
	check.button_pressed = enabled
	check.add_theme_color_override("font_color", TEXT)
	check.toggled.connect(func(on: bool) -> void:
		if on and not row.get("ai") is Dictionary:
			row.ai = {"policy": "attack"}
		elif not on:
			row.erase("ai")
		_mark()
		_build_center())
	%CenterBody.add_child(check)
	if not enabled:
		%CenterBody.add_child(_muted("未启用时不写策略。战斗 AI 仍按法术槽顺序选择。"))
		return
	var values: Array = Database.AI_POLICIES
	var policy := str(row.ai.get("policy", "attack"))
	var label: String = str(AI_LABELS[maxi(0, values.find(policy))] if policy in values else AI_LABELS[0])
	%CenterBody.add_child(_choice("施法策略", AI_LABELS, label, func(value: String) -> void:
		row.ai.policy = values[AI_LABELS.find(value)]
		_mark()
		_build_center()))
	%CenterBody.add_child(_muted("优先级按已装备法术槽的顺序。目标存在指定状态时，这门法术会先于其他攻击法术。没有单独的优先级数值。"))
	if policy == "self_low_hp":
		%CenterBody.add_child(_spin_field("自身生命低于（%）", float(row.ai.get("hp", 0.5)) * 100.0, 1, 100, func(value: float) -> void:
			row.ai.hp = value / 100.0
			_mark()))
	elif policy == "self_status" or policy == "target_status":
		var choices := _status_choices()
		var current := _status_label(str(row.ai.get("status", "")))
		if current not in choices.labels and not choices.labels.is_empty():
			current = str(choices.labels[0])
		%CenterBody.add_child(_choice("触发状态", choices.labels, current, func(value: String) -> void:
			var labels: Array = choices.labels
			var found: int = labels.find(value)
			row.ai.status = choices.values[found] if found >= 0 else value
			_mark()))
	else:
		%CenterBody.add_child(_muted("这个策略没有额外触发条件。"))

func _ordered_card(spell: Dictionary, effect: Dictionary, index: int) -> Control:
	var definition := Registry.find(effects, str(effect.get("effect_id", "")))
	var shown := _grown_effect(spell, effect, index)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(FIELD, 8, 4))
	var box := VBoxContainer.new()
	card.add_child(box)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 4)
	box.add_child(title)
	title.add_child(_label("%02d · %s" % [index + 1, definition.get("name", effect.get("type", "效果"))], EDITOR_FONT_SIZE, TEXT))
	var category := _label(str(definition.get("category", "")), EDITOR_FONT_SIZE, _effect_color(definition))
	category.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(category)
	title.add_child(_mini("↑", _move_effect.bind(spell, index, -1), index == 0))
	title.add_child(_mini("↓", _move_effect.bind(spell, index, 1), index >= spell.effects.size() - 1))
	title.add_child(_mini("编辑", _toggle_effect_editor.bind(index)))
	title.add_child(_mini("复制", _copy_effect.bind(spell, index)))
	title.add_child(_mini("禁用" if bool(effect.get("enabled", true)) else "启用", _toggle_effect.bind(spell, index)))
	title.add_child(_mini("删除", _remove_effect.bind(spell, index)))
	var parts := _summary_parts(shown, definition)
	if not parts[0].is_empty():
		box.add_child(_colored_wrap(parts[0], _effect_color(definition)))
	if not parts[1].is_empty():
		box.add_child(_colored_wrap(parts[1], GOLD))
	if spell_effect_open == index:
		_add_param_editors(box, spell, effect, index, definition, shown)
	return card

func _legacy_card(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(FIELD, 8, 4))
	var box := VBoxContainer.new()
	card.add_child(box)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 4)
	box.add_child(title)
	var kind := "生命恢复" if float(row.get("heal", 0)) > 0.0 else "护体" if float(row.get("guard", 0)) > 0.0 else "直接伤害"
	title.add_child(_label("01 · %s" % kind, EDITOR_FONT_SIZE, TEXT))
	var mark := _label(_legacy_type(row), EDITOR_FONT_SIZE, HEAL if kind != "直接伤害" else DAMAGE)
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(mark)
	title.add_child(_mini("↑", func() -> void: pass, true))
	title.add_child(_mini("↓", func() -> void: pass, true))
	title.add_child(_mini("编辑", func() -> void:
		spell_effect_open = -1 if spell_effect_open == 0 else 0
		_build_center()))
	title.add_child(_mini("删除", func() -> void:
		if float(row.get("heal", 0)) > 0.0:
			row.heal = 0
		elif float(row.get("guard", 0)) > 0.0:
			row.guard = 0
		else:
			row.multiplier = 0
		_mark()
		_build_center()))
	for entry in _spell_effect_lines(row, int(view_level.spell)):
		box.add_child(_colored_wrap(str(entry.text), _line_color(str(entry.kind))))
	if spell_effect_open == 0:
		if kind == "生命恢复":
			box.add_child(_spin_field("治疗", float(row.get("heal", 0)), 0, 99999, func(value: float) -> void:
				row.heal = value
				row.multiplier = 0
				row.guard = 0
				_mark()))
		elif kind == "护体":
			box.add_child(_spin_field("护体", float(row.get("guard", 0)), 0, 99999, func(value: float) -> void:
				row.guard = value
				row.heal = 0
				row.multiplier = 0
				_mark()))
		else:
			box.add_child(_spin_field("攻击系数（%）", float(row.get("multiplier", 0)) * 100.0, 0, 1000, func(value: float) -> void:
				row.multiplier = value / 100.0
				row.heal = 0
				row.guard = 0
				_mark()))
		var choices := _status_choices()
		var labels: Array = ["无"]
		labels.append_array(choices.labels)
		box.add_child(_choice("附加状态", labels, _status_label(str(row.get("status", ""))), func(value: String) -> void:
			if value == "无":
				row.status = ""
			else:
				var status_labels: Array = choices.labels
				var found: int = status_labels.find(value)
				row.status = choices.values[found] if found >= 0 else value
			_mark()
			_build_center()))
	return card

func _trial_card(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(FIELD, 8, 4))
	var box := VBoxContainer.new()
	card.add_child(box)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 4)
	box.add_child(title)
	title.add_child(_label("01 · 本级效果", EDITOR_FONT_SIZE, TEXT))
	var mark := _label("试学", EDITOR_FONT_SIZE, GOLD)
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(mark)
	title.add_child(_mini("编辑", func() -> void:
		spell_effect_open = -1 if spell_effect_open == 0 else 0
		_build_center()))
	for entry in _spell_effect_lines(row, int(view_level.spell)):
		box.add_child(_colored_wrap(str(entry.text), _line_color(str(entry.kind))))
	if spell_effect_open == 0 and row.levels is Array and not row.levels.is_empty():
		var current: Dictionary = row.levels[clampi(int(view_level.spell), 1, row.levels.size()) - 1]
		for key in current.keys():
			var field := str(key)
			if current[key] is String:
				box.add_child(_text_field(field, str(current[key]), true, _set_trial_text.bind(current, field)))
			elif current[key] is int or current[key] is float:
				box.add_child(_spin_field(field, float(current[key]), 0, 99999, _set_trial_number.bind(current, field)))
	return card

func _add_param_editors(box: VBoxContainer, spell: Dictionary, effect: Dictionary, index: int, definition: Dictionary, shown: Dictionary) -> void:
	box.add_child(_wrapped("触发：施法时按节点顺序执行；状态概率、持续回合按下列参数结算。任意自定义触发条件当前未支持。"))
	for param in definition.get("parameters", []):
		if not param is Dictionary:
			continue
		var key := str(param.get("id", ""))
		var param_type := str(param.get("type", ""))
		var value: Variant = shown.get(key, param.get("default"))
		if param_type == "bool":
			var toggle := CheckBox.new()
			toggle.text = str(param.get("name", key))
			toggle.button_pressed = bool(value)
			toggle.add_theme_color_override("font_color", TEXT)
			toggle.toggled.connect(_set_effect_value.bind(effect, spell, index, key, param_type))
			box.add_child(_track(toggle, "effect_%d_%s" % [index, key]))
		elif param_type == "enum":
			box.add_child(_track(_choice(str(param.get("name", key)), param.get("options", []), str(value), _set_effect_value.bind(effect, spell, index, key, param_type)), "effect_%d_%s" % [index, key]))
		else:
			var shown_number := float(value) * 100.0 if param_type == "percent" else float(value)
			var minimum := float(param.get("min", 0)) * (100.0 if param_type == "percent" else 1.0)
			var maximum := float(param.get("max", 1)) * 100.0 if param_type == "percent" else float(param.get("max", 99999))
			box.add_child(_track(_spin_field(str(param.get("name", key)), shown_number, minimum, maximum, _set_effect_value.bind(effect, spell, index, key, param_type)), "effect_%d_%s" % [index, key]))

func _toggle_effect_editor(index: int) -> void:
	spell_effect_open = -1 if spell_effect_open == index else index
	_build_center()

func _summary_parts(effect: Dictionary, definition: Dictionary) -> PackedStringArray:
	var text := Registry.describe(effect, definition, catalog.get("spell_growth", {}))
	var main: PackedStringArray = []
	var extra: PackedStringArray = []
	for part in text.split("，"):
		if part.contains("概率") or part.contains("回合") or part.contains("层"):
			extra.append(part)
		else:
			main.append(part)
	return PackedStringArray([" | ".join(main), " | ".join(extra)])

func _begin_add_effect() -> void:
	var spell := _row("spell")
	if spell.is_empty():
		_notify("先选择一门法术")
		return
	if spell.has("levels"):
		_notify("试学法术按等级字典结算，不能把效果库实例写进同一门法术。可以复制为新法术后再添加效果。")
		return
	if spell.get("effects") is Array:
		_open_effect_picker()
		return
	var blocked := _promote_block_reason(spell)
	if not blocked.is_empty():
		_notify(blocked)
		return
	_confirm("这门法术目前按原字段结算。继续后会改成按效果顺序结算，并把当前数值写成效果实例。伤害系数和治疗会按原每级增量写入 2 级、3 级覆盖。是否继续？", func() -> void:
		var error := _promote_legacy(spell)
		if not error.is_empty():
			_notify(error)
			return
		_mark()
		_build_center()
		_open_effect_picker())

func _promote_block_reason(spell: Dictionary) -> String:
	if float(spell.get("guard", 0)) > 0.0:
		return "这门法术的护体是旧的固定护体。效果库护盾按攻击系数结算，不能自动改成效果实例。"
	return ""

func _promote_legacy(spell: Dictionary) -> String:
	var list: Array = []
	var growth: Array = [{}, {}, {}]
	if float(spell.get("heal", 0)) > 0.0:
		var definition := Registry.find(effects, "effect_heal")
		if definition.is_empty():
			return "没有生命恢复的效果定义"
		var inst := Registry.instance_from(definition)
		var amount := int(spell.heal)
		inst.amount = amount
		inst.power = 0.0
		inst.periodic = 0.0
		inst.percent_max_hp = 0.0
		list.append(inst)
		growth[1] = {"effects": {"0": {"amount": amount + 10}}}
		growth[2] = {"effects": {"0": {"amount": amount + 20}}}
	else:
		var definition := Registry.find(effects, "effect_direct_damage")
		if definition.is_empty():
			return "没有直接伤害的效果定义"
		var inst := Registry.instance_from(definition)
		var power := float(spell.get("multiplier", 0))
		inst.power = power
		inst.flat = 0
		inst.hits = 1
		list.append(inst)
		growth[1] = {"effects": {"0": {"power": power + 0.1}}}
		growth[2] = {"effects": {"0": {"power": power + 0.2}}}
	var status := str(spell.get("status", ""))
	if not status.is_empty():
		var matched := {}
		for item in effects:
			if str(item.get("status", "")) == status:
				matched = item
				break
		if matched.is_empty():
			return "状态 %s 没有对应效果定义，不能改成效果实例。" % status
		var inst := Registry.instance_from(matched)
		if inst.has("chance"):
			inst.chance = float(catalog.get("rules", {}).get("status_chance", 0.3))
		if inst.has("turns"):
			inst.turns = int(catalog.get("rules", {}).get("status_turns", 2))
		list.append(inst)
	spell.ordered = true
	spell.effects = list
	spell.growth = growth
	spell.max_level = 3
	if str(spell.get("target", "")).is_empty():
		spell.target = "self" if float(spell.get("heal", 0)) > 0.0 else "enemy"
	if str(spell.get("spell_type", "")).is_empty():
		spell.spell_type = _legacy_type(spell)
	spell.erase("multiplier")
	spell.erase("heal")
	spell.erase("guard")
	spell.erase("status")
	return ""

func _open_effect_picker() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "添加效果"
	dialog.ok_button_text = "确认添加"
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2(520, 560)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 460)
	dialog.add_child(box)
	var search_box := LineEdit.new()
	search_box.placeholder_text = "搜索效果"
	box.add_child(search_box)
	var categories: Array = ["全部分类"]
	categories.append_array(Registry.CATEGORIES)
	var category := OptionButton.new()
	for item in categories:
		category.add_item(str(item))
	box.add_child(category)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(460, 240)
	box.add_child(list)
	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(460, 72)
	detail.add_theme_color_override("font_color", TEXT)
	box.add_child(detail)
	var refresh := func() -> void:
		list.clear()
		var query := search_box.text.strip_edges().to_lower()
		var chosen := str(categories[category.selected])
		for effect_row in effects:
			var effect_name := str(effect_row.get("name", ""))
			var effect_id := str(effect_row.get("id", ""))
			if not query.is_empty() and query not in effect_name.to_lower() and query not in effect_id.to_lower():
				continue
			if chosen != "全部分类" and str(effect_row.get("category", "")) != chosen:
				continue
			list.add_item("%s · %s" % [effect_name, effect_row.get("category", "")])
			list.set_item_metadata(list.item_count - 1, effect_id)
		_show_effect_detail(list, detail)
	search_box.text_changed.connect(func(_value: String) -> void: refresh.call())
	category.item_selected.connect(func(_index: int) -> void: refresh.call())
	list.item_selected.connect(func(_index: int) -> void: _show_effect_detail(list, detail))
	refresh.call()
	dialog.confirmed.connect(func() -> void:
		if list.get_selected_items().is_empty():
			_notify("先选择一个效果")
			return
		_append_effect(str(list.get_item_metadata(list.get_selected_items()[0])))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _show_effect_detail(list: ItemList, detail: Label) -> void:
	if list.get_selected_items().is_empty():
		detail.text = "选择效果后显示介绍。"
		return
	var definition := Registry.find(effects, str(list.get_item_metadata(list.get_selected_items()[0])))
	detail.text = str(definition.get("summary", definition.get("name", "")))

func _append_effect(effect_id: String) -> void:
	var spell := _row("spell")
	if spell.is_empty() or not spell.get("effects") is Array or effect_id.is_empty():
		return
	var definition := Registry.find(effects, effect_id)
	if definition.is_empty():
		_notify("效果定义不存在")
		return
	var instance := Registry.instance_from(definition)
	instance["node_id"] = _next_node_id(spell)
	spell.effects.append(instance)
	spell_effect_open = spell.effects.size() - 1
	_mark()
	_build_center()

func _next_node_id(spell: Dictionary) -> String:
	var used := {}
	for effect in spell.get("effects", []):
		if effect is Dictionary:
			used[str(effect.get("node_id", ""))] = true
	var serial := 1
	while used.has("node_%d" % serial):
		serial += 1
	return "node_%d" % serial

func _copy_effect(spell: Dictionary, index: int) -> void:
	if index < 0 or index >= spell.get("effects", []).size():
		return
	var copy: Dictionary = spell.effects[index].duplicate(true)
	copy["node_id"] = _next_node_id(spell)
	var target: int = spell.effects.size()
	spell.effects.append(copy)
	for delta in spell.get("growth", []):
		if delta is Dictionary and delta.get("effects") is Dictionary and delta.effects.has(str(index)):
			delta.effects[str(target)] = delta.effects[str(index)].duplicate(true)
	spell_effect_open = target
	_mark()
	_build_center()

func _toggle_effect(spell: Dictionary, index: int) -> void:
	if index < 0 or index >= spell.get("effects", []).size():
		return
	spell.effects[index]["enabled"] = not bool(spell.effects[index].get("enabled", true))
	_mark()
	_build_center()

func _open_growth() -> void:
	var spell := _row("spell")
	if spell.is_empty():
		_notify("先选择一门法术")
		return
	if spell.has("levels"):
		_open_trial_growth(spell, false)
		return
	if not spell.has("effects"):
		_notify(_legacy_growth_text(spell))
		return
	_open_growth_dialog(spell, _scalable_params(spell), false)

func _open_batch() -> void:
	var spell := _row("spell")
	if spell.is_empty():
		_notify("先选择一门法术")
		return
	if spell.has("levels"):
		_open_trial_growth(spell, true)
		return
	if not spell.has("effects"):
		_notify(_legacy_growth_text(spell))
		return
	_open_growth_dialog(spell, _scalable_params(spell), true)

func _legacy_growth_text(spell: Dictionary) -> String:
	var lines: PackedStringArray = ["旧法术成长由原公式决定：伤害系数每级 +0.1，治疗每级 +10，护体每级 +2。"]
	for level in [1, 2, 3]:
		var parts: PackedStringArray = []
		for entry in _spell_effect_lines(spell, level):
			parts.append(str(entry.text))
		lines.append("等级 %d：%s" % [level, "；".join(parts)])
	return "\n".join(lines)

func _scalable_params(spell: Dictionary) -> Array:
	var found: Array = [
		{"index": -1, "key": "mp", "name": "灵力消耗", "type": "int"},
		{"index": -1, "key": "cd", "name": "冷却回合", "type": "int"},
	]
	var index := 0
	for effect in spell.get("effects", []):
		var definition := Registry.find(effects, str(effect.get("effect_id", "")))
		for param in definition.get("parameters", []):
			if param is Dictionary and bool(param.get("scales", false)):
				found.append({"index": index, "key": str(param.get("id", "")), "name": "%s·%s" % [definition.get("name", "效果"), param.get("name", param.get("id", ""))], "type": str(param.get("type", "int"))})
		index += 1
	return found

func _open_growth_dialog(spell: Dictionary, specs: Array, batch: bool) -> void:
	if specs.is_empty():
		_notify("这门法术没有可成长的参数")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "批量设置" if batch else "成长配置"
	dialog.ok_button_text = "写入"
	dialog.cancel_button_text = "取消"
	dialog.min_size = Vector2(480, 320)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var names: PackedStringArray = []
	for spec in specs:
		names.append(str(spec.name))
	box.add_child(_wrapped("可成长参数：" + "、".join(names)))
	var which := OptionButton.new()
	var mode := OptionButton.new()
	var amount := SpinBox.new()
	amount.min_value = -9999
	amount.max_value = 99999
	amount.step = 1
	var ratio := SpinBox.new()
	ratio.min_value = -500
	ratio.max_value = 500
	ratio.step = 1
	if batch:
		box.add_child(_muted("整数和灵力、冷却使用第一个增量。比例参数使用百分数增量。等级 1 保留当前值，更高等级写成覆盖。"))
		box.add_child(_muted("整数每级增量"))
		box.add_child(amount)
		box.add_child(_muted("比例每级增量（%）"))
		box.add_child(ratio)
	else:
		for spec in specs:
			which.add_item(str(spec.name))
		mode.add_item("固定数值")
		mode.add_item("每级增量")
		mode.add_item("单级覆盖")
		box.add_child(which)
		box.add_child(mode)
		box.add_child(amount)
		box.add_child(_muted("比例参数按百分数填写，例如攻击系数 100 表示 100%。"))
	dialog.confirmed.connect(func() -> void:
		if batch:
			_apply_batch(spell, specs, amount.value, ratio.value / 100.0)
		else:
			_apply_one_growth(spell, specs[which.selected], mode.get_item_text(mode.selected), amount.value)
		_mark()
		_build_center()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _open_trial_growth(spell: Dictionary, batch: bool) -> void:
	var keys: Array = []
	if spell.levels is Array and not spell.levels.is_empty() and spell.levels[0] is Dictionary:
		for key in spell.levels[0]:
			if spell.levels[0][key] is int or spell.levels[0][key] is float:
				keys.append(str(key))
	if keys.is_empty():
		_notify("这门试学法术的一级没有可成长的数值字段")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "批量设置" if batch else "成长配置"
	dialog.ok_button_text = "写入"
	dialog.cancel_button_text = "取消"
	var box := VBoxContainer.new()
	dialog.add_child(box)
	box.add_child(_wrapped("试学等级表后一级会覆盖同名字段。这里写入的是该级结果。字段：" + "、".join(keys)))
	var which := OptionButton.new()
	for key in keys:
		which.add_item(str(key))
	var amount := SpinBox.new()
	amount.min_value = -999
	amount.max_value = 99999
	amount.step = 0.05
	if not batch:
		box.add_child(which)
	box.add_child(amount)
	dialog.confirmed.connect(func() -> void:
		var chosen: Array = keys if batch else [str(keys[which.selected])]
		for key in chosen:
			var base := float(spell.levels[0].get(key, 0))
			var step := amount.value
			for index in spell.levels.size():
				var level_row: Dictionary = spell.levels[index]
				var was_int := level_row.get(key) is int or spell.levels[0].get(key) is int
				level_row[key] = int(base + index * step) if was_int else base + index * step
		_mark()
		_build_center()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _apply_one_growth(spell: Dictionary, spec: Dictionary, mode: String, raw: float) -> void:
	var value: Variant = _growth_number(spec, raw)
	if mode == "固定数值":
		_write_growth_base(spell, spec, value)
		_clear_growth_key(spell, spec)
	elif mode == "每级增量":
		_apply_step(spell, spec, float(value) if str(spec.type) != "percent" else raw / 100.0)
	else:
		_write_growth_override(spell, int(view_level.spell), spec, value)

func _apply_batch(spell: Dictionary, specs: Array, int_step: float, ratio_step: float) -> void:
	for spec in specs:
		var step := ratio_step if str(spec.type) == "percent" else float(int_step)
		if step == 0.0:
			continue
		_apply_step(spell, spec, step)

func _apply_step(spell: Dictionary, spec: Dictionary, step: float) -> void:
	var base := _read_growth_base(spell, spec)
	for level in range(2, _spell_level_cap(spell) + 1):
		_write_growth_override(spell, level, spec, base + (level - 1) * step)

func _growth_number(spec: Dictionary, raw: float) -> Variant:
	if str(spec.type) == "percent":
		return raw / 100.0
	if str(spec.type) == "int":
		return int(raw)
	return raw

func _read_growth_base(spell: Dictionary, spec: Dictionary) -> float:
	if int(spec.index) < 0:
		return float(spell.get(spec.key, 0))
	return float(spell.effects[int(spec.index)].get(spec.key, 0))

func _write_growth_base(spell: Dictionary, spec: Dictionary, value: Variant) -> void:
	var stored: Variant = int(value) if str(spec.type) == "int" else value
	if int(spec.index) < 0:
		spell[str(spec.key)] = stored
	else:
		spell.effects[int(spec.index)][str(spec.key)] = stored

func _write_growth_override(spell: Dictionary, level: int, spec: Dictionary, value: Variant) -> void:
	if level <= 1:
		_write_growth_base(spell, spec, value)
		return
	if not spell.get("growth") is Array:
		spell.growth = []
	while spell.growth.size() < level:
		spell.growth.append({})
	if not spell.growth[level - 1] is Dictionary:
		spell.growth[level - 1] = {}
	var stored: Variant = int(round(float(value))) if str(spec.type) == "int" else value
	if int(spec.index) < 0:
		spell.growth[level - 1][str(spec.key)] = stored
		return
	if not spell.growth[level - 1].get("effects") is Dictionary:
		spell.growth[level - 1].effects = {}
	var slot := str(int(spec.index))
	if not spell.growth[level - 1].effects.get(slot) is Dictionary:
		spell.growth[level - 1].effects[slot] = {}
	spell.growth[level - 1].effects[slot][str(spec.key)] = stored

func _clear_growth_key(spell: Dictionary, spec: Dictionary) -> void:
	if not spell.get("growth") is Array:
		return
	for slot in spell.growth:
		if not slot is Dictionary:
			continue
		if int(spec.index) < 0:
			slot.erase(str(spec.key))
		elif slot.get("effects") is Dictionary and slot.effects.get(str(int(spec.index))) is Dictionary:
			slot.effects[str(int(spec.index))].erase(str(spec.key))

func _swap_growth_index(spell: Dictionary, left: int, right: int) -> void:
	if not spell.get("growth") is Array:
		return
	for slot in spell.growth:
		if not slot is Dictionary or not slot.get("effects") is Dictionary:
			continue
		var effects_map: Dictionary = slot.effects
		var key_left := str(left)
		var key_right := str(right)
		var has_left := effects_map.has(key_left)
		var has_right := effects_map.has(key_right)
		var value_left: Variant = effects_map.get(key_left)
		var value_right: Variant = effects_map.get(key_right)
		effects_map.erase(key_left)
		effects_map.erase(key_right)
		if has_left:
			effects_map[key_right] = value_left
		if has_right:
			effects_map[key_left] = value_right

func _shift_growth_after_remove(spell: Dictionary, index: int) -> void:
	if not spell.get("growth") is Array:
		return
	for slot in spell.growth:
		if not slot is Dictionary or not slot.get("effects") is Dictionary:
			continue
		var next := {}
		for key in slot.effects:
			var current := int(str(key))
			if current == index:
				continue
			next[str(current - 1 if current > index else current)] = slot.effects[key]
		slot.effects = next

func _set_trial_number(value: float, level_row: Dictionary, key: String) -> void:
	level_row[key] = int(value) if level_row.get(key) is int else value
	_mark()

func _set_trial_text(value: String, level_row: Dictionary, key: String) -> void:
	level_row[key] = value
	_mark()

func _create_spell_row() -> void:
	var row := Database.blank_spell(spells, effects)
	row._draft = true
	spells.append(row)
	selected.spell = row.id
	view_level.spell = 1
	spell_effect_open = -1
	spell_auto[_token(row)] = true
	row.description = _spell_auto_text(row)
	_capture_spell_if_needed()
	_mark()
	_build_left()
	_build_center()
	_build_right()

func _copy_spell() -> void:
	var row := _row("spell")
	if row.is_empty():
		_notify("先选择一门法术")
		return
	var copy := Database.duplicate_row(row, spells)
	copy.name = str(row.get("name", "法术")) + "·副本"
	copy._draft = true
	copy._persisted = false
	copy._token = ""
	var keep_auto := bool(spell_auto.get(_token(row), false))
	spells.append(copy)
	selected.spell = copy.id
	if keep_auto:
		spell_auto[_token(copy)] = true
	else:
		_token(copy)
	spell_effect_open = -1
	view_level.spell = 1
	_capture_spell_if_needed()
	_mark()
	_build_left()
	_build_center()
	_build_right()

func _ask_delete_spell() -> void:
	var row := _row("spell")
	if row.is_empty():
		_notify("先选择一门法术")
		return
	var buckets := _ref_buckets(str(row.id))
	var summary := "NPC %d，妖兽 %d，其他 %d" % [buckets.npc.size(), buckets.beast.size(), buckets.other.size()]
	if not buckets.all.is_empty():
		var lines: PackedStringArray = []
		for user in buckets.all:
			lines.append("%s · %s · %s" % [user.kind, user.label, user.source])
		_notify("「%s」仍被引用，不能删除。\n%s\n%s" % [row.get("name", row.id), summary, "\n".join(lines)])
		return
	_confirm("删除「%s」？\n%s\n保存后才会写入文件。" % [row.get("name", row.id), summary], _delete_current)

func _confirm(text: String, action: Callable) -> void:
	if notice != null and notice.visible:
		notice.hide()
	for connection in confirm.confirmed.get_connections():
		confirm.confirmed.disconnect(connection.callable)
	confirm.dialog_text = text
	confirm.confirmed.connect(action, CONNECT_ONE_SHOT)
	confirm.popup_centered()

func _spell_name() -> String:
	var row := _row("spell")
	return str(row.get("name", row.get("id", "法术"))) if not row.is_empty() else "法术"

func _token(row: Dictionary) -> String:
	if str(row.get("_token", "")).is_empty():
		row["_token"] = "%s#%d" % [row.get("id", "spell"), randi()]
	return str(row["_token"])

func _capture_spell_if_needed() -> void:
	var row := _row("spell")
	if row.is_empty():
		return
	var key := _token(row)
	if not spell_baselines.has(key):
		spell_baselines[key] = row.duplicate(true)

func _spell_changed() -> bool:
	var row := _row("spell")
	if row.is_empty():
		return false
	if bool(row.get("_draft", false)):
		return true
	var base: Variant = spell_baselines.get(_token(row), null)
	if not base is Dictionary:
		return false
	return JSON.stringify(row) != JSON.stringify(base)

func _revert_spell() -> void:
	var row := _row("spell")
	if row.is_empty():
		return
	var key := _token(row)
	if not bool(row.get("_persisted", false)):
		for index in range(spells.size()):
			if spells[index] is Dictionary and str(spells[index].get("_token", "")) == key:
				spells.remove_at(index)
				break
		spell_baselines.erase(key)
		spell_auto.erase(key)
		if str(selected.spell) == str(row.get("id", "")):
			selected.spell = ""
	else:
		var base: Variant = spell_baselines.get(key, {})
		if base is Dictionary:
			row.clear()
			row.merge((base as Dictionary).duplicate(true), true)
	_release_spell_dirty()

func _release_spell_dirty() -> void:
	for row in spells:
		if not row is Dictionary:
			continue
		if bool(row.get("_draft", false)):
			return
		var base: Variant = spell_baselines.get(str(row.get("_token", "")), null)
		if base is Dictionary and JSON.stringify(row) != JSON.stringify(base):
			return
	dirty_files.erase("spells")
	dirty_files.erase("spell_trials")
	dirty_files.erase("spell_trials_stage2")
	dirty_files.erase("spell_trials_stage3")
	dirty = not dirty_files.is_empty()
	if not dirty:
		%Status.text = "已丢弃这门法术的未保存修改"

func _rename_spell(row: Dictionary, value: String) -> void:
	if bool(row.get("_persisted", false)):
		return
	var next := value.strip_edges()
	if next == str(row.get("id", "")):
		return
	row.id = next
	selected.spell = next
	%CenterMeta.text = "法术 ID：" + next
	%CenterMeta.tooltip_text = next
	_mark()

func _qi_realms() -> Array:
	var names: Array = ["不限"]
	var tiers: Variant = catalog.get("realm_tiers", [])
	if tiers is Array:
		for tier in tiers:
			if tier is Dictionary:
				var realm_name := str(tier.get("qi", ""))
				if not realm_name.is_empty() and realm_name not in names:
					names.append(realm_name)
	if names.size() == 1:
		for realm_name in REALMS:
			if realm_name != "全部" and realm_name not in names:
				names.append(realm_name)
	return names

func _spell_element_names(row: Dictionary) -> Array:
	var found: Array = []
	if row.get("elements") is Array:
		for item in row.elements:
			var label := _element_label(item)
			if label not in found:
				found.append(label)
	var single := _element_label(row.get("element", ""))
	if single not in found:
		found.append(single)
	return found

func _spell_element_match(row: Dictionary) -> bool:
	if elements.is_empty():
		return true
	for element_name in _spell_element_names(row):
		if element_name in elements:
			return true
	return false

func _spell_kinds(row: Dictionary) -> Array:
	var kinds: Array = []
	if row.get("effects") is Array:
		for effect in row.effects:
			if not effect is Dictionary:
				continue
			var definition := Registry.find(effects, str(effect.get("effect_id", "")))
			var category := str(definition.get("category", ""))
			if category.is_empty():
				category = {"damage": "伤害", "heal": "恢复", "shield": "防护", "mana": "恢复", "cleanse": "防护", "status": "控制"}.get(str(effect.get("type", "")), "")
			if not category.is_empty() and category not in kinds:
				kinds.append(category)
	if kinds.is_empty():
		kinds.append(_legacy_type(row))
	var stored := str(row.get("spell_type", ""))
	if not stored.is_empty() and stored != "混合" and stored not in kinds:
		kinds.append(stored)
	return kinds

func _spell_type_match(row: Dictionary) -> bool:
	if spell_type.is_empty():
		return true
	var kinds := _spell_kinds(row)
	if spell_type == "混合":
		return kinds.size() > 1 or str(row.get("spell_type", "")) == "混合"
	return spell_type in kinds or str(row.get("spell_type", "")) == spell_type

func _spell_level_cap(row: Dictionary) -> int:
	if row.has("levels") and row.levels is Array and not row.levels.is_empty():
		return row.levels.size()
	return clampi(int(row.get("max_level", 3)), 1, 3)

func _legacy_has_payload(row: Dictionary) -> bool:
	return float(row.get("multiplier", 0)) > 0.0 or float(row.get("heal", 0)) > 0.0 or float(row.get("guard", 0)) > 0.0 or not str(row.get("status", "")).is_empty()

func _spell_effect_lines(row: Dictionary, level: int) -> Array:
	var runtime: Dictionary = Database._apply_growth(row, level) if row.has("effects") else row
	var lines: Array = []
	if runtime.has("effects") and not runtime.has("levels"):
		for effect in runtime.effects:
			if effect is Dictionary:
				var definition := Registry.find(effects, str(effect.get("effect_id", "")))
				lines.append({"kind": str(effect.get("type", "")), "text": Registry.describe(effect, definition, catalog.get("spell_growth", {}))})
		return lines
	for entry in Spells.effect_lines(runtime, level, catalog.get("spell_growth", {})):
		lines.append({"kind": str(entry[0]), "text": str(entry[1])})
	return lines

func _spell_auto_text(row: Dictionary) -> String:
	var level := clampi(int(view_level.spell), 1, _spell_level_cap(row))
	var element := _element_short(row.get("element", ""))
	var lines: PackedStringArray = ["%s。%s，目标%s，消耗灵力 %d，冷却 %d 回合。" % [str(row.get("name", "法术")), _element_phrase(element), _target_label(str(row.get("target", "enemy"))), Database._spell_mp(row, level), Database._spell_cd(row, level)]]
	for entry in _spell_effect_lines(row, level):
		lines.append(str(entry.text) + "。")
	return "\n".join(lines)

func _refresh_auto_text(force: bool = false) -> void:
	if _ui_lock:
		return
	var row := _row("spell")
	if row.is_empty() or (not force and not bool(spell_auto.get(_token(row), false))):
		return
	var text := _spell_auto_text(row)
	if str(row.get("description", "")) == text and (not is_instance_valid(spell_desc) or spell_desc.text == text):
		return
	_ui_lock = true
	row.description = text
	if is_instance_valid(spell_desc):
		spell_desc.text = text
	_ui_lock = false

func _regenerate_description() -> void:
	var row := _row("spell")
	if row.is_empty() or not bool(spell_auto.get(_token(row), false)):
		return
	_refresh_auto_text(true)
	_mark()

func _target_field(row: Dictionary) -> Control:
	var labels: Array = TARGET_LABELS.duplicate()
	var values: Array = TARGET_VALUES.duplicate()
	var enabled: Array = [true, true, false, false, false]
	var current := str(row.get("target", "enemy"))
	if current not in values:
		labels.append(_target_label(current))
		values.append(current)
		enabled.append(false)
	var button := OptionButton.new()
	button.custom_minimum_size.y = 30
	for index in labels.size():
		button.add_item(str(labels[index]))
		button.set_item_disabled(index, not bool(enabled[index]))
	button.selected = maxi(0, values.find(current))
	button.item_selected.connect(func(index: int) -> void:
		if not bool(enabled[index]):
			return
		row.target = str(values[index])
		_mark())
	var box := VBoxContainer.new()
	box.add_child(_muted("施法目标"))
	box.add_child(button)
	return _track(box, "target")

func _learn_text(row: Dictionary) -> String:
	var names: PackedStringArray = []
	for user in references.get(str(row.get("id", "")), []):
		if str(user.get("kind", "")) == "物品":
			names.append(str(user.get("label", user.get("source", ""))))
	if names.is_empty():
		return "未绑定物品。学习仍由物品或存档授予。"
	return "物品：" + "、".join(names)

func _status_catalog() -> Dictionary:
	var table: Variant = catalog.get("spell_growth", {}).get("statuses", {})
	return table if table is Dictionary else {}

func _status_choices() -> Dictionary:
	var labels: Array = []
	var values: Array = []
	var table := _status_catalog()
	for id in table:
		labels.append(str(table[id].get("name", id)))
		values.append(str(id))
	return {"labels": labels, "values": values}

func _status_label(id: String) -> String:
	if id.is_empty():
		return "无"
	var table := _status_catalog()
	return str(table[id].get("name", id)) if table.has(id) else id

func _add_spell_references(id: String) -> void:
	var buckets := _ref_buckets(id)
	%RightBody.add_child(_section("引用情况"))
	%RightBody.add_child(_label("NPC：%d" % buckets.npc.size(), EDITOR_FONT_SIZE, TEXT))
	%RightBody.add_child(_label("妖兽：%d" % buckets.beast.size(), EDITOR_FONT_SIZE, TEXT))
	%RightBody.add_child(_label("其他引用：%d" % buckets.other.size(), EDITOR_FONT_SIZE, TEXT))
	%RightBody.add_child(_action("查看引用", _toggle_spell_refs))
	if not spell_refs_open:
		return
	if buckets.all.is_empty():
		%RightBody.add_child(_muted("已检查物品学习、原型 NPC、NPC 覆盖、妖兽技能和当前快照，没有引用。历史存档未逐个扫描。"))
	for user in buckets.all:
		%RightBody.add_child(_label("%s · %s · %s" % [user.kind, user.label, user.source], EDITOR_FONT_SIZE, MUTED))

func _toggle_spell_refs() -> void:
	spell_refs_open = not spell_refs_open
	_build_right()

func _ref_buckets(id: String) -> Dictionary:
	var users: Array = references.get(id, [])
	var npc: Array = []
	var beast: Array = []
	var other: Array = []
	for user in users:
		var kind := str(user.get("kind", ""))
		if kind in ["原型NPC", "NPC覆盖"]:
			npc.append(user)
		elif kind.contains("妖兽"):
			beast.append(user)
		else:
			other.append(user)
	return {"npc": npc, "beast": beast, "other": other, "all": users}

func _spell_issues(row: Dictionary) -> PackedStringArray:
	var mine := PackedStringArray()
	var id := str(row.get("id", ""))
	for record in Diagnostics.inspect(_bundle(), catalog.get("spell_growth", {})):
		if record.severity != "error": continue
		var issue: String = record.message
		if not id.is_empty() and id in issue:
			mine.append(issue)
		elif id.is_empty() and issue.contains("法术"):
			mine.append(issue)
	return mine

func _focus_issue(text: String) -> void:
	var node_pattern := RegEx.new()
	node_pattern.compile("effects\\[(\\d+)\\]")
	var node_match := node_pattern.search(text)
	if node_match != null:
		spell_effect_open = int(node_match.get_string(1))
		focus_field = "effects"
		var row := _row("spell")
		if spell_effect_open < row.get("effects", []).size():
			var definition := Registry.find(effects, str(row.effects[spell_effect_open].get("effect_id", "")))
			for parameter in definition.get("parameters", []):
				if text.contains(str(parameter.get("name", parameter.id))):
					focus_field = "effect_%d_%s" % [spell_effect_open, parameter.id]
		_build_center()
		_scroll_to_field.call_deferred(focus_field)
		return
	var field := "effects"
	if text.contains("ID"):
		field = "id"
	elif text.contains("名称"):
		field = "name"
	elif text.contains("五行"):
		field = "element"
	elif text.contains("消耗") or text.contains("灵力"):
		field = "mp"
	elif text.contains("冷却"):
		field = "cd"
	elif text.contains("目标"):
		field = "target"
	elif text.contains("策略"):
		field = "ai"
		spell_ai_open = true
	elif text.contains("等级") or text.contains("成长"):
		field = "growth"
	elif text.contains("状态"):
		field = "status"
	focus_field = field
	if field == "effects":
		spell_effect_open = 0
	_build_center()
	_scroll_to_field.call_deferred(field)

func _scroll_to_field(field: String) -> void:
	var node := _find_field(%CenterBody, field)
	if node != null:
		%CenterScroll.ensure_control_visible(node)

func _find_field(node: Node, field: String) -> Control:
	if node is Control and str(node.get_meta("field", "")) == field:
		return node
	for child in node.get_children():
		var found := _find_field(child, field)
		if found != null:
			return found
	return null

func _test_current_spell() -> void:
	var row := _row("spell")
	if row.is_empty():
		_notify("先选择一门法术")
		return
	_ensure_battle()
	battle.kind = "spell"
	battle.id = row.id
	battle.level = clampi(int(view_level.spell), 1, _spell_level_cap(row))
	battle_result = {}
	%Status.text = "战斗测试使用当前草稿，不会写入正式数据。"
	set_page("battle")

func _validate_current_spell() -> void:
	_on_validate()

func _element_short(value: Variant) -> String:
	var label := _element_label(value)
	return "无" if label == "无属性" else label

func _element_phrase(short: String) -> String:
	return "无属性" if short == "无" or short.is_empty() else short + "系"

func _element_color_of(value: String) -> Color:
	var hex: String = str({"金": "B18A31", "木": "24854C", "水": "2878BD", "火": "C45132", "土": "97722C", "风": "268B80", "雷": "9251BB", "冰": "4397BA"}.get(_element_short(value), "7A8790"))
	return Color(hex).lerp(Color.WHITE, 0.42)

func _rarity_color(value: String) -> Color:
	if value == "黄阶":
		return GOLD
	return MUTED if value.is_empty() else Color("D5E4DC")

func _target_label(value: String) -> String:
	match value:
		"self":
			return "自身"
		"enemy":
			return "敌方单体"
		"ally":
			return "友方单体"
		"all":
			return "敌方群体"
		"allies":
			return "友方群体"
		"chain":
			return "连锁"
		_:
			return "敌方单体" if value.is_empty() else value

func _line_color(kind: String) -> Color:
	match kind:
		"damage":
			return DAMAGE
		"heal":
			return HEAL
		"guard":
			return Color("8EC4F0")
		"control":
			return GOLD
		_:
			return TEXT

func _colored_wrap(text: String, color: Color) -> Label:
	var label := _label(text, EDITOR_FONT_SIZE, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func _section_bar(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label(title, EDITOR_FONT_SIZE, TEXT))
	return row

func _chip(text: String, active: bool, callback: Callable) -> Button:
	var button := _action(text, callback)
	_style_button(button, active)
	button.custom_minimum_size = Vector2(32 if text.length() == 1 else 0, 26)
	button.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
	return button

func _mini(text: String, callback: Callable, disabled := false) -> Button:
	var button := _action(text, callback)
	button.custom_minimum_size = Vector2(28, 26)
	button.disabled = disabled
	button.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
	return button

func _tune(node: Control) -> Control:
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for child in node.get_children():
		if child is OptionButton:
			child.custom_minimum_size.y = 28
	return node

func _fill(node: Control) -> Control:
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func _track(node: Control, field: String) -> Control:
	if field.is_empty():
		return node
	node.set_meta("field", field)
	if focus_field == field:
		node.modulate = Color(1.15, 1.05, 0.85)
	return node

func _lock_spin(node: Control) -> void:
	for child in node.get_children():
		if child is SpinBox:
			child.editable = false

func _chrome_button(button: Button) -> void:
	button.custom_minimum_size.y = 30
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed"]:
		var style := button.get_theme_stylebox(state)
		if style == null:
			continue
		var box := style.duplicate()
		if box is StyleBoxFlat:
			box.content_margin_left = 12
			box.content_margin_right = 12
			box.content_margin_top = 2
			box.content_margin_bottom = 2
			button.add_theme_stylebox_override(state, box)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _box(color: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	return box

func _style_button(button: Button, active: bool, fill: Color = Color(0, 0, 0, 0)) -> void:
	var base := fill if fill.a > 0.0 else (PRIMARY if active else FIELD)
	button.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_stylebox_override("normal", _box(base, 6, 4))
	button.add_theme_stylebox_override("hover", _box(SELECTED, 6, 4))
	button.add_theme_stylebox_override("pressed", _box(base, 6, 4))
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

func _style_input(control: Control) -> void:
	control.add_theme_font_size_override("font_size", EDITOR_FONT_SIZE)
	control.add_theme_color_override("font_color", TEXT)
	if control is LineEdit:
		var field := _box(FIELD, 6, 4)
		control.add_theme_stylebox_override("normal", field)
		control.add_theme_stylebox_override("read_only", field)
		control.add_theme_stylebox_override("focus", field)

func _action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(button, false)
	button.pressed.connect(callback)
	return button

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _muted(text: String) -> Label:
	var label := _label(text, EDITOR_FONT_SIZE, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func _wrapped(text: String) -> Label:
	var label := _label(text, EDITOR_FONT_SIZE, TEXT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func _section(text: String) -> Label:
	return _label(text, EDITOR_FONT_SIZE, TEXT)

func _read_only_text(title: String, text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_muted(title))
	box.add_child(_wrapped(text))
	return box

func _text_field(title: String, value: String, editable: bool, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_muted(title))
	var edit := LineEdit.new()
	edit.text = value
	edit.editable = editable
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(edit)
	edit.text_changed.connect(callback)
	box.add_child(edit)
	return box

func _spin_field(title: String, value: float, minimum: float, maximum: float, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_muted(title))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1 if maximum >= 20 else 0.01
	spin.value = clampf(value, minimum, maximum)
	spin.custom_minimum_size.y = 30
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(callback)
	box.add_child(spin)
	return box

func _choice(title: String, options: Array, current: String, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_child(_muted(title))
	var button := OptionButton.new()
	var selected_index := 0
	for index in options.size():
		button.add_item(str(options[index]))
		if str(options[index]) == current:
			selected_index = index
	button.custom_minimum_size.y = 30
	button.selected = selected_index
	button.item_selected.connect(func(index: int) -> void: callback.call(str(options[index])))
	box.add_child(button)
	return box
