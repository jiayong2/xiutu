@tool
extends PanelContainer

const Config := preload("res://core/npc_generation/generation_config.gd")
const Service := preload("res://core/npc_generation/generation_service.gd")
const Templates := preload("res://core/npc_generation/generation_templates.gd")
const Store := preload("res://core/npc_generation/generation_store.gd")
const Form := preload("res://addons/npc_editor/generation_form.gd")
const Fortune := preload("res://gameplay/character/player_fortunes.gd")
const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const Model := preload("res://core/npc_definitions.gd")

signal committed(rows: Dictionary, ids: Array)

var data: Dictionary = {}
var overrides: Dictionary = {}
var templates: Dictionary = {}
var form: Form
var service := Service.new()
var preview: Dictionary = {}
var preview_fingerprint := ""
var stale := true
var busy := false
var save_path: String = Model.PATH
var template_dir: String = Templates.DIR

@onready var rules_pane: VBoxContainer = $Layout/Body/RulesPane
@onready var preview_pane: PanelContainer = $Layout/Body/PreviewPane
@onready var preview_list: ItemList = $Layout/Body/Side/RosterCard/Content/PreviewList
@onready var list_count: Label = $Layout/Body/Side/RosterCard/Content/ListHeader/ListCount
@onready var preview_index: Label = $Layout/Body/PreviewPane/Content/PreviewHeader/PreviewIndex
@onready var preview_name: Label = $Layout/Body/PreviewPane/Content/PreviewName
@onready var preview_meta: Label = $Layout/Body/PreviewPane/Content/PreviewMeta
@onready var preview_summary: GridContainer = $Layout/Body/PreviewPane/Content/DetailScroll/Detail/SummaryRows
@onready var detail: Label = $Layout/Body/PreviewPane/Content/DetailScroll/Detail/DetailText
@onready var save_template_button: Button = $Layout/Body/Side/TemplateCard/Content/TemplateActions/SaveTemplate
@onready var load_template_button: Button = $Layout/Actions/LoadTemplate
@onready var generate_button: Button = $Layout/Actions/Generate
@onready var reroll_button: Button = $Layout/Actions/Reroll
@onready var save_batch_button: Button = $Layout/Actions/SaveBatch
@onready var count_label: Label = $Layout/Summary/CountLabel
@onready var passed_label: Label = $Layout/Summary/PassedLabel
@onready var failed_label: Label = $Layout/Summary/FailedLabel
@onready var status: Label = $Layout/Status

func _ready() -> void:
	_apply_generation_theme()
	_style_portrait()
	_connect_rule_tabs()
	if preview_list.item_selected.is_connected(_select_preview):
		return
	preview_list.item_selected.connect(_select_preview)
	save_template_button.pressed.connect(save_template)
	load_template_button.pressed.connect(load_selected_template)
	generate_button.pressed.connect(func(): generate_preview(false))
	reroll_button.pressed.connect(func(): generate_preview(true))
	save_batch_button.pressed.connect(save_batch)

func setup(catalog: Dictionary, saved_rows: Dictionary) -> void:
	data = catalog
	overrides = saved_rows
	if form == null:
		form = Form.new()
		form.changed.connect(mark_stale)
	_reload_templates()
	var config: Dictionary = templates.get("template_custom", Config.defaults())
	form.build(_rule_roots(), data, config)
	form.fill_templates(templates, str(config.id))
	if form.template_option and not form.template_option.item_selected.is_connected(_template_chosen):
		form.template_option.item_selected.connect(_template_chosen)
	if not form.copy_requested.is_connected(_copy_current_template):
		form.copy_requested.connect(_copy_current_template)
		form.delete_requested.connect(_delete_current_template)
	_clear_preview("规则已载入。点击「生成预览」只在内存中构造人物。")
	_refresh_actions()

func collect_config() -> Dictionary:
	return form.collect() if form != null else Config.defaults()

func generate_preview(reroll: bool = false) -> Dictionary:
	if busy or data.is_empty() or form == null:
		return preview
	busy = true
	_refresh_actions()
	var config := collect_config()
	if reroll:
		config.erase("seed")
	preview = service.generate(config, data, {"overrides": overrides})
	preview_fingerprint = str(preview.get("fingerprint", ""))
	stale = false
	if preview.get("config", {}).has("seed") and form.texts.has("seed"):
		var restore: bool = form.applying
		form.applying = true
		form.texts["seed"].text = str(preview.config.seed)
		form.applying = restore
	_fill_list()
	_refresh_summary()
	busy = false
	_refresh_actions()
	return preview

