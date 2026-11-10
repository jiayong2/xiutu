extends RefCounted
## Side-aware combat context shared by player, NPC and monster skill casts.
## It owns no rules; it only exposes the caster/target, resources, statuses and
## callbacks needed by SkillEngine.

const Status = preload("res://gameplay/battle/battle_status.gd")
const Fortunes = preload("res://gameplay/character/player_fortunes.gd")
const Math = preload("res://gameplay/battle/combat_math.gd")

var battle: Dictionary
var data: Dictionary
var caster: Dictionary
var target: Dictionary
var caster_stats: Dictionary
var target_stats: Dictionary
var caster_side: String
var target_side: String
var random: RefCounted
var roll: Callable
var monster_hit: Callable
var raw_target: Callable
var max_hp: int
var max_mp: int
var target_max_hp: int
var target_max_mp: int
var cooldowns: Dictionary
var player_caster := false
## NPC casters use the player's spell level, fortune, mana and damage formula,
## while remaining on the non-player side for status and incoming damage.
var actor_rules := false
var root := ""
var spell_bps := 0.0
var fire := 0.0
var equipment: Dictionary = {}
var affixes: Array = []
var target_monster_id := ""

static func for_player(s: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted,
		roll: Callable, raw_target: Callable = Callable()) -> RefCounted:
	var ctx = load("res://gameplay/battle/combat_context.gd").new()
	ctx.battle = s.battle
	ctx.data = data
	ctx.caster = s.player
	ctx.target = s.battle.get("enemy", {})
	ctx.caster_stats = stats
	ctx.target_stats = ctx.target
	ctx.caster_side = "player"
	ctx.target_side = "enemy"
	ctx.random = random
	ctx.roll = roll
	ctx.raw_target = raw_target
	ctx.max_hp = int(stats.get("hp", s.player.get("hp", 1)))
	ctx.max_mp = int(stats.get("mp", s.player.get("mp", 0)))
	var preview_monster := str(s.battle.get("monster", ""))
	ctx.target_max_hp = int(data.monsters[preview_monster].get("hp", 1)) if data.monsters.has(preview_monster) else 1
	ctx.target_max_mp = int(data.monsters[preview_monster].get("mp", 0)) if data.monsters.has(preview_monster) else 0
	ctx.cooldowns = s.battle.get("cooldowns", {}) if s.battle.get("cooldowns") is Dictionary else {}
	ctx.player_caster = true
	ctx.root = str(s.player.get("root", ""))
	ctx.spell_bps = float(stats.get("spell_bps", 0))
	ctx.fire = float(stats.get("fire", 0))
	ctx.equipment = stats.get("equipment_effects", {})
	ctx.target_monster_id = preview_monster
	return ctx

static func for_monster(s: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted,
		monster_hit: Callable, raw_target: Callable = Callable()) -> RefCounted:
	var ctx = load("res://gameplay/battle/combat_context.gd").new()
	var b: Dictionary = s.battle
	ctx.battle = b
	ctx.data = data
	ctx.caster = b.enemy
	ctx.target = s.player
	ctx.caster_stats = {
		"attack": float(b.enemy.get("attack", 0)) * maxf(0.0, 1.0 + Status.stat_modifier(b, "enemy", "attack", data.spell_growth)),
		"defense": float(b.enemy.get("defense", 0)) * maxf(0.0, 1.0 + Status.stat_modifier(b, "enemy", "defense", data.spell_growth)),
		"speed": float(b.enemy.get("speed", 0)) * maxf(0.0, 1.0 + Status.stat_modifier(b, "enemy", "speed", data.spell_growth)),
		"hp": int(b.get("enemy_max_hp", b.enemy.get("hp", 1))),
		"mp": int(b.get("enemy_max_mp", b.enemy.get("mp", 0))),
	}
	ctx.target_stats = stats
	ctx.caster_side = "enemy"
	ctx.target_side = "player"
	ctx.random = random
	ctx.monster_hit = monster_hit
	ctx.raw_target = raw_target
	ctx.max_hp = int(b.get("enemy_max_hp", b.enemy.get("hp", 1)))
	ctx.max_mp = int(b.get("enemy_max_mp", b.enemy.get("mp", 0)))
	ctx.target_max_hp = int(stats.get("hp", 1))
	ctx.target_max_mp = int(stats.get("mp", 0))
	if not b.get("enemy_ai") is Dictionary:
		b["enemy_ai"] = {}
	if not b.enemy_ai.get("cooldowns") is Dictionary:
		b.enemy_ai["cooldowns"] = {}
	ctx.cooldowns = b.enemy_ai.cooldowns
	return ctx

