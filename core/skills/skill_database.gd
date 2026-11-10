extends RefCounted
## Load, validate and save techniques, spells and effect definitions.
## Runtime tables stay the ones ContentCatalog already uses. This is not a second combat database.

const Transaction := preload("res://core/skills/skill_file_transaction.gd")
const Registry := preload("res://core/skills/effect_registry.gd")
const Character := preload("res://gameplay/character/character_system.gd")
const SkillEngine := preload("res://gameplay/battle/skill_engine.gd")
const Context := preload("res://gameplay/battle/combat_context.gd")
const Math := preload("res://gameplay/battle/combat_math.gd")
const Status := preload("res://gameplay/battle/battle_status.gd")
const RandomSvc := preload("res://core/random_service.gd")
const Spells := preload("res://gameplay/battle/spell_progression.gd")

const TECHNIQUE_PATH := "res://data/skills/techniques.json"
const SPELL_PATH := "res://data/skills/spells.json"
const FLOW_PATH := "res://data/cultivation/spirit_flow.json"
const EFFECT_PATH := "res://data/skills/effect_definitions.json"
const TRIAL_PATHS := {
	"spell_trials": "res://data/skills/spell_trials.json",
	"spell_trials_stage2": "res://data/skills/spell_trials_stage2.json",
	"spell_trials_stage3": "res://data/skills/spell_trials_stage3.json",
}
const ROOTS := ["金", "木", "水", "火", "土", "风", "雷", "冰"]
const RARITIES := ["凡品", "黄阶"]
const ROUTES := ["qi", "body"]
const SPELL_TARGETS := ["enemy", "self"]
const AI_POLICIES := ["attack", "self_low_hp", "no_shield", "self_status", "target_status"]
const STAT_KEYS := ["hp", "defense", "attack", "fire", "mp", "speed", "critical", "critical_damage"]
const META_KEYS := ["_source", "_persisted", "_draft", "_token"]

static var _id_regex: RegEx

static func valid_id(value: Variant) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.new()
		_id_regex.compile("^[a-z][a-z0-9_]{2,63}$")
	return value is String and _id_regex.search(value) != null

static func load_bundle(technique_path := TECHNIQUE_PATH, spell_path := SPELL_PATH, flow_path := FLOW_PATH, effect_path := EFFECT_PATH, trial_paths: Dictionary = TRIAL_PATHS) -> Dictionary:
	var recovery := Transaction.recover(technique_path + ".transaction.json")
	if not recovery.is_empty():
		return {"error": recovery}
	var techniques := _read_array(technique_path)
	if not techniques.error.is_empty():
		return techniques
	var spells := _read_array(spell_path)
	if not spells.error.is_empty():
		return spells
	for row in spells.rows:
		row["_source"] = "spells"
		row["_persisted"] = true
	for source in trial_paths:
		var extra := _read_array(str(trial_paths[source]))
		if not extra.error.is_empty():
			return extra
		for row in extra.rows:
			row["_source"] = source
			row["_persisted"] = true
			spells.rows.append(row)
	for row in techniques.rows:
		row["_persisted"] = true
	var flow := _read_object(flow_path)
	if not flow.error.is_empty():
		return flow
	var effects := _read_effects(effect_path)
	if not effects.error.is_empty():
		return effects
	return {
		"techniques": techniques.rows,
		"spells": spells.rows,
		"effects": effects.rows,
		"flow": flow.data,
		"error": "",
	}

