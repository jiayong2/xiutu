extends RefCounted
## Owns runtime state. Commands run on an isolated candidate and commit once.
signal changed
const DEBUG_PLAYER_STATS := {"hp":"生命","mp":"灵力","attack":"攻击","defense":"防御","speed":"速度"}
const DEBUG_PLAYER_VALUE_MAX := 2147483647
signal time_changed(interval: Dictionary)
const Character = preload("res://gameplay/character/character_system.gd")
const Fortunes = preload("res://gameplay/character/player_fortunes.gd")
const Inventory = preload("res://gameplay/inventory/inventory_system.gd")
const Quests = preload("res://gameplay/quest/quest_system.gd")
const Shop = preload("res://gameplay/shop/shop_system.gd")
const Battle = preload("res://gameplay/battle/battle_system.gd")
const Spells = preload("res://gameplay/battle/spell_progression.gd")
const Auction = preload("res://gameplay/auction/auction_system.gd")
const AuctionValidation = preload("res://gameplay/auction/auction_validation.gd")
const Mental = preload("res://gameplay/character/mental_attributes.gd")
const Cultivation = preload("res://gameplay/cultivation/cultivation_system.gd")
const Cave = preload("res://gameplay/cave/cave_system.gd")
const Clock = preload("res://core/time_system.gd")
const Random = preload("res://core/random_service.gd")
const BASE_LOCATIONS = ["town_qinglan","town_yunxi","cave_qinglan","area_qinglan_outskirts"]
var character := Character.new()
var inventory := Inventory.new()
var quests := Quests.new()
var shop := Shop.new()
var battle := Battle.new()
var auction := Auction.new()
var cultivation := Cultivation.new()
var cave := Cave.new()
var clock := Clock.new()
var random := Random.new()
var events := preload("res://core/event_bus.gd").new()
const NpcDefinitions := preload("res://core/npc_definitions.gd")

var data: Dictionary
var _state: Dictionary = {}
var _sequence := 0
var _busy := false

func configure(tables: Dictionary) -> void:
	data = tables.duplicate(true)
	for connection in events.domain_event.get_connections():
		events.domain_event.disconnect(connection.callable)
	events.domain_event.connect(quests.notify.bind(data))

func new_game(name: String, root: String, base: Dictionary, seed_value: int = 1, innate: String = "", randomize_npcs: bool = false) -> String:
	if name.strip_edges().is_empty() or name.length() > 24 or root not in data.rules.roots:
		return "姓名需为1至24字，灵根必须有效"
	if not Fortunes.valid_selection(innate):
		return "先天天赋无效"
	random.initialize(seed_value)
	var identity := Crypto.new().generate_random_bytes(16).hex_encode()
	_state = {"version":1,"player":character.initialize(base,data.rules,name,root,identity),"hours":int(data.rules.start_hour),"initial_age":base.age,"time_seconds":0,"cultivation_fraction":0,"quests":{},"tracked_quest_id":"","completed_events":{},"plots":[{},{},{},{}],"stocks":{},"npcs":{},"prices":{},"battle":{},"pending_battle_result":"","first_wolf":false,"leader_reward":false,"mvp1":false,"formation":false,"cave_level":1,"warehouse":{},"sect":"","contribution":0,"news":[],"operations":{},"last_result":""}
	_state.player.growth = cultivation.initialize_growth(data)
	Spells.grant_trials(_state.player,data.spells)
	_state.player.traits = character.initialize_traits(data)
	_state.player.blood = int(data.progression.character_foundation.initial_blood)
	if not innate.is_empty():
		var base_stats := stats()
		Fortunes.grant(_state.player,innate,clock.seconds(_state),"角色创建")
		var starting_stats := stats()
		_state.player.hp += starting_stats.hp - base_stats.hp
		_state.player.mp += starting_stats.mp - base_stats.mp
		_state.player.blood += starting_stats.blood - base_stats.blood
	clock.spirit.initialize(_state,data)
	for definition in data.shops.values():
		_state.stocks[definition.id] = definition.stock.duplicate(true)
	var authored: Dictionary = data.get("npc_overrides", {})
	var npc_seed := identity if randomize_npcs else str(seed_value)
	for definition in NpcDefinitions.roster(data, authored).values():
		var npc: Dictionary = NpcDefinitions.initial(definition, data) if authored.has(definition.id) else _initial_npc(definition)
		if not authored.has(definition.id):
			NpcDefinitions.complete_prototype(npc,definition.get("profile", {}),data,npc_seed)
		_state.npcs[definition.id] = npc
	_sequence = 0
	_state = _normalize(_state)
	changed.emit()
	return ""

# Profile details are authored catalog data, separate from saved simulation state.
func _initial_npc(definition: Dictionary, elapsed_years: int = 0) -> Dictionary:
	var npc: Dictionary = definition.duplicate(true)
	npc.erase("profile")
	npc.erase("greeting")
	var profile: Dictionary = definition.get("profile", {})
	if profile.has("loadout"):
		npc.loadout = profile.loadout.duplicate(true)
	var age := int(data.prototype.npc_initial_age) + elapsed_years
	npc.merge({"age":age,"alive":age < preload("res://world/world_simulator.gd").npc_lifespan(npc,data),"cultivation":0,"wealth":data.prototype.npc_initial_wealth,"relations":{}})
	Mental.initialize_npc(npc,data.progression.mental)
	return _normalize(npc)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func trade_quote(shop_id: String, item: String, buying: bool, quantity: int = 1, instance: String = "") -> Dictionary:
	if _state.is_empty() or not data.shops.has(shop_id) or not data.items.has(item):
		return {"unit":0,"total":0,"maximum":0,"reason":"商品或商店不存在","confirmation":false}
	var action := "buy" if buying else "sell_equipment" if not instance.is_empty() else "sell"
	var args := {"shop":shop_id,"item":item,"quantity":quantity,"id":instance,"confirmed":true}
	var reason := _trade_quote_error(action,args)
	var unit: int = shop.unit_price(_state,data,shop_id,item,buying)
	var low := 0
	var high := 1 if not instance.is_empty() else 99
	while low < high:
		var middle: int = int((low + high + 1)/2)
		args.quantity = middle
		if _trade_quote_error(action,args).is_empty(): low = middle
		else: high = middle - 1
	return {"unit":unit,"total":unit*quantity,"maximum":low,"reason":reason,
		"confirmation":not buying and item=="material_wolf_fang"}

func _trade_quote_error(action: String, args: Dictionary) -> String:
	var error := _request_state_error(action)
	if not error.is_empty():
		return error
	error = _battle_action_error(_state,action)
	if not error.is_empty():
		return error
	if action == "sell_equipment":
		return _equipment_sale_error(_state,args.id,args.shop)
	return shop.trade_error(_state,data,args,action == "buy")

func stats() -> Dictionary:
	return character.stats(_state.player,data) if not _state.is_empty() else {}

## Updates an existing NPC's assigned gear and techniques as one validated change.
func set_npc_loadout(id: String, loadout: Dictionary) -> bool:
	if _busy or not _state.get("npcs", {}).has(id):
		return false
	var npc: Dictionary = _state.npcs[id]
	if not npc.has("loadout") or not npc.alive or not Character.valid_npc_loadout(loadout, data):
		return false
	npc.loadout = _normalize(loadout)
	changed.emit()
	return true

func export_save() -> Dictionary:
	return {"version":1,"state":snapshot(),"random":random.snapshot(),"sequence":_sequence}

func restore_save(payload: Dictionary) -> String:
	var error := validate_save(payload)
	if not error.is_empty():
		return error
	_state = _normalize(payload.state)
	for definition in data.shops.values():
		if not _state.stocks.has(definition.id):
			_state.stocks[definition.id] = definition.stock.duplicate(true)
	for definition in data.prototype.npcs:
		if not _state.npcs.has(definition.id):
			var elapsed_years := int(clock.seconds(_state) / (int(data.rules.days_year) * int(data.rules.hours_day) * 3600))
			_state.npcs[definition.id] = _initial_npc(definition, elapsed_years)
		var npc: Dictionary = _state.npcs[definition.id]
		var profile: Dictionary = npc.get("profile",definition.get("profile", {}))
		if npc.get("authored", false):
			continue
		if definition.get("identity_from_catalog", false):
			npc.name = definition.name
			npc.role = definition.role
		if definition.realm == 0:
			npc.realm = 0
			npc.cultivation = 0
		elif npc.realm == 0:
			npc.realm = int(definition.realm)
		if profile.has("loadout") and not npc.has("loadout"):
			npc.loadout = profile.loadout.duplicate(true)
		NpcDefinitions.complete_prototype(npc,profile,data,str(payload.random.world))
	Spells.grant_trials(_state.player,data.spells)
	if not _state.player.has("growth"):
		_state.player.growth = cultivation.initialize_growth(data)
	Mental.initialize_player(_state.player,data.progression.mental)
	for npc in _state.npcs.values():
		Mental.initialize_npc(npc,data.progression.mental)
		if npc.get("authored", false):
			NpcDefinitions.fill_vitals(npc,npc.profile,data)
	if not _state.player.has("traits"):
		_state.player.traits = character.initialize_traits(data)
	if not _state.player.has("blood"):
		_state.player.blood = int(data.progression.character_foundation.initial_blood)
	clock.spirit.initialize(_state,data)
	# Legacy pause preferences no longer control or stop the clock.
	_state.erase("time_paused");_state.erase("idle_pause_enabled")
	quests.migrate(_state,data)
	random.initialize(1)
	random.restore(payload.random)
	_sequence = int(payload.sequence)
	changed.emit()
	return ""

