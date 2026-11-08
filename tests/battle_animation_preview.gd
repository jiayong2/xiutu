extends SceneTree
var gm: Node
var main: Control
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func fixture(spell_id: String="skill_spirit_bolt") -> Control:
	gm.new_game("动画验收","木")
	var payload: Dictionary=gm.operations.export_save()
	payload.state.player.location="area_qinglan_outskirts"
	payload.state.player.hp=50
	payload.state.player.spells["skill_wood_heal"]=1;payload.state.player.spells["skill_earth_guard"]=1
	payload.state.player.spells["skill_fire_bolt"]=1;payload.state.player.spells["skill_water_arrow"]=1
	payload.state.player.spell_slots=[spell_id if spell_id in ["skill_fire_bolt","skill_water_arrow"] else "skill_spirit_bolt","skill_wood_heal","skill_earth_guard"]
	gm.operations.battle.start(payload.state,"monster_mountain_boar",gm.operations.data,"animation_fixture")
	payload.state.battle.phase="active"
	check(gm.operations.restore_save(payload).is_empty(),"fixture valid")
	for seed_value in range(100):
		var rng=load("res://core/random_service.gd").new();rng.initialize(seed_value);rng.roll("battle")
		if rng.roll("battle")<gm.operations.data.rules.status_chance:
			gm.operations.random.initialize(seed_value);break
	main.page="战斗";main._refresh()
	await settle()
	return main.content.get_node("BattlePage")
