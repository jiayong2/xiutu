extends RefCounted
## Qingyue outer-arena sparring and the outer-to-inner exam.
## Dialogue, fees and rewards live here. Combat stays in BattleSystem.

const SECT := "sect_qingyue"
const GATE := "sect_qingyue_gate"
const ARENA := "arena"
const OUTER := "outer"
const INNER := "inner"
const HAN := "npc_han_tieshan"
const CHEN := "npc_chen_yuan"
const MENG := "npc_108088301ababcbd3e25e84b"
const ZHOU := "npc_zhou_xuan"
const SPAR_HOURS := 1
const EXAM_HOURS := 2
const FEE := 50
const PROMOTION_CONTRIBUTION := 100
const MERIT_REQUIRED := 100
const QUESTS_REQUIRED := 2
const REALM_REQUIRED := 6
const COOLDOWN_DAYS := 3
const SPARRING := {
	CHEN: {"name": "陈远", "first_contribution": 10, "first_favor": 2, "daily_contribution": 3, "daily_favor": 1,
		"first_line": "师弟，要不要切磋一场？", "repeat_line": "又来切磋了？",
		"win_line": "这次是你赢了，下次再来！", "lose_line": "承让了，改日再战。"},
	MENG: {"name": "孟钧光", "first_contribution": 15, "first_favor": 2, "daily_contribution": 5, "daily_favor": 1,
		"first_line": "想与我切磋？我可不会放水。", "repeat_line": "准备好再战一场了？",
		"win_line": "你赢了，看来我还得继续修炼。", "lose_line": "此次是我胜了，下次再战。"},
}
const REWARD_SPENT_LINE := "今日与此人的有奖切磋已完成，继续挑战不再获得奖励。"
const NO_REWARD := "本次无奖励"

static func rank(s: Dictionary) -> String:
	var stored := str(s.get("sect_rank", ""))
	if stored == "inner":
		return "inner"
	if stored == "outer" or (stored.is_empty() and not str(s.get("sect", "")).is_empty()):
		return "outer"
	return ""

static func member_title(s: Dictionary, sect_id: String) -> String:
	if sect_id.is_empty() or str(s.get("sect", "")) != sect_id:
		return ""
	return "内门弟子" if rank(s) == "inner" else "外门弟子"

static func area_open(s: Dictionary, sect_id: String, area_id: String, restriction: String) -> bool:
	if restriction.is_empty():
		return true
	return area_id == INNER and str(s.get("sect", "")) == sect_id and str(s.get("sect", "")) == SECT and rank(s) == "inner"

static func game_day(s: Dictionary, data: Dictionary) -> int:
	var clock := preload("res://core/time_system.gd").new()
	var day := int(clock.calendar_units(data).day_hours) * 3600
	return int(clock.seconds(s) / day) if day > 0 else 0

static func quest_completions(s: Dictionary, data: Dictionary) -> int:
	var total := 0
	for id in data.get("quests", {}):
		var quest: Dictionary = data.quests[id]
		if str(quest.get("requirements", {}).get("sect_id", "")) != str(s.get("sect", "")):
			continue
		if str(s.get("sect", "")).is_empty():
			continue
		total += _completion_count(s.get("quests", {}).get(id, {}))
	return total

static func sect_quests_exist(data: Dictionary, sect_id: String) -> bool:
	for quest in data.get("quests", {}).values():
		if str(quest.get("requirements", {}).get("sect_id", "")) == sect_id:
			return true
	return false

static func ensure_merit(s: Dictionary, data: Dictionary) -> void:
	if s.has("sect_task_merit"):
		return
	var total := 0
	var sect_id := str(s.get("sect", ""))
	for id in data.get("quests", {}):
		var quest: Dictionary = data.quests[id]
		if str(quest.get("requirements", {}).get("sect_id", "")) != sect_id or sect_id.is_empty():
			continue
		total += _completion_count(s.get("quests", {}).get(id, {})) * int(quest.get("contribution", 0))
	s.sect_task_merit = total

static func note_quest_merit(s: Dictionary, gained: int) -> void:
	if gained <= 0:
		return
	s.sect_task_merit = int(s.get("sect_task_merit", 0)) + gained

static func merit(s: Dictionary) -> int:
	return int(s.get("sect_task_merit", 0))

