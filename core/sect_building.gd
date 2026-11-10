extends RefCounted
## Sect building functions. Cards keep their area ids; behavior comes from type, not from the building name.
const NpcDefinitions := preload("res://core/npc_definitions.gd")
const Interaction := preload("res://world/npc_interaction.gd")

const TYPES := {
	"NPC_INTERACT": "与负责人物交谈",
	"QUEST": "宗门任务尚未开放",
	"SHOP": "建筑交易尚未开放",
	"EXCHANGE": "贡献兑换尚未开放",
	"LIBRARY": "藏经查阅尚未开放",
	"CULTIVATION": "此地修炼尚未开放",
	"REST": "此地休息尚未开放",
	"SPAR": "切磋尚未开放",
	"EXAM": "考核尚未开放",
	"EVENT": "此处尚无可用事件",
	"EXPLORE": "此处尚无探索内容",
	"MANAGEMENT": "宗门管理尚未开放",
	"DEPART": "",
}
const IMPLEMENTED := ["NPC_INTERACT", "DEPART", "SHOP"]
const REQUIREMENT_KEYS := ["membership", "items", "quests", "min_hour"]
const LINK_KEYS := ["quests", "items", "resources", "shop"]

static func validate(tables: Dictionary) -> String:
	var roster := NpcDefinitions.roster(tables, tables.get("npc_overrides", {}))
	for sect_id in tables.get("sect_areas", {}):
		for area in tables.sect_areas[sect_id]:
			if not area is Dictionary:
				continue
			for card in area.get("cards", []):
				if not card is Dictionary:
					continue
				var error := _validate_card(str(sect_id), area, card, tables, roster)
				if not error.is_empty():
					return error
	return ""

static func inspect(state: Dictionary, data: Dictionary, sect: Dictionary, access_error: String, area_id: String, building_id: String) -> Dictionary:
	var found := _context(data, sect, access_error, area_id, building_id)
	if not found.ok:
		return found.result
	if found.concealed:
		return {"ok": true, "concealed": true, "sect_id": sect.id, "area_id": found.area.id, "area_name": found.area.name,
			"building_id": found.card.id, "name": "未知区域", "description": "发现线索后显示", "keepers": [], "actions": [],
			"message": "尚未发现此处。"}
	return {"ok": true, "concealed": false, "sect_id": sect.id, "area_id": found.area.id, "area_name": found.area.name,
		"building_id": found.card.id, "name": str(found.card.name), "description": str(found.card.description),
		"keepers": _keeper_rows(state, data, found.card), "actions": _actions(state, data, sect, found.area, found.card, access_error),
		"message": ""}

static func use(state: Dictionary, data: Dictionary, sect: Dictionary, access_error: String, area_id: String, building_id: String, action_id: String) -> Dictionary:
	var found := _context(data, sect, access_error, area_id, building_id)
	if not found.ok:
		return found.result
	if found.concealed:
		return _done(false, "denied", "尚未发现此处。", "")
	for action in _actions(state, data, sect, found.area, found.card, access_error):
		if str(action.id) == action_id:
			if action.status != "ready":
				return _done(false, action.status, action.message, "")
			var done := _done(true, "ready", action.message, action.action, action.npc_id, action.shop_id)
			done["quest_id"] = str(action.get("quest_id", ""))
			done["option_id"] = str(action.get("option_id", ""))
			done["confirm"] = str(action.get("confirm", "确认"))
			return done
	return _done(false, "invalid", "没有这项功能。", "")

