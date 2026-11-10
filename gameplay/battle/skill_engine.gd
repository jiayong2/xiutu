extends RefCounted
## Authoritative skill-effect engine for player, NPC and monster casts.
##
## Player spells keep their existing `levels` effect vocabulary. Monster skills
## are normalized from their `effects` list into the same vocabulary before
## execution, so damage, status, healing, shields and resources have one
## implementation. BattleSystem supplies side-specific damage callbacks.

const Spells = preload("res://gameplay/battle/spell_progression.gd")
const Status = preload("res://gameplay/battle/battle_status.gd")
const Math = preload("res://gameplay/battle/combat_math.gd")
const Context = preload("res://gameplay/battle/combat_context.gd")

var last_critical := false

func cast_player_spell(s: Dictionary, spell: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, roll: Callable) -> bool:
	var ctx = Context.for_player(s, stats, data, random, roll)
	return cast(ctx, spell, data, random)

func cast_monster_skill(s: Dictionary, plan: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted,
		monster_hit: Callable, raw_target: Callable = Callable()) -> Dictionary:
	var skill: Dictionary = plan.get("skill", {})
	if skill.is_empty():
		return {"avoided": false, "critical": false}
	var ctx = Context.for_monster(s, stats, data, random, monster_hit, raw_target)
	var critical := cast(ctx, skill, data, random)
	return {"avoided": false, "critical": critical}

func cast_npc_skill(s: Dictionary, npc: Dictionary, npc_stats: Dictionary, target: Dictionary, target_stats: Dictionary,
		skill: Dictionary, data: Dictionary, random: RefCounted, hit_target: Callable, raw_target: Callable = Callable()) -> bool:
	var ctx = Context.for_npc(s, npc, npc_stats, target, target_stats, data, random, hit_target, raw_target)
	return cast(ctx, skill, data, random)

func npc_basic_attack(s: Dictionary, npc_stats: Dictionary, target_stats: Dictionary, data: Dictionary, random: RefCounted, raw_target: Callable = Callable()) -> bool:
	var ctx = Context.for_npc(s, s.battle.enemy, npc_stats, s.player, target_stats, data, random, Callable(), raw_target)
	var defense: float = ctx.target_defense() * (1.0 - clampf(ctx.target_ratio("armor_break") + float(ctx.equipment.get("defense_ignore", 0)) / 100.0, 0.0, 1.0))
	var fortune_scale: float = 1.0 + (ctx.fortune("damage") + ctx.fortune("normal_damage") + ctx.fortune("beast_damage", ctx.target_monster_id)) / 100.0
	var crit_bonus := float(ctx.equipment.get("critical", 0)) / 100.0
	var chance := clampf(float(npc_stats.get("critical", data.rules.crit_chance)) + crit_bonus, 0.0, 1.0)
	var crit := 1.0
	last_critical = false
	if random != null and random.roll("battle") < chance:
		crit = float(npc_stats.get("critical_damage", data.rules.crit_multiplier))
		last_critical = true
	var amount: int = Math.direct_damage(float(npc_stats.get("attack", 0)), defense, (1.0 + ctx.target_ratio("vulnerability")) * fortune_scale * crit, data)
	ctx.raw_damage(amount)
	_electrify(ctx, data.spell_growth)
	return last_critical

func npc_mana_cost(s: Dictionary, spell: Dictionary, npc_stats: Dictionary, data: Dictionary) -> int:
	var ctx = Context.for_npc(s, s.battle.get("enemy", {}), npc_stats, s.player, {}, data, null, Callable())
	return mana_cost(ctx, spell)

func player_basic_attack(s: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, roll: Callable) -> void:
	var ctx = Context.for_player(s, stats, data, random, roll)
	var config: Dictionary = data.spell_growth
	var defense: float = ctx.target_defense() * (1.0 - clampf(ctx.target_ratio("armor_break") + float(ctx.equipment.get("defense_ignore", 0)) / 100.0, 0.0, 1.0))
	var fortune_scale: float = 1.0 + (ctx.fortune("damage") + ctx.fortune("normal_damage") + ctx.fortune("beast_damage", ctx.target_monster_id)) / 100.0
	var amount: int = roll.call(float(stats.get("attack", 0)), defense, (1.0 + ctx.target_ratio("vulnerability")) * fortune_scale, data)
	ctx.hit_target_enemy(amount, float(ctx.equipment.get("shield_damage", 0)) / 100.0)
	_electrify(ctx, config)

func preview_mana_cost(s: Dictionary, spell: Dictionary, stats: Dictionary, data: Dictionary) -> int:
	var ctx = Context.for_player(s, stats, data, null, Callable())
	return mana_cost(ctx, spell)