func save_batch() -> Dictionary:
	if not can_save() or busy:
		status.text = "当前预览不能保存。"
		return {"error": status.text, "rows": overrides}
	busy = true
	_refresh_actions()
	var result := Store.commit(preview.get("npcs", []), data, overrides, save_path)
	busy = false
	if result.error.is_empty():
		var ids: Array = []
		for npc in preview.npcs:
			ids.append(npc.id)
		overrides = result.rows
		status.text = "已保存 %d 人到初始定义。" % ids.size()
		committed.emit(result.rows, ids)
		_clear_preview(status.text)
	else:
		status.text = result.error
	_refresh_actions()
	return result

func save_template() -> String:
	if form == null:
		return "规则表单未就绪"
	var config := collect_config()
	var error := Templates.write_one(config, Templates.path_for(str(config.id), template_dir))
	status.text = "模板已保存。" if error.is_empty() else error
	if error.is_empty():
		_reload_templates()
		form.fill_templates(templates, str(config.id))
	return error

func load_selected_template() -> String:
	var id: String = form._selected_template_id() if form != null else ""
	if not templates.has(id):
		status.text = "找不到模板。"
		return status.text
	form.apply(templates[id])
	mark_stale()
	status.text = "已加载模板：" + str(templates[id].name)
	return ""

func copy_template(new_id: String, new_name: String) -> String:
	var error := Templates.copy_as(collect_config(), new_id, new_name, template_dir)
	if error.is_empty():
		_reload_templates()
		form.fill_templates(templates, new_id)
		form.apply(templates[new_id])
		status.text = "已复制模板。"
		mark_stale()
	else:
		status.text = error
	return error

func delete_template(id: String) -> String:
	var error := Templates.delete_one(id, template_dir)
	status.text = "已删除模板。" if error.is_empty() else error
	if error.is_empty():
		_reload_templates()
		var fallback: String = templates.keys()[0] if not templates.is_empty() else "template_custom"
		form.fill_templates(templates, fallback)
		if templates.has(fallback):
			form.apply(templates[fallback])
		mark_stale()
	return error

func can_save() -> bool:
	if form == null or stale or busy:
		return false
	return preview.get("ok", false) == true and int(preview.get("passed", 0)) > 0 and int(preview.get("failed", 0)) == 0 and Config.fingerprint(collect_config()) == preview_fingerprint

func mark_stale() -> void:
	if stale and preview.is_empty():
		_refresh_summary()
		_refresh_actions()
		return
	stale = true
	if not preview.is_empty():
		status.text = "规则已改，旧预览已过期，请重新生成后再保存。"
	_refresh_actions()

func _template_chosen(_index: int) -> void:
	if form.applying:
		return
	load_selected_template()

func _rule_roots() -> Dictionary:
	return {
		"template": $Layout/Body/Side/TemplateCard/Content/TemplateHost,
		"template_actions": $Layout/Body/Side/TemplateCard/Content/TemplateActions,
		"batch": $Layout/Body/Side/BatchCard/Content/BatchHost,
		"basic": $Layout/Body/RulesPane/RulesTabs/基础属性/BasicRules,
		"cultivation": $Layout/Body/RulesPane/RulesTabs/修炼/CultivationRules,
		"fortune": $Layout/Body/RulesPane/RulesTabs/气运/FortuneRules,
		"gear": $Layout/Body/RulesPane/RulesTabs/装备法宝/GearRules,
		"skill": $Layout/Body/RulesPane/RulesTabs/功法法术/SkillRules,
	}

func _reload_templates() -> void:
	var loaded := Templates.load_all(template_dir)
	templates = loaded.rows if loaded.error.is_empty() else {}
	if not loaded.error.is_empty():
		status.text = loaded.error

func _copy_current_template() -> void:
	var config := collect_config()
	var suffix := "_copy"
	var new_id := str(config.id)
	if not new_id.ends_with(suffix):
		new_id += suffix
	copy_template(new_id, str(config.name) + "副本")

func _delete_current_template() -> void:
	delete_template(form._selected_template_id() if form != null else "")

func _fill_list() -> void:
	preview_list.clear()
	for npc in preview.get("npcs", []):
		preview_list.add_item("%s    %s" % [npc.name, Cultivation.npc_realm_label(npc, data)])
		preview_list.set_item_metadata(preview_list.item_count - 1, npc)
	list_count.text = "%d 人" % preview_list.item_count
	if preview_list.item_count > 0:
		preview_list.select(0)
		_select_preview(0)
	else:
		_show_preview_summary([])
		preview_index.text = ""
		preview_name.hide()
		preview_meta.hide()
		var errors := _error_text()
		detail.text = errors if not errors.is_empty() else "没有生成人物。"

