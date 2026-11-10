extends RefCounted
const CLOCK = preload("res://core/time_system.gd")
const Fortunes = preload("res://gameplay/character/player_fortunes.gd")
const STATUSES: Array[String]=["LOCKED","AVAILABLE","ACTIVE","READY_TO_TURN_IN","COMPLETED","FAILED","EXPIRED"]
const TYPES: Array[String]=["TALK_OPTION","VISIT_LOCATION","ITEM_POSSESSION","ITEM_DELIVERY","KILL_ENEMY","COMPLETE_EVENT","REPORT_NPC"]
func status(s: Dictionary,id: String,data: Dictionary) -> String:
	if not data.quests.has(id):return "LOCKED"
	if s.quests.has(id):
		var stored := str(s.quests[id].get("status",""))
		if _repeat_rule(data.quests[id])=="DAILY" and stored in ["COMPLETED","FAILED"]:
			var open := stored=="FAILED" or repeat_available(s,id,data)
			if open:return "AVAILABLE" if requirement_error(s,id,data).is_empty() else "LOCKED"
		var delivery := _delivery_status(s,id,data,stored)
		if not delivery.is_empty():return delivery
		return stored
	return "AVAILABLE" if requirement_error(s,id,data).is_empty() else "LOCKED"
func requirement_error(s: Dictionary,id: String,data: Dictionary) -> String:
	if not data.quests.has(id):return "任务不存在"
	var r: Dictionary=data.quests[id].requirements
	var reasons: Array[String]=[]
	if not r.previous_quest_id.is_empty() and s.quests.get(r.previous_quest_id,{}).get("status","")!="COMPLETED":reasons.append("前置任务："+data.quests[r.previous_quest_id].title)
	if s.player.realm<r.min_realm:reasons.append("需要炼气%d层" % r.min_realm)
	var sect_id := str(r.get("sect_id",""))
	if not sect_id.is_empty() and s.get("sect","")!=sect_id:reasons.append("需要加入"+_sect_name(data,sect_id))
	var giver: String=data.quests[id].giver_npc_id
	if not giver.is_empty() and not s.npcs.get(giver,{}).get("alive",false):reasons.append("发布者已故或不可接触")
	if not reasons.is_empty():return "；".join(reasons)
	return ""
func instance(q: Dictionary) -> Dictionary:
	var objectives: Dictionary={}
	for o in q.objectives:objectives[o.objective_id]={"status":"INACTIVE","current_count":0}
	return {"schema_version":2,"quest_id":q.id,"status":"ACTIVE","current_objective_id":q.objectives[0].objective_id,"objectives":objectives,"progress":0}
func board_only(q: Dictionary) -> bool:
	return q.completion_mode == "BOARD"

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
		if _repeat_rule(q)=="DAILY":
			runtime.accepted_day=_game_day(s,data)
			runtime.reward_claimed=false
			if previous.has("reward_day"):runtime.reward_day=int(previous.reward_day)
	s.quests[id]=runtime;refresh(s,data)
	if s.get("tracked_quest_id","").is_empty():s.tracked_quest_id=id
	return ""
func current(s: Dictionary,id: String,data: Dictionary) -> Dictionary:
	var q: Dictionary=data.quests[id]
	var key: String=s.quests.get(id,{}).get("current_objective_id","")
	for o in q.objectives:
		if o.objective_id==key:return o
	return {}