static func opening_line(s: Dictionary, npc_id: String, data: Dictionary) -> String:
	if npc_id == HAN:
		return _han_line(s)
	if npc_id == ZHOU:
		return _zhou_line(s, data, true)
	if npc_id in SPARRING:
		if npc_id == MENG and str(_promotion(s).get("meng_mode", "spar")) == "exam":
			return _exam_line(s, data, true)
		return _spar_line(s, npc_id, data, true)
	return ""

static func dialogue_options(s: Dictionary, npc_id: String, data: Dictionary, previous: String) -> Array:
	if npc_id == HAN:
		return _han_options(s, data, previous)
	if npc_id == ZHOU:
		return _zhou_options(s, data, previous)
	if npc_id in SPARRING:
		if npc_id == MENG and str(_promotion(s).get("meng_mode", "spar")) == "exam":
			return _exam_options(s, previous)
		return _spar_options(s, npc_id, data, previous)
	return []

static func arm_exam(s: Dictionary, data: Dictionary) -> String:
	var npc: Dictionary = s.get("npcs", {}).get(MENG, {})
	if str(s.player.location) != GATE or npc.is_empty() or npc.get("alive", false) != true or str(npc.get("location", "")) != GATE:
		return "请先前往青岳宗演武场"
	if str(npc.get("sect_area", "")) != OUTER or str(npc.get("sect_building", "")) != ARENA:
		return "考核对手不在演武场"
	if _restricted(npc, data, s):
		return "尚未获得此人物所在区域的通行权限"
	_promotion(s).meng_mode = "exam"
	s.last_result = "这次由我担任考核对手，准备好了吗？"
	return ""

static func find_option(s: Dictionary, npc_id: String, data: Dictionary, option_id: String) -> Dictionary:
	if option_id.is_empty() or npc_id not in [HAN, ZHOU, CHEN, MENG]:
		return {}
	var contexts: Array = ["", "spar_menu", "spar_rules", "spar_pick:" + CHEN, "spar_pick:" + MENG, "spar_warn:" + CHEN, "spar_warn:" + MENG,
		"promo_apply", "promo_confirm", "promo_retry", "promo_short", "promo_enrolled"]
	for previous in contexts:
		for option in dialogue_options(s, npc_id, data, str(previous)):
			if str(option.get("id", "")) == option_id:
				return option
	return {}

static func apply(s: Dictionary, npc_id: String, option: Dictionary, data: Dictionary, battle: RefCounted, identity: String) -> String:
	var kind := str(option.get("kind", ""))
	if kind == "reply" and str(option.get("id", "")).begins_with("spar_pick:"):
		var target := str(option.get("target", ""))
		if target == MENG:
			_promotion(s).meng_mode = "spar"
		if _reward_claimed_today(s, target, data):
			s.last_result = REWARD_SPENT_LINE
		else:
			s.last_result = _spar_line(s, target, data, true)
		return ""
	if kind == "reply" and str(option.get("id", "")) in ["promo_apply", "promo_retry"]:
		if _gaps(s, data).is_empty() and not _cooling(s, data):
			s.last_result = "资格已足，缴纳五十贡献便可报名。"
		else:
			s.last_result = "你尚未达到晋升条件，先去修炼或积累功绩吧。\n" + _missing_text(s, data)
		return ""
	if kind in ["reply", "close"]:
		s.last_result = str(option.get("response", ""))
		if kind == "close":
			_spar(s).summon = ""
		return ""
	if kind == "enroll":
		return _enroll(s, data)
	if kind == "claim":
		return _claim(s)
	if kind == "open_exam":
		_promotion(s).meng_mode = "exam"
		s.ui_open_npc = MENG
		s.last_result = "报名已完成，去演武场参加考核吧。"
		return ""
	if kind == "start_spar":
		return _start_spar(s, str(option.get("target", "")), data, battle, identity)
	if kind == "start_exam":
		return _start_exam(s, data, battle, identity)
	return "没有这项切磋或考核操作"