static func shared_damage(attack: float, defense: float, multiplier: float, data: Dictionary) -> int:
	return Math.direct_damage(attack, defense, multiplier, data)

static func gain_mana(p: Dictionary, stats: Dictionary, amount: int) -> void:
	p.mp = mini(int(stats.get("mp", 0)), int(p.get("mp", 0)) + amount)

static func heal_player(s: Dictionary, stats: Dictionary, amount: int, b: Dictionary, config: Dictionary) -> void:
	var p: Dictionary = s.player
	var scale := 1.0 - Status.ratio(b, "player_corrosion", config)
	scale *= 1.0 + float(stats.get("equipment_effects", {}).get("healing_received", 0)) / 100.0
	p.hp = mini(int(stats.get("hp", 1)), int(p.get("hp", 0)) + floori(amount * scale))

static func repair_player_shield(b: Dictionary, amount: int) -> void:
	var id := Status.shield_id(b)
	if not id.is_empty() and amount > 0:
		var shield: Dictionary = b.status[id]
		shield.amount = mini(int(shield.get("maximum", shield.amount)), int(shield.amount) + amount)

func apply_monster_self_effects(s: Dictionary, effects: Array, data: Dictionary, random: RefCounted, stats: Dictionary) -> Dictionary:
	if effects.is_empty():
		return {}
	var ctx = Context.for_monster(s, stats, data, random, Callable(), Callable())
	var e := _normalize_effects({"target": "self", "effects": effects})
	_support(ctx, e, ctx.caster_stats, data.spell_growth, "")
	return {}

func cast(ctx, spell: Dictionary, data: Dictionary, random: RefCounted) -> bool:
	last_critical = false
	if bool(spell.get("ordered", false)) and spell.has("effects") and not spell.has("levels"):
		return _cast_ordered(ctx, spell, data, random)
	var config: Dictionary = data.spell_growth
	var caster: Dictionary = ctx.caster
	var level: int = int(caster.get("spells", {}).get(spell.get("id", ""), 1)) if ctx.player_caster or ctx.actor_rules else 1
	var e: Dictionary = Spells.effects(spell, level) if spell.has("levels") else _normalize_effects(spell)
	var wind: Dictionary = ctx.caster_status("wind_ready")
	var affixes: Array = []
	if ctx.player_caster or ctx.actor_rules:
		var stored: Variant = caster.get("spell_affixes", {}).get(spell.get("id", ""), {})
		if stored is Dictionary:
			affixes = stored.values()
	var cost := mana_cost(ctx, spell)
	caster.mp = maxi(0, int(caster.get("mp", 0)) - cost)
	if int(spell.get("mp", 0)) > 0:
		ctx.caster_consume("discount")
	if str(spell.get("element", "无")) == "风" and _is_attack(spell):
		ctx.caster_consume("wind_ready")
	ctx.cooldowns[spell.get("id", "")] = int(spell.get("cd", spell.get("cooldown", 0)))
	if ctx.player_caster and spell.has("levels"):
		if e.has("power"):
			last_critical = _attack(ctx, spell, e, ctx.caster_stats, data, random, _direct_damage.bind(data), affixes, wind)
			return last_critical
		_support(ctx, e, ctx.caster_stats, config, str(spell.get("element", "无")))
		return false
	if spell.has("levels"):
		if e.has("power"):
			last_critical = _attack(ctx, spell, e, ctx.caster_stats, data, random, _direct_damage.bind(data), affixes, wind)
			return last_critical
		_support(ctx, e, ctx.caster_stats, config, str(spell.get("element", "无")))
		return false
	if spell.has("effects"):
		if e.has("power"):
			last_critical = _attack(ctx, spell, e, ctx.caster_stats, data, random, _direct_damage.bind(data), affixes, wind)
			return last_critical
		_support(ctx, e, ctx.caster_stats, config, str(spell.get("element", "无")))
		return false
	if not spell.has("levels"):
		if float(spell.get("heal", 0)) > 0:
			var recovery: float = 1.0 + ctx.fortune("wood_heal", str(spell.get("element", ""))) / 100.0
			ctx.heal_caster(floori((float(spell.heal) + (level - 1) * 10) * recovery))
		elif float(spell.get("guard", 0)) > 0:
			if ctx.player_caster:
				ctx.battle.status.guard = {"turns": int(data.rules.status_turns) + 1, "amount": float(spell.guard) + (level - 1) * 2}
		else:
			e = {"power": float(spell.get("multiplier", 1)) + (level - 1) * .1}
			last_critical = _attack(ctx, spell, e, ctx.caster_stats, data, random, _direct_damage.bind(data), affixes, wind)
			if ctx.target_hp() > 0 and not str(spell.get("status", "")).is_empty() and random.roll("battle") < float(data.rules.status_chance):
				var status_id: String = ctx.target_status_id(str(spell.status))
				if ctx.battle.status.get(status_id, {}).has("layers"):
					ctx.target_apply(str(spell.status), float(ctx.caster_stats.get("attack", 0)))
				else:
					ctx.battle.status[status_id] = {"turns": int(data.rules.status_turns)}
		return last_critical
	if e.has("power"):
		last_critical = _attack(ctx, spell, e, ctx.caster_stats, data, random, _direct_damage.bind(data), affixes, wind)
		return last_critical
	_support(ctx, e, ctx.caster_stats, config, str(spell.get("element", "无")))
	return false