static func _context(data: Dictionary, sect: Dictionary, access_error: String, area_id: String, building_id: String) -> Dictionary:
	if sect.is_empty() or not sect.get("id") is String:
		return {"ok": false, "result": _done(false, "invalid", access_error if not access_error.is_empty() else "这里没有宗门驻地。", "")}
	var areas: Array = data.get("sect_areas", {}).get(sect.id, [])
	var area := {}
	for entry in areas:
		if entry is Dictionary and str(entry.get("id", "")) == area_id:
			area = entry
			break
	if area.is_empty():
		return {"ok": false, "result": _done(false, "invalid", "没有这个区域。", "")}
	var card := {}
	for entry in area.get("cards", []):
		if entry is Dictionary and str(entry.get("id", "")) == building_id:
			card = entry
			break
	if card.is_empty():
		return {"ok": false, "result": _done(false, "invalid", "没有这座建筑。", "")}
	return {"ok": true, "concealed": str(card.get("entry", "")) == "undiscovered", "area": area, "card": card}

static func _actions(state: Dictionary, data: Dictionary, sect: Dictionary, area: Dictionary, card: Dictionary, access_error: String) -> Array:
	var rows := []
	var block := _block(state, sect, area, card, access_error)
	for function in card.get("functions", []):
		if not function is Dictionary:
			rows.append(_row("invalid", "", "未知功能", "invalid", "功能配置无效。", ""))
			continue
		var kind := str(function.get("type", ""))
		var function_id := str(function.get("id", "function"))
		var label := str(function.get("label", TYPES.get(kind, "未知功能")))
		if not TYPES.has(kind):
			rows.append(_row(function_id, kind, label, "invalid", "未知功能类型。", ""))
			continue
		if _qingyue_outer_arena(sect, area, card) and kind == "SPAR":
			rows.append(_spar_row(state, data, sect, area, card, function, block))
			continue
		if _qingyue_outer_arena(sect, area, card) and kind == "EXAM":
			rows.append(_exam_row(state, data, function, block))
			continue
		if kind not in IMPLEMENTED:
			rows.append(_row(function_id, kind, label, "closed", str(TYPES[kind]), ""))
		elif kind == "NPC_INTERACT":
			rows.append_array(_npc_rows(state, data, sect, area, card, function, block))
		elif kind == "SHOP":
			rows.append(_shop_row(state, data, sect, function, block))
		elif kind == "DEPART":
			rows.append(_command_row(state, data, sect, function, "map", block))
		else:
			rows.append(_row(function_id, kind, label, "closed", str(TYPES[kind]), ""))
	if str(card.get("id", "")) == "gate":
		for action in preload("res://gameplay/quest/quest_system.gd").new().location_actions(state, data):
			var row := _row("patrol_" + str(action.option_id), "EVENT", str(action.label), "ready", str(action.prompt), "quest_location")
			row["quest_id"] = str(action.quest_id)
			row["option_id"] = str(action.option_id)
			row["confirm"] = str(action.confirm)
			rows.append(row)
	return rows

static func _npc_rows(state: Dictionary, data: Dictionary, sect: Dictionary, area: Dictionary, card: Dictionary, function: Dictionary, block: String) -> Array:
	var function_id := str(function.get("id", "talk"))
	var targets: Array = card.get("keepers", [])
	if function.get("npc") is String and not function.npc.is_empty():
		targets = [function.npc]
	if not targets is Array or targets.is_empty():
		var empty_status := "denied"
		var empty_message := block if not block.is_empty() else "此处没有可交谈的执事。"
		return [_row(function_id, "NPC_INTERACT", str(function.get("label", "交谈")), empty_status, empty_message, "")]
	var rows := []
	for npc_id in targets:
		var action_id := "%s:%s" % [function_id, str(npc_id)]
		var name := _npc_name(state, data, str(npc_id))
		var label := "与%s交谈" % name if not name.is_empty() else "交谈"
		if not _npc_id(npc_id):
			rows.append(_row(action_id, "NPC_INTERACT", label, "invalid", "人物配置无效。", ""))
			continue
		var npc: Dictionary = state.get("npcs", {}).get(npc_id, {})
		if npc.is_empty():
			rows.append(_row(action_id, "NPC_INTERACT", label, "invalid", "没有此人物的信息。", "", str(npc_id)))
			continue
		if not block.is_empty():
			rows.append(_row(action_id, "NPC_INTERACT", label, "denied", block, "", str(npc_id)))
			continue
		if str(npc.get("sect", "")) != str(sect.id) or str(npc.get("sect_area", "")) != str(area.id) or str(npc.get("sect_building", "")) != str(card.id) or str(npc.get("location", "")) != str(state.player.location):
			rows.append(_row(action_id, "NPC_INTERACT", label, "denied", "对方不在此处，无法交谈。", "", str(npc_id)))
			continue
		var verdict: Dictionary = Interaction.new().evaluate(state, data, str(npc_id), "交谈")
		if verdict.get("kind", "") != "talk":
			var verdict_message := str(verdict.get("message", "对方目前无法交谈。"))
			var verdict_status := "invalid" if verdict_message.contains("没有此人物") else "denied"
			rows.append(_row(action_id, "NPC_INTERACT", label, verdict_status, verdict_message, "", str(npc_id)))
			continue
		var requirement := _requirement_error(state, data, function, sect)
		if not requirement.is_empty():
			rows.append(_row(action_id, "NPC_INTERACT", label, requirement.status, requirement.message, "", str(npc_id)))
			continue
		rows.append(_row(action_id, "NPC_INTERACT", label, "ready", "", "npc", str(npc_id)))
	return rows

