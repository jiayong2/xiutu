extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(tab: String,category: String,key: String)
const HOVER := preload("res://ui/character/equipment_hover.gd")
const PARTS := preload("res://gameplay/inventory/equipment_values.gd").SLOTS
const CULTIVATION := preload("res://gameplay/cultivation/cultivation_system.gd")
const FORTUNES := preload("res://gameplay/character/player_fortunes.gd")
const FORTUNE_BADGE := preload("res://ui/character/fortune_badge.gd")
const CHARACTER := preload("res://gameplay/character/character_system.gd")
var service: RefCounted
var state: Dictionary
var data: Dictionary
var tab: String="info"
var category: String=""
var selected: String=""
func field(key: String) -> Node:return find_child(key,true,false)
var spacious_detail := false

func _ready() -> void:
	resized.connect(_resize_equipment_detail)
	_resize_equipment_detail()
	field("Back").pressed.connect(func():navigate.emit("主界面"))
	for pair in [["InfoTab","info"],["EquipmentTab","equipment"],["ArtifactTab","artifact"]]:
		field(pair[0]).pressed.connect(_tab.bind(pair[1]))
	field("EquipmentAction").pressed.connect(_act)
	field("NurtureAction").pressed.connect(func():action_requested.emit("nurture_equipment",{"id":selected}))
	field("ClaimQiEquipment").pressed.connect(func():action_requested.emit("claim_qi_equipment",{}))
func bind_data(operations: RefCounted,saved_tab: String="info",saved_category: String="",key: String="",message: String="") -> void:
	service=operations;state=service.snapshot();data=service.data;tab=saved_tab;category=saved_category;selected=key
	field("Message").text=message
	_info();_equipment();_tab(tab)
func _tab(value: String) -> void:
	tab=value
	field("InfoPage").visible=tab=="info";field("EquipmentPage").visible=tab=="equipment";field("ArtifactPage").visible=tab=="artifact"
	for pair in [["InfoTab","info"],["EquipmentTab","equipment"],["ArtifactTab","artifact"]]:_style(field(pair[0]),tab==pair[1])
	selection_changed.emit(tab,category,selected)
func _style(button: Control,active: bool) -> void:
	var box:=StyleBoxFlat.new();box.bg_color=Color("70988a") if active else Color("415b67")
	button.add_theme_stylebox_override("normal",box)
func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()
func _realm(level: int) -> String:
	return CULTIVATION.realm_name(level,"qi",data)
func _info() -> void:
	var p: Dictionary=state.player
	field("CharacterName").text=p.name
	refresh_growth(p)
	var aptitude_values: Array = []
	var aptitude_lines := PackedStringArray(["六维资质（0–100）"])
	var aptitude_names: PackedStringArray = field("Radar").attribute_names
	for key in CHARACTER.APTITUDE_KEYS:
		var value := clampi(int(p.traits.aptitudes[key]) + FORTUNES.modifier(p,"stat",key,"fixed"),0,100)
		aptitude_lines.append("%s：%d" % [aptitude_names[aptitude_values.size()],value])
		aptitude_values.append(value)
	field("Radar").set_values(aptitude_values)
	field("Radar").tooltip_text="\n".join(aptitude_lines)
	var combat_grid: GridContainer=field("CombatGrid")
	for entry in [["CritChance","crit_chance","暴击率"],["CritDamage","crit_multiplier","暴击伤害"]]:
		var label: Label=combat_grid.get_node(entry[0])
		label.text="%s %s%%" % [entry[2],data.rules[entry[1]]*100]
		label.tooltip_text="来源：现有战斗规则配置"
	_render_traits("TalentGrid", p, "innate", "暂无先天天赋")
	_render_traits("StatusGrid", p, "acquired", "暂无后天气运")
	var guard: Dictionary = state.battle.get("status", {}).get("guard", {})
	var battle_status: Label = field("BattleStatus")
	battle_status.visible = not guard.is_empty()
	if battle_status.visible:
		battle_status.text = "战斗状态 · 土甲（%d 回合）" % guard.turns
		battle_status.tooltip_text = "土甲术：防御 +%d" % guard.amount
	field("RootText").text="%s · %s
对应属性法术伤害 +%s%%" % [p.root,CHARACTER.ROOT_QUALITIES[p.traits.root_quality],10]
	field("RootText").tooltip_text="单属性灵根：%s
对应属性法术伤害加成10%%；基础法术不受影响。
灵根品质决定法修吸纳能力。" % p.root
func refresh_time(snapshot: Dictionary) -> void:
	var previous: Dictionary = state.player.get("fortunes",{})
	var current: Dictionary = snapshot.player.get("fortunes",{})
	state = snapshot
	if previous != current:
		_info()
	else:
		refresh_growth(snapshot.player)