func mana_cost(ctx, spell: Dictionary) -> int:
	var cost := int(spell.get("mp", 0))
	if cost == 0:
		return 0
	if not ctx.player_caster and not ctx.actor_rules:
		return cost
	var discount := int(ctx.caster_status("spring").get("effects", {}).get("spring_discount", 0))
	discount += int(ctx.caster_status("discount").get("value", 0))
	if str(spell.get("element", "")) == "风" and _is_attack(spell):
		discount += int(ctx.caster_status("wind_ready").get("effects", {}).get("wind_discount", 0))
	var adjusted := roundi(maxi(1, cost - discount) * (100 + ctx.fortune("spell_cost")) / 100.0)
	return maxi(1, adjusted + ctx.fortune("first_spell_cost", "", "fixed"))

func _is_attack(spell: Dictionary) -> bool:
	return str(spell.get("target", "")) in ["enemy", "all", "chain"] or (not spell.has("levels") and not spell.has("effects") and float(spell.get("multiplier", 0)) > 0)

func _attack(ctx, spell: Dictionary, e: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, roll: Callable, affixes: Array, wind: Dictionary) -> bool:
	var config: Dictionary = data.spell_growth
	var attack := float(stats.get("attack", 0))
	var start_hp: int = ctx.target_hp()
	var poison: int = ctx.target_layers("poison")
	var burn: int = ctx.target_layers("burn")
	var wet: bool = ctx.target_layers("wet") > 0
	var mark: int = ctx.target_layers("sword_mark")
	var thunder_mark: int = ctx.target_layers("thunder_mark")
	var chill: int = ctx.target_layers("chill")
	var shield: bool = ctx.target_has_shield()
	var consumed: int = ctx.target_consume(str(e.get("consume_enemy", ""))) if e.has("consume_enemy") else 0
	var self_used: int = ctx.caster_consume(str(e.get("consume_self", ""))) if e.has("consume_self") else 0
	var bonus := 0.0
	var equipment: Dictionary = ctx.equipment
	var pierce := float(e.get("pierce", 0)) + float(equipment.get("defense_ignore", 0)) / 100.0
	var crit := float(wind.get("wind_crit", 0)) if str(spell.get("element", "")) == "风" else 0.0
	crit += float(equipment.get("critical", 0)) / 100.0
	var crit_damage := 0.0
	if str(spell.get("element", "")) == "金":
		bonus += ctx.target_ratio("sword_mark") + ctx.caster_ratio("sword_intent")
		if str(e.get("consume_enemy", "")) == "sword_mark":
			bonus += consumed * float(config.statuses.sword_mark.value)
		if not e.has("consume_self"):
			ctx.caster_consume("sword_intent")
		if ctx.target_has("armor_break"):
			bonus += float(e.get("armor_bonus", 0))
		if mark > 0:
			pierce += float(e.get("mark_pierce", 0))
	if str(spell.get("element", "")) == "火":
		if not e.has("consume_self"):
			bonus += ctx.caster_ratio("flame_force")
			ctx.caster_consume("flame_force")
	if str(spell.get("element", "")) == "雷":
		if wet:
			bonus += float(config.statuses.wet.value)
		if thunder_mark > 0:
			crit += float(e.get("mark_crit", 0))
		crit += ctx.caster_ratio("thunder_force")
		ctx.caster_consume("thunder_force")
	if str(spell.get("element", "")) == "冰":
		bonus += chill * float(e.get("chill_bonus", 0))
		bonus += ctx.target_ratio("ice_vulnerability")
		ctx.target_consume("ice_vulnerability")
	if shield:
		bonus += float(e.get("shield_damage_bonus", 0))
	if ctx.player_caster:
		bonus += float(ctx.target_status("focus").get("value", ctx.target_ratio("focus"))) + ctx.target_ratio("vulnerability")
		ctx.target_consume("focus")
	bonus += self_used * float(e.get("self_bonus", 0)) + ctx.caster_layers("wind_force") * float(e.get("wind_bonus", 0))
	if e.has("consume_crit") and consumed >= int(e.consume_crit):
		crit += float(e.crit_bonus)
	if e.has("self_crit_threshold") and self_used >= int(e.self_crit_threshold):
		crit += float(e.self_crit)
	if e.has("consume_crit_damage") and consumed >= int(e.consume_crit_damage):
		crit_damage = float(e.crit_damage)
	if e.has("consume_pierce_threshold") and consumed >= int(e.consume_pierce_threshold):
		pierce += float(e.consume_pierce)
	if "pierce" in affixes:
		pierce += float(config.affixes.pierce.value)
	var defense: float = ctx.target_defense() * (1.0 - ctx.target_ratio("armor_break")) * (1.0 - clampf(pierce, 0, 1))
	var scale: float = (1.1 if ctx.root == str(spell.get("element", "")) else 1.0) * (1.0 + ctx.spell_bps / 10000.0)
	if str(spell.get("element", "")) == "火":
		scale *= 1.0 + ctx.fire
	scale *= 1.0 + bonus
	scale *= 1.0 + (ctx.fortune("damage") + ctx.fortune("spell_damage", str(spell.get("element", ""))) + ctx.fortune("beast_damage", ctx.target_monster_id)) / 100.0
	if str(spell.get("element", "")) in ["金", "木", "水", "火", "土"]:
		scale *= 1.0 + float(equipment.get("five_element_damage", 0)) / 100.0
	var hits: Array[float] = []
	for index in range(int(e.get("hits", 1))):
		hits.append(float(e.get("power", 0)))
	var added: bool = e.has("extra_hit") and random.roll("battle") < float(e.extra_hit)
	if added:
		hits.append(float(e.get("power", 0)))
	if e.has("wind_consume") and ctx.caster_layers("wind_force") >= int(e.wind_consume):
		ctx.caster_consume("wind_force", int(e.wind_consume))
		hits.append(float(e.get("wind_hit", 0)))
	if e.has("execute") and start_hp < ctx.target_max_hp * float(e.execute):
		hits.append(float(e.get("execute_hit", 0)))
	var critical := false
	var shield_broken := false
	var landed := 0
	var direct_loss := 0
	var can_crit := bool(e.get("can_crit", ctx.player_caster or ctx.actor_rules))
	var ordinary := bool(e.get("ordinary", false))
	var shield_bonus := float(equipment.get("shield_damage", 0)) / 100.0
	for power in hits:
		if ctx.target_hp() <= 0:
			break
		var hit: Dictionary = ctx.deal_damage(attack, defense, power * scale, can_crit, crit, ordinary, shield_bonus)
		if bool(hit.get("avoided", false)):
			continue
		landed += 1
		critical = critical or bool(hit.get("critical", false))
		shield_broken = shield_broken or bool(hit.get("shield_broken", false))
		direct_loss += int(hit.get("damage", 0))
		_electrify(ctx, config)
	var extra: int = ctx.fortune("lightning_first_hit", str(spell.get("element", "")))
	if landed > 0 and extra > 0 and ctx.use_battle_trigger("lightning_first_hit", true) and ctx.target_hp() > 0:
		ctx.raw_damage(floori(attack * extra / 100.0))
		direct_loss += floori(attack * extra / 100.0)
	var special := consumed * float(e.get("detonate", 0))
	if wet:
		special += float(e.get("wet_bonus", 0))
	if poison > 0:
		special += float(e.get("poison_bonus", 0))
	if burn > 0:
		special += float(e.get("burn_bonus", 0))
	if ctx.target_has("electrified"):
		special += float(e.get("electrified_bonus", 0))
	if str(spell.get("element", "")) == "土" and ctx.target_consume("shock") > 0:
		special += float(config.statuses.shock.value)
	var detonation_start: int = ctx.target_hp()
	if special > 0 and ctx.target_hp() > 0:
		ctx.target.hp = maxi(0, ctx.target_hp() - floori(attack * special))
	var special_loss := maxi(0, detonation_start) - maxi(0, ctx.target_hp())
	var flat_damage := int(e.get("flat", 0)) + floori(ctx.target_max_hp * float(e.get("percent_max_hp", 0)))
	if flat_damage > 0 and ctx.target_hp() > 0:
		direct_loss += ctx.raw_damage(flat_damage)
	if poison >= int(e.get("poison_echo", 999)) and ctx.target_hp() > 0:
		ctx.target.hp = maxi(0, ctx.target_hp() - ctx.target_dot("poison"))
	if landed > 0 and ctx.target_hp() > 0:
		_target_effects(ctx, e, config, attack, random, poison, burn, wet, chill, consumed, critical, shield_broken)
		_apply_status_list(ctx, e.get("statuses", []), attack, random, landed > 0)
		_apply_status_list(ctx, e.get("target_statuses", []), attack, random, landed > 0)
		if e.has("self_statuses") and landed > 0:
			for row in e.self_statuses:
				if row is Dictionary:
					ctx.caster_apply(str(row.get("status", "")), attack, int(row.get("layers", 1)), _status_extra(row))
		if e.has("mana_drain"):
			ctx.target.mp = maxi(0, int(ctx.target.get("mp", 0)) - int(e.mana_drain))
		if e.has("phase") and ctx.caster_side == "enemy" and ctx.battle.get("enemy_ai") is Dictionary:
			ctx.battle.enemy_ai.phase = str(e.phase)
	if e.has("self_status"):
		ctx.caster_apply(str(e.self_status), attack)
	if e.has("hit_intent") and landed > 0:
		ctx.caster_apply("sword_intent", attack)
	if burn > 0 and e.has("burn_intent"):
		ctx.caster_apply("flame_force", attack, int(e.burn_intent))
	if e.has("consume_self_status") and consumed >= int(e.consume_self_threshold):
		ctx.caster_apply(str(e.consume_self_status), attack, int(e.consume_self_layers))
	if added and landed >= hits.size() and e.has("extra_hit_status"):
		ctx.caster_apply(str(e.extra_hit_status), attack)
	if ctx.target_has("shock") and shield:
		ctx.repair_caster_shield(floori(attack * float(e.get("shock_repair", 0))))
	if shield_broken and e.has("shield_break_gain"):
		_create_caster_shield(ctx, {"shield": e.shield_break_gain}, config)
	var leech := float(e.get("poison_leech", e.get("leech", 0))) if poison > 0 else float(e.get("leech", 0))
	ctx.heal_caster(floori(direct_loss * leech))
	if e.has("consume_leech") and consumed >= int(e.consume_leech):
		ctx.heal_caster(mini(floori(special_loss * e.leech_special), floori(ctx.max_hp * e.leech_special)))
	var mana := int(e.get("wet_mana", 0)) if wet else 0
	if poison >= 3:
		mana += int(e.get("poison_mana", 0))
	if ctx.target_hp() <= 0:
		mana += int(e.get("kill_mana", 0))
	if str(spell.get("element", "")) == "风" and landed >= 2:
		mana += int(wind.get("wind_mana", 0))
	if direct_loss > 0:
		mana += affixes.count("mana") * int(config.affixes.mana.value)
	ctx.gain_caster_mana(mana)
	if landed > 0 and ctx.target_hp() > 0:
		if "burn" in affixes:
			ctx.target_apply("burn", attack, affixes.count("burn") * int(config.affixes.burn.value))
		_thunder_echo(ctx, config, random, ctx.target_has("electrified"))
	if "focus" in affixes:
		ctx.target_apply("focus", attack, 1, {"value": config.affixes.focus.value})
	return critical

