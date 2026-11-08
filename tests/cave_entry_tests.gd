extends SceneTree
var n:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	n+=1
	if not ok:failures+=1;push_error(label)
	print("%s %s" % ["PASS" if ok else "FAIL",label])
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	var gm: Node=root.get_node("GameManager")
	gm.new_game("洞府入口验收","金")
	var main: Control=load("res://ui/main/main.tscn").instantiate();main.page="主界面";root.add_child(main);await settle()
	var before: Dictionary=gm.operations.snapshot()
	for button in main.content.get_node("HomeView").find_children("Nav_*","Button",true,false):
		if button.text.contains("洞府"):button.pressed.emit();break
	await settle()
	check(main.page=="洞府" and gm.operations.snapshot().player.location=="cave_qinglan","home entry actually enters cave")
	check(gm.operations.snapshot().hours==before.hours,"local entry retains existing zero travel time")
	var view: Control=main.content.get_node("CavePage")
	view._tab("Retreat");view._duration(0,0,1);await settle()
	check(not view.field("StartRetreat").disabled,"retreat enabled after entering")
	check(not view.field("Efficiency").text.contains("请进入"),"efficiency uses cave location")
	view.field("StartRetreat").pressed.emit();await settle()
	check(gm.operations.snapshot().hours==before.hours+24,"retreat advances actual world time")
	check(gm.operations.snapshot().player.cultivation>before.player.cultivation,"retreat grants actual cultivation")
	before=gm.operations.snapshot()
	main._navigate("洞府");await settle()
	check(before==gm.operations.snapshot(),"already in cave does not duplicate travel")
	gm.request("travel",{"id":"town_yunxi"});await settle()
	var probe: RefCounted=gm.operations.get_script().new();probe.configure(gm.operations.data);probe.restore_save(gm.operations.export_save());probe.request("travel",{"id":"cave_qinglan"})
	main._navigate("洞府");await settle()
	check(gm.operations.snapshot().hours==probe.snapshot().hours,"distant entry applies existing travel time")
	gm.new_game("战斗入口验收","金")
	gm.request("travel",{"id":"area_qinglan_outskirts"})
	for i in range(20):
		gm.request("explore")
		if not gm.operations.snapshot().battle.is_empty():break
	before=gm.operations.snapshot()
	main.page="战斗";main._navigate("洞府");await settle()
	check(main.page!="洞府" and gm.operations.snapshot()==before,"failed travel never opens cave or changes battle")
	print("CAVE ENTRY: %d checks, %d failures" % [n,failures]);quit(0 if failures==0 else 1)