func validate_save(payload: Dictionary) -> String:
	if payload.get("version") != 1 or not payload.get("state") is Dictionary or not payload.get("random") is Dictionary:
		return "存档版本或结构无效"
	var s: Dictionary = payload.state
	for time_key in ["time_seconds","cultivation_fraction"]:
		if not _nonnegative(s.get(time_key,0)):return "时间余数无效"
	if s.has("retreat_report"):
		var report_value: Variant=s.retreat_report
		if not report_value is Dictionary or not report_value.get("groups") is Dictionary:return "闭关报告结构无效"
		for group in ["cultivation","npc","sect","economy","world","quest"]:
			if not report_value.groups.get(group) is Array:return "闭关报告分类无效"
			for line in report_value.groups[group]:
				if not line is String:return "闭关报告记录无效"
		for key in ["start","end","requested","elapsed","gain","after","age","realm"]:
			if not _nonnegative(report_value.get(key)):return "闭关报告数值无效"
		if not report_value.get("reason") is String or not report_value.get("id") is String or not report_value.get("interrupted") is bool:return "闭关报告标记无效"
		if report_value.get("route","qi") not in ["qi","body"]:return "闭关报告修炼路线无效"
		if report_value.has("spirit_ledger"):
			var ledger: Variant=report_value.spirit_ledger
			if not ledger is Dictionary:return "闭关灵气账本结构无效"
			for key in ["processed","loss","cultivation","nurture","returned"]:
				if not _nonnegative(ledger.get(key)):return "闭关灵气账本数值无效"
			if ledger.processed!=ledger.loss+ledger.cultivation+ledger.nurture+ledger.returned:
				return "闭关灵气账本不平衡"
	if s.get("time_seconds",0)>=3600 or s.get("cultivation_fraction",0)>=int(data.rules.hours_day)*3600*10000:return "时间余数超限"
	for time_key in ["time_paused","idle_pause_enabled"]:
		if s.has(time_key) and not s[time_key] is bool:return "时间开关无效"
	for key in ["player","stocks","npcs","quests","operations","warehouse","battle","prices"]:
		if not s.get(key) is Dictionary:
			return "存档缺少对象：" + key
	for key in ["hours","initial_age","cave_level"]:
		if not _nonnegative(s.get(key)):
			return "存档数值非法：" + key
	if not s.get("plots") is Array or s.plots.size() != 4 or not s.get("news") is Array:
		return "灵田或新闻结构无效"
	for key in ["first_wolf","leader_reward","mvp1","formation"]:
		if not s.get(key) is bool:
			return "存档布尔字段无效：" + key
	for key in ["pending_battle_result","last_result","sect"]:
		if not s.get(key) is String:
			return "存档文本字段无效：" + key
	if not _nonnegative(s.get("contribution")) or s.cave_level not in [1,2,1.0,2.0]:
		return "洞府等级或贡献无效"
	for plot in s.plots:
		if not plot is Dictionary:
			return "灵田无效"
		if not plot.is_empty():
			if not data.herbs.has(plot.get("herb","")) or not _nonnegative(plot.get("planted_at")) or not _nonnegative(plot.get("ready_at")) or plot.ready_at < plot.planted_at:
				return "灵田内容无效"
	for id in data.shops:
		if data.shops[id].get("seed_on_restore", false) and not s.stocks.has(id):
			continue
		if not s.stocks.get(id) is Dictionary:
			return "商店库存缺失"
		for item in s.stocks[id]:
			if not data.items.has(item) or not _nonnegative(s.stocks[id][item]):
				return "库存引用或数量无效"
	for definition in data.prototype.npcs:
		# NPCs introduced after the original roster are seeded during restore.
		if not s.npcs.has(definition.id) and (definition.get("seed_on_restore", false) or definition.id in ["npc_lin_zhaoxi", "npc_shen_yunzhao"]):
			continue
		var npc: Variant = s.npcs.get(definition.id)
		if not npc is Dictionary or not npc.get("alive") is bool or not npc.get("location") is String:
			return "人物状态无效"
		if npc.has("loadout") and not Character.valid_npc_loadout(npc.loadout, data):
			return "人物装配无效"
		for key in ["age","cultivation","wealth"]:
			if not _nonnegative(npc.get(key)):
				return "人物数值无效"
		var realm_validation := NpcDefinitions.realm_error(npc)
		if not realm_validation.is_empty():
			return realm_validation
		if not npc.get("authored", false) and not Fortunes.valid_state(npc,clock.seconds(s),false,Fortunes.DEFINITIONS.size()):
			return "人物气运状态无效"
	var known_people := _npc_relationship_targets(s)
	for id in s.npcs:
		var npc: Variant = s.npcs[id]
		if npc is Dictionary:
			for key in ["hp","mp","blood"]:
				if npc.has(key) and not _nonnegative(npc[key]):
					return "人物资源无效"
		if npc is Dictionary and npc.get("authored", false):
			if npc.get("id") != id or not npc.get("alive") is bool or not _nonnegative(npc.get("wealth")):
				return "人物存档状态无效"
			var npc_error := NpcDefinitions.validate(npc, data, known_people, false)
			if not npc_error.is_empty():
				return npc_error
			if not npc.get("fortunes") is Dictionary or not npc.get("attributes") is Dictionary:
				return "人物运行属性无效"
			for fortune_id in npc.fortunes:
				if fortune_id not in npc.fortune_ids:
					return "人物气运引用无效"
	var auction_error := AuctionValidation.state(s,data)
	if not auction_error.is_empty():
		return auction_error
	var quest_error: String=preload("res://gameplay/quest/quest_validation.gd").new().validate_state(s,data)
	if not quest_error.is_empty():return quest_error
	for id in s.warehouse:
		if not data.items.has(id) or not _nonnegative(s.warehouse[id]):
			return "仓库物品无效"
	for town in s.prices:
		if town not in ["town_qinglan","town_yunxi"] or not _nonnegative(s.prices[town]) or s.prices[town] < 9000 or s.prices[town] > 11000:
			return "城镇价格无效"
	var p: Dictionary = s.player
	for key in ["id","name","root","location"]:
		if not p.get(key) is String or p[key].is_empty():
			return "角色文本字段无效：" + key
	if not _has_location(p.location) or not (p.get("last_pill_day") is int or p.get("last_pill_day") is float):
		return "角色地点或服丹记录无效"
	for key in ["inventory","base","equipped","equipment_instances","techniques","spells"]:
		if not p.get(key) is Dictionary:
			return "角色缺少对象：" + key
	for key in ["hp","mp","spirit_stones","cultivation","realm","age","lifespan"]:
		if not _nonnegative(p.get(key)):
			return "角色数值非法：" + key
	if p.realm < 1 or p.realm > Cultivation.MAX_LEVEL or p.get("root","") not in data.rules.roots:
		return "角色境界或灵根无效"
	var growth_error: String = cultivation.validate_growth(p, data)
	if not growth_error.is_empty():
		return growth_error
	if s.has("spirit") and not p.has("growth"):
		return "灵气存档缺少根基状态"
	var spirit_error: String = clock.spirit.validate(s,data)
	if not spirit_error.is_empty():
		return spirit_error
	for id in p.inventory:
		if not data.items.has(id) or not _nonnegative(p.inventory[id]):
			return "背包物品或数量无效"
	for key in ["techniques","spells"]:
		for id in p[key]:
			if not data[key].has(id) or not _nonnegative(p[key][id]) or p[key][id] < 1 or p[key][id] > (3 if key=="techniques" else Spells.maximum(data.spells[id])):
				return "已学功法或法术无效"
	if not Spells.validate_player(p,data):
		return "法术熟练度或参悟记录无效"
	for key in ["hp","mp","attack","defense","speed"]:
		if not _nonnegative(p.base.get(key)):
			return "基础属性无效"
	for instance in p.equipment_instances:
		if not data.equipment.has(p.equipment_instances[instance]):
			return "装备定义无效"
	for slot in p.equipped:
		var instance: Variant = p.equipped[slot]
		if not p.equipment_instances.has(instance) or data.equipment[p.equipment_instances[instance]].slot != slot:
			return "装备实例引用无效"
	var nurture: Variant = p.get("equipment_nurture", {})
	if not nurture is Dictionary or not p.get("qi_equipment_claimed", false) is bool:
		return "装备成长或领取记录无效"
	for instance in nurture:
		if not p.equipment_instances.has(instance) or not _nonnegative(nurture[instance]) or nurture[instance] != floorf(float(nurture[instance])) or nurture[instance] > int(data.equipment[p.equipment_instances[instance]].get("nurture_max",0)):
			return "装备温养层数无效"
	for pair in [["technique_slots","techniques"],["spell_slots","spells"]]:
		if not p.get(pair[0]) is Array or p[pair[0]].size() > 3:
			return "槽位无效"
		var seen := {}
		for id in p[pair[0]]:
			if not p[pair[1]].has(id) or seen.has(id):
				return "槽位引用或重复配置无效"
			seen[id] = true
	if not Fortunes.valid_state(p,clock.seconds(s),not s.battle.is_empty()):
		return "先天天赋或后天气运记录无效"
	var current_stats := character.stats(p,data)
	if p.has("traits") and not character.validate_traits(p.traits):
		return "灵根品质或六维资质无效"
	if p.has("blood") and (not _nonnegative(p.blood) or p.blood > current_stats.blood):
		return "角色气血数值无效"
	if p.hp > current_stats.hp or p.mp > current_stats.mp:
		return "角色当前生命或灵力超限"
	if not s.battle.is_empty():
		var b: Dictionary = s.battle
		if b.has("log_entries") and not Battle.valid_log_entries(b.log_entries):return "战斗结构化日志无效"
		if not Fortunes.valid_battle_triggers(b):return "气运战斗计数无效"
		if not data.monsters.has(b.get("monster","")) or not b.get("id") is String or not b.get("enemy") is Dictionary or not b.get("status") is Dictionary or not b.get("cooldowns") is Dictionary or not b.get("log") is Array or not b.get("guard") is bool or not _nonnegative(b.get("turn")):
			return "战斗状态无效"
		if b.has("round_order"):
			if b.get("phase")!="active" or b.round_order not in [["player","enemy"],["enemy","player"]] or (b.round_order[0]=="enemy" and b.turn<1):
				return "战斗行动顺序无效"
		for key in ["hp","mp","attack","defense","speed","special_every","special_multiplier"]:
			if not b.enemy.has(key) or not (b.enemy[key] is int or b.enemy[key] is float) or b.enemy[key] < 0:
				return "敌方属性无效"
		for id in b.cooldowns:
			if not data.spells.has(id) or not _nonnegative(b.cooldowns[id]):
				return "法术冷却无效"
		for id in b.status:
			if not battle.valid_status(id,b.status[id],data):
				return "战斗效果无效"
	if s.has("battle_report"):
		var report: Variant=s.battle_report
		if not report is Dictionary:return "战斗结算记录无效"
		if not report.get("confirmed") is bool or not report.get("id") is String or report.get("result") not in ["win","lose","escape"]:return "战斗结算标记无效"
		if not data.monsters.has(report.get("monster","")) or not report.get("drops") is Dictionary or not report.get("growth") is Array or not report.get("background") is Dictionary or not report.get("log") is Array:return "战斗结算内容无效"
		if not _nonnegative(report.get("turns")) or not _nonnegative(report.get("hp")) or not _nonnegative(report.get("mp")) or not (report.get("money") is int or report.get("money") is float):return "战斗结算数值无效"
		for key in ["location","return_location"]:
			if not report.get(key) is String or not _has_location(report[key]):return "战斗结算地点无效"
		if not report.background.get("player") is Dictionary or not report.background.get("battle") is Dictionary:return "战场快照无效"
		if report.background.battle.has("log_entries") and not Battle.valid_log_entries(report.background.battle.log_entries):return "结算结构化日志无效"
		for item in report.drops:
			if not data.items.has(item) or not _nonnegative(report.drops[item]):return "结算掉落无效"
		for member in report.growth:
			if not member is Dictionary or not member.get("name") is String or not member.get("type") is String:return "结算成长无效"
			for key in ["realm","gain","current","target"]:
				if not _nonnegative(member.get(key)):return "结算成长数值无效"
	for name in ["battle","loot","exploration","world"]:
		if not payload.random.get(name) is String or not payload.random[name].is_valid_int():
			return "随机状态无效"
	for name in ["spell_affix","auction"]:
		if payload.random.has(name) and (not payload.random[name] is String or not payload.random[name].is_valid_int()):
			return "扩展随机状态无效"
	if not _nonnegative(payload.get("sequence")):
		return "操作序号无效"
	return ""

