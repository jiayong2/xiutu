@tool
extends RefCounted

const Config := preload("res://core/npc_generation/generation_config.gd")
const Fortune := preload("res://gameplay/character/player_fortunes.gd")
const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const Equipment := preload("res://gameplay/inventory/equipment_values.gd")
const Character := preload("res://gameplay/character/character_system.gd")
const Locations := preload("res://core/world_locations.gd")

const ROUTE_LABELS := {
	"qi_primary": "法修为主",
	"body_primary": "体修为主",
	"dual": "法体双修",
	"random": "随机",
}
const MODE_LABELS := {
	"strict": "严格同境界",
	"down_one": "向下浮动一个大境界",
	"up_one": "上下浮动一个大境界",
	"absolute": "指定绝对境界范围",
	"any": "不限制",
}
const STAT_LABELS := {
	"hp": "基础生命", "mp": "基础灵力", "attack": "基础攻击", "defense": "基础防御", "speed": "基础速度",
}
const FOUNDATION_LABELS := {
	"qi_sea": "气海", "meridians": "经脉", "bones": "筋骨", "physique": "体魄", "spirit_sea": "识海", "soul": "神魂",
}

signal changed
signal copy_requested
signal delete_requested

var applying := false
var data: Dictionary = {}
var spins := {}
var texts := {}
var toggles := {}
var options := {}
var groups := {}
var picks := {}
var template_option: OptionButton
var _columns := 2
var _grid: GridContainer

func build(roots: Dictionary, catalog: Dictionary, config: Dictionary) -> void:
	data = catalog
	_grid = null
	_columns = 2
	_clear(roots.template)
	_clear(roots.batch)
	_clear(roots.basic)
	_clear(roots.cultivation)
	_clear(roots.fortune)
	_clear(roots.gear)
	_clear(roots.skill)
	_build_template(roots.template, roots.template_actions)
	_build_batch(roots.batch)
	_build_basic(roots.basic, config)
	_build_cultivation(roots.cultivation, config)
	_build_fortunes(roots.fortune, config)
	_build_gear(roots.gear, config)
	_build_skills(roots.skill, config)
	apply(config)

func apply(config: Dictionary) -> void:
	applying = true
	var normalized: Dictionary = Config.normalize(config)
	_set_spin("count", int(normalized.count))
	_set_text("name", str(normalized.name))
	_set_text("seed", str(normalized.get("seed", "")))
	_set_toggle("identity.generate_names", normalized.identity.generate_names == true)
	_set_spin("identity.male_weight", int(normalized.identity.male_weight))
	_set_spin("identity.female_weight", int(normalized.identity.female_weight))
	_set_range("identity.age", normalized.identity.age)
	_set_range("identity.lifespan", normalized.identity.lifespan)
	_set_range("identity.wealth", normalized.identity.wealth)
	for key in Config.STAT_KEYS:
		_set_range("base_stats." + key, normalized.base_stats[key])
	_set_range("cultivation.qi_realm", normalized.cultivation.qi_realm)
	_set_range("cultivation.body_realm", normalized.cultivation.body_realm)
	_set_range("cultivation.cultivation_ratio", normalized.cultivation.cultivation_ratio)
	_set_option("cultivation.route", str(normalized.cultivation.route))
	_set_toggle("cultivation.realm_known", normalized.cultivation.realm_known == true)
	_set_text("cultivation.qi_realm_weights", _weights_text(normalized.cultivation.qi_realm_weights))
	_set_text("cultivation.body_realm_weights", _weights_text(normalized.cultivation.body_realm_weights))
	for key in Config.FOUNDATION_KEYS:
		_set_range("cultivation.foundation." + key, normalized.cultivation.foundation[key])
	_set_group("identity.location_ids", Config.string_ids(normalized.identity.location_ids))
	_set_group("identity.sect_names", normalized.identity.sect_names)
	_set_group("identity.roles", normalized.identity.roles)
	_set_group("identity.personalities", normalized.identity.personalities)
	_set_group("cultivation.roots", normalized.cultivation.roots)
	_set_group("cultivation.ranks", normalized.cultivation.ranks)
	_apply_fortune("innate_fortune", normalized.innate_fortune)
	_apply_fortune("acquired_fortune", normalized.acquired_fortune)
	_apply_gear("equipment", normalized.equipment)
	_apply_gear("artifacts", normalized.artifacts)
	_apply_skill("techniques", normalized.techniques)
	_apply_skill("spells", normalized.spells)
	if template_option != null:
		_select_option_by_id(template_option, str(normalized.id))
	applying = false

