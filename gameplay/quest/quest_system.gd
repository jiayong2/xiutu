extends RefCounted
const CLOCK = preload("res://core/time_system.gd")
const STATUSES: Array[String]=["LOCKED","AVAILABLE","ACTIVE","READY_TO_TURN_IN","COMPLETED","FAILED","EXPIRED"]
const TYPES: Array[String]=["TALK_OPTION","VISIT_LOCATION","ITEM_POSSESSION","ITEM_DELIVERY","KILL_ENEMY","COMPLETE_EVENT","REPORT_NPC"]
func status(s: Dictionary,id: String,data: Dictionary) -> String:
	if s.quests.has(id):return s.quests[id].status
	return "AVAILABLE" if requirement_error(s,id,data).is_empty() else "LOCKED"
func requirement_error(s: Dictionary,id: String,data: Dictionary) -> String:
	if not data.quests.has(id):return "任务不存在"
	var r: Dictionary=data.quests[id].requirements
	var reasons: Array[String]=[]
	if not r.previous_quest_id.is_empty() and s.quests.get(r.previous_quest_id,{}).get("status","")!="COMPLETED":reasons.append("前置任务："+data.quests[r.previous_quest_id].title)
	if s.player.realm<r.min_realm:reasons.append("需要炼气%d层" % r.min_realm)
	var giver: String=data.quests[id].giver_npc_id
	if not giver.is_empty() and not s.npcs.get(giver,{}).get("alive",false):reasons.append("发布者已故或不可接触")
	if not reasons.is_empty():return "；".join(reasons)
	return ""
func instance(q: Dictionary) -> Dictionary:
	var objectives: Dictionary={}
	for o in q.objectives:objectives[o.objective_id]={"status":"INACTIVE","current_count":0}
	return {"schema_version":2,"quest_id":q.id,"status":"ACTIVE","current_objective_id":q.objectives[0].objective_id,"objectives":objectives,"progress":0}
func board_only(q: Dictionary) -> bool:
	return q.get("repeatable",false) or q.completion_mode == "BOARD"

func repeat_available(s: Dictionary, id: String, data: Dictionary) -> bool:
	var previous: Dictionary = s.quests.get(id,{})
	return data.quests[id].get("repeatable",false) and previous.get("status") == "COMPLETED" and CLOCK.new().seconds(s) >= int(previous.get("next_available_time",0))

func accept(s: Dictionary,id: String,data: Dictionary,from_board: bool=false) -> String:
	var error:=requirement_error(s,id,data)
	if not error.is_empty():return error
	var q: Dictionary = data.quests[id]
	if board_only(q) and not from_board:return "请在公告栏接取委托"
	var previous: Dictionary = s.quests.get(id,{})
	if not previous.is_empty() and previous.status!="FAILED" and not repeat_available(s,id,data):
		return "任务已接取或完成"
	var runtime := instance(q)
	if q.get("repeatable",false):
		var legacy_completion := int(previous.get("status") == "COMPLETED")
		runtime.round = int(previous.get("round", 0 if previous.is_empty() else 1)) + 1
		runtime.completed_count = int(previous.get("completed_count",legacy_completion))
		runtime.last_completed_time = int(previous.get("last_completed_time",0))
		runtime.next_available_time = int(previous.get("next_available_time",0))
	s.quests[id]=runtime;refresh(s,data)
	if s.get("tracked_quest_id","").is_empty():s.tracked_quest_id=id
	return ""
func current(s: Dictionary,id: String,data: Dictionary) -> Dictionary:
	var q: Dictionary=data.quests[id]
	var key: String=s.quests.get(id,{}).get("current_objective_id","")
	for o in q.objectives:
		if o.objective_id==key:return o
	return {}

func objective_count(s: Dictionary, id: String, objective: Dictionary) -> int:
	var runtime: Dictionary = s.quests[id].objectives[objective.objective_id]
	if objective.objective_type == "ITEM_DELIVERY" and runtime.status == "ACTIVE" and s.quests[id].status in ["ACTIVE", "READY_TO_TURN_IN"]:
		return mini(int(objective.required_count), int(s.player.inventory.get(objective.target_id, 0)))
	return int(runtime.current_count)

