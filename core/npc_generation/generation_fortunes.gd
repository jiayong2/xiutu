@tool
extends RefCounted

const Config := preload("res://core/npc_generation/generation_config.gd")
const Fortune := preload("res://gameplay/character/player_fortunes.gd")
const STREAM := "world"

static func apply(random: RefCounted, config: Dictionary, npc: Dictionary) -> String:
	var actor := {}
	var innate := pick(random, config.innate_fortune, ["innate"], false, actor)
	if not innate.error.is_empty():
		return innate.error
	var acquired := pick(random, config.acquired_fortune, ["acquired"], config.acquired_fortune.get("allow_negative", false) == true, actor)
	if not acquired.error.is_empty():
		return acquired.error
	npc.fortune_ids = innate.ids + acquired.ids
	return ""

static func pick(random: RefCounted, rules: Dictionary, kinds: Array, allow_negative: bool, actor: Dictionary) -> Dictionary:
	var span := Config.range_of(rules.get("count"))
	var required: Array = Config.string_ids(rules.get("required_ids"))
	if span.max <= 0 and required.is_empty():
		return {"error": "", "ids": []}
	if required.size() > span.max:
		return {"error": "必带气运数量超出总数量上限", "ids": []}
	var needed: int = random.integer(STREAM, span.min, span.max) if span.max >= span.min else span.min
	needed = maxi(needed, required.size())
	if needed <= 0:
		return {"error": "", "ids": []}
	var pool := candidates(rules, kinds, allow_negative)
	var selected: Array = []
	for id in required:
		var error := _take(id, pool, selected, actor, "必带")
		if not error.is_empty():
			return {"error": error, "ids": []}
	var at_least: Dictionary = rules.get("at_least", {})
	var high_quality := str(at_least.get("quality", ""))
	var high_need := maxi(0, int(at_least.get("count", 0)) - _high_count(selected, high_quality))
	var remaining := needed - selected.size()
	if high_need > remaining:
		return {"error": "高品质气运数量无法包含在总数量 %d～%d 内" % [span.min, span.max], "ids": []}
	if high_need > 0:
		var high_pool := _high_pool(pool, high_quality)
		if high_pool.size() < high_need:
			return {"error": "符合品质条件的气运不足，要求 %d 条，当前仅 %d 条。" % [int(at_least.count), _high_count(selected, high_quality) + high_pool.size()], "ids": []}
		var error := _fill(random, pool, selected, actor, high_need, rules.get("quality_weights", {}), high_quality)
		if not error.is_empty():
			return {"error": error, "ids": []}
	remaining = needed - selected.size()
	if remaining > 0:
		var error := _fill(random, pool, selected, actor, remaining, rules.get("quality_weights", {}), "")
		if not error.is_empty():
			return {"error": error, "ids": []}
	return {"error": "", "ids": selected}

static func candidates(rules: Dictionary, kinds: Array, allow_negative: bool) -> Array:
	var excluded: Array = Config.string_ids(rules.get("excluded_ids"))
	var result: Array = []
	for id in Fortune.DEFINITIONS:
		if _eligible(id, rules, kinds, allow_negative, excluded):
			result.append(id)
	return result