## NPC context. The caster stays on the non-player side. Spell level, fortune,
## mana and the direct-damage formula follow the player rules.
static func for_npc(s: Dictionary, npc: Dictionary, npc_stats: Dictionary, target: Dictionary, target_stats: Dictionary,
		data: Dictionary, random: RefCounted, hit_target: Callable, raw_target: Callable = Callable()) -> RefCounted:
	var ctx = load("res://gameplay/battle/combat_context.gd").new()
	ctx.battle = s.battle
	ctx.data = data
	ctx.caster = npc
	ctx.target = target
	ctx.caster_stats = npc_stats
	ctx.target_stats = target_stats
	ctx.caster_side = "enemy"
	ctx.target_side = "player"
	ctx.random = random
	ctx.monster_hit = hit_target
	ctx.raw_target = raw_target
	ctx.actor_rules = true
	ctx.roll = func(attack: float, defense: float, multiplier: float, payload: Dictionary) -> int:
		return Math.direct_damage(attack, defense, multiplier, payload)
	ctx.max_hp = int(s.battle.get("enemy_max_hp", npc_stats.get("hp", 1)))
	ctx.max_mp = int(s.battle.get("enemy_max_mp", npc_stats.get("mp", 0)))
	ctx.target_max_hp = int(target_stats.get("hp", 1))
	ctx.target_max_mp = int(target_stats.get("mp", 0))
	ctx.root = str(npc.get("root", ""))
	ctx.spell_bps = float(npc_stats.get("spell_bps", 0))
	ctx.fire = float(npc_stats.get("fire", 0))
	ctx.equipment = npc_stats.get("equipment_effects", {}) if npc_stats.get("equipment_effects") is Dictionary else {}
	if not s.battle.get("enemy_ai") is Dictionary:
		s.battle["enemy_ai"] = {}
	if not s.battle.enemy_ai.get("cooldowns") is Dictionary:
		s.battle.enemy_ai["cooldowns"] = {}
	ctx.cooldowns = s.battle.enemy_ai.cooldowns
	return ctx

func status_id(id: String, side: String) -> String:
	if id.is_empty():
		return id
	if id in Status.PLAYER or id in Status.PLAYER_NEGATIVE:
		return id
	if side == "player":
		return "player_" + id if not id.begins_with("player_") else id
	return id

func target_status(id: String) -> Dictionary:
	return battle.get("status", {}).get(status_id(id, target_side), {})

func target_status_id(id: String) -> String:
	return status_id(id, target_side)

func target_has(id: String) -> bool:
	return battle.get("status", {}).has(status_id(id, target_side))

func target_layers(id: String) -> int:
	return Status.layers(battle, status_id(id, target_side))

func target_ratio(id: String) -> float:
	return float(target_layers(id)) * float(data.spell_growth.statuses.get(id, {}).get("value", 0))

func target_dot(id: String) -> int:
	return Status.dot(battle, status_id(id, target_side), data.spell_growth)

func target_consume(id: String, count: int = 999) -> int:
	return Status.consume(battle, status_id(id, target_side), count)

func target_apply(id: String, attack: float, layers: int = 1, extra: Dictionary = {}) -> void:
	Status.apply(battle, status_id(id, target_side), data.spell_growth, attack, layers, extra)

func caster_status(id: String) -> Dictionary:
	return battle.get("status", {}).get(status_id(id, caster_side), {})

func caster_has(id: String) -> bool:
	return battle.get("status", {}).has(status_id(id, caster_side))

func caster_layers(id: String) -> int:
	return Status.layers(battle, status_id(id, caster_side))

func caster_ratio(id: String) -> float:
	return float(caster_layers(id)) * float(data.spell_growth.statuses.get(id, {}).get("value", 0))

func caster_consume(id: String, count: int = 999) -> int:
	return Status.consume(battle, status_id(id, caster_side), count)

func caster_apply(id: String, attack: float, layers: int = 1, extra: Dictionary = {}) -> void:
	Status.apply(battle, status_id(id, caster_side), data.spell_growth, attack, layers, extra)

func target_shield_id() -> String:
	if target_side == "player":
		return Status.shield_id(battle)
	return "enemy_shield" if battle.status.has("enemy_shield") else ""

func target_has_shield() -> bool:
	return not target_shield_id().is_empty()

func target_shield() -> Dictionary:
	return battle.status.get(target_shield_id(), {})

func caster_shield_id() -> String:
	if player_caster:
		return Status.shield_id(battle)
	return "enemy_shield" if battle.status.has("enemy_shield") else ""

func caster_shield() -> Dictionary:
	return battle.status.get(caster_shield_id(), {})