static func settle_spar(s: Dictionary, npc_id: String, result: String, data: Dictionary, battle_id: String) -> Dictionary:
	var record := _spar(s)
	var last: Dictionary = record.get("last", {})
	if str(last.get("battle_id", "")) == battle_id and not battle_id.is_empty():
		return last
	var reward := {"contribution": 0, "favor": 0, "favor_applied": 0, "text": NO_REWARD}
	if result == "win" and SPARRING.has(npc_id):
		reward = _spar_reward(s, npc_id, data)
		if int(reward.contribution) > 0:
			s.contribution = int(s.get("contribution", 0)) + int(reward.contribution)
		if int(reward.favor) > 0:
			reward.favor_applied = _adjust_favor(s, npc_id, int(reward.favor))
		if int(reward.contribution) > 0 or int(reward.favor) > 0:
			record.first_win[npc_id] = true
			record.reward_day[npc_id] = game_day(s, data)
		var profile: Dictionary = SPARRING[npc_id]
		reward.text = _reward_text(int(reward.contribution), int(reward.favor_applied))
		reward["line"] = str(profile.win_line)
	else:
		reward["line"] = str(SPARRING.get(npc_id, {}).get("lose_line", "承让了，改日再战。"))
	if int(reward.contribution) == 0 and int(reward.get("favor_applied", 0)) == 0:
		reward.text = NO_REWARD
	reward["npc_id"] = npc_id
	reward["result"] = result
	reward["day"] = game_day(s, data)
	reward["battle_id"] = battle_id
	record.last = reward
	record.summon = ""
	return reward

static func settle_exam(s: Dictionary, result: String, battle_id: String, data: Dictionary) -> Dictionary:
	var promo := _promotion(s)
	if str(promo.get("exam_battle_id", "")) == battle_id and not battle_id.is_empty():
		return {"line": str(promo.get("exam_line", "")), "result": str(promo.get("result", "")), "text": NO_REWARD}
	var won := result == "win"
	promo.exam_battle_id = battle_id
	promo.result = "win" if won else "lose"
	promo.enrolled = false
	promo.meng_mode = "spar"
	if won:
		promo.pending_report = true
		promo.cooldown_until_day = -1
		promo.exam_line = "考核通过，去向周长老复命吧。"
	else:
		promo.pending_report = false
		promo.cooldown_until_day = game_day(s, data) + COOLDOWN_DAYS
		promo.exam_line = "此次考核结束，下次再来。"
	return {"line": str(promo.exam_line), "result": promo.result, "text": NO_REWARD, "contribution": 0, "favor": 0}

static func hours_for(battle_type: String) -> int:
	return EXAM_HOURS if battle_type == "sect_exam" else SPAR_HOURS

static func validate(s: Dictionary) -> String:
	if s.has("sect_rank") and str(s.sect_rank) not in ["", "outer", "inner"]:
		return "宗门职级无效"
	if str(s.get("sect_rank", "")) == "inner" and str(s.get("sect", "")) != SECT:
		return "内门职级与宗门不符"
	if s.has("sect_task_merit") and not _whole(s.sect_task_merit):
		return "宗门任务功绩无效"
	if s.has("sect_spar"):
		var spar_error := _validate_spar(s.sect_spar)
		if not spar_error.is_empty():
			return spar_error
	if s.has("sect_promotion"):
		var promo_error := _validate_promotion(s.sect_promotion, s)
		if not promo_error.is_empty():
			return promo_error
	if str(s.get("sect_rank", "")) == "inner":
		var promo: Dictionary = s.get("sect_promotion", {})
		if promo.get("completed", false) != true or promo.get("reward_claimed", false) != true:
			return "内门职级缺少晋升记录"
	if s.get("sect_promotion", {}).get("completed", false) == true and str(s.get("sect_rank", "")) != "inner":
		return "晋升记录与职级不符"
	return ""

static func _han_line(s: Dictionary) -> String:
	if not _can_spar(s).is_empty():
		return _can_spar(s)
	var visits := _bump_visit(_spar(s), HAN)
	if visits <= 1:
		return "这里是外门演武场，同门切磋，点到为止。"
	return "今日想找谁切磋？"

static func _han_options(s: Dictionary, data: Dictionary, previous: String) -> Array:
	if not _can_spar(s).is_empty():
		return [_option("spar_leave", "离开", "离开。", "close")] if previous.is_empty() else []
	if previous.is_empty():
		var rows: Array = [_option("spar_menu", "选择对手", "选择对手。", "reply")]
		if int(_spar(s).get("visits", {}).get(HAN, 0)) <= 1:
			rows.append(_option("spar_rules", "切磋规则", "切磋不伤性命，每名对手每日首次获胜可得贡献。", "reply"))
		rows.append(_option("spar_leave", "离开", "离开。", "close"))
		return rows
	if previous == "spar_menu":
		return [
			_option("spar_pick:" + CHEN, "陈远", "", "reply", CHEN),
			_option("spar_pick:" + MENG, "孟钧光", "", "reply", MENG),
			_option("spar_back", "返回", "今日想找谁切磋？", "reply"),
		]
	if previous.begins_with("spar_pick:"):
		return _follow_rows(previous.trim_prefix("spar_pick:"), _reward_claimed_today(s, previous.trim_prefix("spar_pick:"), data))
	if previous == "spar_rules" or previous == "spar_back":
		return _han_options(s, data, "")
	return []