func dialogue_line(s: Dictionary, npc_id: String, data: Dictionary) -> String:
	var lines: Array[String] = []
	for q in data.quests.values():
		if q.giver_npc_id != npc_id or not q.has("delivery_dialogue") or q.objectives[0].target_location_id != s.player.location:
			continue
		var stage: Dictionary = q.delivery_dialogue.get(_dialogue_status(s, q.id, data), {})
		if not stage.is_empty():
			lines.append(stage.line)
	return "\n".join(lines)

func _dialogue_status(s: Dictionary, id: String, data: Dictionary) -> String:
	var value := status(s, id, data)
	if value == "FAILED" and requirement_error(s, id, data).is_empty():
		return "AVAILABLE"
	return value
func refresh(s: Dictionary,data: Dictionary) -> void:
	for id in s.quests:
		var runtime: Dictionary=s.quests[id]
		if runtime.status in ["COMPLETED","FAILED","EXPIRED"]:continue
		var q: Dictionary=data.quests[id]
		if q.get("fail_on_giver_death",true) and not q.giver_npc_id.is_empty() and not s.npcs.get(q.giver_npc_id,{}).get("alive",false):
			runtime.status="FAILED";runtime.failure_reason="发布者已故，任务无法交付";continue
		# Possession is live until the task is turned in, including after later stages activate.
		var possession_ok:=true
		for o in q.objectives:
			var r: Dictionary=runtime.objectives[o.objective_id]
			if o.objective_type=="ITEM_POSSESSION" and r.status!="INACTIVE":
				r.current_count=mini(int(o.required_count),int(s.player.inventory.get(o.target_id,0)))
				r.status="COMPLETED" if r.current_count>=o.required_count else "ACTIVE"
				if r.status!="COMPLETED":possession_ok=false
		var active_found:=false
		var completed:=0
		runtime.current_objective_id=""
		for o in q.objectives:
			var r: Dictionary=runtime.objectives[o.objective_id]
			if active_found and q.get("serial",true):
				if r.status!="COMPLETED":r.status="INACTIVE"
				continue
			if o.objective_type=="COMPLETE_EVENT" and s.get("completed_events",{}).get(o.target_id,{}).get("option","")==o.completion_condition.get("option_id",""):
				r.current_count=mini(int(o.required_count),int(s.completed_events[o.target_id].get("count",1)))
			if o.objective_type=="ITEM_POSSESSION":
				r.current_count=mini(int(o.required_count),int(s.player.inventory.get(o.target_id,0)))
			if r.current_count>=o.required_count:
				r.status="COMPLETED";completed+=1;continue
			r.status="ACTIVE"
			if not active_found:runtime.current_objective_id=o.objective_id
			active_found=true
		var objective:=current(s,id,data)
		runtime.progress=1 if completed==q.objectives.size() or (possession_ok and completed==q.objectives.size()-1 and not objective.is_empty() and objective.objective_type in ["REPORT_NPC","ITEM_DELIVERY"]) else 0
		if not objective.is_empty() and objective.objective_type=="ITEM_DELIVERY" and s.player.inventory.get(objective.target_id,0)<objective.required_count:runtime.progress=0
		runtime.status="READY_TO_TURN_IN" if runtime.progress==1 else "ACTIVE"
