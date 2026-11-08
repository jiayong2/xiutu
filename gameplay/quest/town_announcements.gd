extends RefCounted

const QUESTS = preload("res://gameplay/quest/quest_system.gd")
const CLOCK = preload("res://core/time_system.gd")
const TOWNS := ["town_qinglan", "town_yunxi"]
const CATEGORIES := {
	"bounty": "悬赏委托", "purchase": "采集收购", "recruitment": "宗门招募",
	"commerce": "商会消息", "rumor": "城镇传闻", "notice": "官府告示", "event": "特殊事件"
}

static func validate(data: Dictionary) -> String:
	var npcs := {}
	for npc in data.prototype.npcs:
		npcs[npc.id] = true
	var linked_quests := {}
	for row in data.announcements.values():
		var id: String = row.id
		if id.is_empty() or row.get("town_id") not in TOWNS or not CATEGORIES.has(row.get("category")):
			return "榜文城镇或分类无效：" + id
		for field in ["quest_id", "publisher_id", "location_id", "title", "description"]:
			if not row.get(field, "") is String:
				return "榜文字段类型无效：" + id + "/" + field
		for field in ["created_at", "expires_at"]:
			if not row.has(field):
				continue
			var hour: Variant = row[field]
			if not (hour is int or hour is float) or not is_finite(float(hour)) or hour < 0 or floor(float(hour)) != hour:
				return "榜文时间无效：" + id + "/" + field
		if row.has("expires_at") and row.expires_at <= row.get("created_at", 0):
			return "榜文期限早于或等于发布时间：" + id
		var location: String = row.get("location_id", "")
		if not location.is_empty() and location not in preload("res://gameplay/quest/quest_validation.gd").PLACES:
			return "榜文地点无效：" + id
		var publisher: String = row.get("publisher_id", "")
		if not publisher.is_empty() and not npcs.has(publisher):
			return "榜文发布者无效：" + id
		var quest_id: String = row.get("quest_id", "")
		if quest_id.is_empty():
			if row.get("title", "").strip_edges().is_empty() or row.get("description", "").strip_edges().is_empty():
				return "普通榜文缺少标题或正文：" + id
		elif row.category in ["rumor", "notice"]:
			return "传闻及普通告示仅供查看：" + id
		elif not data.quests.has(quest_id) or linked_quests.has(quest_id):
			return "榜文任务引用无效或重复：" + id
		else:
			linked_quests[quest_id] = true
			var quest: Dictionary = data.quests[quest_id]
			if quest.completion_mode == "BOARD":
				for objective in quest.objectives:
					if objective.objective_type == "ITEM_DELIVERY" and objective.target_location_id != row.town_id:
						return "材料交付地点须与榜文城镇一致：" + quest_id
	var quests := QUESTS.new()
	for quest in data.quests.values():
		if quests.board_only(quest) and not linked_quests.has(quest.id):
			return "公告栏专属委托缺少榜文：" + quest.id
	return ""

static func is_published(row: Dictionary, state: Dictionary) -> bool:
	return CLOCK.new().seconds(state) >= int(row.get("created_at", 0)) * 3600

static func status(row: Dictionary, state: Dictionary, data: Dictionary, quests: RefCounted) -> String:
	var quest_id: String = row.get("quest_id", "")
	var value: String = "READ_ONLY" if quest_id.is_empty() else quests.status(state, quest_id, data)
	if value == "COMPLETED" and data.quests[quest_id].get("repeatable",false):
		if not quests.repeat_available(state,quest_id,data):
			return "COOLDOWN"
		value = "AVAILABLE" if quests.requirement_error(state,quest_id,data).is_empty() else "LOCKED"
	# An expired posting closes recruitment. The quest system still owns accepted work.
	if value in ["ACTIVE", "READY_TO_TURN_IN", "COMPLETED", "EXPIRED"]:
		return value
	if row.has("expires_at") and CLOCK.new().seconds(state) >= int(row.expires_at) * 3600:
		return "EXPIRED"
	if value == "FAILED":
		return "AVAILABLE" if quests.requirement_error(state, quest_id, data).is_empty() else "LOCKED"
	return value

static func accept(id: String, state: Dictionary, data: Dictionary, quests: RefCounted) -> String:
	var row: Dictionary = data.announcements.get(id, {})
	if row.is_empty() or row.town_id != state.player.location or not is_published(row, state):
		return "当前城镇没有这条榜文"
	var value := status(row, state, data, quests)
	match value:
		"AVAILABLE":
			return quests.accept(state, row.quest_id, data, true)
		"LOCKED":
			return quests.requirement_error(state, row.quest_id, data)
		"EXPIRED":
			return "榜文已过期"
		"READ_ONLY":
			return "此榜文仅供查看"
		"COOLDOWN":
			return "委托尚在刷新冷却中"
	return "委托已接取或完成"

static func claim(id: String, round_number: int, state: Dictionary, data: Dictionary, quests: RefCounted, inventory: RefCounted) -> String:
	var row: Dictionary = data.announcements.get(id,{})
	if row.is_empty() or row.town_id != state.player.location:
		return "请返回发布委托的公告栏"
	var quest_id: String = row.get("quest_id","")
	var quest: Dictionary = data.quests.get(quest_id,{})
	if quest.get("completion_mode") != "BOARD":
		return "此委托须通过原交付方式完成"
	var runtime: Dictionary = state.quests.get(quest_id,{})
	if runtime.get("round",0) != round_number:
		return "委托轮次已变化，请刷新公告栏"
	return quests.claim(state,quest_id,data,inventory,"",true)