func _target_effects(ctx, e: Dictionary, config: Dictionary, attack: float, random: RefCounted, poison: int, burn: int, wet: bool, chill: int, consumed: int, critical: bool, shield_broken: bool) -> void:
	if e.has("status"):
		var layers := int(e.get("layers", 1))
		match e.status:
			"poison":
				if poison > 0:
					layers += int(e.get("extra_poison", 0))
			"burn":
				if burn >= int(e.get("extra_burn", 999)):
					layers += 1
			"chill":
				if wet:
					layers += 1 + int(e.get("wet_chill", 0))
			"thunder_mark":
				if critical:
					layers += int(e.get("crit_mark", 0))
		ctx.target_apply(str(e.status), attack, layers)
	if e.has("secondary_status"):
		ctx.target_apply(str(e.secondary_status), attack)
	if e.has("consume_status") and consumed >= int(e.get("consume_threshold", 1)):
		ctx.target_apply(str(e.consume_status), attack)
	if shield_broken and e.has("shield_break_status"):
		ctx.target_apply(str(e.shield_break_status), attack)
	if wet:
		if e.has("wet_weaken"):
			ctx.target_apply("weak_attack", attack, 1, {"value": e.wet_weaken})
		if e.has("wet_status"):
			ctx.target_apply(str(e.wet_status), attack)
	if e.has("slow"):
		ctx.target_apply("slow", attack, 1, {"value": e.slow})
		if chill >= int(e.get("seal", 999)):
			ctx.target_consume("chill", int(e.seal))
			var rule: Dictionary = config.control
			var rank := "normal"
			if not ctx.target_monster_id.is_empty():
				rank = str(rule.monster_ranks.get(ctx.target_monster_id, "normal"))
			var resistance := float(ctx.target_status("control_resistance").get("value", 0))
			if random.roll("battle") < maxf(0, float(rule[rank]) - resistance):
				ctx.target_apply("seal", attack)
				ctx.target_apply("control_resistance", attack, 1, {"value": minf(1.0, resistance + float(rule.resistance_gain))})
				if e.has("seal_weaken"):
					ctx.target_apply("weak_attack", attack, 1, {"value": e.seal_weaken})

