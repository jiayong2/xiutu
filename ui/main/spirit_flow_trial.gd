extends AcceptDialog
## Developer-only preview. No OperationService commands are issued.
const Flow := preload("res://gameplay/cultivation/spirit_flow.gd")
const Simulation := preload("res://gameplay/cultivation/spirit_flow_simulation.gd")
const DEFAULT_PATH := "res://data/cultivation/spirit_flow.json"
const OVERRIDE_PATH := "user://spirit_flow_trial.json"
const ENVIRONMENTS := ["town","cave","advanced_cave","sparse","rich","starved"]
const MODES := ["natural","practice","retreat"]
const DURATIONS := [1,24,240,8640]
var parameters: TextEdit
var output: RichTextLabel
var environment: OptionButton
var practice_mode: OptionButton
var quality: OptionButton
var route: OptionButton
var duration: OptionButton
var aptitude: SpinBox
var foundation: SpinBox
var stones: SpinBox
var formation: CheckButton
var current_character: CheckButton

func _ready() -> void:
	title = "开发者 · 灵气流转试算"
	ok_button_text = "关闭"
	var column := VBoxContainer.new()
	add_child(column)
	var selectors := HBoxContainer.new()
	column.add_child(selectors)
	environment = _options(selectors,["青岚镇","一级洞府","高级洞府","灵气稀薄","灵气浓郁","长期不足"])
	practice_mode = _options(selectors,["自然吐纳","主动修炼","闭关"])
	route = _options(selectors,["法修","体修"])
	quality = _options(selectors,["普通灵根","优良灵根","上乘灵根","天灵根"])
	duration = _options(selectors,["1 小时","1 日","10 日","1 年"])
	duration.select(1)
	var setup := HBoxContainer.new()
	column.add_child(setup)
	aptitude = _number(setup,"灵性或根骨",20,100)
	foundation = _number(setup,"经脉或筋骨与体魄",20,100)
	stones = _number(setup,"投入试算灵石",0,100)
	formation = CheckButton.new()
	formation.text = "聚灵阵"
	setup.add_child(formation)
	current_character = CheckButton.new()
	current_character.text = "读取当前角色快照"
	setup.add_child(current_character)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons,"模拟",_simulate)
	_button(buttons,"恢复默认配置",_load_config.bind(DEFAULT_PATH))
	_button(buttons,"读取本地配置",_load_config.bind(OVERRIDE_PATH))
	_button(buttons,"保存本地配置",_save_config)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	parameters = TextEdit.new()
	parameters.custom_minimum_size = Vector2(620,500)
	parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(parameters)
	output = RichTextLabel.new()
	output.custom_minimum_size = Vector2(600,500)
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(output)
	_load_config(DEFAULT_PATH)

func open() -> void:
	popup_centered(Vector2i(1460,800))
	_simulate()

func _options(parent: Container, names: Array) -> OptionButton:
	var picker := OptionButton.new()
	for label in names:
		picker.add_item(label)
	parent.add_child(picker)
	return picker

func _number(parent: Container, title_text: String, initial: int, maximum: int) -> SpinBox:
	var label := Label.new()
	label.text = title_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.max_value = maximum
	spin.value = initial
	parent.add_child(spin)
	return spin

func _button(parent: Container, title_text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = title_text
	parent.add_child(button)
	button.pressed.connect(handler)

func _load_config(path: String) -> void:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		output.text = "读取失败：" + path
		return
	parameters.text = file.get_as_text()
	var rules := _rules()
	if not rules.is_empty():
		aptitude.value = rules.default_aptitude
		quality.select(["ordinary","fine","superior","heavenly"].find(rules.default_root_quality))

func _rules() -> Dictionary:
	var parser := JSON.new()
	if parser.parse(parameters.text) != OK or not parser.data is Dictionary:
		output.text = "配置不是有效的 JSON 对象。第 %d 行：%s" % [parser.get_error_line(),parser.get_error_message()]
		return {}
	var data: Dictionary = GameManager.catalog.tables
	if data.is_empty():
		output.text = "游戏配置尚未加载。"
		return {}
	var error: String = Simulation.validate(parser.data,data.techniques,data.rules.roots)
	if not error.is_empty():
		output.text = error
		return {}
	return parser.data

func _save_config() -> void:
	if _rules().is_empty():
		return
	var file := FileAccess.open(OVERRIDE_PATH,FileAccess.WRITE)
	if file == null:
		output.text = "无法保存本地试算配置。"
		return
	file.store_string(parameters.text)
	file.close()
	output.text = "已保存本地试算配置。此配置只用于开发者模拟。"

func _simulate() -> void:
	var rules := _rules()
	if rules.is_empty():
		return
	var data: Dictionary = GameManager.catalog.tables
	var trial_route: String = "body" if route.selected==1 else "qi"
	if trial_route == "body" and practice_mode.selected == 0:
		output.text = "体修只支持主动淬体或体修闭关。请选择对应模式。"
		return
	var id: String = "technique_iron_body" if trial_route=="body" else "technique_qi_flow"
	var player := {"root":"木","technique_slots":[id],"techniques":{id:1},"growth":{"attributes":{
		"meridians":int(foundation.value),"bones":int(foundation.value),"physique":int(foundation.value)}}}
	var source_label: String = "试算角色 · %s一级" % data.techniques[id].name
	if current_character.button_pressed:
		var snapshot: Dictionary = GameManager.operations.snapshot()
		if snapshot.is_empty():
			output.text = "先创建角色，或取消读取当前角色。"
			return
		player = snapshot.player
		source_label = "当前角色快照 · %s" % player.name
	var traits := {"root_quality":["ordinary","fine","superior","heavenly"][quality.selected],
		"spirituality":int(aptitude.value),"constitution":int(aptitude.value)}
	var focus := "balance"
	if current_character.button_pressed:
		traits.root_quality = player.traits.root_quality
		traits.spirituality = player.traits.aptitudes.spirituality
		traits.constitution = player.traits.aptitudes.constitution
		focus = player.growth.focus[trial_route]
	var profile := Flow.profile(player,trial_route,data.techniques,rules,traits)
	var row: Dictionary = rules.environments[ENVIRONMENTS[environment.selected]]
	var hours: int = DURATIONS[duration.selected]
	var result := Simulation.simulate(profile,row,rules,MODES[practice_mode.selected],hours*3600,int(stones.value),formation.button_pressed,focus)
	var lines := PackedStringArray(["%s · %d 游戏小时" % [source_label,hours],
		"共用正式流转规则的独立试算，未计角色境界和根基上限。",
		"结束浓度：%s    修为：%.3f    温养：%.3f" % [result.grade,result.cultivation,result.nurture],
		"吸纳 / 运转 / 炼化能力：%.3f / %.3f / %.3f 灵气点每小时" % [
			profile.absorption/10000.0,profile.channel/10000.0,profile.refinement/10000.0],
		"炼化损耗比例：%.2f%%" % (profile.loss/100.0),""])
	for field in [["start","起始储量"],["end","结束储量"],["recovered","天地补充"],["released","灵石释放"],
			["stone_unreleased","灵石未释放量"],["transferred","阵法从周边转入"],["diffused","向周边逸散"],
			["available","环境可供提取"],["absorbed","实际吸纳"],["channelled","实际运转"],
			["processed","实际进入炼化"],["channel_return","经脉退回"],["refinement_return","功法退回"],
			["refinement_loss","炼化损耗"],["refined","有效炼化"]]:
		lines.append("%s：%.3f 灵气点" % [field[1],float(result[field[0]])/Flow.QUANTA_PER_POINT])
	output.text = "\n".join(lines)
