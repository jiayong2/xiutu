extends SceneTree

var checks := 0
var failures := 0
var main: Control
var gm: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(title)
	return ok

func settle() -> void:
	for i in range(6):
		await process_frame

func snapshot() -> Dictionary:
	return gm.operations.snapshot()

func page(name: String) -> Control:
	return main.content.get_node_or_null(name) as Control

func click_named(container: Node, label: String) -> bool:
	for node in container.get_children():
		if node is Button and (node.text.contains(label) or node.tooltip_text.begins_with(label + " · ")):
			if not check(not node.disabled, "enabled: " + label):
				return false
			node.pressed.emit()
			return true
	return check(false, "button exists: " + label)

func travel(id: String) -> void:
	var home := page("HomeView")
	home.field("WorldMap").pressed.emit()
	await settle()
	var map := page("WorldMap")
	map.field("Index_" + id).pressed.emit()
	map.field("Enter").pressed.emit()
	await settle()

func run() -> void:
	# Fail even if a scene lookup or callback aborts the test coroutine.
	create_timer(15).timeout.connect(func():
		push_error("World UI test did not finish")
		quit(1)
	)
	gm = root.get_node("GameManager")
	# Isolate explicit action durations from real-time progression.
	gm.set_process(false)
	gm.new_game("世界界面验收", "金")
	var legacy: Dictionary = gm.operations.export_save()
	legacy.state.npcs.erase("npc_lin_zhaoxi")
	legacy.state.npcs.erase("npc_shen_yunzhao")
	legacy.state.npcs.npc_qin_shoushan.realm = 4
	legacy.state.npcs.npc_qin_shoushan.cultivation = 40
	legacy.state.npcs.npc_qin_shoushan.relations[legacy.state.player.id] = -6
	check(gm.operations.restore_save(legacy).is_empty(), "old save restores without Lin")
	check(snapshot().npcs.get("npc_lin_zhaoxi", {}).get("location") == "town_qinglan", "old save adds Lin in Qinglan")
	var prodigy: Dictionary = snapshot().npcs.get("npc_shen_yunzhao", {})
	check(prodigy.get("realm") == 19 and prodigy.get("location") == "town_qinglan", "old save adds Golden Core prodigy in Qinglan")
	var expected_qin: Dictionary = legacy.state.npcs.npc_qin_shoushan.duplicate(true)
	expected_qin.realm = 0
	expected_qin.cultivation = 0
	check(snapshot().npcs.npc_qin_shoushan == expected_qin, "migration updates mortal cultivation and preserves other NPC state")
	var old_profile_save: Dictionary = gm.operations.export_save()
	old_profile_save.state.npcs.npc_lin_zhaoxi.erase("loadout")
	check(gm.operations.restore_save(old_profile_save).is_empty(), "existing Lin save without loadout restores")
	check(snapshot().npcs.npc_lin_zhaoxi.loadout.equipment.weapon == "equip_iron_sword", "old profile save receives starting equipment")
	main = load("res://ui/main/main.tscn").instantiate()
	main.page = "地图"
	root.add_child(main)
	await settle()

	for resolution in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = resolution
		await settle()
		var map := page("WorldMap")
		check(root.size == resolution, "test window size %s" % [resolution])
		var body: Control = map.field("Body")
		var index: Control = map.field("IndexPanel")
		var center: Control = map.field("CenterPanel")
		var details: Control = map.field("RightPanel")
		check(body.get_child_count() == 3, "index, map and detail columns")
		check(index.position.x < center.position.x and center.position.x < details.position.x, "approved column order")
		check(center.size.x > index.size.x and center.size.x > details.size.x, "central map dominates side columns")
		check(map.field("Header").size.y <= 112, "compact map header")
		for key in ["Body", "GameTime", "Enter", "Back"]:
			check(map.get_global_rect().encloses(map.field(key).get_global_rect()), "map control within viewport: " + key)
		check(map.field("Canvas").get_child_count() == 6 and map.field("sect_qingyue_gate") != null, "five locations including sect gate plus routes")
		var before: Dictionary = gm.operations.export_save()
		map.field("Index_town_yunxi").pressed.emit()
		check(map.selected_place == "town_yunxi" and map.field("PlaceName").text == "云溪城", "index updates details")
		check(not map.field("Enter").disabled and map.field("UnlockStatus").text == "已开放", "ordinary city open without quest gate")
		check(before == gm.operations.export_save(), "map selection and travel query are read-only")
		map.field("town_qinglan").pressed.emit()
		map.field("Enter").pressed.emit()
		await settle()
		var home := page("HomeView")
		check(main.page == "地点场景" and snapshot().hours == 8, "enter current town without elapsed time")
		for key in ["MainContent", "WorldMap", "BottomNavigation"]:
			check(home.get_global_rect().encloses(home.field(key).get_global_rect()), "location control within viewport: " + key)
		check(home.field("Buildings").get_child_count() == 4 and home.field("Buildings").get_child(2).text == "公告栏", "shops, inn and announcement board")
		var nearby := 0
		var town_state := snapshot()
		for npc in town_state.npcs.values():
			if npc.alive and npc.location == town_state.player.location:
				nearby += 1
		check(home.field("Npcs").get_child_count() == nearby, "actual nearby NPCs")
		if click_named(home.field("Npcs"), "沈云昭"):
			await settle()
			var overlay: Control = main.npc_overlay
			check(overlay.field("Realm").text == "金丹一层", "prodigy shows the correct realm")
			overlay.field("Action10").pressed.emit()
			await settle()
			var profile: Control = overlay.profile
			if check(profile != null, "prodigy profile opens"):
				check(profile._field("IdentityPersonality").text == "性格：沉着果决", "personality shows in the identity grid")
				check(profile._field("IdentityRank").text == "评级：天骄", "prodigy rank shows in the identity grid")
				check(profile._field("Innate5").visible and profile._field("Acquired5").visible, "all twelve prodigy fortunes are displayed")
				var heavenly: StyleBoxFlat = profile._field("Innate5").get_theme_stylebox("normal")
				check(heavenly.bg_color.is_equal_approx(Color("9E222B")) and heavenly.border_color.is_equal_approx(Color("FFD36C")), "heavenly fortune uses the red and gold badge")
				check(profile._field("Attack").tooltip_text.contains("破岳重剑"), "prodigy equipment contributes to attack")
				check(profile._field("Identity").get_global_rect().encloses(profile._field("IdentityPersonality").get_global_rect()), "personality fits inside the identity panel")
				profile._field("Close").pressed.emit()
			overlay.field("Close").pressed.emit()
			await settle()
		if click_named(home.field("Npcs"), "秦守山"):
			await settle()
			var overlay: Control = main.npc_overlay
			check(main.page == "地点场景" and page("HomeView") == home, "NPC overlay preserves location page")
			check(overlay.npc_id == "npc_qin_shoushan" and overlay.field("Actions").get_child_count() == 12, "unified NPC actions")
			check(overlay.field("Relation").text == "关系：冷淡", "negative saved relation is presented as text")
			check(overlay.get_global_rect().encloses(overlay.field("Panel").get_global_rect()), "NPC overlay fits viewport")
			overlay.field("Close").pressed.emit()
			await settle()
			check(main.npc_overlay == null and page("HomeView") == home, "NPC close returns to same location view")
		if click_named(home.field("Npcs"), "林照溪"):
			await settle()
			var overlay: Control = main.npc_overlay
			var before_view: Dictionary = gm.operations.export_save()
			overlay.field("Action10").pressed.emit()
			await settle()
			var profile: Control = overlay.profile
			if check(profile != null, "View opens Lin's profile"):
				check(profile._field("IdentityName").text.contains("林照溪"), "profile uses selected NPC")
				check(profile._field("IdentityAge").position.x == profile._field("IdentityMentor").position.x, "identity right column stays aligned")
				check(profile._field("HealthBar").value == 92 and profile._field("ManaBar").value == 28 and profile._field("BloodBar").value == 66, "resource bars show live values and calculated caps")
				check(profile._field("QiSea").text == "气海：14" and profile._field("Attack").text == "攻击：16", "foundation and calculated combat values are visible")
				check(profile._field("Innate0").text == "木息亲和" and profile._field("Acquired0").text == "山径识途", "innate and acquired fortune are visible")
				check(profile.get_global_rect().encloses(profile._field("Frame").get_global_rect()), "profile fits viewport")
				check(profile._field("Attack").tooltip_text.contains("装备 · 精铁剑") and profile._field("Attack").tooltip_text.contains("气运 · 经年采药"), "attack tooltip lists gear and fortune sources")
				check(profile._field("Innate0").tooltip_text.contains("灵力上限 +2"), "fortune tooltip lists numeric effect")
				if resolution.x == 1920:
					var changed_loadout: Dictionary = before_view.state.npcs.npc_lin_zhaoxi.loadout.duplicate(true)
					changed_loadout.equipment.weapon = "equip_green_wood_sword"
					changed_loadout.techniques = {"technique_iron_body":2}
					check(gm.operations.set_npc_loadout("npc_lin_zhaoxi", changed_loadout), "valid NPC loadout commits")
					await settle()
					check(profile._field("Attack").text == "攻击：11" and profile._field("Defense").text == "防御：11", "open profile reflects swapped gear and technique level")
					check(profile._field("HealthBar").max_value == 130 and profile._field("Defense").tooltip_text.contains("铁骨功 Lv.2"), "technique bonus reaches cap and tooltip")
					var invalid_loadout: Dictionary = changed_loadout.duplicate(true)
					invalid_loadout.equipment.armor = "equip_iron_sword"
					check(not gm.operations.set_npc_loadout("npc_lin_zhaoxi", invalid_loadout), "wrong equipment slot is rejected")
					check(snapshot().npcs.npc_lin_zhaoxi.loadout == changed_loadout, "invalid assignment preserves committed loadout")
					check(gm.operations.restore_save(gm.operations.export_save()).is_empty() and snapshot().npcs.npc_lin_zhaoxi.loadout == changed_loadout, "changed loadout survives save round trip")
					check(gm.operations.restore_save(before_view).is_empty(), "restore original loadout")
					await settle()
				for tab in range(5):
					profile._field("Tab%d" % tab).pressed.emit()
					check(profile._field("Page%d" % tab).visible, "profile tab %d opens" % tab)
				check(profile._field("RelationList").get_child(0).text.contains("陌生"), "missing relation is stranger")
				check(profile._field("HistoryList").get_child_count() == 3, "authored biography is visible")
				profile._field("Close").pressed.emit()
				check(overlay.profile == null and overlay.field("Panel").visible, "profile close returns to actions")
			check(before_view == gm.operations.export_save(), "profile leaves saved state unchanged")
			overlay.field("Close").pressed.emit()
			await settle()
		home.field("WorldMap").pressed.emit()
		await settle()

	page("WorldMap").field("Back").pressed.emit()
	await settle()
	check(page("HomeView") != null and snapshot().player.location == "town_qinglan", "map return keeps current location")
	if click_named(page("HomeView").field("Buildings"), "青岚杂货铺"):
		await settle()
		check(main.page == "商店" and main.selected_shop == "shop_qinglan_general", "building opens actual shop")
		page("ShopHome").field("Back").pressed.emit()
		await settle()

	gm.request("accept", {"id": "quest_qinglan_001"})
	await settle()
	if click_named(page("HomeView").field("Npcs"), "秦守山"):
		await settle()
		var overlay: Control = main.npc_overlay
		check(snapshot().quests.quest_qinglan_001.progress == 0, "opening dialogue grants no progress")
		click_named(overlay.field("Actions"), "交谈")
		await settle()
		check(snapshot().quests.quest_qinglan_001.current_objective_id == "ask_disturbance", "ordinary talk does not complete designated objective")
		check(overlay.field("Feedback").text.contains("秦守山"), "real dialogue feedback")
		click_named(overlay.field("QuestOptions"), "询问青岚山异动")
		await settle()
		check(snapshot().quests.quest_qinglan_001.current_objective_id == "investigate_tracks", "dedicated option and supplies advance quest")
		check(overlay.field("QuestOptions").get_child(0).text.contains("进展"), "in-progress option follows quest")
		overlay.field("Close").pressed.emit()
		await settle()
		page("HomeView").field("TaskOpen").pressed.emit()
		await settle()
		check(main.page == "任务" and main.task_selected == "quest_qinglan_001", "location task card opens tracked quest")
		main._navigate("地点场景")
		await settle()

	var before_inn := snapshot()
	if click_named(page("HomeView").field("Buildings"), "悦来客栈"):
		await settle()
		var inn := page("InnPage")
		check(inn != null and snapshot() == before_inn, "entering inn does not charge")
		inn.field("Stay").pressed.emit()
		await settle()
		inn.field("ConfirmStay").pressed.emit()
		await settle()
		check(snapshot().player.spirit_stones == before_inn.player.spirit_stones - 10 and snapshot().hours == before_inn.hours + 24, "lodging uses original payment and time rules")
		page("InnPage").field("Back").pressed.emit()
		await settle()

	await travel("cave_qinglan")
	var cave := page("HomeView")
	check(snapshot().player.location == "cave_qinglan" and cave.field("Buildings").get_child(0).text == "修炼室", "cave uses real location and facilities")
	check(cave.field("NpcTitle").text.contains("0 人"), "no invented cave NPCs")
	await travel("area_qinglan_outskirts")
	var wild := page("HomeView")
	check(wild.field("Buildings").get_child(0).text == "山外围探索", "outskirts exploration entry")
	if click_named(wild.field("Buildings"), "调查妖兽踪迹"):
		await settle()
		var dialog: ConfirmationDialog
		for child in wild.get_children():
			if child is ConfirmationDialog:
				dialog = child
		if check(dialog != null and dialog.dialog_text.contains("爪印"), "investigation shows actual clue"):
			dialog.confirmed.emit()
			await settle()
			check(snapshot().quests.quest_qinglan_001.status == "READY_TO_TURN_IN", "investigation UI completes real event")
	gm.request("travel", {"id": "town_qinglan"})
	gm.request("npc_option", {"npc": "npc_qin_shoushan", "option": "report_quest_qinglan_001"})
	gm.request("travel", {"id": "area_qinglan_outskirts"})
	gm.request("accept", {"id": "quest_qinglan_002"})
	await settle()
	var before_explore := snapshot()
	if click_named(page("HomeView").field("Buildings"), "山外围探索"):
		await settle()
		check(snapshot().hours == before_explore.hours + 4, "exploration takes four game hours")
		check(not snapshot().battle.is_empty() and main.page == "战斗", "encounter opens real battle")

	var saves := preload("res://core/save_service.gd").new()
	var expected: Dictionary = gm.operations.export_save()
	var path := saves.write(expected, "user://test_saves")
	check(not path.is_empty() and gm.operations.restore_save(saves.read(path)).is_empty(), "world UI state saves and reloads")
	check(gm.operations.export_save() == expected, "world UI save round trip preserves state")
	print("WORLD UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