static func _shop_row(state: Dictionary, data: Dictionary, sect: Dictionary, function: Dictionary, block: String) -> Dictionary:
	var function_id := str(function.get("id", "shop"))
	var label := str(function.get("label", "交易"))
	var shop_id := str(_links(function).get("shop", ""))
	if shop_id.is_empty() or not data.get("shops", {}).has(shop_id):
		return _row(function_id, "SHOP", label, "invalid", "未配置有效店铺。", "")
	if not block.is_empty():
		return _row(function_id, "SHOP", label, "denied", block, "", "", shop_id)
	var requirement := _requirement_error(state, data, function, sect)
	if not requirement.is_empty():
		return _row(function_id, "SHOP", label, requirement.status, requirement.message, "", "", shop_id)
	var shop: Dictionary = data.shops[shop_id]
	var npc: Dictionary = state.get("npcs", {}).get(shop.get("npc_id", ""), {})
	if npc.is_empty() or not npc.get("alive", false) or str(npc.get("location", "")) != str(shop.get("location", "")) or str(state.player.location) != str(shop.get("location", "")):
		return _row(function_id, "SHOP", label, "denied", "商人不在此处或已死亡。", "", "", shop_id)
	return _row(function_id, "SHOP", label, "ready", "", "shop", "", shop_id)

static func _command_row(state: Dictionary, data: Dictionary, sect: Dictionary, function: Dictionary, action_name: String, block: String) -> Dictionary:
	var function_id := str(function.get("id", action_name))
	var label := str(function.get("label", "返回"))
	var kind := str(function.get("type", ""))
	if not block.is_empty():
		return _row(function_id, kind, label, "denied", block, "")
	var requirement := _requirement_error(state, data, function, sect)
	if not requirement.is_empty():
		return _row(function_id, kind, label, requirement.status, requirement.message, "")
	return _row(function_id, kind, label, "ready", "", action_name)

static func _block(state: Dictionary, sect: Dictionary, area: Dictionary, card: Dictionary, access_error: String) -> String:
	if not access_error.is_empty():
		return access_error
	if not state.get("player") is Dictionary:
		return "请先创建角色。"
	if not str(area.get("restriction", "")).is_empty() and not preload("res://gameplay/sect/sect_arena.gd").area_open(state, str(sect.get("id", "")), str(area.get("id", "")), str(area.get("restriction", ""))):
		return str(area.restriction)
	var status := str(card.get("status", "available"))
	if status not in ["", "available"]:
		return "此建筑暂未开放。" if status == "unavailable" else "建筑状态配置无效。"
	var membership := ""
	if card.get("access") is Dictionary:
		membership = str(card.access.get("membership", ""))
	if membership == "member" and str(state.get("sect", "")) != str(sect.get("id", "")):
		return "需先加入本宗。"
	if membership not in ["", "member"]:
		return "建筑权限配置无效。"
	return ""