static func catalog_errors(rules: Dictionary, field: String, kinds: Array, allow_negative: bool) -> Array:
	var issues: Array = []
	var span := Config.range_of(rules.get("count"))
	if span.min < 0 or span.max < span.min:
		issues.append({"code": "RANGE", "message": "气运数量范围无效", "field": field + ".count"})
	var min_quality := str(rules.get("min_quality", ""))
	var max_quality := str(rules.get("max_quality", ""))
	if not min_quality.is_empty() and Config.fortune_rank(min_quality) < 0:
		issues.append({"code": "QUALITY", "message": "气运最低品质不是现有品质：" + min_quality, "field": field + ".min_quality"})
	if not max_quality.is_empty() and Config.fortune_rank(max_quality) < 0:
		issues.append({"code": "QUALITY", "message": "气运最高品质不是现有品质：" + max_quality, "field": field + ".max_quality"})
	if Config.fortune_rank(min_quality) >= 0 and Config.fortune_rank(max_quality) >= 0 and Config.fortune_rank(min_quality) > Config.fortune_rank(max_quality):
		issues.append({"code": "QUALITY", "message": "气运最低品质高于最高品质", "field": field})
	var at_least: Dictionary = rules.get("at_least", {})
	var high_quality := str(at_least.get("quality", ""))
	var high_count := int(at_least.get("count", 0))
	if high_count < 0:
		issues.append({"code": "COUNT", "message": "指定品质至少条数不能为负", "field": field + ".at_least"})
	if high_count > 0:
		if Config.fortune_rank(high_quality) < 0:
			issues.append({"code": "QUALITY", "message": "指定品质不是现有品质：" + high_quality, "field": field + ".at_least"})
		if high_count > span.max:
			issues.append({"code": "COUNT", "message": "高品质条数超出总数量上限", "field": field + ".at_least"})
	var required: Array = Config.string_ids(rules.get("required_ids"))
	var excluded: Array = Config.string_ids(rules.get("excluded_ids"))
	for id in required:
		if id in excluded:
			issues.append({"code": "CONFLICT", "message": "必带气运与排除气运冲突：" + id, "field": field})
		var row: Dictionary = Fortune.DEFINITIONS.get(id, {})
		if row.is_empty():
			issues.append({"code": "REF", "message": "必带气运不存在：" + id, "field": field + ".required_ids"})
		elif not _eligible(id, rules, kinds, allow_negative, []):
			issues.append({"code": "REF", "message": "必带气运不符合该栏规则：" + id, "field": field + ".required_ids"})
	for id in excluded:
		if not Fortune.DEFINITIONS.has(id):
			issues.append({"code": "REF", "message": "排除气运不存在：" + id, "field": field + ".excluded_ids"})
	if required.size() > span.max:
		issues.append({"code": "COUNT", "message": "必带气运数量超出总数量上限", "field": field + ".required_ids"})
	var pool := candidates(rules, kinds, allow_negative)
	if span.min > 0 and pool.size() < span.min:
		issues.append({"code": "POOL", "message": "符合品质条件的气运不足，要求 %d 条，当前仅 %d 条。" % [span.min, pool.size()], "field": field + ".count"})
	if high_count > 0 and Config.fortune_rank(high_quality) >= 0:
		var high_pool := _high_pool(pool, high_quality)
		if high_pool.size() < high_count:
			issues.append({"code": "POOL", "message": "符合品质条件的气运不足，要求 %d 条，当前仅 %d 条。" % [high_count, high_pool.size()], "field": field + ".at_least"})
	return issues

static func npc_errors(npc: Dictionary, rules: Dictionary, kinds: Array, allow_negative: bool, field: String) -> Array:
	var issues: Array = []
	var span := Config.range_of(rules.get("count"))
	if span.max <= 0 and Config.string_ids(rules.get("required_ids")).is_empty():
		return issues
	var selected: Array = []
	for id in npc.get("fortune_ids", []):
		var row: Dictionary = Fortune.DEFINITIONS.get(id, {})
		if row.get("kind") in kinds or (allow_negative and row.get("kind") == "negative"):
			selected.append(id)
	if selected.size() < span.min or selected.size() > span.max:
		issues.append({"code": "COUNT", "message": "气运条数不在 %d～%d" % [span.min, span.max], "field": field})
	for id in Config.string_ids(rules.get("required_ids")):
		if id not in selected:
			issues.append({"code": "REQUIRED", "message": "缺少必带气运：" + id, "field": field})
	for id in Config.string_ids(rules.get("excluded_ids")):
		if id in selected:
			issues.append({"code": "EXCLUDED", "message": "出现已排除气运：" + id, "field": field})
	var at_least: Dictionary = rules.get("at_least", {})
	var high_quality := str(at_least.get("quality", ""))
	if int(at_least.get("count", 0)) > 0 and _high_count(selected, high_quality) < int(at_least.count):
		issues.append({"code": "QUALITY", "message": "高品质气运不足，要求 %d 条，当前仅 %d 条。" % [int(at_least.count), _high_count(selected, high_quality)], "field": field})
	return issues

