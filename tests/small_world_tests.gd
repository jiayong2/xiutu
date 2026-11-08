extends SceneTree

const Operations := preload("res://core/operation_service.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var manager := root.get_node("GameManager")
	manager.set_process(false)
	var operations := Operations.new()
	var prototype_tables: Dictionary = manager.catalog.tables.duplicate()
	prototype_tables.npc_overrides = {}
	operations.configure(prototype_tables)
	var data: Dictionary = operations.data
	operations.new_game("小世界验收", "木", manager.repository.starting_character(), 17)
	var legacy: Dictionary = operations.export_save()
	var roster: Dictionary = legacy.state.npcs
	for npc in roster.values():
		check(npc.get("hp",0) > 0, "Living NPC starts with HP: " + npc.id)
		if npc.realm > 0:
			check(npc.get("mp",0) > 0 and npc.get("blood",0) > 0, "Cultivator starts with MP and blood: " + npc.id)
	var elder: Dictionary = roster.npc_zhou_xuan
	check(elder.realm >= 10 and elder.hp > roster.npc_qin_shoushan.hp, "Sect elder uses cultivator stats")
	check(not elder.fortunes.is_empty() and not elder.loadout.equipment.is_empty() and not elder.loadout.techniques.is_empty(), "Sect elder receives real fortune, gear and technique")
	var elder_presentation: Dictionary = preload("res://world/npc_interaction.gd").new().presentation(legacy.state,data,elder.id)
	check(elder_presentation.identity == "外门长老" and elder_presentation.rank == "普通", "Elder identity is separate from fixed aptitude rank")
	var seeded_again := Operations.new()
	seeded_again.configure(data)
	seeded_again.new_game("小世界验收", "木", manager.repository.starting_character(), 17)
	check(seeded_again.snapshot().npcs == roster, "Fixed seed reproduces NPC generation")
	for definition in data.shops.values():
		var merchant: Dictionary = legacy.state.npcs[definition.npc_id]
		check(merchant.location == definition.location, "Merchant starts in shop town: " + definition.id)
		if definition.get("seed_on_restore", false):
			legacy.state.stocks.erase(definition.id)
	for definition in data.prototype.npcs:
		if definition.get("seed_on_restore", false):
			legacy.state.npcs.erase(definition.id)
	legacy.state.stocks.shop_qinglan_general.item_aura_powder = 0
	legacy.state.npcs.npc_yunxi_keeper.name = "药阁掌柜"
	legacy.state.npcs.npc_yunxi_keeper.erase("loadout")
	legacy.state.npcs.npc_yunxi_keeper.erase("fortunes")
	legacy.state.npcs.npc_yunxi_keeper.erase("mp")
	legacy.state.player.mp = 0
	check(operations.restore_save(legacy).is_empty(), "Restore version-one save predating new content")
	var before: Dictionary = operations.snapshot()
	var shop_id := "shop_qinglan_baicao"
	var item_id := "pill_mana_restore"
	check(before.stocks.shop_qinglan_general.item_aura_powder == 0, "Existing depleted stock remains depleted")
	check(before.npcs.has("npc_jiang_wangshu"), "New resident seeded")
	check(before.npcs.npc_yunxi_keeper.name == "宁丹青", "Existing apothecary ID receives its canonical name")
	var keeper: Dictionary = before.npcs.npc_yunxi_keeper
	check(keeper.mp > 0 and not keeper.loadout.techniques.is_empty() and not keeper.fortunes.is_empty(), "Old save receives missing cultivator fields")
	check(before.npcs.npc_lin_zhaoxi.loadout == roster.npc_lin_zhaoxi.loadout, "Preserve curated loadout")
	check(operations.restore_save(operations.export_save()).is_empty() and operations.snapshot().npcs == before.npcs, "Generated NPC values and loadouts do not reroll on restore")
	check(before.npcs.has(data.inns.inn_qinglan.owner_npc_id), "Innkeeper seeded")
	check(before.stocks[shop_id][item_id] == data.shops[shop_id].stock[item_id], "New shop seeded")
	var args := {"shop":shop_id,"item":item_id,"quantity":1}
	check(operations.request("buy", args, "small_world_buy").success, "Buy recovery pill through normal request")
	var bought: Dictionary = operations.snapshot()
	check(bought.stocks[shop_id][item_id] == before.stocks[shop_id][item_id] - 1, "Purchase decrements stock")
	check(bought.player.spirit_stones < before.player.spirit_stones, "Purchase deducts money")
	check(bought.player.inventory.get(item_id, 0) == 1, "Purchase grants one item")
	check(not operations.request("buy", args, "small_world_buy").success, "Duplicate operation rejected")
	check(operations.restore_save(operations.export_save()).is_empty(), "Restore current save")
	check(operations.snapshot().stocks[shop_id][item_id] == bought.stocks[shop_id][item_id], "Restore preserves new shop stock")
	check(operations.request("use_item", {"id":item_id}).success, "Pill uses normal recovery path")
	check(operations.snapshot().player.mp > 0 and not operations.snapshot().player.inventory.has(item_id), "Pill restores MP and is consumed")
	check(operations.request("buy", args).success, "Buy second recovery pill")
	check(operations.request("sell", args).success, "Sell pill through normal request")
	check(not operations.snapshot().player.inventory.has(item_id), "Sale removes pill")
	var combat: Dictionary = operations.export_save()
	combat.state.player.spirit_stones = 500
	combat.state.player.mp = 0
	check(operations.restore_save(combat).is_empty(), "Prepare equipment and battle checks")
	var old_attack: int = operations.stats().attack
	var weapon := "equip_wolf_fang_blade"
	check(operations.request("buy", {"shop":"shop_qinglan_blacksmith","item":weapon}).success, "Buy weapon")
	var instances: Dictionary = operations.snapshot().player.equipment_instances
	var weapon_instance: String = instances.find_key(weapon)
	check(operations.request("equip", {"id":weapon_instance}).success, "Equip weapon instance")
	check(operations.stats().attack > old_attack, "Weapon improves attack")
	check(operations.request("buy", args).success, "Buy pill for battle")
	check(operations.request("travel", {"id":"area_qinglan_outskirts"}).success, "Travel to outskirts")
	var before_route: Dictionary = operations.export_save()
	check(not operations.request("explore", {"route":"missing"}, "unknown_route").success, "Unknown route rejected")
	check(operations.export_save() == before_route, "Rejected routes preserve time, state and RNG")
	var iron := "material_ordinary_iron_ore"
	var spirit_iron := "material_spirit_iron"
	var mine_routes: Array = data.prototype.outskirts_routes.filter(func(route):return route.has("mining"))
	var encounters: Dictionary = {}
	for route in mine_routes:
		check(route.encounter.chance == 25, "Configured encounter chance")
		encounters[route.id] = route.encounter
		route.erase("encounter")
	var mined: Dictionary = operations.request("explore", {"route":"rocky_slope"}, "mine_rocky_slope")
	var slope: Dictionary = operations.snapshot()
	check(mined.success and mined.message.contains("普通铁矿"), "Rocky slope mining and feedback")
	check(slope.hours == before_route.state.hours + int(data.rules.exploration_hours), "Mining advances normal exploration time")
	check(slope.player.inventory.get(iron,0) == 1 and not slope.player.inventory.has(spirit_iron), "Slope yields ordinary iron only")
	check(not operations.request("explore", {"route":"rocky_slope"}, "mine_rocky_slope").success and operations.snapshot() == slope, "Duplicate mining grants no ore or time")
	for index in range(20):
		check(operations.request("explore", {"route":"abandoned_mine"}).success, "Mine without a pickaxe")
	var mine_save: Dictionary = operations.export_save()
	var mine_items: Dictionary = mine_save.state.player.inventory
	check(mine_items.get(iron,0) == 21, "Mine always grants ordinary iron")
	check(mine_items.get(spirit_iron,0) > 0 and mine_items[spirit_iron] < 20, "Mine sometimes grants spirit iron")
	check(operations.restore_save(mine_save).is_empty() and operations.export_save() == mine_save, "Mining inventory and RNG survive restore")
	check(operations.request("travel", {"id":"town_qinglan"}).success, "Return from mining")
	var wallet: int = operations.snapshot().player.spirit_stones
	check(operations.request("sell", {"shop":"shop_qinglan_blacksmith","item":iron}).success, "Sell mined ore at the smithy")
	check(operations.snapshot().player.inventory.get(iron,0) == 20 and operations.snapshot().player.spirit_stones > wallet, "Sale removes ore and pays player")
	check(operations.restore_save(before_route).is_empty(), "Restore state before mining")
	for route in mine_routes:
		var encounter: Dictionary = encounters[route.id]
		route.encounter = encounter.duplicate()
		route.encounter.chance = 100
		var monster_id: String = encounter.monster_id
		var original_monster: Dictionary = data.monsters[monster_id].duplicate(true)
		var drop: Array = original_monster.drops[0]
		check(drop[2] == (0.75 if route.id == "rocky_slope" else 0.70), "Configured monster drop chance")
		data.monsters[monster_id].hp = 1
		data.monsters[monster_id].drops[0][2] = 1.0
		var encounter_args := {"route":route.id}
		check(operations.request("explore", encounter_args, route.id).success, "Mining encounter starts")
		var encounter_save: Dictionary = operations.export_save()
		check(encounter_save.state.battle.get("monster") == monster_id, "Encounter uses regional monster")
		check(encounter_save.state.player.inventory == before_route.state.player.inventory, "Encounter grants no mining ore")
		check(encounter_save.state.hours == before_route.state.hours + int(data.rules.exploration_hours), "Encounter advances time once")
		check(operations.restore_save(encounter_save).is_empty(), "Reload mining encounter")
		check(operations.request("battle_action", {"kind":"attack"}, "win_" + route.id).success, "Fight through standard battle action")
		var won: Dictionary = operations.snapshot()
		var report: Dictionary = won.get("battle_report", {})
		var quantity: int = report.get("drops", {}).get(drop[0],0)
		check(report.get("result") == "win" and quantity >= 1 and quantity <= (3 if route.id == "rocky_slope" else 1), "Victory grants configured loot range")
		check(won.player.inventory.get(drop[0],0) == quantity, "Inventory and battle report agree")
		check(not operations.request("battle_action", {"kind":"attack"}, "win_" + route.id).success and operations.snapshot() == won, "Victory loot cannot be awarded twice")
		check(operations.restore_save(before_route).is_empty(), "Reset to pre-encounter state")
		data.monsters[monster_id] = original_monster
		route.encounter = encounter
	var weights: Array = data.rules.exploration_weights
	data.rules.exploration_weights = [0,20,10,0,0]
	check(operations.request("explore", {"route":"stone_path"}).success, "Stone path exploration")
	var travelled: Dictionary = operations.snapshot()
	check(travelled.battle.get("monster") == "monster_mountain_boar", "Stone path uses existing boar")
	check(travelled.hours == before_route.state.hours + int(data.rules.exploration_hours), "Route advances normal exploration time")
	check(travelled.player.location == "area_qinglan_outskirts", "Route keeps parent location")
	check(operations.restore_save(before_route).is_empty(), "Restore before exploring another route")
	data.rules.exploration_weights = [0,0,0,25,0]
	check(operations.request("explore", {"route":"mist_woods"}).success, "Mist woods gathering")
	check(operations.snapshot().player.inventory.get("herb_fire_tip",0) > before_route.state.player.inventory.get("herb_fire_tip",0), "Mist woods grants existing fire herb")
	data.rules.exploration_weights = weights
	check(operations.restore_save(before_route).is_empty(), "Restore independent battle state")
	check(operations.request("challenge").success, "Enter wolf leader encounter")
	check(operations.request("battle_action", {"kind":"item","id":item_id}).success, "Use recovery pill in battle")
	check(not operations.snapshot().player.inventory.has(item_id), "Battle consumes pill")
	var month_state: Dictionary = operations.snapshot()
	data.prototype.npc_migration_chance = 1.0
	operations.clock.world.settle_month(month_state, data, operations.random, 1)
	check(month_state.npcs.npc_shen_baicao.location == "town_qinglan", "Shopkeeper stays at shop")
	check(month_state.npcs.npc_jiang_wangshu.location == "town_yunxi", "Travelling cultivator follows original migration")
	var city_save: Dictionary = before_route.duplicate(true)
	city_save.state.player.location = "town_yunxi"
	city_save.state.mvp1 = true
	check(operations.restore_save(city_save).is_empty(), "Prepare Yunxi storefront checks")
	var city: Dictionary = operations.snapshot()
	var home: Control = load("res://ui/main/home_view.tscn").instantiate()
	home.state = city
	home.data = data
	home._buildings()
	var opened: Array = []
	home.shop_requested.connect(func(id: String):opened.append(id))
	home.npc_requested.connect(func(id: String):opened.append(id))
	for button in home.field("Buildings").get_children():
		if button.text in ["云溪坊市","百炼坊","符箓阁"]:
			check(not button.disabled, "Available storefront: " + button.text)
			button.pressed.emit()
	check(opened == ["shop_yunxi_market","shop_yunxi_bailian","npc_lu_zhifu"], "City buildings use real shop or dialogue routes")
	home.free()
	check(operations.request("buy", {"shop":"shop_yunxi_market","item":iron}).success, "Market sells actual ore")
	check(operations.request("sell", {"shop":"shop_yunxi_bailian","item":iron}).success, "Forge accepts ore through normal trade")
	check(operations.request("talk", {"id":"npc_lu_zhifu"}).message.contains("陆知符"), "Talisman building has real dialogue")
	var interaction := preload("res://world/npc_interaction.gd").new()
	check(interaction.evaluate(operations.snapshot(),data,"npc_lu_zhifu","交易").kind == "reject", "No unusable talismans are offered")
	check(data.auctions.auction_yunxi.host.name == city.npcs.npc_xie_yunlou.name, "Auction uses named host")
	check(city.npcs.npc_xie_yunlou.realm == 6 and interaction.presentation(city,data,"npc_xie_yunlou").realm == "境界未知", "Xie Yunlou has a real but undisclosed realm")
	check(interaction.presentation(city,data,"npc_gu_qingyue").realm == "境界未知", "Prototype NPC realm is hidden")
	check(city.npcs.npc_han_shi.location == "area_qinglan_outskirts", "Mining chief is placed in the outskirts")
	check(city.npcs.npc_han_ming.sect == "sect_qingyue", "Sect officer has affiliation")
	check(interaction.sect_area_restricted(city.npcs.npc_gu_changfeng,data), "Core NPC preserves sector restriction")
	print("Small world checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
