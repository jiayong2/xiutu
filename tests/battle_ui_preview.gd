extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	var gm: Node=root.get_node("GameManager")
	gm.new_game("战斗验收","火")
	gm.request("travel",{"id":"area_qinglan_outskirts"})
	gm.request("explore",{})
	if gm.operations.snapshot().battle.is_empty():
		var payload: Dictionary=gm.operations.export_save()
		var bsys=load("res://gameplay/battle/battle_system.gd").new()
		bsys.start(payload.state,"monster_gray_wolf",gm.operations.data,"ui_test")
		gm.operations.restore_save(payload)
	root.size=Vector2i(1920,1080)
	var page=load("res://ui/battle/battle_page.tscn").instantiate()
	root.add_child(page)
	page.action_requested.connect(func(action,args):gm.request(action,args))
	page.bind_data(gm.operations)
	await settle()
	check(page.field("Attack").disabled,"prepare attack disabled")
	check(page.field("Begin").get_global_rect().get_center().is_equal_approx(page.get_global_rect().get_center()),"begin centered on screen")
	root.get_texture().get_image().save_png("res://docs/screenshots/battle_prepare_center.png")
	page.field("Begin").pressed.emit()
	page.bind_data(gm.operations)
	await settle()
	check(not page.field("Attack").disabled,"active attack enabled")
	check(not page.field("Begin").visible,"begin hidden after start")
	root.get_texture().get_image().save_png("res://docs/screenshots/battle_1v1.png")
	var before: Dictionary=gm.operations.export_save()
	page.field("Skill5").pressed.emit()
	check(before==gm.operations.export_save(),"skill page read only")
	page.field("Skill5").pressed.emit()
	page.field("Defend").pressed.emit()
	check(gm.operations.snapshot().battle.turn==1,"real defend advances round")
	page.bind_data(gm.operations)
	await settle()
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution
		await settle()
		for counts in [[1,1],[1,3],[1,6],[3,3],[3,6],[6,6],[2,4],[5,2]]:
			var entries: Array=[]
			for team in range(2):
				for i in range(counts[team]):
					entries.append({"id":"u%d_%d" % [team,i],"name":("我方" if team==0 else "敌方")+str(i+1),"side":"ally" if team==0 else "enemy","hp":80,"max_hp":100,"mp":25,"max_mp":40,"speed":20-i+team,"statuses":["护体 · 剩余2回合","测试状态 · 剩余3回合","第三状态 · 剩余1回合"]})
			page.set_units(entries);await settle()
			for key in ["AllyFormation","EnemyFormation"]:
				var area: Control=page.field(key)
				for view in area.get_children():
					var square: Control=view.get_node("Square")
					check(is_equal_approx(square.size.x,square.size.y),"square aspect")
					check(area.get_global_rect().encloses(view.get_global_rect()),"unit fits formation")
					check(view.has_node("hp") and view.has_node("mp"),"both bars retained")
			check(page.get_global_rect().encloses(page.field("Skill5").get_global_rect()),"bottom visible")
			check(page.field("TurnScroll").size.y<=72,"compact turn bar")
			if resolution.x==1920 and counts in [[1,6],[3,6],[6,6]]:
				root.get_texture().get_image().save_png("res://docs/screenshots/battle_%dv%d.png" % counts)
	var main=load("res://ui/main/main.tscn").instantiate()
	main.page="战斗";root.add_child(main);await settle()
	check(main.content.has_node("BattlePage"),"main routes real battle page")
	main.queue_free()
	print("BATTLE UI: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