static func validate_bundle(bundle: Dictionary, growth: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var json_error := _json_safe(bundle, "bundle")
	if not json_error.is_empty():
		issues.append(json_error)
		return issues
	var technique_ids := {}
	var spell_ids := {}
	var effect_ids := {}
	var flow: Dictionary = bundle.get("flow", {})
	var flow_rows: Dictionary = flow.get("techniques", {}) if flow.get("techniques") is Dictionary else {}
	for row in bundle.get("effects", []):
		if not row is Dictionary:
			issues.append("效果定义不是对象")
			continue
		var message := Registry.validate_definition(row, growth)
		if not message.is_empty():
			issues.append(message)
		elif effect_ids.has(row.id):
			issues.append("效果 ID 重复：" + row.id)
		else:
			effect_ids[row.id] = true
	var definitions := Registry.by_id(bundle.get("effects", []))
	for row in bundle.get("techniques", []):
		if not row is Dictionary:
			issues.append("功法不是对象")
			continue
		var message := _validate_technique(row, flow_rows)
		if not message.is_empty():
			issues.append(message)
		elif technique_ids.has(row.id):
			issues.append("功法 ID 重复：" + row.id)
		else:
			technique_ids[row.id] = true
	for id in flow_rows:
		if not technique_ids.has(id):
			issues.append("炼化配置没有对应功法：" + str(id))
	for row in bundle.get("spells", []):
		if not row is Dictionary:
			issues.append("法术不是对象")
			continue
		var message := _validate_spell(row, definitions, growth)
		if not message.is_empty():
			issues.append(message)
		elif spell_ids.has(row.id) or technique_ids.has(row.id):
			issues.append("法术 ID 与其他技能重复：" + row.id)
		else:
			spell_ids[row.id] = true
	return issues

static func validate_runtime_spells(spells: Dictionary, growth: Dictionary) -> String:
	for id in spells:
		var spell: Dictionary = spells[id]
		if spell.has("levels") or not spell.has("effects"):
			continue
		var message := _validate_spell(spell, {}, growth)
		if not message.is_empty():
			return message
	return ""

static func save_bundle(bundle: Dictionary, growth: Dictionary, paths: Dictionary = {}) -> Dictionary:
	var issues := validate_bundle(bundle, growth)
	if not issues.is_empty():
		return {"success": false, "message": "\n".join(issues), "warning": ""}
	var technique_path := str(paths.get("techniques", TECHNIQUE_PATH))
	var spell_path := str(paths.get("spells", SPELL_PATH))
	var flow_path := str(paths.get("flow", FLOW_PATH))
	var effect_path := str(paths.get("effects", EFFECT_PATH))
	var trial_paths: Dictionary = paths.get("trials", TRIAL_PATHS)
	for path in [technique_path, spell_path, flow_path, effect_path]:
		if path.begins_with("res://") and not OS.has_feature("editor"):
			return {"success": false, "message": "导出版本不能写入 res://，请在 Godot 编辑器中保存。", "warning": ""}
	var include: Dictionary = paths.get("include", {})
	var candidates := []
	if include.is_empty() or bool(include.get("techniques", false)):
		candidates.append(technique_path)
	if include.is_empty() or bool(include.get("flow", false)):
		candidates.append(flow_path)
	if include.is_empty() or bool(include.get("effects", false)):
		candidates.append(effect_path)
	if include.is_empty() or bool(include.get("spells", false)):
		candidates.append(spell_path)
	for source in trial_paths:
		if include.is_empty() or bool(include.get(source, false)):
			candidates.append(str(trial_paths[source]))
	for path in candidates:
		if FileAccess.file_exists(path):
			var existing := _read_object(path) if path == flow_path else _read_array(path)
			if not existing.error.is_empty():
				return {"success": false, "message": existing.error, "warning": ""}
	var grouped := {"spells": []}
	for source in trial_paths:
		grouped[source] = []
	for row in bundle.spells:
		var source := str(row.get("_source", "spells"))
		if not grouped.has(source):
			source = "spells"
		grouped[source].append(_public_row(row))
	var flow_data: Dictionary = bundle.flow.duplicate(true)
	flow_data["techniques"] = {}
	for row in bundle.techniques:
		var public_row := _public_row(row)
		var flow_row: Dictionary = bundle.flow.get("techniques", {}).get(public_row.id, {}).duplicate(true)
		flow_row.merge(row.get("_flow", {}), true)
		flow_data.techniques[public_row.id] = flow_row
	var writes := {
		technique_path: _public_rows(bundle.techniques),
		effect_path: _public_rows(bundle.effects),
	}
	writes[spell_path] = grouped.spells
	for source in trial_paths:
		writes[str(trial_paths[source])] = grouped[source]
	writes[flow_path] = flow_data
	var texts := {}
	for path in candidates:
		texts[path] = JSON.stringify(writes[path], "  ") + "\n"
	var result := Transaction.commit(texts, technique_path + ".transaction.json")
	if result.success:
		result.message = "已保存功法 %d、法术 %d、效果 %d。" % [bundle.techniques.size(), bundle.spells.size(), bundle.effects.size()]
	return result

static func blank_technique(rows: Array) -> Dictionary:
	return {
		"id": unique_id("technique_new", rows), "name": "新功法", "description": "", "rarity": "凡品",
		"cultivation_route": "qi", "realm_min": 0, "hp": 0, "defense": 0, "attack": 0, "fire": 0.0,
		"hp_step": 0, "defense_step": 0, "attack_step": 0, "fire_step": 0.0, "buy_price": 0,
		"percents": {}, "level_overrides": {}, "_flow": {"element": "", "hourly": 60000, "hourly_step": 2500, "loss": 2000},
		"_source": "techniques", "_persisted": false,
	}

static func blank_spell(rows: Array, definitions: Array) -> Dictionary:
	var damage := Registry.find(definitions, "effect_direct_damage")
	var effects := []
	if not damage.is_empty():
		effects.append(Registry.instance_from(damage))
		effects[0]["node_id"] = "node_1"
	return {
		"id": unique_id("skill_new", rows), "name": "新法术", "description": "", "element": "无",
		"rarity": "凡品", "mp": 5, "cd": 0, "target": "enemy", "spell_type": "伤害", "buy_price": 0,
		"max_level": 3, "ordered": true, "effects": effects, "growth": [{}, {}, {}],
		"ai": {"policy": "attack"}, "_source": "spells", "_persisted": false,
	}

static func blank_effect(rows: Array) -> Dictionary:
	var row := Registry.find(Registry.fallback(), "effect_direct_damage").duplicate(true)
	row.id = unique_id("effect_custom", rows)
	row.name = "自定义直接伤害"
	row.builtin = false
	return row

static func duplicate_row(row: Dictionary, rows: Array, prefix_key := "id") -> Dictionary:
	var copy: Dictionary = row.duplicate(true)
	copy[prefix_key] = unique_id(str(row.get(prefix_key, "skill")) + "_copy", rows)
	copy["_persisted"] = false
	if copy.has("_source") and str(copy._source) != "spells" and copy.has("levels"):
		copy["_source"] = "spells"
	if bool(copy.get("builtin", false)):
		copy["builtin"] = false
	return copy

static func unique_id(base: String, rows: Array) -> String:
	var used := {}
	for row in rows:
		if row is Dictionary:
			used[str(row.get("id", ""))] = true
	var candidate := _clean_id(base)
	if not used.has(candidate):
		return candidate
	var index := 2
	while used.has("%s_%d" % [candidate, index]):
		index += 1
	return "%s_%d" % [candidate, index]

static func attach_flow(techniques: Array, flow: Dictionary) -> void:
	var rows: Dictionary = flow.get("techniques", {}) if flow.get("techniques") is Dictionary else {}
	for row in techniques:
		var current: Dictionary = rows.get(row.id, {})
		row["_flow"] = current.duplicate(true)

static func technique_amount(definition: Dictionary, key: String, level: int) -> float:
	return float(Character.technique_amount(definition, key, level))

static func preview_technique(row: Dictionary, level: int, player: Dictionary, data: Dictionary) -> Dictionary:
	var before := _actor(player, {})
	var equipped := _actor(player, {row.id: level})
	var tables := data.duplicate(true)
	tables.techniques = tables.techniques.duplicate(true)
	tables.techniques[row.id] = _public_row(row)
	if not tables.has("spirit_flow"):
		tables["spirit_flow"] = {"techniques": {}}
	tables.spirit_flow = tables.spirit_flow.duplicate(true)
	tables.spirit_flow.techniques = tables.spirit_flow.techniques.duplicate(true)
	tables.spirit_flow.techniques[row.id] = row.get("_flow", {})
	var bare: Dictionary = Character.new().stats(before, tables)
	var worn: Dictionary = Character.new().stats(equipped, tables)
	return {"before": bare, "after": worn, "level": level, "text": _technique_text(row, level)}

static func preview_spell(row: Dictionary, level: int, definitions: Array, growth: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("%s · %s · %s · %s" % [row.get("name", ""), row.get("rarity", ""), _element_name(row.get("element", "")), "Lv.%d" % level])
	lines.append("目标 %s · 灵力 %d · 冷却 %d" % [_target_name(str(row.get("target", ""))), _spell_mp(row, level), _spell_cd(row, level)])
	if row.has("levels"):
		for line in Spells.effect_lines(row, level, growth):
			lines.append(line[1])
		lines.append("试学法术按等级字典累加，正式熟练度上限为 %d。" % Spells.maximum(row))
	elif row.has("effects"):
		var runtime := _apply_growth(row, level)
		var defs := Registry.by_id(definitions)
		for effect in runtime.effects:
			var found: Variant = defs.get(str(effect.get("effect_id", "")), {})
			var definition: Dictionary = found if found is Dictionary else {}
			lines.append(Registry.describe(effect, definition, growth))
	else:
		for line in Spells.effect_lines(row, level, growth):
			lines.append(line[1])
		lines.append("旧法术等级成长沿用原公式：伤害系数每级 +0.1，治疗每级 +10，护体每级 +2。")
	return "\n".join(lines)

static func simulate_spell(row: Dictionary, level: int, caster: Dictionary, target: Dictionary, data: Dictionary, seed_value: int, times: int) -> Dictionary:
	var runs: Array = []
	var damages: Array[int] = []
	var heals: Array[int] = []
	var crits := 0
	var status_hits := 0
	for index in range(times):
		var random := RandomSvc.new()
		random.initialize(seed_value + index)
		var result := _one_cast(row, level, caster, target, data, random)
		if not str(result.get("error", "")).is_empty():
			return result
		runs.append(result)
		damages.append(int(result.damage))
		heals.append(int(result.heal))
		if bool(result.critical):
			crits += 1
		if int(result.status_count) > 0:
			status_hits += 1
	return {
		"error": "", "runs": runs, "count": times, "seed": seed_value,
		"damage_avg": _average(damages), "damage_min": _min(damages), "damage_max": _max(damages),
		"heal_avg": _average(heals), "crits": crits, "status_hits": status_hits,
	}

static func references_for(catalog: Dictionary, runtime: Dictionary = {}) -> Dictionary:
	var refs := {}
	for item_id in catalog.get("items", {}):
		var effect: Variant = catalog.items[item_id].get("use_effect")
		if effect is Dictionary and effect.get("learn") is String:
			_add_ref(refs, effect.learn, "物品", item_id, str(catalog.items[item_id].get("name", item_id)))
	for npc in catalog.get("prototype", {}).get("npcs", []):
		if npc is Dictionary:
			_scan_actor(refs, npc, "原型NPC", str(npc.get("id", "")), str(npc.get("name", "")))
	var overrides := _read_object("res://data/world/npc_overrides.json")
	if overrides.error.is_empty():
		for npc_id in overrides.data:
			if overrides.data[npc_id] is Dictionary:
				_scan_actor(refs, overrides.data[npc_id], "NPC覆盖", str(npc_id), str(overrides.data[npc_id].get("name", npc_id)))
	for monster_id in catalog.get("monsters", {}):
		var monster: Dictionary = catalog.monsters[monster_id]
		for skill_id in monster.get("skill_ids", []):
			_add_ref(refs, str(skill_id), "妖兽技能", monster_id, str(monster.get("name", monster_id)))
	if runtime.get("player") is Dictionary:
		_scan_actor(refs, runtime.player, "当前存档", "player", str(runtime.player.get("name", "玩家")))
	return refs

static func effect_references(spells: Array, effect_id: String) -> Array:
	var found := []
	for spell in spells:
		if not spell is Dictionary:
			continue
		for effect in spell.get("effects", []):
			if effect is Dictionary and str(effect.get("effect_id", "")) == effect_id:
				found.append({"id": spell.id, "name": str(spell.get("name", spell.id)), "kind": "法术"})
				break
	return found

static func _one_cast(row: Dictionary, level: int, caster: Dictionary, target: Dictionary, data: Dictionary, random: RefCounted) -> Dictionary:
	var spell := _public_row(row)
	var player := {
		"hp": int(caster.get("hp", 100)), "mp": int(caster.get("mp", 50)), "root": str(caster.get("root", "金")),
		"spells": {spell.id: level}, "spell_affixes": {}, "name": "测试施法者",
	}
	var enemy := {
		"hp": int(target.get("hp", 100)), "mp": int(target.get("mp", 0)),
		"attack": int(target.get("attack", 10)), "defense": int(target.get("defense", 0)),
		"speed": int(target.get("speed", 10)), "name": "测试目标",
	}
	var battle := {
		"enemy": enemy, "status": target.get("status", {}).duplicate(true) if target.get("status") is Dictionary else {},
		"cooldowns": {}, "turn": int(caster.get("turn", 1)), "monster": "", "log": [], "effect_trace": [],
		"enemy_max_hp": int(target.get("max_hp", enemy.hp)), "enemy_max_mp": int(target.get("max_mp", enemy.mp)),
		"enemy_ai": {"cooldowns": {}}, "acting": "player",
	}
	for id in caster.get("status", {}):
		battle.status[id] = caster.status[id]
	var state := {"player": player, "battle": battle}
	var stats := {
		"hp": int(caster.get("max_hp", player.hp)), "mp": int(caster.get("max_mp", player.mp)),
		"attack": float(caster.get("attack", 10)), "defense": float(caster.get("defense", 0)),
		"speed": float(caster.get("speed", 10)), "fire": float(caster.get("fire", 0)),
		"critical": float(caster.get("critical", 0)), "critical_damage": float(caster.get("critical_damage", 0)),
		"spell_bps": 0, "equipment_effects": {},
	}
	var ctx = Context.for_player(state, stats, data, random, Math.direct_damage)
	ctx.target = enemy
	ctx.target_stats = enemy
	ctx.target_max_hp = int(target.get("max_hp", enemy.hp))
	ctx.target_max_mp = int(target.get("max_mp", enemy.mp))
	var before_hp := int(enemy.hp)
	var before_caster := int(player.hp)
	var before_mp := int(player.mp)
	var engine := SkillEngine.new()
	var critical: bool = engine.cast(ctx, spell, data, random)
	var statuses := {}
	for id in battle.status:
		statuses[id] = battle.status[id].duplicate(true)
	return {
		"error": "", "damage": before_hp - int(enemy.hp), "heal": int(player.hp) - before_caster,
		"mp_spent": before_mp - int(player.mp), "critical": critical, "status_count": statuses.size(),
		"statuses": statuses, "trace": battle.effect_trace.duplicate(true),
		"target_hp": int(enemy.hp), "caster_hp": int(player.hp), "caster_mp": int(player.mp),
	}

static func _validate_technique(row: Dictionary, flow_rows: Dictionary) -> String:
	if not valid_id(row.get("id")):
		return "功法 ID 无效：" + str(row.get("id", ""))
	if str(row.get("name", "")).strip_edges().is_empty():
		return "功法 %s 缺少名称" % row.id
	if str(row.get("rarity", "")) not in RARITIES:
		return "功法 %s 的品阶不在升级表中" % row.id
	if str(row.get("cultivation_route", "")) not in ROUTES:
		return "功法 %s 缺少有效修炼路线" % row.id
	if not _whole(row.get("realm_min", 0), 0, 81):
		return "功法 %s 的境界条件无效" % row.id
	if not _whole(row.get("buy_price", 0), 0, 99999999):
		return "功法 %s 的价格无效" % row.id
	for key in ["hp", "defense", "attack", "hp_step", "defense_step", "attack_step"]:
		if not _whole(row.get(key, 0), 0, 999999):
			return "功法 %s 的 %s 无效" % [row.id, key]
	for key in ["fire", "fire_step"]:
		if not _number(row.get(key, 0)) or float(row.get(key, 0)) < 0.0 or float(row.get(key, 0)) > 10.0:
			return "功法 %s 的法术伤害系数无效" % row.id
	var percents: Variant = row.get("percents", {})
	if not percents is Dictionary:
		return "功法 %s 的百分比加成格式无效" % row.id
	for key in percents:
		if str(key) not in ["hp", "mp", "attack", "defense", "speed"]:
			return "功法 %s 的百分比属性不受计算支持：%s" % [row.id, key]
		if not _number(percents[key]) or float(percents[key]) < 0.0 or float(percents[key]) > 5.0:
			return "功法 %s 的百分比超出 0%% 到 500%%" % row.id
	var overrides: Variant = row.get("level_overrides", {})
	if not overrides is Dictionary:
		return "功法 %s level_overrides 必须是对象" % row.id
	for level in overrides:
		if not level is String or not level.is_valid_int() or str(int(level)) != level or int(level) < 1:
			return "功法 %s level_overrides 等级无效：%s" % [row.id, level]
		if not overrides[level] is Dictionary:
			return "功法 %s level_overrides.%s 必须是对象" % [row.id, level]
		for key in overrides[level]:
			if key not in STAT_KEYS:
				continue # Unknown inert extensions are retained, never interpreted.
			var value: Variant = overrides[level][key]
			var ratio: bool = key in ["fire", "critical", "critical_damage"]
			if (not ratio and not _whole(value, 0, 999999)) or (ratio and (not _number(value) or float(value) < 0.0 or float(value) > (10.0 if key == "fire" else 9999.99))):
				return "功法 %s level_overrides.%s.%s 超出既有属性范围" % [row.id, level, key]
	var flow: Variant = row.get("_flow", flow_rows.get(row.id, {}))
	if not flow is Dictionary:
		return "功法 %s 缺少炼化配置" % row.id
	var element := str(flow.get("element", ""))
	if not element.is_empty() and element not in ROOTS:
		return "功法 %s 的炼化五行无效" % row.id
	if not _whole(flow.get("hourly"), 1, 200000) or not _whole(flow.get("hourly_step"), 0, 200000) or not _whole(flow.get("loss"), 0, 10000):
		return "功法 %s 的炼化参数无效" % row.id
	return ""

static func _validate_spell(row: Dictionary, definitions: Dictionary, growth: Dictionary) -> String:
	if not valid_id(row.get("id")):
		return "法术 ID 无效：" + str(row.get("id", ""))
	if str(row.get("name", "")).strip_edges().is_empty():
		return "法术 %s 缺少名称" % row.id
	var element := str(row.get("element", ""))
	if element != "无" and element not in ROOTS:
		return "法术 %s 的五行无效" % row.id
	if not _whole(row.get("mp", 0), 0, 9999) or not _whole(row.get("cd", row.get("cooldown", 0)), 0, 99):
		return "法术 %s 的消耗或冷却无效" % row.id
	if row.has("levels"):
		if row.has("effects"):
			return "法术 %s 不能同时使用试学等级和效果列表" % row.id
		if not row.levels is Array or row.levels.is_empty():
			return "法术 %s 缺少等级效果" % row.id
		var target := str(row.get("target", "enemy"))
		if target not in ["enemy", "self", "ally", "all", "chain"]:
			return "法术 %s 的目标无效" % row.id
		for level in row.levels:
			if not level is Dictionary:
				return "法术 %s 的等级效果无效" % row.id
			for key in level:
				var value: Variant = level[key]
				if value is String and not growth.get("statuses", {}).has(value) and not growth.get("statuses", {}).has(key):
					if not growth.get("statuses", {}).has(value):
						return "法术 %s 的等级效果引用了未知状态 %s" % [row.id, value]
				elif not value is String and not _number(value):
					return "法术 %s 的等级字段 %s 不是数值" % [row.id, key]
				elif not value is String and float(value) < 0.0:
					return "法术 %s 的等级字段 %s 不能为负" % [row.id, key]
		return ""
	if row.has("effects"):
		if str(row.get("target", "")) not in SPELL_TARGETS:
			return "法术 %s 的施法目标当前战斗未执行" % row.id
		if not row.effects is Array or row.effects.is_empty():
			return "法术 %s 至少需要一个效果" % row.id
		var node_ids := {}
		for node_index in range(row.effects.size()):
			var effect: Variant = row.effects[node_index]
			if not effect is Dictionary or str(effect.get("type", "")) not in Registry.EXECUTORS:
				return "法术 %s 含有未注册执行器" % row.id
			if effect.has("node_id"):
				if not valid_id(effect.node_id) or node_ids.has(effect.node_id):
					return "法术 %s 的节点 ID 无效或重复" % row.id
				node_ids[effect.node_id] = true
			if effect.has("enabled") and not effect.enabled is bool:
				return "法术 %s 的节点 enabled 必须是布尔值" % row.id
			var effect_id := str(effect.get("effect_id", ""))
			if not effect_id.is_empty() and not definitions.is_empty() and not definitions.has(effect_id):
				return "法术 %s 引用了不存在的效果 %s" % [row.id, effect_id]
			if effect_id.is_empty() and definitions.is_empty():
				pass
			if not effect_id.is_empty() and definitions.has(effect_id):
				var message := Registry.validate_instance(effect, definitions[effect_id])
				if not message.is_empty():
					return "法术 %s effects[%d]：%s" % [row.id, node_index, message]
			if str(effect.get("type", "")) == "status" and not growth.get("statuses", {}).has(str(effect.get("status", ""))):
				return "法术 %s 使用了不可用状态 %s" % [row.id, effect.get("status", "")]
		var ai: Variant = row.get("ai", {"policy": "attack"})
		if not ai is Dictionary or str(ai.get("policy", "attack")) not in AI_POLICIES:
			return "法术 %s 的施法策略当前 AI 不能执行" % row.id
		if not row.get("growth") is Array:
			return "法术 %s 缺少等级成长表" % row.id
		return _validate_growth(row, definitions, growth)
	for key in ["multiplier", "heal", "guard"]:
		if row.has(key) and (not _number(row[key]) or float(row[key]) < 0.0):
			return "法术 %s 的 %s 无效" % [row.id, key]
	if row.has("status") and not str(row.status).is_empty() and not growth.get("statuses", {}).has(str(row.status)):
		return "法术 %s 的状态无效" % row.id
	var has_payload := float(row.get("multiplier", 0)) > 0.0 or float(row.get("heal", 0)) > 0.0 or float(row.get("guard", 0)) > 0.0 or not str(row.get("status", "")).is_empty()
	if not has_payload:
		return "法术 %s 没有可结算的效果" % row.id
	return ""

static func _actor(player: Dictionary, techniques: Dictionary) -> Dictionary:
	var actor := player.duplicate(true)
	actor["techniques"] = techniques.duplicate(true)
	actor["technique_slots"] = techniques.keys()
	if not actor.has("base"):
		actor["base"] = {"hp": 100, "mp": 50, "attack": 10, "defense": 5, "speed": 10}
	if not actor.has("equipped"):
		actor["equipped"] = {}
	if not actor.has("equipment_instances"):
		actor["equipment_instances"] = {}
	if not actor.has("growth"):
		actor["growth"] = {"attributes": {}}
	return actor

static func _validate_growth(row: Dictionary, definitions: Dictionary, growth: Dictionary) -> String:
	for level in range(row.growth.size()):
		var delta: Variant = row.growth[level]
		var where := "法术 %s growth[%d]" % [row.id, level]
		if not delta is Dictionary:
			return where + " 必须是对象"
		for key in ["mp", "cd"]:
			if delta.has(key) and not _whole(delta[key], 0, 9999 if key == "mp" else 99):
				return where + "." + key + " 超出已有整数范围"
		var patches: Variant = delta.get("effects", {})
		if not patches is Dictionary:
			return where + ".effects 必须是对象"
		for key in patches:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0 or int(key) >= row.effects.size():
				return where + ".effects 无效下标：" + str(key)
			if not patches[key] is Dictionary:
				return where + ".effects." + key + " 必须是对象"
			var effect: Dictionary = row.effects[int(key)].duplicate(true)
			for identity in ["type", "effect_id", "status", "target", "drain", "node_id", "enabled"]:
				if patches[key].has(identity) and patches[key][identity] != effect.get(identity):
					return where + ".effects." + key + " 不允许成长改变效果身份：" + identity
			effect.merge(patches[key], true)
			var definition: Dictionary = definitions.get(str(effect.get("effect_id", "")), {})
			if definition.is_empty():
				for candidate in Registry.fallback():
					if candidate.executor == effect.get("type"):
						definition = candidate
						break
			if definition.is_empty():
				return where + " 缺少参数校验定义"
			var message := Registry.validate_instance(effect, definition)
			if not message.is_empty():
				return where + ".effects." + key + "：" + message
			if effect.get("type") == "status" and not growth.get("statuses", {}).has(str(effect.get("status", ""))):
				return where + " 状态引用无效"
	return ""

static func _json_safe(value: Variant, where: String) -> String:
	if value is float and not is_finite(value):
		return where + " 非有限数值不能无损保存为JSON"
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName):
				return where + " JSON对象键必须是字符串"
			var message := _json_safe(value[key], where + "." + key)
			if not message.is_empty():
				return message
	elif value is Array:
		for i in range(value.size()):
			var message := _json_safe(value[i], where + "[%d]" % i)
			if not message.is_empty():
				return message
	elif value != null and not (value is String or value is bool or value is int or value is float):
		return where + " 含不支持的JSON值"
	return ""

static func _technique_text(row: Dictionary, level: int) -> String:
	var lines: PackedStringArray = []
	lines.append("%s · %s · %s · %s" % [row.get("name", ""), row.get("rarity", ""), _route_name(str(row.get("cultivation_route", ""))), "Lv.%d" % level])
	var flow: Dictionary = row.get("_flow", {})
	lines.append("炼化五行 %s · 每小时 %d · 每级 %+d · 损耗 %d" % [_element_name(flow.get("element", "")), int(flow.get("hourly", 0)), int(flow.get("hourly_step", 0)), int(flow.get("loss", 0))])
	for key in STAT_KEYS:
		if not row.has(key) and not row.has(key + "_step") and not _level_row(row, level).has(key):
			continue
		var amount := technique_amount(row, key, level)
		if amount == 0.0:
			continue
		lines.append("%s %+s" % [_stat_name(key), _format_stat(key, amount)])
	for key in row.get("percents", {}):
		lines.append("%s %+d%%" % [_stat_name(str(key)), roundi(float(row.percents[key]) * 100.0)])
	if int(row.get("realm_min", 0)) > 0:
		lines.append("学习需要境界 %d" % int(row.realm_min))
	return "\n".join(lines)

static func _apply_growth(spell: Dictionary, level: int) -> Dictionary:
	var copy := spell.duplicate(true)
	if not copy.get("growth") is Array:
		return copy
	var index := level - 1
	if index < 0 or index >= copy.growth.size() or not copy.growth[index] is Dictionary:
		return copy
	var delta: Dictionary = copy.growth[index]
	if delta.has("mp"):
		copy.mp = int(delta.mp)
	if delta.has("cd"):
		copy.cd = int(delta.cd)
	var patches: Variant = delta.get("effects", {})
	if patches is Dictionary:
		for key in patches:
			var effect_index := int(key)
			if effect_index >= 0 and effect_index < copy.effects.size() and patches[key] is Dictionary:
				copy.effects[effect_index].merge(patches[key], true)
	return copy

static func _spell_mp(row: Dictionary, level: int) -> int:
	var runtime := _apply_growth(row, level) if row.has("effects") else row
	return int(runtime.get("mp", 0))

static func _spell_cd(row: Dictionary, level: int) -> int:
	var runtime := _apply_growth(row, level) if row.has("effects") else row
	return int(runtime.get("cd", runtime.get("cooldown", 0)))

static func _level_row(definition: Dictionary, level: int) -> Dictionary:
	var table: Variant = definition.get("level_overrides", {})
	if not table is Dictionary:
		return {}
	var row: Variant = table.get(str(level), {})
	return row if row is Dictionary else {}

static func _scan_actor(refs: Dictionary, actor: Dictionary, kind: String, id: String, label: String) -> void:
	for key in ["techniques", "spells"]:
		if actor.get(key) is Dictionary:
			for skill_id in actor[key]:
				_add_ref(refs, str(skill_id), kind, id, label)
	for key in ["technique_slots", "spell_slots"]:
		if actor.get(key) is Array:
			for skill_id in actor[key]:
				_add_ref(refs, str(skill_id), kind, id, label)
	var profile: Variant = actor.get("profile", {})
	if profile is Dictionary:
		for skill_id in profile.get("spells", []):
			_add_ref(refs, str(skill_id), kind, id, label)
		var loadout: Variant = profile.get("loadout", actor.get("loadout", {}))
		if loadout is Dictionary and loadout.get("techniques") is Dictionary:
			for skill_id in loadout.techniques:
				_add_ref(refs, str(skill_id), kind, id, label)

static func _add_ref(refs: Dictionary, id: String, kind: String, source: String, label: String) -> void:
	if id.is_empty():
		return
	if not refs.has(id):
		refs[id] = []
	for entry in refs[id]:
		if entry.kind == kind and entry.source == source:
			return
	refs[id].append({"kind": kind, "source": source, "label": label})

static func _public_rows(rows: Array) -> Array:
	var result := []
	for row in rows:
		result.append(_public_row(row))
	return result

static func _public_row(row: Dictionary) -> Dictionary:
	var copy := row.duplicate(true)
	for key in META_KEYS:
		copy.erase(key)
	copy.erase("_flow")
	return copy

static func _read_array(path: String) -> Dictionary:
	var parsed := _parse(path)
	if not parsed.error.is_empty():
		return parsed
	if not parsed.data is Array:
		return {"rows": [], "error": "数据根节点必须是数组：" + path}
	var rows: Array = []
	for index in range(parsed.data.size()):
		var row: Variant = parsed.data[index]
		if not row is Dictionary:
			return {"rows": [], "error": "%s 记录[%d]不是对象，已阻止加载与保存" % [path, index]}
		rows.append(row.duplicate(true))
	return {"rows": rows, "error": ""}

static func _read_object(path: String) -> Dictionary:
	var parsed := _parse(path)
	if not parsed.error.is_empty():
		return parsed
	if not parsed.data is Dictionary:
		return {"data": {}, "error": "数据根节点必须是对象：" + path}
	return {"data": parsed.data.duplicate(true), "error": ""}

static func _read_effects(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"rows": Registry.fallback(), "error": ""}
	var parsed := _read_array(path)
	if not parsed.error.is_empty():
		return parsed
	if parsed.rows.is_empty():
		return {"rows": Registry.fallback(), "error": ""}
	return parsed

static func _parse(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"data": null, "error": "找不到文件：" + path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"data": null, "error": "无法读取：" + path}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"data": null, "error": "%s 第 %d 行 JSON 无效：%s" % [path, parser.get_error_line(), parser.get_error_message()]}
	return {"data": parser.data, "error": ""}

