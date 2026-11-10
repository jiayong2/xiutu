extends Control
const DISPLAY_PREFERENCES := "user://display_preferences.cfg"
const MIN_BRIGHTNESS := 55
const DEFAULT_BRIGHTNESS := 100

var screen_brightness := DEFAULT_BRIGHTNESS
var retreat_overlay: Control
var npc_overlay: Control
var debug_panel: PanelContainer
var debug_text: Label
var debug_npc_picker: ItemList
var debug_npc_import: Button
var debug_npc_sync: Button
var debug_npc_status: Label
var legend_editor: Control
var item_editor: Control
var monster_editor: Control
var skill_editor: Control
var content_manager: Control
var npc_editor_overlay: Control
var exploration_map_test: Control
var spirit_flow_trial: AcceptDialog
var content: Control
var page := "主菜单"
var recent_messages: Array=[]
var message_player_id := ""
var esc_return := "主界面"
var message := "欢迎来到仙途"
var selected_inn := ""
var selected_auction := ""
var selected_shop := "shop_qinglan_general"
var shop_view_state := {}
var shop_context := false
var observation_panel: AcceptDialog
var sect_tab := "Overview"
var sect_selected := ""
var sect_return := "地点场景"
var sect_map_open := false
var inventory_category := "全部"
var inventory_selected := ""
var inventory_return := "主界面"
var cave_view_state := {}
var home_cultivation_route := "qi"
var character_tab := "info"
var character_category := ""
var character_selected := ""
var technique_mode := "techniques"
var technique_selected := ""
var modal: AcceptDialog
var task_selected := ""
var task_category := "全部"
var world_place := ""
var world_npc := "npc_qin_shoushan"
var world_dialogue := ""
var world_previous_option := ""

