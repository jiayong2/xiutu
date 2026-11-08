extends RefCounted

const DEFINITIONS = preload("res://data/fortunes/catalog.gd").DEFINITIONS

static func valid_selection(id: String) -> bool:
	if id.is_empty():
		return true
	var definition: Dictionary = DEFINITIONS.get(id,{})
	return definition.get("kind") == "innate" and definition.acquisition.connected

static func grant(actor: Dictionary, id: String, timestamp: int, source: String, day_seconds: int = 86400) -> bool:
	if not DEFINITIONS.has(id) or actor.get("fortunes",{}).has(id):
		return false
	var definition: Dictionary = DEFINITIONS[id]
	var group: String = definition.exclusive_group
	for held in actor.get("fortunes",{}):
		if not group.is_empty() and DEFINITIONS[held].exclusive_group == group:
			return false
	if not actor.has("fortunes"):
		actor.fortunes = {}
	var record := {"obtained_at":timestamp,"source":source}
	if definition.duration.type == "timed":
		record.expires_at = timestamp + int(definition.duration.days) * day_seconds
	actor.fortunes[id] = record
	return true

static func end_battle(actor: Dictionary) -> void:
	for id in actor.get("fortunes",{}).keys():
		if DEFINITIONS[id].duration.type == "battle":
			remove(actor,id)

static func remove(actor: Dictionary, id: String) -> bool:
	return actor.get("fortunes",{}).erase(id)

static func next_expiry(actor: Dictionary, limit: int) -> int:
	for record in actor.get("fortunes",{}).values():
		if record.has("expires_at"):
			limit = mini(limit,int(record.expires_at))
	return limit

static func expire(actor: Dictionary, timestamp: int) -> bool:
	var changed := false
	for id in actor.get("fortunes",{}).keys():
		var record: Dictionary = actor.fortunes[id]
		if record.has("expires_at") and int(record.expires_at) <= timestamp:
			changed = remove(actor,id) or changed
	return changed

static func record_event(actor: Dictionary, event: String, timestamp: int, day_seconds: int, source: String, target: String = "") -> Array[String]:
	var awarded: Array[String] = []
	for id in DEFINITIONS:
		var rule: Dictionary = DEFINITIONS[id].acquisition
		if not rule.connected or rule.event != event or (rule.has("targets") and target not in rule.targets):
			continue
		var threshold: int = rule.threshold
		if id == "battle_veteran":
			var wins := int(actor.get("fortune_wins",0))
			actor.fortune_wins = mini(wins+1,threshold)
			if wins+1 != threshold:
				continue
		elif threshold > 1:
			if not actor.has("fortune_progress"):
				actor.fortune_progress = {}
			var progress: Dictionary = actor.fortune_progress
			var count := int(progress.get(id,0))
			progress[id] = mini(count+1,threshold)
			if count+1 != threshold:
				continue
			if DEFINITIONS[id].duration.type == "timed":
				progress[id] = 0
		if grant(actor,id,timestamp,source,day_seconds):
			awarded.append(DEFINITIONS[id].name)
	return awarded

static func valid_state(actor: Dictionary, timestamp: int, in_battle: bool = false, max_innate: int = 1) -> bool:
	var records: Variant = actor.get("fortunes",{})
	var wins: Variant = actor.get("fortune_wins",0)
	var progress: Variant = actor.get("fortune_progress",{})
	if not records is Dictionary or not progress is Dictionary or not valid_integer(wins) or wins > 50:
		return false
	if records.has("battle_veteran") and wins != 50:
		return false
	for id in progress:
		if not DEFINITIONS.has(id) or not valid_integer(progress[id]) or progress[id] > DEFINITIONS[id].acquisition.threshold:
			return false
	var innate := 0
	var groups := {}
	for id in records:
		var record: Variant = records[id]
		if not DEFINITIONS.has(id) or not record is Dictionary:
			return false
		if not valid_integer(record.get("obtained_at")) or record.obtained_at > timestamp or not record.get("source") is String or record.source.is_empty():
			return false
		var definition: Dictionary = DEFINITIONS[id]
		if definition.duration.type == "battle" and not in_battle:
			return false
		if definition.duration.type == "timed":
			if not valid_integer(record.get("expires_at")) or record.expires_at <= timestamp:
				return false
		elif record.has("expires_at"):
			return false
		var group: String = definition.exclusive_group
		if not group.is_empty():
			if groups.has(group):
				return false
			groups[group] = true
		if definition.kind == "innate":
			innate += 1
	return innate <= max_innate

static func is_active(actor: Dictionary, id: String) -> bool:
	if not DEFINITIONS[id].group.contains("特殊传承"):
		return true
	var priority := 0
	for held in actor.get("fortunes",{}):
		if held < id and DEFINITIONS[held].group.contains("特殊传承"):
			priority += 1
	return priority < 2

static func modifier(actor: Dictionary, type: String, target: String = "", unit: String = "%") -> int:
	var total := 0
	var permanent := 0
	var cap := 30 if type == "cultivation_gain" else 25 if type == "damage" else 0
	for id in actor.get("fortunes",{}):
		if not is_active(actor,id):
			continue
		var definition: Dictionary = DEFINITIONS[id]
		for effect in definition.effects:
			if not effect.implemented or effect.type != type or effect.unit != unit:
				continue
			var scope: Array = effect.elements if not effect.elements.is_empty() else effect.targets
			if not scope.is_empty() and target not in scope:
				continue
			if cap > 0 and definition.kind == "acquired" and definition.duration.type == "permanent" and effect.value > 0 and not definition.group.contains("特殊传承"):
				permanent += int(effect.value)
			else:
				total += int(effect.value)
	return total + mini(permanent,cap)

static func describe(definition: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray(["%s · %s" % [definition.name,definition.quality]])
	for effect in definition.effects:
		var suffix := "" if effect.implemented else "（相关玩法尚未开放）"
		if effect.has("scope"):
			suffix = "（%s）" % effect.scope
		lines.append(str(effect.description) + suffix)
	if not definition.removal.is_empty():
		lines.append("解除条件：%s" % definition.removal)
	return lines

static func debug_report() -> String:
	var lines := PackedStringArray(["气运依赖 · A 可用 / B 待补齐 / C 基础触发待接 / D 未来玩法 / E 规则冲突"])
	for id in DEFINITIONS:
		var definition: Dictionary = DEFINITIONS[id]
		lines.append("%s [%s] %s" % [definition.name,id,"来源已接通" if definition.acquisition.connected else "来源待接入"])
		for effect in definition.effects:
			lines.append("  %s · %s · %s · %s" % [effect.id,effect.status,effect.dependency,effect.description])
	return "\n".join(lines)

static func use_battle_trigger(battle: Dictionary, effect_type: String, once_per_battle: bool) -> bool:
	if not battle.has("fortune_triggers"):
		battle.fortune_triggers = {}
	var marker: int = 0 if once_per_battle else int(battle.turn)
	if battle.fortune_triggers.get(effect_type,-1) == marker:
		return false
	battle.fortune_triggers[effect_type] = marker
	return true

static func valid_battle_triggers(battle: Dictionary) -> bool:
	var triggers: Variant = battle.get("fortune_triggers",{})
	if not triggers is Dictionary:
		return false
	for key in triggers:
		if key not in ["lightning_first_hit"] or not valid_integer(triggers[key]) or triggers[key] > battle.turn:
			return false
	return true

static func consume(actor: Dictionary, id: String) -> bool:
	return DEFINITIONS.has(id) and DEFINITIONS[id].duration.type == "once" and remove(actor,id)

static func valid_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(float(value))
