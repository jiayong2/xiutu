extends Control

signal techniques_requested
signal back_requested
signal selected_changed(key: String)

const Spells = preload("res://gameplay/battle/spell_progression.gd")
const TRAINING = preload("res://ui/technique/spell_training.tscn")
const INSIGHT = preload("res://ui/technique/spell_insight.tscn")
const RESULT = preload("res://ui/technique/spell_result.tscn")
const COLORS := {"damage":"#FF9B8B","heal":"#9ADDB5","guard":"#9ACCF1","control":"#DDBAFA","combo":"#F2CD87","normal":"#C2D1D7"}
const CARD_COLORS := {"damage":"4A3D46","heal":"354F4D","guard":"344A5C","control":"443F55","combo":"4B4942"}
const TARGETS := {"enemy":"敌方单体","self":"自身","ally":"友方单体","all":"敌方全体","chain":"最多3名敌人"}
const SLOT_LABELS := ["①", "②"]

var service: RefCounted
var state: Dictionary
var data: Dictionary
var config: Dictionary
var selected := ""
var subview: Control
var training_result: Control
var method := "quiet"
var slot := 0
var candidate := ""

func field(key: String, surface: Control = self) -> Node:
	return surface.find_child(key,true,false)

func _ready() -> void:
	field("Back").pressed.connect(func(): back_requested.emit())
	field("Techniques").pressed.connect(func(): techniques_requested.emit())
	field("Filter").item_selected.connect(func(_index: int): _render())
	field("Equip").pressed.connect(_equip)
	field("Upgrade").pressed.connect(open_training)
	field("Insight").pressed.connect(open_insight)

func bind_data(operations: RefCounted, key: String, message: String = "") -> void:
	if service != operations:
		service = operations
		data = service.data
		config = data.spell_growth
		var filter: OptionButton = field("Filter")
		filter.clear()
		for value in ["全部","无"] + data.rules.roots:
			filter.add_item(value)
		filter.select(0)
	selected = key
	refresh_state(message)

func refresh_state(message: String = "") -> void:
	if service == null:
		return
	state = service.snapshot()
	field("Status").text = message
	field("Status").visible = not message.is_empty()
	_render()

func _render() -> void:
	var player: Dictionary = state.player
	var learned: Dictionary = player.spells
	var equipped: Array = player.spell_slots
	var count := int(data.rules.initial_slots)
	field("SlotTitle").text = "已配置法术 %d/%d" % [equipped.size(),count]
	field("SlotHint").text = "当前开放%d槽" % count
	var list: Container = field("TechniqueList")
	var grid: Container = field("SlotGrid")
	var filter: OptionButton = field("Filter")
	var element := filter.get_item_text(filter.selected)
	var keys: Array = []
	for id in learned:
		if element == "全部" or data.spells[id].element == element:
			keys.append(id)
	if not learned.has(selected) or selected not in keys:
		selected = str(keys[0]) if not keys.is_empty() else ""
	_clear(grid)
	_clear(list)
	for index in range(count):
		if index < equipped.size():
			var id: String = equipped[index]
			var entry := _entry(grid,"%s\nLv.%d" % [data.spells[id].name,learned[id]],id == selected,114)
			entry.pressed.connect(_select.bind(id,true))
		else:
			var entry := _entry(grid,"＋ 空槽",false,114)
			entry.pressed.connect(_empty_slot)
	for id in keys:
		var spell: Dictionary = data.spells[id]
		var element_text: String = "无属性" if spell.element == "无" else spell.element+"系"
		var entry := _entry(list,"%s · Lv.%d\n%s · %s · %s" % [spell.name,learned[id],element_text,_target(spell),"已装备" if id in equipped else "未装备"],id == selected,85)
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.pressed.connect(_select.bind(id))
	if keys.is_empty():
		var empty := Label.new()
		empty.text = "当前分类暂无已学法术"
		list.add_child(empty)
	field("Information").visible = not selected.is_empty()
	for action in ["Equip","Upgrade","Insight"]:
		field(action).disabled = selected.is_empty()
	if not selected.is_empty():
		_detail(data.spells[selected],int(learned[selected]),selected in equipped)
	selected_changed.emit(selected)

