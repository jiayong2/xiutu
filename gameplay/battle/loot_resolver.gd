extends RefCounted
## Monster loot resolution. Every monster uses one configurable `loot` table;
## there is no per-monster branch in the battle code.

static func roll(monster: Dictionary, data: Dictionary, random: RefCounted, claimed: Dictionary) -> Dictionary:
	var loot: Dictionary = monster.get("loot", {})
	return _roll_table(monster, loot, data, random, claimed)

static func _roll_table(monster: Dictionary, loot: Dictionary, data: Dictionary, random: RefCounted, claimed: Dictionary) -> Dictionary:
	var drops := {}
	var money: Array = loot.get("money", [0, 0])
	var stones: int = random.integer("loot", int(money[0]), int(money[1])) if money.size() == 2 else 0
	for entry in loot.get("entries", []):
		if not entry is Dictionary or not _conditions_met(monster, entry.get("conditions", {}), data):
			continue
		var once_key := str(entry.get("once", ""))
		var flag := "%s:%s" % [str(monster.get("id", "")), once_key] if not once_key.is_empty() else ""
		if not flag.is_empty() and claimed.get(flag, false):
			continue
		var guaranteed := bool(entry.get("guaranteed", false))
		if not guaranteed and random.roll("loot") >= float(entry.get("chance", 0.0)):
			continue
		var minimum := maxi(1, int(entry.get("min", 1)))
		var maximum := maxi(minimum, int(entry.get("max", minimum)))
		var quantity := minimum
		if maximum > minimum:
			quantity = random.integer("loot", minimum, maximum)
		if quantity <= 0:
			continue
		var item := str(entry.get("item_id", ""))
		if item.is_empty():
			continue
		drops[item] = int(drops.get(item, 0)) + quantity
		if not flag.is_empty():
			claimed[flag] = true
	return {"money": stones, "drops": drops}

static func _conditions_met(monster: Dictionary, conditions: Dictionary, data: Dictionary) -> bool:
	if conditions.is_empty():
		return true
	if conditions.has("rank"):
		var ranks: Array = conditions.rank
		if str(monster.get("rank", "normal")) not in ranks:
			return false
	if conditions.has("realm_min") and int(monster.get("realm", 0)) < int(conditions.realm_min):
		return false
	return true