static func _spar_line(s: Dictionary, npc_id: String, data: Dictionary, bump: bool) -> String:
	var reason := _can_spar(s)
	if not reason.is_empty():
		return reason
	if _reward_claimed_today(s, npc_id, data):
		return REWARD_SPENT_LINE
	if bump:
		var visits := _bump_visit(_spar(s), npc_id)
		return str(SPARRING[npc_id].first_line) if visits <= 1 else str(SPARRING[npc_id].repeat_line)
	var visits_now := int(_spar(s).get("visits", {}).get(npc_id, 0))
	return str(SPARRING[npc_id].first_line) if visits_now <= 1 else str(SPARRING[npc_id].repeat_line)

static func _spar_options(s: Dictionary, npc_id: String, data: Dictionary, previous: String) -> Array:
	if not _can_spar(s).is_empty():
		return [_option("spar_leave", "离开", "离开。", "close")] if previous.is_empty() else []
	if previous.is_empty():
		return _follow_rows(npc_id, _reward_claimed_today(s, npc_id, data))
	return []

static func _follow_rows(npc_id: String, claimed: bool) -> Array:
	if claimed:
		return [
			_option("spar_go:" + npc_id, "继续挑战", "切磋开始。", "start_spar", npc_id),
			_option("spar_leave", "离开", "离开。", "close"),
		]
	return [
		_option("spar_go:" + npc_id, "开始切磋", "切磋开始。", "start_spar", npc_id),
		_option("spar_later", "暂时不了", "暂时不了。", "close"),
	]

static func _reward_claimed_today(s: Dictionary, npc_id: String, data: Dictionary) -> bool:
	return int(_spar(s).get("reward_day", {}).get(npc_id, -1)) == game_day(s, data)

static func _zhou_line(s: Dictionary, data: Dictionary, bump: bool) -> String:
	var state := _promotion_state(s, data)
	match state:
		"inner":
			return "你已是内门弟子，无须再参加此项考核。"
		"report":
			return "考核已通过，从今日起，你便是青岳宗内门弟子。"
		"enrolled":
			return "报名已完成，去演武场参加考核吧。"
		"cooldown":
			return "此次未能通过，三日后可以重新报名。\n冷却剩余：%d 个游戏日。" % _cooldown_left(s, data)
		"cooldown_done":
			return "可以再次参加考核了，准备好了吗？"
		"short":
			return "你尚未达到晋升条件，先去修炼或积累功绩吧。\n" + _missing_text(s, data)
		_:
			if bump:
				var visits := _bump_visit(_promotion(s), "ordinary")
				return "想晋升内门，须有足够的修为、功绩，并通过实战考核。" if visits <= 1 else "考虑好参加内门考核了吗？"
			var seen := int(_promotion(s).get("visits", {}).get("ordinary", 0))
			return "想晋升内门，须有足够的修为、功绩，并通过实战考核。" if seen <= 1 else "考虑好参加内门考核了吗？"

static func _zhou_options(s: Dictionary, data: Dictionary, previous: String) -> Array:
	if previous == "promo_apply" or previous == "promo_retry":
		if _gaps(s, data).is_empty():
			return [
				_option("promo_confirm", "确认报名", "报名已完成，去演武场参加考核吧。", "enroll"),
				_option("promo_later", "暂时不了", "暂时不了。", "close"),
			]
		return [
			_option("promo_conditions", "查看条件", _condition_text(s, data), "reply"),
			_option("promo_leave", "离开", "离开。", "close"),
		]
	if previous == "promo_confirm":
		return [
			_option("promo_go", "前往考核", "报名已完成，去演武场参加考核吧。", "open_exam"),
			_option("promo_wait", "稍后再去", "稍后再去。", "close"),
		]
	if previous == "promo_short":
		return [
			_option("promo_conditions", "查看条件", _condition_text(s, data), "reply"),
			_option("promo_leave", "离开", "离开。", "close"),
		]
	if not previous.is_empty() and previous != "promo_conditions":
		return []
	match _promotion_state(s, data):
		"inner":
			return [_option("promo_end", "结束", "结束。", "close")]
		"report":
			return [
				_option("promo_claim", "领取晋升结果", "", "claim"),
				_option("promo_later", "稍后再说", "稍后再说。", "close"),
			]
		"enrolled":
			return [
				_option("promo_go", "前往考核", "报名已完成，去演武场参加考核吧。", "open_exam"),
				_option("promo_wait", "稍后再去", "稍后再去。", "close"),
			]
		"cooldown":
			return [_option("promo_leave", "离开", "离开。", "close")]
		"cooldown_done":
			return [
				_option("promo_retry", "重新报名", "", "reply"),
				_option("promo_leave", "离开", "离开。", "close"),
			]
		"short":
			return [
				_option("promo_conditions", "查看条件", _condition_text(s, data), "reply"),
				_option("promo_leave", "离开", "离开。", "close"),
			]
		_:
			return [
				_option("promo_apply", "申请考核", "", "reply"),
				_option("promo_conditions", "查看条件", _condition_text(s, data), "reply"),
				_option("promo_leave", "离开", "离开。", "close"),
			]