func refresh_growth(player: Dictionary) -> void:
	var cultivation: RefCounted=service.cultivation
	var stats: Dictionary=service.stats()
	field("Age").text="年龄 %d / 寿元 %d" % [player.age,player.lifespan]
	var required: int=cultivation.requirement(player,"qi",data)
	for entry in [["Health","生命",player.hp,stats.hp],["Vitality","气血",player.blood,stats.blood],
			["Mana","灵力",player.mp,stats.mp],["Cultivation","修为",player.cultivation,required]]:
		field(entry[0]+"Text").text="%s %d / %s" % [entry[1],entry[2],str(int(entry[3])) if entry[3]>0 else "已达上限"]
		field(entry[0]).max_value=maxi(1,int(entry[3]));field(entry[0]).value=entry[2]
	field("VitalityText").tooltip_text="气血上限受体魄影响。当前尚无消耗气血的主动招式。"
	var combat_grid: GridContainer=field("CombatGrid")
	for entry in [["Attack","attack","攻击"],["Defense","defense","防御"],["Speed","speed","速度"],["MaxHealth","hp","生命上限"],["MaxMana","mp","灵力上限"]]:
		var label: Label=combat_grid.get_node(entry[0])
		label.text="%s %d" % [entry[2],int(stats[entry[1]])]
		label.tooltip_text=service.character_stat_tooltip(entry[1])
	field("Realm").text="%s    %s" % [_realm(player.realm),cultivation.body_realm_name(player,data)]
	field("Realm").tooltip_text="法修境界与体修境界分别成长。"
	var quality: Dictionary=player.growth.get("breakthrough_quality",{})
	if quality.has("qi"):
		field("Realm").tooltip_text+="\n筑基品质："+str({"base":"人道","middle":"地道","high":"天道"}[quality.qi])
	if quality.has("body"):
		field("Realm").tooltip_text+="\n锻骨品质："+str({"base":"凡品","middle":"上品","high":"极品"}[quality.body])
	var names: Array=["气海","经脉","筋骨","体魄"]
	var index := 0
	for route in ["qi","body"]:
		var cap: int=cultivation.attribute_cap(player,route,data)
		for key in CULTIVATION.GROWTH_ATTRIBUTES[route]:
			var label: Label=field("Aptitude%d" % index)
			var effective := int(player.growth.attributes[key]) + FORTUNES.modifier(player,"stat",key,"fixed")
			label.text="%s %d / %d" % [names[index],effective,cap]
			label.tooltip_text="通过%s温养提升，突破后提高成长上限。" % ("法修" if route=="qi" else "体修")
			index+=1
	var mental := preload("res://gameplay/character/mental_attributes.gd")
	for key in mental.KEYS:
		var label: Label = field("Aptitude%d" % index)
		label.text = "%s %d / %d" % ["识海" if key=="spirit_sea" else "神魂",mental.effective(player,data)[key],mental.cap(key,cultivation.attribute_cap(player,"qi",data),data.progression)]
		label.tooltip_text = "影响神识感知与威压。" if key=="spirit_sea" else "影响神识威压与抵抗。"
		index += 1
func _render_traits(key: String, player: Dictionary, kind: String, empty_text: String) -> void:
	var flow: HFlowContainer = field(key)
	_clear(flow)
	for id in player.get("fortunes", {}):
		var definition: Dictionary = FORTUNES.DEFINITIONS[id]
		if definition.kind != kind and not (kind == "acquired" and definition.kind == "negative"):
			continue
		var panel := PanelContainer.new()
		panel.custom_minimum_size.y = 30
		var label := Label.new()
		label.text = definition.name
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size",16)
		FORTUNE_BADGE.apply(label, definition, panel)
		panel.add_child(label)
		var record: Dictionary = player.fortunes[id]
		var lines := FORTUNES.describe(definition)
		lines.append("来源：%s" % record.source)
		if not FORTUNES.is_active(player,id):
			lines.append("已持有，未生效（同时生效的传承已达上限）")
		if record.has("expires_at"):
			var hours := ceili((int(record.expires_at) - service.clock.seconds(state)) / 3600.0)
			lines.append("查看时剩余 %d 游戏小时" % hours)
		panel.tooltip_text = "\n".join(lines)
		flow.add_child(panel)
	if flow.get_child_count() == 0:
		var empty := Label.new()
		empty.text = empty_text
		flow.add_child(empty)
func _supported(key: String) -> bool:
	for definition in data.equipment.values():
		if definition.slot==key:return true
	return false
func _category(key: String,from_slot: bool=false) -> void:
	category=key
	if from_slot:selected=str(state.player.equipped.get(key,""))
	elif not selected.is_empty():
		var item: String=state.player.equipment_instances.get(selected,"")
		if not data.equipment.has(item) or (not key.is_empty() and data.equipment[item].slot!=key):selected=str(state.player.equipped.get(key,""))
	_equipment();selection_changed.emit(tab,category,selected)
func _select(key: String) -> void:
	selected=key;_equipment();selection_changed.emit(tab,category,selected)