func _detail(spell: Dictionary, level: int, equipped: bool) -> void:
	var cap := Spells.maximum(spell)
	var mastery := int(state.player.get("spell_mastery",{}).get(selected,0))
	field("Name").text = spell.name
	field("Meta").text = "%s · Lv.%d" % [spell.get("rarity","凡品"),level]
	field("Description").text = spell.get("description","凝聚灵气，化为气弹击向敌人。" if selected=="skill_spirit_bolt" else _target(spell)+"法术")
	field("Mana").text = "灵力 %d" % spell.mp
	field("Cooldown").text = "冷却 %d" % spell.cd
	field("Target").text = _target(spell)
	field("Effects").text = _effects(spell,level)
	field("TrainingTitle").text = "修炼 · "+Spells.TITLES[level-1] if spell.has("levels") else "法术等级 · Lv.%d/%d" % [level,cap]
	field("Mastery").text = ("已圆满" if level == cap else "%d/%d" % [mastery,config.per_level]) if spell.has("levels") else "灵石升级"
	_progress(self,mastery,level==cap)
	field("Next").text = "下一级\n"+_changes(spell,level,level+1) if level < cap else _colored("已达当前等级上限","heal")
	field("Affixes").text = _affix_summary(spell,level)
	field("Equip").text = "卸下" if equipped else "装备"
	var reason := ""
	if not state.battle.is_empty():
		reason = "请先结束当前战斗"
	elif state.player.age >= state.player.lifespan:
		reason = "角色寿元已尽"
	elif not equipped and state.player.spell_slots.size() >= int(data.rules.initial_slots):
		reason = "法术槽已满，请先卸下一门法术"
	field("Equip").disabled = not reason.is_empty()
	field("Equip").tooltip_text = reason
	field("Upgrade").text = "修炼" if spell.has("levels") else "升级"

func _select(id: String, clear_filter: bool = false) -> void:
	selected = id
	if clear_filter:
		field("Filter").select(0)
	refresh_state()

func _empty_slot() -> void:
	if not selected.is_empty() and selected not in state.player.spell_slots:
		_equip()
	else:
		refresh_state("请先选择一门未装备的法术")

func _equip() -> void:
	if selected.is_empty():
		return
	var response := _request("slot",{"id":selected})
	refresh_state("" if response.success else response.message)

func open_training() -> void:
	if selected.is_empty() or is_instance_valid(subview):
		return
	_open(TRAINING)
	method = "quiet"
	var spell: Dictionary = data.spells[selected]
	var modern := spell.has("levels")
	field("Title",subview).text = ("法术修炼" if modern else "法术升级")+" · "+spell.name
	field("Methods",subview).visible = modern
	field("Duration",subview).visible = modern
	field("TrainingTotals",subview).visible = modern
	field("PreviewText",subview).visible = not modern
	for key in config.methods:
		var plan: Dictionary = config.methods[key]
		var button: Button = field("Quiet" if key=="quiet" else "Stones",subview)
		button.text = "%s\n每日熟练度 +%d · 每日灵石 %d" % [plan.name,plan.gain,plan.cost]
		button.pressed.connect(_method.bind(key))
	var days: SpinBox = field("Days",subview)
	days.max_value = int(config.max_days)
	days.value_changed.connect(func(_value: float): _training_preview())
	field("Cancel",subview).pressed.connect(_close)
	field("Confirm",subview).pressed.connect(_train)
	_training_preview()

func _method(value: String) -> void:
	method = value
	_training_preview()

