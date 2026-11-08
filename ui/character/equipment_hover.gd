extends Button

const Values := preload("res://gameplay/inventory/equipment_values.gd")
const QUALITY := {"下品":"7D8992","中品":"268652","上品":"276DA8","极品":"8245AF"}
const ELEMENT := {"none":["无属性","7A8790"],"metal":["金","B18A31"],"wood":["木","24854C"],"water":["水","2878BD"],"fire":["火","C45132"],"earth":["土","97722C"],"wind":["风","268B80"],"thunder":["雷","9251BB"],"ice":["冰","4397BA"],"five_elements":["五行","45685E"]}
const STAT_COLORS := {"hp":"C14F51","mp":"416DB7","attack":"B45A36","defense":"287E60","spirit_sea":"557BC0","soul":"8553A7"}
const REALMS := ["凡人","炼气期","筑基期"]
var definition: Dictionary
var player: Dictionary
var rules: Dictionary
var instance: String

static func details(item: Dictionary, actor: Dictionary, key: String, config: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var values := Values.base_stats(item,actor,key,config)
	for stat in values:
		if values[stat] != 0:
			lines.append("%s %+d" % [Values.STATS[stat],values[stat]])
	if item.has("recommended_realm"):
		var realms: Array[String] = []
		for tier in item.recommended_realm:
			realms.append(REALMS[int(tier)])
		lines.append("适用境界：" + "/".join(realms))
		if Values.factor(item,actor,config) < 1.0:
			lines.append("当前越阶发挥：%d%%" % roundi(Values.factor(item,actor,config)*100))
	else:
		lines.append("装备条件：炼气%d层" % item.realm)
	return lines

static func attach(button: Button, item: Dictionary, actor: Dictionary, key: String, config: Dictionary) -> void:
	if not item.has("base_stats"):
		return
	button.set_script(load("res://ui/character/equipment_hover.gd"))
	button.set("definition",item)
	button.set("player",actor)
	button.set("instance",key)
	button.set("rules",config)
	button.tooltip_text = item.name

func _make_custom_tooltip(_hint: String) -> Object:
	return build_tooltip(self, definition, player, instance, rules)

static func build_tooltip(anchor: Control, definition: Dictionary, player: Dictionary, instance: String, rules: Dictionary) -> Control:
	var panel := PanelContainer.new()
	const CARD_WIDTH := 340.0
	var surface := _style("EAF0E7","A5C2B1",8)
	panel.custom_minimum_size.x = CARD_WIDTH
	panel.add_theme_stylebox_override("panel",surface)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",3)
	panel.add_child(body)
	populate(body,definition,player,instance,rules)
	# Give the text its wrapping width before Godot measures the popup.
	var text_width := CARD_WIDTH - surface.get_minimum_size().x
	for child in body.get_children():
		if child is RichTextLabel:
			child.custom_minimum_size.x = text_width
			child.size.x = text_width
		elif child is HBoxContainer:
			var icon: Control = child.get_child(0)
			var title: RichTextLabel = child.get_child(1)
			title.custom_minimum_size.x = text_width - icon.get_combined_minimum_size().x - child.get_theme_constant("separation")
			title.size.x = title.custom_minimum_size.x
	anchor.add_child(panel)
	panel.size = panel.get_combined_minimum_size()
	anchor.remove_child(panel)
	return panel

static func populate(body: VBoxContainer, definition: Dictionary, player: Dictionary, instance: String, rules: Dictionary, detail := false, detail_font := 18) -> void:
	var spacious := detail and detail_font > 18
	var quality: String = QUALITY[definition.quality]
	var element: Array = ELEMENT[definition.element]
	var icon := Panel.new()
	var icon_size := 80.0 if spacious else (56.0 if detail else 42.0)
	icon.custom_minimum_size = Vector2(icon_size,icon_size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.add_theme_stylebox_override("panel",_style("D4E4D8",quality,0))
	if detail:
		var preview := PanelContainer.new()
		preview.custom_minimum_size.y = icon_size + 12.0
		preview.add_theme_stylebox_override("panel",_style("EFF4ED","A5C2B1",6))
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation",8)
		header.add_child(icon)
		var title := "[font_size=%d][b]%s[/b][/font_size]" % [detail_font + 4,_color(definition.name,quality)]
		_line(header,title + "\n" + _color(definition.tier + " · " + definition.quality,quality))
		preview.add_child(header)
		body.add_child(preview)
	else:
		var header := HBoxContainer.new()
		header.add_child(icon)
		body.add_child(header)
		_line(header,_color(definition.name + "\n" + definition.tier + "·" + definition.quality,quality),true)
	_line(body,"部位：" + Values.SLOTS[definition.slot] + "    五行：" + _color(element[0],element[1]))
	var realms: Array[String] = []
	for tier in definition.recommended_realm:
		realms.append(REALMS[int(tier)])
	_line(body,"适用境界：" + "/".join(realms))
	var scale := Values.factor(definition,player,rules)
	if scale < 1.0:
		_line(body,"当前越阶发挥：%d%%" % roundi(scale*100))
	if not detail or spacious:
		_line(body,"基础属性",true)
	var values := Values.base_stats(definition,player,instance,rules)
	var stats: Array[String] = []
	for key in values:
		var value: int = values[key]
		if value != 0:
			stats.append(Values.STATS[key] + " " + _color("%+d" % value,STAT_COLORS.get(key,"25875C")))
	_line(body,("基础属性  " if detail and not spacious else "") + "    ".join(stats),detail and not spacious)
	if not definition.traits.is_empty():
		if not detail or spacious:
			_line(body,"器蕴效果",true)
		for entry in definition.traits:
			var title := _color(str(entry.name),element[1])
			var line: String = Values.TRAIT_TEXT[entry.type] % Values.trait_amount(definition,entry,player,rules)
			if entry.type in ["control_resist","wood_reduction"]:
				line += "（尚未接入战斗）"
			if spacious:
				_line(body,title)
				_line(body,line)
			else:
				_line(body,("器蕴  " if detail else "") + title + "  " + line,detail)
	_line(body,"温养与状态",true)
	var current := Values.level(player,instance)
	var maximum := int(definition.nurture_max)
	var growth: Array = rules.equipment_growth_percent
	var level_text := ("层数：%d/%d" if detail else "温养层数：%d/%d") % [current,maximum]
	var bonus_text := _color(("基础属性 +%d%%" if detail else "当前：基础属性 +%d%%") % growth[current],"25875C")
	_line(body,level_text + "    " + bonus_text)
	var bar := ProgressBar.new()
	bar.max_value = maximum
	bar.value = current
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	bar.add_theme_stylebox_override("background",_style("C9DED2","C9DED2",0))
	bar.add_theme_stylebox_override("fill",_style("25875C","25875C",0))
	body.add_child(bar)
	_line(body,"已温养至圆满" if current == maximum else "下一层：基础属性 +%d%%" % growth[current+1])
	var status := "已穿戴" if instance in player.equipped.values() else "未穿戴"
	_line(body,status + "    " + _color("%d灵石" % definition.value,"A2762D"))
	_line(body,_color(definition.description,"738E81"))
	if detail:
		for label in body.find_children("*","RichTextLabel",true,false):
			label.add_theme_font_size_override("normal_font_size",detail_font)
	
static func _style(background: String, border: String, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(background)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_content_margin_all(margin)
	return style

static func _line(parent: Control, content: String, section := false) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("default_color",Color("45685E"))
	if section:
		label.add_theme_stylebox_override("normal",_style("D4E4D8","D4E4D8",2))
	label.text = content
	parent.add_child(label)

static func _color(content: String, color: String) -> String:
	return "[color=#%s]%s[/color]" % [color,content]

