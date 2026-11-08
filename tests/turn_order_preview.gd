extends SceneTree
var checks:=0
var failures:=0
var gm: Node
var page: Control
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func wait_layout(bar: Control) -> void:
	while bar.layout_tween!=null and bar.layout_tween.is_valid() and bar.layout_tween.is_running():await process_frame
	await settle()
func entries(count: int) -> Array:
	var result: Array=[]
	for index in range(count):result.append({"id":"test_%d" % index,"name":(["玩家","敌一","敌二","敌三"][index] if index<4 else "敌%d" % index),"hp":100,"max_hp":100,"mp":20,"max_mp":20,"side":"ally" if index%2==0 else "enemy","speed":100-index,"statuses":[]})
	return result
func verify_positions(bar: Control) -> void:
	var shown: Array=bar.action_queue.slice(0,9)
	for index in range(shown.size()):
		var portrait: Control=bar.portraits[shown[index]]
		check(portrait.size.is_equal_approx(Vector2(48,48)),"portrait exact 48 square: "+str(portrait.size))
		check(portrait.position.is_equal_approx(Vector2(bar.target_width-64-index*64,12)),"earliest on right, equal gap")
		check(bar.get_node("Track").get_rect().encloses(portrait.get_rect()),"portrait within track")
	check(bar.current_id==str(shown[0]) if not shown.is_empty() else bar.current_id.is_empty(),"rightmost current ID")
	check(is_equal_approx(bar.get_node("CurrentMarker").position.x,bar.target_width+12),"marker constant relative offset")