func _select_preview(index: int) -> void:
	if index < 0 or index >= preview_list.item_count:
		return
	var npc: Dictionary = preview_list.get_item_metadata(index)
	preview_index.text = "%02d / %02d" % [index + 1, preview_list.item_count]
	preview_name.text = str(npc.get("name", ""))
	preview_name.visible = not preview_name.text.is_empty()
	preview_meta.text = "%s · %s" % [str(npc.get("role", "")), Cultivation.npc_realm_label(npc, data)]
	preview_meta.visible = not str(npc.get("role", "")).is_empty() or not Cultivation.npc_realm_label(npc, data).is_empty()
	var stats: Dictionary = service.preview_stats(npc, data) if not npc.is_empty() else {}
	var innate: Array = []
	var acquired: Array = []
	for id in npc.get("fortune_ids", []):
		var row: Dictionary = Fortune.DEFINITIONS.get(id, {})
		var label: String = "%s（%s）" % [row.get("name", id), row.get("quality", "")]
		if row.get("kind") == "innate":
			innate.append(label)
		else:
			acquired.append(label)
	var techniques: Array = []
	for id in npc.get("techniques", {}):
		techniques.append("%s Lv.%s" % [data.techniques.get(id, {}).get("name", id), npc.techniques[id]])
	var spells: Array = []
	for id in npc.get("spells", {}):
		spells.append("%s Lv.%s" % [data.spells.get(id, {}).get("name", id), npc.spells[id]])
	var gear: Array = []
	for slot in npc.get("equipped", {}):
		var instance: String = str(npc.equipped[slot])
		var item_id: String = str(npc.get("equipment_instances", {}).get(instance, ""))
		gear.append("%s %s" % [slot, data.equipment.get(item_id, {}).get("name", item_id)])
	var artifacts: Array = []
	for id in npc.get("artifact_ids", []):
		artifacts.append(str(data.artifacts.get(id, {}).get("name", id)))
	var foundation: Array = []
	for key in Config.FOUNDATION_KEYS:
		foundation.append("%s %s" % [key, npc.profile.foundation.get(key, 0)])
	_show_preview_summary([
		["年龄", npc.get("age", "")],
		["性格", npc.profile.get("personality", "")],
		["灵根", npc.profile.get("root", "")],
		["先天气运", "%s 条" % innate.size()],
		["后天气运", "%s 条" % acquired.size()],
		["装备", "%s 件" % gear.size()],
		["法宝", "%s 件" % artifacts.size()],
		["功法", "%s 部" % techniques.size()],
		["法术", "%s 门" % spells.size()],
	])
	detail.text = "\n".join([
		"姓名：%s" % npc.get("name", ""),
		"性别：%s" % npc.profile.get("gender", ""),
		"身份：%s" % npc.get("role", ""),
		"境界：%s（%s）" % [Cultivation.npc_realm_label(npc, data), npc.profile.get("body_realm", "")],
		"天资：%s" % npc.profile.get("rank", ""),
		"根基：%s" % " / ".join(foundation),
		"底值 生命%s 灵力%s 攻击%s 防御%s 速度%s" % [npc.profile.base.get("hp", 0), npc.profile.base.get("mp", 0), npc.profile.base.get("attack", 0), npc.profile.base.get("defense", 0), npc.profile.base.get("speed", 0)],
		"最终攻击：%s" % stats.get("attack", "—"),
		"先天气运：%s" % ("、".join(innate) if not innate.is_empty() else "无"),
		"后天气运：%s" % ("、".join(acquired) if not acquired.is_empty() else "无"),
		"功法：%s" % ("、".join(techniques) if not techniques.is_empty() else "无"),
		"已装备功法：%s" % ("、".join(npc.get("technique_slots", [])) if not npc.get("technique_slots", []).is_empty() else "无"),
		"法术：%s" % ("、".join(spells) if not spells.is_empty() else "无"),
		"已装备法术：%s" % ("、".join(npc.get("spell_slots", [])) if not npc.get("spell_slots", []).is_empty() else "无"),
		"装备：%s" % ("、".join(gear) if not gear.is_empty() else "无"),
		"法宝：%s" % ("、".join(artifacts) if not artifacts.is_empty() else "无"),
		"物品：无（本阶段不生成背包堆叠）",
		"所在地点：%s" % npc.get("location", ""),
		"校验：通过",
	])

