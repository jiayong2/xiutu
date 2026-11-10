@tool
extends RefCounted

const SCHEMA_VERSION := 1
const COUNT_MIN := 1
const COUNT_MAX := 100
const ROUTES := ["qi_primary", "body_primary", "dual", "random"]
const STAT_KEYS := ["hp", "mp", "attack", "defense", "speed"]
const FOUNDATION_KEYS := ["qi_sea", "meridians", "bones", "physique", "spirit_sea", "soul"]
const FORTUNE_QUALITIES := ["凡品", "良品", "上品", "玄品", "地品", "天品"]
const NEGATIVE_QUALITY := "负面"
const GEAR_QUALITIES := ["下品", "中品", "上品", "极品"]
const TECHNIQUE_RARITIES := ["凡品", "黄阶"]
const REALM_MODES := ["strict", "down_one", "up_one", "absolute", "any"]
const ELEMENTS := {
	"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土",
	"wind": "风", "thunder": "雷", "ice": "冰", "none": "", "five_elements": "",
}

static func defaults() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": "template_custom",
		"name": "自定义",
		"count": 1,
		"identity": {
			"location_ids": [],
			"sect_names": [""],
			"roles": [],
			"role_weights": [],
			"male_weight": 50,
			"female_weight": 50,
			"age": {"min": 18, "max": 80},
			"lifespan": {"min": 100, "max": 100},
			"wealth": {"min": 0, "max": 200},
			"personalities": [],
			"personality_weights": [],
			"generate_names": true,
		},
		"cultivation": {
			"qi_realm": {"min": 0, "max": 9},
			"body_realm": {"min": 0, "max": 9},
			"qi_realm_weights": {},
			"body_realm_weights": {},
			"route": "random",
			"cultivation_ratio": {"min": 0, "max": 80},
			"roots": [],
			"root_weights": [],
			"ranks": ["普通"],
			"rank_weights": [1],
			"realm_known": true,
			"foundation": {
				"qi_sea": {"min": 10, "max": 30},
				"meridians": {"min": 10, "max": 30},
				"bones": {"min": 10, "max": 30},
				"physique": {"min": 10, "max": 30},
				"spirit_sea": {"min": 10, "max": 30},
				"soul": {"min": 10, "max": 30},
			},
		},
		"base_stats": {
			"hp": {"min": 80, "max": 160},
			"mp": {"min": 0, "max": 60},
			"attack": {"min": 8, "max": 30},
			"defense": {"min": 4, "max": 16},
			"speed": {"min": 6, "max": 16},
		},
		"innate_fortune": _empty_fortune_rules(),
		"acquired_fortune": _empty_fortune_rules(),
		"equipment": _empty_gear_rules(),
		"artifacts": _empty_gear_rules(),
		"techniques": _empty_skill_rules(),
		"spells": _empty_skill_rules(),
	}

static func _empty_fortune_rules() -> Dictionary:
	return {
		"count": {"min": 0, "max": 0},
		"min_quality": "",
		"max_quality": "",
		"at_least": {"quality": "", "count": 0},
		"quality_weights": {},
		"required_ids": [],
		"excluded_ids": [],
		"allow_negative": false,
	}

static func _empty_gear_rules() -> Dictionary:
	return {
		"count": {"min": 0, "max": 0},
		"min_quality": "",
		"max_quality": "",
		"quality_weights": {},
		"realm_mode": "down_one",
		"realm_min": 0,
		"realm_max": 9,
		"slots": [],
		"types": [],
		"required_ids": [],
		"excluded_ids": [],
		"match_route": false,
	}

static func _empty_skill_rules() -> Dictionary:
	return {
		"count": {"min": 0, "max": 0},
		"equipped": {"min": 0, "max": 10},
		"min_rarity": "",
		"max_rarity": "",
		"level": {"min": 1, "max": 1},
		"required_ids": [],
		"excluded_ids": [],
		"match_root": true,
		"match_route": true,
	}