static func _requirement_error(state: Dictionary, data: Dictionary, function: Dictionary, sect: Dictionary) -> Dictionary:
	if not function.has("requirements"):
		return {}
	var requirements: Variant = function.requirements
	if not requirements is Dictionary:
		return {"status": "invalid", "message": "功能条件配置无效。"}
	for key in requirements:
		if str(key) not in REQUIREMENT_KEYS:
			return {"status": "invalid", "message": "功能条件配置无效。"}
	var membership := str(requirements.get("membership", ""))
	if membership not in ["", "member"]:
		return {"status": "invalid", "message": "功能条件配置无效。"}
	if membership == "member" and str(state.get("sect", "")) != str(sect.get("id", "")):
		return {"status": "denied", "message": "需先加入本宗。"}
	var items: Variant = requirements.get("items", {})
	if not items is Dictionary:
		return {"status": "invalid", "message": "功能条件配置无效。"}
	for item_id in items:
		if not data.get("items", {}).has(item_id) or not _positive(items[item_id]):
			return {"status": "invalid", "message": "功能所需物品不存在。"}
		if int(state.get("player", {}).get("inventory", {}).get(item_id, 0)) < int(items[item_id]):
			return {"status": "denied", "message": "所需物品不足。"}
	var quests: Variant = requirements.get("quests", [])
	if not quests is Array:
		return {"status": "invalid", "message": "功能条件配置无效。"}
	for quest_id in quests:
		if not quest_id is String or not data.get("quests", {}).has(quest_id):
			return {"status": "invalid", "message": "功能相关事务不存在。"}
		if str(state.get("quests", {}).get(quest_id, {}).get("status", "")) not in ["ACTIVE", "COMPLETED"]:
			return {"status": "denied", "message": "相关事务尚未达成。"}
	if requirements.has("min_hour"):
		if not _whole(requirements.min_hour):
			return {"status": "invalid", "message": "功能条件配置无效。"}
		if int(state.get("hours", 0)) < int(requirements.min_hour):
			return {"status": "denied", "message": "时间尚未满足。"}
	return {}

static func _qingyue_outer_arena(sect: Dictionary, area: Dictionary, card: Dictionary) -> bool:
	return str(sect.get("id", "")) == "sect_qingyue" and str(area.get("id", "")) == "outer" and str(card.get("id", "")) == "arena"

static func _spar_row(state: Dictionary, data: Dictionary, sect: Dictionary, area: Dictionary, card: Dictionary, function: Dictionary, block: String) -> Dictionary:
	var function_id := str(function.get("id", "spar"))
	var label := str(function.get("label", "同门切磋"))
	if not block.is_empty():
		return _row(function_id, "SPAR", label, "denied", block, "")
	var keeper := "npc_han_tieshan"
	if str(state.get("sect", "")) != "sect_qingyue" or preload("res://gameplay/sect/sect_arena.gd").rank(state) not in ["outer", "inner"]:
		return _row(function_id, "SPAR", label, "denied", "需先加入青岳宗。", "", keeper)
	var presence := _npc_rows(state, data, sect, area, card, {"id": function_id, "label": label, "npc": keeper}, "")
	if presence.is_empty() or str(presence[0].get("status", "")) != "ready":
		var reason := str(presence[0].get("message", "演武教习不在此处。")) if not presence.is_empty() else "演武教习不在此处。"
		return _row(function_id, "SPAR", label, "denied", reason, "", keeper)
	return _row(function_id, "SPAR", label, "ready", "", "npc", keeper)

