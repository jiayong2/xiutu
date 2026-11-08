extends SceneTree

const Values := preload("res://gameplay/inventory/equipment_values.gd")
const Hover := preload("res://ui/character/equipment_hover.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	var op: RefCounted = gm.operations
	gm.new_game("装备验收","木")
	var config: Dictionary = op.data
	var rows := 0
	var ids := {}
	for item in config.equipment.values():
		if not item.has("base_stats"):
			continue
		rows += 1
		check(Values.SLOTS.has(item.slot) and Hover.QUALITY.has(item.quality) and Hover.ELEMENT.has(item.element),"equipment display vocabulary")
		check(item.tier in ["凡器","灵纹器","宝器"] and item.nurture_level == 0 and item.nurture_max == 5,"equipment growth and tier")
		check(config.items[item.id].buy_price == item.value and config.items[item.id].description == item.description,"equipment and item data agree")
		for key in item.base_stats:
			check(Values.STATS.has(key),"known stat")
		for entry in item.traits:
			check(not ids.has(entry.id) and Values.TRAIT_TEXT.has(entry.type),"unique trait and display template")
			ids[entry.id] = true
	check(rows == 32 and config.artifacts.size() == 8,"catalog counts")
	for item in config.artifacts.values():
		check(not ids.has(item.ability.id) and item.ability.effects.has(item.refine_field) and item.refine_level == 0,"artifact data contract")
		ids[item.ability.id] = true
	check(op.request("claim_qi_equipment").success,"claim succeeds")
	check(not op.request("claim_qi_equipment").success,"claim is one-time")
	var instances: Dictionary = op.snapshot().player.equipment_instances
	check(instances.size() == 9,"eight new instances plus legacy starter")
	var old_mp: int = op.stats().mp
	var belt := ""
	for instance in instances:
		if instance.begins_with("qi_set_"):
			check(op.request("equip",{"id":instance}).success,"equip " + instance)
			if instances[instance] == "equip_v1_spirit_belt":
				belt = instance
	check(op.snapshot().player.equipped.size() == 8,"all eight slots active")
	var equipped_mp: int = op.stats().mp
	check(equipped_mp > old_mp,"mana increases after equipping")
	check(op.request("unequip",{"id":belt}).success and op.stats().mp == equipped_mp - 14,"unequip removes base and trait")
	check(not op.request("unequip",{"id":belt}).success,"unequip cannot remove another item")
	check(op.request("equip",{"id":belt}).success,"reequip")
	var save: Dictionary = op.export_save()
	save.state.player.equipment_nurture = {belt:3}
	check(op.restore_save(save).is_empty() and op.stats().mp == equipped_mp + 1,"growth restores and applies once")
	var item: Dictionary = config.equipment.equip_v1_spirit_belt
	var player: Dictionary = op.snapshot().player
	check("灵力 +11" in Hover.details(item,player,belt,config.rules),"detail uses the same computed stat")
	var button := Button.new()
	root.add_child(button)
	Hover.attach(button,item,player,belt,config.rules)
	var tooltip: Control = button.call("_make_custom_tooltip",item.name)
	root.add_child(tooltip)
	var bars := tooltip.find_children("*","ProgressBar",true,false)
	check(bars.size() == 1 and bars[0].value == 3 and bars[0].max_value == 5,"tooltip progress matches instance")
	tooltip.queue_free()
	button.queue_free()
	check(op.request("nurture_equipment",{"id":belt}).success and Values.level(op.snapshot().player,belt) == 4,"nurture advances selected instance once")
	check(op.request("nurture_equipment",{"id":belt}).success and Values.level(op.snapshot().player,belt) == 5,"nurture reaches maximum")
	check(not op.request("nurture_equipment",{"id":belt}).success and Values.level(op.snapshot().player,belt) == 5,"nurture rejects beyond maximum")
	check(not op.request("nurture_equipment",{"id":"starting_sword"}).success,"legacy template cannot nurture")
	check(op.restore_save(op.export_save()).is_empty() and Values.level(op.snapshot().player,belt) == 5,"nurture round trip")
	var page: Control = load("res://ui/character/character_page.tscn").instantiate()
	var viewport := SubViewport.new()
	root.add_child(viewport)
	viewport.add_child(page)
	for dimensions in [Vector2i(1920,1080),Vector2i(1280,720)]:
		viewport.size = dimensions
		page.bind_data(op,"info")
		await process_frame
		await process_frame
		var info: ScrollContainer = page.field("InfoPage")
		var root_text: Label = page.field("RootText")
		info.ensure_control_visible(root_text)
		await process_frame
		check(info.get_global_rect().grow(1).encloses(root_text.get_global_rect()),"info root text reachable at %s" % dimensions)
		page.bind_data(op,"equipment","",belt)
		await process_frame
		var wear: Button = page.field("EquipmentAction")
		var nurture: Button = page.field("NurtureAction")
		check(wear.get_parent() == nurture.get_parent() and absf(wear.position.y-nurture.position.y) < 1.0 and nurture.disabled,"nurture is beside equip and disabled at cap")
		var detail: VBoxContainer = page.field("EquipmentSections")
		var detail_bars := detail.find_children("*","ProgressBar",true,false)
		check(detail_bars.size() == 1 and detail_bars[0].value == 5,"detail renders actual nurture level")
		var scroll: ScrollContainer = page.field("DetailScroll")
		await process_frame
		var descriptions := detail.find_children("*","RichTextLabel",true,false)
		var description: RichTextLabel = descriptions.back()
		check(description.get_theme_font_size("normal_font_size") == (27 if dimensions.y == 1080 else 18),"detail font follows window height")
		check(not scroll.get_v_scroll_bar().visible and scroll.get_global_rect().grow(1).encloses(description.get_global_rect()),"equipment detail fits without scrolling at %s: view=%s, body=%s, description=%s, scrollbar=%s" % [dimensions,scroll.get_global_rect(),detail.get_global_rect(),description.get_global_rect(),scroll.get_v_scroll_bar().visible])
	var hover_button := Button.new()
	viewport.add_child(hover_button)
	for candidate in config.equipment.values():
		if not candidate.has("base_stats"):
			continue
		Hover.attach(hover_button,candidate,player,"",config.rules)
		var card: Control = hover_button.call("_make_custom_tooltip",candidate.name)
		var popup_height := card.get_combined_minimum_size().y
		viewport.add_child(card)
		await process_frame
		await process_frame
		await process_frame
		var lines := card.find_children("*","RichTextLabel",true,false)
		var last: RichTextLabel = lines.back()
		check(card.find_children("*","ScrollContainer",true,false).is_empty() and card.size.y <= viewport.size.y and last.size.y >= last.get_content_height() and card.get_global_rect().grow(1).encloses(last.get_global_rect()),"complete tooltip at 1280x720: " + candidate.name)
		var icon: Panel = card.get_child(0).get_child(0).get_child(0)
		check(icon.size == Vector2(42,42),"square tooltip icon: " + candidate.name)
		var bottom_gap := card.get_global_rect().end.y - last.get_global_rect().end.y
		check(absf(popup_height-card.size.y) <= 1.0 and absf(bottom_gap-8.0) <= 1.0,"popup height matches content: %s (initial=%s, actual=%s, gap=%s)" % [candidate.name,popup_height,card.size.y,bottom_gap])
		card.queue_free()
	viewport.queue_free()
	print("Equipment V1: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

