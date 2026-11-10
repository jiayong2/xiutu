@tool
extends RefCounted

const Config := preload("res://core/npc_generation/generation_config.gd")
const Names := preload("res://core/npc_generation/name_table.gd")
const Validator := preload("res://core/npc_generation/generation_validator.gd")
const Fortunes := preload("res://core/npc_generation/generation_fortunes.gd")
const Loadout := preload("res://core/npc_generation/generation_loadout.gd")
const Model := preload("res://core/npc_definitions.gd")
const Random := preload("res://core/random_service.gd")
const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const Character := preload("res://gameplay/character/character_system.gd")
const Locations := preload("res://core/world_locations.gd")
const World := preload("res://world/world_simulator.gd")

const ID_ATTEMPTS := 32
const STREAM := "world"

func generate(raw_config: Dictionary, data: Dictionary, context: Dictionary = {}) -> Dictionary:
	var config := Config.normalize(raw_config)
	var issues: Array = Validator.config_errors(config, data)
	if not issues.is_empty():
		return _result(false, config, 0, [], issues, [])
	var names_table := Names.load_table(str(context.get("names_path", Names.PATH)))
	if not names_table.error.is_empty():
		return _result(false, config, 0, [], [Validator._issue("NAMES", names_table.error, "names")], [])
	var seed_value := _seed(config)
	var random := Random.new()
	random.initialize(seed_value)
	var overrides: Dictionary = context.get("overrides", data.get("npc_overrides", {}))
	var roster := Model.roster(data, overrides)
	var used_ids := {}
	var used_names := {}
	for id in roster:
		used_ids[id] = true
		used_names[str(roster[id].get("name", ""))] = true
	for extra in context.get("existing_ids", []):
		used_ids[str(extra)] = true
	for extra in context.get("existing_names", []):
		used_names[str(extra)] = true
	var personalities: Array = config.identity.personalities.duplicate()
	if personalities.is_empty():
		for personality in Config.collect_personalities(data, overrides):
			personalities.append(personality)
	var locations: Array = config.identity.location_ids.duplicate()
	if locations.is_empty():
		locations = Locations.names(data).keys()
	var roots: Array = config.cultivation.roots.duplicate()
	if roots.is_empty():
		roots = data.rules.roots.duplicate()
	var npcs: Array = []
	var npc_issues: Array = []
	var known := roster.duplicate()
	for _index in int(config.count):
		var built := _one(random, config, data, names_table.rows, used_ids, used_names, personalities, locations, roots)
		if not built.error.is_empty():
			npc_issues.append(Validator._issue("GENERATE", built.error, "npc"))
			continue
		var npc: Dictionary = Model.draft(built.npc, data)
		known[npc.id] = npc
		var errors := Validator.npc_errors(npc, config, data, known)
		if not errors.is_empty():
			known.erase(npc.id)
			npc_issues.append_array(errors)
			continue
		used_ids[npc.id] = true
		used_names[str(npc.name)] = true
		npcs.append(npc)
	return _result(true, config, seed_value, npcs, [], npc_issues)

func preview_stats(npc: Dictionary, data: Dictionary) -> Dictionary:
	return Character.new().npc_stats(Model.initial(npc.duplicate(true), data), npc.profile, data)

static func _result(ok: bool, config: Dictionary, seed_value: int, npcs: Array, config_issues: Array, npc_issues: Array) -> Dictionary:
	return {
		"ok": ok,
		"seed": seed_value,
		"config": config,
		"fingerprint": Config.fingerprint(config),
		"npcs": npcs,
		"config_issues": config_issues,
		"npc_issues": npc_issues,
		"passed": npcs.size(),
		"failed": npc_issues.size(),
	}

static func _seed(config: Dictionary) -> int:
	if config.has("seed") and Config._is_whole(config.seed):
		return int(config.seed)
	return int(Time.get_ticks_usec()) ^ int(Time.get_unix_time_from_system())