func _show_preview_summary(rows: Array) -> void:
	for child in preview_summary.get_children():
		preview_summary.remove_child(child)
		child.queue_free()
	for row in rows:
		var caption := Label.new()
		caption.text = row[0]
		caption.add_theme_color_override("font_color", Color("#5D7A74"))
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview_summary.add_child(caption)
		var value := Label.new()
		value.text = str(row[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		preview_summary.add_child(value)
	preview_summary.visible = not rows.is_empty()

func _error_text() -> String:
	var lines: Array = []
	for issue in preview.get("config_issues", []) + preview.get("npc_issues", []):
		lines.append("%s：%s" % [issue.get("code", ""), issue.get("message", "")])
	return "\n".join(lines)

func _clear_preview(message: String) -> void:
	_show_preview_summary([])
	preview = {}
	preview_fingerprint = ""
	stale = true
	preview_list.clear()
	list_count.text = "0 人"
	preview_index.text = ""
	preview_name.text = ""
	preview_name.visible = false
	preview_meta.text = ""
	preview_meta.visible = false
	detail.text = message
	status.text = message
	_refresh_summary()
	_refresh_actions()

func _refresh_summary() -> void:
	var config := collect_config() if form != null else {"count": 0}
	count_label.text = "预计生成：%s" % int(config.get("count", 0))
	passed_label.text = "校验成功：%s" % int(preview.get("passed", 0))
	failed_label.text = "失败：%s" % int(preview.get("failed", 0) + preview.get("config_issues", []).size())

func _connect_rule_tabs() -> void:
	var tabs: TabContainer = $Layout/Body/RulesPane/RulesTabs
	var buttons := $Layout/Body/RulesPane/TabButtons.get_children()
	for index in buttons.size():
		var button: Button = buttons[index]
		button.pressed.connect(func():
			tabs.current_tab = index
			button.set_pressed_no_signal(true)
		)
	tabs.tab_changed.connect(func(selected: int):
		for index in buttons.size():
			buttons[index].set_pressed_no_signal(index == selected)
	)
	buttons[tabs.current_tab].set_pressed_no_signal(true)

func _apply_generation_theme() -> void:
	var result := Theme.new()
	result.default_font_size = 18
	var ink := Color("#214B44")
	var border := Color("#8EB7AB")
	for kind in ["Button", "OptionButton", "LineEdit", "Label", "ItemList", "CheckButton", "TabContainer", "SpinBox"]:
		result.set_font_size("font_size", kind, 18)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.set_color(key, kind, ink)
	var page_box := _flat_box(Color("#D9EAE4"), Color(0, 0, 0, 0), 8, 8)
	page_box.set_border_width_all(0)
	add_theme_stylebox_override("panel", page_box)
	for kind in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var fill := Color("#ABD6C8") if state in ["hover", "pressed", "focus"] else Color("#CBE2D9")
			result.set_stylebox(state, kind, _flat_box(fill, border, 10, 6))
		result.set_color("font_disabled_color", kind, Color("#607A74"))
	result.set_type_variation("GenerationCard", "PanelContainer")
	result.set_stylebox("panel", "GenerationCard", _flat_box(Color("#EDF5F1"), border, 12, 12))
	result.set_type_variation("GenerationStepButton", "Button")
	result.set_stylebox("normal", "GenerationStepButton", _flat_box(Color("#CBE2D9"), border, 4, 4))
	result.set_stylebox("normal", "LineEdit", _flat_box(Color("#FDFDFC"), border, 4, 4))
	result.set_stylebox("focus", "LineEdit", _flat_box(Color("#FDFDFC"), Color("#548E7D"), 4, 4))
	result.set_stylebox("read_only", "LineEdit", _flat_box(Color("#EDF5F1"), border, 6, 3))
	var plain := StyleBoxEmpty.new()
	for state in ["normal", "pressed", "hover", "hover_pressed", "disabled", "disabled_pressed", "focus"]:
		result.set_stylebox(state, "CheckButton", plain)
	result.set_stylebox("panel", "ItemList", _flat_box(Color("#EDF5F1"), border, 4, 4))
	result.set_stylebox("selected", "ItemList", _flat_box(Color("#ABD6C8"), border, 4, 2))
	result.set_stylebox("selected_focus", "ItemList", _flat_box(Color("#ABD6C8"), border, 4, 2))
	result.set_stylebox("panel", "TabContainer", _flat_box(Color("#EDF5F1"), border, 8, 6))
	result.set_constant("buttons_width", "SpinBox", 0)
	theme = result

func _style_portrait() -> void:
	var portrait: PanelContainer = $Layout/Body/PreviewPane/Content/Portrait
	portrait.add_theme_stylebox_override("panel", _flat_box(Color("#CBE2D9"), Color("#2F7469"), 6, 6))

func _flat_box(fill: Color, border: Color, margin_x: int, margin_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box

func _refresh_actions() -> void:
	var ready := form != null and not busy
	generate_button.disabled = not ready
	reroll_button.disabled = not ready
	save_template_button.disabled = not ready
	load_template_button.disabled = not ready
	save_batch_button.disabled = not can_save()