func collect() -> Dictionary:
	var raw := {
		"schema_version": Config.SCHEMA_VERSION,
		"id": _selected_template_id(),
		"name": _text("name"),
		"count": _spin("count"),
		"identity": {
			"location_ids": _group("identity.location_ids"),
			"sect_names": _group("identity.sect_names"),
			"roles": _group("identity.roles"),
			"male_weight": _spin("identity.male_weight"),
			"female_weight": _spin("identity.female_weight"),
			"age": _range("identity.age"),
			"lifespan": _range("identity.lifespan"),
			"wealth": _range("identity.wealth"),
			"personalities": _group("identity.personalities"),
			"generate_names": _toggle("identity.generate_names"),
		},
		"cultivation": {
			"qi_realm": _range("cultivation.qi_realm"),
			"body_realm": _range("cultivation.body_realm"),
			"qi_realm_weights": _parse_weights(_text("cultivation.qi_realm_weights")),
			"body_realm_weights": _parse_weights(_text("cultivation.body_realm_weights")),
			"route": _option("cultivation.route"),
			"cultivation_ratio": _range("cultivation.cultivation_ratio"),
			"roots": _group("cultivation.roots"),
			"ranks": _group("cultivation.ranks"),
			"realm_known": _toggle("cultivation.realm_known"),
			"foundation": {},
		},
		"base_stats": {},
		"innate_fortune": _collect_fortune("innate_fortune"),
		"acquired_fortune": _collect_fortune("acquired_fortune"),
		"equipment": _collect_gear("equipment"),
		"artifacts": _collect_gear("artifacts"),
		"techniques": _collect_skill("techniques"),
		"spells": _collect_skill("spells"),
	}
	for key in Config.STAT_KEYS:
		raw.base_stats[key] = _range("base_stats." + key)
	for key in Config.FOUNDATION_KEYS:
		raw.cultivation.foundation[key] = _range("cultivation.foundation." + key)
	var seed_text := _text("seed").strip_edges()
	if seed_text.is_valid_int():
		raw.seed = int(seed_text)
	return Config.normalize(raw)

func _build_template(parent: Node, actions: HBoxContainer) -> void:
	template_option = _option_button()
	parent.add_child(template_option)
	for child in actions.get_children():
		if str(child.name) == "SaveTemplate":
			continue
		actions.remove_child(child)
		child.queue_free()
	var copy_button := _small_button("复制")
	copy_button.pressed.connect(func(): copy_requested.emit())
	actions.add_child(copy_button)
	var delete_button := _small_button("删除")
	delete_button.pressed.connect(func(): delete_requested.emit())
	actions.add_child(delete_button)

func _build_batch(parent: Node) -> void:
	_columns = 1
	_grid = null
	_spin_row(parent, "生成数量", "count", Config.COUNT_MIN, Config.COUNT_MAX)
	_columns = 2
	_grid = null

func _build_basic(parent: Node, _config: Dictionary) -> void:
	_heading(parent, "姓名与档案")
	_text_row(parent, "模板名称", "name")
	_text_row(parent, "随机种子（可空）", "seed")
	_toggle_row(parent, "自动生成姓名", "identity.generate_names")
	_range_row(parent, "年龄", "identity.age", 0, 100000)
	_range_row(parent, "寿元", "identity.lifespan", 1, 100000)
	_range_row(parent, "灵石", "identity.wealth", 0, 100000000)
	_spin_row(parent, "男性权重", "identity.male_weight", 0, 1000)
	_spin_row(parent, "女性权重", "identity.female_weight", 0, 1000)
	_heading(parent, "地点 / 宗门 / 身份 / 性格")
	_note(parent, "不勾选地点或灵根表示使用全部现有合法值。")
	var places := Locations.names(data)
	var location_items := []
	for id in places:
		location_items.append({"id": id, "name": "%s（%s）" % [places[id], id]})
	_group_box(parent, "初始地点", "identity.location_ids", location_items)
	var sects := []
	for name in Config.sect_names(data):
		sects.append({"id": name, "name": "无宗门" if name.is_empty() else name})
	_group_box(parent, "宗门", "identity.sect_names", sects)
	_group_box(parent, "身份", "identity.roles", _named(Config.collect_roles(data, data.get("npc_overrides", {}))))
	_group_box(parent, "性格", "identity.personalities", _named(Config.collect_personalities(data, data.get("npc_overrides", {}))))
	_heading(parent, "战斗底值")
	_note(parent, "此处是基础属性。最终攻击等须经现有属性计算，不会把装备/功法加成写回底值。暴击率/暴伤因定义校验要求整数，本页不生成这两项底值。")
	for key in Config.STAT_KEYS:
		_range_row(parent, STAT_LABELS[key], "base_stats." + key, 0, 100000)