func _apply_status_list(ctx, rows: Array, attack: float, random: RefCounted, hit: bool = true) -> void:
	for row in rows:
		if not row is Dictionary:
			continue
		if not _chance(row, random):
			continue
		var status := str(row.get("status", ""))
		if status.is_empty():
			continue
		if bool(row.get("requires_hit", false)) and not hit:
			continue
		var extra := {
			"turns": int(row.get("turns", ctx.data.spell_growth.statuses.get(status, {}).get("turns", 1))),
			"dispellable": bool(row.get("dispellable", true)),
		}
		if row.has("value"):
			extra["value"] = float(row.value)
		if row.has("flat"):
			extra["flat"] = float(row.flat)
		var mode := str(row.get("mode", "stack"))
		var self_target := str(row.get("target", "")) == "self"
		var id: String = ctx.status_id(status, ctx.caster_side if self_target else ctx.target_side)
		if mode == "refresh" and ctx.battle.status.has(id):
			ctx.battle.status[id].turns = int(extra.turns)
			ctx.battle.status[id].merge(extra, true)
		else:
			if mode == "replace":
				ctx.battle.status.erase(id)
			if self_target:
				ctx.caster_apply(status, attack, int(row.get("layers", 1)), extra)
			else:
				ctx.target_apply(status, attack, int(row.get("layers", 1)), extra)
		if row.has("max_layers") and ctx.battle.status.has(id):
			ctx.battle.status[id].layers = mini(maxi(1, int(row.max_layers)), int(ctx.battle.status[id].get("layers", 1)))