func target_hp() -> int:
	return int(target.get("hp", 0))

func caster_hp() -> int:
	return int(caster.get("hp", 0))

func target_defense() -> float:
	if target_side == "player":
		var defense := float(target_stats.get("defense", target.get("defense", 0))) * maxf(0.0, 1.0 + Status.stat_modifier(battle, "player", "defense", data.spell_growth))
		if target_hp() * 100 < int(target_stats.get("hp", 1)) * 30:
			defense *= 1.0 + float(Fortunes.modifier(target, "defense_low_hp")) / 100.0
		defense += float(battle.get("status", {}).get("guard", {}).get("amount", 0))
		return defense
	return float(target.get("defense", 0)) * maxf(0.0, 1.0 + Status.stat_modifier(battle, "enemy", "defense", data.spell_growth))

func deal_damage(attack_value: float, defense: float, multiplier: float, can_crit: bool, crit_bonus: float, ordinary: bool, shield_bonus: float = 0.0) -> Dictionary:
	if player_caster or actor_rules:
		var chance := float(data.rules.crit_chance)
		var power := float(data.rules.crit_multiplier)
		if actor_rules and not player_caster:
			chance = float(caster_stats.get("critical", chance))
			power = float(caster_stats.get("critical_damage", power))
		elif player_caster:
			chance += float(caster_stats.get("critical", 0.0))
			power += float(caster_stats.get("critical_damage", 0.0))
		var crit := 1.0
		var critical := false
		if can_crit and random != null and random.roll("battle") < clampf(chance + crit_bonus, 0.0, 1.0):
			crit = power
			critical = true
		var amount: int = roll.call(attack_value, defense, multiplier * crit, data)
		if player_caster:
			var before := target_hp()
			var broke := hit_target_enemy(amount, shield_bonus)
			return {"damage": before - target_hp(), "critical": critical, "shield_broken": broke, "avoided": false}
		return {"damage": raw_damage(amount), "critical": critical, "shield_broken": false, "avoided": false}
	var hit: Dictionary = monster_hit.call(multiplier, ordinary, can_crit)
	return {"damage": int(hit.get("damage", 0)), "critical": bool(hit.get("critical", false)),
		"shield_broken": false, "avoided": bool(hit.get("avoided", false))}

func hit_target_enemy(amount: int, shield_bonus: float = 0.0) -> bool:
	var reduction := clampf(Status.reduction(battle, "enemy", data.spell_growth) + (0.5 if battle.get("enemy_guard", false) else 0.0), 0.0, 0.75)
	amount = roundi(amount * (1.0 - reduction))
	if not target_has_shield():
		target.hp = maxi(0, target_hp() - amount)
		return false
	var shield: Dictionary = target_shield()
	var absorbed := mini(roundi(amount * (1.0 + shield_bonus)), int(shield.amount))
	shield.amount -= absorbed
	target.hp = maxi(0, target_hp() - maxi(0, amount - ceili(absorbed / (1.0 + shield_bonus))))
	if shield.amount == 0:
		target_consume("enemy_shield")
		return true
	return false

func raw_damage(amount: int) -> int:
	if raw_target.is_valid():
		return int(raw_target.call(amount))
	target.hp = maxi(0, target_hp() - amount)
	return amount

func heal_caster(amount: int) -> int:
	if amount <= 0:
		return 0
	var scale := 1.0
	if player_caster:
		scale *= 1.0 - Status.ratio(battle, "player_corrosion", data.spell_growth)
		scale *= 1.0 + float(equipment.get("healing_received", 0)) / 100.0
	else:
		scale *= 1.0 - Status.ratio(battle, status_id("corrosion", caster_side), data.spell_growth)
	var before := caster_hp()
	caster.hp = mini(max_hp, before + floori(amount * scale))
	return int(caster.hp) - before

func gain_caster_mana(amount: int) -> void:
	if amount <= 0:
		return
	caster.mp = mini(max_mp, int(caster.get("mp", 0)) + amount)

func repair_caster_shield(amount: int) -> void:
	var id := caster_shield_id()
	if id.is_empty() or amount <= 0:
		return
	var shield: Dictionary = battle.status[id]
	shield.amount = mini(int(shield.get("maximum", shield.amount)), int(shield.amount) + amount)

func fortune(type: String, arg: String = "", unit: String = "%") -> int:
	return Fortunes.modifier(caster, type, arg, unit) if player_caster or actor_rules else 0

func use_battle_trigger(type: String, once: bool = true) -> bool:
	return Fortunes.use_battle_trigger(battle, type, once) if player_caster or actor_rules else false
