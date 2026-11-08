extends SceneTree

var failures := 0
var checks := 0
var output := ""
var main: Control
var gm: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func settle() -> void:
	for index in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

func capture(surface: Control, name: String, fixed: Array) -> void:
	await settle()
	for key in fixed:
		var node: Control = surface.find_child(key,true,false)
		check(node.visible and surface.get_global_rect().encloses(node.get_global_rect()),name+" / "+key+" remains visible")
	var picture := root.get_texture().get_image()
	check(picture.save_png(output.path_join(name+".png")) == OK,name+" screenshot")
	check(picture.get_size() == root.size,name+" screenshot matches window")

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	gm = root.get_node("GameManager")
	check(gm.boot_ok and gm.new_game("界面测试","金").is_empty(),"game boots")
	gm.set_process(false)
	var op: RefCounted = gm.operations
	var fixture: Dictionary = op.export_save()
	fixture.state.player.spirit_stones = 1000
	fixture.state.player.spell_mastery = {"skill_metal_edge":95}
	check(op.restore_save(fixture).is_empty(),"isolated UI fixture")
	main = load("res://ui/main/main.tscn").instantiate()
	main.page = "功法"
	root.size = Vector2i(1920,1080)
	root.add_child(main)
	await settle()
	var page: Control = main.content.get_node("TechniquePage")
	check(page.field("SlotGrid").get_child_count() == 10,"passive tab still uses its existing grid")
	page.field("Spells").pressed.emit()
	var spell: Control = page.spell_page
	check(spell.field("TechniqueList").get_child_count() == 33,"all trial spells listed")
	check(spell.field("SlotGrid").get_child_count() == 3,"only three equip slots")
	spell._select("skill_metal_edge")
	spell.field("Equip").pressed.emit()
	check("skill_metal_edge" in op.snapshot().player.spell_slots,"equip button uses real command")
	await capture(spell,"spell-main-1920",["Equip","Upgrade","Insight"])
	spell.field("Upgrade").pressed.emit()
	var training: Control = spell.subview
	spell.field("Stones",training).pressed.emit()
	spell.field("Days",training).value = 10
	await capture(training,"spell-training-1920",["Cancel","Confirm"])
	spell.field("Confirm",training).pressed.emit()
	var result: Control = spell.training_result
	check(op.snapshot().player.spells.skill_metal_edge == 3 and op.snapshot().player.spell_mastery.skill_metal_edge == 15,"two-level result uses committed growth")
	var committed: Dictionary = op.snapshot()
	spell.field("Confirm",training).pressed.emit()
	check(op.snapshot() == committed,"second click leaves training settled once")
	await capture(result,"spell-result-1920",["Confirm"])
	root.size = Vector2i(1280,720)
	await capture(result,"spell-result-1280",["Confirm"])
	spell.field("Confirm",result).pressed.emit()
	await capture(training,"spell-training-1280",["Cancel","Confirm"])
	spell.field("Cancel",training).pressed.emit()
	check(spell.field("Meta").text.contains("Lv.3"),"training return refreshes main detail")
	await capture(spell,"spell-main-1280",["Equip","Upgrade","Insight"])
	spell.field("Upgrade").pressed.emit()
	training = spell.subview
	spell.field("Days",training).value = 1
	spell.field("Confirm",training).pressed.emit()
	result = spell.training_result
	check(not spell.field("ChangesPanel",result).visible and op.snapshot().player.spell_mastery.skill_metal_edge == 23,"mastery-only result has no upgrade summary")
	spell.field("Confirm",result).pressed.emit()
	spell.field("Cancel",training).pressed.emit()
	var ready: Dictionary = op.export_save()
	ready.state.player.spells.skill_metal_edge = 5
	ready.state.player.spell_mastery.skill_metal_edge = 0
	ready.state.player.spell_affixes = {"skill_metal_edge":{"0":"mana"}}
	check(op.restore_save(ready).is_empty(),"level-five fixture with first affix")
	spell.field("Insight").pressed.emit()
	var insight: Control = spell.subview
	check(not spell.field("Slot2",insight).disabled,"second slot is open")
	spell.field("Slot2",insight).pressed.emit()
	spell.field("Roll",insight).pressed.emit()
	var pending: Dictionary = op.snapshot().player.spell_affix_pending
	check(pending.slot == 1 and op.snapshot().player.spell_affixes.skill_metal_edge.size() == 1,"preview preserves installed affix")
	spell.field("CandidateGrid",insight).get_child(0).pressed.emit()
	await capture(insight,"spell-insight-1280",["Keep","Replace"])
	root.size = Vector2i(1920,1080)
	await capture(insight,"spell-insight-1920",["Keep","Replace"])
	spell.field("Replace",insight).pressed.emit()
	check(op.snapshot().player.spell_affixes.skill_metal_edge.size() == 2,"confirmed second affix is saved")
	spell.field("Roll",insight).pressed.emit()
	var rolled: Dictionary = op.snapshot()
	spell.field("Back",insight).pressed.emit()
	check(op.snapshot() == rolled,"leaving insight preserves pending result")
	spell.field("Insight").pressed.emit()
	insight = spell.subview
	spell.field("Keep",insight).pressed.emit()
	check(op.snapshot().player.spell_affixes == rolled.player.spell_affixes and op.snapshot().player.spirit_stones == rolled.player.spirit_stones,"keep preserves installed affixes without another cost")
	spell.field("Back",insight).pressed.emit()
	check(spell.field("Affixes").text.contains("②"),"main detail shows both slots")
	spell.field("Techniques").pressed.emit()
	check(page.field("SlotGrid").get_child_count() == 10,"switch back preserves passive page")
	print("SPELL UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