func _build_cultivation(parent: Node, _config: Dictionary) -> void:
	_heading(parent, "境界与方向")
	_range_row(parent, "法修境界", "cultivation.qi_realm", 0, Cultivation.MAX_LEVEL)
	_range_row(parent, "体修境界", "cultivation.body_realm", 0, Cultivation.MAX_LEVEL)
	_text_row(parent, "法修权重 如 1:3,9:1", "cultivation.qi_realm_weights")
	_text_row(parent, "体修权重 如 0:2,9:1", "cultivation.body_realm_weights")
	var route := _option_button()
	for id in Config.ROUTES:
		route.add_item(ROUTE_LABELS[id])
		route.set_item_metadata(route.item_count - 1, id)
	route.item_selected.connect(_emit_changed)
	options["cultivation.route"] = route
	_labeled(parent, "修炼方向", route)
	_range_row(parent, "当前修为比例%", "cultivation.cultivation_ratio", 0, 100)
	_toggle_row(parent, "在游戏中公开法修境界", "cultivation.realm_known")
	_heading(parent, "灵根与天资")
	var roots := []
	for root in data.rules.roots:
		roots.append({"id": root, "name": root})
	_group_box(parent, "灵根", "cultivation.roots", roots)
	var ranks := []
	for rank in Character.NPC_RANKS:
		ranks.append({"id": rank, "name": rank})
	_group_box(parent, "天资", "cultivation.ranks", ranks)
	_heading(parent, "六项根基")
	for key in Config.FOUNDATION_KEYS:
		_range_row(parent, FOUNDATION_LABELS[key], "cultivation.foundation." + key, 0, 100000)

func _build_fortunes(parent: Node, _config: Dictionary) -> void:
	_fortune_block(parent, "先天气运", "innate_fortune", ["innate"], false)
	_fortune_block(parent, "后天气运", "acquired_fortune", ["acquired"], true)

func _fortune_block(parent: Node, title_text: String, field: String, kinds: Array, allow_negative_toggle: bool) -> void:
	_heading(parent, title_text)
	_range_row(parent, "总数量范围", field + ".count", 0, 20)
	var quality_range := HBoxContainer.new()
	quality_range.add_child(_quality_picker(field + ".min_quality", Config.FORTUNE_QUALITIES))
	var separator := Label.new()
	separator.text = "至"
	quality_range.add_child(separator)
	quality_range.add_child(_quality_picker(field + ".max_quality", Config.FORTUNE_QUALITIES))
	_labeled(parent, "品质范围", quality_range)
	_quality_option(parent, "保底品质", field + ".at_least.quality", Config.FORTUNE_QUALITIES)
	_spin_row(parent, "保底数量", field + ".at_least.count", 0, 20)
	_text_row(parent, "品质权重 如 凡品:1,天品:8", field + ".quality_weights")
	if allow_negative_toggle:
		_toggle_row(parent, "允许负面气运", field + ".allow_negative")
	_id_pick(parent, "必带", field + ".required_ids", _fortune_choices(kinds, allow_negative_toggle))
	_id_pick(parent, "排除", field + ".excluded_ids", _fortune_choices(kinds, true))

func _build_gear(parent: Node, _config: Dictionary) -> void:
	_gear_block(parent, "装备", "equipment", data.equipment, Equipment.SLOTS, true)
	_gear_block(parent, "法宝", "artifacts", data.artifacts, {}, false)