func _training_preview() -> void:
	state = service.snapshot()
	var spell: Dictionary = data.spells[selected]
	var level := int(state.player.spells[selected])
	var cap := Spells.maximum(spell)
	var progress := int(state.player.get("spell_mastery",{}).get(selected,0))
	var modern := spell.has("levels")
	var confirm: Button = field("Confirm",subview)
	field("CurrentText",subview).text = "Lv.%d · %s · %s\n%s" % [level,spell.get("rarity","凡品"),spell.element,_effects(spell,level)]
	if modern:
		var remaining: int = int(config.per_level)-progress
		var mastery_line := "熟练度 %d/%d · 距下一级 %d" % [progress,config.per_level,remaining] if level<cap else "法术圆满"
		field("CurrentText",subview).text += "\n%s · %s" % [Spells.TITLES[level-1],mastery_line]
	field("MasteryBar",subview).visible = modern
	_progress(subview,progress,level==cap)
	var stages: Array[String] = []
	for index in range(1,cap+1):
		stages.append("Lv.%d · %s" % [index,_effects(spell,index) if index==1 else _changes(spell,index-1,index)])
	field("GrowthText",subview).text = "\n".join(stages)
	if modern:
		field("Quiet",subview).theme_type_variation = &"Selected" if method=="quiet" else &""
		field("Stones",subview).theme_type_variation = &"Selected" if method=="stones" else &""
		var quote: Dictionary = service.spell_training(selected,method,int(field("Days",subview).value))
		_fill_totals(subview,quote)
		field("ProgressValue",subview).text = _progress_text(quote.level,quote.progress,cap)
		field("ProgressValue",subview).add_theme_color_override("font_color",Color(COLORS.heal))
		confirm.disabled = not quote.success
		field("Status",subview).text = quote.message
	else:
		var info: Dictionary = service.skill_presentation(selected)
		field("PreviewTitle",subview).text = "灵石升级"
		field("PreviewText",subview).text = info.cost
		confirm.disabled = not info.upgrade.success
		field("Status",subview).text = info.upgrade.message if confirm.disabled else ""
	field("Status",subview).visible = not field("Status",subview).text.is_empty()

func _train() -> void:
	var confirm: Button = field("Confirm",subview)
	if confirm.disabled or is_instance_valid(training_result):
		return
	confirm.disabled = true
	var spell: Dictionary = data.spells[selected]
	var modern := spell.has("levels")
	var days := int(field("Days",subview).value)
	var quote: Dictionary = service.spell_training(selected,method,days) if modern else {}
	var response := _request("spell_train" if modern else "upgrade",{"id":selected,"method":method,"days":days})
	if response.success and modern:
		_show_result(spell,quote)
	_training_preview()
	if not response.success:
		field("Status",subview).text = response.message
		field("Status",subview).show()

func _show_result(spell: Dictionary, quote: Dictionary) -> void:
	training_result = RESULT.instantiate()
	subview.add_child(training_result)
	var cap := Spells.maximum(spell)
	var leveled: bool = quote.before != quote.level
	field("SpellName",training_result).text = spell.name
	field("LevelChange",training_result).text = "Lv.%d %s → Lv.%d %s" % [quote.before,Spells.TITLES[quote.before-1],quote.level,Spells.TITLES[quote.level-1]] if leveled else "Lv.%d · %s" % [quote.level,Spells.TITLES[quote.level-1]]
	_fill_totals(training_result,quote)
	var changes: Array[String] = []
	for index in range(quote.before+1,quote.level+1):
		changes.append("Lv.%d · %s" % [index,_changes(spell,index-1,index,true)])
		if index in Spells.AFFIX_LEVELS:
			changes.append(_colored("法术精进：解锁第%s个参悟词条槽" % ("一" if index==3 else "二"),"combo"))
	field("ChangesPanel",training_result).visible = leveled
	field("Changes",training_result).text = "法术精进\n"+"\n".join(changes)
	field("Remaining",training_result).text = "当前熟练度\n"+_colored(_progress_text(quote.level,quote.progress,cap),"heal")
	field("Confirm",training_result).pressed.connect(func():
		training_result.queue_free()
		training_result = null
		_training_preview())
	field("Confirm",training_result).grab_focus()

func _fill_totals(surface: Control, quote: Dictionary) -> void:
	field("DurationValue",surface).text = "%d日" % quote.days
	field("GainValue",surface).text = "+%d" % quote.gain
	field("GainValue",surface).add_theme_color_override("font_color",Color(COLORS.heal))
	field("CostValue",surface).text = str(quote.cost)

