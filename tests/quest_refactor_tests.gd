extends SceneTree
var gm: Node
var op: RefCounted
var n:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	n+=1
	if not ok:failures+=1;push_error(title)
	print("%s %s" % ["PASS" if ok else "FAIL",title])
func act(action: String,args: Dictionary={}) -> Dictionary:return op.request(action,args)
func current() -> String:return op.snapshot().quests.get("quest_qinglan_001",{}).get("current_objective_id","")
func run() -> void:
	gm=root.get_node("GameManager");op=gm.operations;gm.new_game("任务验收","金")
	check(act("travel",{"id":"town_yunxi"}).success,"ordinary Yunxi accessible without quests or realm")
	act("travel",{"id":"town_qinglan"})
	check(act("accept",{"id":"quest_qinglan_001"}).success and current()=="ask_disturbance","accept activates specified first stage")
	var before: Dictionary=op.snapshot()
	act("talk",{"id":"npc_qin_shoushan"})
	check(current()=="ask_disturbance","ordinary talk does not satisfy option")
	check(not act("npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_001"}).success,"early report rejected")
	check(act("npc_option",{"npc":"npc_qin_shoushan","option":"ask_qinglan_disturbance"}).success,"specified option accepted")
	check(current()=="investigate_tracks","preowned healing automatically satisfies possession")
	check(op.snapshot().player.inventory.item_healing_powder==2,"possession does not consume")
	act("travel",{"id":"cave_qinglan"});check(current()=="investigate_tracks","unrelated visit no progress")
	act("travel",{"id":"area_qinglan_outskirts"})
	check(not act("investigate",{"id":"event_beast_tracks","option":"invalid"}).success,"invalid event option rejected")
	var hours: int=op.snapshot().hours
	check(act("investigate",{"id":"event_beast_tracks","option":"inspect_tracks"}).success,"real investigation")
	check(op.snapshot().hours==hours+4,"investigation costs configured world time")
	check(op.snapshot().quests.quest_qinglan_001.status=="READY_TO_TURN_IN","event unlocks report stage")
	check(not act("claim",{"id":"quest_qinglan_001"}).success,"remote claim does not bypass report")
	var save: Dictionary=op.export_save()
	check(op.restore_save(save).is_empty() and current()=="report_tracks","save restores exact report stage")
	act("travel",{"id":"town_qinglan"})
	check(not act("claim",{"id":"quest_qinglan_001"}).success,"generic claim cannot replace dedicated report")
	var stones: int=op.snapshot().player.spirit_stones
	check(act("npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_001"}).success,"dedicated report")
	check(op.snapshot().quests.quest_qinglan_001.status=="COMPLETED" and op.snapshot().player.spirit_stones==stones+30 and op.snapshot().player.inventory.item_healing_powder==3,"reward actual and once")
	before=op.snapshot()
	check(not act("npc_option",{"npc":"npc_qin_shoushan","option":"report_quest_qinglan_001"}).success and op.snapshot()==before,"duplicate report atomic rejection")
	check(op.quests.dialogue_options(op.snapshot(),"npc_qin_shoushan",op.data).all(func(option):return option.id!="report_quest_qinglan_001"),"completed quest hides report")
	# Legacy migration preserves completed rewards; incomplete talk does not invent investigation.
	save=op.export_save();save.state.quests.quest_qinglan_001={"status":"COMPLETED","progress":1}
	check(op.restore_save(save).is_empty() and op.snapshot().quests.quest_qinglan_001.schema_version==2,"legacy completed migrated")
	check(op.snapshot().player.spirit_stones==before.player.spirit_stones,"migration no duplicate reward")
	save.state.quests.quest_qinglan_001={"status":"ACTIVE","progress":1}
	check(op.restore_save(save).is_empty() and current()=="ask_disturbance","legacy incomplete safely restarts explicit stages")
	# Any legal source of possession counts, including purchase before acceptance.
	gm.new_game("预购验收","水");op=gm.operations
	act("buy",{"shop":"shop_qinglan_general","item":"item_healing_powder","quantity":1})
	act("accept",{"id":"quest_qinglan_001"});act("npc_option",{"npc":"npc_qin_shoushan","option":"ask_qinglan_disturbance"})
	check(current()=="investigate_tracks","prepurchased supplies count")
	# Exhausting supplies invalidates current holding requirement, regardless of acquisition history.
	act("sell",{"shop":"shop_qinglan_general","item":"item_healing_powder","quantity":3})
	check(current()=="prepare_healing","possession reflects current inventory")
	act("buy",{"shop":"shop_qinglan_general","item":"item_healing_powder","quantity":1})
	check(current()=="investigate_tracks","purchase immediately refreshes possession")
	check(act("track_quest",{"id":"quest_qinglan_001"}).success and op.snapshot().tracked_quest_id=="quest_qinglan_001","tracking persisted")
	save=op.export_save();save.state.quests.quest_qinglan_001.current_objective_id="missing"
	check(not op.restore_save(save).is_empty(),"corrupt objective rejected")
	for field in ["giver_npc_id","target_id","target_location_id"]:
		var data: Dictionary=op.data.duplicate(true)
		if field=="giver_npc_id":data.quests.quest_qinglan_001[field]="missing"
		else:data.quests.quest_qinglan_001.objectives[0][field]="missing"
		check(not preload("res://gameplay/quest/quest_validation.gd").new().validate(data).is_empty(),"missing reference "+field+" reports error")
	var data: Dictionary=op.data.duplicate(true);data.events.erase("event_beast_tracks")
	check(not preload("res://gameplay/quest/quest_validation.gd").new().validate(data).is_empty(),"missing event configuration rejected")
	check(act("abandon_quest",{"id":"quest_qinglan_001"}).success,"may abandon quest")
	check(act("travel",{"id":"town_yunxi"}).success,"abandoned quest never blocks travel")

	# Isolated reusable objective template; no new formal content.
	var template: Dictionary=op.data.quests.quest_qinglan_001.duplicate(true)
	template.id="quest_test_visit";template.quest_id=template.id;template.previous="";template.requirements={"previous_quest_id":"","min_realm":1}
	template.objectives=[{"objective_id":"visit_test","description":"到达青岚镇","objective_type":"VISIT_LOCATION","target_id":"town_qinglan","target_location_id":"town_qinglan","required_count":2,"completion_condition":{},"hint":"真实来回移动"}]
	op.data.quests[template.id]=template
	check(act("accept",{"id":template.id}).success,"reusable visit objective accepted")
	act("travel",{"id":"town_qinglan"})
	check(op.snapshot().quests[template.id].objectives.visit_test.current_count==1,"real visit increments once")
	act("travel",{"id":"town_qinglan"})
	check(op.snapshot().quests[template.id].objectives.visit_test.current_count==1,"same-place click not another arrival")
	act("travel",{"id":"cave_qinglan"});act("travel",{"id":"town_qinglan"})
	check(op.snapshot().quests[template.id].objectives.visit_test.current_count==2,"required count greater than one")
	data=op.data.duplicate(true);data.quests.quest_qinglan_001.objectives[1].target_id="missing_item"
	check(not preload("res://gameplay/quest/quest_validation.gd").new().validate(data).is_empty(),"missing item configuration rejected")
	var saves:=preload("res://core/save_service.gd").new()
	var path: String=saves.write(op.export_save(),"user://test_saves")
	check(not path.is_empty() and op.restore_save(saves.read(path)).is_empty(),"actual disk save reload")

	gm.new_game("预先调查","木");op=gm.operations
	act("travel",{"id":"area_qinglan_outskirts"});act("investigate",{"id":"event_beast_tracks","option":"inspect_tracks"});act("travel",{"id":"town_qinglan"})
	check(op.snapshot().completed_events.has("event_beast_tracks"),"actual discovery completion marker persists")
	act("accept",{"id":"quest_qinglan_001"})
	check(current()=="ask_disturbance","prior discovery does not skip first serial step")
	act("npc_option",{"npc":"npc_qin_shoushan","option":"ask_qinglan_disturbance"})
	check(current()=="report_tracks","prior real discovery usable after prerequisites")

	gm.new_game("世界独立验收","火");op=gm.operations
	act("travel",{"id":"cave_qinglan"})
	var npc_before: int=op.snapshot().npcs.npc_lin_zhaoxi.cultivation
	check(not op.snapshot().mvp1,"fixture never visited Yunxi")
	check(act("retreat",{"days":30}).success,"noncombat month retreat without quest or sect")
	check(op.snapshot().npcs.npc_lin_zhaoxi.cultivation>npc_before,"NPC month growth independent of player milestone")
	print("QUEST REFACTOR: %d checks, %d failures" % [n,failures]);quit(0 if failures==0 else 1)
