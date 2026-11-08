extends SceneTree
const Ops = preload("res://core/operation_service.gd")
const Save = preload("res://core/save_service.gd")
var count := 0
var failures := 0
var op: RefCounted
var base: Dictionary
var data: Dictionary
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	count += 1
	if not ok: failures += 1; push_error(text)
	print("%s %s" % ["PASS" if ok else "FAIL",text])
func command(action: String, args: Dictionary = {}) -> bool:
	var result: Dictionary = op.request(action,args)
	if not result.success: print("COMMAND REJECTED ",action," ",result.message)
	return result.success
func fresh(seed_value: int = 1) -> void:
	op = Ops.new()
	op.configure(data)
	check(op.new_game("无名散修","金",base,seed_value).is_empty(),"new game")
func state() -> Dictionary:
	return op.snapshot()
func edit_fixture(callback: Callable) -> void:
	var payload: Dictionary = op.export_save()
	callback.call(payload.state)
	var error: String = op.restore_save(payload)
	check(error.is_empty(),"isolated test fixture restore: " + error)
func fight() -> void:
	var rounds := 0
	while not state().battle.is_empty() and rounds < 100:
		var p: Dictionary = state().player
		if p.hp < 50 and p.inventory.get("item_healing_powder",0)>0:
			command("battle_action",{"kind":"item","id":"item_healing_powder"})
		elif p.mp >= 5:
			command("battle_action",{"kind":"spell","id":"skill_spirit_bolt"})
		else: command("battle_action",{"kind":"attack"})
		rounds += 1
	check(rounds < 100,"battle terminates")