func _nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and floor(float(value)) == value

func _normalize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _normalize(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_normalize(item))
		return result
	if value is float and is_finite(value) and floor(value) == value:
		return int(value)
	return value

func sect_at_location(location: String) -> Dictionary:
	for sect in data.prototype.sects:
		if sect.get("residence",{}).get("location_id","")==location and not location.is_empty():
			return sect.duplicate(true)
	return {}

func sect_member_title(sect_id: String) -> String:
	if not sect_id.is_empty() and _state.get("sect","")==sect_id:
		return "外门弟子"
	return ""

func _has_location(location: String) -> bool:
	return location in BASE_LOCATIONS or not sect_at_location(location).is_empty()

func travel_hours(from: String, to: String) -> int:
	if from==to:
		return 0
	var hours := int(data.prototype.town_travel_days*24) if "town_yunxi" in [from,to] else 0
	for location in [from,to]:
		hours+=int(sect_at_location(location).get("residence",{}).get("travel_hours",0))
	return hours

func _sect_eligibility(s: Dictionary, id: String, allow_member: bool) -> String:
	if not s.mvp1:
		return "需先开放云溪城"
	if s.player.realm < data.prototype.sect_join_realm:
		return "需达到炼气%d层" % data.prototype.sect_join_realm
	if not s.sect.is_empty() and (not allow_member or s.sect!=id):
		return "入门条件要求尚未加入其他宗门" if allow_member else "已加入宗门"
	return ""

func sect_residence_access(location: String) -> String:
	var sect := sect_at_location(location)
	if sect.is_empty() or _state.is_empty() or _state.player.location!=location:
		return "请先抵达宗门山门"
	return _sect_eligibility(_state,sect.id,true)

func _request_state_error(action: String) -> String:
	if _busy or _state.is_empty():
		return "尚未创建角色或操作正在执行"
	if _state.player.age >= _state.player.lifespan and action!="confirm_battle_result":
		return "角色寿元已尽。本段仙途结束，可查看记录、保存或返回主菜单。"
	return ""

func request(action: String, args: Dictionary = {}, operation_id: String = "") -> Dictionary:
	var state_error := _request_state_error(action)
	if not state_error.is_empty():
		return {"success":false,"message":state_error}
	if operation_id.is_empty():
		_sequence += 1
		operation_id = "%s:%s" % [_state.player.id,_sequence]
	if _state.operations.has(operation_id):
		return {"success":false,"message":"重复请求已拒绝"}
	_busy = true
	var candidate: Dictionary = _state.duplicate(true)
	var before_random := random.snapshot()
	var error := _execute(candidate,action,args,operation_id)
	if error.is_empty():
		quests.refresh(candidate,data)
		if action in ["retreat","retreat_target"] and candidate.has("retreat_report"):
			for quest_id in candidate.quests:
				if candidate.quests[quest_id].status=="FAILED" and _state.quests.get(quest_id,{}).get("status","")!="FAILED":candidate.retreat_report.groups.quest.append(data.quests[quest_id].title+"："+candidate.quests[quest_id].get("failure_reason","无法继续"))
		candidate.operations[operation_id] = true
		_state = _normalize(candidate)
	else:
		random.restore(before_random)
	_busy = false
	if error.is_empty():
		changed.emit()
	return {"success":error.is_empty(),"message":error if not error.is_empty() else (candidate.last_result if not candidate.last_result.is_empty() else "操作成功"),"operation_id":operation_id}