static func _eligible(id: String, rules: Dictionary, kinds: Array, allow_negative: bool, excluded: Array) -> bool:
	if id in excluded:
		return false
	var row: Dictionary = Fortune.DEFINITIONS.get(id, {})
	if row.is_empty() or row.get("duration", {}).get("type") != "permanent":
		return false
	var kind: String = str(row.get("kind", ""))
	if kind == "negative":
		return allow_negative
	if kind not in kinds:
		return false
	return Config.quality_allowed(str(row.get("quality", "")), str(rules.get("min_quality", "")), str(rules.get("max_quality", "")), Config.FORTUNE_QUALITIES)

static func _take(id: String, pool: Array, selected: Array, actor: Dictionary, label: String) -> String:
	if id not in pool and id not in selected:
		return "%s气运不在合法候选中：%s" % [label, id]
	if not Fortune.grant(actor, id, 0, "NPC 初始配置"):
		return "%s气运无法授予（重复或互斥）：%s" % [label, id]
	if id in pool:
		pool.erase(id)
	if id not in selected:
		selected.append(id)
	_drop_conflicts(pool, actor)
	return ""

static func _fill(random: RefCounted, pool: Array, selected: Array, actor: Dictionary, count: int, weights: Variant, high_quality: String) -> String:
	for _step in count:
		_drop_conflicts(pool, actor)
		var source: Array = _high_pool(pool, high_quality) if not high_quality.is_empty() else pool
		if source.is_empty():
			return "符合品质条件的气运不足，要求 %d 条，当前仅 %d 条。" % [selected.size() + (count - _step), selected.size()]
		var id: String = str(_weighted(random, source, weights))
		var error := _take(id, pool, selected, actor, "")
		if not error.is_empty():
			return error
	return ""

static func _drop_conflicts(pool: Array, actor: Dictionary) -> void:
	var remaining: Array = []
	for id in pool:
		var probe: Dictionary = actor.duplicate(true)
		if Fortune.grant(probe, id, 0, "NPC 初始配置"):
			remaining.append(id)
	pool.clear()
	pool.append_array(remaining)

static func _high_pool(pool: Array, quality: String) -> Array:
	var result: Array = []
	var low: int = Config.fortune_rank(quality)
	for id in pool:
		if Config.fortune_rank(str(Fortune.DEFINITIONS[id].quality)) >= low:
			result.append(id)
	return result

static func _high_count(ids: Array, quality: String) -> int:
	if quality.is_empty():
		return 0
	var count := 0
	var low: int = Config.fortune_rank(quality)
	for id in ids:
		if Config.fortune_rank(str(Fortune.DEFINITIONS.get(id, {}).get("quality", ""))) >= low:
			count += 1
	return count

static func _weighted(random: RefCounted, items: Array, weights: Variant) -> Variant:
	var total := 0
	var resolved: Array = []
	for id in items:
		var weight := 1
		if weights is Dictionary:
			var quality: String = str(Fortune.DEFINITIONS.get(id, {}).get("quality", ""))
			if Config._is_whole(weights.get(quality, 1)):
				weight = maxi(0, int(weights[quality])) if weights.has(quality) else 1
		resolved.append(weight)
		total += weight
	if total <= 0:
		return items[random.integer(STREAM, 0, items.size() - 1)]
	var roll: int = random.integer(STREAM, 1, total)
	var cursor := 0
	for index in items.size():
		cursor += int(resolved[index])
		if roll <= cursor:
			return items[index]
	return items.back()