static func _exam_line(s: Dictionary, data: Dictionary, bump: bool) -> String:
	var promo := _promotion(s)
	if promo.get("pending_report", false) == true:
		return "考核通过，去向周长老复命吧。"
	if promo.get("completed", false) == true or rank(s) == "inner":
		return "你已是内门弟子，无须再参加此项考核。"
	if not bool(promo.get("enrolled", false)):
		if _cooling(s, data):
			return "此次考核结束，下次再来。"
		return "请先向周长老报名。"
	if bump:
		var visits := _bump_visit(promo, "exam")
		return "这次由我担任考核对手，准备好了吗？" if visits <= 1 else "这次由我担任考核对手，准备好了吗？"
	return "这次由我担任考核对手，准备好了吗？"

static func _exam_options(s: Dictionary, previous: String) -> Array:
	if not previous.is_empty():
		return []
	var promo := _promotion(s)
	if promo.get("pending_report", false) == true or promo.get("completed", false) == true or rank(s) == "inner" or not bool(promo.get("enrolled", false)):
		return [_option("exam_leave", "稍后再来", "稍后再来。", "close")]
	return [
		_option("exam_start", "开始考核", "考核开始。", "start_exam"),
		_option("exam_later", "稍后再来", "稍后再来。", "close"),
	]

static func _start_spar(s: Dictionary, npc_id: String, data: Dictionary, battle: RefCounted, identity: String) -> String:
	var reason := _spar_presence(s, npc_id, data)
	if not reason.is_empty():
		return reason
	_spar(s).summon = npc_id
	var error: String = battle.start_npc_duel(s, s.npcs[npc_id], data, identity, "sect_spar")
	if not error.is_empty():
		_spar(s).summon = ""
		return error
	s.last_result = "切磋开始。"
	return ""

static func _start_exam(s: Dictionary, data: Dictionary, battle: RefCounted, identity: String) -> String:
	var reason := _exam_presence(s, data)
	if not reason.is_empty():
		return reason
	var error: String = battle.start_npc_duel(s, s.npcs[MENG], data, identity, "sect_exam")
	if not error.is_empty():
		return error
	s.last_result = "考核开始。"
	return ""

static func _spar_presence(s: Dictionary, npc_id: String, data: Dictionary) -> String:
	var reason := _can_spar(s)
	if not reason.is_empty():
		return reason
	if not SPARRING.has(npc_id):
		return "不能与此人切磋"
	if not s.battle.is_empty():
		return "请先结束当前战斗"
	var npc: Dictionary = s.get("npcs", {}).get(npc_id, {})
	if npc.is_empty() or npc.get("alive", false) != true:
		return "对方无法应战"
	if str(npc.get("location", "")) != str(s.player.location) or str(s.player.location) != GATE:
		return "请先前往青岳宗演武场"
	if str(npc.get("sect", "")) != SECT:
		return "对方不是青岳宗弟子"
	if _restricted(npc, data, s):
		return "尚未获得此人物所在区域的通行权限"
	if str(npc.get("sect_area", "")) == OUTER and str(npc.get("sect_building", "")) == ARENA:
		return ""
	if str(npc.get("sect_area", "")) != OUTER:
		return "对方不在演武场"
	return ""