func _debug_import_npc(s: Dictionary, definition: Variant, refresh: bool, edit_saved_npc: bool) -> String:
	if not OS.is_debug_build():
		return "NPC 调试导入仅在开发构建中可用"
	if not definition is Dictionary or definition.get("authored") != true:
		return "缺少已保存的 NPC 定义"
	var id: Variant = definition.get("id")
	if not id is String or not id.begins_with("npc_") or not id.is_valid_identifier():
		return "无效 NPC ID"
	var known: Dictionary = _npc_relationship_targets(s) if edit_saved_npc else s.npcs
	if s.npcs.has(id):
		if not refresh:
			return "当前档已有此 NPC，请明确选择同步装配"
		var existing: Dictionary = s.npcs[id]
		var refresh_error := NpcDefinitions.validate(definition, data, known)
		if not refresh_error.is_empty():
			return refresh_error
		var updated := NpcDefinitions.initial(definition, data)
		if not existing.has("profile"):
			existing.profile = {}
			for row in data.prototype.npcs:
				if row.id == id:
					existing.profile = row.get("profile", {}).duplicate(true)
					break
		if edit_saved_npc:
			return _apply_saved_npc_edit(s,existing,updated)
		if not existing.get("authored", false):
			_sync_npc_fortunes(existing,updated)
			s.last_result = "已同步 %s 的气运。需要保留时请手动保存。" % existing.name
			return ""
		for instance in updated.equipped.values():
			var equip_error := NpcDefinitions.equipment_error(existing, updated.equipment_instances[instance], data)
			if not equip_error.is_empty():
				return "当前档 NPC 的境界无法穿戴该装备：" + str(updated.equipment_instances[instance])
		existing.equipment_instances.merge(updated.equipment_instances, true)
		existing.equipment_nurture.merge(updated.equipment_nurture, true)
		for instance in updated.equipment_instances:
			if not updated.equipment_nurture.has(instance):
				existing.equipment_nurture.erase(instance)
		existing.equipped = updated.equipped
		_sync_npc_fortunes(existing,updated)
		for key in ["base", "stat_overrides"]:
			existing.profile[key] = updated.profile[key]
		s.last_result = "已同步 %s 的装备、气运和战斗底值。需要保留时请手动保存。" % existing.name
		return ""
	if refresh:
		return "当前档尚无此 NPC，请先导入"
	var error := NpcDefinitions.validate(definition, data, known)
	if not error.is_empty():
		return error
	var npc := NpcDefinitions.initial(definition, data)
	npc.introduced_year = _npc_world_year(s)
	s.npcs[id] = npc
	s.last_result = "已导入 %s。初始地点 %s%s。需要保留时请手动保存。" % [
		npc.name, npc.location, "，该 NPC 已达寿元上限" if not npc.alive else ""]
	return ""

func _npc_relationship_targets(s: Dictionary) -> Dictionary:
	var known: Dictionary = s.npcs.duplicate()
	var player_id: Variant = s.player.get("id")
	if player_id is String and not player_id.is_empty():
		known[player_id] = s.player
	return known

func _npc_world_year(s: Dictionary) -> int:
	var calendar: Dictionary = clock.calendar_units(data)
	var year_seconds: int = calendar.month_days * 12 * calendar.day_hours * 3600
	return int(clock.seconds(s) / year_seconds)

func _apply_saved_npc_edit(s: Dictionary, existing: Dictionary, updated: Dictionary) -> String:
	var root: Variant = updated.profile.get("root", "")
	if root != existing.profile.get("root", "") and root not in data.rules.roots:
		return "无效灵根"
	var rank: Variant = updated.profile.get("rank", "普通")
	if rank not in Character.NPC_RANKS:
		return "无效天资评级"
	if int(updated.age) != int(existing.age):
		var year := _npc_world_year(s)
		var elapsed := maxi(0,year - int(existing.get("introduced_year",0)))
		var credited := mini(elapsed,int(updated.age))
		existing.initial_age = int(updated.age) - credited
		if credited < elapsed:
			existing.introduced_year = year - credited
	if updated.location != existing.location:
		existing.erase("sect_area")
	for key in ["name","role","location","age","lifespan","realm","realm_known","cultivation","profile",
			"inventory","equipment_instances","equipped","equipment_nurture","relations",
			"techniques","technique_slots","spells","spell_slots","spell_mastery",
			"artifact_ids","artifact_slots","greeting","attributes"]:
		if updated.has(key):
			existing[key] = updated[key]
	for id in updated.fortunes:
		if existing.get("fortunes",{}).has(id):
			updated.fortunes[id] = existing.fortunes[id]
	existing.fortune_ids = updated.fortune_ids
	existing.fortunes = updated.fortunes
	existing.authored = true
	existing.erase("loadout")
	existing.alive = existing.alive and existing.age < preload("res://world/world_simulator.gd").npc_lifespan(existing,data)
	NpcDefinitions.fill_vitals(existing,existing.profile,data)
	var caps := character.npc_stats(existing,existing.profile,data)
	for key in ["hp","mp","blood"]:
		if existing.has(key):
			existing[key] = clampi(int(existing[key]),0,maxi(0,int(caps[key])))
	s.last_result = "已更新 %s 的存档人物数据。" % existing.name
	return ""

func _sync_npc_fortunes(existing: Dictionary, updated: Dictionary) -> void:
	for key in ["fortune_ids","fortunes"]:
		existing[key] = updated[key]
	for key in ["innate_fortune","acquired_fortune"]:
		existing.profile[key] = updated.profile.get(key, [])

func _battle_action_error(s: Dictionary, action: String) -> String:
	if not s.battle.is_empty() and action not in ["battle_action","use_item","prepare_use","begin_battle"]:
		return "请先结束当前战斗"
	return ""

func _equipment_sale_error(s: Dictionary, instance: String, shop_id: String) -> String:
	var p: Dictionary = s.player
	if not p.equipment_instances.has(instance) or not data.shops.has(shop_id):
		return "装备或商店不存在"
	var definition: Dictionary = data.shops[shop_id]
	if p.location != definition.location or not s.npcs[definition.npc_id].alive or s.npcs[definition.npc_id].location != p.location:
		return "商人不在此处或已死亡"
	if instance in p.equipped.values():
		return "请先卸下装备"
	if s.npcs[definition.npc_id].wealth < shop.unit_price(s,data,shop_id,p.equipment_instances[instance],false):
		return "商人灵石不足"
	return ""