static func _exam_row(state: Dictionary, data: Dictionary, function: Dictionary, block: String) -> Dictionary:
	var function_id := str(function.get("id", "exam"))
	var label := str(function.get("label", "晋升考核"))
	if not block.is_empty():
		return _row(function_id, "EXAM", label, "denied", block, "")
	var arena := preload("res://gameplay/sect/sect_arena.gd")
	var npc: Dictionary = state.get("npcs", {}).get(arena.MENG, {})
	if npc.is_empty() or npc.get("alive", false) != true or str(npc.get("location", "")) != str(state.get("player", {}).get("location", "")) or str(npc.get("sect_area", "")) != "outer" or str(npc.get("sect_building", "")) != "arena":
		return _row(function_id, "EXAM", label, "denied", "考核对手不在演武场。", "", arena.MENG)
	if str(state.get("sect", "")) != arena.SECT or arena.rank(state) not in ["outer", "inner"]:
		return _row(function_id, "EXAM", label, "denied", "只有青岳宗弟子可以参加此项考核。", "", arena.MENG)
	var promo: Dictionary = state.get("sect_promotion", {})
	if arena.rank(state) == "inner" or promo.get("completed", false) == true:
		return _row(function_id, "EXAM", label, "denied", "你已是内门弟子，无须再参加此项考核。", "", arena.MENG)
	if promo.get("pending_report", false) == true:
		return _row(function_id, "EXAM", label, "denied", "考核已通过，去向周长老复命吧。", "", arena.MENG)
	if int(promo.get("cooldown_until_day", -1)) >= 0 and arena.game_day(state, data) < int(promo.cooldown_until_day):
		var left := int(promo.cooldown_until_day) - arena.game_day(state, data)
		return _row(function_id, "EXAM", label, "denied", "此次未能通过，三日后可以重新报名。\n冷却剩余：%d 个游戏日。" % left, "", arena.MENG)
	if promo.get("enrolled", false) != true:
		return _row(function_id, "EXAM", label, "denied", "请先到事务殿向周玄报名。", "", arena.MENG)
	return _row(function_id, "EXAM", label, "ready", "", "sect_exam", arena.MENG)

static func _keeper_rows(state: Dictionary, data: Dictionary, card: Dictionary) -> Array:
	var rows := []
	for npc_id in card.get("keepers", []):
		var name := _npc_name(state, data, str(npc_id))
		rows.append({"id": str(npc_id), "name": name if not name.is_empty() else "未知人物"})
	return rows

static func _npc_name(state: Dictionary, data: Dictionary, npc_id: String) -> String:
	var npc: Dictionary = state.get("npcs", {}).get(npc_id, {})
	if not str(npc.get("name", "")).is_empty():
		return str(npc.name)
	var defined: Dictionary = NpcDefinitions.roster(data, data.get("npc_overrides", {})).get(npc_id, {})
	return str(defined.get("name", ""))

static func _validate_card(sect_id: String, area: Dictionary, card: Dictionary, tables: Dictionary, roster: Dictionary) -> String:
	var where := "%s / %s / %s" % [sect_id, area.get("id", ""), card.get("id", "")]
	if card.has("status") and str(card.status) not in ["available", "unavailable"]:
		return "建筑状态无效：" + where
	if card.has("keepers"):
		if not card.keepers is Array:
			return "负责人物配置无效：" + where
		var seen_keeper := {}
		for npc_id in card.keepers:
			if not _npc_id(npc_id) or not roster.has(npc_id) or seen_keeper.has(npc_id):
				return "负责人物无效：" + where
			seen_keeper[npc_id] = true
	if card.has("access"):
		if not card.access is Dictionary or str(card.access.get("membership", "")) not in ["", "member"]:
			return "建筑权限配置无效：" + where
	if not card.has("functions"):
		return ""
	if not card.functions is Array:
		return "建筑功能配置无效：" + where
	var seen_function := {}
	for function in card.functions:
		if not function is Dictionary or not _key(function.get("id")) or seen_function.has(function.id):
			return "建筑功能编号无效：" + where
		seen_function[function.id] = true
		if not TYPES.has(str(function.get("type", ""))):
			return "未知建筑功能：" + where
		if not function.get("label") is String or function.label.strip_edges().is_empty():
			return "建筑功能名称无效：" + where
		if function.has("system") and not function.system is String:
			return "建筑功能系统无效：" + where
		if function.has("npc") and (not _npc_id(function.npc) or not roster.has(function.npc)):
			return "建筑功能人物无效：" + where
		var link_error := _validate_links(function, tables)
		if not link_error.is_empty():
			return link_error + where
		var requirement_error := _validate_requirements(function, tables)
		if not requirement_error.is_empty():
			return requirement_error + where
		if str(function.type) == "SHOP" and str(_links(function).get("shop", "")).is_empty():
			return "交易功能未配置店铺：" + where
	return ""