static func _exam_presence(s: Dictionary, data: Dictionary) -> String:
	if str(s.get("sect", "")) != SECT or rank(s) != "outer":
		return "只有青岳宗外门弟子可以参加考核"
	if not s.battle.is_empty():
		return "请先结束当前战斗"
	var promo := _promotion(s)
	if promo.get("completed", false) == true:
		return "你已是内门弟子，无须再参加此项考核。"
	if promo.get("pending_report", false) == true:
		return "考核已通过，请向周玄复命"
	if not bool(promo.get("enrolled", false)):
		return "请先向周玄报名"
	if _cooling(s, data):
		return "考核仍在冷却中"
	var npc: Dictionary = s.get("npcs", {}).get(MENG, {})
	if npc.is_empty() or npc.get("alive", false) != true:
		return "考核对手无法应战"
	if str(s.player.location) != GATE or str(npc.get("location", "")) != GATE:
		return "请先前往青岳宗演武场"
	if str(npc.get("sect_area", "")) != OUTER or str(npc.get("sect_building", "")) != ARENA:
		return "考核对手不在演武场"
	if _restricted(npc, data, s):
		return "尚未获得此人物所在区域的通行权限"
	return ""

static func _can_spar(s: Dictionary) -> String:
	if str(s.get("sect", "")) != SECT:
		return "需先加入青岳宗"
	if rank(s) not in ["outer", "inner"]:
		return "需具备外门弟子或更高身份"
	if not s.battle.is_empty():
		return "请先结束当前战斗"
	return ""

static func _enroll(s: Dictionary, data: Dictionary) -> String:
	var promo := _promotion(s)
	if promo.get("completed", false) == true or rank(s) == "inner":
		return "你已是内门弟子，无须再参加此项考核。"
	if bool(promo.get("enrolled", false)):
		s.last_result = "报名已完成，去演武场参加考核吧。"
		return ""
	if _cooling(s, data):
		return "考核仍在冷却中"
	var gaps := _gaps(s, data)
	if not gaps.is_empty():
		s.last_result = "你尚未达到晋升条件，先去修炼或积累功绩吧。\n" + "\n".join(gaps)
		return "你尚未达到晋升条件"
	if int(s.get("contribution", 0)) < FEE:
		return "宗门贡献不足"
	s.contribution = int(s.contribution) - FEE
	promo.enrolled = true
	promo.fee_paid = FEE
	promo.result = ""
	promo.pending_report = false
	s.last_result = "报名已完成，去演武场参加考核吧。"
	return ""

static func _claim(s: Dictionary) -> String:
	var promo := _promotion(s)
	if promo.get("reward_claimed", false) == true or rank(s) == "inner":
		return "晋升奖励已经领取"
	if promo.get("pending_report", false) != true or str(promo.get("result", "")) != "win":
		return "考核尚未通过"
	if str(s.get("sect", "")) != SECT or rank(s) != "outer":
		return "只有青岳宗外门弟子可以领取晋升"
	s.sect_rank = "inner"
	s.contribution = int(s.get("contribution", 0)) + PROMOTION_CONTRIBUTION
	promo.completed = true
	promo.reward_claimed = true
	promo.pending_report = false
	promo.enrolled = false
	promo.meng_mode = "spar"
	s.last_result = "考核已通过，从今日起，你便是青岳宗内门弟子。\n宗门贡献 +%d" % PROMOTION_CONTRIBUTION
	return ""

static func _spar_reward(s: Dictionary, npc_id: String, data: Dictionary) -> Dictionary:
	var profile: Dictionary = SPARRING[npc_id]
	var record := _spar(s)
	var first := not bool(record.first_win.get(npc_id, false))
	var claimed := int(record.reward_day.get(npc_id, -1)) == game_day(s, data)
	if claimed:
		return {"contribution": 0, "favor": 0, "favor_applied": 0, "text": NO_REWARD}
	if first:
		return {"contribution": int(profile.first_contribution), "favor": int(profile.first_favor), "favor_applied": 0, "text": ""}
	return {"contribution": int(profile.daily_contribution), "favor": int(profile.daily_favor), "favor_applied": 0, "text": ""}

static func _reward_text(contribution: int, favor: int) -> String:
	var parts: Array[String] = []
	if contribution > 0:
		parts.append("宗门贡献 +%d" % contribution)
	if favor > 0:
		parts.append("好感 +%d" % favor)
	return "\n".join(parts) if not parts.is_empty() else NO_REWARD

static func _adjust_favor(s: Dictionary, npc_id: String, delta: int) -> int:
	if delta == 0 or not s.npcs.has(npc_id):
		return 0
	var npc: Dictionary = s.npcs[npc_id]
	if not npc.get("relations") is Dictionary:
		npc.relations = {}
	var current: Variant = npc.relations.get(s.player.id, 0)
	if not (current is int or (current is float and is_finite(float(current)))):
		return 0
	var updated := clampi(int(current) + delta, -100, 100)
	var applied := updated - int(current)
	npc.relations[s.player.id] = updated
	return applied