func _gear_block(parent: Node, title_text: String, field: String, table: Dictionary, slots: Dictionary, with_slots: bool) -> void:
	_heading(parent, title_text)
	_range_row(parent, "数量", field + ".count", 0, 8 if with_slots else 4)
	_quality_option(parent, "最低品质", field + ".min_quality", Config.GEAR_QUALITIES)
	_quality_option(parent, "最高品质", field + ".max_quality", Config.GEAR_QUALITIES)
	var mode := _option_button()
	for id in Config.REALM_MODES:
		mode.add_item(MODE_LABELS[id])
		mode.set_item_metadata(mode.item_count - 1, id)
	mode.item_selected.connect(_emit_changed)
	options[field + ".realm_mode"] = mode
	_labeled(parent, "境界匹配", mode)
	_spin_row(parent, "绝对最低大境界档", field + ".realm_min", 0, 9)
	_spin_row(parent, "绝对最高大境界档", field + ".realm_max", 0, 9)
	if with_slots:
		var slot_items := []
		for slot in slots:
			slot_items.append({"id": slot, "name": slots[slot]})
		_group_box(parent, "槽位（不选表示全部）", field + ".slots", slot_items)
	_toggle_row(parent, "优先匹配灵根/方向", field + ".match_route")
	_id_pick(parent, "必带", field + ".required_ids", _table_choices(table))
	_id_pick(parent, "排除", field + ".excluded_ids", _table_choices(table))

func _build_skills(parent: Node, _config: Dictionary) -> void:
	_skill_block(parent, "功法", "techniques", data.techniques, true)
	_skill_block(parent, "法术", "spells", data.spells, false)

func _skill_block(parent: Node, title_text: String, field: String, table: Dictionary, techniques: bool) -> void:
	_heading(parent, title_text)
	_range_row(parent, "已学数量", field + ".count", 0, 10)
	_range_row(parent, "装配数量", field + ".equipped", 0, 10)
	_range_row(parent, "等级", field + ".level", 1, 5)
	if techniques:
		_quality_option(parent, "最低品阶", field + ".min_rarity", Config.TECHNIQUE_RARITIES)
		_quality_option(parent, "最高品阶", field + ".max_rarity", Config.TECHNIQUE_RARITIES)
		_toggle_row(parent, "优先匹配修炼方向", field + ".match_route")
	else:
		_toggle_row(parent, "优先匹配灵根", field + ".match_root")
	_id_pick(parent, "必带", field + ".required_ids", _table_choices(table))
	_id_pick(parent, "排除", field + ".excluded_ids", _table_choices(table))

func _apply_fortune(field: String, rules: Dictionary) -> void:
	_set_range(field + ".count", rules.count)
	_set_option(field + ".min_quality", str(rules.min_quality))
	_set_option(field + ".max_quality", str(rules.max_quality))
	_set_option(field + ".at_least.quality", str(rules.at_least.quality))
	_set_spin(field + ".at_least.count", int(rules.at_least.count))
	_set_text(field + ".quality_weights", _weights_text(rules.quality_weights))
	if toggles.has(field + ".allow_negative"):
		_set_toggle(field + ".allow_negative", rules.get("allow_negative", false) == true)
	_set_pick(field + ".required_ids", Config.string_ids(rules.required_ids))
	_set_pick(field + ".excluded_ids", Config.string_ids(rules.excluded_ids))

func _apply_gear(field: String, rules: Dictionary) -> void:
	_set_range(field + ".count", rules.count)
	_set_option(field + ".min_quality", str(rules.min_quality))
	_set_option(field + ".max_quality", str(rules.max_quality))
	_set_option(field + ".realm_mode", str(rules.realm_mode))
	_set_spin(field + ".realm_min", int(rules.realm_min))
	_set_spin(field + ".realm_max", int(rules.realm_max))
	if groups.has(field + ".slots"):
		_set_group(field + ".slots", rules.get("slots", []))
	_set_toggle(field + ".match_route", rules.get("match_route", false) == true)
	_set_pick(field + ".required_ids", Config.string_ids(rules.required_ids))
	_set_pick(field + ".excluded_ids", Config.string_ids(rules.excluded_ids))