func _execute(s: Dictionary, action: String, args: Dictionary, op: String) -> String:
	var p: Dictionary = s.player
	var st := character.stats(p,data)
	s.last_result = ""
	var battle_error := _battle_action_error(s,action)
	if not battle_error.is_empty():
		return battle_error
	if action in Auction.ACTIONS:
		return auction.execute(s,action,args,data,random,inventory)
	match action:
		"debug_set_player_values":
			if not OS.is_debug_build():
				return "玩家属性调试仅在开发构建中可用"
			if args.size() != DEBUG_PLAYER_STATS.size() + 1:
				return "请填写全部六项数值"
			var stones: Variant = args.get("spirit_stones")
			if not stones is int or stones < 0 or stones > DEBUG_PLAYER_VALUE_MAX:
				return "持有灵石须为 0 至 %d 的整数" % DEBUG_PLAYER_VALUE_MAX
			for key in DEBUG_PLAYER_STATS:
				var value: Variant = args.get(key)
				var minimum := 1 if key == "hp" else 0
				if not value is int or value < minimum or value > DEBUG_PLAYER_VALUE_MAX:
					return "基础%s须为 %d 至 %d 的整数" % [DEBUG_PLAYER_STATS[key], minimum, DEBUG_PLAYER_VALUE_MAX]
			for key in DEBUG_PLAYER_STATS:
				p.base[key] = args[key]
			p.spirit_stones = stones
			s.last_result = "玩家属性与持有灵石已更新"
		"debug_import_npc":
			return _debug_import_npc(s, args.get("definition"), args.get("refresh", false) == true, args.get("edit_saved_npc", false) == true)
		"confirm_battle_result":
			var report: Dictionary=s.get("battle_report",{})
			if report.is_empty() or report.id!=args.get("id","") or report.confirmed:return "结算不存在或已经确认"
			report.confirmed=true
		"prepare_use":
			if s.battle.is_empty() or s.battle.get("phase","") != "prepare":
				return "不在战斗准备阶段"
			if args.get("id","") not in Battle.RECOVERY_ITEMS:
				return "准备阶段仅可使用恢复道具"
			return inventory.use(p,args.id,data,st,int(s.hours/24))
		"use_item":
			if not s.battle.is_empty():
				return "战斗中请使用战斗道具指令"
			return inventory.use(p,args.get("id",""),data,st,int(s.hours/24))
		"buy", "sell":
			var error := shop.trade(s,data,args,action == "buy",inventory,op)
			if not error.is_empty():
				return error
			_fortune_event(s,"shop_trade_total","商贸交易")
		"sell_equipment":
			var instance: String = args.get("id","")
			var shop_id: String = args.get("shop","")
			var error := _equipment_sale_error(s,instance,shop_id)
			if not error.is_empty():
				return error
			var definition: Dictionary = data.shops[shop_id]
			var payout: int = shop.unit_price(s,data,shop_id,p.equipment_instances[instance],false)
			s.npcs[definition.npc_id].wealth -= payout
			p.spirit_stones += payout
			p.equipment_instances.erase(instance)
			if p.has("equipment_nurture"):
				p.equipment_nurture.erase(instance)
			_fortune_event(s,"shop_trade_total","商贸交易")
		"accept":
			if data.quests.get(args.get("id",""), {}).has("delivery_dialogue"):
				return "请通过委托人的对话接取"
			return quests.accept(s,args.get("id",""),data)
		"accept_announcement":
			return preload("res://gameplay/quest/town_announcements.gd").accept(args.get("id",""),s,data,quests)
		"claim_announcement":
			return preload("res://gameplay/quest/town_announcements.gd").claim(args.get("id",""),args.get("round",0),s,data,quests,inventory)
		"talk":
			var npc: String = args.get("id","")
			if not s.npcs.has(npc) or not s.npcs[npc].alive or s.npcs[npc].location != p.location:
				return "人物不在此处"
			if preload("res://world/npc_interaction.gd").sect_area_restricted(s.npcs[npc],data):
				return "尚未获得此人物所在区域的通行权限"
			var quest_line := quests.dialogue_line(s,npc,data)
			if not quest_line.is_empty():
				s.last_result = quest_line
				return ""
			s.last_result = "秦守山：先备好补给，再去青岚山。" if npc == "npc_qin_shoushan" else "欢迎来访，可以查看商店。"
			if s.npcs[npc].get("seed_on_restore", false):
				s.last_result = "%s：道友，有何事？" % s.npcs[npc].name
			if s.npcs[npc].has("greeting"):
				s.last_result = s.npcs[npc].greeting
				return ""
			for definition in data.prototype.npcs:
				if definition.id == npc and definition.has("greeting"):
					s.last_result = definition.greeting
					break
		"track_quest":
			return quests.track(s,args.get("id",""),data)
		"abandon_quest":
			return quests.abandon(s,args.get("id",""))
		"npc_option":
			var npc: String=args.get("npc","")
			if preload("res://world/npc_interaction.gd").sect_area_restricted(s.npcs.get(npc,{}),data):
				return "尚未获得此人物所在区域的通行权限"
			var options: Array=quests.dialogue_options(s,npc,data)
			for option in options:
				if option.id!=args.get("option",""):continue
				if option.kind in ["accept", "delivery", "reply"]:
					var error := ""
					if option.kind == "accept":
						error = quests.accept(s,option.quest,data)
					elif option.kind == "delivery":
						error = quests.claim(s,option.quest,data,inventory)
					if error.is_empty() and option.has("response"):
						s.last_result = option.response
					return error
				if option.kind=="progress":
					s.last_result=quests.current(s,option.quest,data).get("hint","查看任务页");return ""
				events.publish(s,{"type":option.kind,"target":npc,"location":p.location,"option":option.id})
				if option.kind=="REPORT_NPC":
					if quests.current(s,option.quest,data).is_empty():return quests.claim(s,option.quest,data,inventory,npc)
					s.last_result="报告进度已记录";return ""
				s.last_result=option.get("response","任务对话已记录")
				return ""
			return "当前任务阶段没有此对话选项"
		"investigate":
			var id: String=args.get("id","")
			if not data.events.has(id):return "探索事件不存在"
			var definition: Dictionary=data.events[id]
			if p.location!=definition.location_id:return "请前往调查事件所在地点"
			for option in definition.options:
				if option.id!=args.get("option",""):continue
				clock.advance(s,int(option.hours),data,random)
				s.completed_events[id]={"option":option.id,"hours":s.hours,"count":int(s.completed_events.get(id,{}).get("count",0))+1}
				events.publish(s,{"type":"COMPLETE_EVENT","target":id,"location":p.location,"option":option.id})
				s.last_result=option.result
				return ""
			return "无效调查操作"
		"claim":
			if data.quests.get(args.get("id",""), {}).has("delivery_dialogue"):
				return "请通过委托人的对话交付"
			return quests.claim(s,args.get("id",""),data,inventory)
		"travel":
			var location: String = args.get("id","")
			if not _has_location(location):
				return "地点不存在"
			var sect := sect_at_location(location)
			if not sect.is_empty():
				var reason := _sect_eligibility(s,sect.id,true)
				if not reason.is_empty():
					return reason
			var hours := travel_hours(p.location,location)
			if hours>0:
				clock.advance(s,hours,data,random)
			var arrived: bool=p.location!=location
			p.location = location
			if arrived:events.publish(s,{"type":"VISIT_LOCATION","target":location,"location":location})
			if location == "town_yunxi":
				s.mvp1 = true
			if not sect.is_empty() and arrived:
				s.last_result="已抵达"+sect.residence.name
		"cultivation_focus":
			var route: Variant = args.get("route")
			var focus: Variant = args.get("focus")
			if route not in ["qi", "body"] or focus not in ["refinement", "balance", "nurture"]:
				return "修炼路线或倾向无效"
			p.growth.focus[route] = focus
			s.last_result = "修炼倾向已调整"
		"release_spirit_stones":
			var count: Variant = args.get("count",1)
			if not count is int:
				return "灵石数量无效"
			var error: String = clock.spirit.release_stones(s,count,data)
			if not error.is_empty():
				return error
			s.last_result = "已释放 %d 块灵石的灵气。" % count
		"practice", "retreat", "retreat_target":
			var route: Variant = args.get("route", "qi")
			if route not in ["qi", "body"]:return "修炼路线无效"
			var days: Variant=args.get("days",1)
			if not days is int or days<=0 or days>100000000:return "修炼时长必须为有效正整数日"
			if p.location not in ["town_qinglan","cave_qinglan","town_yunxi"]:return "请在安全地点修炼"
			if action!="practice" and p.location!="cave_qinglan":return "请先进入洞府修炼室"
			if action=="practice" and days not in [1,3,10]:return "只支持打坐一日、三日或十日"
			if cultivation.equipped_techniques(p,route,data).is_empty():
				return "请先装备炼体功法" if route=="body" else "请先装备法修功法"
			var requested: int=int(days)*int(data.rules.hours_day)*3600
			var required: int=cultivation.requirement(p,route,data)
			var goal := -1
			if action=="retreat_target":
				if required<=0:return "已达当前境界上限"
				if cultivation.progress(p,route)>=required:return "已达瓶颈，请手动突破"
				goal=required
				requested=maxi(0,(int(p.lifespan)-int(s.initial_age))*int(data.rules.days_year)*int(data.rules.hours_day)*3600-clock.seconds(s))
			var before: Dictionary=s.duplicate(true)
			var interval: Dictionary=clock.advance_seconds(s,requested,data,random,"practice" if action=="practice" else "retreat",route,goal)
			if goal>=0:
				requested=interval.elapsed
			if action=="retreat_target" and cultivation.progress(p,route)<required:
				interval.interrupted=true;interval.reason="寿元已尽，未达到修炼目标"
			if action!="practice":
				s.retreat_report=preload("res://core/time_report.gd").build(before,s,interval,requested,op,data)
				s.last_result="闭关结束，获得 %d %s；世界同步推进 %s 小时。%s" % [interval.gain,"炼体修为" if route=="body" else "修为",snappedf(interval.elapsed/3600.0,.01),interval.reason]
			elif route=="body":
				s.last_result="淬体结束，炼体修为 +%d。" % interval.gain
		"promote":
			var route: Variant = args.get("route", "qi")
			if route not in ["qi", "body"]:return "修炼路线无效"
			var days: int = cultivation.breakthrough_days(p,route,data)
			var old_level: int = int(p.growth.body_level) if route=="body" else int(p.realm)
			var error: String = cultivation.promote_body(p,data) if route=="body" else cultivation.promote(s,data,random)
			if not error.is_empty():
				return error
			if old_level!=(int(p.growth.body_level) if route=="body" else int(p.realm)):
				s.spirit.progress[route].cultivation=0
				s.spirit.progress[route].erase("fortune_carry")
			clock.advance(s,days*int(data.rules.hours_day),data,random,"none")
			if route=="body":
				s.last_result="炼体突破，当前境界为%s。" % cultivation.body_realm_name(p,data)
			if old_level == 9 and (int(p.growth.body_level) if route=="body" else int(p.realm)) == 10:
				if p.growth.get("breakthrough_quality", {}).get(route) == "high":
					_fortune_event(s,"highest_first_breakthrough","高品质突破")
			var new_level := int(p.growth.body_level) if route == "body" else int(p.realm)
			if new_level > old_level and old_level > 0 and old_level % 9 == 0:
				_fortune_event(s,"major_breakthrough","大境界突破")
		"inn_stay":
			var id: String=args.get("inn","")
			if not data.inns.has(id) or p.location!=data.inns[id].location:return "请先进入客栈所在城镇"
			var found: bool=false
			for room in data.inns[id].available_rooms:
				if room.id==args.get("room","") and room.available:found=true
			if not found:return "客房不可用"
			var error: String=_execute(s,"inn",{},op)
			if not error.is_empty():return error
			s.last_result="住宿完成：花费%d灵石，休息%d日，生命与灵力已恢复。" % [data.rules.inn_cost,data.rules.inn_days]
		"inn":
			if p.location not in ["town_qinglan","town_yunxi"] or p.spirit_stones < data.rules.inn_cost:
				return "请在城镇准备足够灵石"
			p.spirit_stones -= data.rules.inn_cost
			p.hp = st.hp
			p.mp = st.mp
			clock.advance(s,int(data.rules.inn_days*24),data,random)
		"plant", "harvest", "craft":
			if p.location != "cave_qinglan":
				return "请先返回洞府"
			var error := ""
			if action == "plant":
				error = cave.plant(s,int(args.get("plot",-1)),args.get("id",""),data,inventory)
			elif action == "harvest":
				error = cave.harvest(s,int(args.get("plot",-1)),data,inventory)
			else:
				error = cave.craft(s,args.get("id",""),data,inventory)
			if not error.is_empty():
				return error
			if action == "craft":
				var seconds: int = int(data.recipes[args.id].days) * 24 * 3600
				var percent := Fortunes.modifier(p,"craft_time")
				clock.advance_seconds(s,ceili(seconds * (100 + percent) / 100.0),data,random)
				_fortune_event(s,"alchemy_total","炼丹成功")
			elif action == "harvest":
				_fortune_event(s,"harvest_total","成熟灵植收获")
		"claim_qi_equipment":
			if p.get("qi_equipment_claimed", false):
				return "已领取炼气装备"
			for item_id in data.rules.qi_equipment_set:
				if not data.equipment.has(item_id) or not data.items.has(item_id):
					return "炼气套装配置无效"
			for item_id in data.rules.qi_equipment_set:
				var error: String = inventory.add(p,item_id,1,data,"qi_set_" + item_id)
				if not error.is_empty():
					return error
			p.qi_equipment_claimed = true
		"nurture_equipment":
			var instance: String = args.get("id","")
			if not p.equipment_instances.has(instance):
				return "装备实例不存在"
			var definition: Dictionary = data.equipment[p.equipment_instances[instance]]
			if not definition.has("nurture_max"):
				return "该装备无法温养"
			var levels: Dictionary = p.get("equipment_nurture",{})
			var current := int(levels.get(instance,0))
			if current >= int(definition.nurture_max):
				return "已温养至圆满"
			levels[instance] = current + 1
			p.equipment_nurture = levels
		"equip", "unequip":
			var instance: String = args.get("id","")
			if not p.equipment_instances.has(instance):
				return "装备实例不存在"
			var definition: Dictionary = data.equipment[p.equipment_instances[instance]]
			if action == "equip":
				var equip_error := preload("res://gameplay/inventory/equipment_values.gd").equip_error(definition, int(p.realm))
				if not equip_error.is_empty():
					return equip_error
				p.equipped[definition.slot] = instance
			else:
				if p.equipped.get(definition.slot, "") != instance:
					return "该装备未穿戴"
				p.equipped.erase(definition.slot)
		"slot", "upgrade":
			var id: String = args.get("id","")
			var passive: bool = data.techniques.has(id)
			var learned: Dictionary = p.techniques if passive else p.spells
			var slots: Array = p.technique_slots if passive else p.spell_slots
			if not learned.has(id):
				return "尚未学习"
			if action == "slot":
				if id in slots:
					slots.erase(id)
				elif slots.size() < int(data.rules.initial_slots):
					slots.append(id)
				else:
					return "当前仅开放三个槽位"
			else:
				var level: int = int(learned[id])
				if not passive and data.spells[id].has("levels"):
					return "请通过法术修炼提高熟练度"
				if level >= 3:
					return "已达三级"
				var cost: Array = data.rules.technique_upgrade[data.techniques[id].rarity][level-1] if passive else [data.rules.spell_upgrade[level-1],0]
				if p.spirit_stones < cost[0] or p.cultivation < cost[1]:
					return "灵石或修为不足"
				p.spirit_stones -= cost[0]
				p.cultivation -= cost[1]
				learned[id] += 1
		"spell_train":
			var id: String = args.get("id","")
			var quote := _spell_training(s,id,args.get("method",""),args.get("days",0))
			if not quote.success:
				return quote.message
			p.spirit_stones -= quote.cost
			clock.advance(s,quote.hours,data,random,"none")
			var progress := Spells.add_mastery(p,id,quote.gain,data)
			s.last_result = "%s修炼完成，熟练度 +%d" % [data.spells[id].name,progress.gain]
		"spell_affix_roll":
			var id: String = args.get("id","")
			var slot: Variant = args.get("slot")
			if not p.spells.has(id) or not Spells.supports_affixes(data.spells[id]) or not slot is int or slot < 0 or slot >= Spells.affix_slots(int(p.spells[id])):
				return "该法术或词条槽尚未开放参悟"
			if not p.get("spell_affix_pending",{}).is_empty():
				return "请先处理已有参悟结果"
			var cost := int(data.spell_growth.affix_cost)
			if p.spirit_stones < cost:
				return "灵石不足"
			var pool: Array = data.spell_growth.affixes.keys()
			for affix in p.get("spell_affixes",{}).get(id,{}).values():
				pool.erase(affix)
			var options: Array = []
			for index in range(mini(2,pool.size())):
				options.append(pool.pop_at(random.integer("spell_affix",0,pool.size()-1)))
			p.spirit_stones -= cost
			p.spell_affix_pending = {"id":id,"slot":slot,"candidates":options,"token":op}
		"spell_affix_resolve":
			var pending: Dictionary = p.get("spell_affix_pending",{})
			var option: String = args.get("option","")
			if pending.is_empty() or pending.token != args.get("token","") or (not option.is_empty() and option not in pending.candidates):
				return "参悟结果无效或已处理"
			if not option.is_empty():
				if not p.has("spell_affixes"):
					p.spell_affixes = {}
				if not p.spell_affixes.has(pending.id):
					p.spell_affixes[pending.id] = {}
				p.spell_affixes[pending.id][str(pending.slot)] = option
			p.erase("spell_affix_pending")
		"explore":
			if p.location != "area_qinglan_outskirts":
				return "请先前往青岚山外围"
			var route_id: Variant = args.get("route", "")
			if not route_id is String:
				return "未知探索入口"
			var outcomes: Array = [0,1,2,3,4]
			var herbs: Array = ["herb_morning_dew","herb_spirit_grass"]
			var mining: Array = []
			var encounter: Dictionary = {}
			if not route_id.is_empty():
				var route_index: int = data.prototype.outskirts_routes.find_custom(func(entry):return entry.id == route_id)
				if route_index < 0:
					return "未知探索入口"
				var definition: Dictionary = data.prototype.outskirts_routes[route_index]
				if definition.has("unavailable"):
					return definition.unavailable
				outcomes = definition.get("outcomes", [])
				herbs = definition.get("herbs", [])
				mining = definition.get("mining", [])
				encounter = definition.get("encounter", {})
			var elapsed := clock.advance(s,int(data.rules.exploration_hours),data,random)
			if not mining.is_empty():
				if elapsed.interrupted:
					s.last_result = "采矿中断：" + elapsed.reason
					return ""
				if not encounter.is_empty() and random.integer("exploration",1,100) <= encounter.chance:
					return battle.start(s,encounter.monster_id,data,op)
				var gathered := PackedStringArray()
				for ore in mining:
					if ore.chance < 100 and random.integer("exploration",1,100) > ore.chance:
						continue
					inventory.add(p,ore.item_id,1,data)
					gathered.append("%s ×1" % data.items[ore.item_id].name)
				s.last_result = "采到 " + "、".join(gathered) if not gathered.is_empty() else "这次没有采到矿石"
				return ""
			var event: int = 0
			if 0 in outcomes and s.quests.get("quest_qinglan_002",{}).get("status","") == "ACTIVE" and not s.first_wolf:
				s.first_wolf = true
			else:
				var total := 0
				for i in outcomes:
					total += int(data.rules.exploration_weights[i])
				var roll: int = random.integer("exploration",1,100 if route_id.is_empty() else total)
				total = 0
				for i in outcomes:
					total += int(data.rules.exploration_weights[i])
					if roll <= total:
						event = i
						break
			if event < 3:
				return battle.start(s,["monster_gray_wolf","monster_mountain_boar","monster_green_fox"][event],data,op)
			elif event == 3:
				var herb: String = herbs[random.integer("exploration",0,herbs.size()-1)]
				var quantity := 1
				var chance := Fortunes.modifier(p,"herb_yield")
				if chance > 0 and random.roll("exploration") < chance / 100.0:
					quantity += 1
				inventory.add(p,herb,quantity,data)
				s.last_result = "采集到 %d 株灵草" % quantity
				for index in range(quantity):
					_fortune_event(s,"herb_gather_total","历练采药")
			else:
				var caps := character.stats(p,data)
				p.hp = mini(int(caps.hp),int(p.hp + data.rules.rest_hp))
				p.mp = mini(int(caps.mp),int(p.mp + data.rules.rest_mp))
				s.last_result = "山间清泉恢复了生命与灵力"
		"challenge":
			if p.location != "area_qinglan_outskirts":
				return "请先前往青岚山外围，狼首危险，建议备好补给"
			return battle.start(s,"monster_wolf_leader",data,op)
		"begin_battle", "battle_action":
			var error := battle.begin(s,data,st,random,inventory) if action=="begin_battle" else battle.action(s,args,data,st,random,inventory)
			if not error.is_empty():
				return error
			if not s.pending_battle_result.is_empty():
				_finish_battle(s,st)
		"formation":
			if not s.mvp1 or p.location != "cave_qinglan":
				return "云溪城开放后可在洞府启用"
			if not s.formation:
				if p.spirit_stones < data.rules.formation_start:
					return "灵石不足"
				p.spirit_stones -= data.rules.formation_start
			s.formation = not s.formation
		"warehouse":
			if not s.mvp1 or p.location != "cave_qinglan":
				return "云溪城开放后可使用洞府仓库"
			var id: String = args.get("id","")
			if args.get("withdraw",false):
				if s.warehouse.get(id,0) < 1:
					return "仓库没有该物品"
				s.warehouse[id] -= 1
				inventory.add(p,id,1,data)
			else:
				if s.warehouse.get(id,0) >= data.prototype.warehouse_capacity:
					return "该物品仓储已满"
				var error := inventory.remove(p,id,1)
				if not error.is_empty():
					return error
				s.warehouse[id] = int(s.warehouse.get(id,0))+1
		"cave_upgrade":
			if not s.mvp1 or p.location != "cave_qinglan" or s.cave_level >= 2:
				return "升级尚未开放或已达原型上限"
			if p.spirit_stones < data.prototype.cave_upgrade_cost or p.inventory.get("material_spirit_iron",0) < data.prototype.cave_upgrade_iron:
				return "升级需要200灵石与5下品灵铁"
			p.spirit_stones -= data.prototype.cave_upgrade_cost
			inventory.remove(p,"material_spirit_iron",int(data.prototype.cave_upgrade_iron))
			s.cave_level += 1
		"join_sect":
			var id: String = args.get("id","")
			var reason := _sect_eligibility(s,id,false)
			if not reason.is_empty():
				return reason
			var found := false
			for sect in data.prototype.sects:
				if sect.id == id:
					found = true
			if not found:
				return "宗门不存在"
			s.sect = id
		"donate":
			if s.sect.is_empty() or p.spirit_stones < data.prototype.sect_donation:
				return "未加入宗门或灵石不足"
			p.spirit_stones -= data.prototype.sect_donation
			s.contribution += roundi(float(data.prototype.sect_contribution) * (100 + Fortunes.modifier(p,"contribution")) / 100.0)
		_:
			return "未知操作"
	var final_stats := character.stats(p,data)
	if action == "debug_set_player_values" and (final_stats.hp < 1 or final_stats.mp < 0):
		return "加成结算后的生命或灵力上限无效"
	p.hp = clampi(int(p.hp),0,int(final_stats.hp))
	p.mp = clampi(int(p.mp),0,int(final_stats.mp))
	return ""