func _one(random: RefCounted, config: Dictionary, data: Dictionary, names: Dictionary, used_ids: Dictionary, used_names: Dictionary, personalities: Array, locations: Array, roots: Array) -> Dictionary:
	var id := _uid(random, used_ids)
	if id.is_empty():
		return {"error": "无法生成唯一 NPC ID"}
	var gender := _gender(random, config.identity)
	var name := ""
	if config.identity.get("generate_names", true):
		var picked := Names.pick(random, names, gender, used_names)
		if not picked.error.is_empty():
			return {"error": picked.error}
		name = picked.name
	var realms := _realms(random, config, data)
	if not realms.error.is_empty():
		return realms
	var lifespan := _lifespan(random, config, data, int(realms.qi))
	var age_hi := mini(int(config.identity.age.max), lifespan.effective - 1)
	if int(config.identity.age.min) > age_hi:
		return {"error": "年龄与寿元无法同时满足"}
	var age: int = random.integer(STREAM, int(config.identity.age.min), age_hi)
	var location: String = _choice(random, locations)
	var sect: String = _choice(random, config.identity.sect_names) if not config.identity.sect_names.is_empty() else ""
	var role := ""
	if not config.identity.roles.is_empty():
		role = str(_weighted(random, config.identity.roles, config.identity.role_weights))
	var personality := ""
	if not personalities.is_empty():
		personality = str(_weighted(random, personalities, config.identity.personality_weights))
	var rank: String = str(_weighted(random, config.cultivation.ranks, config.cultivation.rank_weights))
	var root: String = str(_weighted(random, roots, config.cultivation.root_weights))
	var foundation := {}
	for key in Config.FOUNDATION_KEYS:
		foundation[key] = _roll(random, config.cultivation.foundation[key])
	var base := {}
	for key in Config.STAT_KEYS:
		base[key] = _roll(random, config.base_stats[key])
	var cultivation_value := 0
	if int(realms.qi) > 0 and int(realms.qi) < Cultivation.MAX_LEVEL:
		var required: int = Cultivation.new().requirement({"realm": int(realms.qi), "growth": {"body_level": int(realms.body)}, "cultivation": 0}, "qi", data)
		var ratio: int = _roll(random, config.cultivation.cultivation_ratio)
		cultivation_value = int(round(float(required) * float(ratio) / 100.0))
	var npc := {
		"id": id,
		"name": name,
		"authored": true,
		"age": age,
		"initial_age": age,
		"lifespan": lifespan.stored,
		"wealth": _roll(random, config.identity.wealth),
		"cultivation": cultivation_value,
		"location": location,
		"realm": int(realms.qi),
		"realm_known": config.cultivation.get("realm_known", true) == true,
		"role": role,
		"profile": {
			"gender": gender,
			"personality": personality,
			"root": root,
			"rank": Character.npc_rank({"rank": rank}),
			"body_realm": Cultivation.realm_name(int(realms.body), "body", data),
			"sect": sect,
			"foundation": foundation,
			"base": base,
			"stat_overrides": {},
			"innate_fortune": [],
			"acquired_fortune": [],
			"contacts": {},
		},
	}
	npc["_generation_route"] = str(realms.route)
	var fortune_error := Fortunes.apply(random, config, npc)
	if not fortune_error.is_empty():
		return {"error": fortune_error}
	var loadout_error := Loadout.apply(random, config, npc, data)
	npc.erase("_generation_route")
	if not loadout_error.is_empty():
		return {"error": loadout_error}
	return {"error": "", "npc": npc}