static func normalize(raw: Dictionary) -> Dictionary:
	var result := defaults()
	_merge_section(result, raw)
	result.schema_version = SCHEMA_VERSION
	if raw.has("seed"):
		result.seed = raw.seed
	if raw.get("id") is String and not raw.id.strip_edges().is_empty():
		result.id = raw.id.strip_edges()
	if raw.get("name") is String and not raw.name.strip_edges().is_empty():
		result.name = raw.name.strip_edges()
	if _is_whole(raw.get("count")):
		result.count = int(raw.count)
	return result

static func fingerprint(config: Dictionary) -> String:
	var copy: Dictionary = normalize(config)
	copy.erase("seed")
	return JSON.stringify(copy)

static func range_of(value: Variant, fallback_min: int = 0, fallback_max: int = 0) -> Dictionary:
	var result := {"min": fallback_min, "max": fallback_max}
	if value is Dictionary:
		if _is_number(value.get("min")):
			result.min = int(value.min)
		if _is_number(value.get("max")):
			result.max = int(value.max)
	return result

static func whole_in(value: Variant, low: int, high: int) -> bool:
	return _is_whole(value) and int(value) >= low and int(value) <= high

static func fortune_rank(quality: String) -> int:
	return FORTUNE_QUALITIES.find(quality)

static func gear_rank(quality: String) -> int:
	return GEAR_QUALITIES.find(quality)

static func rarity_rank(quality: String) -> int:
	return TECHNIQUE_RARITIES.find(quality)

static func quality_allowed(quality: String, minimum: String, maximum: String, order: Array) -> bool:
	var rank: int = order.find(quality)
	if rank < 0:
		return false
	if not minimum.is_empty():
		var low: int = order.find(minimum)
		if low < 0 or rank < low:
			return false
	if not maximum.is_empty():
		var high: int = order.find(maximum)
		if high < 0 or rank > high:
			return false
	return true

static func string_ids(value: Variant) -> Array:
	var result: Array = []
	var seen := {}
	if not value is Array:
		return result
	for item in value:
		if item is String and not item.strip_edges().is_empty() and not seen.has(item):
			seen[item] = true
			result.append(item)
	return result

static func major_tier(realm: int) -> int:
	if realm <= 0:
		return 0
	return 1 + (maxi(1, realm) - 1) / 9

static func _merge_section(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if key == "seed":
			continue
		if target.has(key) and target[key] is Dictionary and source[key] is Dictionary:
			_merge_section(target[key], source[key])
		elif target.has(key) or key in ["id", "name", "count", "schema_version"]:
			target[key] = source[key]

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _is_whole(value: Variant) -> bool:
	return _is_number(value) and float(value) == floor(float(value))

static func collect_personalities(data: Dictionary, overrides: Dictionary = {}) -> PackedStringArray:
	var seen := {}
	var result: PackedStringArray = []
	var rows: Array = []
	if data.has("prototype") and data.prototype.get("npcs") is Array:
		rows = data.prototype.npcs.duplicate()
	for npc in rows + overrides.values():
		if not npc is Dictionary:
			continue
		var personality: String = str(npc.get("profile", {}).get("personality", "")).strip_edges()
		if personality.is_empty() or seen.has(personality):
			continue
		seen[personality] = true
		result.append(personality)
	return result

static func collect_roles(data: Dictionary, overrides: Dictionary = {}) -> PackedStringArray:
	var seen := {}
	var result: PackedStringArray = []
	var rows: Array = []
	if data.has("prototype") and data.prototype.get("npcs") is Array:
		rows = data.prototype.npcs.duplicate()
	for npc in rows + overrides.values():
		if not npc is Dictionary:
			continue
		var role: String = str(npc.get("role", "")).strip_edges()
		if role.is_empty() or seen.has(role):
			continue
		seen[role] = true
		result.append(role)
	return result

static func sect_names(data: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray([""])
	if not data.has("prototype") or not data.prototype.get("sects") is Array:
		return result
	for sect in data.prototype.sects:
		if sect is Dictionary and sect.get("name") is String and not result.has(sect.name):
			result.append(sect.name)
	return result
