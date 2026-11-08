extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	var gm: Node=root.get_node("GameManager");gm.set_process(false)
	root.size=Vector2i(1920,1080)
	var page=load("res://ui/battle/battle_page.tscn").instantiate();root.add_child(page)
	for critical in [false,true]:
		gm.new_game("暴击飘字验收","木")
		var saved: Dictionary=gm.operations.export_save();saved.state.player.location="area_qinglan_outskirts";saved.state.player.hp=50
		gm.operations.battle.start(saved.state,"monster_mountain_boar",gm.operations.data,"critical_float_fixture");saved.state.battle.phase="active"
		check(gm.operations.restore_save(saved).is_empty(),"fixture valid")
		for seed_value in range(10000):
			var random=load("res://core/random_service.gd").new();random.initialize(seed_value)
			if (random.roll("battle")<gm.operations.data.rules.crit_chance)==critical:
				gm.operations.random.initialize(seed_value);break
		page.bind_data(gm.operations);await settle()
		check(gm.operations.request("battle_action",{"kind":"attack"}).success,"real attack")
		var events: Array=gm.operations.snapshot().battle.events
		check(events[0].critical==critical,"real critical flag")
		var expected_damage: int=events[0].before.enemy.hp-events[0].after.enemy.hp
		var settled: Dictionary=gm.operations.export_save()
		page.play_events(events)
		var inspected:=false
		while page.playing:
			await process_frame
			if inspected or page.active_actor!="player":continue
			for label in page.floating_labels:
				if not is_instance_valid(label) or not label.text.begins_with("-"):continue
				check(label.text=="-%d%s" % [expected_damage," 暴击" if critical else ""],"actual damage and critical label")
				check(Color(label.modulate.r,label.modulate.g,label.modulate.b).is_equal_approx(Color("F4C766") if critical else Color("ff6868")),"gold critical / red ordinary floating text")
				check(label.get_theme_font_size("font_size")==42,"large font preserved")
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/screenshots/battle_floating_critical.png" if critical else "res://docs/screenshots/battle_floating_normal.png")
				inspected=true;break
		check(inspected,"damage float observed")
		check(settled==gm.operations.export_save(),"presentation never changes settlement")
		await settle()
	page.queue_free();await settle()
	print("CRITICAL FLOAT: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
