extends SceneTree
var failures:=0
var checks:=0
var gm: Node
var main: Control
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
func home() -> Control:return main.content.get_node("HomeView")
func run() -> void:
	gm=root.get_node("GameManager");gm.set_process(false);gm.new_game("地点界面验收","金")
	root.size=Vector2i(1920,1080)
	main=load("res://ui/main/main.tscn").instantiate();main.page="主界面";root.add_child(main)
	await settle()
	var h:=home()
	check(h.field("TaskOpen").text=="暂无追踪任务","empty tracked quest honest")
	check(h.field("Messages").get_child(0).size.y>=28 and h.field("TaskHint").size.y>=28,"messages and hints visibly readable")
	check(h.field("Npcs").get_child_count()==3,"town real npcs")
	check(h.field("Buildings").get_child_count()==3,"town real shops and inn")
	check(h.find_children("Nav_*","Button",true,false).size()==5,"five navigation buttons")
	for resolution in [Vector2i(1920,1080),Vector2i(1280,720)]:
		root.size=resolution;await settle();h=home()
		for key in ["Header","CurrentTaskCard","BuildingPanel","CultivationCard","NearbyNpcPanel","WorldMessagePanel","BottomNavigation"]:
			check(h.get_global_rect().encloses(h.field(key).get_global_rect()),"visible "+key)
		check(h.field("CharacterPlaceholder").size.y>=205,"large portrait")
		check(absf(h.field("LeftPanel").size.x/h.field("MainContent").size.x-.25)<.03,"left quarter")
		check(absf(h.field("CultivationCard").size.x/h.field("MainContent").size.x-.5)<.03,"center half")
		root.get_texture().get_image().save_png("res://docs/screenshots/location_home_town_%d.png" % resolution.x)
	root.size=Vector2i(1920,1080);await settle()
	h.field("Buildings").get_child(0).pressed.emit();await settle()
	check(main.page=="商店" and not main.content.has_node("HomeView"),"shop replaces main")
	main.content.get_node("ShopHome").field("Back").pressed.emit();await settle()
	check(main.page=="地点场景" and home().field("LocationDate").text.contains("青岚镇"),"shop returns same town")
	home().field("Npcs").get_child(0).pressed.emit();await settle()
	check(main.npc_overlay!=null and main.page=="地点场景","npc opens unified overlay")
	main.npc_overlay.close();await settle()
	main._navigate("主界面");await settle()
	gm.request("accept",{"id":"quest_qinglan_001"});await settle()
	h=home();check(h.field("TaskOpen").text==gm.operations.data.quests.quest_qinglan_001.title,"only actual tracked quest")
	check(not h.field("TaskProgress").text.is_empty(),"real objective progress")
	h.field("TaskOpen").pressed.emit();await settle()
	check(main.page=="任务" and main.task_selected=="quest_qinglan_001","quest click selects tracked task")
	main._navigate("主界面");await settle()
	home().field("WorldMap").pressed.emit();await settle()
	check(main.page=="地图","map entry")
	main._world_action("travel",{"id":"area_qinglan_outskirts"});await settle();h=home()
	check(h.field("LocationDate").text.contains("青岚山外围"),"travel refreshes shared main")
	check(h.field("Buildings").get_child_count()==3,"wild exploration investigation challenge")
	check(h.field("NpcTitle").text.contains("0 人"),"remote npcs hidden")
	check(h.field("Practice").disabled and h.field("LocationAura").text.contains("吐纳"),"wild practice rule retained")
	root.get_texture().get_image().save_png("res://docs/screenshots/location_home_wild_1920.png")
	main._world_action("travel",{"id":"cave_qinglan"});await settle();h=home()
	check(h.field("WorldMap").text.contains(gm.operations.clock.spirit.grade(gm.operations.snapshot(),"cave_qinglan",gm.operations.data))
		and h.field("LocationAura").text.contains("吐纳"),"real cave concentration and natural cultivation estimate")
	h.field("Buildings").get_child(1).pressed.emit();await settle()
	check(main.page=="洞府","cave facility")
	main.content.get_node("CavePage").field("Back").pressed.emit();await settle()
	check(home().field("LocationDate").text.contains("洞府"),"cave returns cave main")
	main._world_action("travel",{"id":"town_yunxi"});await settle()
	home().field("Buildings").get_child(2).pressed.emit();await settle()
	check(main.page=="宗门","existing sect entry")
	main.content.get_node("SectPage").field("Back").pressed.emit();await settle()
	check(home().field("LocationDate").text.contains("云溪城"),"sect returns correct town")
	var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true
	main._unhandled_key_input(key);await settle();check(main.page=="设置","escape opens existing settings")
	main._unhandled_key_input(key);await settle();check(main.content.has_node("HomeView"),"escape returns prior main")
	home().field("Practice").pressed.emit();await settle();check(main.page=="修炼","practice existing flow")
	var hours: int=gm.operations.snapshot().hours
	main._command("practice",{"days":1});await settle()
	check(gm.operations.snapshot().hours==hours+24,"practice real time")
	main._navigate("主界面");await settle()
	var before: Dictionary=gm.operations.snapshot()
	home().field("Promote").pressed.emit();await settle()
	check(gm.operations.snapshot()==before and main.message.contains("修为不足"),"failed promotion clear atomic feedback")
	var payload: Dictionary=gm.operations.export_save();payload.state.player.cultivation=100
	payload.state.npcs.npc_qin_shoushan.location="town_yunxi";payload.state.npcs.npc_liu_qinghe.alive=false
	for i in range(20):payload.state.news.append("隔离测试消息 "+str(i))
	gm.operations.restore_save(payload);await settle()
	check(home().field("NpcTitle").text.contains("2 人"),"migration and death refresh list")
	check(home().field("Messages").get_child_count()>=20,"world news adapted")
	check(home().field("MessageScroll").get_v_scroll_bar().max_value>home().field("MessageScroll").size.y,"messages internal scrolling")
	home().field("Promote").pressed.emit();await settle()
	check(gm.operations.snapshot().player.realm==2,"real promotion")
	check(gm.operations.restore_save(gm.operations.export_save()).is_empty(),"save compatible")
	print("LOCATION HOME: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
