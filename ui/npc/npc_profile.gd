extends Control

signal closed

const Interaction = preload("res://world/npc_interaction.gd")
const Character = preload("res://gameplay/character/character_system.gd")
const FORTUNE_BADGE := preload("res://ui/character/fortune_badge.gd")
const STAT_LABELS := {
	"hp":"生命上限", "mp":"灵力上限", "blood":"气血上限", "attack":"攻击",
	"defense":"防御", "speed":"速度", "critical":"暴击", "critical_damage":"暴伤", "dodge":"闪避"
}
const RATIO_STATS := ["critical", "critical_damage", "dodge"]
const PARTS = preload("res://ui/character/character_page.gd").PARTS
const FRAME_SIZE := Vector2(1180, 650)

class EquipmentCard extends Label:
	const Hover := preload("res://ui/character/equipment_hover.gd")
	var definition: Dictionary
	var actor: Dictionary
	var instance: String
	var rules: Dictionary

	func bind_equipment(item: Dictionary, item_name: String, npc: Dictionary, key: String, config: Dictionary) -> void:
		definition = item
		actor = npc
		instance = key
		rules = config
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = item_name
		if not definition.has("base_stats"):
			tooltip_text += "\n" + "\n".join(Hover.details(definition, actor, instance, rules))

	func _make_custom_tooltip(_hint: String) -> Object:
		if not definition.has("base_stats"):
			return null
		return Hover.build_tooltip(self, definition, actor, instance, rules)

var catalog: Dictionary
var dossier: Dictionary
var world: Dictionary
var subject_id: String
var loadout: Dictionary

func _ready() -> void:
	resized.connect(_fit)
	_fit()
	for index in range(5):
		_field("Tab%d" % index).pressed.connect(_show_page.bind(index))
	_field("Dismiss").pressed.connect(func(): closed.emit())
	_field("Close").pressed.connect(func(): closed.emit())
	_field("LearnSpells").pressed.connect(_learned.bind(false))
	_field("LearnTech").pressed.connect(_learned.bind(true))
	_field("Family").pressed.connect(_relations.bind(true))
	_field("Contacts").pressed.connect(_relations.bind(false))
	_show_page(0)

func bind_data(state: Dictionary, data: Dictionary, id: String) -> void:
	world = state
	catalog = data
	subject_id = id
	dossier = {}
	for definition in data.prototype.npcs:
		if definition.id == id:
			dossier = definition.get("profile", {})
			break
	var npc: Dictionary = state.npcs[id]
	if npc.has("profile"):
		dossier = npc.profile
	var info := Interaction.new().presentation(state, data, id)
	_field("Subject").text = "%s · %s" % [info.name, info.realm]
	_field("Current").text = "%s\n当前人物" % info.name
	loadout = npc.get("loadout", dossier.get("loadout", {}))
	if npc.get("authored", false):
		loadout = {"techniques":npc.techniques}
	_bind_overview(npc, info)
	_skill_cards("TechniquesList", loadout.get("techniques", {}).keys(), data.techniques, "功法")
	_skill_cards("SpellsList", npc.spells.keys() if npc.get("authored", false) else dossier.get("spells", []), data.spells, "法术")
	_learned(_field("LearnTech").button_pressed)
	_relations(_field("Family").button_pressed)
	var gear := _clear("EquipmentList")
	var equipment: Dictionary = loadout.get("equipment", {})
	var uses_instances: bool = npc.get("authored", false)
	for slot in PARTS:
		var item_id: String = equipment.get(slot, "")
		var instance_id: String = slot
		if uses_instances:
			instance_id = npc.equipped.get(slot, "")
			item_id = npc.equipment_instances.get(instance_id, "")
		var item: Dictionary = data.items.get(item_id, {})
		var card := EquipmentCard.new()
		_style_card(card, "%s\n%s" % [PARTS[slot], item.get("name", "空位")], Vector2(129, 150))
		gear.add_child(card)
		if data.equipment.has(item_id):
			var actor: Dictionary = npc if uses_instances else {"equipped":{slot:instance_id}}
			card.bind_equipment(data.equipment[item_id], item.get("name", item_id), actor, instance_id, data.rules)
	_card(_clear("ArtifactList"), "暂无法宝记录", Vector2(220, 104))
	var history := _clear("HistoryList")
	for entry in dossier.get("history", []):
		_card(history, "●   %s      %s" % [entry[0], entry[1]], Vector2(0, 52), true)
	if history.get_child_count() == 0:
		_card(history, "暂无生平记录", Vector2(0, 52), true)

