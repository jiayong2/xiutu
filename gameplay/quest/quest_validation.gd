extends RefCounted
const PLACES: Array[String]=["town_qinglan","town_yunxi","cave_qinglan","area_qinglan_outskirts","sect_qingyue_gate"]
func validate(data: Dictionary) -> String:
	var npcs: Dictionary={}
	for npc in data.prototype.npcs:npcs[npc.id]=true
	var all_objectives: Dictionary={}
	for q in data.quests.values():
		for key in ["quest_id","title","description","quest_type","giver_npc_id","recommended_realm","requirements","objectives","completion_mode"]:
			if not q.has(key):return "任务缺少字段："+q.id+"/"+key
		if q.quest_id!=q.id or q.title!=q.name or q.requirements.get("previous_quest_id","")!=q.previous or q.requirements.get("min_realm")!=q.realm:return "任务兼容字段不一致："+q.id
		if q.quest_id!=q.id or not q.objectives is Array or q.objectives.is_empty():return "任务ID或目标数组无效："+q.id
		if not q.giver_npc_id.is_empty() and not npcs.has(q.giver_npc_id):return "任务NPC引用无效："+q.id
		if not q.get("fail_on_giver_death",true) is bool:return "任务失败条件配置无效："+q.id
		if not q.get("repeatable",false) is bool:return "任务重复配置无效："+q.id
		if q.has("repeat_rule") and str(q.repeat_rule) not in ["DAILY","INTERVAL"]:return "任务重复规则无效："+q.id
		if str(q.get("repeat_rule",""))=="DAILY" and not q.get("repeatable",false):return "每日任务必须允许重复："+q.id
		if q.get("repeatable",false) and (not _count(q.get("repeat_interval_days"),2147483647) or q.repeat_interval_days<=0):return "任务刷新天数无效："+q.id
		if q.has("contribution") and not _count(q.contribution,2147483647):return "任务贡献奖励无效："+q.id
		if q.has("turn_in_label") and not _nonempty_text(q.turn_in_label):return "任务交付地点无效："+q.id
		var sect_id := str(q.requirements.get("sect_id",""))
		if not sect_id.is_empty():
			var known_sect := false
			for sect in data.prototype.sects:
				if sect.id==sect_id:known_sect=true
			if not known_sect:return "任务宗门引用无效："+q.id
		if q.requirements.has("min_sect_rank") and str(q.requirements.min_sect_rank)!="outer":return "任务宗门身份无效："+q.id
		for o in q.objectives:
			for key in ["objective_id","description","objective_type","target_id","target_location_id","required_count","completion_condition","hint"]:
				if not o.has(key):return "目标缺少字段："+q.id+"/"+key
			if all_objectives.has(q.id+":"+o.objective_id):return "目标ID重复："+q.id
			all_objectives[q.id+":"+o.objective_id]=true
			if o.objective_type not in preload("res://gameplay/quest/quest_system.gd").TYPES:return "目标类型无效："+q.id
			if not o.required_count is float and not o.required_count is int:return "目标数量类型无效："+q.id
			if o.required_count<1 or floor(float(o.required_count))!=o.required_count:return "目标数量无效："+q.id
			if not o.target_location_id.is_empty() and o.target_location_id not in PLACES:return "目标地点引用无效："+q.id
			var valid:=true
			match o.objective_type:
				"TALK_OPTION","REPORT_NPC":valid=npcs.has(o.target_id) and o.completion_condition.has("option_id")
				"ITEM_DELIVERY":
					var contact: String = o.completion_condition.get("npc_id","")
					valid = data.items.has(o.target_id) and (contact.is_empty() and q.giver_npc_id.is_empty() if q.completion_mode == "BOARD" else npcs.has(contact))
				"ITEM_POSSESSION":valid=data.items.has(o.target_id)
				"KILL_ENEMY":valid=data.monsters.has(o.target_id)
				"VISIT_LOCATION":valid=o.target_id in PLACES
				"COMPLETE_EVENT":valid=data.events.has(o.target_id)
			if not valid:return "任务目标引用无效："+q.id+"/"+o.objective_id
			if o.objective_type=="COMPLETE_EVENT":
				var event: Dictionary=data.events[o.target_id]
				if event.location_id!=o.target_location_id:return "任务事件地点不一致："+q.id
				var found:=false
				for option in event.options:
					if option.id==o.completion_condition.get("option_id",""):found=true
				if not found:return "任务事件选项引用无效："+q.id
			var steps: Variant=o.completion_condition.get("steps",[])
			if steps is Array and not steps.is_empty():
				if o.objective_type!="VISIT_LOCATION" or steps.size()!=int(o.required_count):return "巡查步骤无效："+q.id
				var seen_step := {}
				for step in steps:
					if not step is Dictionary or step.get("location","") not in PLACES or seen_step.has(step.get("option_id","")):return "巡查步骤无效："+q.id
					if not _nonempty_text(step.get("option_id")) or not _nonempty_text(step.get("label")) or not _nonempty_text(step.get("prompt")) or not _nonempty_text(step.get("confirm")) or not _nonempty_text(step.get("response")):return "巡查步骤无效："+q.id
					seen_step[step.option_id]=true
				if str(steps[0].location)!=o.target_id:return "巡查起点不一致："+q.id
		if q.has("dialogue"):
			var dialogue_error := _validate_dialogue(q,npcs)
			if not dialogue_error.is_empty():return dialogue_error
		if q.has("delivery_dialogue") or q.has("delivery_shop_id"):
			var error := _validate_delivery(q, data)
			if not error.is_empty():return error
	for event in data.events.values():
		if event.location_id not in PLACES or not event.options is Array or event.options.is_empty():return "探索事件配置无效："+event.id
		for option in event.options:
			if not option.get("id") is String or not option.get("result") is String or not _count(option.get("hours"),2147483647):return "探索选项配置无效："+event.id
	return ""

