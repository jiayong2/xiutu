extends RefCounted

const PLAYER := ["guard","sword_intent","flame_force","rock_shield","wind_force","focus","spring","wind_step","life","discount","stand","wind_ready","thunder_force","thunder_echo","ice_armor"]
const SHIELDS := ["rock_shield", "ice_armor"]
const PLAYER_NEGATIVE := ["player_poison","player_burn","player_corrosion","player_bleed","player_stun","player_root","player_silence","player_attack_down","player_defense_down","player_speed_down"]

static func is_player(id: String) -> bool:
	return id in PLAYER or id in PLAYER_NEGATIVE or id.begins_with("player_")

static func layers(b: Dictionary, id: String) -> int:
	var status: Dictionary = b.status.get(id,{})
	return 0 if status.is_empty() else int(status.get("layers",1))

static func consume(b: Dictionary, id: String, count: int = 999) -> int:
	var used := mini(count,layers(b,id))
	if used > 0:
		var remaining := layers(b,id)-used
		if remaining > 0:
			b.status[id].layers = remaining
		else:
			b.status.erase(id)
	return used

static func apply(b: Dictionary, id: String, config: Dictionary, attack: float, count: int = 1, extra: Dictionary = {}) -> void:
	var rule: Dictionary = config.statuses[id.trim_prefix("player_")]
	var total := mini(int(rule.max), layers(b,id)+count)
	b.status[id] = {"turns":int(rule.turns),"layers":total,"attack":attack,"applied_round":b.turn,"applied_actor":b.get("acting","player")}
	b.status[id].merge(extra,true)

static func tick(b: Dictionary, id: String) -> void:
	b.status[id].turns -= 1
	if b.status[id].turns <= 0:
		b.status.erase(id)

static func visible(statuses: Dictionary, player: bool) -> Dictionary:
	var result := {}
	for id in statuses:
		if is_player(id) == player:
			result[id] = statuses[id].duplicate(true)
	return result

static func ratio(b: Dictionary, id: String, config: Dictionary) -> float:
	return layers(b,id)*float(config.statuses[id.trim_prefix("player_")].value)

## Generic side-aware stat modifier shared by monsters, NPCs and the player.
## Positive statuses use <stat>_up and negative ones <stat>_down.
static func stat_modifier(b: Dictionary, side: String, stat: String, config: Dictionary) -> float:
	var total := 0.0
	for id in b.status:
		if is_player(id) != (side == "player"):
			continue
		var key: String = str(id).trim_prefix("player_")
		if key != stat + "_up" and key != stat + "_down":
			continue
		var rule: Dictionary = config.statuses.get(key, {})
		var value: float = float(rule.get("value", 0)) * layers(b, str(id))
		value += float(b.status[id].get("flat", 0))
		total += value if key == stat + "_up" else -value
	return total

static func reduction(b: Dictionary, side: String, config: Dictionary) -> float:
	var total := 0.0
	for id in b.status:
		if is_player(id) != (side == "player"):
			continue
		if str(id).trim_prefix("player_") != "damage_reduction":
			continue
		total += float(config.statuses.damage_reduction.value) * layers(b, str(id))
		total += float(b.status[id].get("flat", 0))
	return total

static func shield_id(b: Dictionary) -> String:
	for id in SHIELDS:
		if b.status.has(id):
			return id
	return ""

static func create_shield(b: Dictionary, id: String, config: Dictionary, stats: Dictionary, e: Dictionary) -> void:
	var amount := mini(floori(stats.attack*e.shield),floori(stats.hp*config.shield_cap))
	for shield in SHIELDS:
		b.status.erase(shield)
	if amount > 0:
		apply(b,id,config,stats.attack,1,{"amount":amount,"maximum":amount,"effects":e})

static func dot(b: Dictionary, id: String, config: Dictionary) -> int:
	var status: Dictionary = b.status.get(id, {})
	var amount := floori(float(status.get("attack", 0)) * ratio(b, id, config))
	if status.has("flat"):
		amount += int(status.flat) * maxi(1, layers(b, id))
	return amount

static func valid(id: String, status: Variant, data: Dictionary) -> bool:
	if not status is Dictionary or not _number(status.get("turns"), true):
		return false
	if id == "guard":
		return _number(status.get("amount"))
	var key := id.trim_prefix("player_")
	if not data.spell_growth.statuses.has(key) or (id != key and not id.begins_with("player_")):
		return false
	if id in ["burn","wet"] and not status.has("layers"):
		return true
	var rule: Dictionary = data.spell_growth.statuses[key]
	if not _number(status.get("layers"),true) or status.layers < 1 or status.layers > rule.max or status.turns > int(rule.get("max_turns", rule.turns)):
		return false
	if not _number(status.get("attack")) or not _number(status.get("applied_round"),true):
		return false
	if status.get("applied_actor","player") not in ["player","enemy"]:
		return false
	for field in ["amount","maximum","value","triggers"]:
		if status.has(field) and not _number(status[field]):
			return false
	if id in SHIELDS or id == "enemy_shield":
		if not _number(status.get("amount"),true) or not _number(status.get("maximum"),true) or status.amount > status.maximum:
			return false
	if status.has("effects"):
		if not status.effects is Dictionary:
			return false
		for effect in status.effects:
			if not status.effects[effect] is String and not _number(status.effects[effect]):
				return false
	return true

static func _number(value: Variant, whole: bool = false) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0 and (not whole or floorf(value)==value)