func run() -> void:
	gm=root.get_node("GameManager");gm.set_process(false);root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();root.add_child(main);await settle()
	for action in [{"kind":"attack"},{"kind":"spell","id":"skill_spirit_bolt"},{"kind":"spell","id":"skill_wood_heal"},{"kind":"spell","id":"skill_earth_guard"},{"kind":"spell","id":"skill_fire_bolt"},{"kind":"spell","id":"skill_water_arrow"},{"kind":"defend"},{"kind":"item","id":"item_healing_powder"}]:
		var view: Control=await fixture(action.get("id","skill_spirit_bolt"))
		var actor: Control=view._view("player")
		var target: Control=view._view("enemy")
		var actor_start: Vector2=actor.position
		var target_start: Vector2=target.position
		var seed_state: Dictionary=gm.operations.export_save()
		var probe=load("res://core/operation_service.gd").new();probe.configure(gm.operations.data);probe.restore_save(seed_state)
		var expected: Dictionary=probe.request("battle_action",action)
		check(expected.success,"reference accepts")
		main._battle_command("battle_action",action)
		check(gm.operations.snapshot().battle.turn==1,"settled immediately before presentation")
		var settled: Dictionary=gm.operations.export_save()
		check(settled==probe.export_save(),"same state and RNG as nonanimated request")
		main._battle_command("battle_action",action)
		check(settled==gm.operations.export_save(),"busy refuses duplicate submission")
		var moved:=false
		var spell_moved:=false
		var seen_label:=false
		var frame_count:=0
		var screenshot_saved:=false
		var saw_enemy_current:=false
		var current_mismatch:=false
		while view.playing:
			await process_frame;frame_count+=1
			var track: Control=view.field("TurnOrder")
			if not track.current_id.is_empty():
				current_mismatch=current_mismatch or view.active_actor!=track.current_id
				saw_enemy_current=saw_enemy_current or track.current_id=="enemy"
			if view.active_actor=="player" and not actor.position.is_equal_approx(actor_start):
				if action.kind=="attack":moved=true
				elif action.kind=="spell":spell_moved=true
			if action.kind=="spell":
				for label in view.floating_labels:
					if is_instance_valid(label) and label.text==gm.operations.data.spells[action.id].name:seen_label=true
			if action.kind=="attack" and moved and frame_count%4==0 and not seen_label:
				root.get_texture().get_image().save_png("res://docs/screenshots/battle_attack_motion.png");seen_label=true
			if action.kind=="spell" and seen_label and view.active_actor=="player" and not screenshot_saved:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/screenshots/battle_"+action.id+"_instant.png");screenshot_saved=true
			if frame_count>900:view.skip_animations();check(false,"animation timeout");break
		await settle()
		check(gm.operations.export_save()==settled,"presentation no mutation")
		check(main.content.get_node("BattlePage")==view and view._view("player")==actor,"stable unit and UI identity")
		check(actor.position.is_equal_approx(actor_start) and target.position.is_equal_approx(target_start),"both actors return exactly")
		check(actor.get_node("Square").modulate==Color.WHITE and target.get_node("Square").modulate==Color.WHITE,"colors restored")
		check(view.floating_labels.is_empty(),"floating labels cleaned")
		check(saw_enemy_current and not current_mismatch,"real event actor matches rightmost portrait and scene highlight")
		check(view.field("TurnOrder").action_queue==["player","enemy"],"round end restores real next-round queue without extra turns")
		check(not view.field("Item").disabled and not view.field("Skill5").disabled,"item and skill expansion restored after presentation")
		if action.kind=="attack":check(moved,"basic attack lunges")
		if action.kind=="spell":
			check(not spell_moved,"spell caster never advances")
			check(seen_label,"spell name displayed")
		var events: Array=gm.operations.snapshot().battle.events
		check(events[0].actor=="player" and events[1].actor=="enemy","original speed order")
		if action.get("id","")=="skill_wood_heal":check(events[0].after.player.hp>events[0].before.player.hp,"healing actual target")
		if action.get("id","") in ["skill_fire_bolt","skill_water_arrow"]:
			var status_id: String=gm.operations.data.spells[action.id].status
			check(events[0].after.enemy.statuses.has(status_id),"real debuff applied")
			check(not view._view("enemy").get_node("StatusContainer").get_children().is_empty(),"debuff UI updated")
		if action.get("id","")=="skill_earth_guard":check(events[0].after.player.statuses.has("guard"),"guard actual target")
	var view: Control=await fixture()
	main._battle_command("battle_action",{"kind":"attack"})
	var before_skip: Dictionary=gm.operations.export_save()
	view.field("Skip").pressed.emit()
	while view.playing:await process_frame
	await settle()
	check(before_skip==gm.operations.export_save() and not view.field("Attack").disabled,"skip safe and controls restored")
	view=await fixture();view.animation_speed=2
	main._battle_command("battle_action",{"kind":"attack"})
	var before_speed: Dictionary=gm.operations.export_save()
	while view.playing:await process_frame
	check(before_speed==gm.operations.export_save(),"speed presentation only")
	view=await fixture();view.animation_speed=2
	var player_portrait: Control=view.field("TurnOrder").portraits.player
	for round_index in range(2):
		main._battle_command("battle_action",{"kind":"defend"})
		while view.playing:await process_frame
		check(gm.operations.snapshot().battle.turn==round_index+1,"consecutive rounds execute once")
		check(view.field("TurnOrder").portraits.player==player_portrait,"round boundary retains stable portrait")
	# Isolated presentation fixture: multiple actual changed targets and one unchanged target.
	view=await fixture()
	var sample: Array=view.units.duplicate(true)
	var extra: Dictionary=sample[1].duplicate(true);extra.id="enemy_two";extra.name="测试目标二";sample.append(extra)
	view.set_units(sample);await settle()
	var before: Dictionary={}
	for u in sample:before[u.id]={"hp":u.hp,"mp":u.mp,"statuses":{},"defending":false}
	var after: Dictionary=before.duplicate(true);after.enemy.hp-=10;after.enemy_two.hp-=20
	var group_event: Dictionary={"actor":"player","kind":"spell","label":"测试群体法术","before":before,"after":after}
	view.animation_speed=2
	view.play_events([group_event])
	var flashed_one:=false
	var flashed_two:=false
	var false_hit:=false
	var data_before: Dictionary=gm.operations.export_save()
	while view.playing:
		await process_frame
		flashed_one=flashed_one or view._view("enemy").get_node("Square").modulate!=Color.WHITE
		flashed_two=flashed_two or view._view("enemy_two").get_node("Square").modulate!=Color.WHITE
		false_hit=false_hit or view._view("player").get_node("Square").modulate!=Color.WHITE
	check(flashed_one and flashed_two and not false_hit,"all affected targets flash; unchanged caster no hit")
	check(view._view("enemy_two").get_node("hp").value==after.enemy_two.hp,"second target bar matches actual delta")
	check(data_before==gm.operations.export_save(),"group presentation fixture never changes official state")
	# True end-of-battle paths settle first, then open existing result UI exactly once.
	for outcome in ["win","lose","escape"]:
		view=await fixture()
		var saved: Dictionary=gm.operations.export_save()
		if outcome=="win":saved.state.battle.enemy.hp=1
		if outcome=="lose":saved.state.player.hp=1;saved.state.battle.enemy.speed=999
		check(gm.operations.restore_save(saved).is_empty(),"end fixture valid")
		await settle();view=main.content.get_node("BattlePage")
		if outcome=="escape":
			# Select deterministic isolated seed yielding the existing escape success condition.
			for seed_value in range(100):
				var rng=load("res://core/random_service.gd").new();rng.initialize(seed_value)
				if rng.roll("battle")<gm.operations.data.rules.escape_chance:
					gm.operations.random.initialize(seed_value);break
		main._battle_command("battle_action",{"kind":"escape" if outcome=="escape" else "attack"})
		var settled_end: Dictionary=gm.operations.export_save()
		check(settled_end.state.battle_report.result==outcome,"real immediate "+outcome)
		if outcome!="win":view.skip_animations()
		while is_instance_valid(view) and view.playing:await process_frame
		await settle()
		check(main.content.has_node("BattleResultOverlay"),"result overlay after "+outcome)
		check(gm.operations.export_save()==settled_end,"no duplicate end settlement "+outcome)
	# Leaving the presentation must kill its Tweens without changing settled state.
	view=await fixture();main._battle_command("battle_action",{"kind":"attack"})
	var interrupted_state: Dictionary=gm.operations.export_save()
	main._navigate("主界面");await settle()
	check(not is_instance_valid(view),"interrupted view freed")
	check(gm.operations.export_save()==interrupted_state,"interruption preserves settled state")
	view=await fixture()
	var lines: Array=[]
	for index in range(90):lines.append("滚动验收 %d" % index)
	view.update_log(lines);await settle()
	var log_scroll: VScrollBar=view.field("Log").get_v_scroll_bar()
	check(log_scroll.value>0,"log follows newest when already at bottom")
	log_scroll.value=0;lines.append("新增真实日志")
	view.update_log(lines);await settle()
	check(is_zero_approx(log_scroll.value),"new log preserves manual historical scroll")
	root.size=Vector2i(1280,720);await settle()
	view.animation_speed=2
	main._battle_command("battle_action",{"kind":"spell","id":"skill_wood_heal"})
	while view.playing:await process_frame
	await settle()
	check(view.get_global_rect().size.x<=1920 and view.field("Attack").is_visible_in_tree(),"small window actions remain visible")
	root.get_texture().get_image().save_png("res://docs/screenshots/battle_animation_small.png")
	var source: String=FileAccess.get_file_as_string("res://ui/battle/battle_page.gd")
	check(not source.contains("ColorRect.new") and not source.contains("GPUParticles") and not source.contains("Shader"),"no spell projectiles or special effects")
	main.queue_free();await settle()
	print("BATTLE ANIMATION: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