static func _validate_links(function: Dictionary, tables: Dictionary) -> String:
	if not function.has("links"):
		return ""
	if not function.links is Dictionary:
		return "功能关联配置无效："
	for key in function.links:
		if str(key) not in LINK_KEYS:
			return "功能关联配置无效："
	if not function.links.get("quests", []) is Array or not function.links.get("items", []) is Array or not function.links.get("resources", []) is Array:
		return "功能关联配置无效："
	for quest_id in function.links.get("quests", []):
		if not quest_id is String or not tables.quests.has(quest_id):
			return "功能关联事务无效："
	for item_id in function.links.get("items", []):
		if not item_id is String or not tables.items.has(item_id):
			return "功能关联物品无效："
	for resource_id in function.links.get("resources", []):
		if not resource_id is String or resource_id.strip_edges().is_empty():
			return "功能关联资源无效："
	var shop_id: Variant = function.links.get("shop", "")
	if not shop_id is String or (not shop_id.is_empty() and not tables.shops.has(shop_id)):
		return "功能关联店铺无效："
	return ""

static func _validate_requirements(function: Dictionary, tables: Dictionary) -> String:
	if not function.has("requirements"):
		return ""
	if not function.requirements is Dictionary:
		return "功能条件配置无效："
	for key in function.requirements:
		if str(key) not in REQUIREMENT_KEYS:
			return "功能条件配置无效："
	if str(function.requirements.get("membership", "")) not in ["", "member"]:
		return "功能条件配置无效："
	var items: Variant = function.requirements.get("items", {})
	if not items is Dictionary:
		return "功能条件配置无效："
	for item_id in items:
		if not tables.items.has(item_id) or not _positive(items[item_id]):
			return "功能所需物品无效："
	var quests: Variant = function.requirements.get("quests", [])
	if not quests is Array:
		return "功能条件配置无效："
	for quest_id in quests:
		if not quest_id is String or not tables.quests.has(quest_id):
			return "功能相关事务无效："
	if function.requirements.has("min_hour") and not _whole(function.requirements.min_hour):
		return "功能条件配置无效："
	return ""

static func _links(function: Dictionary) -> Dictionary:
	return function.get("links", {}) if function.get("links", {}) is Dictionary else {}

static func _row(id: String, type: String, label: String, status: String, message: String, action: String, npc_id: String = "", shop_id: String = "") -> Dictionary:
	return {"id": id, "type": type, "label": label, "status": status, "message": message,
		"action": action if status == "ready" else "", "npc_id": npc_id, "shop_id": shop_id}

static func _done(ok: bool, status: String, message: String, action: String, npc_id: String = "", shop_id: String = "") -> Dictionary:
	return {"ok": ok, "status": status, "message": message, "action": action, "npc_id": npc_id,
		"shop_id": shop_id, "changes_state": false}

static func _npc_id(value: Variant) -> bool:
	return value is String and value.begins_with("npc_") and value.is_valid_identifier()

static func _key(value: Variant) -> bool:
	return value is String and value.is_valid_identifier() and value == value.to_lower()

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and float(value) == floor(float(value))

static func _positive(value: Variant) -> bool:
	return _whole(value) and float(value) >= 1