func notify(s: Dictionary,event: Variant,data: Dictionary) -> void:
	if not event is Dictionary:return
	var battle_id: String = event.get("battle_id","")
	if event.get("type") == "KILL_ENEMY" and (battle_id.is_empty() or s.battle.get("id","") != battle_id or s.get("pending_battle_result","") != "win"):
		return
	for id in s.quests:
		var runtime: Dictionary = s.quests[id]
		if runtime.status not in ["ACTIVE","READY_TO_TURN_IN"]:continue
		if not battle_id.is_empty() and runtime.get("last_battle_id","") == battle_id:continue
		for o in data.quests[id].objectives:
			var r: Dictionary=runtime.objectives[o.objective_id]
			if r.status!="ACTIVE" or o.objective_type in ["ITEM_POSSESSION","ITEM_DELIVERY"]:continue
			if o.objective_type=="REPORT_NPC" and s.quests[id].status!="READY_TO_TURN_IN":continue
			if o.objective_type!=event.get("type","") or o.target_id!=event.get("target",""):continue
			if not o.target_location_id.is_empty() and o.target_location_id!=event.get("location",""):continue
			if o.completion_condition.has("option_id") and o.completion_condition.option_id!=event.get("option",""):continue
			var count := 1
			if o.objective_type == "KILL_ENEMY":
				count = maxi(0,int(event.get("count",1)))
				if count == 0:continue
				runtime.last_battle_id = battle_id
			r.current_count=mini(int(o.required_count),int(r.current_count)+count)
		# Activate the next objective only after handling the event, never reuse one event for two serial steps.
		refresh(s,data)
func claim(s: Dictionary,id: String,data: Dictionary,inventory: RefCounted,report_npc: String="",from_board: bool=false) -> String:
	refresh(s,data)
	if not s.quests.has(id) or s.quests[id].status!="READY_TO_TURN_IN":return "任务尚未完成或已经领取"
	var q: Dictionary=data.quests[id]
	if q.completion_mode == "BOARD" and not from_board:return "请返回公告栏交付委托"
	var o:=current(s,id,data)
	var contact_id: String=o.completion_condition.get("npc_id",q.giver_npc_id) if not o.is_empty() else q.giver_npc_id
	if not report_npc.is_empty():contact_id=report_npc
	var npc: Dictionary=s.npcs.get(contact_id,{})
	if not contact_id.is_empty() and (npc.is_empty() or not npc.alive or npc.location!=s.player.location):return "请前往交付对象所在地点；人物可能已离开或不可接触"
	if not o.is_empty():
		if o.objective_type!="ITEM_DELIVERY":return "请通过发布者的专属报告选项提交"
		if o.completion_condition.get("npc_id","")!=contact_id:return "交付对象不匹配"
		if not o.target_location_id.is_empty() and s.player.location!=o.target_location_id:return "交付地点不匹配"
		var error: String=inventory.remove(s.player,o.target_id,int(o.required_count))
		if not error.is_empty():return "缺少%s ×%d" % [data.items[o.target_id].name,o.required_count]
		var r: Dictionary=s.quests[id].objectives[o.objective_id]
		r.current_count=o.required_count;r.status="COMPLETED"
	for item in q.rewards:
		var error: String=inventory.add(s.player,item,int(q.rewards[item]),data,id)
		if not error.is_empty():return error
	s.player.spirit_stones+=q.money
	s.quests[id].status="COMPLETED";s.quests[id].progress=1;s.quests[id].current_objective_id=""
	if q.get("repeatable",false):
		var runtime: Dictionary = s.quests[id]
		runtime.round = int(runtime.get("round",1))
		runtime.completed_count = int(runtime.get("completed_count",0)) + 1
		runtime.last_completed_time = CLOCK.new().seconds(s)
		runtime.next_available_time = runtime.last_completed_time + int(q.repeat_interval_days) * int(CLOCK.new().calendar_units(data).day_hours) * 3600
	var reward_text: Array[String]=["灵石 +%d" % q.money]
	for item in q.rewards:reward_text.append("%s +%d" % [data.items[item].name,q.rewards[item]])
	var next_hint: String="可自由探索、修炼或经营洞府。"
	for next_id in data.quests:
		if status(s,next_id,data)=="AVAILABLE":
			next_hint="可接《%s》，也可自由探索和修炼。" % data.quests[next_id].title;break
	s.last_result="完成《%s》：%s。下一步：%s" % [q.title,"、".join(reward_text),next_hint]
	return ""