func _support(ctx, e: Dictionary, stats: Dictionary, config: Dictionary, element: String) -> void:
	if e.has("heal"):
		var low: bool = ctx.caster_hp() < ctx.max_hp * .3
		var recovery: float = 1.0 + ctx.fortune("wood_heal", element) / 100.0
		ctx.heal_caster(floori(float(stats.get("attack", 0)) * float(e.heal) * recovery * (1.0 + float(e.get("low_heal", 0)) if low else 1.0)))
		if e.has("periodic_heal"):
			ctx.caster_apply("life", float(stats.get("attack", 0)), 1, {"value": e.periodic_heal})
		if low and e.has("cleanse"):
			_cleanse(ctx, ctx.caster_side, 1)
	if e.has("heal_flat"):
		ctx.heal_caster(int(e.heal_flat))
	if e.has("heal_percent"):
		ctx.heal_caster(floori(ctx.max_hp * float(e.heal_percent)))
	if e.has("shield"):
		_create_caster_shield(ctx, e, config)
	if e.has("self_status"):
		ctx.caster_apply(str(e.self_status), float(stats.get("attack", 0)), int(e.get("self_layers", 1)), {"effects": e})
	if e.has("self_statuses"):
		for row in e.self_statuses:
			if row is Dictionary:
				ctx.caster_apply(str(row.get("status", "")), float(stats.get("attack", 0)), int(row.get("layers", 1)), _status_extra(row))
	if e.has("target_statuses"):
		_apply_status_list(ctx, e.target_statuses, float(stats.get("attack", 0)), ctx.random)
	if e.has("statuses"):
		_apply_status_list(ctx, e.statuses, float(stats.get("attack", 0)), ctx.random)
	if e.has("wind_discount"):
		ctx.caster_apply("wind_ready", float(stats.get("attack", 0)), 1, {"effects": e})
	if e.has("thunder_echo"):
		ctx.caster_apply("thunder_echo", float(stats.get("attack", 0)), 1, {"effects": e})
	if e.has("next_discount"):
		ctx.caster_apply("discount", float(stats.get("attack", 0)), 1, {"value": e.next_discount})
	ctx.gain_caster_mana(int(e.get("mana", 0)))
	if e.has("cleanse"):
		if not ctx.player_caster:
			_cleanse(ctx, ctx.caster_side, int(e.cleanse))
	if e.has("phase") and ctx.caster_side == "enemy" and ctx.battle.get("enemy_ai") is Dictionary:
		ctx.battle.enemy_ai.phase = str(e.phase)

func _cleanse(ctx, side: String, count: int) -> void:
	var remaining := maxi(0, count)
	var negatives := ["poison", "burn", "bleed", "chill", "wet", "stun", "root", "silence", "attack_down", "defense_down", "speed_down", "weak_attack", "vulnerability", "armor_break", "slow", "seal", "corrosion"]
	for status in negatives:
		if remaining <= 0:
			break
		var id: String = ctx.status_id(status, side)
		if ctx.battle.status.has(id) and ctx.battle.status[id].get("dispellable", true) == true:
			ctx.battle.status.erase(id)
			remaining -= 1