func _delivery_status(s: Dictionary, id: String, data: Dictionary, stored: String) -> String:
	if stored not in ["ACTIVE","READY_TO_TURN_IN"]:return ""
	var objective := current(s,id,data)
	if objective.is_empty() or objective.objective_type!="ITEM_DELIVERY":return ""
	var held := int(s.player.inventory.get(objective.target_id,0))
	return "READY_TO_TURN_IN" if held>=int(objective.required_count) else "ACTIVE"
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
	var spoken: Array = _solo_dialogue_quests(s, npc_id, data)
	if spoken.size()==1:
		var node := _entry_node(spoken[0], status(s, spoken[0].id, data))
		if not str(node.get("line","")).is_empty(): lines.append(node.line)
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
			if o.objective_type=="VISIT_LOCATION" and o.completion_condition.get("steps",[]) is Array and not o.completion_condition.get("steps",[]).is_empty():
				if str(event.get("type",""))!="VISIT_LOCATION":continue
				var steps: Array=o.completion_condition.steps
				var index := int(r.current_count)
				if index<0 or index>=steps.size():continue
				var step: Dictionary=steps[index]
				var place := str(step.get("location",""))
				if str(event.get("target",""))!=place and str(event.get("location",""))!=place:continue
				if str(event.get("option",""))!=str(step.get("option_id","")):continue
				r.current_count=mini(int(o.required_count),index+1)
				continue
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
	var sect_error := requirement_error(s,id,data)
	if not sect_error.is_empty() and not str(q.requirements.get("sect_id","")).is_empty():return sect_error
	if _repeat_rule(q)=="DAILY" and s.quests[id].get("reward_claimed",false)==true:return "今日奖励已经领取"
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
	var contribution := _grant_contribution(s,int(q.get("contribution",0)))
	if str(q.get("requirements",{}).get("sect_id",""))==str(s.get("sect","")) and not str(s.get("sect","")).is_empty():
		preload("res://gameplay/sect/sect_arena.gd").note_quest_merit(s,contribution)
	s.quests[id].status="COMPLETED";s.quests[id].progress=1;s.quests[id].current_objective_id=""
	if q.get("repeatable",false):
		var runtime: Dictionary = s.quests[id]
		runtime.round = int(runtime.get("round",1))
		runtime.completed_count = int(runtime.get("completed_count",0)) + 1
		runtime.last_completed_time = CLOCK.new().seconds(s)
		if _repeat_rule(q)=="DAILY":
			runtime.reward_claimed=true
			runtime.reward_day=_game_day(s,data)
			runtime.next_available_time=_next_day_start(s,data)
		else:
			runtime.next_available_time = runtime.last_completed_time + int(q.repeat_interval_days) * int(CLOCK.new().calendar_units(data).day_hours) * 3600
	var reward_text: Array[String]=[]
	if contribution>0:reward_text.append("宗门贡献 +%d" % contribution)
	reward_text.append("灵石 +%d" % q.money)
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
	if _daily_navigation(s,npc_id,data,previous_option):return _daily_focused(s,npc_id,data,previous_option)
	result.append_array(preload("res://gameplay/sect/sect_arena.gd").dialogue_options(s,npc_id,data,previous_option))
	_append_daily_root(result,s,npc_id,data)
	for id in data.quests:
		var q: Dictionary=data.quests[id]
		if q.has("dialogue"):continue
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
func resolve_option(s: Dictionary, npc_id: String, data: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty():return {}
	var arena_option: Dictionary = preload("res://gameplay/sect/sect_arena.gd").find_option(s,npc_id,data,option_id)
	if not arena_option.is_empty():return arena_option
	var configured := _configured_daily_option(s,npc_id,data,option_id)
	if not configured.is_empty() and _daily_option_allowed(s,data,configured):return configured
	for option in dialogue_options(s,npc_id,data,""):
		if option.id==option_id:return option
	return {}
func location_actions(s: Dictionary, data: Dictionary) -> Array:
	var result: Array=[]
	var place := str(s.get("player",{}).get("location",""))
	for id in s.get("quests",{}):
		if not data.quests.has(id):continue
		var runtime: Dictionary=s.quests[id]
		if str(runtime.get("status","")) not in ["ACTIVE","READY_TO_TURN_IN"]:continue
		var objective := current(s,str(id),data)
		if objective.is_empty() or objective.objective_type!="VISIT_LOCATION":continue
		var steps: Array=objective.completion_condition.get("steps",[])
		if steps.is_empty():continue
		var index := int(runtime.objectives[objective.objective_id].get("current_count",0))
		if index<0 or index>=steps.size():continue
		var step: Dictionary=steps[index]
		if str(step.get("location",""))!=place:continue
		result.append({"quest_id":str(id),"option_id":str(step.option_id),"location":place,"label":str(step.label),"prompt":str(step.prompt),"confirm":str(step.confirm),"response":str(step.response)})
	return result
func _repeat_rule(q: Dictionary) -> String:
	if str(q.get("repeat_rule",""))=="DAILY":return "DAILY"
	if q.get("repeatable",false):return "INTERVAL"
	return "ONCE"
func _day_seconds(data: Dictionary) -> int:
	return int(CLOCK.new().calendar_units(data).day_hours)*3600
func _game_day(s: Dictionary, data: Dictionary) -> int:
	return int(CLOCK.new().seconds(s)/_day_seconds(data))
func _next_day_start(s: Dictionary, data: Dictionary) -> int:
	var day := _day_seconds(data)
	return (int(CLOCK.new().seconds(s)/day)+1)*day
func _grant_contribution(s: Dictionary, base: int) -> int:
	if base<=0:return 0
	var gained := roundi(float(base)*(100+Fortunes.modifier(s.player,"contribution"))/100.0)
	s.contribution+=gained
	return gained
func _sect_name(data: Dictionary, sect_id: String) -> String:
	for sect in data.prototype.sects:
		if sect.id==sect_id:return str(sect.name)
	return "宗门"
func _dialogue_quests(npc_id: String, data: Dictionary) -> Array:
	var result: Array=[]
	for id in data.quests:
		var q: Dictionary=data.quests[id]
		if q.giver_npc_id==npc_id and q.get("dialogue",{}) is Dictionary and not q.get("dialogue",{}).is_empty():result.append(q)
	return result
func _quest_visible(s: Dictionary, q: Dictionary, data: Dictionary) -> bool:
	return status(s,q.id,data)!="LOCKED"
func _status_name(value: String) -> String:
	return {"AVAILABLE":"可接取","ACTIVE":"进行中","READY_TO_TURN_IN":"可交付","COMPLETED":"今日已完成","LOCKED":"未解锁","FAILED":"已失败"}.get(value,value)
func _entry_node(q: Dictionary, status_value: String) -> Dictionary:
	var fallback := {}
	for node_id in q.dialogue.nodes:
		var node: Dictionary=q.dialogue.nodes[node_id]
		if status_value in node.get("statuses",[]):
			if node.get("entry",false):return node
			if fallback.is_empty():fallback=node
	return fallback
func _entry_node_id(q: Dictionary, status_value: String) -> String:
	var fallback := ""
	for node_id in q.dialogue.nodes:
		var node: Dictionary=q.dialogue.nodes[node_id]
		if status_value in node.get("statuses",[]):
			if node.get("entry",false):return str(node_id)
			if fallback.is_empty():fallback=str(node_id)
	return fallback
func _group_members(s: Dictionary, npc_id: String, data: Dictionary, group: String) -> Array:
	var result: Array=[]
	for q in _dialogue_quests(npc_id,data):
		if str(q.dialogue.get("group",""))==group and _quest_visible(s,q,data):result.append(q)
	return result
func _solo_dialogue_quests(s: Dictionary, npc_id: String, data: Dictionary) -> Array:
	var result: Array=[]
	var grouped := {}
	for q in _dialogue_quests(npc_id,data):
		var group := str(q.dialogue.get("group",""))
		if group.is_empty():
			if _quest_visible(s,q,data):result.append(q)
		else:grouped[group]=true
	for group in grouped:
		var members := _group_members(s,npc_id,data,group)
		if members.size()==1:result.append(members[0])
	return result
func _hub_groups(s: Dictionary, npc_id: String, data: Dictionary) -> Array:
	var result: Array=[]
	var seen := {}
	for q in _dialogue_quests(npc_id,data):
		var group := str(q.dialogue.get("group",""))
		if group.is_empty() or seen.has(group):continue
		seen[group]=true
		if _group_members(s,npc_id,data,group).size()>=2:result.append(group)
	return result
func _option_row(quest_id: String, node_id: String, option: Dictionary, npc_id: String) -> Dictionary:
	return {"id":"%s:%s:%s" % [quest_id,node_id,option.id],"label":str(option.label),"response":str(option.response),"quest":quest_id,"kind":str(option.kind),"next":str(option.get("next","")),"event_option":str(option.get("event_option","")),"target":npc_id,"node":node_id}
func _node_rows(q: Dictionary, node_id: String, npc_id: String) -> Array:
	var result: Array=[]
	var node: Dictionary=q.dialogue.nodes.get(node_id,{})
	for option in node.get("options",[]):
		result.append(_option_row(q.id,node_id,option,npc_id))
	return result
func _hub_button(npc_id: String) -> Dictionary:
	return {"id":"daily_hub:"+npc_id,"label":"查看宗门日常委托","response":"事务殿眼下有这些日常委托。","quest":"","kind":"reply","next":"hub","event_option":"","target":npc_id}
func _hub_menu(s: Dictionary, npc_id: String, data: Dictionary, group: String) -> Array:
	var result: Array=[]
	for q in _group_members(s,npc_id,data,group):
		var value := status(s,q.id,data)
		var node := _entry_node(q,value)
		result.append({"id":"daily_open:"+q.id,"label":"%s（%s）" % [q.title,_status_name(value)],"response":str(node.get("line","")),"quest":q.id,"kind":"reply","next":"quest:"+q.id,"event_option":"","target":npc_id})
	result.append({"id":"daily_back:"+npc_id,"label":"返回","response":"有事再来。","quest":"","kind":"reply","next":"close","event_option":"","target":npc_id})
	return result
func _quest_menu(s: Dictionary, q: Dictionary, data: Dictionary, npc_id: String, with_return: bool) -> Array:
	var rows := _node_rows(q,_entry_node_id(q,status(s,q.id,data)),npc_id)
	if with_return:rows.append({"id":"daily_return:"+q.id,"label":"返回","response":"还有哪一件要办？","quest":q.id,"kind":"reply","next":"hub","event_option":"","target":npc_id})
	return rows
func _append_daily_root(result: Array, s: Dictionary, npc_id: String, data: Dictionary) -> void:
	for group in _hub_groups(s,npc_id,data):result.append(_hub_button(npc_id))
	for q in _solo_dialogue_quests(s,npc_id,data):result.append_array(_quest_menu(s,q,data,npc_id,false))
func _configured_daily_option(s: Dictionary, npc_id: String, data: Dictionary, option_id: String) -> Dictionary:
	if option_id=="daily_hub:"+npc_id:return _hub_button(npc_id)
	if option_id=="daily_back:"+npc_id:return {"id":option_id,"label":"返回","response":"有事再来。","quest":"","kind":"reply","next":"close","event_option":"","target":npc_id}
	for q in _dialogue_quests(npc_id,data):
		if option_id=="daily_open:"+q.id:
			var node := _entry_node(q,status(s,q.id,data))
			return {"id":option_id,"label":q.title,"response":str(node.get("line","")),"quest":q.id,"kind":"reply","next":"quest:"+q.id,"event_option":"","target":npc_id}
		if option_id=="daily_return:"+q.id:return {"id":option_id,"label":"返回","response":"还有哪一件要办？","quest":q.id,"kind":"reply","next":"hub","event_option":"","target":npc_id}
		for node_id in q.dialogue.nodes:
			for option in q.dialogue.nodes[node_id].get("options",[]):
				var row := _option_row(q.id,str(node_id),option,npc_id)
				if row.id==option_id:return row
	return {}
func _daily_option_allowed(s: Dictionary, data: Dictionary, option: Dictionary) -> bool:
	var option_id := str(option.get("id",""))
	if option_id.begins_with("daily_hub:") or option_id.begins_with("daily_back:"):return true
	var quest_id := str(option.get("quest",""))
	if quest_id.is_empty() or not data.quests.has(quest_id):return false
	if not _quest_visible(s,data.quests[quest_id],data):return false
	if option_id.begins_with("daily_open:") or option_id.begins_with("daily_return:"):return true
	var node_id := str(option.get("node",""))
	var node: Dictionary=data.quests[quest_id].dialogue.nodes.get(node_id,{})
	return status(s,quest_id,data) in node.get("statuses",[])
func _looks_like_daily_option(data: Dictionary, npc_id: String, option_id: String) -> bool:
	if option_id.begins_with("daily_"):return true
	for q in _dialogue_quests(npc_id,data):
		if option_id.begins_with(q.id+":"):return true
	return false
func _daily_navigation(s: Dictionary, npc_id: String, data: Dictionary, previous_option: String) -> bool:
	return not previous_option.is_empty() and _looks_like_daily_option(data,npc_id,previous_option)
func _daily_focused(s: Dictionary, npc_id: String, data: Dictionary, previous_option: String) -> Array:
	var option := _configured_daily_option(s,npc_id,data,previous_option)
	if option.is_empty():return []
	var nxt := str(option.get("next",""))
	if nxt=="close" or nxt.is_empty():return []
	if nxt=="hub" or previous_option.begins_with("daily_hub:"):
		var groups := _hub_groups(s,npc_id,data)
		return _hub_menu(s,npc_id,data,str(groups[0])) if not groups.is_empty() else []
	if nxt.begins_with("quest:") or previous_option.begins_with("daily_open:"):
		var quest_id := nxt.trim_prefix("quest:") if nxt.begins_with("quest:") else previous_option.trim_prefix("daily_open:")
		if not data.quests.has(quest_id):return []
		return _quest_menu(s,data.quests[quest_id],data,npc_id,not _hub_groups(s,npc_id,data).is_empty())
	var quest_id := str(option.get("quest",""))
	if data.quests.has(quest_id) and data.quests[quest_id].dialogue.nodes.has(nxt) and status(s,quest_id,data) in data.quests[quest_id].dialogue.nodes[nxt].get("statuses",[]):
		return _node_rows(data.quests[quest_id],nxt,npc_id)
	return []
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