func _bind_overview(npc: Dictionary, info: Dictionary) -> void:
	var sources := {}
	var stats := Character.new().npc_stats(npc, dossier, catalog, sources)
	var identity := {
		"IdentityName": ["姓名", info.name],
		"IdentityAge": ["年龄 / 寿元", "%d / %d" % [int(npc.age), preload("res://world/world_simulator.gd").npc_lifespan(npc,catalog)]],
		"IdentityRace": ["种族", dossier.get("race", "暂无")],
		"IdentitySect": ["宗门", dossier.get("sect", "暂无")],
		"IdentityRole": ["身份", info.identity],
		"IdentityOrigin": ["出身", dossier.get("origin", "暂无")],
		"IdentityRoot": ["灵根", dossier.get("root", "暂无")],
		"IdentityMentor": ["师承", dossier.get("mentor", "暂无")],
		"IdentityPersonality": ["性格", dossier.get("personality", "暂无")],
		"IdentityRank": ["评级", info.rank]
	}
	for key in identity:
		_set_overview_field(key, identity[key][0], identity[key][1])

	_field("Vitals").text = "法修：%s   体修：%s" % [info.realm, dossier.get("body_realm", "暂无")]
	var resources: Dictionary = dossier.get("resources", {})
	for pair in [["Health", "hp"], ["Mana", "mp"], ["Blood", "blood"]]:
		var key: String = pair[1]
		var bar: ProgressBar = _field(pair[0] + "Bar")
		bar.max_value = float(stats.get(key, 1))
		var visible_resource: bool = key == "hp" or npc.realm > 0
		bar.value = clampf(float(npc.get(key, resources.get(key, 0))), 0, bar.max_value) if visible_resource else 0.0
		var value_label: Label = _field(pair[0] + "Value")
		value_label.text = "%d / %d" % [bar.value, bar.max_value] if visible_resource else "—"
		value_label.mouse_filter = Control.MOUSE_FILTER_PASS
		value_label.tooltip_text = _source_tooltip(key, sources.get(key, {})) if visible_resource else ""

	var foundation: Dictionary = dossier.get("foundation", {}).duplicate()
	foundation.merge(npc.get("attributes", {}), true)
	for entry in [
		["QiSea", "气海", "qi_sea"], ["Meridians", "经脉", "meridians"],
		["Bones", "根骨", "bones"], ["Physique", "体魄", "physique"],
		["SpiritSea", "识海", "spirit_sea"], ["Soul", "神魂", "soul"]
	]:
		_set_overview_field(entry[0], entry[1], foundation.get(entry[2], "暂无"))

	for entry in [
		["Attack", "攻击", "attack"], ["Defense", "防御", "defense"],
		["Speed", "速度", "speed"], ["Critical", "暴击", "critical"],
		["CriticalDamage", "暴伤", "critical_damage"], ["Dodge", "闪避", "dodge"]
	]:
		var key: String = entry[2]
		_set_overview_field(entry[0], entry[1], _stat_value(key, stats[key]) if stats.has(key) else "暂无")
		var field: Label = _field(entry[0])
		field.mouse_filter = Control.MOUSE_FILTER_PASS
		field.tooltip_text = _source_tooltip(key, sources.get(key, {}))

	var innate: Array = dossier.get("innate_fortune", []).duplicate()
	var acquired: Array = dossier.get("acquired_fortune", []).duplicate()
	var catalog_script = preload("res://gameplay/character/player_fortunes.gd")
	for id in npc.get("fortunes", {}):
		var fortune: Dictionary = catalog_script.DEFINITIONS[id].duplicate()
		fortune.description = "\n".join(catalog_script.describe(fortune))
		if fortune.kind == "innate":
			innate.append(fortune)
		else:
			acquired.append(fortune)
	_bind_fortune("Innate", "先天气运", innate)
	_bind_fortune("Acquired", "后天气运", acquired)

func _stat_value(key: String, value: float, bonus: bool = false) -> String:
	if key in RATIO_STATS:
		var unit := " 个百分点" if bonus else "%"
		return str(snappedf(value * 100.0, 0.01)) + unit
	return str(int(value))

func _source_tooltip(key: String, sources: Dictionary) -> String:
	if sources.is_empty():
		return ""
	var lines := PackedStringArray([STAT_LABELS[key]])
	for source in sources:
		var amount: float = sources[source]
		var prefix := "+" if source != "基础值" and amount > 0 else ""
		lines.append("%s：%s%s" % [source, prefix, _stat_value(key, amount, source != "基础值")])
	return "\n".join(lines)