func _equipment() -> void:
	var p: Dictionary=state.player
	field("ClaimQiEquipment").visible = not p.get("qi_equipment_claimed",false)
	_clear(field("EquipmentSlots"));_clear(field("Categories"));_clear(field("EquipmentGrid"))
	for part in PARTS:
		var slot: Button=preload("res://ui/character/equipment_slot.tscn").instantiate()
		var instance: String=p.equipped.get(part,"")
		slot.text=PARTS[part]+"
"+(data.items[p.equipment_instances[instance]].name if not instance.is_empty() else "空" if _supported(part) else "暂未开放")
		slot.disabled=not _supported(part);slot.tooltip_text="" if _supported(part) else "现有系统不支持该部位"
		if not instance.is_empty():
			HOVER.attach(slot,data.equipment[p.equipment_instances[instance]],p,instance,data.rules)
		slot.pressed.connect(_category.bind(part,true));_style(slot,part==category);field("EquipmentSlots").add_child(slot)
	for part in [""]+PARTS.keys():
		var button:=Button.new();button.text="全部" if part.is_empty() else PARTS[part]
		button.custom_minimum_size=Vector2(80,48);button.pressed.connect(_category.bind(part,false))
		_style(button,part==category);field("Categories").add_child(button)
	var shown:=0
	for instance in p.equipment_instances:
		var id: String=p.equipment_instances[instance]
		if not data.equipment.has(id):continue
		if not category.is_empty() and data.equipment[id].slot!=category:continue
		var tile: Button=preload("res://ui/character/inventory_item_slot.tscn").instantiate()
		tile.text="

%s
%s" % [data.items[id].name,"已装备" if instance in p.equipped.values() else "未装备"]
		tile.tooltip_text=data.items[id].name;tile.pressed.connect(_select.bind(instance));_style(tile,instance==selected)
		HOVER.attach(tile,data.equipment[id],p,instance,data.rules)
		field("EquipmentGrid").add_child(tile);shown+=1
	field("InventoryHeading").text="背包装备 · %d 件" % shown
	if shown==0:
		var empty:=Label.new();empty.text="此分类暂无装备";field("EquipmentGrid").add_child(empty)
	_detail()
func _resize_equipment_detail() -> void:
	var spacious := size.y >= 900.0
	if spacious_detail == spacious:
		return
	spacious_detail = spacious
	if service != null:
		_detail()

func _detail() -> void:
	var p: Dictionary=state.player
	field("EquipmentAction").disabled=true
	field("EquipmentReason").hide()
	field("NurtureAction").disabled=true
	field("NurtureAction").tooltip_text="请选择可温养的装备"
	var sections: VBoxContainer = field("EquipmentSections")
	_clear(sections)
	var has_item: bool = p.equipment_instances.has(selected)
	var uses_sections: bool = has_item and data.equipment[p.equipment_instances[selected]].has("base_stats")
	sections.visible = uses_sections
	for key in ["EquipmentIcon","EquipmentName","EquipmentDescription"]:
		field(key).visible = not uses_sections
	if not has_item:
		field("EquipmentName").text="请选择装备"
		field("EquipmentDescription").text="当前槽位为空" if not category.is_empty() else "点击背包装备查看详情"
		field("EquipmentReason").text="";return
	var id: String=p.equipment_instances[selected]
	var definition: Dictionary=data.equipment[id]
	var item: Dictionary=data.items[id]
	var equipped: bool=selected in p.equipped.values()
	var lines: Array[String]=["部位："+str(PARTS.get(definition.slot,definition.slot)),"品质："+str({"common":"普通","uncommon":"精良","rare":"稀有"}.get(item.rarity,item.rarity))]
	lines.append_array(HOVER.details(definition,p,selected,data.rules))
	lines.append(item.description);lines.append("已装备" if equipped else "未装备")
	field("EquipmentName").text=item.name;field("EquipmentDescription").text="
".join(lines)
	if uses_sections:
		sections.add_theme_constant_override("separation",8 if spacious_detail else 2)
		HOVER.populate(sections,definition,p,selected,data.rules,true,27 if spacious_detail else 18)
		var nurture: Dictionary = service.equipment_availability(selected,"nurture_equipment")
		field("NurtureAction").disabled = not nurture.success
		field("NurtureAction").tooltip_text = "提升一层温养" if nurture.success else nurture.message
	var action: String="unequip" if equipped else "equip"
	var result: Dictionary=service.equipment_availability(selected,action)
	field("EquipmentAction").text="卸下" if equipped else "装备"
	field("EquipmentAction").disabled=not result.success
	field("EquipmentReason").text="" if result.success else result.message
	field("EquipmentReason").visible = not result.success
func _act() -> void:
	if field("EquipmentAction").disabled:return
	action_requested.emit("unequip" if selected in state.player.equipped.values() else "equip",{"id":selected})