func _apply_skill(field: String, rules: Dictionary) -> void:
	_set_range(field + ".count", rules.count)
	_set_range(field + ".equipped", rules.equipped)
	_set_range(field + ".level", rules.level)
	if options.has(field + ".min_rarity"):
		_set_option(field + ".min_rarity", str(rules.min_rarity))
		_set_option(field + ".max_rarity", str(rules.max_rarity))
	if toggles.has(field + ".match_route"):
		_set_toggle(field + ".match_route", rules.get("match_route", true) == true)
	if toggles.has(field + ".match_root"):
		_set_toggle(field + ".match_root", rules.get("match_root", true) == true)
	_set_pick(field + ".required_ids", Config.string_ids(rules.required_ids))
	_set_pick(field + ".excluded_ids", Config.string_ids(rules.excluded_ids))

func _collect_fortune(field: String) -> Dictionary:
	return {
		"count": _range(field + ".count"),
		"min_quality": _option(field + ".min_quality"),
		"max_quality": _option(field + ".max_quality"),
		"at_least": {"quality": _option(field + ".at_least.quality"), "count": _spin(field + ".at_least.count")},
		"quality_weights": _parse_weights(_text(field + ".quality_weights")),
		"required_ids": _pick(field + ".required_ids"),
		"excluded_ids": _pick(field + ".excluded_ids"),
		"allow_negative": _toggle(field + ".allow_negative") if toggles.has(field + ".allow_negative") else false,
	}

func _collect_gear(field: String) -> Dictionary:
	return {
		"count": _range(field + ".count"),
		"min_quality": _option(field + ".min_quality"),
		"max_quality": _option(field + ".max_quality"),
		"realm_mode": _option(field + ".realm_mode"),
		"realm_min": _spin(field + ".realm_min"),
		"realm_max": _spin(field + ".realm_max"),
		"slots": _group(field + ".slots") if groups.has(field + ".slots") else [],
		"required_ids": _pick(field + ".required_ids"),
		"excluded_ids": _pick(field + ".excluded_ids"),
		"match_route": _toggle(field + ".match_route"),
	}

func _collect_skill(field: String) -> Dictionary:
	var result := {
		"count": _range(field + ".count"),
		"equipped": _range(field + ".equipped"),
		"level": _range(field + ".level"),
		"required_ids": _pick(field + ".required_ids"),
		"excluded_ids": _pick(field + ".excluded_ids"),
		"match_root": _toggle(field + ".match_root") if toggles.has(field + ".match_root") else true,
		"match_route": _toggle(field + ".match_route") if toggles.has(field + ".match_route") else true,
	}
	if options.has(field + ".min_rarity"):
		result.min_rarity = _option(field + ".min_rarity")
		result.max_rarity = _option(field + ".max_rarity")
	return result

func _option_button() -> OptionButton:
	var box := OptionButton.new()
	box.fit_to_longest_item = false
	box.clip_text = true
	box.custom_minimum_size = Vector2(0, 52)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box

func _small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)
	return button

func _new_spin(low: int, high: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.custom_minimum_size = Vector2(44, 52)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spin.add_theme_constant_override("buttons_width", 0)
	spin.add_theme_constant_override("set_min_buttons_width_from_icons", 0)
	spin.add_theme_constant_override("field_and_buttons_separation", 0)
	spin.add_theme_font_size_override("font_size", 18)
	var edit := spin.get_line_edit()
	edit.add_theme_font_size_override("font_size", 18)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.value_changed.connect(_emit_changed)
	return spin

func _step_button(glyph: String, spin: SpinBox, direction: int) -> Button:
	var button := Button.new()
	button.text = glyph
	button.custom_minimum_size = Vector2(38, 52)
	button.theme_type_variation = &"GenerationStepButton"
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(func():
		spin.value = clamp(spin.value + direction, spin.min_value, spin.max_value)
	)
	return button

func _stepper_row(parts: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for index in parts.size():
		if index > 0:
			var separator := Label.new()
			separator.text = "至"
			row.add_child(separator)
		var spin: SpinBox = parts[index]
		var endpoint := HBoxContainer.new()
		endpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		endpoint.add_theme_constant_override("separation", 4)
		row.add_child(endpoint)
		endpoint.add_child(_step_button("+", spin, 1))
		endpoint.add_child(spin)
		endpoint.add_child(_step_button("−", spin, -1))
	return row

func _grid_of(parent: Node) -> GridContainer:
	if _grid != null and is_instance_valid(_grid) and _grid.get_parent() == parent and _grid.columns == _columns:
		return _grid
	_grid = GridContainer.new()
	_grid.columns = _columns
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(_grid)
	return _grid

func _full() -> void:
	_grid = null

func _heading(parent: Node, value: String) -> void:
	_full()
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)

func _note(parent: Node, value: String) -> void:
	_full()
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#5D7A74"))
	parent.add_child(label)

func _labeled(parent: Node, title_text: String, control: Control) -> void:
	var grid := _grid_of(parent)
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = title_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("#5D7A74"))
	cell.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.add_child(control)
	grid.add_child(cell)