func _fortune_event(s: Dictionary, event: String, source: String, target: String = "") -> void:
	var names := Fortunes.record_event(s.player,event,clock.seconds(s),int(data.rules.hours_day)*3600,source,target)
	for name in names:
		s.last_result += " 获得后天气运「%s」。" % name

func _finish_battle(s: Dictionary, st: Dictionary) -> void:
	if s.battle.is_empty() or s.pending_battle_result.is_empty():
		return
	var result: String = s.pending_battle_result
	var enemy: Dictionary = s.battle.enemy
	var monster: String = s.battle.monster
	var before: Dictionary=s.player.duplicate(true)
	Fortunes.end_battle(s.player)
	var drops: Dictionary={}
	var battle_snapshot: Dictionary=s.battle.duplicate(true)
	if not battle_snapshot.has("log_entries"):
		battle_snapshot.log_entries=[]
		for line in battle_snapshot.log:battle_snapshot.log_entries.append({"type":"legacy","text":line})
	battle_snapshot.log_entries.append({"type":"result","result":result})
	if result == "win":
		s.player.spirit_stones += random.integer("loot",int(enemy.money[0]),int(enemy.money[1]))
		for drop in enemy.drops:
			if random.roll("loot") < drop[2]:
				var quantity := int(drop[1])
				if drop.size() == 4:
					quantity = random.integer("loot",quantity,int(drop[3]))
				inventory.add(s.player,drop[0],quantity,data)
				drops[drop[0]]=int(drops.get(drop[0],0))+quantity
		if monster == "monster_wolf_leader" and not s.leader_reward:
			inventory.add(s.player,"pill_qi_gathering",1,data)
			drops["pill_qi_gathering"]=int(drops.get("pill_qi_gathering",0))+1
			s.leader_reward = true
		events.publish(s,{"type":"KILL_ENEMY","target":monster,"location":s.player.location,"battle_id":battle_snapshot.id,"count":1})
	elif result == "lose":
		s.player.hp = int(ceil(st.hp*data.rules.defeat_restore))
		s.player.mp = int(ceil(st.mp*data.rules.defeat_restore))
		s.player.spirit_stones -= int(floor(s.player.spirit_stones*data.rules.defeat_loss))
		s.player.location = "town_qinglan"
	s.last_result = {"win":"战斗胜利，战利品已结算","lose":"战败，已返回青岚镇","escape":"逃跑成功，无战利品"}[result]
	if result == "win":
		_fortune_event(s,"battle_win_total","战斗胜利")
		_fortune_event(s,"battle_win_streak","连续战斗胜利")
		_fortune_event(s,"beast_victory","击败妖兽",monster)
	elif s.player.has("fortune_progress"):
		s.player.fortune_progress.erase("battle_streak")
	var target: int=cultivation.requirement(s.player,"qi",data)
	s.battle_report={"id":battle_snapshot.id,"confirmed":false,"result":result,"location":before.location,"return_location":s.player.location,"monster":monster,"turns":battle_snapshot.turn,"money":s.player.spirit_stones-before.spirit_stones,"drops":drops,"growth":[{"name":s.player.name,"realm":s.player.realm,"type":"修为","gain":s.player.cultivation-before.cultivation,"current":s.player.cultivation,"target":target}],"hp":s.player.hp,"mp":s.player.mp,"background":{"player":before,"battle":battle_snapshot},"log":battle_snapshot.log.duplicate()}
	s.battle = {}
	s.pending_battle_result = ""
	clock.advance(s,int(data.rules.battle_hours),data,random,"none")