static func _clean_id(value: String) -> String:
	var cleaned := value.to_lower()
	var regex := RegEx.new()
	regex.compile("[^a-z0-9_]")
	cleaned = regex.sub(cleaned, "_", true)
	if cleaned.is_empty() or not cleaned[0] in "abcdefghijklmnopqrstuvwxyz":
		cleaned = "skill_" + cleaned
	return cleaned.substr(0, 64)

static func _element_name(value: Variant) -> String:
	var text := str(value)
	return "无属性" if text.is_empty() or text == "无" else text

static func _route_name(value: String) -> String:
	return "体修" if value == "body" else "法修"

static func _target_name(value: String) -> String:
	return {"enemy": "敌方单体", "self": "自身", "ally": "友方单体", "all": "敌方群体", "chain": "连锁"}.get(value, value)

static func _stat_name(key: String) -> String:
	return {"hp": "最大生命", "mp": "最大灵力", "attack": "攻击", "defense": "防御", "speed": "速度", "fire": "法术伤害", "critical": "暴击率", "critical_damage": "暴击伤害"}.get(key, key)

static func _format_stat(key: String, amount: float) -> String:
	if key in ["fire", "critical", "critical_damage"]:
		return "%d%%" % roundi(amount * 100.0)
	return str(roundi(amount))

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floor(float(value)) and int(value) >= minimum and int(value) <= maximum

static func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())

static func _min(values: Array) -> int:
	var best := int(values[0]) if not values.is_empty() else 0
	for value in values:
		best = mini(best, int(value))
	return best

static func _max(values: Array) -> int:
	var best := int(values[0]) if not values.is_empty() else 0
	for value in values:
		best = maxi(best, int(value))
	return best