func _validate_delivery(q: Dictionary, data: Dictionary) -> String:
	var error: String = "收集委托对话配置无效：" + q.id
	if q.objectives.size() != 1 or q.completion_mode != "ITEM_DELIVERY":
		return error
	var objective: Dictionary = q.objectives[0]
	if objective.objective_type != "ITEM_DELIVERY" or objective.target_location_id.is_empty() or objective.completion_condition.npc_id != q.giver_npc_id:
		return error
	if q.has("delivery_shop_id"):
		var shop: Dictionary = data.shops.get(q.delivery_shop_id, {})
		if shop.get("npc_id") != q.giver_npc_id or shop.get("location") != objective.target_location_id:
			return "收集委托交付店铺引用无效：" + q.id
	if not q.get("delivery_dialogue") is Dictionary or not _count(q.money, 2147483647):
		return error
	var required_actions := {"AVAILABLE":"accept", "ACTIVE":"", "READY_TO_TURN_IN":"delivery", "COMPLETED":""}
	if q.delivery_dialogue.size() != required_actions.size():
		return error
	var seen := {}
	for key in required_actions:
		var stage: Variant = q.delivery_dialogue.get(key)
		if not stage is Dictionary or not _nonempty_text(stage.get("line")) or not stage.get("options") is Array:
			return error
		if stage.options.is_empty() != (key == "COMPLETED"):
			return error
		var required: String = required_actions[key]
		var found := required.is_empty()
		for option in stage.options:
			if not option is Dictionary or not _nonempty_text(option.get("id")) or seen.has(option.id):
				return error
			if not _nonempty_text(option.get("label")) or not _nonempty_text(option.get("response")):
				return error
			if option.get("kind") != "reply" and (required.is_empty() or option.get("kind") != required):
				return error
			if option.get("follow", "") not in ["", "hide_self", "close"]:
				return error
			seen[option.id] = true
			found = found or option.kind == required
		if not found:return error
	return ""