func run() -> void:
	gm=root.get_node("GameManager");gm.new_game("行动条验收","木")
	root.size=Vector2i(1920,1080)
	var saved: Dictionary=gm.operations.export_save()
	gm.operations.battle.start(saved.state,"monster_mountain_boar",gm.operations.data,"turn_order_fixture");saved.state.battle.phase="active"
	check(gm.operations.restore_save(saved).is_empty(),"real fixture valid")
	page=load("res://ui/battle/battle_page.tscn").instantiate();root.add_child(page)
	var bar: Control=page.field("TurnOrder")
	page.bind_data(gm.operations);await wait_layout(bar)
	check(bar.action_queue==gm.operations.battle.action_order(gm.operations.stats(),gm.operations.snapshot().battle),"real system queue bound")
	check(bar.get_node("Track").size.x==200,"duel compact width")
	verify_positions(bar)
	root.get_texture().get_image().save_png("res://docs/screenshots/turn_order_duel.png")
	check(gm.operations.battle.action_order({"speed":12},{"enemy":{"speed":12}})==["player","enemy"],"existing tie rule preserved")
	check(gm.operations.battle.action_order({"speed":1},{"enemy":{"speed":12}})==["enemy","player"],"enemy-first real order")
	var enemy_first: Dictionary=gm.operations.export_save();enemy_first.state.battle.enemy.speed=999
	check(gm.operations.restore_save(enemy_first).is_empty(),"enemy-first fixture valid")
	check(gm.operations.request("begin_battle").success and gm.operations.snapshot().battle.events[0].actor=="enemy","fast monster takes the opening action")
	page.bind_data(gm.operations);await wait_layout(bar)
	check(bar.current_id=="player" and bar.action_queue==["player"],"player is the remaining action after enemy opener")
	check(page._view("player").get_node("Square").get_theme_stylebox("normal").border_color==Color("8bd6b5"),"scene highlight matches current player input")
	check(gm.operations.restore_save(saved).is_empty(),"restore original duel")
	page.bind_data(gm.operations);await wait_layout(bar)
	# UI-only multi-unit fixture with deliberately non-speed-sorted queue.
	var multi: Array=entries(4)
	var queue: Array=["test_2","test_0","test_3","test_1"]
	page.set_units(multi,queue);await wait_layout(bar)
	verify_positions(bar)
	check(bar.target_width==272,"four-unit width content driven")
	var stable: Control=bar.portraits.test_2
	var old_position: Vector2=stable.position
	bar.set_queue(multi,["test_0","test_3","test_1","test_2"],["test_2"],true)
	check(stable.position==old_position,"no instant reorder")
	for i in range(6):await process_frame
	check(stable.position.x<old_position.x and stable.position.x>16,"portrait has intermediate Tween position")
	check(bar.current_id.is_empty(),"new current highlight waits until movement completes")
	await wait_layout(bar)
	check(bar.portraits.test_2==stable and stable.next_round,"stable ID and next-round badge")
	verify_positions(bar)
	check(bar.portraits.test_0.get_theme_stylebox("normal").border_color==Color("edcf82"),"gold current border")
	root.get_texture().get_image().save_png("res://docs/screenshots/turn_order_four.png")
	# Latest state interrupts old tween; no duplicate portraits.
	bar.set_queue(multi,queue,[],true);await process_frame
	bar.set_queue(multi,["test_3","test_1","test_0","test_2"],[],true)
	bar.set_speed(2);await wait_layout(bar);verify_positions(bar)
	check(bar.get_node("Track").get_child_count()==4,"fast update has no duplicate avatars")
	var six: Array=entries(6);bar.set_queue(six,six.map(func(unit):return unit.id),[],true);await wait_layout(bar)
	check(bar.target_width==400 and bar.action_queue.size()==6,"six-unit adaptive width")
	bar.set_queue(multi,queue,[],false);await settle()
	# Death fades, shrinks and removes by ID.
	multi[1].hp=0
	var previous_width: float=bar.get_node("Track").size.x
	var removed: Control=bar.portraits.test_1
	bar.set_queue(multi,queue,[],true)
	await process_frame
	check(is_instance_valid(removed),"death fade retains node until complete")
	await wait_layout(bar)
	check(not is_instance_valid(removed) and not bar.portraits.has("test_1"),"dead portrait freed")
	check(bar.get_node("Track").size.x<previous_width,"death reduces width")
	verify_positions(bar)
	# Overflow retains full source queue and only windows the next nine.
	multi=entries(12);queue=multi.map(func(unit):return unit.id)
	bar.set_queue(multi,queue,[],true);await wait_layout(bar)
	check(bar.action_queue.size()==12 and bar.portraits.size()==12,"overflow preserves all IDs")
	check(bar.target_width==650 and bar.get_node("Overflow").visible,"maximum width and full queue entry")
	var visible_count:=0
	for id in bar.portraits:if bar.portraits[id].visible:visible_count+=1
	check(visible_count==9,"only upcoming window shown")
	verify_positions(bar)
	bar.get_node("Overflow").pressed.emit();await settle()
	var popup: PopupMenu=bar.get_child(bar.get_child_count()-1)
	check(popup.item_count==12,"overflow popup lists full queue")
	popup.hide();await settle()
	# Feedback uses centered large red numbers, all native labels, with longer lifetime.
	page.set_units(entries(4),["test_0","test_1","test_2","test_3"]);await wait_layout(bar)
	var square: Control=page._view("test_1").get_node("Square")
	page._float_text("test_1","-42",Color("ff6868"))
	var label: Label=page.floating_labels.back()
	check(label.get_theme_font_size("font_size")==42 and label.modulate==Color("ff6868"),"large red damage font")
	check(label.get_global_rect().get_center().is_equal_approx(square.get_global_rect().get_center()),"damage starts at rectangle center")
	page._float_text("test_0","行动中",Color.WHITE,2)
	var actor_label: Label=page.floating_labels.back()
	page._float_text("test_0","特殊攻击",Color.WHITE,1)
	var special_label: Label=page.floating_labels.back()
	var actor_square: Control=page._view("test_0").get_node("Square")
	check(is_equal_approx(actor_label.get_global_rect().get_center().x,actor_square.get_global_rect().get_center().x),"acting label centered")
	check(is_equal_approx(special_label.get_global_rect().get_center().x,actor_square.get_global_rect().get_center().x),"special label centered")
	var hold:=create_timer(.85);await hold.timeout
	check(is_instance_valid(label) and label.modulate.a>.95,"feedback stays legible past old lifetime")
	root.get_texture().get_image().save_png("res://docs/screenshots/turn_order_feedback.png")
	page._cleanup_presentation();await settle()
	root.size=Vector2i(1280,720);page.bind_data(gm.operations);await wait_layout(bar)
	check(page.get_global_rect().encloses(bar.get_node("CurrentMarker").get_global_rect()),"small window compact marker fits")
	root.get_texture().get_image().save_png("res://docs/screenshots/turn_order_small.png")
	check(saved.state.player==gm.operations.export_save().state.player,"UI changes never mutate player")
	page.queue_free();await settle()
	print("TURN ORDER: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
