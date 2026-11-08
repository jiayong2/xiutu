extends SceneTree
const Ops = preload("res://core/operation_service.gd")
const Save = preload("res://core/save_service.gd")
var failures := 0
var checks := 0
var data: Dictionary
var base: Dictionary
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(title)
	print("%s %s" % ["PASS" if ok else "FAIL",title])
func command(op: RefCounted, action: String, args: Dictionary = {}) -> void:
	var result: Dictionary = op.request(action,args)
	check(result.success,action+": "+result.message)
func new_op(seed_value: int = 1) -> RefCounted:
	var op := Ops.new(); op.configure(data)
	op.new_game("回归散修","火",base,seed_value)
	return op
func fight(op: RefCounted) -> void:
	for turn in range(60):
		var s: Dictionary = op.snapshot()
		if s.battle.is_empty(): return
		var p: Dictionary = s.player
		if p.hp < 60 and p.inventory.get("item_healing_powder",0)>0:
			command(op,"battle_action",{"kind":"item","id":"item_healing_powder"})
		elif p.mp>=5: command(op,"battle_action",{"kind":"spell","id":"skill_spirit_bolt"})
		else: command(op,"battle_action",{"kind":"attack"})
	check(false,"battle exceeded 60 turns")
func run() -> void:
	data = root.get_node("GameManager").catalog.tables
	base = root.get_node("GameManager").repository.starting_character()
	for seed_value in [1,2,3]:
		var op := new_op(seed_value)
		command(op,"accept",{"id":"quest_qinglan_001"})
		command(op,"talk",{"id":"npc_qin_shoushan"})
		command(op,"npc_option",{"npc":"npc_qin_shoushan","option":"ask_qinglan_disturbance"})
		command(op,"travel",{"id":"area_qinglan_outskirts"})
		command(op,"investigate",{"id":"event_beast_tracks","option":"inspect_tracks"})
		command(op,"travel",{"id":"town_qinglan"})
		command(op,"npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_001"})
		command(op,"buy",{"shop":"shop_qinglan_general","item":"item_aura_powder","quantity":1})
		command(op,"buy",{"shop":"shop_qinglan_general","item":"seed_spirit_grass","quantity":1})
		command(op,"accept",{"id":"quest_qinglan_002"})
		command(op,"travel",{"id":"area_qinglan_outskirts"}); command(op,"explore"); fight(op)
		command(op,"travel",{"id":"town_qinglan"}); command(op,"claim",{"id":"quest_qinglan_002"})
		command(op,"use_item",{"id":"book_technique_iron_body"}); command(op,"slot",{"id":"technique_iron_body"})
		command(op,"travel",{"id":"cave_qinglan"}); command(op,"plant",{"plot":0,"id":"herb_spirit_grass"})
		command(op,"practice",{"days":3}); command(op,"harvest",{"plot":0}); command(op,"craft",{"id":"recipe_qi_gathering"})
		command(op,"use_item",{"id":"pill_qi_gathering"}); command(op,"promote")
		var saves := Save.new()
		var path := saves.write(op.export_save(),"user://test_saves")
		var restored := new_op()
		check(restored.restore_save(saves.read(path)).is_empty(),"midway load")
		op = restored
		command(op,"travel",{"id":"town_qinglan"}); command(op,"inn")
		command(op,"accept",{"id":"quest_qinglan_003"}); command(op,"travel",{"id":"area_qinglan_outskirts"}); command(op,"challenge"); fight(op)
		command(op,"travel",{"id":"town_qinglan"}); command(op,"npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_003"})
		check(op.snapshot().quests.quest_qinglan_003.status=="COMPLETED","full clean campaign seed %s without fixtures or debug" % seed_value)
		command(op,"travel",{"id":"town_yunxi"})
		command(op,"buy",{"shop":"shop_yunxi","item":"herb_morning_dew","quantity":2})
		command(op,"buy",{"shop":"shop_yunxi","item":"herb_calm_leaf","quantity":1})
		command(op,"travel",{"id":"cave_qinglan"}); command(op,"craft",{"id":"recipe_healing"})
		check(op.snapshot().player.inventory.pill_healing == 1,"second recipe real materials")
	# Isolated component fixtures for paths that need high resources or specific conditions.
	var op := new_op()
	var fixture: Dictionary = op.export_save()
	fixture.state.player.spirit_stones=5000
	fixture.state.player.techniques.technique_iron_body=1
	fixture.state.player.technique_slots.append("technique_iron_body")
	fixture.state.player.spells.skill_fire_bolt=1
	fixture.state.player.spell_slots.append("skill_fire_bolt")
	fixture.state.player.inventory.item_healing_powder=10
	fixture.state.mvp1=true
	fixture.state.player.realm=9
	fixture.state.player.cultivation=1000
	fixture.state.player.inventory.pill_foundation=2
	check(op.restore_save(fixture).is_empty(),"high resource fixture")
	command(op,"promote")
	check(op.snapshot().hours == 248,"foundation always spends 10 days")
	check(op.snapshot().player.realm==10 or op.snapshot().player.cultivation==800,"foundation success/failure configured")
	command(op,"travel",{"id":"town_yunxi"}) if op.snapshot().quests.get("quest_qinglan_003",{}).get("status","")=="COMPLETED" else command(op,"travel",{"id":"town_qinglan"})
	command(op,"buy",{"shop":"shop_qinglan_general","item":"equip_cloth_robe","quantity":1})
	var instance := ""
	for id in op.snapshot().player.equipment_instances:
		if id != "starting_sword": instance=id
	command(op,"equip",{"id":instance})
	var before: Dictionary = op.snapshot()
	check(not op.request("sell_equipment",{"shop":"shop_qinglan_general","id":instance}).success and op.snapshot()==before,"equipped item cannot be sold")
	command(op,"unequip",{"id":instance}); command(op,"sell_equipment",{"shop":"shop_qinglan_general","id":instance})
	check(not op.snapshot().player.equipment_instances.has(instance),"sold equipment instance removed")
	command(op,"travel",{"id":"cave_qinglan"}); command(op,"formation")
	command(op,"warehouse",{"id":"item_healing_powder"}); command(op,"warehouse",{"id":"item_healing_powder","withdraw":true})
	var upgrade_fixture: Dictionary = op.export_save()
	upgrade_fixture.state.player.inventory.material_spirit_iron=5
	check(op.restore_save(upgrade_fixture).is_empty(),"upgrade material fixture")
	command(op,"cave_upgrade")
	check(op.snapshot().cave_level==2 and op.snapshot().player.inventory.get("material_spirit_iron",0)==0,"cave upgrade consumes actual materials")
	var simulation: Dictionary = op.snapshot()
	op.clock.advance(simulation,864000,data,op.random)
	var export: Dictionary = op.export_save(); export.state=simulation; export.random=op.random.snapshot()
	var saves := Save.new(); var path := saves.write(export,"user://test_saves")
	var second := new_op()
	check(second.restore_save(saves.read(path)).is_empty() and second.snapshot()==simulation,"100-year simulation save/load exact")
	for key in simulation:
		if second.snapshot().get(key) != simulation[key]: print("LONG DIFF ",key," ",simulation[key]," / ",second.snapshot().get(key))
	# Repeated real page creation must not mutate world state.
	var gm := root.get_node("GameManager")
	gm.new_game("界面测试","金")
	var scene := load("res://ui/main/main.tscn") as PackedScene
	var main := scene.instantiate(); root.add_child(main)
	before = gm.operations.snapshot()
	main.page = "主界面"
	main._refresh()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	main._unhandled_key_input(escape)
	await process_frame
	var slider: HSlider = main.find_child("BrightnessSlider", true, false)
	check(main.page == "设置" and slider != null, "escape opens display settings")
	if slider != null:
		var saved_level: int = main.screen_brightness
		slider.drag_started.emit()
		slider.value = 70
		var dimmer: ColorRect = main.get_node("DisplayLayer/ScreenDimmer")
		check(dimmer.visible and is_equal_approx(dimmer.color.a, 0.3) and dimmer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "slider previews global dimming without blocking input")
		slider.value = 100
		check(not dimmer.visible, "100 percent restores the original screen")
		slider.value = saved_level
		slider.drag_ended.emit(false)
	main._unhandled_key_input(escape)
	await process_frame
	check(main.page == "主界面" and gm.operations.snapshot() == before, "escape returns without mutating game state")
	for page in ["主界面","角色","背包","功法","洞府","地图","任务","宗门","天下","设置","读取存档","商店","修炼","战斗"]:
		main.page=page; main._refresh()
		check(gm.operations.snapshot()==before,"page does not mutate state: "+page)
	main.queue_free()
	print("REGRESSION: %s checks, %s failures" % [checks,failures])
	quit(0 if failures==0 else 1)
