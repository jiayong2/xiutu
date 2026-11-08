extends SceneTree

const ID := "quest_test_collect_001"
const NPC := "npc_shen_baicao"
const ITEM := "herb_spirit_grass"
const SHOP := "shop_qinglan_baicao"
var op: RefCounted
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func choose(key: String) -> Dictionary:
	return op.request("npc_option", {"npc":NPC, "option":ID + ":" + key})

func options(previous: String = "") -> Array:
	return op.quests.dialogue_options(op.snapshot(), NPC, op.data, "" if previous.is_empty() else ID + ":" + previous)

func progress() -> int:
	return op.quests.objective_count(op.snapshot(), ID, op.data.quests[ID].objectives[0])

func trade(action: String, quantity: int) -> bool:
	return op.request(action, {"shop":SHOP, "item":ITEM, "quantity":quantity}).success

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.new_game("药铺验收", "金")
	op = gm.operations
	check(op.request("talk", {"id":NPC}).message.contains("青灵草快用完了") and options().size() == 4, "offer greeting and four options")
	check(choose("use").message.contains("聚气丹") and options("use").map(func(o): return o.id) == [ID+":where", ID+":accept", ID+":refuse"], "use reply and follow-up choices")
	check(choose("where").message.contains("灵溪谷") and options("where").map(func(o): return o.id) == [ID+":use", ID+":accept", ID+":refuse"], "location reply and follow-up choices")
	check(choose("refuse").message.contains("改了主意") and options("refuse").is_empty() and not op.snapshot().quests.has(ID), "refusal changes no quest state")
	check(not op.request("accept", {"id":ID}).success and choose("accept").message.contains("三十灵石") and options("accept").is_empty(), "accept via NPC and end offer")
	check(op.snapshot().quests[ID].status == "ACTIVE" and progress() == 0, "active empty progress")
	check(op.request("talk", {"id":NPC}).message.contains("可寻到了") and choose("short").message.contains("不急这一时"), "shortage dialogue")
	check(options().map(func(o): return o.id) == [ID+":short", ID+":ask_again"], "shortage offers both choices")
	check(choose("ask_again").message == "青石山道、黑风林和灵溪谷都能寻到。若是急用，其他药铺也有出售。" and options("ask_again").is_empty() and op.snapshot().quests[ID].status == "ACTIVE", "asking again ends dialogue without changing quest status")
	var before: Dictionary = op.snapshot()
	check(not choose("deliver").success and op.snapshot() == before, "short delivery rejected atomically")
	check(trade("buy", 2) and progress() == 2, "purchase updates live progress")
	check(trade("buy", 2) and progress() == 3, "live progress capped")
	before = op.snapshot()
	check(choose("keep").message == "无妨，药草既在小友手中，自然由你做主。想好了再来找老夫便是。" and options("keep").is_empty() and op.snapshot().player == before.player and op.snapshot().quests[ID] == before.quests[ID], "keep herbs without deductions, reward or completion")
	check(trade("sell", 2) and progress() == 2 and not choose("deliver").success, "selling reopens shortage and rejects stale choice")
	check(trade("buy", 2), "replenish herbs")
	var saves := preload("res://core/save_service.gd").new()
	var path := saves.write(op.export_save(), "user://test_saves/quest_collect")
	check(not path.is_empty() and op.restore_save(saves.read(path)).is_empty() and progress() == 3, "active disk save restores live progress")
	var panel: Control = preload("res://ui/quest/task_page.tscn").instantiate()
	root.add_child(panel)
	panel.bind_data(op.snapshot(), op.data, ID)
	check(panel.field("TaskTitle").text.contains("进行中") and panel.field("Objective").text.contains("3/3") and panel.field("Related").text.contains("青岚镇 · 百草药铺"), "task panel binds status, progress and hand-in location")
	check(ID in panel.visible_ids() and panel.field("TaskType").text.contains("普通委托") and panel.field("Rewards").text.contains("×30"), "existing list and reward fields")
	check(panel.field("Description").text == op.data.quests[ID].description and panel.field("Objective").text.contains("青灵草") and not panel.field("Objective").text.contains("青石山道"), "clue stays out of description and objective")
	var clue: Label = panel.field("Clue")
	check(clue.visible and clue.text == "前往青岚山外围 · 青石山道，探索时有机会采集青灵草。" and panel.field("Objective").get_index() < clue.get_index() and clue.get_index() < panel.field("RelatedHeading").get_index(), "standalone clue between objective and related section")
	check(panel.field("ActionReason").text.is_empty() and not panel.field("ActionReason").visible, "footer does not repeat the clue")
	panel.queue_free()
	before = op.snapshot()
	check(not op.request("claim", {"id":ID}).success and op.snapshot() == before, "generic claim cannot bypass dialogue")
	check(choose("deliver").message.contains("三十灵石你收下"), "delivery reply")
	var after: Dictionary = op.snapshot()
	check(after.player.inventory.get(ITEM, 0) == before.player.inventory[ITEM] - 3 and after.player.spirit_stones == before.player.spirit_stones + 30 and after.quests[ID].status == "COMPLETED", "deduct three and grant 30 exactly once")
	check(not choose("deliver").success and not choose("accept").success and op.snapshot() == after, "duplicate delivery and accept rejected")
	path = saves.write(op.export_save(), "user://test_saves/quest_collect")
	check(not path.is_empty() and op.restore_save(saves.read(path)).is_empty(), "completed disk save reloads")
	check(op.request("talk", {"id":NPC}).message.contains("上次多亏") and options().is_empty() and not choose("deliver").success and op.snapshot().player.spirit_stones == after.player.spirit_stones, "completed greeting after reload and no replay")
	check(trade("buy", 1), "Baicao still trades after completion")
	# A second quest uses the same contract with different configured inputs.
	var variant: Dictionary = op.data.quests[ID].duplicate(true)
	variant.id = "quest_collect_fixture"
	variant.quest_id = variant.id
	variant.giver_npc_id = "npc_liu_qinghe"
	variant.target = variant.giver_npc_id
	variant.delivery_shop_id = "shop_qinglan_general"
	variant.money = 7
	variant.objectives[0].target_id = "item_healing_powder"
	variant.objectives[0].required_count = 1
	variant.objectives[0].completion_condition.npc_id = variant.giver_npc_id
	variant.delivery_dialogue.READY_TO_TURN_IN.options[0].response = "配置复用验收"
	op.data.quests[variant.id] = variant
	check(preload("res://gameplay/quest/quest_validation.gd").new().validate(op.data).is_empty(), "alternate quest configuration validates")
	var args := {"npc":variant.giver_npc_id, "option":variant.id + ":accept"}
	check(op.request("npc_option", args).success, "alternate NPC accepts configuration-only quest")
	before = op.snapshot()
	args.option = variant.id + ":deliver"
	check(op.request("npc_option", args).message == "配置复用验收", "alternate delivery uses configured response")
	after = op.snapshot()
	check(after.player.spirit_stones == before.player.spirit_stones + 7 and after.player.inventory.item_healing_powder == before.player.inventory.item_healing_powder - 1, "alternate item, quantity and reward used")
	gm.new_game("先采后接验收", "木")
	op = gm.operations
	check(op.request("travel", {"id":"area_qinglan_outskirts"}).success, "reach outskirts before accepting")
	# Force the gathering outcome only in this isolated run, with the real Stone Path herb table.
	var weights: Array = op.data.rules.exploration_weights
	op.data.rules.exploration_weights = [0,0,0,25,0]
	for attempt in range(30):
		if op.snapshot().player.inventory.get(ITEM, 0) >= 3:
			break
		if not op.request("explore", {"route":"stone_path"}).success:
			break
	op.data.rules.exploration_weights = weights
	check(op.snapshot().player.inventory.get(ITEM, 0) >= 3 and not op.snapshot().quests.has(ID), "real Stone Path gathering before acceptance")
	check(op.request("travel", {"id":"town_qinglan"}).success and choose("accept").success and progress() == 3 and op.snapshot().quests[ID].status == "READY_TO_TURN_IN", "preowned gathered herbs qualify immediately")
	var unavailable: Dictionary = op.snapshot()
	unavailable.npcs[NPC].alive = false
	op.quests.refresh(unavailable, op.data)
	check(unavailable.quests[ID].status == "READY_TO_TURN_IN" and op.quests.dialogue_options(unavailable, NPC, op.data).is_empty(), "unavailable NPC blocks delivery without failing the quest")
	check(choose("deliver").success, "gathered herbs can be delivered")
	quit(failures)