func _create_caster_shield(ctx, e: Dictionary, config: Dictionary) -> void:
	if ctx.player_caster:
		Status.create_shield(ctx.battle, str(e.get("shield_status", "rock_shield")), config, ctx.caster_stats, e)
		return
	var amount := floori(float(ctx.caster_stats.get("attack", 0)) * float(e.get("shield", 0)))
	amount += floori(ctx.max_hp * float(e.get("shield_percent", 0)))
	amount = mini(amount, floori(ctx.max_hp * float(config.shield_cap)))
	if amount <= 0:
		return
	var status_id := "enemy_shield"
	var turns := int(e.get("shield_turns", config.statuses[status_id].turns))
	Status.apply(ctx.battle, ctx.status_id(status_id, ctx.caster_side), config, float(ctx.caster_stats.get("attack", 0)), 1, {
		"amount": amount, "maximum": amount, "turns": turns, "effects": e,
	})

func _chance(row: Dictionary, random: RefCounted) -> bool:
	var chance := clampf(float(row.get("chance", 1.0)), 0.0, 1.0)
	if chance >= 1.0:
		return true
	if chance <= 0.0:
		return false
	return random.roll("battle") < chance

func _status_extra(row: Dictionary) -> Dictionary:
	var extra := {"turns": int(row.get("turns", 1)), "dispellable": bool(row.get("dispellable", true))}
	if row.has("value"):
		extra["value"] = float(row.value)
	if row.has("flat"):
		extra["flat"] = float(row.flat)
	return extra

func _thunder_echo(ctx, config: Dictionary, random: RefCounted, electrified: bool) -> void:
	var echo: Dictionary = ctx.caster_status("thunder_echo")
	if echo.is_empty():
		return
	ctx.target.hp = maxi(0, ctx.target_hp() - floori(echo.attack * echo.effects.thunder_echo))
	if ctx.target_hp() > 0 and echo.effects.has("echo_mark") and random.roll("battle") < echo.effects.echo_mark:
		ctx.target_apply("thunder_mark", echo.attack)
	if electrified:
		ctx.gain_caster_mana(int(echo.effects.get("echo_mana", 0)))

func _electrify(ctx, config: Dictionary) -> void:
	var status: Dictionary = ctx.target_status("electrified")
	if status.is_empty() or ctx.target_hp() <= 0:
		return
	if status.get("trigger_round", -1) != ctx.battle.turn:
		status.trigger_round = ctx.battle.turn
		status.triggers = 0
	if int(status.triggers) < 2:
		status.triggers += 1
		ctx.target.hp = maxi(0, ctx.target_hp() - floori(status.attack * config.statuses.electrified.value))

func _direct_damage(attack: float, defense: float, multiplier: float, data: Dictionary) -> int:
	return Math.direct_damage(attack, defense, multiplier, data)

func _cast_ordered(ctx, spell: Dictionary, data: Dictionary, random: RefCounted) -> bool:
	var config: Dictionary = data.spell_growth
	var caster: Dictionary = ctx.caster
	var level: int = int(caster.get("spells", {}).get(spell.get("id", ""), 1)) if ctx.player_caster or ctx.actor_rules else 1
	var runtime := _apply_effect_growth(spell, level)
	var wind: Dictionary = ctx.caster_status("wind_ready")
	var affixes: Array = []
	if ctx.player_caster or ctx.actor_rules:
		var stored: Variant = caster.get("spell_affixes", {}).get(spell.get("id", ""), {})
		if stored is Dictionary:
			affixes = stored.values()
	var cost := mana_cost(ctx, runtime)
	caster.mp = maxi(0, int(caster.get("mp", 0)) - cost)
	if int(runtime.get("mp", 0)) > 0:
		ctx.caster_consume("discount")
	if str(spell.get("element", "无")) == "风" and _is_attack(runtime):
		ctx.caster_consume("wind_ready")
	ctx.cooldowns[spell.get("id", "")] = int(runtime.get("cd", runtime.get("cooldown", 0)))
	var critical := false
	for effect in runtime.get("effects", []):
		if not effect is Dictionary:
			continue
		if not bool(effect.get("enabled", true)):
			continue
		var before_target := int(ctx.target_hp())
		var before_caster := int(ctx.caster_hp())
		var before_mp := int(caster.get("mp", 0))
		var one := {
			"id": spell.get("id", ""), "name": spell.get("name", ""),
			"element": spell.get("element", "无"),
			"target": str(effect.get("target", spell.get("target", "enemy"))),
			"effects": [effect],
		}
		var e := _normalize_effects(one)
		var step_crit := false
		if e.has("power"):
			step_crit = _attack(ctx, spell, e, ctx.caster_stats, data, random, _direct_damage.bind(data), affixes, wind)
			critical = critical or step_crit
		else:
			_support(ctx, e, ctx.caster_stats, config, str(spell.get("element", "无")))
		if ctx.battle.get("effect_trace") is Array:
			ctx.battle.effect_trace.append({
				"effect_id": str(effect.get("effect_id", effect.get("type", ""))),
				"type": str(effect.get("type", "")),
				"target_loss": before_target - ctx.target_hp(),
				"caster_gain": ctx.caster_hp() - before_caster,
				"mp_delta": int(caster.get("mp", 0)) - before_mp,
				"critical": step_crit,
			})
	last_critical = critical
	return critical