func _realms(random: RefCounted, config: Dictionary, _data: Dictionary) -> Dictionary:
	var route: String = str(config.cultivation.route)
	if route == "random":
		route = ["qi_primary", "body_primary", "dual"][random.integer(STREAM, 0, 2)]
	var qi_range := Config.range_of(config.cultivation.qi_realm)
	var body_range := Config.range_of(config.cultivation.body_realm)
	if route == "body_primary":
		var body_candidates := _levels(body_range.min, body_range.max)
		if body_candidates.is_empty():
			return {"error": "体修范围没有合法候选"}
		var body: int = int(_weighted(random, body_candidates, _level_weights(body_candidates, config.cultivation.body_realm_weights)))
		var qi_high: int = mini(int(qi_range.max), body) if body > 0 else int(qi_range.max)
		var qi_candidates := _levels(qi_range.min, qi_high)
		if qi_candidates.is_empty():
			return {"error": "法修范围在当前体修下没有合法候选"}
		var qi: int = int(_weighted(random, qi_candidates, _level_weights(qi_candidates, config.cultivation.qi_realm_weights)))
		return {"error": "", "qi": qi, "body": body, "route": route}
	var qi_candidates: Array = []
	for level in range(qi_range.min, qi_range.max + 1):
		if _body_high(route, level, body_range) >= body_range.min:
			qi_candidates.append(level)
	if qi_candidates.is_empty():
		return {"error": "法修与体修范围没有可同时满足的组合"}
	var qi: int = int(_weighted(random, qi_candidates, _level_weights(qi_candidates, config.cultivation.qi_realm_weights)))
	var body_candidates := _levels(body_range.min, _body_high(route, qi, body_range))
	if body_candidates.is_empty():
		return {"error": "体修范围在当前法修下没有合法候选"}
	var body: int = int(_weighted(random, body_candidates, _level_weights(body_candidates, config.cultivation.body_realm_weights)))
	return {"error": "", "qi": qi, "body": body, "route": route}

static func _levels(low: int, high: int) -> Array:
	var result: Array = []
	if high < low:
		return result
	for level in range(low, high + 1):
		result.append(level)
	return result

static func _body_high(route: String, qi: int, body_range: Dictionary) -> int:
	if route == "qi_primary":
		return mini(int(body_range.max), qi)
	return int(body_range.max)

func _lifespan(random: RefCounted, config: Dictionary, data: Dictionary, realm: int) -> Dictionary:
	var stored: int = _roll(random, config.identity.lifespan)
	var sample := {"realm": realm, "lifespan": stored}
	return {"stored": stored, "effective": World.npc_lifespan(sample, data)}

func _gender(random: RefCounted, identity: Dictionary) -> String:
	var male: int = maxi(0, int(identity.male_weight))
	var female: int = maxi(0, int(identity.female_weight))
	return "男" if random.integer(STREAM, 1, male + female) <= male else "女"

func _uid(random: RefCounted, used: Dictionary) -> String:
	for _attempt in ID_ATTEMPTS:
		var hex := ""
		for _byte in 12:
			hex += "%02x" % random.integer(STREAM, 0, 255)
		var id := "npc_" + hex
		if id.is_valid_identifier() and not used.has(id):
			return id
	return ""

func _roll(random: RefCounted, spec: Variant) -> int:
	var span := Config.range_of(spec)
	return random.integer(STREAM, span.min, span.max)

func _choice(random: RefCounted, items: Array) -> Variant:
	return items[random.integer(STREAM, 0, items.size() - 1)]

func _weighted(random: RefCounted, items: Array, weights: Variant) -> Variant:
	if items.is_empty():
		return ""
	var resolved: Array = []
	var total := 0
	for index in items.size():
		var weight := 1
		if weights is Array and index < weights.size() and Config._is_whole(weights[index]):
			weight = maxi(0, int(weights[index]))
		resolved.append(weight)
		total += weight
	if total <= 0:
		return _choice(random, items)
	var roll: int = random.integer(STREAM, 1, total)
	var cursor := 0
	for index in items.size():
		cursor += int(resolved[index])
		if roll <= cursor:
			return items[index]
	return items.back()

func _level_weights(levels: Array, configured: Variant) -> Array:
	var result: Array = []
	for level in levels:
		var weight := 1
		if configured is Dictionary:
			var key := str(int(level))
			if configured.has(key) and Config._is_whole(configured[key]):
				weight = maxi(0, int(configured[key]))
			elif configured.has(int(level)) and Config._is_whole(configured[int(level)]):
				weight = maxi(0, int(configured[int(level)]))
		result.append(weight)
	return result