func _set_overview_field(key: String, caption: String, value: Variant) -> void:
	var field: Label = _field(key)
	field.text = "%s：%s" % [caption, str(int(value)) if value is float and value == floor(value) else str(value)]
	field.tooltip_text = field.text

func _bind_fortune(prefix: String, caption: String, entries: Array) -> void:
	var grid: GridContainer = _field(prefix + "Grid")
	_field(prefix + "Title").text = "%s（%d）" % [caption, entries.size()]
	for index in range(grid.get_child_count()):
		var tag: Label = grid.get_child(index)
		tag.visible = index < entries.size() or (index == 0 and entries.is_empty())
		tag.mouse_filter = Control.MOUSE_FILTER_PASS
		tag.tooltip_text = ""
		if index >= entries.size():
			tag.text = "暂无"
			tag.remove_theme_stylebox_override("normal")
			tag.add_theme_color_override("font_color", Color("345c51"))
			continue
		var fortune: Dictionary = entries[index]
		tag.text = fortune.name
		FORTUNE_BADGE.apply(tag, fortune)
		var lines := PackedStringArray([fortune.name])
		for key in fortune.get("bonuses", {}):
			var amount: float = fortune.bonuses[key]
			var sign_text := "+" if amount > 0 else ""
			lines.append("%s %s%s" % [STAT_LABELS[key], sign_text, _stat_value(key, amount, true)])
		tag.tooltip_text = fortune.get("description", "\n".join(lines))

func _field(key: String) -> Node:
	return find_child(key, true, false)

func _fit() -> void:
	var frame: Control = _field("Frame")
	var factor := minf((size.x - 24) / FRAME_SIZE.x, (size.y - 24) / FRAME_SIZE.y)
	frame.scale = Vector2.ONE * maxf(0.05, factor)
	frame.position = (size - FRAME_SIZE * frame.scale) / 2.0

func _show_page(index: int) -> void:
	for tab in range(5):
		_field("Page%d" % tab).visible = tab == index
		_field("Tab%d" % tab).set_pressed_no_signal(tab == index)

func _clear(key: String) -> Container:
	var list: Container = _field(key)
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	return list

func _card(parent: Container, caption: String, minimum: Vector2, left: bool = false) -> void:
	var card := Label.new()
	_style_card(card, caption, minimum, left)
	parent.add_child(card)

func _style_card(card: Label, caption: String, minimum: Vector2, left: bool = false) -> void:
	card.custom_minimum_size = minimum
	card.text = caption
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_theme_color_override("font_color", Color("345c51"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f8faf2")
	style.border_color = Color("a4bfb0")
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	card.add_theme_stylebox_override("normal", style)

func _skill_cards(key: String, ids: Array, definitions: Dictionary, category: String) -> void:
	var list := _clear(key)
	for id in ids:
		if definitions.has(id):
			var caption: String = definitions[id].name
			if category == "功法":
				caption += " · %d级" % int(loadout.techniques[id])
			_card(list, "%s\n%s" % [category, caption], Vector2(102, 80))
	if list.get_child_count() == 0:
		_card(list, "暂无%s记录" % category, Vector2(160, 80))

func _learned(techniques: bool) -> void:
	_field("LearnSpells").set_pressed_no_signal(not techniques)
	_field("LearnTech").set_pressed_no_signal(techniques)
	var key := "techniques" if techniques else "spells"
	var category := "功法" if techniques else "法术"
	_field("LearnedTitle").text = "已学习" + category
	var ids: Array = loadout.get("techniques", {}).keys() if techniques else dossier.get("spells", [])
	if world.npcs[subject_id].get("authored", false):
		ids = world.npcs[subject_id][key].keys()
	_skill_cards("LearnedList", ids, catalog[key], category)

func _relations(family: bool) -> void:
	_field("Family").set_pressed_no_signal(family)
	_field("Contacts").set_pressed_no_signal(not family)
	var list := _clear("RelationList")
	_field("Stem").visible = not family
	if family:
		_card(list, "暂无亲族记录", Vector2(180, 110))
		return
	var npc: Dictionary = world.npcs[subject_id]
	var relation := Interaction.relation_label(npc, world.player.id)
	_card(list, "◆\n%s（你）\n%s" % [world.player.name, relation], Vector2(180, 110))
	var contacts: Dictionary = dossier.get("contacts", {})
	for id in contacts:
		if world.npcs.has(id):
			_card(list, "◆\n%s\n%s" % [world.npcs[id].name, contacts[id]], Vector2(180, 110))