func _apply_effect_growth(spell: Dictionary, level: int) -> Dictionary:
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
	if patches is Dictionary and copy.get("effects") is Array:
		for key in patches:
			var effect_index := int(str(key))
			if effect_index >= 0 and effect_index < copy.effects.size() and patches[key] is Dictionary and copy.effects[effect_index] is Dictionary:
				copy.effects[effect_index].merge(patches[key], true)
	return copy

func _normalize_effects(skill: Dictionary) -> Dictionary:
	var e := {}
	var skill_target := str(skill.get("target", "enemy"))
	if bool(skill.get("ordinary", false)):
		e["ordinary"] = true
	for effect in skill.get("effects", []):
		if not effect is Dictionary:
			continue
		if not bool(effect.get("enabled", true)):
			continue
		var kind := str(effect.get("type", ""))
		var target := str(effect.get("target", "self" if skill_target == "self" else "enemy"))
		match kind:
			"damage":
				e["power"] = float(effect.get("power", 0))
				e["hits"] = int(effect.get("hits", 1))
				e["can_crit"] = bool(effect.get("can_crit", false))
				if effect.has("flat"):
					e["flat"] = int(effect.flat)
				if effect.has("percent_max_hp"):
					e["percent_max_hp"] = float(effect.percent_max_hp)
				if effect.has("lifesteal"):
					e["leech"] = float(effect.lifesteal)
			"status":
				if not e.has("statuses"):
					e["statuses"] = []
				e.statuses.append(_status_row(effect, target))
			"stat":
				var stat_status := str(effect.get("stat", "attack")) + ("_up" if float(effect.get("value", 0)) >= 0 else "_down")
				var row := {
					"status": stat_status,
					"value": absf(float(effect.get("value", 0))),
					"turns": int(effect.get("turns", 1)),
					"layers": int(effect.get("layers", 1)),
					"chance": float(effect.get("chance", 1.0)),
					"requires_hit": bool(effect.get("requires_hit", false)),
				}
				if effect.has("max_layers"):
					row["max_layers"] = int(effect.max_layers)
				if target == "self":
					if not e.has("self_statuses"):
						e["self_statuses"] = []
					e.self_statuses.append(row)
				else:
					if not e.has("target_statuses"):
						e["target_statuses"] = []
					e.target_statuses.append(row)
			"heal":
				if effect.has("power"):
					e["heal"] = float(effect.power)
				if effect.has("amount"):
					e["heal_flat"] = int(effect.amount)
				if effect.has("percent_max_hp"):
					e["heal_percent"] = float(effect.percent_max_hp)
				if effect.has("periodic"):
					e["periodic_heal"] = float(effect.periodic)
			"shield":
				e["shield"] = float(effect.get("power", 0))
				e["shield_percent"] = float(effect.get("percent_max_hp", 0))
				e["shield_turns"] = int(effect.get("turns", 0))
			"mana":
				if bool(effect.get("drain", false)):
					e["mana_drain"] = int(effect.get("amount", 0))
				else:
					e["mana"] = int(effect.get("amount", 0))
			"cleanse":
				e["cleanse"] = int(effect.get("count", 1))
			"phase":
				e["phase"] = str(effect.get("value", ""))
	return e

func _status_row(effect: Dictionary, target: String) -> Dictionary:
	var row := {
		"status": str(effect.get("status", "")),
		"chance": float(effect.get("chance", 1.0)),
		"turns": int(effect.get("turns", 1)),
		"layers": int(effect.get("layers", 1)),
		"requires_hit": bool(effect.get("requires_hit", false)),
		"mode": str(effect.get("mode", "stack")),
		"target": target,
	}
	if effect.has("value"):
		row["value"] = float(effect.value)
	if effect.has("flat"):
		row["flat"] = float(effect.flat)
	if effect.has("max_layers"):
		row["max_layers"] = int(effect.max_layers)
	if effect.has("dispellable"):
		row["dispellable"] = bool(effect.dispellable)
	return row