func _validate_dialogue(q: Dictionary, npcs: Dictionary) -> String:
	var dialogue: Variant=q.dialogue
	if not dialogue is Dictionary or not dialogue.get("nodes") is Dictionary or dialogue.nodes.is_empty():return "任务对话无效："+q.id
	if dialogue.has("group") and not dialogue.group is String:return "任务对话分组无效："+q.id
	var covered := {}
	var seen := {}
	var has_accept := false
	var has_delivery := false
	for node_id in dialogue.nodes:
		var node: Variant=dialogue.nodes[node_id]
		if not node is Dictionary or not node.get("statuses") is Array or not node.get("options") is Array or not node.get("line") is String:return "任务对话节点无效："+q.id
		for value in node.statuses:
			if value not in ["AVAILABLE","ACTIVE","READY_TO_TURN_IN","COMPLETED"]:return "任务对话状态无效："+q.id
			if node.get("entry",false):covered[value]=true
		for option in node.options:
			if not option is Dictionary or not _nonempty_text(option.get("id")) or seen.has(str(node_id)+":"+str(option.id)):return "任务对话选项无效："+q.id
			if not _nonempty_text(option.get("label")) or not option.get("response") is String or str(option.get("kind","")) not in ["reply","accept","delivery","TALK_OPTION"]:return "任务对话选项无效："+q.id
			var nxt := str(option.get("next",""))
			if not nxt.is_empty() and nxt!="close" and nxt!="hub" and not nxt.begins_with("quest:") and not dialogue.nodes.has(nxt):return "任务对话去向无效："+q.id
			seen[str(node_id)+":"+str(option.id)]=true
			if option.kind=="accept":has_accept=true
			if option.kind=="delivery":has_delivery=true
			if option.kind=="TALK_OPTION":
				if not npcs.has(q.giver_npc_id) or str(option.get("event_option",""))!=str(q.objectives[0].completion_condition.get("option_id","")):return "任务对话选项无效："+q.id
	for value in ["AVAILABLE","ACTIVE","READY_TO_TURN_IN","COMPLETED"]:
		if not covered.has(value):return "任务对话缺少入口："+q.id
	if not has_accept or not has_delivery:return "任务对话缺少接取或交付："+q.id
	return ""

func _nonempty_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()
func validate_state(s: Dictionary,data: Dictionary) -> String:
	if s.has("tracked_quest_id") and (not s.tracked_quest_id is String or (not s.tracked_quest_id.is_empty() and not data.quests.has(s.tracked_quest_id))):return "追踪任务引用无效"
	if s.has("completed_events"):
		if not s.completed_events is Dictionary:return "探索完成记录格式无效"
		for id in s.completed_events:
			var record: Variant=s.completed_events[id]
			if not data.events.has(id) or not record is Dictionary or not _count(record.get("hours"),9223372036854775807):return "探索完成记录引用无效"
			var found:=false
			for option in data.events[id].options:
				if option.id==record.get("option",""):found=true
			if not found:return "探索完成选项引用无效"
	for id in s.quests:
		var q: Variant=s.quests[id]
		if not data.quests.has(id) or not q is Dictionary:return "任务状态引用无效"
		if not q.has("schema_version"):
			if q.get("status","") not in ["ACTIVE","COMPLETED"] or not _count(q.get("progress"),1):return "旧任务状态无效"
			continue
		if not _count(q.get("progress"),1):return "任务总进度无效"
		if not q.get("last_battle_id","") is String:return "任务战斗标识无效"
		if q.has("round") or q.has("completed_count") or q.has("last_completed_time") or q.has("next_available_time"):
			if not _count(q.get("round"),2147483647) or q.round<1 or not _count(q.get("completed_count"),int(q.round)):return "任务轮次无效"
			if not _count(q.get("next_available_time"),9223372036854775807) or not _count(q.get("last_completed_time"),int(q.next_available_time)):return "任务刷新时间无效"
		if q.has("accepted_day") and not _count(q.accepted_day,2147483647):return "任务接取日期无效"
		if q.has("reward_day") and not _count(q.reward_day,2147483647):return "任务领奖日期无效"
		if q.has("reward_claimed") and not q.reward_claimed is bool:return "任务领奖标记无效"
		if q.schema_version!=2 or q.get("quest_id")!=id or q.get("status","") not in preload("res://gameplay/quest/quest_system.gd").STATUSES or not q.get("objectives") is Dictionary:return "任务实例无效"
		var keys: Array[String]=[]
		for o in data.quests[id].objectives:
			keys.append(o.objective_id)
			var r: Variant=q.objectives.get(o.objective_id)
			if not r is Dictionary or r.get("status","") not in ["INACTIVE","ACTIVE","COMPLETED"] or not _count(r.get("current_count"),o.required_count):return "目标运行状态无效"
		if q.objectives.size()!=keys.size() or q.get("current_objective_id","") not in keys+[""]:return "任务阶段引用无效"
	return ""
func _count(value: Variant,maximum: int) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=0 and value<=maximum and floor(float(value))==value
