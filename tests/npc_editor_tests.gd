extends SceneTree

const Model := preload("res://core/npc_definitions.gd")
const Catalog := preload("res://core/content_catalog.gd")
const Operations := preload("res://core/operation_service.gd")
const EditorPanel := preload("res://addons/npc_editor/editor.tscn")
const TEST_PATH := "user://npc_editor_test.json"
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _same_stats(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left:
		if not right.has(key):
			return false
		if left[key] is Dictionary:
			if not right[key] is Dictionary or not _same_stats(left[key], right[key]):
				return false
		elif not is_equal_approx(float(left[key]), float(right[key])):
			return false
	return true

func _run() -> void:
	var catalog := Catalog.new()
	if not catalog.load_all():
		push_error(catalog.error)
		quit(1)
		return
	var data := catalog.tables
	var workspace := VBoxContainer.new()
	root.add_child(workspace)
	var editor = EditorPanel.instantiate()
	workspace.add_child(editor)
	_check(editor.ready_to_edit and editor.pages.size() == 11, "editor opens the catalog")
	_check(editor.roster_list.item_count == Model.roster(data, editor.saved).size(), "the default roster includes all NPCs (%s of %s, rank %s)" % [editor.roster_list.item_count, Model.roster(data, editor.saved).size(), editor.rank_filter.selected])
	var roster := Model.roster(data,editor.saved)
	for id in ["npc_qin_shoushan","npc_zhou_xuan"]:
		editor._open(roster[id])
		var selected_place := ""
		for row in editor.pages[0].get_children():
			if row is HBoxContainer and row.get_child(0).text == "初始所在地":
				var options: OptionButton = row.get_child(1)
				if options.selected >= 0:
					selected_place = options.get_item_text(options.selected)
		var expected: String = Model.Locations.names(data)[roster[id].location]
		_check(selected_place == expected and editor.draft.location == roster[id].location, "location reads the actual definition and shows the map name for " + id)
		_check(Model.validate(editor.draft,data,roster).is_empty(), "existing definition location is accepted for " + id)
		var selected: int = editor.roster_list.get_selected_items()[0]
		_check(editor.roster_list.get_item_tooltip(selected).contains(expected), "roster tooltip displays the location")
	_check(editor.rank_filter.item_count == Model.Character.NPC_RANKS.size() + 1, "rank filter offers only fixed ranks")
	_check(Model.Character.npc_rank({"rank":"外门长老"}) == "普通", "invalid rank falls back to the normal rank")
	for dimensions in [Vector2(1920, 1080), Vector2(1280, 720)]:
		workspace.size = dimensions
		await process_frame
		await process_frame
		_check(editor.size.is_equal_approx(dimensions), "NPC panel fills the workspace at %s" % dimensions)
		_check(editor.theme.default_font_size == (36 if dimensions.x == 1920 else 24), "NPC controls scale with workspace width")
		var columns: HBoxContainer = editor.get_node("Frame/Columns")
		var footer: HBoxContainer = editor.get_node("Frame/Footer")
		_check(columns.size.y > dimensions.y * 0.8 and footer.get_global_rect().end.y > dimensions.y - 20.0, "NPC columns fill the body and footer stays at the bottom at %s" % dimensions)
		var header: HBoxContainer = editor.get_node("Frame/Header")
		_check(editor.get_global_rect().encloses(header.get_node("SelectSave").get_global_rect()) and editor.get_global_rect().encloses(header.get_node("SaveChanges").get_global_rect()), "save buttons fit beside the heading at %s" % dimensions)
	editor.rank_filter.select(1)
	editor._refresh_roster()
	_check(editor.roster_list.item_count > 0 and editor.roster_list.get_item_tooltip(0).contains("天骄"), "roster filters by rank (%s matches)" % editor.roster_list.item_count)
	editor._random_npc()
	_check(editor.is_dirty() and editor.rank_filter.selected == 0 and editor.draft.profile.gender in ["男", "女"] and editor.draft.profile.root in data.rules.roots, "random NPC uses valid choices and appears in the full roster")
	_check(Model.validate(editor.draft, data, Model.roster(data, editor.saved)).is_empty(), "random draft is valid")
	editor._revert()
	editor._new()
	_check(editor.is_dirty() and editor.draft.id.begins_with("npc_"), "editor creates a draft")
	editor._set_field("编辑器测试草稿", editor.draft, "name")
	editor.search.text = "编辑器测试草稿"
	editor._refresh_roster()
	_check(editor.roster_list.item_count == 1 and editor.roster_list.get_item_tooltip(0).contains("未保存"), "search finds the current named draft")
	editor._add_fortune("fortune_039")
	editor._add_fortune("fortune_036")
	_check(editor.draft.fortune_ids == ["fortune_039", "fortune_036"], "both innate fortunes are accepted")
	editor._add_fortune("fortune_039")
	_check(editor.draft.fortune_ids.size() == 2 and editor.fortune_feedback.innate.text.contains("万木长生体"), "duplicate is explained below the innate list")
	for row in editor.pages[2].get_children():
		if row is HBoxContainer and row.get_child(0).text == "万木长生体":
			_check(row.get_child(0).autowrap_mode == TextServer.AUTOWRAP_OFF and row.get_child(0).size_flags_horizontal == Control.SIZE_FILL, "fortune badge stays compact and horizontal")
	editor._enable_base()
	editor._learn("technique_qi_flow", editor.draft.techniques)
	editor._learn("skill_spirit_bolt", editor.draft.spells)
	editor._add_gear("equip_v1_green_edge_sword", true)
	var instance: String = editor.draft.equipped.weapon
	for check in [
		[3, "等级", editor.draft.techniques, "technique_qi_flow", 1],
		[4, "等级", editor.draft.spells, "skill_spirit_bolt", 1],
		[5, "温养等级", editor.draft.equipment_nurture, instance, 0],
	]:
		var found := false
		for row in editor.pages[check[0]].get_children():
			if not row is HBoxContainer or row.get_child(0).text != check[1]:
				continue
			var minus: Button = row.get_child(1)
			var number: Label = row.get_child(2)
			var plus: Button = row.get_child(3)
			found = true
			_check(minus.disabled and number.text == str(check[4]) and plus.custom_minimum_size.x >= 56, "level stepper starts at the minimum with large side buttons")
			plus.pressed.emit()
			_check(check[2][check[3]] == check[4] + 1 and not minus.disabled, "plus raises the level and enables minus")
			minus.pressed.emit()
			_check(check[2][check[3]] == check[4] and minus.disabled, "minus restores the lower bound")
			break
		_check(found, "level stepper is present on page %s" % check[0])
	editor._choose(editor._equipment_table("weapon"), [], editor._add_gear.bind(true))
	_check(editor.picker.list.item_count > 0, "shared picker lists weapons")
	editor.picker.hide()
	workspace.queue_free()
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/starting_character.json"))
	var legacy := Operations.new()
	legacy.configure(data)
	_check(legacy.new_game("验收", data.rules.roots[0], base).is_empty(), "legacy new game")
	var previous := legacy.export_save()
	var id := "npc_editor_test"
	var npc := Model.draft({"id":id,"name":"测试人物","role":"测试散修","location":"town_qinglan","realm":2}, data)
	npc.profile.root = data.rules.roots[0]
	npc.profile.rank = "良才"
	for key in Model.STATS:
		npc.profile.base[key] = base[key]
	npc.equipment_instances.test_weapon = "equip_v1_green_edge_sword"
	npc.equipped.weapon = "test_weapon"
	npc.equipment_nurture.test_weapon = 2
	npc.techniques.technique_qi_flow = 1
	npc.technique_slots = ["technique_qi_flow"]
	npc.spells.skill_spirit_bolt = 2
	npc.spell_slots = ["skill_spirit_bolt"]
	npc.fortune_ids = ["fortune_039", "fortune_036"]
	for fortune_id in Model.Fortune.DEFINITIONS:
		var row: Dictionary = Model.Fortune.DEFINITIONS[fortune_id]
		if row.kind == "acquired" and row.duration.type == "permanent" and row.exclusive_group.is_empty():
			npc.fortune_ids.append(fortune_id)
			break
	_check(npc.fortune_ids.size() == 3, "two innate and one acquired fortune IDs")
	var artifact: String = data.artifacts.keys()[0]
	npc.artifact_ids = [artifact]
	npc.artifact_slots = [artifact]
	for item in data.items:
		if not data.equipment.has(item):
			npc.inventory[item] = 3
			break
	var rows := {id:npc}
	_check(Model.write_definitions(rows, data, TEST_PATH).is_empty(), "atomic definition write")
	_check(Model.write_definitions(rows, data, TEST_PATH).is_empty(), "replace existing definition")
	var result := Model.load_definitions(data, TEST_PATH)
	if not result.error.is_empty():
		push_error(result.error)
		quit(1)
		return
	var loaded: Dictionary = result.rows[id]
	_check(loaded.equipment_nurture.test_weapon == 2 and loaded.spells.skill_spirit_bolt == 2 and loaded.technique_slots == npc.technique_slots and loaded.fortune_ids == npc.fortune_ids and loaded.artifact_slots == npc.artifact_slots and _same_stats(loaded.inventory, npc.inventory), "definition retains resources")
	data.npc_overrides = result.rows
	var game := Operations.new()
	game.configure(data)
	_check(game.restore_save(previous).is_empty() and not game.snapshot().npcs.has(id), "existing saves keep their NPC roster")
	var original_state := game.snapshot()
	var original_qin: Dictionary = original_state.npcs.npc_qin_shoushan
	var qin_definition := Model.draft(roster.npc_qin_shoushan,data)
	qin_definition.fortune_ids = ["fortune_039","fortune_036"]
	_check(game.request("debug_import_npc", {"definition":qin_definition, "refresh":true}).success, "sync supports an original roster NPC")
	var synced_qin: Dictionary = game.snapshot().npcs.npc_qin_shoushan
	_check(synced_qin.fortunes.size() == 2 and synced_qin.location == original_qin.location and synced_qin.wealth == original_qin.wealth and synced_qin.get("loadout") == original_qin.get("loadout"), "prototype fortune sync preserves location, wealth and loadout")
	var fortune_save := game.export_save()
	_check(game.restore_save(fortune_save).is_empty() and game.snapshot().npcs.npc_qin_shoushan.fortunes == synced_qin.fortunes, "multiple synchronized fortunes survive restore")
	var saves := preload("res://core/save_service.gd").new()
	var fortune_path: String = saves.write(fortune_save,"user://test_saves")
	editor._open(roster.npc_qin_shoushan)
	editor._read_saved_fortunes(fortune_path)
	_check(editor.is_dirty() and editor.draft.fortune_ids.has("fortune_039") and editor.draft.fortune_ids.has("fortune_036"), "editor reads permanent runtime fortunes into the draft")
	if not fortune_path.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fortune_path))
	editor._revert()
	var old_definition := loaded.duplicate(true)
	old_definition.equipped.clear()
	old_definition.fortune_ids = ["fortune_039"]
	var imported := game.request("debug_import_npc", {"definition":old_definition})
	_check(imported.success and game.snapshot().npcs.has(id), "debug imports NPC into the loaded game")
	_check(game.snapshot().player == original_state.player, "debug import leaves the player unchanged")
	_check(not game.request("debug_import_npc", {"definition":loaded}).success, "debug import rejects an existing NPC")
	var before_sync: Dictionary = game.snapshot().npcs[id]
	var calculator := Model.Character.new()
	var old_attack: float = calculator.npc_stats(before_sync, before_sync.profile, data).attack
	_check(game.request("debug_import_npc", {"definition":loaded, "refresh":true}).success, "debug sync updates an imported NPC")
	var after_sync: Dictionary = game.snapshot().npcs[id]
	_check(calculator.npc_stats(after_sync, after_sync.profile, data).attack > old_attack and after_sync.age == before_sync.age and after_sync.location == before_sync.location, "debug sync equips gear and preserves age and location")
	var profile = preload("res://ui/npc/npc_profile.tscn").instantiate()
	root.add_child(profile)
	var profile_state := game.snapshot()
	profile_state.npcs[id] = before_sync
	profile.bind_data(profile_state, data, id)
	profile.get_node("Frame/Page2").show()
	var weapon: Label = profile.find_child("EquipmentList", true, false).get_child(0)
	_check(weapon.text == "武器\n空位" and weapon.tooltip_text.is_empty(), "held gear does not appear as equipped or have a tooltip")
	profile.bind_data(game.snapshot(), data, id)
	weapon = profile.find_child("EquipmentList", true, false).get_child(0)
	_check(weapon.text == "武器\n" + data.items.equip_v1_green_edge_sword.name, "NPC profile resolves the equipped instance to its item name")
	var hover: Control = weapon.call("_make_custom_tooltip", weapon.tooltip_text)
	var hover_text := ""
	for line in hover.find_children("*", "RichTextLabel", true, false):
		hover_text += line.text + "\n"
	_check(hover_text.contains("锋锐") and hover_text.contains("温养层数：2/5") and hover_text.contains("已穿戴"), "NPC equipment uses the player tooltip with instance effects and nurture")
	hover.free()
	profile.bind_data(game.snapshot(), data, "npc_lin_zhaoxi")
	weapon = profile.find_child("EquipmentList", true, false).get_child(0)
	_check(weapon.tooltip_text.contains("攻击 +9"), "legacy equipment displays its attack bonus")
	profile.queue_free()
	_check(game.restore_save(game.export_save()).is_empty() and game.snapshot().npcs.has(id), "an explicitly saved debug import survives load")
	_check(game.snapshot().npcs[id].fortunes.has("fortune_039") and game.snapshot().npcs[id].fortunes.has("fortune_036"), "both innate fortunes survive save restore")
	_check(not previous.state.npcs.has(id), "the original save payload is unchanged")
	_check(game.new_game("验收", data.rules.roots[0], base).is_empty(), "new game accepts authored NPC")
	var state: Dictionary = game.snapshot().npcs[id]
	var character := Model.Character.new()
	var preview := character.npc_stats(Model.initial(loaded, data), loaded.profile, data)
	var runtime := character.npc_stats(state, state.profile, data)
	_check(_same_stats(preview, runtime), "preview and runtime use the same stats")
	_check(game.restore_save(game.export_save()).is_empty(), "authored runtime save restores")
	state.equipped.clear()
	_check(character.npc_stats(state, state.profile, data).attack < runtime.attack, "unequip removes attack once")
	var without_gear := character.npc_stats(state, state.profile, data)
	state.fortunes.clear()
	var without_fortune := character.npc_stats(state, state.profile, data)
	var clean := loaded.duplicate(true)
	clean.equipped.clear()
	clean.fortune_ids.clear()
	_check(_same_stats(without_fortune, character.npc_stats(Model.initial(clean, data), clean.profile, data)), "removing fortunes restores the unmodified calculation")
	_check(without_gear.has("attack"), "stats remain available")
	_check(not Model.slots_error(Array(range(11)), {}, 10).is_empty(), "slot limit")
	loaded.spells["invalid_spell"] = 1
	_check(not Model.validate(loaded, data, Model.roster(data, rows)).is_empty(), "invalid resource rejected")
	var edit_directory := "user://" + Model.uid("npc_save_edit_test_")
	var edit_player_id: String = fortune_save.state.player.id
	fortune_save.state.npcs.npc_qin_shoushan.relations[edit_player_id] = -6
	var edit_path: String = saves.write(fortune_save,edit_directory)
	editor._open(roster.npc_qin_shoushan)
	editor._select_target_save(edit_path)
	_check(editor.draft.fortune_ids.size() == 2 and editor.roster_list.item_count == fortune_save.state.npcs.size(), "header save picker reads the selected save roster and actual fortunes")
	var original_payloads: Dictionary = {}
	for revision in range(1,7):
		original_payloads[revision] = saves.read(edit_path)
		editor.draft.fortune_ids = ["fortune_039"] if revision % 2 else ["fortune_036"]
		editor._apply_to_selected_save()
		_check(editor.selected_save == ProjectSettings.globalize_path(edit_path), "editor applies to the same path: " + editor.status.text)
		var changed: Dictionary = saves.read(edit_path)
		_check(changed.state.npcs.npc_qin_shoushan.fortunes.keys() == editor.draft.fortune_ids, "direct editor update writes the selected fortunes")
		_check(changed.state.npcs.npc_qin_shoushan.relations.get(edit_player_id) == -6, "direct save accepts and preserves the NPC's relation to the player")
		var before_edit: Dictionary = original_payloads[revision].duplicate(true)
		before_edit.state.npcs.erase("npc_qin_shoushan")
		changed.state.npcs.erase("npc_qin_shoushan")
		_check(changed == before_edit, "direct editor update preserves all unrelated save data")
	var backup_dir := edit_directory.path_join("npc_backups")
	var backup_files := DirAccess.get_files_at(backup_dir)
	_check(backup_files.size() == 5 and saves.list_saves(edit_directory).size() == 1, "six edits retain five backups and one visible save")
	var backup_orders: Array[int] = []
	for filename in backup_files:
		var backup_path := backup_dir.path_join(filename)
		var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(backup_path))
		var order := int(envelope.npc_backup_order)
		backup_orders.append(order)
		_check(envelope.npc_backup_source == edit_path.get_file() and saves.read(backup_path) == original_payloads[order], "backup preserves its previous save payload")
	backup_orders.sort()
	_check(backup_orders == [2,3,4,5,6], "backup rotation replaces the oldest version")
	var stable := FileAccess.get_file_as_string(edit_path)
	_check(not saves.replace_with_npc_backup(edit_path,fortune_save,"stale-checksum").is_empty() and FileAccess.get_file_as_string(edit_path) == stable, "stale target cannot be replaced")
	editor.draft.fortune_ids = ["invalid_fortune"]
	editor._apply_to_selected_save()
	_check(FileAccess.get_file_as_string(edit_path) == stable and DirAccess.get_files_at(backup_dir) == backup_files, "invalid draft leaves selected save and backups intact")
	_check(editor.status.text.contains("无效、互斥或非永久气运"), "child-process failure is readable Chinese")
	editor.draft.fortune_ids = ["fortune_039"]
	editor.search.text = ""
	editor.rank_filter.select(0)
	editor._refresh_roster()
	for index in range(editor.roster_list.item_count):
		if editor.roster_list.get_item_metadata(index) == "npc_lin_zhaoxi":
			editor._select(index)
			break
	_check(editor.draft.id == "npc_lin_zhaoxi" and editor.selected_save == ProjectSettings.globalize_path(edit_path), "queued edits allow switching NPCs without selecting the save again")
	var editable_growth_fields := 0
	var realm_visibility: CheckBox
	for row in editor.pages[1].get_children():
		if row is CheckBox and row.text == "在游戏中公开法修境界":
			realm_visibility = row
		if not row is HBoxContainer:
			continue
		if row.get_child(0).text in ["修为","气海","经脉","筋骨","体魄","识海","神魂"] and row.get_child(1).editable:
			editable_growth_fields += 1
		if row.get_child(0).text in ["灵根","天资评级"] and not row.get_child(1).disabled:
			editable_growth_fields += 1
	_check(editable_growth_fields == 9, "the nine requested growth fields are editable in the save")
	editor.draft.cultivation = 48
	editor.draft.name = "林照溪·存档验收"
	editor.draft.role = "采药修士"
	editor.draft.location = "town_yunxi"
	editor.draft.age = 32
	editor.draft.lifespan = 140
	editor.draft.realm = 3
	_check(realm_visibility != null, "editor exposes the realm visibility flag")
	if realm_visibility != null:
		realm_visibility.button_pressed = false
		_check(editor.draft.realm_known == false, "turning off visibility keeps the numeric realm")
		realm_visibility.button_pressed = true
	editor.draft.greeting = "存档交谈验收"
	editor.draft.profile.gender = "女"
	editor.draft.profile.body_realm = "通脉二层"
	editor.draft.profile.sect = "青岳宗"
	editor.draft.profile.root = "水"
	editor.draft.profile.rank = "精英"
	for index in Model.FOUNDATION.size():
		editor.draft.profile.foundation[Model.FOUNDATION[index]] = 24 + index
	editor.draft.fortune_ids = ["fortune_036"]
	editor.draft.inventory = {"item_healing_powder":3}
	editor.draft.equipment_instances.erase("legacy_weapon")
	editor.draft.equipment_instances["save_edit_weapon"] = "equip_v1_iron_fine_sword"
	editor.draft.equipped.weapon = "save_edit_weapon"
	editor.draft.equipment_nurture.save_edit_weapon = 2
	editor.draft.techniques = {"technique_qi_flow":2}
	editor.draft.technique_slots = ["technique_qi_flow"]
	editor.draft.spells = {"skill_spirit_bolt":1}
	editor.draft.spell_slots = ["skill_spirit_bolt"]
	editor.draft.artifact_ids = [artifact]
	editor.draft.artifact_slots = [artifact]
	editor.draft.relations.npc_qin_shoushan = 38
	editor.draft.profile.contacts.npc_qin_shoushan = "存档关系验收"
	editor.draft.relations[edit_player_id] = 7
	editor.draft.profile.contacts[edit_player_id] = "玩家关系验收"
	editor._refresh_roster()
	_check(editor.get_node("Frame/Header/SaveChanges").text == "保存 *" and editor.get_node("Frame/Header/SaveStatus").text.contains("未保存 2 人"), "header shows two unsaved people")
	editor._apply_to_selected_save()
	var batch_save: Dictionary = saves.read(edit_path)
	var edited: Dictionary = batch_save.state.npcs.npc_lin_zhaoxi
	_check(editor.queued_drafts.is_empty() and batch_save.state.npcs.npc_qin_shoushan.fortunes.has("fortune_039") and edited.fortunes.has("fortune_036"), "one submission updates both queued NPCs")
	_check(edited.cultivation == 48 and edited.profile.root == "水" and edited.profile.rank == "精英", "cultivation, root and aptitude are written back")
	_check(edited.name == "林照溪·存档验收" and edited.role == "采药修士" and edited.location == "town_yunxi" and edited.age == 32 and edited.lifespan == 140 and edited.realm == 3, "identity, location, lifespan and realm are written back")
	_check(edited.greeting == "存档交谈验收" and edited.profile.gender == "女" and edited.profile.body_realm == "通脉二层" and edited.profile.sect == "青岳宗", "dialogue and dossier fields are written back")
	_check(edited.equipped.weapon == "save_edit_weapon" and edited.equipment_nurture.save_edit_weapon == 2 and not edited.equipment_instances.has("legacy_weapon"), "equipment, removal and nurture are written back")
	_check(edited.inventory.item_healing_powder == 3 and edited.techniques.technique_qi_flow == 2 and edited.spell_slots == ["skill_spirit_bolt"] and edited.artifact_slots == [artifact], "inventory, learned abilities and artifact slots are written back")
	_check(edited.relations.npc_qin_shoushan == 38 and edited.profile.contacts.npc_qin_shoushan == "存档关系验收", "relationship values and description are written back")
	_check(edited.relations[edit_player_id] == 7 and edited.profile.contacts[edit_player_id] == "玩家关系验收", "player relationship with description survives save validation")
	for index in Model.FOUNDATION.size():
		var key: String = Model.FOUNDATION[index]
		_check(edited.attributes[key] == 24 + index and edited.profile.foundation[key] == edited.attributes[key], "foundation is synchronized to live stats: " + key)
	_check(game.restore_save(batch_save).is_empty() and game.snapshot().npcs.npc_lin_zhaoxi.cultivation == 48, "the edited cultivator survives restore")
	var realm_info: Dictionary = preload("res://world/npc_interaction.gd").new().presentation(game.snapshot(),data,"npc_lin_zhaoxi")
	_check(edited.realm_known == true and realm_info.realm == "炼气三层", "saved visibility and level match the game display after restore")
	var malformed := batch_save.duplicate(true)
	malformed.state.npcs.npc_lin_zhaoxi.realm_known = "true"
	_check(not game.validate_save(malformed).is_empty(), "realm visibility must be a boolean")
	_check(editor.get_node("Frame/Header/SaveChanges").text == "保存" and editor.get_node("Frame/Header/SaveChanges").disabled, "successful save clears the dirty indicator")
	var latest_backup_order := 0
	for filename in DirAccess.get_files_at(backup_dir):
		var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(backup_dir.path_join(filename)))
		latest_backup_order = maxi(latest_backup_order,int(backup.npc_backup_order))
	_check(latest_backup_order == 7 and DirAccess.get_files_at(backup_dir).size() == 5, "batch rotates just one backup")
	editor._open(roster.npc_qin_shoushan)
	editor.draft.fortune_ids = ["fortune_036"]
	editor._stage_current_draft()
	editor._open(roster.npc_zhao_shanhe)
	editor.draft.fortune_ids = ["invalid_fortune"]
	var before_failed_batch := FileAccess.get_file_as_string(edit_path)
	editor._apply_to_selected_save()
	_check(FileAccess.get_file_as_string(edit_path) == before_failed_batch and editor.queued_drafts.size() == 2, "invalid second NPC rolls back the batch and keeps queued drafts")
	editor.queued_drafts.clear()
	for filename in backup_files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_dir.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(edit_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(edit_directory))
	var manager := root.get_node("GameManager")
	manager.set_process(false)
	var main: Control = load("res://ui/main/main.tscn").instantiate()
	root.add_child(main)
	var f1 := InputEventKey.new()
	f1.pressed = true
	f1.keycode = KEY_F1
	main._unhandled_key_input(f1)
	var disk_rows: Dictionary = Model.load_definitions(manager.catalog.tables).rows
	_check(main.debug_panel.visible and main.debug_npc_picker.item_count == disk_rows.size(), "F1 immediately lists saved definitions before entering a game")
	_check(main.debug_npc_import.disabled and main.debug_npc_sync.disabled, "F1 lists NPCs without a save but does not apply changes")
	for index in range(main.debug_npc_picker.item_count):
		var saved_id: String = main.debug_npc_picker.get_item_metadata(index)
		var row: Dictionary = disk_rows[saved_id]
		_check(main.debug_npc_picker.get_item_text(index).contains(row.name), "F1 shows saved NPC name " + row.name)
	var prototype_tables: Dictionary = manager.catalog.tables.duplicate()
	prototype_tables.npc_overrides = {}
	manager.operations.configure(prototype_tables)
	manager.operations.new_game("F1验收",data.rules.roots[0],base)
	main._refresh_debug_npcs()
	for index in range(main.debug_npc_picker.item_count):
		var saved_id: String = main.debug_npc_picker.get_item_metadata(index)
		if not manager.operations.snapshot().npcs.has(saved_id):
			continue
		main.debug_npc_picker.select(index)
		main._update_debug_npc_buttons()
		_check(not main.debug_npc_sync.disabled and main.debug_npc_sync.text == "同步气运", "Existing prototype is selectable for synchronization")
		main._import_debug_npc(true)
		_check(main._selected_debug_npc() == saved_id, "F1 keeps selected NPC when the list refreshes")
		_check(manager.operations.snapshot().npcs[saved_id].fortunes.size() == disk_rows[saved_id].fortune_ids.size(), "F1 applies the selected NPC's saved fortunes")
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("NPC_EDITOR_TEST ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