func open_insight() -> void:
	if selected.is_empty() or is_instance_valid(subview):
		return
	state = service.snapshot()
	var pending: Dictionary = state.player.get("spell_affix_pending",{})
	if not pending.is_empty():
		_select(pending.id,true)
	_open(INSIGHT)
	slot = int(pending.get("slot",0))
	candidate = ""
	field("Back",subview).pressed.connect(_close)
	field("Slot1",subview).pressed.connect(_choose_slot.bind(0))
	field("Slot2",subview).pressed.connect(_choose_slot.bind(1))
	field("Roll",subview).pressed.connect(_roll_affix)
	field("Keep",subview).pressed.connect(_resolve_affix.bind(false))
	field("Replace",subview).pressed.connect(_resolve_affix.bind(true))
	_insight_preview()

func _choose_slot(index: int) -> void:
	slot = index
	candidate = ""
	_insight_preview()

func _insight_preview(message: String = "") -> void:
	state = service.snapshot()
	var p: Dictionary = state.player
	var level := int(p.spells[selected])
	var spell: Dictionary = data.spells[selected]
	var supported := Spells.supports_affixes(spell)
	var unlocked := Spells.affix_slots(level) if supported or spell.has("levels") else 0
	var pending: Dictionary = p.get("spell_affix_pending",{})
	var rolled := not pending.is_empty()
	var equipped: Dictionary = p.get("spell_affixes",{}).get(selected,{})
	field("Title",subview).text = "法术参悟 · "+spell.name
	field("Subtitle",subview).text = "%s · Lv.%d · 已开启%d个词条槽" % [spell.get("rarity","凡品"),level,unlocked]
	field("CurrentSpell",subview).text = "%s Lv.%d\n%s\n灵力%d · 冷却%d · %s" % [spell.name,level,_effects(spell,level),spell.mp,spell.cd,_target(spell)]
	for index in range(2):
		var button: Button = field("Slot%d" % (index+1),subview)
		var id: String = equipped.get(str(index),"")
		var requirement: int = Spells.AFFIX_LEVELS[index]
		var slot_text: String = _affix_text(id,false) if index < unlocked else ("未开启 · Lv.%d解锁" % requirement if Spells.maximum(spell)>=requirement else "暂未开放")
		button.text = "%s %s" % [SLOT_LABELS[index],slot_text]
		button.disabled = index >= unlocked or rolled or not supported
		button.theme_type_variation = &"Selected" if index < unlocked and index == slot else &""
	field("Cost",subview).text = "参悟消耗\n灵石 ×%d（持有 %d）" % [config.affix_cost,p.spirit_stones]
	var grid: Container = field("CandidateGrid",subview)
	_clear(grid)
	var entries: Array = pending.get("candidates",[]) if rolled else config.affixes.keys() if supported else []
	for id in entries:
		var card := _entry(grid,_affix_text(id,false),id==candidate,94)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.disabled = not rolled
		card.tooltip_text = Spells.affix_effect(config.affixes[id])
		var role: String = config.affixes[id].role
		var color := Color(COLORS[role])
		var box: StyleBoxFlat = card.get_theme_stylebox("normal","Button").duplicate()
		box.bg_color = Color(CARD_COLORS[role])
		if id == candidate:
			box.border_color = color
			box.set_border_width_all(2)
		card.add_theme_stylebox_override("normal",box)
		card.add_theme_stylebox_override("disabled",box)
		card.add_theme_color_override("font_disabled_color",color)
		card.add_theme_color_override("font_color",color)
		card.pressed.connect(_choose_candidate.bind(id))
	field("CandidateTitle",subview).text = "候选参悟词条" if rolled else "参悟词条池"
	field("BeforeAffix",subview).text = "当前效果\n"+_affix_text(equipped.get(str(slot),""),true)
	field("AfterAffix",subview).text = "新效果\n"+(_affix_text(candidate,true) if not candidate.is_empty() else "请选择候选词条" if rolled else "参悟后显示")
	field("Roll",subview).visible = not rolled
	field("Roll",subview).disabled = not supported or unlocked == 0 or p.spirit_stones < config.affix_cost
	field("Keep",subview).visible = rolled
	field("Replace",subview).visible = rolled
	field("Replace",subview).disabled = candidate.is_empty()
	if message.is_empty():
		if not supported:
			message = "该法术暂未开放词条池"
		elif unlocked == 0:
			message = "达到 Lv.%d 后解锁参悟" % Spells.AFFIX_LEVELS[0]
		elif not rolled and p.spirit_stones < config.affix_cost:
			message = "灵石不足"
		else:
			message = "确认替换前保留原有词条"
	field("Status",subview).text = message

