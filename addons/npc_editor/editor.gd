@tool
extends PanelContainer

const Model := preload("res://core/npc_definitions.gd")
const Catalog := preload("res://core/content_catalog.gd")
const Picker := preload("res://addons/npc_editor/resource_picker.gd")
const GenerationPage := preload("res://addons/npc_editor/generation_page.gd")
const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const Saves := preload("res://core/save_service.gd")
const RANKS := Model.Character.NPC_RANKS
const TABS := ["基础","修炼","气运","功法","法术","装备","法宝","物品","关系","行为","宗门"]
const STAT_NAMES := {"hp":"生命","mp":"灵力","blood":"气血","attack":"攻击","defense":"防御","speed":"速度","critical":"暴击率","critical_damage":"暴伤","dodge":"闪避","fire":"火伤","spell_bps":"法术增幅"}

var data: Dictionary
var saved: Dictionary
var draft: Dictionary
var clean: Dictionary
var baseline: Dictionary
var pages: Array[VBoxContainer] = []
var tabs: TabContainer
var search: LineEdit
var roster_list: ItemList
var rank_filter: OptionButton
var preview: VBoxContainer
var status: Label
var fortune_feedback: Dictionary = {}
var picker: Picker
var pending: Callable
var ready_to_edit := false
var selected_save := ""
var queued_drafts := {}
var save_roster := {}
var selected_save_checksum := ""
var generation: GenerationPage
var batch_open := false