## Read-only presentation; probes reuse the real command validation on isolated state.
func skill_presentation(id: String) -> Dictionary:
	var passive: bool=data.techniques.has(id)
	var learned: Dictionary=_state.player.techniques if passive else _state.player.spells
	var level: int=int(learned[id])
	var result: Dictionary={}
	if not passive and data.spells[id].has("levels"):
		var slot_error := ""
		if not _state.battle.is_empty():
			slot_error = "请先结束当前战斗"
		elif _state.player.age >= _state.player.lifespan:
			slot_error = "角色寿元已尽"
		elif id not in _state.player.spell_slots and _state.player.spell_slots.size() >= int(data.rules.initial_slots):
			slot_error = "法术槽已满"
		result.slot = {"success":slot_error.is_empty(),"message":slot_error}
		result.upgrade = {"success":false,"message":"请使用法术修炼"}
		result.current = _skill_effect_text(id,level)
		result.next = _skill_effect_text(id,level+1) if level<Spells.maximum(data.spells[id]) else "已达当前等级上限"
		result.cost = ""
		return result
	for action in ["slot","upgrade"]:
		var probe: RefCounted=get_script().new()
		probe.configure(data)
		probe.restore_save(export_save())
		result[action]=probe.request(action,{"id":id})
	result.current=_skill_effect_text(id,level)
	result.next=_skill_effect_text(id,level+1) if level<3 else "已达当前等级上限"
	if level<3:
		var cost: Array=data.rules.technique_upgrade[data.techniques[id].rarity][level-1] if passive else [data.rules.spell_upgrade[level-1],0]
		result.cost="升级消耗：%d 灵石、%d 修为（持有 %d / %d）" % [cost[0],cost[1],_state.player.spirit_stones,_state.player.cultivation]
	else:result.cost="无需升级：已达三级"
	return result