func _spin_row(parent: Node, title_text: String, key: String, low: int, high: int) -> void:
	var spin := _new_spin(low, high)
	spins[key] = spin
	_labeled(parent, title_text, _stepper_row([spin]))

func _range_row(parent: Node, title_text: String, key: String, low: int, high: int) -> void:
	var lo := _new_spin(low, high)
	var hi := _new_spin(low, high)
	spins[key + ".min"] = lo
	spins[key + ".max"] = hi
	_labeled(parent, title_text, _stepper_row([lo, hi]))

func _text_row(parent: Node, title_text: String, key: String) -> void:
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(0, 52)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(_emit_changed)
	texts[key] = field
	_labeled(parent, title_text, field)

func _toggle_row(parent: Node, title_text: String, key: String) -> void:
	_full()
	var button := CheckButton.new()
	button.text = title_text
	button.add_theme_font_size_override("font_size", 17)
	button.toggled.connect(_emit_changed)
	toggles[key] = button
	parent.add_child(button)

func _quality_option(parent: Node, title_text: String, key: String, values: Array) -> void:
	_labeled(parent, title_text, _quality_picker(key, values))

func _quality_picker(key: String, values: Array) -> OptionButton:
	var box := _option_button()
	box.add_item("不限")
	box.set_item_metadata(0, "")
	for value in values:
		box.add_item(value)
		box.set_item_metadata(box.item_count - 1, value)
	box.item_selected.connect(_emit_changed)
	options[key] = box
	return box

func _group_box(parent: Node, title_text: String, key: String, items: Array) -> void:
	_full()
	var label := Label.new()
	label.text = title_text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("#5D7A74"))
	parent.add_child(label)
	var wrap := HFlowContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("h_separation", 8)
	wrap.add_theme_constant_override("v_separation", 6)
	parent.add_child(wrap)
	groups[key] = {}
	for item in items:
		var button := CheckButton.new()
		button.text = str(item.name)
		button.add_theme_font_size_override("font_size", 17)
		button.toggled.connect(_emit_changed)
		wrap.add_child(button)
		groups[key][str(item.id)] = button

func _id_pick(parent: Node, title_text: String, key: String, choices: Array) -> void:
	_full()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var label := Label.new()
	label.text = title_text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color("#5D7A74"))
	row.add_child(label)
	var box := _option_button()
	box.add_item("选择…")
	box.set_item_metadata(0, "")
	for item in choices:
		box.add_item(str(item.name))
		box.set_item_metadata(box.item_count - 1, str(item.id))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var add := _small_button("+ 添加")
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(add)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 56)
	parent.add_child(list)
	var remove := _small_button("移除")
	remove.size_flags_horizontal = Control.SIZE_SHRINK_END
	parent.add_child(remove)
	picks[key] = {"box": box, "list": list}
	add.pressed.connect(func():
		var id: String = str(box.get_item_metadata(box.selected)) if box.selected >= 0 else ""
		if id.is_empty():
			return
		for index in list.item_count:
			if str(list.get_item_metadata(index)) == id:
				return
		list.add_item(_choice_name(choices, id))
		list.set_item_metadata(list.item_count - 1, id)
		_emit_changed()
	)
	remove.pressed.connect(func():
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		list.remove_item(selected[0])
		_emit_changed()
	)

func _named(values: PackedStringArray) -> Array:
	var result: Array = []
	for value in values:
		result.append({"id": value, "name": value})
	return result

func _table_choices(table: Dictionary) -> Array:
	var result: Array = []
	for id in table:
		result.append({"id": id, "name": "%s（%s）" % [table[id].get("name", id), id]})
	return result