func run() -> void:
	var manager := root.get_node("GameManager")
	data = manager.catalog.tables
	base = manager.repository.starting_character()
	check(manager.boot_ok,"content catalog loaded")
	var initial := {}
	for i in range(10):
		fresh()
		var p: Dictionary = state().player
		p.erase("id")
		if i == 0: initial = p
		check(p == initial,"10 identical initializations")
	check(op.stats().attack == 24 and state().player.inventory.item_healing_powder == 2,"T001 initial equipment/resources")
	check(command("accept",{"id":"quest_qinglan_001"}),"accept quest001")
	check(state().quests.quest_qinglan_001.progress == 0,"accept does not complete objective")
	command("talk",{"id":"npc_qin_shoushan"})
	command("npc_option",{"npc":"npc_qin_shoushan","option":"ask_qinglan_disturbance"})
	command("travel",{"id":"area_qinglan_outskirts"})
	command("investigate",{"id":"event_beast_tracks","option":"inspect_tracks"})
	command("travel",{"id":"town_qinglan"})
	command("npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_001"})
	var before: Dictionary = state()
	check(not command("claim",{"id":"quest_qinglan_001"}) and state() == before,"T002 reward once")
	command("buy",{"shop":"shop_qinglan_general","item":"item_aura_powder","quantity":1})
	check(state().player.spirit_stones == 132 and state().stocks.shop_qinglan_general.item_aura_powder == 9,"T003 trade reconciles")
	check(state().npcs.npc_liu_qinghe.wealth == 218,"merchant receives purchase money")
	before = state()
	check(not command("buy",{"shop":"shop_qinglan_spells","item":"equip_iron_sword","quantity":99}) and state() == before,"T004 insufficient funds atomic")
	for qty in [0,-1,1.5,"1"]:
		check(not command("buy",{"shop":"shop_qinglan_general","item":"item_aura_powder","quantity":qty}),"invalid trade quantity")
	command("accept",{"id":"quest_qinglan_002"})
	command("travel",{"id":"area_qinglan_outskirts"})
	command("explore")
	check(state().battle.monster == "monster_gray_wolf","first quest exploration guaranteed wolf")
	fight()
	check(state().quests.quest_qinglan_002.progress == 1 and state().player.inventory.material_wolf_fang == 1,"wolf kill event and loot")
	before = state()
	check(not command("battle_action",{"kind":"attack"}) and state() == before,"T005 no repeat settlement")
	command("travel",{"id":"town_qinglan"})
	command("sell",{"shop":"shop_qinglan_general","item":"material_wolf_fang","quantity":1,"confirmed":true})
	before = state()
	check(not command("claim",{"id":"quest_qinglan_002"}) and state() == before,"T006 missing tooth does not consume/reward")
	edit_fixture(func(s): s.player.inventory.material_wolf_fang = 1)
	command("claim",{"id":"quest_qinglan_002"})
	command("use_item",{"id":"book_technique_iron_body"})
	command("slot",{"id":"technique_iron_body"})
	check(op.stats().hp == 140 and op.stats().defense == 10,"T008 equip passive once")
	command("slot",{"id":"technique_iron_body"})
	check(op.stats().hp == 120,"T008 unequip recalculates")
	edit_fixture(func(s): s.player.inventory.book_technique_qi_flow = 1)
	before = state()
	check(not command("use_item",{"id":"book_technique_qi_flow"}) and state() == before,"T007 duplicate learning rejected")
	command("buy",{"shop":"shop_qinglan_general","item":"seed_spirit_grass","quantity":1})
	command("travel",{"id":"cave_qinglan"})
	command("plant",{"plot":0,"id":"herb_spirit_grass"})
	command("practice",{"days":1}); command("practice",{"days":1})
	check(not command("harvest",{"plot":0}),"T009 immature at 2 days")
	command("practice",{"days":1}); command("harvest",{"plot":0})
	before = state()
	check(not command("harvest",{"plot":0}) and state() == before and state().player.inventory.herb_spirit_grass == 3,"T010 harvest once")
	var hours: int = state().hours
	command("craft",{"id":"recipe_qi_gathering"})
	check(state().hours == hours+24 and state().player.inventory.herb_spirit_grass == 1,"T012 craft consumes and advances time")
	before = state()
	check(not command("craft",{"id":"recipe_qi_gathering"}) and state() == before,"T011 insufficient materials atomic")
	command("use_item",{"id":"pill_qi_gathering"})
	edit_fixture(func(s): s.player.inventory.pill_qi_gathering = 1)
	before = state()
	check(not command("use_item",{"id":"pill_qi_gathering"}) and state() == before,"T013 daily pill limit")
	if state().player.cultivation < 100: command("practice",{"days":3})
	hours = state().hours
	command("promote")
	check(state().player.realm == 2 and state().hours == hours+24,"T014 advance one realm")
	var request_id := "test-idempotency"
	check(op.request("practice",{"days":1},request_id).success,"operation first request")
	before = state()
	check(not op.request("practice",{"days":1},request_id).success and state() == before,"operation duplicate rejected")
	var saves := Save.new()
	var path: String = saves.write(op.export_save(),"user://test_saves")
	check(not path.is_empty(),"save revision written")
	var restored: Dictionary = saves.read(path)
	var copy := Ops.new(); copy.configure(data)
	check(copy.restore_save(restored).is_empty() and copy.snapshot() == state(),"T016 state restored exactly")
	for key in state():
		if copy.snapshot().get(key) != state()[key]: print("SAVE DIFF ",key," BEFORE ",state()[key]," AFTER ",copy.snapshot().get(key))
	check(copy.random.snapshot() == op.random.snapshot(),"T016 random state preserved")
	var bad: Dictionary = restored.duplicate(true)
	bad.state.player.spirit_stones = -1
	check(not copy.restore_save(bad).is_empty(),"invalid save rejected")
	command("travel",{"id":"town_qinglan"}); command("inn")
	command("accept",{"id":"quest_qinglan_003"}); command("travel",{"id":"area_qinglan_outskirts"}); command("challenge")
	fight()
	check(state().quests.quest_qinglan_003.progress == 1,"leader defeated through normal commands")
	command("travel",{"id":"town_qinglan"}); command("npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_003"})
	check(state().quests.quest_qinglan_003.status == "COMPLETED","VS0 task chain complete")
	command("travel",{"id":"town_yunxi"})
	check(state().mvp1 and state().player.location == "town_yunxi","S09 second town unlocked")
	command("join_sect",{"id":"sect_qingyue"}); command("donate")
	check(state().contribution == 1,"S09 sect donation changes real resources")
	var simulation: Dictionary = state()
	op.clock.advance(simulation,100*360*24,data,op.random)
	check(simulation.player.spirit_stones >= 0 and simulation.npcs.npc_qin_shoushan.alive == false,"T018 100 year life/death simulation")
	check(simulation.news.size() <= 100,"bounded world news")
	var first_rng: Dictionary = op.random.snapshot()
	var sequence := []
	for i in range(100): sequence.append(op.random.integer("exploration",1,100))
	op.random.restore(first_rng)
	var same := true
	for i in range(100): same = same and sequence[i] == op.random.integer("exploration",1,100)
	check(same,"T017 fixed random sequence 100 draws")
	print("GAME TESTS: %s checks, %s failures" % [count,failures])
	quit(0 if failures==0 else 1)