static func _promotion_state(s: Dictionary, data: Dictionary) -> String:
	var promo := _promotion(s)
	if rank(s) == "inner" or promo.get("completed", false) == true:
		return "inner"
	if promo.get("pending_report", false) == true:
		return "report"
	if bool(promo.get("enrolled", false)):
		return "enrolled"
	if _cooling(s, data):
		return "cooldown"
	if int(promo.get("cooldown_until_day", -1)) >= 0:
		return "cooldown_done"
	if not _gaps(s, data).is_empty():
		return "short"
	return "ready"

static func _cooling(s: Dictionary, data: Dictionary) -> bool:
	var until := int(_promotion(s).get("cooldown_until_day", -1))
	return until >= 0 and game_day(s, data) < until

static func _cooldown_left(s: Dictionary, data: Dictionary) -> int:
	return maxi(0, int(_promotion(s).get("cooldown_until_day", 0)) - game_day(s, data))

static func _gaps(s: Dictionary, data: Dictionary) -> Array:
	var gaps: Array = []
	if str(s.get("sect", "")) != SECT:
		gaps.append("宗门：需加入青岳宗")
	elif rank(s) != "outer":
		gaps.append("身份：需为外门弟子（当前：%s）" % (member_title(s, SECT) if not member_title(s, SECT).is_empty() else "无"))
	if int(s.get("player", {}).get("realm", 0)) < REALM_REQUIRED and int(s.get("player", {}).get("growth", {}).get("body_level", 0)) < REALM_REQUIRED:
		gaps.append("修为：法修炼气六层或体修通脉六层（当前：%s）" % _realm_text(s, data))
	if merit(s) < MERIT_REQUIRED:
		gaps.append("累计任务功绩：%d/%d" % [merit(s), MERIT_REQUIRED])
	if quest_completions(s, data) < QUESTS_REQUIRED:
		gaps.append("已完成宗门任务：%d/%d" % [quest_completions(s, data), QUESTS_REQUIRED])
	if not bool(_promotion(s).get("enrolled", false)) and int(s.get("contribution", 0)) < FEE:
		gaps.append("可用宗门贡献：%d/%d" % [int(s.get("contribution", 0)), FEE])
	if str(s.get("sect", "")) == SECT and not sect_quests_exist(data, SECT):
		gaps.append("宗门任务尚未开放，晋升资格暂不可达")
	return gaps

static func _missing_text(s: Dictionary, data: Dictionary) -> String:
	var gaps := _gaps(s, data)
	return "\n".join(gaps) if not gaps.is_empty() else _condition_text(s, data)

static func _condition_text(s: Dictionary, data: Dictionary) -> String:
	var lines: Array[String] = ["晋升条件："]
	lines.append("宗门：青岳宗（%s）" % ("已满足" if str(s.get("sect", "")) == SECT else "未满足"))
	lines.append("身份：外门弟子（当前：%s）" % (member_title(s, str(s.get("sect", ""))) if not member_title(s, str(s.get("sect", ""))).is_empty() else "无"))
	lines.append("修为：法修炼气六层或体修通脉六层（当前：%s）" % _realm_text(s, data))
	lines.append("累计任务功绩：%d/%d" % [merit(s), MERIT_REQUIRED])
	lines.append("已完成宗门任务：%d/%d" % [quest_completions(s, data), QUESTS_REQUIRED])
	lines.append("可用宗门贡献：%d/%d" % [int(s.get("contribution", 0)), FEE])
	lines.append("考核费用：50 贡献，报名时扣除")
	lines.append("战斗考核：击败孟钧光")
	lines.append("失败冷却：3 个游戏日")
	if not sect_quests_exist(data, SECT):
		lines.append("宗门任务尚未开放，晋升资格暂不可达")
	return "\n".join(lines)

static func _realm_text(s: Dictionary, data: Dictionary) -> String:
	var cultivation := preload("res://gameplay/cultivation/cultivation_system.gd").new()
	var player: Dictionary = s.get("player", {})
	return "法修%s，体修%s" % [cultivation.realm_name(int(player.get("realm", 0)), "qi", data), cultivation.body_realm_name(player, data)]