func _ready() -> void:
	if Engine.is_editor_hint() and get_parent() != EditorInterface.get_editor_main_screen():
		return
	theme = _theme()
	resized.connect(_fit_controls)
	_fit_controls()
	var left := $Frame/Columns/Roster
	search = left.get_node("Search")
	search.text_changed.connect(func(_text): _refresh_roster())
	rank_filter = left.get_node("RankFilter")
	rank_filter.item_selected.connect(func(_index): _refresh_roster())
	roster_list = left.get_node("Characters")
	roster_list.item_selected.connect(_select)
	left.get_node("New").pressed.connect(_new)
	left.get_node("Random").pressed.connect(_random_npc)
	left.get_node("Copy").pressed.connect(_copy)
	tabs = $Frame/Columns/Tabs
	for title_text in TABS:
		var scroll := ScrollContainer.new()
		scroll.name = title_text
		tabs.add_child(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		pages.append(page)
	preview = $Frame/Columns/PreviewScroll/Preview
	$Frame/Footer/Save.pressed.connect(save)
	$Frame/Footer/Revert.pressed.connect(_revert)
	$Frame/Footer/Reload.pressed.connect(_reload)
	$Frame/Header/SelectSave.pressed.connect(_choose_target_save)
	$Frame/Header/SaveChanges.pressed.connect(_apply_to_selected_save)
	$Frame/Header/Batch.pressed.connect(toggle_batch)
	generation = $Frame/Generation
	generation.committed.connect(_on_batch_committed)
	status = $Frame/Footer/Status
	picker = Picker.new()
	picker.theme = theme
	add_child(picker)
	picker.picked.connect(func(id): pending.call(id))
	_reload()

func _fit_controls() -> void:
	var font_size := clampi(roundi(size.x * 36.0 / 1920.0), 18, 36)
	if batch_open:
		font_size = 18
	if theme.default_font_size != font_size:
		theme.default_font_size = font_size
	$Frame/Header/Heading.add_theme_font_size_override("font_size", 32 if batch_open else font_size * 4 / 3)

func _theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18
	result.set_color("font_placeholder_color", "LineEdit", Color("#50746D"))
	var inks := Color("#214B44")
	var border := Color("#2F7469")
	for kind in ["Button","OptionButton","LineEdit","Label","ItemList","CheckButton","TabContainer","TextEdit"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_selected_color","font_unselected_color"]:
			result.set_color(key, kind, inks)
	for entry in [
		["PanelContainer","panel","#DCECE7"], ["TabContainer","panel","#F1F7F3"],
		["ItemList","panel","#F1F7F3"], ["ItemList","selected","#B7D8CC"],
		["ItemList","selected_focus","#B7D8CC"], ["LineEdit","normal","#F1F7F3"],
		["TextEdit","normal","#F1F7F3"], ["PopupPanel","panel","#E4F0E9"],
		["TabContainer","tab_selected","#B7D8CC"], ["TabContainer","tab_unselected","#E4F0E9"]
	]:
		result.set_stylebox(entry[1], entry[0], _style(Color(entry[2]), border))
	for kind in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","focus"]:
			result.set_stylebox(state, kind, _style(Color("#E4F0E9" if state == "normal" else "#B7D8CC"), border))
	return result

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		box.set_content_margin(side, 6)
	return box

func toggle_batch() -> void:
	set_batch_open(not batch_open)

func set_batch_open(open: bool) -> void:
	if open == batch_open:
		if open and is_instance_valid(generation):
			generation.overrides = saved
		return
	if open and not _guard():
		return
	batch_open = open
	var header: HBoxContainer = $Frame/Header
	var heading: Label = $Frame/Header/Heading
	var save_status: Label = $Frame/Header/SaveStatus
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL if open else Control.SIZE_FILL
	save_status.size_flags_horizontal = Control.SIZE_FILL if open else Control.SIZE_EXPAND_FILL
	save_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if open else HORIZONTAL_ALIGNMENT_LEFT
	save_status.custom_minimum_size.x = 185 if open else 0
	header.move_child($Frame/Header/Batch, 4 if open else 1)
	header.move_child(save_status, 1 if open else 4)
	for button in [$Frame/Header/Batch, $Frame/Header/SelectSave, $Frame/Header/SaveChanges]:
		button.custom_minimum_size.y = 48 if open else 0
	$Frame/Columns.visible = not open
	$Frame/Footer.visible = not open
	generation.visible = open
	$Frame/Header/Batch.text = "返回人物" if open else "批量生成"
	$Frame/Header/Heading.text = "仙途  /  NPC 批量生成" if open else "仙途  /  NPC 初始定义"
	_fit_controls()
	if open:
		if generation.form == null:
			generation.setup(data, saved)
		else:
			generation.overrides = saved

func _on_batch_committed(rows: Dictionary, ids: Array) -> void:
	saved = rows
	data.npc_overrides = rows
	set_batch_open(false)
	if not ids.is_empty() and saved.has(ids[0]):
		_open(saved[ids[0]])
	else:
		_refresh_roster()

func is_dirty() -> bool:
	return not draft.is_empty() and draft != clean

func has_unqueued_changes() -> bool:
	return is_dirty() and queued_drafts.get(draft.id) != draft

func _guard() -> bool:
	if not selected_save.is_empty():
		_stage_current_draft()
		return true
	if has_unqueued_changes():
		status.text = "当前有未处理修改。请加入批量修改、保存定义或撤销后再切换。"
		_refresh_roster()
		return false
	return true

func _reload() -> void:
	if not selected_save.is_empty():
		_select_target_save(selected_save)
		return
	if not _guard():
		return
	var catalog := Catalog.new()
	if not catalog.load_all(false):
		status.text = catalog.error
		return
	var result := Model.load_definitions(catalog.tables)
	if not result.error.is_empty():
		status.text = result.error
		return
	data = catalog.tables
	saved = result.rows
	ready_to_edit = true
	var roster := Model.roster(data, saved)
	_refresh_rank_filter()
	var id: String = draft.get("id", "")
	if roster.has(id):
		_open(roster[id])
	elif queued_drafts.has(id):
		_open(queued_drafts[id])
	elif not roster.is_empty():
		_open(roster.values()[0])
	_refresh_roster()
	status.text = "已从磁盘载入初始定义。"

func _visible_roster() -> Dictionary:
	return Model.roster(data,saved) if selected_save.is_empty() else save_roster.duplicate()

func _refresh_rank_filter() -> void:
	var previous := rank_filter.get_item_text(rank_filter.selected) if rank_filter.selected >= 0 else ""
	rank_filter.clear()
	rank_filter.add_item("全部评级")
	rank_filter.select(0)
	for rank in RANKS:
		rank_filter.add_item(rank)
		if rank == previous:
			rank_filter.select(rank_filter.item_count - 1)

func _personalities() -> Dictionary:
	var options := {"":"未设定"}
	for npc in Model.roster(data, saved).values():
		var personality: String = npc.get("profile", {}).get("personality", "")
		if not personality.is_empty():
			options[personality] = personality
	return options

func _refresh_roster() -> void:
	roster_list.clear()
	if not ready_to_edit:
		return
	var roster := _visible_roster()
	roster.merge(queued_drafts,true)
	var ids: Array = saved.keys() if selected_save.is_empty() else []
	for id in roster:
		if not ids.has(id):
			ids.append(id)
	if not draft.is_empty():
		roster[draft.id] = draft
		if not ids.has(draft.id):
			ids.push_front(draft.id)
	var needle := search.text.strip_edges().to_lower()
	var places := Model.Locations.names(data)
	for id in ids:
		var name_text: String = roster[id].name if not roster[id].name.is_empty() else "未命名 NPC"
		var rank := Model.Character.npc_rank(roster[id].get("profile", {}))
		if rank_filter.selected > 0 and rank != rank_filter.get_item_text(rank_filter.selected):
			continue
		if not needle.is_empty() and not (name_text + " " + id).to_lower().contains(needle):
			continue
		var dirty: bool = queued_drafts.has(id) or (id == draft.get("id") and is_dirty())
		var index := roster_list.add_item(name_text + (" *" if dirty else ""))
		roster_list.set_item_custom_fg_color(index, Color("#214B44"))
		roster_list.set_item_metadata(index, id)
		var location_id: String = roster[id].get("location", "")
		roster_list.set_item_tooltip(index, "%s · %s\n初始所在地：%s\n%s%s" % [name_text, rank, places.get(location_id,location_id), id, "\n未保存" if dirty else ""])
		if id == draft.get("id"):
			roster_list.select(index)
	_refresh_save_header()

func _select(index: int) -> void:
	var id: String = roster_list.get_item_metadata(index)
	if id == draft.get("id"):
		return
	if _guard():
		var roster := _visible_roster()
		_open(roster.get(id,queued_drafts.get(id,{})))

func focus_npc(id: String) -> void:
	if not ready_to_edit:
		return
	for index in roster_list.item_count:
		if str(roster_list.get_item_metadata(index)) == id:
			roster_list.select(index)
			_select(index)
			return

func _new() -> void:
	if ready_to_edit and _guard():
		var id := Model.uid("npc_")
		_open({"id":id,"name":"","location":Model.Locations.names(data).keys()[0],"realm":0}, true)

func _random_npc() -> void:
	if not ready_to_edit or not _guard():
		return
	var id := Model.uid("npc_")
	var locations: Array = []
	for npc in data.prototype.npcs:
		if npc.location not in locations:
			locations.append(npc.location)
	var realm_id: String = data.realms.keys().pick_random()
	var personalities := _personalities()
	personalities.erase("")
	var character_profile := {
		"gender": ["男", "女"].pick_random(),
		"root": data.rules.roots.pick_random(),
		"rank": Array(RANKS).slice(0, 5).pick_random(),
		"personality": personalities.keys().pick_random() if not personalities.is_empty() else "",
		"base": _starting_base(),
	}
	_open({"id":id, "name":"随机人物 " + id.right(4), "realm":int(realm_id.trim_prefix("qi_")),
		"location":locations.pick_random(), "profile":character_profile}, true)
	status.text = "随机草稿 · 可调整后保存"

func _copy() -> void:
	if draft.is_empty() or not _guard():
		return
	var copy := draft.duplicate(true)
	copy.id = Model.uid("npc_")
	copy.name += "（副本）"
	_open(copy, true)

func _open(definition: Dictionary, unsaved: bool = false) -> void:
	draft = Model.draft(definition, data)
	clean = {} if unsaved else draft.duplicate(true)
	if not unsaved and queued_drafts.has(draft.id):
		draft = queued_drafts[draft.id].duplicate(true)
	baseline = _stats()
	if unsaved:
		search.text = ""
		rank_filter.select(0)
		tabs.current_tab = 0
	status.text = draft.id
	_rebuild()
	_refresh_roster()

func _revert() -> void:
	if not selected_save.is_empty():
		queued_drafts.erase(draft.id)
		if save_roster.has(draft.id):
			_open(save_roster[draft.id])
		else:
			_open(save_roster.values()[0])
		return
	if not clean.is_empty():
		_open(clean)
	elif ready_to_edit:
		draft = {}
		_reload()

func save() -> void:
	if draft.is_empty():
		return
	var current := Model.load_definitions(data)
	if not current.error.is_empty() or current.get("rows", {}) != saved:
		status.text = "磁盘定义发生变化或无效。请保留所需修改后重新载入。"
		return
	var next := saved.duplicate(true)
	var candidate := draft.duplicate(true)
	var automatic_profile: Dictionary = candidate.profile.duplicate(true)
	automatic_profile.stat_overrides = {}
	var automatic := Model.Character.new().npc_stats(Model.initial(candidate, data), automatic_profile, data)
	candidate.profile.stat_originals = {}
	for key in candidate.profile.stat_overrides:
		candidate.profile.stat_originals[key] = automatic.get(key, 0)
	next[draft.id] = candidate
	var error := Model.validate(draft, data, Model.roster(data, next))
	if error.is_empty():
		error = Model.write_definitions(next, data)
	if not error.is_empty():
		status.text = error
		return
	saved = Model.load_definitions(data).rows
	draft.profile.stat_originals = candidate.profile.stat_originals
	clean = draft.duplicate(true)
	baseline = _stats()
	_refresh_roster()
	_refresh_preview()
	status.text = "已保存 · 新游戏读取此定义，当前档可用 F1 同步气运。"

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _label(parent: Node, value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, title_text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title_text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _row(parent: Node, title_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, title_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row

func _set_field(value: Variant, values: Dictionary, key: String) -> void:
	values[key] = value
	status.text = "未保存 · " + draft.id
	_refresh_roster()
	_refresh_preview()

func _text(parent: Node, title_text: String, values: Dictionary, key: String) -> void:
	var row := _row(parent, title_text)
	var field := LineEdit.new()
	field.custom_minimum_size.x = 250
	field.text = str(values.get(key, ""))
	field.text_changed.connect(_set_field.bind(values, key))
	row.add_child(field)

func _number(parent: Node, title_text: String, values: Dictionary, key: String, low: int, high: int, fallback: int = 0) -> void:
	var row := _row(parent, title_text)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = values.get(key, fallback)
	spin.value_changed.connect(_set_field.bind(values, key))
	row.add_child(spin)

func _level_stepper(parent: Node, title_text: String, values: Dictionary, key: String, low: int, high: int) -> void:
	var row := _row(parent, title_text)
	var decrease := Button.new()
	decrease.text = "−"
	decrease.custom_minimum_size = Vector2(56, 48)
	row.add_child(decrease)
	var number := _label(row, "")
	number.custom_minimum_size.x = 56
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var increase := Button.new()
	increase.text = "+"
	increase.custom_minimum_size = decrease.custom_minimum_size
	row.add_child(increase)
	decrease.tooltip_text = "降低" + title_text
	increase.tooltip_text = "提高" + title_text
	var render := func():
		var level := int(values.get(key, low))
		number.text = str(level)
		decrease.disabled = level <= low
		increase.disabled = level >= high
	var step := func(delta: int):
		var current := int(values.get(key, low))
		var next := clampi(current + delta, low, high)
		if current != next:
			_set_field(next, values, key)
			render.call()
	decrease.pressed.connect(step.bind(-1))
	increase.pressed.connect(step.bind(1))
	render.call()

func _asset(parent: Node, title_text: String, profile: Dictionary, key: String) -> void:
	var path: String = profile.get(key, "")
	var row := _row(parent, title_text + (" · " + path.get_file() if not path.is_empty() else ""))
	_button(row, "选择图片", _pick_image.bind(profile, key))
	if not path.is_empty():
		_button(row, "清除", _erase.bind(key, profile))

func _pick_image(profile: Dictionary, key: String) -> void:
	var dialog := FileDialog.new()
	dialog.title = "选择项目图片"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.svg; 图片"])
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.file_selected.connect(func(path: String):
		dialog.queue_free()
		if ResourceLoader.exists(path, "Texture2D"):
			profile[key] = path
			_changed()
		else:
			status.text = "图片尚未导入 Godot，请选择已导入的图片。"
	)
	dialog.popup_centered_ratio(0.75)

func _options(parent: Node, title_text: String, values: Dictionary, key: String, options: Dictionary) -> void:
	var row := _row(parent, title_text)
	var field := OptionButton.new()
	row.add_child(field)
	for id in options:
		field.add_item(str(options[id]))
	field.select(options.keys().find(values.get(key)))
	field.item_selected.connect(func(index): _set_field(options.keys()[index], values, key))

func _choose(table: Dictionary, owned: Variant, action: Callable) -> void:
	pending = action
	picker.choose(table, owned)

func _changed() -> void:
	status.text = "未保存 · " + draft.id
	_rebuild()
	_refresh_roster()

func _rebuild() -> void:
	for page in pages:
		_clear(page)
	var profile: Dictionary = draft.profile
	var basic := pages[0]
	var existing_save_npc: Dictionary = save_roster.get(draft.id,{})
	var reading_existing := not existing_save_npc.is_empty()
	_label(basic, draft.id)
	_text(basic, "姓名", draft, "name")
	_text(basic, "身份", draft, "role")
	_options(basic, "存档所在地" if reading_existing else "初始所在地", draft, "location", Model.Locations.names(data))
	var gender_row := _row(basic, "性别")
	var gender_group := ButtonGroup.new()
	for gender in ["男", "女"]:
		var button := _button(gender_row, gender, _set_field.bind(gender, profile, "gender"))
		button.toggle_mode = true
		button.button_group = gender_group
		button.set_pressed_no_signal(profile.get("gender", "") in [gender, gender + "性"])
	var personalities := _personalities()
	var personality: String = profile.get("personality", "")
	if not personality.is_empty():
		personalities[personality] = personality
	_options(basic, "性格", profile, "personality", personalities)
	_asset(basic, "头像", profile, "portrait")
	_asset(basic, "立绘", profile, "illustration")
	_number(basic, "年龄", draft, "age", 0, 100000)
	_number(basic, "基础寿元", draft, "lifespan", 1, 100000, data.prototype.npc_lifespan)
	var growth := pages[1]
	var realms := {0:"凡人"}
	var body := {"凡体":"凡体"}
	for level in range(1, Cultivation.MAX_LEVEL + 1):
		realms[level] = Cultivation.realm_name(level, "qi", data)
		var body_name := Cultivation.realm_name(level, "body", data)
		body[body_name] = body_name
	# JSON stores whole numbers as floats.
	var realm_options := OptionButton.new()
	_row(growth, "法修境界").add_child(realm_options)
	for level in realms:
		realm_options.add_item(realms[level], level)
	realm_options.select(int(draft.realm))
	realm_options.item_selected.connect(func(index): _set_field(index, draft, "realm"))
	var realm_visibility := CheckBox.new()
	realm_visibility.text = "在游戏中公开法修境界"
	realm_visibility.button_pressed = draft.get("realm_known",false) == true
	realm_visibility.toggled.connect(_set_field.bind(draft,"realm_known"))
	growth.add_child(realm_visibility)
	_options(growth, "体修境界（档案）", profile, "body_realm", body)
	_number(growth, "修为", draft, "cultivation", 0, 100000000)
	var roots := {}
	for root in data.rules.roots:
		roots[root] = root
	if profile.has("root"):
		roots[profile.root] = profile.root
	_options(growth, "灵根", profile, "root", roots)
	var ranks := {}
	for rank in RANKS:
		ranks[rank] = rank
	_options(growth, "天资评级", profile, "rank", ranks)
	var foundation_names := ["气海","经脉","筋骨","体魄","识海","神魂"]
	var initialized := Model.initial(draft, data)
	for index in Model.FOUNDATION.size():
		var key: String = Model.FOUNDATION[index]
		_number(growth, foundation_names[index], profile.foundation, key, 0, 100000, initialized.attributes.get(key, data.progression.attribute_start))
	if profile.base.is_empty():
		var base_button := _button(growth, "启用战斗底值", _enable_base)
		base_button.tooltip_text = "使用现有出生配置作为起点"
	else:
		for key in Model.STATS:
			_number(growth, STAT_NAMES[key] + "底值", profile.base, key, 0, 100000)
			var check := CheckBox.new()
			check.text = "手动覆盖最终" + STAT_NAMES[key]
			check.button_pressed = profile.stat_overrides.has(key)
			check.toggled.connect(_toggle_override.bind(key))
			growth.add_child(check)
			if profile.stat_overrides.has(key):
				_number(growth, "覆盖值", profile.stat_overrides, key, 0, 1000000)
	_fortunes(pages[2])
	_skills(pages[3], "techniques", "technique_slots")
	_skills(pages[4], "spells", "spell_slots")
	_gear(pages[5])
	_artifacts(pages[6])
	_items(pages[7])
	_relations(pages[8])
	_text(pages[9], "交谈台词", draft, "greeting")
	_label(pages[9], "交谈台词由游戏交互读取。通用 NPC 目标、活动与战斗策略尚无运行入口。")
	var sects := {"":"无宗门"}
	for sect in data.prototype.sects:
		sects[sect.name] = sect.name
	_options(pages[10], "档案宗门", profile, "sect", sects)
	_label(pages[10], "此字段用于人物档案显示。现有宗门成员管理尚未覆盖 NPC。")
	_refresh_preview()

func _starting_base() -> Dictionary:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/starting_character.json"))
	var result := {}
	for key in Model.STATS:
		result[key] = base[key]
	return result

func _enable_base() -> void:
	draft.profile.base = _starting_base()
	_changed()

func _toggle_override(enabled: bool, key: String) -> void:
	if enabled:
		draft.profile.stat_overrides[key] = _stats().get(key, 0)
	else:
		draft.profile.stat_overrides.erase(key)
	_changed()

func _stats() -> Dictionary:
	return Model.Character.new().npc_stats(Model.initial(draft, data), draft.profile, data)

func _refresh_preview() -> void:
	_clear(preview)
	_label(preview, "人物预览")
	_label(preview, draft.name)
	var profile: Dictionary = draft.profile
	_label(preview, "%s · %s · %s" % [profile.get("rank","评级未设"), profile.get("root","灵根未设"), Cultivation.realm_name(int(draft.realm), "qi", data) if draft.realm else "凡人"])
	_label(preview, "游戏显示：%s" % Cultivation.npc_realm_label(draft,data))
	var path: String = profile.get("illustration", profile.get("portrait", ""))
	if not path.is_empty() and ResourceLoader.exists(path, "Texture2D"):
		var portrait := TextureRect.new()
		portrait.texture = load(path)
		portrait.custom_minimum_size.y = 140
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.add_child(portrait)
	var sources := {}
	var stats := Model.Character.new().npc_stats(Model.initial(draft, data), profile, data, sources)
	if stats.is_empty():
		_label(preview, "尚未设置战斗底值")
	for key in STAT_NAMES:
		if not stats.has(key):
			continue
		var delta: float = stats[key] - baseline.get(key, stats[key])
		var field := _label(preview, "%s  %s   (%+.3f)" % [STAT_NAMES[key], stats[key], delta])
		field.mouse_filter = Control.MOUSE_FILTER_PASS
		field.tooltip_text = JSON.stringify(sources.get(key, {}), "  ")
	var roster := Model.roster(data, saved)
	roster[draft.id] = draft
	var error := Model.validate(draft, data, roster)
	if not error.is_empty():
		_label(preview, error)

func _resource_name(table: Dictionary, id: String) -> String:
	return table.get(id, {}).get("name", id)

func _add_id(id: String, values: Array) -> void:
	if not values.has(id):
		values.append(id)
	_changed()

func _remove_id(id: String, values: Array) -> void:
	values.erase(id)
	_changed()

func _erase(id: String, values: Dictionary) -> void:
	values.erase(id)
	_changed()

func _toggle_slot(id: String, slots: Array, limit: int) -> void:
	if id in slots:
		slots.erase(id)
	elif slots.size() < limit:
		slots.append(id)
	else:
		status.text = "槽位已满"
		return
	_changed()

func _fortunes(parent: Node) -> void:
	fortune_feedback.clear()
	_button(parent, "从存档读取气运到草稿", _choose_fortune_save)
	_label(parent, "这里显示初始配置。可选择存档，把该人物当时持有的永久气运读入草稿。")
	var definitions: Dictionary = Model.Fortune.DEFINITIONS
	for kind in ["innate", "acquired"]:
		var innate: bool = kind == "innate"
		var title_text := "先天气运" if innate else "后天气运与负面气运"
		_label(parent, title_text)
		var choices := {}
		for id in definitions:
			if (definitions[id].kind == "innate") == innate:
				choices[id] = definitions[id]
		var browse := _button(parent, "浏览" + title_text, _choose.bind(choices, draft.fortune_ids, _add_fortune))
		browse.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for id in draft.fortune_ids:
			if choices.has(id):
				var row := HBoxContainer.new()
				parent.add_child(row)
				var label := _label(row, choices[id].name)
				label.autowrap_mode = TextServer.AUTOWRAP_OFF
				preload("res://ui/character/fortune_badge.gd").apply(label, choices[id])
				label.tooltip_text = "\n".join(Model.Fortune.describe(choices[id]))
				label.mouse_filter = Control.MOUSE_FILTER_PASS
				_button(row, "移除", _remove_id.bind(id, draft.fortune_ids))
		var legacy_entries: Array = draft.profile.innate_fortune if innate else draft.profile.acquired_fortune
		for legacy in legacy_entries:
			var row := _row(parent, "%s（原档案气运）" % legacy.name)
			_button(row, "移除", _remove_id.bind(legacy, legacy_entries))
		var rule := "NPC 可添加多项永久先天气运。同一气运和同一互斥组各只能添加一次。" if innate else "初始配置支持永久气运。同一气运和同一互斥组各只能添加一次。"
		_label(parent, rule)
		fortune_feedback[kind] = _label(parent, "")
		fortune_feedback[kind].add_theme_color_override("font_color", Color("#9E222B"))

func _choose_fortune_save() -> void:
	_choose_save("选择要读取气运的游戏存档", _read_saved_fortunes)

func _choose_target_save() -> void:
	_choose_save("选择要应用 NPC 草稿的游戏存档", _select_target_save)

func _select_target_save(path: String) -> void:
	if is_dirty() or not queued_drafts.is_empty():
		status.text = "还有未保存的修改，请先保存或撤销。"
		return
	var error := _read_target_save(path)
	if not error.is_empty():
		status.text = error
		return
	search.clear()
	rank_filter.select(0)
	_refresh_roster()

func _read_target_save(path: String) -> String:
	var saves := Saves.new()
	var payload := saves.read(path)
	if not saves.error.is_empty():
		return saves.error
	var state: Variant = payload.get("state")
	if not state is Dictionary or not state.get("npcs") is Dictionary or state.npcs.is_empty():
		return "该存档没有可读取的人物。"
	var profiles := Model.roster(data,{})
	var loaded := {}
	for id in state.npcs:
		var npc: Variant = state.npcs[id]
		if not npc is Dictionary or npc.get("id") != id or not npc.get("profile", {}) is Dictionary or not npc.get("fortunes", {}) is Dictionary:
			return "存档中的人物定义无效。"
		npc = npc.duplicate(true)
		var initial: Dictionary = profiles.get(id,{})
		if not npc.has("profile"):
			npc.profile = initial.get("profile", {}).duplicate(true)
		if not npc.has("greeting") and initial.has("greeting"):
			npc.greeting = initial.greeting
		var foundation: Dictionary = npc.profile.get("foundation", {}).duplicate()
		var attributes: Dictionary = npc.get("attributes", {})
		for key in Model.FOUNDATION:
			if attributes.has(key):
				foundation[key] = attributes[key]
		npc.profile.foundation = foundation
		npc.fortune_ids = _permanent_fortune_ids(npc.get("fortunes", {}))
		loaded[id] = npc
	selected_save = path
	selected_save_checksum = saves.source_checksum
	save_roster = loaded
	$Frame/Footer/Save.disabled = true
	_open(save_roster.get(draft.get("id",""),save_roster.values()[0]))
	status.text = "已读取存档中的 %d 名人物。" % save_roster.size()
	return ""

func _refresh_save_header() -> void:
	var header := $Frame/Header
	header.get_node("Heading").text = "仙途  /  NPC 初始定义" if selected_save.is_empty() else "仙途  /  NPC 存档"
	var pending := queued_drafts.size()
	if is_dirty() and not queued_drafts.has(draft.id):
		pending += 1
	header.get_node("SaveChanges").text = "保存 *" if pending > 0 and not selected_save.is_empty() else "保存"
	header.get_node("SaveChanges").disabled = selected_save.is_empty() or pending == 0
	var label: Label = header.get_node("SaveStatus")
	label.text = "尚未选择存档" if selected_save.is_empty() else "%s · %s" % ["未保存 %d 人" % pending if pending > 0 else "已读取",selected_save.get_file()]
	label.tooltip_text = label.text

func _choose_save(title_text: String, on_selected: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.title = title_text
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.current_dir = ProjectSettings.globalize_path("user://saves")
	dialog.add_filter("save_*.json", "游戏存档")
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		on_selected.call(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.75)

func _apply_to_selected_save() -> void:
	if selected_save.is_empty() or draft.is_empty():
		return
	_stage_current_draft()
	var batch := queued_drafts.values()
	if batch.is_empty():
		return
	var result := _update_selected_save(selected_save,batch)
	if not result.error.is_empty():
		status.text = result.error
		return
	queued_drafts.clear()
	var reload_error := _read_target_save(result.path)
	status.text = "已保存 %d 名人物 · %s" % [batch.size(), selected_save.get_file()] if reload_error.is_empty() else "存档已保存，重新读取失败：" + reload_error
	status.tooltip_text = selected_save

func _stage_current_draft() -> void:
	if is_dirty():
		queued_drafts[draft.id] = draft.duplicate(true)
	elif not draft.is_empty():
		queued_drafts.erase(draft.id)

func _update_selected_save(path: String, batch: Array) -> Dictionary:
	var temporary := ProjectSettings.globalize_path("user://" + Model.uid("npc_save_draft_") + ".json")
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		return {"path":"","error":"无法写入 NPC 临时草稿。"}
	file.store_string(JSON.stringify({"drafts":batch,"source_checksum":selected_save_checksum}))
	file.flush()
	var write_error := file.get_error()
	file.close()
	var output := []
	var exit_code := -1
	if write_error == OK:
		exit_code = OS.execute(OS.get_executable_path(),[
			"--headless","--path",ProjectSettings.globalize_path("res://"),
			"--script","res://addons/npc_editor/apply_to_save.gd","--",
			ProjectSettings.globalize_path(path),temporary
		],output,true)
	DirAccess.remove_absolute(temporary)
	if write_error != OK:
		return {"path":"","error":"无法写入 NPC 临时草稿。"}
	for chunk in output:
		for line in str(chunk).split("\n"):
			if line.begins_with("NPC_SAVE_RESULT "):
				var result: Variant = JSON.parse_string(line.trim_prefix("NPC_SAVE_RESULT "))
				if result is Dictionary and result.get("path") is String and result.get("error") is String:
					if exit_code == 0 or not result.error.is_empty():
						return result
	return {"path":"","error":"存档更新未完成。请检查 Godot 输出。"}

func _read_saved_fortunes(path: String) -> void:
	var saves := Saves.new()
	var payload := saves.read(path)
	if not saves.error.is_empty():
		status.text = saves.error
		return
	var state: Variant = payload.get("state")
	var npc: Variant = state.get("npcs", {}).get(draft.id) if state is Dictionary and state.get("npcs") is Dictionary else null
	if not npc is Dictionary or not npc.get("fortunes", {}) is Dictionary:
		status.text = "所选存档没有该人物或气运数据无效。"
		return
	var profile: Dictionary = npc.get("profile", {})
	if not npc.has("profile"):
		for row in data.prototype.npcs:
			if row.id == draft.id:
				profile = row.get("profile", {})
				break
	draft.fortune_ids = _permanent_fortune_ids(npc.get("fortunes", {}))
	for key in ["innate_fortune","acquired_fortune"]:
		draft.profile[key] = profile.get(key, []).duplicate(true)
	_changed()
	status.text = "已读取存档气运到草稿。" if not selected_save.is_empty() else "已读取存档气运到草稿，保存后才会更新初始配置。"

func _permanent_fortune_ids(records: Dictionary) -> Array:
	var ids := []
	for id in records:
		var definition: Dictionary = Model.Fortune.DEFINITIONS.get(id, {})
		if not definition.is_empty() and definition.duration.type == "permanent":
			ids.append(id)
	return ids

func _add_fortune(id: String) -> void:
	var definition: Dictionary = Model.Fortune.DEFINITIONS[id]
	var kind := "innate" if definition.kind == "innate" else "acquired"
	var feedback: Label = fortune_feedback[kind]
	if definition.duration.type != "permanent":
		feedback.text = "无法添加「%s」：该气运有持续时间或只在战斗内生效，NPC 初始配置仅支持永久气运。" % definition.name
		return
	for held in draft.fortune_ids:
		var other: Dictionary = Model.Fortune.DEFINITIONS[held]
		if id == held:
			feedback.text = "无法添加「%s」：该气运已在列表中。" % definition.name
			return
		if not definition.exclusive_group.is_empty() and other.exclusive_group == definition.exclusive_group:
			feedback.text = "无法添加「%s」：它与「%s」同属互斥组「%s」。" % [definition.name, other.name, definition.exclusive_group]
			return
	_add_id(id, draft.fortune_ids)

func _skills(parent: Node, table_key: String, slot_key: String) -> void:
	var learned: Dictionary = draft[table_key]
	var slots: Array = draft[slot_key]
	var table: Dictionary = data[table_key]
	_label(parent, "已装配 %d / %d" % [slots.size(), Model.SLOT_LIMIT])
	for index in Model.SLOT_LIMIT:
		_label(parent, "%02d  %s" % [index + 1, _resource_name(table, slots[index]) if index < slots.size() else "空位"])
	_button(parent, "从资源库学习", _choose.bind(table, learned, _learn.bind(learned)))
	if table_key == "spells":
		_label(parent, "装配与学习分别保存。当前 NPC 没有施法决策入口。")
	else:
		_label(parent, "已装配功法进入被动属性计算。")
	for id in learned:
		var row := _row(parent, _resource_name(table, id))
		_button(row, "卸下" if id in slots else "装配", _toggle_slot.bind(id, slots, Model.SLOT_LIMIT))
		_button(row, "遗忘", _forget.bind(id, learned, slots))
		var max_level: int = table[id].get("levels", [0,0,0]).size()
		_level_stepper(parent, "等级", learned, id, 1, max_level)
		if table_key == "spells" and table[id].has("levels"):
			_number(parent, "熟练度（满级为零）", draft.spell_mastery, id, 0, int(data.spell_growth.per_level) - 1)

func _learn(id: String, learned: Dictionary) -> void:
	if not learned.has(id):
		learned[id] = 1
	_changed()

func _forget(id: String, learned: Dictionary, slots: Array) -> void:
	learned.erase(id)
	if is_same(learned, draft.spells):
		draft.spell_mastery.erase(id)
	_remove_id(id, slots)

func _equipment_table(slot: String = "") -> Dictionary:
	var rows := {}
	for id in data.equipment:
		if not slot.is_empty() and data.equipment[id].slot != slot:
			continue
		var row: Dictionary = data.equipment[id].duplicate()
		row.merge(data.items[id])
		rows[id] = row
	return rows

func _gear(parent: Node) -> void:
	for slot in Model.Equipment.SLOTS:
		var instance: String = draft.equipped.get(slot, "")
		var title_text: String = Model.Equipment.SLOTS[slot]
		if not instance.is_empty():
			title_text += " · " + _resource_name(data.items, draft.equipment_instances[instance])
		var row := _row(parent, title_text)
		_button(row, "选择并穿戴", _choose.bind(_equipment_table(slot), draft.equipment_instances.values(), _add_gear.bind(true)))
		if not instance.is_empty():
			_button(row, "卸下", _erase.bind(slot, draft.equipped))
	_button(parent, "添加持有装备", _choose.bind(_equipment_table(), draft.equipment_instances.values(), _add_gear.bind(false)))
	for instance in draft.equipment_instances:
		var id: String = draft.equipment_instances[instance]
		var definition: Dictionary = data.equipment[id]
		var row := _row(parent, _resource_name(data.items, id))
		if draft.equipped.get(definition.slot) != instance:
			_button(row, "穿戴", _equip.bind(instance))
		_button(row, "移除实例", _remove_gear.bind(instance))
		if definition.has("nurture_max"):
			_level_stepper(parent, "温养等级", draft.equipment_nurture, instance, 0, definition.nurture_max)

func _add_gear(id: String, wear: bool) -> void:
	if wear:
		var error := Model.equipment_error(draft, id, data)
		if not error.is_empty():
			status.text = error
			return
	var instance := Model.uid("gear_")
	draft.equipment_instances[instance] = id
	if wear:
		_equip(instance)
	else:
		_changed()

func _equip(instance: String) -> void:
	var id: String = draft.equipment_instances[instance]
	var error := Model.equipment_error(draft, id, data)
	if not error.is_empty():
		status.text = error
		return
	draft.equipped[data.equipment[id].slot] = instance
	_changed()

func _remove_gear(instance: String) -> void:
	var slot: String = data.equipment[draft.equipment_instances[instance]].slot
	if draft.equipped.get(slot) == instance:
		draft.equipped.erase(slot)
	draft.equipment_nurture.erase(instance)
	_erase(instance, draft.equipment_instances)

func _artifacts(parent: Node) -> void:
	_label(parent, "档案装配。法宝能力当前未接入 NPC 结算。")
	for index in 4:
		_label(parent, "%d  %s" % [index + 1, _resource_name(data.artifacts, draft.artifact_slots[index]) if index < draft.artifact_slots.size() else "空位"])
	_button(parent, "选择法宝", _choose.bind(data.artifacts, draft.artifact_ids, _add_id.bind(draft.artifact_ids)))
	for id in draft.artifact_ids:
		var row := _row(parent, _resource_name(data.artifacts, id))
		_button(row, "卸下" if id in draft.artifact_slots else "装配", _toggle_slot.bind(id, draft.artifact_slots, 4))
		_button(row, "移除", _remove_artifact.bind(id))

func _remove_artifact(id: String) -> void:
	draft.artifact_slots.erase(id)
	_remove_id(id, draft.artifact_ids)

func _items(parent: Node) -> void:
	_button(parent, "选择物品", _choose.bind(data.items, draft.inventory.keys() + draft.equipment_instances.values(), _add_item))
	_label(parent, "装备以独立实例保存，穿戴和温养请在装备页处理。")
	for id in draft.inventory:
		_number(parent, _resource_name(data.items, id), draft.inventory, id, 1, 1000000)
		_button(parent, "移除 " + _resource_name(data.items, id), _erase.bind(id, draft.inventory))
	for instance in draft.equipment_instances:
		_label(parent, _resource_name(data.items, draft.equipment_instances[instance]))

func _add_item(id: String) -> void:
	if data.equipment.has(id):
		_add_gear(id, false)
	else:
		var error := Model.Inventory.new().add(draft, id, 1, data)
		if not error.is_empty():
			status.text = error
			return
		_changed()

func _relations(parent: Node) -> void:
	var roster := _visible_roster()
	roster.merge(queued_drafts,true)
	roster.erase(draft.id)
	_button(parent, "选择关系对象", _choose.bind(roster, draft.relations, _add_relation))
	_label(parent, "好感沿用现有单向分数，关系描述用于人物档案。")
	var ids: Array = draft.relations.keys()
	for id in draft.profile.contacts:
		if id not in ids:
			ids.append(id)
	for id in ids:
		_number(parent, _resource_name(roster, id) + " · 好感", draft.relations, id, -100, 100)
		_text(parent, "关系描述", draft.profile.contacts, id)
		_button(parent, "移除关系", _remove_relation.bind(id))

func _add_relation(id: String) -> void:
	if not draft.relations.has(id):
		draft.relations[id] = 0
	_changed()

func _remove_relation(id: String) -> void:
	draft.profile.contacts.erase(id)
	_erase(id, draft.relations)