func _choose_candidate(id: String) -> void:
	candidate = id
	_insight_preview()

func _roll_affix() -> void:
	if field("Roll",subview).disabled:
		return
	var response := _request("spell_affix_roll",{"id":selected,"slot":slot})
	candidate = ""
	_insight_preview("" if response.success else response.message)

func _resolve_affix(replace: bool) -> void:
	if replace and candidate.is_empty():
		return
	var pending: Dictionary = state.player.get("spell_affix_pending",{})
	if pending.is_empty():
		return
	var response := _request("spell_affix_resolve",{"token":pending.token,"option":candidate if replace else ""})
	candidate = ""
	_insight_preview(("词条已替换" if replace else "已保留原词条") if response.success else response.message)

func _affix_summary(spell: Dictionary, level: int) -> String:
	if not Spells.supports_affixes(spell):
		return "该法术暂未开放词条池"
	var unlocked := Spells.affix_slots(level)
	if unlocked == 0:
		return "Lv.%d 解锁第一个词条槽" % Spells.AFFIX_LEVELS[0]
	var equipped: Dictionary = state.player.get("spell_affixes",{}).get(spell.id,{})
	var lines: Array[String] = []
	for index in range(unlocked):
		lines.append(SLOT_LABELS[index]+" "+_affix_text(equipped.get(str(index),""),true))
	return "\n".join(lines)

func _affix_text(id: String, styled: bool) -> String:
	if id.is_empty():
		return "未配置"
	var entry: Dictionary = config.affixes[id]
	var text: String = entry.name+(" · " if styled else "\n")+Spells.affix_effect(entry)
	return _colored(text,entry.role) if styled else text

func _open(scene: PackedScene) -> void:
	subview = scene.instantiate()
	add_child(subview)
	field("Margin").hide()

func _close() -> void:
	if not is_instance_valid(subview):
		return
	remove_child(subview)
	subview.queue_free()
	subview = null
	field("Margin").show()
	refresh_state()

func _request(action: String, args: Dictionary) -> Dictionary:
	return GameManager.request(action,args) if service == GameManager.operations else service.request(action,args)

func _target(spell: Dictionary) -> String:
	return TARGETS[spell.target] if spell.has("target") else "自身" if spell.heal > 0 or spell.guard > 0 else "敌方单体"

func _progress(surface: Control, current: int, complete: bool) -> void:
	var bar: ProgressBar = field("MasteryBar",surface)
	bar.max_value = int(config.per_level)
	bar.value = int(config.per_level) if complete else current

func _progress_text(level: int, progress: int, cap: int) -> String:
	return "Lv.%d · 登峰造极 · 法术圆满" % level if level==cap else "Lv.%d · %d/%d" % [level,progress,config.per_level]

func _effects(spell: Dictionary, level: int) -> String:
	var lines: Array[String] = []
	for line in Spells.effect_lines(spell,level,config):
		lines.append(_colored(line[1],line[0]))
	return "\n".join(lines)

func _changes(spell: Dictionary, before: int, after: int, compare: bool = false) -> String:
	var previous := Spells.effect_lines(spell,before,config)
	var lines: Array[String] = []
	var next := Spells.effect_lines(spell,after,config)
	for index in range(next.size()):
		var line: Array = next[index]
		if line not in previous:
			var text: String = line[1]
			if compare and index==0 and not previous.is_empty() and previous[0][0]==line[0]:
				text = previous[0][1]+" → "+text
			lines.append(_colored(text,line[0]))
	return " / ".join(lines)

func _colored(value: String, role: String) -> String:
	return "[color=%s]%s[/color]" % [COLORS[role],value]

func _entry(parent: Container, value: String, active: bool, height: int) -> Button:
	var button := Button.new()
	button.text = value
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size.y = height
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.theme_type_variation = &"Selected" if active else &""
	parent.add_child(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