func _ready() -> void:
	var preferences := ConfigFile.new()
	if preferences.load(DISPLAY_PREFERENCES) == OK:
		var saved: Variant = preferences.get_value("display", "brightness", DEFAULT_BRIGHTNESS)
		if saved is int:
			_apply_screen_brightness(saved)
	var theme := Theme.new()
	theme.default_font_size = 24
	self.theme = theme
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	debug_panel = PanelContainer.new()
	debug_panel.position = Vector2(220,120)
	debug_panel.size = Vector2(1480,800)
	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color("101820")
	debug_style.content_margin_left = 24
	debug_style.content_margin_right = 24
	debug_style.content_margin_top = 24
	debug_style.content_margin_bottom = 24
	debug_panel.add_theme_stylebox_override("panel",debug_style)
	add_child(debug_panel)
	var debug_body := VBoxContainer.new()
	debug_panel.add_child(debug_body)
	var trial_button := Button.new()
	trial_button.text = "灵气流转试算"
	trial_button.pressed.connect(_open_spirit_flow_trial)
	debug_body.add_child(trial_button)
	if OS.is_debug_build():
		var catalog_button := Button.new()
		catalog_button.text = "内容管理中心"
		catalog_button.pressed.connect(_open_content_manager)
		debug_body.add_child(catalog_button)
		if OS.has_feature("editor"):
			var legend_button := Button.new()
			legend_button.text = "地图图例与掉落配置"
			legend_button.pressed.connect(_open_legend_editor)
			debug_body.add_child(legend_button)
			var item_button := Button.new()
			item_button.text = "物品数据库管理器"
			item_button.pressed.connect(_open_item_editor)
			debug_body.add_child(item_button)
			var monster_button := Button.new()
			monster_button.text = "妖兽编辑器"
			monster_button.pressed.connect(_open_monster_editor)
			debug_body.add_child(monster_button)
			var skill_button := Button.new()
			skill_button.text = "功法·法术编辑器"
			skill_button.pressed.connect(_open_skill_editor)
			debug_body.add_child(skill_button)
		var npc_heading := Label.new()
		npc_heading.text = "NPC 编辑器已保存的人物"
		debug_body.add_child(npc_heading)
		debug_npc_picker = ItemList.new()
		debug_npc_picker.custom_minimum_size.y = 160
		debug_npc_picker.item_selected.connect(func(_index): _update_debug_npc_buttons())
		debug_body.add_child(debug_npc_picker)
		var npc_row := HBoxContainer.new()
		debug_body.add_child(npc_row)
		var reload_npcs := Button.new()
		reload_npcs.text = "重新读取 NPC 名单"
		reload_npcs.pressed.connect(_refresh_debug_npcs)
		npc_row.add_child(reload_npcs)
		debug_npc_import = Button.new()
		debug_npc_import.text = "导入到当前档"
		debug_npc_import.pressed.connect(_import_debug_npc)
		npc_row.add_child(debug_npc_import)
		debug_npc_sync = Button.new()
		debug_npc_sync.text = "同步装备与气运"
		debug_npc_sync.pressed.connect(_import_debug_npc.bind(true))
		npc_row.add_child(debug_npc_sync)
		var chen_battle := Button.new()
		chen_battle.text = "测试战斗 · 陈远"
		chen_battle.pressed.connect(_start_npc_test_battle.bind("npc_chen_yuan"))
		npc_row.add_child(chen_battle)
		var meng_battle := Button.new()
		meng_battle.text = "测试战斗 · 孟钧光"
		meng_battle.pressed.connect(_start_npc_test_battle.bind("npc_108088301ababcbd3e25e84b"))
		npc_row.add_child(meng_battle)
		debug_npc_status = Label.new()
		debug_npc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		debug_body.add_child(debug_npc_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	debug_body.add_child(scroll)
	debug_text = Label.new()
	debug_text.custom_minimum_size = Vector2(1400,0)
	debug_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(debug_text)
	debug_panel.hide()
	modal = AcceptDialog.new()
	add_child(modal)
	GameManager.time_ui_changed.connect(_world_time_refresh)
	GameManager.operations.changed.connect(_schedule_refresh)
	if OS.is_debug_build():
		add_child(preload("res://ui/main/player_debug_panel.gd").new())
	_refresh()

func _open_spirit_flow_trial() -> void:
	if spirit_flow_trial == null:
		spirit_flow_trial = preload("res://ui/main/spirit_flow_trial.gd").new()
		add_child(spirit_flow_trial)
	spirit_flow_trial.open()

func _schedule_refresh() -> void:
	if page=="天机楼" and content!=null and content.has_node("TianjiPage"):
		var snapshot: Dictionary = GameManager.operations.snapshot()
		if snapshot.get("player", {}).get("location", "")=="town_yunxi" and snapshot.get("battle_report", {}).get("confirmed", true):
			content.get_node("TianjiPage").set_spirit_stones(snapshot.player.spirit_stones)
			return
	if page=="公告栏" and content!=null and content.has_node("TownBoard"):
		content.get_node("TownBoard").sync(GameManager.operations.snapshot())
		return
	if page=="拍卖会" and content!=null and content.has_node("AuctionPage"):
		var view: Control = content.get_node("AuctionPage")
		if not view.submitting:
			view.refresh_state()
		return
	if page=="功法" and content!=null and content.has_node("TechniquePage"):
		var view: Control = content.get_node("TechniquePage")
		if view.mode=="spells":
			view.sync_spells()
			return
	if page=="战斗" and content!=null and content.has_node("BattlePage") and content.get_node("BattlePage").playing:return
	if page=="客栈" and content!=null and content.has_node("InnPage"):
		content.get_node("InnPage").refresh_data(recent_messages)
		return
	if npc_overlay!=null and is_instance_valid(npc_overlay):
		npc_overlay.refresh_data()
		return
	call_deferred("_refresh")

func _refresh() -> void:
	if content!=null and content.has_node("BattlePage") and content.get_node("BattlePage").playing:
		var battle_view: Control=content.get_node("BattlePage")
		battle_view.skip_animations()
		if not battle_view.presentation_finished.is_connected(_refresh):battle_view.presentation_finished.connect(_refresh,CONNECT_ONE_SHOT|CONNECT_DEFERRED)
		return
	if npc_overlay!=null and is_instance_valid(npc_overlay):return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("18232b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(bg)
	if page=="NPC对话":
		page="主界面"
		call_deferred("open_npc_interaction",world_npc)
	var s: Dictionary = GameManager.operations.snapshot()
	var player_id: String=s.get("player",{}).get("id","")
	if player_id!=message_player_id:
		recent_messages.clear()
		message_player_id=player_id
	if not s.get("battle_report",{}).get("confirmed",true) and page not in ["主菜单","创建角色","读取存档"]:page="战斗"
	if page=="宗门驻地" and GameManager.operations.sect_residence_access(s.get("player",{}).get("location",""))!="":
		page="地点场景"
	if page=="天机楼" and s.get("player", {}).get("location", "")!="town_yunxi":
		page="地点场景"
	if page == "主菜单":
		_menu()
	elif page == "创建角色":
		_creation()
	elif s.is_empty() and page not in ["设置","读取存档"]:
		_label(content,"请先从主菜单创建角色",Rect2(100,100,1700,100))
		_button(content,"返回主菜单",Rect2(100,240,300,64),func(): _navigate("主菜单"))
	elif page in ["主界面","地点场景"]:
		_home(s)
	elif page == "地图":
		_world_page(s)
	elif page == "宗门驻地":
		_sect_residence(s.player.location)
	elif page == "客栈":
		_inn_page()
	elif page == "拍卖会":
		_auction_page()
	elif page == "天机楼":
		var view: Control = preload("res://ui/tianji/tianji_page.tscn").instantiate()
		content.add_child(view)
		view.set_spirit_stones(s.player.spirit_stones)
		view.closed.connect(func(): _navigate("地点场景"))
	elif page == "商店":
		_shop_home(s)
	elif page == "商店交易":
		_shop_page()
	elif page == "宗门":
		_sect_page()
	elif page == "背包":
		_inventory_page()
	elif page == "洞府":
		_cave_page()
	elif page == "角色":
		_character_page()
	elif page == "功法":
		_technique_page()
	elif page == "战斗":
		_battle_page()
	elif page == "任务":
		_task_page(s)
	elif page == "公告栏":
		_town_board(s)
	else:
		_subpage(s)
	if page not in ["主界面","任务","地图","地点场景","NPC对话","客栈","商店","商店交易","功法","角色","洞府","背包","宗门","宗门驻地","战斗","拍卖会","公告栏","天机楼"]:
		_label(content,message,Rect2(32,1040,1856,40),20)
	if not GameManager.boot_ok:
		_label(content,"启动配置错误："+GameManager.repository.last_error,Rect2(32,950,1856,80),24)

func _menu() -> void:
	_label(content,"仙途",Rect2(720,150,600,100),48)
	var choices := ["新游戏","继续游戏","读取存档","设置","退出"]
	for i in range(choices.size()):
		var title: String = choices[i]
		_button(content,title,Rect2(720,300+i*110,480,82),func():
			match title:
				"新游戏": _navigate("创建角色")
				"继续游戏": _continue()
				"读取存档": _navigate("读取存档")
				"设置":
					esc_return = "主菜单"
					_navigate("设置")
				"退出": get_tree().quit()
		)

func _creation() -> void:
	_label(content,"创建角色 · 青岚散修",Rect2(500,140,1000,80),36)
	var name_field := LineEdit.new()
	name_field.text = "无名散修"
	name_field.max_length = 24
	name_field.position = Vector2(600,280)
	name_field.size = Vector2(720,70)
	content.add_child(name_field)
	var roots := OptionButton.new()
	roots.position = Vector2(600,400)
	roots.size = Vector2(720,70)
	for root in GameManager.catalog.tables.rules.roots:
		roots.add_item(root)
	content.add_child(roots)
	var innate := OptionButton.new()
	innate.position = Vector2(600,510)
	innate.size = Vector2(720,70)
	innate.add_item("先天天赋 · 无")
	innate.set_item_metadata(0,"")
	var definitions: Dictionary = preload("res://gameplay/character/player_fortunes.gd").DEFINITIONS
	for id in definitions:
		var definition: Dictionary = definitions[id]
		if definition.kind != "innate" or not definition.acquisition.connected:
			continue
		innate.add_item("先天天赋 · " + str(definition.name))
		innate.set_item_metadata(innate.item_count-1,id)
		innate.get_popup().set_item_tooltip(innate.item_count-1,"\n".join(preload("res://gameplay/character/player_fortunes.gd").describe(definition)))
	content.add_child(innate)
	_button(content,"踏入仙途",Rect2(600,650,720,82),func():
		var error: String = GameManager.new_game(name_field.text,roots.get_item_text(roots.selected),str(innate.get_selected_metadata()))
		message = error if not error.is_empty() else "来到青岚镇，请拜访秦守山。"
		if error.is_empty(): page = "主界面"
		_schedule_refresh())
	_button(content,"返回",Rect2(600,780,720,82),func(): _navigate("主菜单"))

func _continue() -> void:
	var error: String = GameManager.load_game()
	message = error if not error.is_empty() else "存档读取成功"
	if error.is_empty(): page = "主界面"
	_schedule_refresh()

func _home(s: Dictionary) -> void:
	if s.player.age >= s.player.lifespan:
		message = "寿元已尽，本段仙途结束。可查看记录、保存或返回主菜单。"
	var home := preload("res://ui/main/home_view.tscn").instantiate()
	content.add_child(home)
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.navigate.connect(_navigate)
	home.action_requested.connect(_command)
	home.exploration_map_requested.connect(_open_exploration_map_test)
	home.npc_requested.connect(open_npc_interaction)
	home.shop_requested.connect(func(id: String):_open_shop(id))
	home.auction_requested.connect(func(id: String): selected_auction=id; _navigate("拍卖会"))
	home.quest_requested.connect(func(id: String):task_selected=id;task_category="全部";_navigate("任务"))
	home.cave_requested.connect(func(tab: String):cave_view_state.tab=tab;_navigate("洞府"))
	home.route_changed.connect(func(route: String):home_cultivation_route=route)
	home.build(s, GameManager.catalog.tables, message,GameManager.operations,recent_messages,home_cultivation_route)
	if not s.battle.is_empty():
		page = "战斗"
		_schedule_refresh()

func _subpage(s: Dictionary) -> void:
	_label(content,page,Rect2(32,16,1400,80),36)
	if page == "设置":
		_button(content,"返回（ESC）",Rect2(1540,24,348,64),func(): _navigate(esc_return))
	else:
		_button(content,"返回主界面",Rect2(1540,24,348,64),func(): _navigate("主界面"))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(32,120)
	scroll.size = Vector2(1856,880)
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = 1800
	rows.add_theme_constant_override("separation",16)
	scroll.add_child(rows)
	var p: Dictionary = s.get("player",{})
	var data: Dictionary = GameManager.catalog.tables
	match page:
		"修炼", "淬体":
			var route: String = "body" if page=="淬体" else "qi"
			var growth: RefCounted = GameManager.operations.cultivation
			var realm: String = growth.body_realm_name(p,data) if route=="body" else _realm(p.realm)
			var required: int = growth.requirement(p,route,data)
			var label: String = "炼体修为" if route=="body" else "修为"
			_text(rows,"%s，%s %d / %s。修炼不恢复生命灵力。" % [realm,label,growth.progress(p,route),str(required) if required>0 else "已达上限"])
			for days in [1,3,10]:
				_row(rows,"%s%s日" % [page,days],[["开始","practice",{"days":days,"route":route}]])
			var breakthrough: String = "突破（耗时 %d 日）" % growth.breakthrough_days(p,route,data)
			if route=="qi" and p.realm==9:
				breakthrough += " · 筑基丹 ×1，成功率 80%"
			_row(rows,breakthrough,[["确认晋升","promote",{"route":route}]])
		"天下":
			_text(rows,"\n".join(s.news) if not s.news.is_empty() else "暂无世界新闻；到访云溪城后启用月度模拟。")
			for npc in s.npcs.values(): _text(rows,"%s · 炼气%s层 · %s岁 · %s · %s" % [npc.name,npc.realm,npc.age,_place(npc.location),"在世" if npc.alive else "已故"])
		"设置":
			_add_display_settings(rows)
			var save_button := Button.new()
			save_button.text = "保存新版本（保留已有存档）"
			save_button.custom_minimum_size.y = 64
			save_button.pressed.connect(func(): message = GameManager.save_game(); _schedule_refresh())
			rows.add_child(save_button)
			var load_button := Button.new()
			load_button.text = "读取存档"
			load_button.custom_minimum_size.y = 64
			load_button.pressed.connect(func(): _navigate("读取存档"))
			rows.add_child(load_button)
			var menu_button := Button.new()
			menu_button.text = "返回主菜单（请先保存）"
			menu_button.custom_minimum_size.y = 64
			menu_button.pressed.connect(func(): _navigate("主菜单"))
			rows.add_child(menu_button)
		"读取存档":
			var paths: Array = GameManager.saves.list_saves()
			if paths.is_empty(): _text(rows,"暂无存档")
			for path in paths:
				var button := Button.new()
				button.text = path.get_file()
				button.custom_minimum_size.y = 64
				button.pressed.connect(func():
					var error: String = GameManager.load_game(path)
					message = error if not error.is_empty() else "读取成功"
					if error.is_empty(): page = "主界面"
					_schedule_refresh())
				rows.add_child(button)

func _add_display_settings(rows: VBoxContainer) -> void:
	_text(rows, "画面亮度")
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 16)
	rows.add_child(controls)
	var slider := HSlider.new()
	slider.name = "BrightnessSlider"
	slider.min_value = MIN_BRIGHTNESS
	slider.max_value = DEFAULT_BRIGHTNESS
	slider.step = 1
	slider.value = screen_brightness
	slider.custom_minimum_size = Vector2(420, 48)
	slider.tooltip_text = "向左调暗游戏画面"
	controls.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 90
	value.text = "%d%%" % screen_brightness
	controls.add_child(value)
	var reset := Button.new()
	reset.text = "恢复默认"
	controls.add_child(reset)
	var feedback := Label.new()
	rows.add_child(feedback)
	# Keep drag previews in memory and write once when the slider is released.
	slider.drag_started.connect(func(): slider.set_meta("previewing", true))
	slider.drag_ended.connect(func(changed: bool):
		slider.set_meta("previewing", false)
		if changed:
			_save_display_preferences(feedback))
	slider.value_changed.connect(func(level: float):
		_apply_screen_brightness(int(level))
		value.text = "%d%%" % screen_brightness
		if not slider.get_meta("previewing", false):
			_save_display_preferences(feedback))
	slider.tree_exiting.connect(func():
		if slider.get_meta("previewing", false):
			_save_display_preferences(feedback))
	reset.pressed.connect(func(): slider.value = DEFAULT_BRIGHTNESS)

func _apply_screen_brightness(level: int) -> void:
	screen_brightness = clampi(level, MIN_BRIGHTNESS, DEFAULT_BRIGHTNESS)
	var dimmer: ColorRect = $DisplayLayer/ScreenDimmer
	dimmer.color = Color(0, 0, 0, 1.0 - screen_brightness / 100.0)
	dimmer.visible = screen_brightness < DEFAULT_BRIGHTNESS

func _save_display_preferences(feedback: Label) -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("display", "brightness", screen_brightness)
	var result := preferences.save(DISPLAY_PREFERENCES)
	feedback.text = "" if result == OK else "亮度已应用，但未能保存显示偏好。"

func _command(action: String, args: Dictionary) -> void:
	if action == "sell" and args.get("item","") == "material_wolf_fang" and not args.get("confirmed",false):
		var dialog := ConfirmationDialog.new()
		dialog.dialog_text = "灰狼牙是任务所需材料。确认出售%d枚？" % int(args.get("quantity",1))
		add_child(dialog)
		dialog.confirmed.connect(func(): var confirmed := args.duplicate(); confirmed.confirmed = true; _command(action,confirmed); dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
		return
	var result: Dictionary = GameManager.request(action,args,args.get("_request_id",""))
	message = result.message
	if action in ["buy","sell","sell_equipment"]:
		var item_id: String=args.get("item","")
		message=("%s%s ×%d" % ["购买" if action=="buy" else "出售",GameManager.operations.data.items.get(item_id,{}).get("name","物品"),args.get("quantity",1)])+("成功" if result.success else "失败："+result.message)
	_record_message(message)
	if result.success and action in ["retreat","retreat_target"]:call_deferred("_show_retreat_report",GameManager.operations.snapshot().retreat_report)
	if result.success and not GameManager.operations.snapshot().battle.is_empty(): page = "战斗"
	_schedule_refresh()

func _row(parent: Node, title: String, commands: Array) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 850
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	for command in commands:
		var button := Button.new()
		button.text = command[0]
		button.custom_minimum_size = Vector2(240,64)
		button.pressed.connect(func(): _command(command[1],command[2]))
		row.add_child(button)

func _text(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1750
	parent.add_child(label)

func _button(parent: Node, text: String, rect: Rect2, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(callback)
	parent.add_child(button)

func _label(parent: Node, text: String, rect: Rect2, font_size: int = 24) -> void:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _navigate(destination: String) -> void:
	if destination=="客栈":
		for inn in GameManager.operations.data.inns.values():
			if inn.location==GameManager.operations.snapshot().player.location:selected_inn=inn.id
		message="进入"+str(GameManager.operations.data.inns.get(selected_inn,{}).get("name","客栈"))
		_record_message(message)
	if destination=="NPC对话":
		open_npc_interaction(world_npc)
		return
	if npc_overlay!=null and is_instance_valid(npc_overlay):npc_overlay.close()
	if destination=="地点场景" and page=="NPC对话" and shop_context:destination="商店"
	if destination not in ["商店","商店交易","NPC对话"]:shop_context=false
	if destination == "洞府":
		var current: Dictionary=GameManager.operations.snapshot()
		if not current.is_empty() and current.player.location != "cave_qinglan":
			var result: Dictionary=GameManager.request("travel",{"id":"cave_qinglan"})
			if not result.success:
				message=result.message
				_schedule_refresh()
				return
	if destination == "背包" and page != "背包":
		inventory_return = page
		inventory_category = "全部"
		inventory_selected = ""
	if destination == "宗门" and page not in ["宗门","宗门驻地"] and not sect_map_open:
		sect_return = page
		var snapshot: Dictionary=GameManager.operations.snapshot()
		var local_sect: Dictionary=GameManager.operations.sect_at_location(snapshot.player.location)
		if snapshot.sect.is_empty() and not local_sect.is_empty():
			sect_selected=local_sect.id
	if destination == "宗门驻地" and page in ["主界面","地点场景"]:
		sect_return=page
	if destination!="地图":
		sect_map_open=false
	page = destination
	_schedule_refresh()

func _realm(realm: int) -> String:
	return preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(realm,"qi",GameManager.catalog.tables)

func _place(id: String) -> String:
	return preload("res://ui/world/world_page.gd").place_name(id,GameManager.catalog.tables)

func _date(hours: int) -> String:
	var day: int = int(hours/24)
	return "玄灵历%s年%s月%s日 %02d:00" % [int(day/360)+1,int(day%360/30)+1,day%30+1,hours%24]

func _quest_summary(s: Dictionary) -> String:
	var lines := ""
	for id in s.quests: lines += "\n%s：%s" % [GameManager.catalog.tables.quests[id].name,_quest_status(s.quests[id].status)]
	return lines

func _quest_status(value: String) -> String:
	return {"ACTIVE":"进行中","COMPLETED":"已完成"}.get(value,value)

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(exploration_map_test) and exploration_map_test.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_exploration_map_test()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(skill_editor):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			skill_editor.request_close()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(content_manager):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			content_manager.request_close()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(npc_editor_overlay):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_npc_editor_overlay()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(monster_editor):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			monster_editor.request_close()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(item_editor):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			item_editor.request_close()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(legend_editor):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			legend_editor.request_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if retreat_overlay!=null and is_instance_valid(retreat_overlay):
			retreat_overlay.close()
		elif npc_overlay!=null and is_instance_valid(npc_overlay):
			npc_overlay.back()
		elif observation_panel!=null and is_instance_valid(observation_panel) and observation_panel.visible:
			observation_panel.hide()
		elif page=="客栈":content.get_node("InnPage").back()
		elif page=="拍卖会":content.get_node("AuctionPage").back()
		elif page=="天机楼":_navigate("地点场景")
		elif page=="公告栏":_navigate("主界面")
		elif page=="商店交易" or (page=="NPC对话" and shop_context):_navigate("商店")
		elif page=="商店":_navigate("地点场景")
		elif page=="设置":_navigate(esc_return)
		elif page=="主菜单" or (not GameManager.operations.snapshot().is_empty() and page!="战斗"):
			esc_return=page
			_navigate("设置")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		toggle_debug()
		get_viewport().set_input_as_handled()

func _open_exploration_map_test(map_id: String) -> void:
	if is_instance_valid(exploration_map_test):
		return
	var state: Dictionary = GameManager.operations.snapshot()
	if state.is_empty() or not state.get("battle", {}).is_empty():
		return
	var result: Dictionary = GameManager.request("exploration_enter", {"map_id": map_id})
	if not result.success:
		message = result.message
		_schedule_refresh()
		return
	exploration_map_test = preload("res://ui/exploration/map_test.tscn").instantiate()
	exploration_map_test.runtime_state = GameManager.operations.exploration_snapshot
	exploration_map_test.runtime_request = GameManager.request
	exploration_map_test.save_game = GameManager.save_game
	exploration_map_test.closed.connect(_close_exploration_map_test)
	exploration_map_test.encounter_started.connect(_show_exploration_battle)
	add_child(exploration_map_test)

func _close_exploration_map_test() -> void:
	var result: Dictionary = GameManager.request("exploration_leave")
	if not result.success:
		exploration_map_test.get_node("%Status").text = result.message
		return
	_free_exploration_map_test()

func _free_exploration_map_test() -> void:
	exploration_map_test.queue_free()
	exploration_map_test = null

func _show_exploration_battle() -> void:
	exploration_map_test.hide()
	_navigate("战斗")

func _open_legend_editor() -> void:
	if not OS.has_feature("editor") or is_instance_valid(legend_editor):
		return
	legend_editor = preload("res://ui/exploration/legend_editor.tscn").instantiate()
	legend_editor.catalog = GameManager.catalog.tables
	legend_editor.closed.connect(_close_legend_editor)
	debug_panel.hide()
	add_child(legend_editor)

func _close_legend_editor() -> void:
	legend_editor.queue_free()
	legend_editor = null
	debug_panel.show()

func _open_content_manager() -> void:
	if not OS.is_debug_build() or is_instance_valid(content_manager):
		return
	content_manager = preload("res://ui/content_manager/content_manager.tscn").instantiate()
	if GameManager.catalog != null:
		content_manager.catalog = GameManager.catalog.tables
	content_manager.closed.connect(_close_content_manager)
	content_manager.editor_requested.connect(_open_editor_from_catalog)
	debug_panel.hide()
	add_child(content_manager)

func _close_content_manager() -> void:
	if is_instance_valid(content_manager):
		content_manager.queue_free()
	content_manager = null
	debug_panel.show()

func _open_editor_from_catalog(kind: String, id: String) -> void:
	match kind:
		"item":
			_open_item_editor()
			if is_instance_valid(item_editor) and item_editor.has_method("focus_item"):
				item_editor.focus_item(id)
			if is_instance_valid(content_manager):
				content_manager.hide()
		"monster":
			_open_monster_editor()
			if is_instance_valid(monster_editor) and monster_editor.has_method("focus_monster"):
				monster_editor.focus_monster(id)
			if is_instance_valid(content_manager):
				content_manager.hide()
		"technique", "spell":
			_open_skill_editor(kind, id)
			if is_instance_valid(content_manager):
				content_manager.hide()
		"npc":
			_open_npc_editor_overlay(id)

func _open_npc_editor_overlay(id: String) -> void:
	if is_instance_valid(npc_editor_overlay):
		return
	npc_editor_overlay = preload("res://addons/npc_editor/editor.tscn").instantiate()
	npc_editor_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid(content_manager):
		content_manager.hide()
	debug_panel.hide()
	add_child(npc_editor_overlay)
	if npc_editor_overlay.has_method("focus_npc"):
		npc_editor_overlay.call_deferred("focus_npc", id)

func _close_npc_editor_overlay() -> void:
	if is_instance_valid(npc_editor_overlay):
		npc_editor_overlay.queue_free()
	npc_editor_overlay = null
	if is_instance_valid(content_manager):
		content_manager.show()
	else:
		debug_panel.show()

func _open_skill_editor(kind: String = "", id: String = "") -> void:
	if not OS.has_feature("editor"):
		return
	if is_instance_valid(skill_editor):
		if not kind.is_empty():
			skill_editor.focus_entry(kind, id)
		return
	if not GameManager.boot_ok:
		message = "配置未通过启动校验，不能打开功法·法术编辑器"
		_refresh()
		return
	var state: Dictionary = GameManager.operations.snapshot()
	if not state.is_empty() and not state.get("battle", {}).is_empty():
		message = "战斗进行中，暂不能打开功法·法术编辑器"
		_refresh()
		return
	skill_editor = preload("res://ui/skill_editor/skill_editor.tscn").instantiate()
	skill_editor.catalog = GameManager.catalog.tables
	skill_editor.runtime = state
	skill_editor.propagate_to_game = true
	skill_editor.closed.connect(_close_skill_editor)
	debug_panel.hide()
	add_child(skill_editor)
	if not kind.is_empty():
		skill_editor.focus_entry(kind, id)

func _close_skill_editor() -> void:
	if is_instance_valid(skill_editor):
		skill_editor.queue_free()
	skill_editor = null
	if is_instance_valid(content_manager):
		content_manager.show()
	else:
		debug_panel.show()
	_schedule_refresh()

func _open_item_editor() -> void:
	if not OS.has_feature("editor") or is_instance_valid(item_editor):
		return
	if not GameManager.boot_ok:
		message = "配置未通过启动校验，不能打开物品管理器"
		_refresh()
		return
	var state: Dictionary = GameManager.operations.snapshot()
	if not state.is_empty() and not state.get("battle", {}).is_empty():
		message = "战斗进行中，暂不能打开物品管理器"
		_refresh()
		return
	item_editor = preload("res://ui/item_editor/item_editor.tscn").instantiate()
	item_editor.catalog = GameManager.catalog.tables
	item_editor.runtime = state
	item_editor.data_path = preload("res://core/items/item_database.gd").PATH
	item_editor.propagate_to_game = true
	item_editor.closed.connect(_close_item_editor)
	debug_panel.hide()
	add_child(item_editor)

func _close_item_editor() -> void:
	item_editor.queue_free()
	item_editor = null
	if is_instance_valid(content_manager):
		content_manager.show()
	else:
		debug_panel.show()
	_schedule_refresh()

func _open_monster_editor() -> void:
	if not OS.has_feature("editor") or is_instance_valid(monster_editor):
		return
	if not GameManager.boot_ok:
		message = "配置未通过启动校验，不能打开妖兽编辑器"
		_refresh()
		return
	var state: Dictionary = GameManager.operations.snapshot()
	if not state.is_empty() and not state.get("battle", {}).is_empty():
		message = "战斗进行中，暂不能打开妖兽编辑器"
		_refresh()
		return
	monster_editor = preload("res://ui/monster_editor/monster_editor.tscn").instantiate()
	monster_editor.catalog = GameManager.catalog.tables
	monster_editor.runtime = state
	monster_editor.data_path = preload("res://core/monsters/monster_database.gd").PATH
	monster_editor.skills_data_path = preload("res://core/monsters/monster_database.gd").SKILLS_PATH
	monster_editor.propagate_to_game = true
	monster_editor.closed.connect(_close_monster_editor)
	monster_editor.test_battle_requested.connect(_start_monster_test_battle)
	debug_panel.hide()
	add_child(monster_editor)

func _close_monster_editor() -> void:
	if is_instance_valid(monster_editor):
		monster_editor.queue_free()
	monster_editor = null
	if is_instance_valid(content_manager):
		content_manager.show()
	else:
		debug_panel.show()
	_schedule_refresh()

func _start_npc_test_battle(npc_id: String) -> void:
	var result: Dictionary = GameManager.request("debug_start_npc_battle", {"npc_id": npc_id})
	if not result.success:
		if debug_npc_status != null:
			debug_npc_status.text = result.message
		return
	debug_panel.hide()
	page = "战斗"
	message = result.message
	_schedule_refresh()

func _start_monster_test_battle(monster_id: String) -> void:
	if not is_instance_valid(monster_editor):
		return
	var result: Dictionary = GameManager.request("debug_start_battle", {"monster_id": monster_id})
	if not result.success:
		monster_editor.show_test_battle_error(result.message)
		return
	_close_monster_editor()
	debug_panel.hide()
	page = "战斗"
	_schedule_refresh()

func toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible
	if debug_panel.visible:
		if OS.is_debug_build():
			_refresh_debug_npcs()
		debug_text.text = "开发调试 · F1关闭\n状态：%s\n配置：%s\n运行状态：%s\n日志：%s\n\n%s" % [
			GameManager.boot_ok,JSON.stringify(GameManager.repository.starting_character()),
			JSON.stringify(GameManager.operations.snapshot()),JSON.stringify(AppLog.snapshot()),
			preload("res://gameplay/character/player_fortunes.gd").debug_report()]

func _refresh_debug_npcs() -> void:
	var previous_id := _selected_debug_npc()
	debug_npc_picker.clear()
	debug_npc_import.disabled = true
	debug_npc_sync.disabled = true
	var state: Dictionary = GameManager.operations.snapshot()
	var definitions: Dictionary = GameManager.debug_npc_definitions()
	if not definitions.error.is_empty():
		debug_npc_status.text = definitions.error
		return
	var selected := 0
	for id in definitions.rows:
		var npc: Dictionary = definitions.rows[id]
		var place: String = preload("res://ui/world/world_page.gd").place_name(npc.location, GameManager.catalog.tables)
		var index := debug_npc_picker.add_item("%s · %s · %d 条气运" % [npc.name, place, npc.fortune_ids.size() + npc.profile.get("innate_fortune", []).size() + npc.profile.get("acquired_fortune", []).size()])
		debug_npc_picker.set_item_metadata(index, id)
		if id == previous_id:
			selected = index
	if debug_npc_picker.item_count > 0:
		debug_npc_picker.select(selected)
	_update_debug_npc_buttons()
	if debug_npc_picker.item_count == 0:
		debug_npc_status.text = "未读到已保存的 NPC。请先在 NPC 编辑器保存，再点「重新读取 NPC 名单」。"
	elif state.is_empty():
		debug_npc_status.text = "已读取 %d 名人物。进入游戏或读档后可同步。" % debug_npc_picker.item_count
	else:
		debug_npc_status.text = "已读取 %d 名人物。点选人物后可导入或同步。" % debug_npc_picker.item_count

func _selected_debug_npc() -> String:
	var selected := debug_npc_picker.get_selected_items()
	return str(debug_npc_picker.get_item_metadata(selected[0])) if not selected.is_empty() else ""

func _update_debug_npc_buttons() -> void:
	var id := _selected_debug_npc()
	var state: Dictionary = GameManager.operations.snapshot()
	var npc: Dictionary = state.get("npcs", {}).get(id, {})
	debug_npc_import.disabled = id.is_empty() or state.is_empty() or not npc.is_empty()
	debug_npc_sync.disabled = id.is_empty() or npc.is_empty()
	var authored: bool = npc.get("authored", false)
	debug_npc_sync.text = "同步装备与气运" if authored else "同步气运"

func _import_debug_npc(refresh: bool = false) -> void:
	var id := _selected_debug_npc()
	if id.is_empty():
		return
	var result: Dictionary = GameManager.debug_import_npc(id, refresh)
	if result.success:
		_refresh_debug_npcs()
	debug_npc_status.text = result.message

func _town_board(snapshot: Dictionary) -> void:
	var board: Control = preload("res://ui/quest/town_board.tscn").instantiate()
	content.add_child(board)
	board.closed.connect(func():_navigate("主界面"))
	board.refresh_requested.connect(func():board.sync(GameManager.operations.snapshot(), "已同步当前榜文"))
	board.accept_requested.connect(func(id: String):
		var result: Dictionary = GameManager.request("accept_announcement", {"id":id})
		board.sync(GameManager.operations.snapshot(), "已接取委托" if result.success else result.message)
	)
	board.claim_requested.connect(func(id: String, round_number: int):
		var result: Dictionary = GameManager.request("claim_announcement", {"id":id,"round":round_number})
		board.sync(GameManager.operations.snapshot(), result.message)
	)
	board.tasks_requested.connect(func(id: String):
		task_selected=id
		task_category="进行中"
		_navigate("任务")
	)
	board.place_requested.connect(func(id: String):
		world_place=id
		_navigate("地图")
	)
	board.bind_data(snapshot, GameManager.catalog.tables)

func _task_page(snapshot: Dictionary) -> void:
	var task: Control = preload("res://ui/quest/task_page.tscn").instantiate()
	content.add_child(task)
	task.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	task.navigate.connect(_navigate)
	task.npc_requested.connect(open_npc_interaction)
	task.action_requested.connect(_command)
	task.selection_changed.connect(func(selected: String, category: String): task_selected = selected; task_category = category)
	task.bind_data(snapshot, GameManager.catalog.tables, task_selected, task_category, message)

func _world_page(snapshot: Dictionary) -> void:
	var path: String = {"地图":"world_map","地点场景":"location_scene","NPC对话":"npc_dialogue"}[page]
	var view: Control = load("res://ui/world/"+path+".tscn").instantiate()
	content.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.navigate.connect(func(destination: String):
		_navigate("宗门" if page=="地图" and sect_map_open else destination))
	view.action_requested.connect(_world_action)
	view.place_selected.connect(func(id: String): world_place = id)
	view.npc_requested.connect(open_npc_interaction)
	view.shop_requested.connect(func(id: String): _open_shop(id))
	view.bind_data(snapshot,GameManager.catalog.tables,GameManager.operations.stats(),world_place,world_npc,message,world_dialogue,world_previous_option)

func _world_action(action: String, args: Dictionary) -> void:
	var result: Dictionary = GameManager.request(action,args)
	message = result.message
	_record_message(message)
	if result.success:
		if action == "travel":
			sect_map_open=false
			page="地点场景"
		elif action in ["talk","npc_option"]:
			world_dialogue = result.message
			world_previous_option = args.get("option","")
		if not GameManager.operations.snapshot().battle.is_empty(): page = "战斗"
	_schedule_refresh()

func _shop_page() -> void:
	var view: Control = preload("res://ui/shop/shop_page.tscn").instantiate()
	content.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.navigate.connect(func(_destination: String):_navigate("商店"))
	view.action_requested.connect(_command)
	view.selection_changed.connect(func(mode: String, category: String, key: String, quantity: int): shop_view_state[selected_shop] = {"mode":mode,"category":category,"key":key,"quantity":quantity})
	var saved: Dictionary = shop_view_state.get(selected_shop,{})
	view.bind_data(GameManager.operations,selected_shop,saved.get("mode","购买"),saved.get("category","全部"),saved.get("key",""),int(saved.get("quantity",1)),message)


func _technique_page() -> void:
	var view: Control = preload("res://ui/technique/technique_page.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.action_requested.connect(_command)
	view.selection_changed.connect(func(mode: String, key: String): technique_mode=mode;technique_selected=key)
	view.bind_data(GameManager.operations,technique_mode,technique_selected,message)

func _auction_page() -> void:
	if not GameManager.operations.data.auctions.has(selected_auction):
		_label(content,"当前没有可进入的拍卖会",Rect2(32,30,1400,60))
		_button(content,"返回地点",Rect2(1550,30,300,60),func(): _navigate("地点场景"))
		return
	var view: Control = preload("res://ui/auction/auction_page.tscn").instantiate()
	content.add_child(view)
	view.closed.connect(func(): _navigate("地点场景"))
	view.bind_data(GameManager.operations,selected_auction)

func _character_page() -> void:
	var view: Control = preload("res://ui/character/character_page.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.action_requested.connect(_command)
	view.selection_changed.connect(func(tab: String, category: String, key: String): character_tab=tab;character_category=category;character_selected=key)
	view.bind_data(GameManager.operations,character_tab,character_category,character_selected,message)

func _cave_page() -> void:
	var view: Control = preload("res://ui/cave/cave_page.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.action_requested.connect(_command)
	view.selection_changed.connect(func(saved: Dictionary): cave_view_state=saved)
	view.bind_data(GameManager.operations,cave_view_state,message)

func _inventory_page() -> void:
	var view: Control = preload("res://ui/inventory/inventory_page.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.action_requested.connect(_command)
	view.selection_changed.connect(func(category: String, key: String): inventory_category=category;inventory_selected=key)
	view.bind_data(GameManager.operations,inventory_category,inventory_selected,inventory_return,message)

func _sect_page() -> void:
	var view: Control = preload("res://ui/sect/sect_page.tscn").instantiate()
	content.add_child(view)
	view.close_requested.connect(func():_navigate(sect_return))
	view.map_requested.connect(func(location: String):
		world_place=location
		sect_map_open=true
		_navigate("地图"))
	view.residence_requested.connect(func(location: String):
		var reason: String=GameManager.operations.sect_residence_access(location)
		if reason.is_empty():
			_navigate("宗门驻地")
		else:
			message=reason
			_schedule_refresh())
	view.npc_requested.connect(open_npc_interaction)
	view.action_requested.connect(_command)
	view.selection_changed.connect(func(tab: String, selected: String): sect_tab=tab;sect_selected=selected)
	view.bind_data(GameManager.operations,sect_tab,sect_selected,message)

func _sect_residence(location: String) -> void:
	var view: Control = preload("res://ui/sect/sect_residence.tscn").instantiate()
	content.add_child(view)
	view.overview_requested.connect(func(tab: String):
		sect_selected=GameManager.operations.sect_at_location(location).id
		sect_tab=tab
		_navigate("宗门"))
	view.map_requested.connect(func():
		world_place=location
		_navigate("地图"))
	view.npc_requested.connect(open_npc_interaction)
	view.shop_requested.connect(_open_shop)
	view.bind_data(GameManager.operations,location)

func _battle_page() -> void:
	var view = preload("res://ui/battle/battle_page.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.action_requested.connect(_battle_command)
	var report: Dictionary=GameManager.operations.snapshot().get("battle_report",{})
	view.bind_data(GameManager.operations,message,report.get("background",{}) if not report.get("confirmed",true) else {})
	var battle: Dictionary = GameManager.operations.snapshot().battle
	if battle.get("phase")=="active" and GameManager.operations.battle.needs_round(battle):
		_resume_battle_round.call_deferred(view)
	if not report.get("confirmed",true):
		view.field("Round").text="第 %d 回合" % report.turns
		for button in view.find_children("*","Button",true,false):
			button.disabled=true
			button.focus_mode=Control.FOCUS_NONE
		var overlay=preload("res://ui/battle/battle_result_overlay.tscn").instantiate()
		content.add_child(overlay)
		overlay.bind_data(report,GameManager.operations.data)
		overlay.confirm_requested.connect(func(id: String):
			var result: Dictionary=GameManager.request("confirm_battle_result",{"id":id})
			if result.success:
				var latest: Dictionary = GameManager.operations.snapshot()
				world_place = latest.player.location
				if report.background.battle.has("exploration_node") and latest.get("exploration_run", {}).get("active", false):
					_navigate("主界面")
					if is_instance_valid(exploration_map_test):
						exploration_map_test.resume_run()
						exploration_map_test.show()
					else:
						_open_exploration_map_test(latest.exploration_run.map.map_id)
				else:
					if is_instance_valid(exploration_map_test):
						_free_exploration_map_test()
					_navigate("地点场景"))

func _record_message(text: String) -> void:
	if text.is_empty():return
	recent_messages.append(text)
	if recent_messages.size()>50:recent_messages.pop_front()

func _open_shop(id: String) -> void:
	selected_shop=id
	shop_context=true
	message="进入"+str(GameManager.operations.data.shops[id].name)
	_record_message(message)
	_navigate("商店")

func _shop_home(snapshot: Dictionary) -> void:
	var view=preload("res://ui/shop/shop_home.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.trade_requested.connect(func(mode: String):
		var saved: Dictionary=shop_view_state.get(selected_shop,{})
		saved.mode=mode
		saved.category="全部"
		saved.key=""
		shop_view_state[selected_shop]=saved
		_navigate("商店交易"))
	view.dialogue_requested.connect(open_npc_interaction)
	view.observation.connect(_observe_shop)
	view.bind_data(snapshot,GameManager.operations.data,selected_shop,recent_messages)

func _observe_shop(text: String) -> void:
	message="观察"+str(GameManager.operations.data.shops[selected_shop].name)+"："+text
	_record_message(message)
	observation_panel=AcceptDialog.new()
	add_child(observation_panel)
	observation_panel.title="观察店铺"
	observation_panel.dialog_text=text
	observation_panel.confirmed.connect(func():observation_panel.queue_free())
	observation_panel.canceled.connect(func():observation_panel.queue_free())
	observation_panel.popup_centered(Vector2i(720,320))
	_schedule_refresh()

func open_npc_interaction(id: String) -> void:
	if npc_overlay!=null and is_instance_valid(npc_overlay):return
	npc_overlay=preload("res://ui/npc/npc_interaction.tscn").instantiate()
	add_child(npc_overlay)
	npc_overlay.bind_data(GameManager.operations,id)
	npc_overlay.command.connect(_npc_command)
	npc_overlay.closed.connect(_npc_closed)

func _npc_command(action: String,args: Dictionary) -> void:
	if action=="sell" and args.get("item","")=="material_wolf_fang" and not args.get("confirmed",false):
		var dialog:=ConfirmationDialog.new()
		add_child(dialog)
		dialog.dialog_text="灰狼牙是任务材料，确认出售？"
		dialog.confirmed.connect(func():var confirmed: Dictionary=args.duplicate();confirmed.confirmed=true;_npc_command(action,confirmed);dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
		return
	var result: Dictionary=GameManager.request(action,args)
	message=result.message
	var acted: Dictionary=GameManager.operations.snapshot()
	if npc_overlay!=null and is_instance_valid(npc_overlay) and (not acted.get("battle", {}).is_empty() or not acted.get("battle_report", {}).get("confirmed", true)):
		npc_overlay.queue_free()
		npc_overlay=null
		page="战斗"
		_schedule_refresh()
		return
	if result.success and not str(result.get("open_npc", "")).is_empty():
		var next_id := str(result.open_npc)
		if npc_overlay!=null and is_instance_valid(npc_overlay):
			npc_overlay.queue_free()
			npc_overlay=null
		open_npc_interaction(next_id)
		return
	if result.success and action=="npc_option" and message=="操作成功":
		message="委托已接取，可继续交谈或查看任务进度。"
		result.message=message
	if action in ["buy","sell","sell_equipment"]:
		message=("%s%s ×%d" % ["购买" if action=="buy" else "出售",GameManager.operations.data.items.get(args.get("item",""),{}).get("name","物品"),args.get("quantity",1)])+("成功" if result.success else "失败："+result.message)
		result.message=message
	_record_message(message)
	if npc_overlay!=null and is_instance_valid(npc_overlay):npc_overlay.receive(result,args.get("option","") if action=="npc_option" else "")

func _npc_closed() -> void:
	npc_overlay=null
	# Rebind values on the original scene; do not reload it.
	var snapshot: Dictionary=GameManager.operations.snapshot()
	var scrolls: Array=[]
	for node in content.find_children("*","ScrollContainer",true,false):scrolls.append([node,node.scroll_vertical,node.scroll_horizontal])
	for child in content.get_children():
		if child.name=="HomeView":child.build(snapshot,GameManager.operations.data,message,GameManager.operations,recent_messages)
		elif child.name=="InnPage":child.refresh_data(recent_messages)
		elif child.name=="ShopHome":child.bind_data(snapshot,GameManager.operations.data,selected_shop,recent_messages)
		elif child.name=="TaskPage":child.bind_data(snapshot,GameManager.catalog.tables,task_selected,task_category,message)
	for entry in scrolls:
		if is_instance_valid(entry[0]):
			entry[0].set_deferred("scroll_vertical",entry[1])
			entry[0].set_deferred("scroll_horizontal",entry[2])

func _inn_page() -> void:
	var view=preload("res://ui/inn/inn_page.tscn").instantiate()
	content.add_child(view)
	view.navigate.connect(_navigate)
	view.npc_requested.connect(open_npc_interaction)
	view.action_requested.connect(_inn_command)
	view.feedback.connect(func(text: String):_record_message(text);view.refresh_data(recent_messages))
	view.bind_data(GameManager.operations,selected_inn,recent_messages)

func _inn_command(action: String,args: Dictionary,operation_id: String) -> void:
	var result: Dictionary=GameManager.request(action,args,operation_id)
	message=result.message
	_record_message(message)
	if content.has_node("InnPage"):content.get_node("InnPage").receive(result,recent_messages)

func _resume_battle_round(view: Control) -> void:
	if is_instance_valid(view) and view.is_inside_tree() and page=="战斗":
		var battle: Dictionary = GameManager.operations.snapshot().battle
		if battle.get("phase")=="active" and GameManager.operations.battle.needs_round(battle):
			_battle_command("begin_battle",{})

func _battle_command(action: String,args: Dictionary) -> void:
	if action not in ["battle_action","begin_battle"]:
		_command(action,args)
		return
	if not content.has_node("BattlePage"):return
	var view: Control=content.get_node("BattlePage")
	if view.playing:return
	view.playing=true
	var result: Dictionary=GameManager.request(action,args)
	message=result.message
	if not result.success:
		view.playing=false
		view.append_log_message(message)
		return
	var snapshot: Dictionary=GameManager.operations.snapshot()
	var battle: Dictionary=snapshot.battle if not snapshot.battle.is_empty() else snapshot.get("battle_report",{}).get("background",{}).get("battle",{})
	var batch: Array = battle.get("events",[])
	if batch.is_empty():
		view.playing=false
	else:
		await view.play_events(batch,GameManager.operations.battle.waiting_order(snapshot.battle))
	if not is_instance_valid(view):return
	if page!="战斗":return
	if snapshot.battle.is_empty():_refresh()
	else:view.bind_data(GameManager.operations,message)

func _world_time_refresh(interval: Dictionary) -> void:
	if content==null:return
	var snapshot: Dictionary=GameManager.operations.snapshot()
	if snapshot.is_empty():return
	if npc_overlay!=null and is_instance_valid(npc_overlay) and interval.get("months",0)>0:npc_overlay.refresh_data()
	var clock=GameManager.operations.clock
	for child in content.get_children():
		var date: Node=child.find_child("WorldTime",true,false)
		if date==null:date=child.find_child("GameTime",true,false)
		if date is Label:date.text=clock.format_date(snapshot,GameManager.operations.data)
		if child.name=="HomeView":
			child.refresh_time(snapshot)
			if interval.get("months",0)>0:child._npcs();child._buildings();child._task();child._messages(message,recent_messages)
		elif child.name=="CharacterPage":
			child.refresh_time(snapshot)
		elif child.name=="WorldMap":
			child.refresh_aura(snapshot)
		elif child.name=="ShopPage" and interval.get("months",0)>0:
			child.bind_data(GameManager.operations,selected_shop,child.mode,child.category,child.selected,child.quantity,"月度库存与价格已刷新")
		elif child.name=="ShopHome" and interval.get("months",0)>0:child.bind_data(snapshot,GameManager.operations.data,selected_shop,recent_messages)
		elif child.name=="InnPage" and interval.get("months",0)>0:child.refresh_data(recent_messages)
		elif child.name=="AuctionPage" and int(interval.get("start",0)/3600)!=int(interval.get("end",0)/3600):
			child.refresh_state()
		elif child.name=="TaskPage" and interval.get("months",0)>0:child.bind_data(snapshot,GameManager.catalog.tables,task_selected,task_category,message)
		elif child.name=="TownBoard" and int(interval.get("start",0)/3600)!=int(interval.get("end",0)/3600):
			child.sync(snapshot)
		elif child.name=="CavePage":
			child.state=snapshot
			var hour_changed: bool=int(interval.get("start",0)/3600)!=int(interval.get("end",0)/3600)
			if child.tab=="Retreat" and not child.retreat_busy:
				child._retreat_info()
				if hour_changed:child._preview()
			elif hour_changed:child._overview();child._fields()
func _show_retreat_report(report: Dictionary) -> void:
	if retreat_overlay!=null and is_instance_valid(retreat_overlay):retreat_overlay.queue_free()
	retreat_overlay=preload("res://ui/cave/retreat_report.tscn").instantiate();add_child(retreat_overlay)
	retreat_overlay.closed.connect(func():retreat_overlay=null)
	retreat_overlay.bind_data(report)