func _fortune_choices(kinds: Array, include_negative: bool) -> Array:
	var result: Array = []
	for id in Fortune.DEFINITIONS:
		var row: Dictionary = Fortune.DEFINITIONS[id]
		if row.get("duration", {}).get("type") != "permanent":
			continue
		var kind: String = str(row.get("kind", ""))
		if kind == "negative" and not include_negative:
			continue
		if kind != "negative" and kind not in kinds:
			continue
		result.append({"id": id, "name": "%s · %s（%s）" % [row.get("name", id), row.get("quality", ""), id]})
	return result

func _choice_name(choices: Array, id: String) -> String:
	for item in choices:
		if str(item.id) == id:
			return str(item.name)
	return id

func _selected_template_id() -> String:
	if template_option == null or template_option.selected < 0:
		return "template_custom"
	return str(template_option.get_item_metadata(template_option.selected))

func _spin(key: String) -> int:
	return int(spins[key].value) if spins.has(key) else 0

func _text(key: String) -> String:
	return str(texts[key].text) if texts.has(key) else ""

func _toggle(key: String) -> bool:
	return toggles[key].button_pressed if toggles.has(key) else false

func _option(key: String) -> String:
	if not options.has(key):
		return ""
	var box: OptionButton = options[key]
	if box.selected < 0:
		return ""
	return str(box.get_item_metadata(box.selected))

func _range(key: String) -> Dictionary:
	return {"min": _spin(key + ".min"), "max": _spin(key + ".max")}

func _group(key: String) -> Array:
	var result: Array = []
	if not groups.has(key):
		return result
	for id in groups[key]:
		if groups[key][id].button_pressed:
			result.append(id)
	return result

func _pick(key: String) -> Array:
	var result: Array = []
	if not picks.has(key):
		return result
	var list: ItemList = picks[key].list
	for index in list.item_count:
		result.append(str(list.get_item_metadata(index)))
	return result

func _set_spin(key: String, value: int) -> void:
	if spins.has(key):
		spins[key].value = value

func _set_text(key: String, value: String) -> void:
	if texts.has(key):
		texts[key].text = value

func _set_toggle(key: String, value: bool) -> void:
	if toggles.has(key):
		toggles[key].button_pressed = value

func _set_option(key: String, value: String) -> void:
	if options.has(key):
		_select_option_by_id(options[key], value)

func _set_range(key: String, value: Dictionary) -> void:
	_set_spin(key + ".min", int(value.get("min", 0)))
	_set_spin(key + ".max", int(value.get("max", 0)))

func _set_group(key: String, selected: Array) -> void:
	if not groups.has(key):
		return
	for id in groups[key]:
		groups[key][id].button_pressed = id in selected

func _set_pick(key: String, ids: Array) -> void:
	if not picks.has(key):
		return
	var list: ItemList = picks[key].list
	list.clear()
	var box: OptionButton = picks[key].box
	for id in ids:
		var label := str(id)
		for index in box.item_count:
			if str(box.get_item_metadata(index)) == str(id):
				label = box.get_item_text(index)
				break
		list.add_item(label)
		list.set_item_metadata(list.item_count - 1, str(id))

func _select_option_by_id(box: OptionButton, value: String) -> void:
	for index in box.item_count:
		if str(box.get_item_metadata(index)) == value:
			box.select(index)
			return
	if box.item_count > 0:
		box.select(0)

func fill_templates(rows: Dictionary, current_id: String) -> void:
	if template_option == null:
		return
	var previous := applying
	applying = true
	template_option.clear()
	for id in rows:
		template_option.add_item(str(rows[id].get("name", id)))
		template_option.set_item_metadata(template_option.item_count - 1, id)
	_select_option_by_id(template_option, current_id)
	applying = previous

func _weights_text(value: Variant) -> String:
	if not value is Dictionary or value.is_empty():
		return ""
	var parts: Array = []
	for key in value:
		parts.append("%s:%s" % [key, value[key]])
	return ",".join(parts)

func _parse_weights(text: String) -> Dictionary:
	var result := {}
	for part in text.split(",", false):
		var bits := part.split(":", false)
		if bits.size() != 2:
			continue
		var key := bits[0].strip_edges()
		var amount := bits[1].strip_edges()
		if key.is_empty() or not amount.is_valid_int():
			continue
		result[key] = int(amount)
	return result

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _emit_changed(_unused: Variant = null) -> void:
	if not applying:
		changed.emit()