func _skill_effect_text(id: String,level: int) -> String:
	var lines: Array[String]=[]
	if data.techniques.has(id):
		var definition: Dictionary=data.techniques[id]
		for key in ["hp","defense","attack","fire"]:
			var value: float=definition[key]+definition[key+"_step"]*(level-1)
			if value!=0:
				lines.append("%s +%s%s" % [{"hp":"生命上限","defense":"防御","attack":"攻击","fire":"火系伤害"}[key],str(snapped(value*100 if key=="fire" else value,0.01)),"%" if key=="fire" else ""])
		lines.append("用于%s炼化灵气，升级提高每小时可炼化量。" % ("炼体" if definition.cultivation_route=="body" else "法修"))
	else:
		var spell: Dictionary=data.spells[id]
		lines.append("%s属性 · 灵力消耗 %d · 冷却 %d 自身行动" % [spell.element,spell.mp,spell.cd])
		for line in Spells.effect_lines(spell,level,data.spell_growth):
			lines.append(line[1])
	return "
".join(lines)


func spell_training(id: String, method: String, days: int) -> Dictionary:
	if _state.is_empty():
		return {"success":false,"message":"尚未创建角色"}
	return _spell_training(_state,id,method,days)

func _spell_training(s: Dictionary, id: String, method: Variant, days: Variant) -> Dictionary:
	var p: Dictionary = s.player
	var config: Dictionary = data.spell_growth
	if not p.spells.has(id) or not data.spells[id].has("levels"):
		return {"success":false,"message":"该法术不适用熟练度修炼"}
	if not days is int or days < 1 or days > int(config.max_days) or not config.methods.has(method):
		return {"success":false,"message":"修炼方式或时长无效"}
	var plan: Dictionary = config.methods[method]
	var quote := Spells.growth(p,id,int(plan.gain)*days,data)
	quote.merge({"cost":int(plan.cost)*days,"hours":days*int(data.rules.hours_day),"days":days,"success":false,"message":""})
	if not s.battle.is_empty() or p.location not in ["town_qinglan","cave_qinglan","town_yunxi"]:
		quote.message = "请在安全地点修炼"
	elif quote.before >= Spells.maximum(data.spells[id]):
		quote.message = "法术已圆满"
	elif p.spirit_stones < quote.cost:
		quote.message = "灵石不足"
	elif clock.projected_age(s,days,data) >= p.lifespan:
		quote.message = "剩余寿元不足以完成修炼"
	else:
		quote.success = true
	return quote

func equipment_availability(instance: String,action: String) -> Dictionary:
	if action not in ["equip","unequip","nurture_equipment"]:return {"success":false,"message":"无效装备操作"}
	var probe: RefCounted=get_script().new()
	probe.configure(data)
	probe.restore_save(export_save())
	return probe.request(action,{"id":instance})

func character_stat_tooltip(key: String) -> String:
	if _state.is_empty():return ""
	var p: Dictionary=_state.player
	var lines: Array[String]=["基础：%s" % p.base[key]]
	var bonus: int = character.foundation_bonuses(p,data).get(key,0)
	if bonus>0:
		lines.append("根基温养：+%d" % bonus)
	for instance in p.equipped.values():
		var id: String=p.equipment_instances[instance]
		var definition: Dictionary = data.equipment[id]
		var values := preload("res://gameplay/inventory/equipment_values.gd").base_stats(definition,p,str(instance),data.rules)
		var value: float = float(values.get(key,0))
		for entry in definition.get("traits", []):
			if entry.type == key:
				value += preload("res://gameplay/inventory/equipment_values.gd").trait_amount(definition,entry,p,data.rules)
		if value!=0:lines.append("%s：+%s" % [data.items[id].name,value])
	for id in p.technique_slots:
		var definition: Dictionary=data.techniques[id]
		if not definition.has(key):continue
		var value: float=definition[key]+definition[key+"_step"]*(int(p.techniques[id])-1)
		if value!=0:lines.append("%s：+%s" % [definition.name,value])
	var fixed := Fortunes.modifier(p,"stat",key,"fixed")
	var percent := Fortunes.modifier(p,"stat",key)
	if fixed != 0 or percent != 0:
		lines.append("天赋与气运：固定 %d，百分比 %d%%" % [fixed,percent])
	lines.append("最终：%s" % stats()[key])
	return "
".join(lines)

func cave_quote(action: String,args: Dictionary) -> Dictionary:
	var probe: RefCounted=get_script().new()
	probe.configure(data)
	probe.restore_save(export_save())
	return probe.request(action,args)

func retreat_preview(years: int,months: int,days: int,goal: bool=false,route: String="qi") -> Dictionary:
	var units: Dictionary=clock.calendar_units(data)
	var total: int=years*units.year_days+months*units.month_days+days
	var reason: String=""
	if years<0 or months<0 or days<0 or (total<=0 and not goal):reason="闭关时长必须大于零"
	var probe: RefCounted=get_script().new();probe.configure(data)
	var error: String=probe.restore_save(export_save())
	if reason.is_empty():reason=error
	var result: Dictionary={"success":false,"message":reason}
	if reason.is_empty():result=probe.request("retreat_target" if goal else "retreat",{"days":maxi(1,total),"route":route})
	if not result.success:reason=result.message
	var report: Dictionary=probe.snapshot().get("retreat_report",{}) if result.success else {}
	var warnings: Array=[]
	if not report.is_empty():
		if report.age>=_state.player.lifespan:warnings.append("本次闭关将到达寿元上限，此后无法继续玩法操作。")
		for line in report.groups.quest:warnings.append("任务风险："+str(line))
	return {"warnings":warnings,"days":total,"gain":report.get("gain",0),"after":report.get("after",cultivation.progress(_state.player,route)),"age":report.get("age",_state.player.age),"remaining":maxi(0,int(_state.player.lifespan)-int(report.get("age",_state.player.age))),"reason":reason,"success":result.success,"elapsed":report.get("elapsed",0),"report":report}
func clock_status() -> Dictionary:
	return {"exists":not _state.is_empty(),"expired":not _state.is_empty() and _state.player.age>=_state.player.lifespan}
func advance_realtime(seconds: int) -> Dictionary:
	var status: Dictionary=clock_status()
	if seconds<=0 or _busy or not status.exists or status.expired:return {"elapsed":0}
	_busy=true
	var candidate: Dictionary=_state.duplicate(true)
	var interval: Dictionary=clock.advance_seconds(candidate,seconds,data,random,"natural")
	quests.refresh(candidate,data)
	_state=_normalize(candidate);_busy=false
	time_changed.emit(interval)
	return interval

func inventory_action_quote(action: String,args: Dictionary) -> Dictionary:
	var probe: RefCounted=get_script().new()
	probe.configure(data)
	probe.restore_save(export_save())
	return probe.request(action,args)