static func _restricted(npc: Dictionary, data: Dictionary, state: Dictionary) -> bool:
	var area_id := str(npc.get("sect_area", ""))
	if area_id.is_empty():
		return false
	for area in data.get("sect_areas", {}).get(str(npc.get("sect", "")), []):
		if str(area.get("id", "")) != area_id:
			continue
		if str(area.get("restriction", "")).is_empty():
			return false
		return not (area_id == INNER and str(state.get("sect_rank", "")) == "inner" and str(state.get("sect", "")) == str(npc.get("sect", "")))
	return true

static func _completion_count(runtime: Dictionary) -> int:
	var count := int(runtime.get("completed_count", 0))
	if count > 0:
		return count
	return 1 if str(runtime.get("status", "")) == "COMPLETED" else 0

static func _bump_visit(record: Dictionary, key: String) -> int:
	if not record.get("visits") is Dictionary:
		record.visits = {}
	record.visits[key] = int(record.visits.get(key, 0)) + 1
	return int(record.visits[key])

static func _spar(s: Dictionary) -> Dictionary:
	if not s.get("sect_spar") is Dictionary:
		s.sect_spar = {}
	var record: Dictionary = s.sect_spar
	for key in ["visits", "first_win", "reward_day"]:
		if not record.get(key) is Dictionary:
			record[key] = {}
	if not record.has("summon"):
		record.summon = ""
	if not record.get("last") is Dictionary:
		record.last = {}
	return record

static func _promotion(s: Dictionary) -> Dictionary:
	if not s.get("sect_promotion") is Dictionary:
		s.sect_promotion = {}
	var promo: Dictionary = s.sect_promotion
	if not promo.get("visits") is Dictionary:
		promo.visits = {}
	if not promo.has("meng_mode"):
		promo.meng_mode = "spar"
	if not promo.has("enrolled"):
		promo.enrolled = false
	if not promo.has("fee_paid"):
		promo.fee_paid = 0
	if not promo.has("result"):
		promo.result = ""
	if not promo.has("cooldown_until_day"):
		promo.cooldown_until_day = -1
	if not promo.has("pending_report"):
		promo.pending_report = false
	if not promo.has("completed"):
		promo.completed = false
	if not promo.has("reward_claimed"):
		promo.reward_claimed = false
	return promo

static func _option(id: String, label: String, response: String, kind: String, target: String = "") -> Dictionary:
	return {"id": id, "label": label, "response": response, "kind": kind, "target": target, "system": "sect_arena", "quest": ""}

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and float(value) == floor(float(value))

static func _validate_spar(value: Variant) -> String:
	if not value is Dictionary:
		return "切磋记录无效"
	for key in ["visits", "first_win", "reward_day", "last"]:
		if value.has(key) and not value[key] is Dictionary:
			return "切磋记录无效"
	if value.has("summon") and not value.summon is String:
		return "切磋记录无效"
	for npc_id in value.get("reward_day", {}):
		if not _whole(value.reward_day[npc_id]):
			return "切磋日期无效"
	for npc_id in value.get("visits", {}):
		if not _whole(value.visits[npc_id]):
			return "切磋对话记录无效"
	for npc_id in value.get("first_win", {}):
		if not value.first_win[npc_id] is bool:
			return "切磋首胜记录无效"
	return ""

static func _validate_promotion(value: Variant, s: Dictionary) -> String:
	if not value is Dictionary:
		return "晋升记录无效"
	if value.has("visits") and not value.visits is Dictionary:
		return "晋升记录无效"
	for key in ["enrolled", "pending_report", "completed", "reward_claimed"]:
		if value.has(key) and not value[key] is bool:
			return "晋升记录无效"
	if value.has("fee_paid") and not _whole(value.fee_paid):
		return "考核费用记录无效"
	if value.has("cooldown_until_day") and not (value.cooldown_until_day is int or value.cooldown_until_day is float):
		return "考核冷却无效"
	if value.has("result") and str(value.result) not in ["", "win", "lose"]:
		return "考核结果无效"
	if value.has("meng_mode") and str(value.meng_mode) not in ["spar", "exam"]:
		return "考核入口无效"
	if value.get("completed", false) == true and str(s.get("sect_rank", "")) != "inner":
		return "晋升记录与职级不符"
	if value.get("reward_claimed", false) == true and value.get("completed", false) != true:
		return "晋升奖励记录无效"
	if value.get("pending_report", false) == true and str(value.get("result", "")) != "win":
		return "待复命记录无效"
	if value.get("enrolled", false) == true and int(value.get("fee_paid", 0)) != FEE:
		return "报名费用记录无效"
	return ""