func dialogue_options(s: Dictionary,npc_id: String,data: Dictionary,previous_option: String="") -> Array:
	var result: Array=[]
	var npc: Dictionary=s.npcs.get(npc_id,{})
	if npc.is_empty() or not npc.alive or npc.location!=s.player.location:return result
	for id in data.quests:
		var q: Dictionary=data.quests[id]
		var active_objective:=current(s,id,data)
		var objective_npc: String=active_objective.get("target_id","") if active_objective.get("objective_type","") in ["TALK_OPTION","REPORT_NPC"] else active_objective.get("completion_condition",{}).get("npc_id","")
		if q.giver_npc_id!=npc_id and objective_npc!=npc_id:continue
		var value:=status(s,id,data)
		if q.has("delivery_dialogue"):
			value = _dialogue_status(s, id, data)
			if q.objectives[0].target_location_id != s.player.location or not q.delivery_dialogue.has(value):
				continue
			var configured: Array = q.delivery_dialogue[value].options
			var prefix: String = id + ":"
			var follow := ""
			if previous_option.begins_with(prefix):
				for stage in q.delivery_dialogue.values():
					for option in stage.options:
						if prefix + option.id == previous_option:
							follow = option.get("follow", "")
			if follow == "close":
				continue
			for option in configured:
				var option_id: String = prefix + option.id
				if follow == "hide_self" and option_id == previous_option:
					continue
				result.append({"id":option_id, "label":option.label, "response":option.response, "quest":id, "kind":option.kind})
			continue
		if value=="AVAILABLE" and not board_only(q):result.append({"id":"accept_"+id,"label":"接受委托："+q.title,"quest":id,"kind":"accept"})
		elif value in ["ACTIVE","READY_TO_TURN_IN"]:
			var o:=current(s,id,data)
			if not o.is_empty() and not o.target_location_id.is_empty() and o.objective_type in ["TALK_OPTION","REPORT_NPC","ITEM_DELIVERY"] and o.target_location_id!=s.player.location:
				result.append({"id":"progress_"+id,"label":"询问委托进展："+q.title,"quest":id,"kind":"progress"})
			elif not o.is_empty() and o.objective_type in ["TALK_OPTION","REPORT_NPC"] and o.target_id==npc_id:
				result.append({"id":o.completion_condition.option_id,"label":o.completion_condition.get("label",o.description),"response":o.completion_condition.get("response","任务对话已记录"),"quest":id,"kind":o.objective_type})
			elif not o.is_empty() and o.objective_type=="ITEM_DELIVERY":
				result.append({"id":"deliver_"+id,"label":"交付"+q.title,"quest":id,"kind":"delivery"})
			else:result.append({"id":"progress_"+id,"label":"询问委托进展："+q.title,"quest":id,"kind":"progress"})
	return result
func migrate(s: Dictionary,data: Dictionary) -> void:
	if not s.has("tracked_quest_id"):s.tracked_quest_id=""
	if not s.has("completed_events"):s.completed_events={}
	for id in s.quests:
		var old: Dictionary=s.quests[id]
		if old.has("schema_version"):continue
		var runtime:=instance(data.quests[id])
		if old.status=="COMPLETED":
			runtime.status="COMPLETED";runtime.progress=1;runtime.current_objective_id=""
			for o in data.quests[id].objectives:
				var r: Dictionary=runtime.objectives[o.objective_id]
				r.status="COMPLETED";r.current_count=o.required_count
		elif id!="quest_qinglan_001" and old.progress==1:
			var first: Dictionary=runtime.objectives[data.quests[id].objectives[0].objective_id]
			first.current_count=1;first.status="COMPLETED"
		s.quests[id]=runtime
	refresh(s,data)
func track(s: Dictionary,id: String,data: Dictionary) -> String:
	if not data.quests.has(id):return "任务不存在"
	s.tracked_quest_id=id
	return ""
func abandon(s: Dictionary,id: String) -> String:
	if not s.quests.has(id) or s.quests[id].status not in ["ACTIVE","READY_TO_TURN_IN"]:return "当前任务不能放弃"
	s.quests[id].status="FAILED"
	if s.get("tracked_quest_id","")==id:s.tracked_quest_id=""
	return ""
