extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")
const Status = preload("res://gameplay/battle/battle_status.gd")
const Spells = preload("res://gameplay/battle/spell_progression.gd")
const Skills = preload("res://gameplay/battle/skill_engine.gd")
const BeastAI = preload("res://gameplay/battle/monster_ai.gd")
const NpcAI = preload("res://gameplay/battle/npc_ai.gd")
const Math = preload("res://gameplay/battle/combat_math.gd")
const PLAYER_RESTORE := ["hp", "mp", "blood", "inventory", "spells", "spell_mastery", "fortunes", "fortune_progress", "fortune_wins"]
const RECOVERY_ITEMS := ["item_healing_powder", "item_aura_powder", "pill_healing", "pill_mana_restore"]
var skills := Skills.new()
var last_critical := false

static func is_npc_duel(battle: Dictionary) -> bool:
	return str(battle.get("battle_type", "")) in ["npc_test", "sect_spar", "sect_exam"]

static func is_friendly(battle: Dictionary) -> bool:
	return str(battle.get("battle_type", "")) in ["sect_spar", "sect_exam"]

func start_npc_test(s: Dictionary, npc: Dictionary, data: Dictionary, identity: String, battle_random: String) -> String:
	return _start_npc_duel(s, npc, data, identity, "npc_test", battle_random)

func start_npc_duel(s: Dictionary, npc: Dictionary, data: Dictionary, identity: String, battle_type: String) -> String:
	if battle_type not in ["sect_spar", "sect_exam"]:
		return "战斗类型无效"
	return _start_npc_duel(s, npc, data, identity, battle_type, "")

func _start_npc_duel(s: Dictionary, npc: Dictionary, data: Dictionary, identity: String, battle_type: String, battle_random: String) -> String:
	if not s.battle.is_empty():
		return "已有战斗"
	var built: Dictionary = preload("res://gameplay/battle/npc_combatant.gd").build(npc, data)
	if built.is_empty() or str(built.enemy.get("name", "")).is_empty() or int(built.enemy.hp) <= 0:
		return "无法生成 NPC 战斗单位"
	s.erase("battle_report")
	var restore := {}
	for key in PLAYER_RESTORE:
		if s.player.has(key):
			var value: Variant = s.player[key]
			restore[key] = value.duplicate(true) if value is Dictionary or value is Array else value
		else:
			restore[key] = null
	s.battle = {
		"id": identity,
		"battle_type": battle_type,
		"npc_id": str(npc.get("id", "")),
		"player_id": str(s.player.get("id", "")),
		"phase": "prepare",
		"monster": "",
		"enemy": built.enemy,
		"enemy_max_hp": int(built.stats.get("hp", 1)),
		"enemy_max_mp": int(built.stats.get("mp", 0)),
		"enemy_stats": built.stats,
		"enemy_ai": {"actions": 0, "uses": {}, "cooldowns": {}, "rule_cooldowns": {}, "trigger_uses": {}, "phase": ""},
		"turn": 0,
		"status": {},
		"cooldowns": {},
		"guard": false,
		"log": [],
		"log_entries": [],
		"restore_player": restore,
	}
	if battle_type == "npc_test":
		s.battle.restore_battle_random = battle_random
	return ""

func start(s: Dictionary, monster: String, data: Dictionary, identity: String) -> String:
	if not s.battle.is_empty() or not data.monsters.has(monster):
		return "已有战斗或怪物不存在"
	s.erase("battle_report")
	var definition: Dictionary = data.monsters[monster].duplicate(true)
	var skill_snapshot := {}
	for id in definition.get("skill_ids", []):
		if data.get("monster_skills", {}).has(id):
			skill_snapshot[id] = data.monster_skills[id].duplicate(true)
	s.battle = {"id":identity,"phase":"prepare","monster":monster,"enemy":definition,
		"enemy_max_hp":int(definition.get("hp", 1)),"enemy_max_mp":int(definition.get("mp", 0)),
		"enemy_skills":skill_snapshot,"enemy_ai":{"actions":0,"uses":{},"cooldowns":{},
			"rule_cooldowns":{},"trigger_uses":{},"phase":""},
		"turn":0,"status":{},"cooldowns":{},"guard":false,"log":[],"log_entries":[]}
	return ""

func needs_round(battle: Dictionary) -> bool:
	return not battle.is_empty() and not battle.has("round_order")

func waiting_order(battle: Dictionary) -> Array:
	var order: Array = battle.get("round_order",[])
	return order.slice(order.find("player")) if not order.is_empty() else []

func display_round(battle: Dictionary) -> int:
	var order: Array = battle.get("round_order",[])
	return int(battle.turn)+(0 if order == ["enemy","player"] else 1)

func begin(s: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted, inventory: RefCounted) -> String:
	if not needs_round(s.battle):
		return "战斗已开始，当前等待玩家行动"
	BeastAI.ensure_state(s.battle)
	_begin_events(s.battle)
	if not is_npc_duel(s.battle):
		_run_enemy_passives(s,data,stats,random)
		_run_enemy_triggers(s,data,stats,random,"battle_start")
	_open_round(s,data,stats,random,inventory)
	return ""

func action(s: Dictionary, args: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted, inventory: RefCounted) -> String:
	if s.battle.is_empty():
		return "没有进行中的战斗"
	var b: Dictionary = s.battle
	BeastAI.ensure_state(b)
	var kind: String = args.get("kind","attack")
	if kind not in ["attack","spell","defend","item","escape"]:
		return "无效行动"
	_begin_events(b)
	# Legacy callers and saves may reach the first command without an open round.
	if needs_round(b):
		_open_round(s,data,stats,random,inventory)
		if not s.pending_battle_result.is_empty():
			return ""
	if b.status.has("player_stun") and not (kind == "escape" and is_npc_duel(b)):
		kind = "stun"
	var spell: Dictionary = {}
	if kind == "spell":
		if b.status.has("player_silence"):
			return "被禁术，无法施法"
		var id: String = args.get("id","")
		if id not in s.player.spell_slots or not data.spells.has(id):
			return "法术未装备"
		spell = data.spells[id]
		if s.player.mp < skills.preview_mana_cost(s,spell,stats,data) or b.cooldowns.get(id,0) > 0:
			return "灵力不足或法术冷却中"
	if kind == "item":
		if args.get("id","") not in RECOVERY_ITEMS:
			return "战斗中只能使用恢复道具"
		var validation: String = inventory.use(s.player.duplicate(true),args.id,data,stats,int(s.hours/24))
		if not validation.is_empty():
			return validation
	if kind == "escape" and not is_npc_duel(b) and b.status.has("player_root"):
		return "被缠绕，无法逃跑"
	var player_first: bool = b.round_order[0]=="player"
	if player_first:
		_start_round(b)
	_resolve_actor(s,"player",kind,args,spell,data,stats,random,inventory)
	if player_first and s.pending_battle_result.is_empty():
		_resolve_actor(s,"enemy","attack",{},{},data,stats,random,inventory)
	_log_round_end(s)
	if s.pending_battle_result.is_empty():
		_open_round(s,data,stats,random,inventory)
	return ""

func _begin_events(b: Dictionary) -> void:
	if not b.has("log_entries"):
		b.log_entries = []
		for line in b.log:
			b.log_entries.append({"type":"legacy","text":line})
	b.events = []
	b.phase = "active"

func _open_round(s: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted, inventory: RefCounted) -> void:
	var b: Dictionary = s.battle
	if int(b.turn) == 0 and not b.has("round_order"):
		Skills.gain_mana(s.player,stats,floori(stats.mp * Fortunes.modifier(s.player,"battle_start_mana") / 100.0))
		var opening := mini(int(stats.get("equipment_effects",{}).get("opening_shield",0)),floori(stats.hp * float(data.spell_growth.shield_cap)))
		if opening > 0:
			Status.apply(b,"rock_shield",data.spell_growth,stats.attack,1,{"amount":opening,"maximum":opening})
		var hp_percent := Fortunes.modifier(s.player,"battle_start_hp")
		if hp_percent != 0:
			s.player.hp = maxi(1,s.player.hp + int(stats.hp * hp_percent / 100.0))
		if is_npc_duel(b):
			var enemy_stats: Dictionary = b.get("enemy_stats", {})
			Skills.gain_mana(b.enemy, enemy_stats, floori(float(enemy_stats.get("mp", 0)) * Fortunes.modifier(b.enemy, "battle_start_mana") / 100.0))
			var enemy_hp := Fortunes.modifier(b.enemy, "battle_start_hp")
			if enemy_hp != 0:
				b.enemy.hp = clampi(int(b.enemy.hp) + int(float(enemy_stats.get("hp", 1)) * enemy_hp / 100.0), 1, int(b.get("enemy_max_hp", enemy_stats.get("hp", 1))))
	var mana_percent := Fortunes.modifier(s.player,"round_mana")
	if mana_percent > 0:
		Skills.gain_mana(s.player,stats,maxi(1,floori(stats.mp * mana_percent / 100.0)))
	if is_npc_duel(b):
		var enemy_round := Fortunes.modifier(b.enemy, "round_mana")
		if enemy_round > 0:
			Skills.gain_mana(b.enemy, b.get("enemy_stats", {}), maxi(1, floori(float(b.enemy_stats.get("mp", 0)) * enemy_round / 100.0)))
	b.round_order = action_order(stats,b,data.spell_growth)
	if b.round_order[0]=="enemy":
		_start_round(b)
		_resolve_actor(s,"enemy","attack",{},{},data,stats,random,inventory)
		if not s.pending_battle_result.is_empty():
			_log_round_end(s)

func _start_round(b: Dictionary) -> void:
	b.turn += 1
	b.log_entries.append({"type":"round","turn":b.turn})

func _log_round_end(s: Dictionary) -> void:
	var b: Dictionary = s.battle
	b.log.append("第 %s 轮：生命 %s，敌方生命 %s" % [b.turn,s.player.hp,maxi(0,int(b.enemy.hp))])

func _resolve_actor(s: Dictionary, actor: String, kind: String, args: Dictionary, spell: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted, inventory: RefCounted) -> void:
	var b: Dictionary = s.battle
	b.acting = actor
	var before := _frame(s)
	last_critical = false
	var avoided := false
	var ended := ""
	var label: String
	if actor=="player":
		label = {"attack":"普通攻击","defend":"防御","escape":"逃跑","stun":"眩晕"}.get(kind,"")
		b.guard = false
		if kind == "stun":
			kind = "special"
			b.log_entries.append({"type":"system","text":"%s 被眩晕，无法行动。" % s.player.name})
		else:
			for id in b.cooldowns:
				b.cooldowns[id] = maxi(0,int(b.cooldowns[id])-1)
			match kind:
				"escape":
					if is_friendly(b):
						ended = "escape"
						label = "认输"
					elif b.get("battle_type") == "npc_test":
						ended = "escape"
						label = "结束测试"
					elif random.roll("battle") < data.rules.escape_chance:
						ended = "escape"
				"defend":
					b.guard = true
				"item":
					label = data.items[args.id].name
					inventory.use(s.player,args.id,data,stats,int(s.hours/24))
				"spell":
					label = spell.name
					last_critical = skills.cast_player_spell(s,spell,stats,data,random,_direct_damage)
					var hp_cost := Fortunes.modifier(s.player,"fire_hp_cost",spell.element)
					s.player.hp -= floori(stats.hp * hp_cost / 100.0)
					if spell.has("levels"):
						Spells.add_mastery(s.player,spell.id,int(data.spell_growth.battle_gain),data)
				"attack":
					skills.player_basic_attack(s,stats,data,random,damage.bind(random,true,float(stats.get("equipment_effects",{}).get("critical",0))/100.0))
		_end_action(s,stats,data,true)
	else:
		var outcome := _resolve_enemy_action(s,data,stats,random)
		kind = outcome.kind
		label = outcome.label
		avoided = outcome.avoided
		last_critical = outcome.critical
		if bool(outcome.get("enemy_escape", false)):
			ended = "enemy_escape"
		_end_action(s,stats,data,false)
	var player: Dictionary = s.player
	if player.hp > 0 and player.hp * 100 < stats.hp * 30:
		var world_seconds: int = int(s.hours) * 3600 + int(s.get("time_seconds",0))
		var names := Fortunes.record_event(player,"battle_low_hp",world_seconds,int(data.rules.hours_day)*3600,"战斗中重伤")
		if not names.is_empty():
			var blood := Fortunes.modifier(player,"blood_recovery_on_grant")
			player.blood = mini(int(stats.blood),int(player.blood)+floori(stats.blood * blood / 100.0))
	var friendly_down := false
	if is_friendly(b) and ended != "escape":
		if int(b.enemy.hp) <= 1:
			b.enemy.hp = 1
			friendly_down = true
		if int(s.player.hp) <= 1:
			s.player.hp = 1
			friendly_down = true
	if not friendly_down and b.round_order[1] == actor and ended.is_empty() and s.player.hp > 0 and b.enemy.hp > 0:
		var recovery := Fortunes.modifier(s.player,"round_heal")
		if recovery > 0:
			Skills.heal_player(s,stats,floori(stats.hp * recovery / 100.0),b,data.spell_growth)
	var event := {"actor":actor,"kind":kind,"label":label,"before":before,"after":_frame(s),"critical":last_critical,"turn":b.turn}
	b.events.append(event)
	_append_event_log(s,event,data.spell_growth.statuses)
	if avoided:
		b.log_entries.append({"type":"avoidance","target":s.player.name,"outcome":"dodge"})
	if is_friendly(b):
		if ended != "escape":
			if int(s.player.hp) <= 1:
				ended = "lose"
			elif int(b.enemy.hp) <= 1:
				ended = "win"
	else:
		if b.enemy.hp <= 0:
			ended = "win"
		if s.player.hp <= 0:
			ended = "lose"
	if not ended.is_empty():
		s.pending_battle_result = ended
	b.erase("acting")

func _resolve_enemy_action(s: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted) -> Dictionary:
	var b: Dictionary = s.battle
	if is_npc_duel(b):
		return _resolve_npc_action(s, data, stats, random)
	_run_enemy_triggers(s,data,stats,random,"turn_start")
	_run_enemy_triggers(s,data,stats,random,"hp_below")
	b["enemy_guard"] = false
	if b.status.has("stun"):
		b.log_entries.append({"type":"system","text":"%s 被眩晕，无法行动。" % b.enemy.name})
		return {"kind":"special","label":"眩晕","avoided":false,"critical":false}
	if not BeastAI.configured(b.enemy):
		var avoided := _enemy_attack(s,stats,data,random,1.0,true)
		return {"kind":"attack","label":"普通攻击","avoided":avoided,"critical":false}
	BeastAI.begin_action(b)
	var plan: Dictionary = BeastAI.choose(b,b.enemy,data,random)
	var outcome := {"kind":"attack","label":str(plan.get("label","普通攻击")),"avoided":false,"critical":false}
	match str(plan.get("action","attack")):
		"skill":
			var skill: Dictionary = plan.get("skill",{})
			var cast := _cast_enemy_skill(s,plan,data,stats,random)
			outcome.avoided = bool(cast.get("avoided",false))
			outcome.critical = bool(cast.get("critical",false))
			outcome.kind = "attack" if bool(skill.get("ordinary",false)) else "special"
		"defend":
			b["enemy_guard"] = true
			outcome.kind = "defend"
			outcome.label = "防御"
		"charge":
			b["enemy_charge"] = 1.5
			outcome.kind = "special"
			outcome.label = "蓄力"
		"flee":
			outcome.kind = "escape"
			outcome.label = "逃跑"
			outcome["enemy_escape"] = true
		_:
			outcome.avoided = _enemy_attack(s,stats,data,random,1.0,true)
			outcome.kind = "attack"
			outcome.label = "普通攻击"
	BeastAI.record_plan(b,plan)
	return outcome

func _resolve_npc_action(s: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted) -> Dictionary:
	var b: Dictionary = s.battle
	b["enemy_guard"] = false
	if b.status.has("stun"):
		b.log_entries.append({"type":"system","text":"%s 被眩晕，无法行动。" % b.enemy.name})
		return {"kind":"special","label":"眩晕","avoided":false,"critical":false}
	for id in b.enemy_ai.cooldowns.keys():
		b.enemy_ai.cooldowns[id] = maxi(0, int(b.enemy_ai.cooldowns[id]) - 1)
	var plan: Dictionary = NpcAI.choose(b, data, func(spell: Dictionary) -> int: return skills.npc_mana_cost(s, spell, b.enemy_stats, data))
	match str(plan.get("action", "attack")):
		"spell":
			var cast := _cast_npc_spell(s, plan.get("skill", {}), data, stats, random)
			return {"kind":"spell","label":str(plan.get("label", "法术")),"avoided":bool(cast.get("avoided", false)),"critical":bool(cast.get("critical", false))}
		"defend":
			b["enemy_guard"] = true
			return {"kind":"defend","label":"防御","avoided":false,"critical":false}
		_:
			var receive := func(amount: int) -> int: return _npc_receive(s, stats, data, amount)
			var critical := skills.npc_basic_attack(s, b.enemy_stats, stats, data, random, receive)
			return {"kind":"attack","label":"普通攻击","avoided":false,"critical":critical}

func _cast_npc_spell(s: Dictionary, spell: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted) -> Dictionary:
	if spell.is_empty():
		return {"avoided":false,"critical":false}
	var b: Dictionary = s.battle
	var receive := func(amount: int) -> int: return _npc_receive(s, stats, data, amount)
	var critical := skills.cast_npc_skill(s, b.enemy, b.enemy_stats, s.player, stats, spell, data, random, Callable(), receive)
	var hp_cost := Fortunes.modifier(b.enemy, "fire_hp_cost", str(spell.get("element", "")))
	b.enemy.hp -= floori(float(b.enemy_stats.get("hp", 1)) * hp_cost / 100.0)
	return {"avoided":false,"critical":critical}

func _npc_receive(s: Dictionary, stats: Dictionary, data: Dictionary, amount: int) -> int:
	var b: Dictionary = s.battle
	var config: Dictionary = data.spell_growth
	var shield_id := Status.shield_id(b)
	var shield_effects: Dictionary = b.status.get(shield_id, {}).get("effects", {})
	var stand_effects: Dictionary = b.status.get("stand", {}).get("effects", {})
	var reduction := float(shield_effects.get("reduction", 0)) + float(stand_effects.get("reduction", 0)) + Status.reduction(b, "player", config)
	if b.guard:
		reduction += 0.5
	amount = roundi(float(amount) * (1.0 - minf(reduction, float(config.reduction_cap))))
	var weakened := float(b.status.get("weak_attack", {}).get("value", 0))
	if weakened > 0.0:
		amount = roundi(float(amount) * (1.0 - weakened))
		Status.consume(b, "weak_attack")
	return _apply_player_damage(s, stats, amount, data)

func _cast_enemy_skill(s: Dictionary, plan: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted) -> Dictionary:
	var skill: Dictionary = plan.get("skill",{})
	if skill.is_empty():
		return {"avoided":false,"critical":false}
	var hit_player := func(power: float, ordinary: bool, can_crit: bool) -> Dictionary:
		return _enemy_hit(s,stats,data,random,power,ordinary,can_crit)
	var raw_player := func(amount: int) -> int:
		return _apply_player_damage(s,stats,amount,data)
	return skills.cast_monster_skill(s,plan,data,stats,random,hit_player,raw_player)

func _run_enemy_passives(s: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted) -> void:
	var b: Dictionary = s.battle
	var passives: Variant = b.enemy.get("passives",[])
	if passives is Array and not passives.is_empty():
		skills.apply_monster_self_effects(s,passives,data,random,stats)

func _run_enemy_triggers(s: Dictionary, data: Dictionary, stats: Dictionary, random: RefCounted, event: String) -> void:
	var b: Dictionary = s.battle
	for trigger in BeastAI.pending_triggers(b,b.enemy,event):
		BeastAI.mark_trigger(b,trigger)
		var trigger_name := str(trigger.get("name",trigger.get("id","妖兽异动")))
		b.log_entries.append({"type":"system","text":"%s：%s" % [b.enemy.name,trigger_name]})
		b.log.append("%s触发%s。" % [b.enemy.name,trigger_name])
		skills.apply_monster_self_effects(s,trigger.get("effects",[]),data,random,stats)

func damage(attack: float, defense: float, multiplier: float, data: Dictionary, random: RefCounted, can_crit: bool = true, crit_bonus: float = 0.0) -> int:
	var crit: float = data.rules.crit_multiplier if can_crit and random.roll("battle") < clampf(float(data.rules.crit_chance)+crit_bonus,0.0,1.0) else 1.0
	last_critical=crit!=1.0
	return _direct_damage(attack,defense,multiplier*crit,data)

func _direct_damage(attack: float, defense: float, multiplier: float, data: Dictionary) -> int:
	return Math.direct_damage(attack, defense, multiplier, data)

func valid_status(id: String, status: Variant, data: Dictionary) -> bool:
	return Status.valid(id,status,data)

func _enemy_attack(s: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, multiplier: float, ordinary: bool) -> bool:
	return bool(_enemy_hit(s,stats,data,random,multiplier,ordinary,false).get("avoided",false))

func _enemy_hit(s: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, multiplier: float, ordinary: bool, can_crit: bool) -> Dictionary:
	var b: Dictionary = s.battle
	var p: Dictionary = s.player
	var config: Dictionary = data.spell_growth
	var wind: Dictionary = b.status.get("wind_step",{})
	var dodge := minf(float(wind.get("effects",{}).get("dodge",0)) + (Fortunes.modifier(p,"dodge","","个百分点") + stats.get("equipment_effects",{}).get("dodge",0)) / 100.0,float(config.dodge_cap))
	if dodge > 0 and random.roll("battle") < dodge:
		if not wind.is_empty() and wind.get("trigger_round",-1) != b.turn:
			wind.trigger_round = b.turn
			b.enemy.hp -= floori(wind.attack*float(wind.effects.get("dodge_counter",0)))
			if wind.effects.has("dodge_wind"):
				Status.apply(b,"wind_force",config,wind.attack,int(wind.effects.dodge_wind))
		return {"avoided":true,"damage":0,"critical":false}
	var shield_id := Status.shield_id(b)
	var shield: Dictionary = b.status.get(shield_id,{})
	var shield_effects: Dictionary = shield.get("effects",{})
	var stand: Dictionary = b.status.get("stand",{})
	var stand_effects: Dictionary = stand.get("effects",{})
	var reduction := float(shield_effects.get("reduction",0))+float(stand_effects.get("reduction",0))+(0.5 if b.guard else 0.0)
	var defense: float = stats.defense * maxf(0.0, 1.0 + Status.stat_modifier(b,"player","defense",config))
	if p.hp * 100 < stats.hp * 30:
		defense *= 1.0 + Fortunes.modifier(p,"defense_low_hp") / 100.0
	defense += b.status.get("guard",{}).get("amount",0)
	var weakened := float(b.status.get("weak_attack",{}).get("value",0))
	var incoming := 1.0 + Fortunes.modifier(p,"incoming_normal") / 100.0 if ordinary else 1.0
	var critical := false
	var attack_bonus := Status.stat_modifier(b,"enemy","attack",config)
	var attack_value := float(b.enemy.attack) * maxf(0.0, 1.0 + attack_bonus)
	var charged := clampf(float(b.get("enemy_charge",0)),0.0,10.0)
	if charged > 0:
		multiplier *= charged
		b["enemy_charge"] = 0.0
	if can_crit:
		var crit_chance := clampf(float(data.rules.crit_chance) + Status.stat_modifier(b,"enemy","crit",config),0.0,1.0)
		if random.roll("battle") < crit_chance:
			critical = true
			multiplier *= float(data.rules.crit_multiplier)
	var amount := _direct_damage(attack_value,defense,multiplier*incoming*(1.0-weakened)*(1.0-minf(reduction,float(config.reduction_cap))),data)
	Status.consume(b,"weak_attack")
	var dealt := _apply_player_damage(s,stats,amount,data)
	return {"avoided":false,"damage":dealt,"critical":critical}

func _apply_player_damage(s: Dictionary, stats: Dictionary, amount: int, data: Dictionary) -> int:
	var b: Dictionary = s.battle
	var p: Dictionary = s.player
	var config: Dictionary = data.spell_growth
	var shield_id := Status.shield_id(b)
	var shield: Dictionary = b.status.get(shield_id,{})
	var shield_effects: Dictionary = shield.get("effects",{})
	var stand: Dictionary = b.status.get("stand",{})
	var stand_effects: Dictionary = stand.get("effects",{})
	var before := int(p.hp)
	if not shield.is_empty():
		var absorbed := mini(amount,int(shield.amount))
		shield.amount -= absorbed
		amount -= absorbed
		var wet := 1 if b.status.has("wet") else 0
		if shield_effects.has("hit_chill") and shield.get("trigger_round",-1) != b.turn:
			shield.trigger_round = b.turn
			Status.apply(b,"chill",config,shield.attack,int(shield_effects.hit_chill)+wet)
			Skills.gain_mana(p,stats,int(shield_effects.get("chill_mana",0)))
		if shield.amount == 0:
			Status.consume(b,shield_id)
			b.enemy.hp -= floori(shield.attack*float(shield_effects.get("rebound",0)))
			if shield_effects.has("rebound_chill") and b.enemy.hp > 0:
				Status.apply(b,"chill",config,shield.attack,int(shield_effects.rebound_chill)+wet)
		if shield_id == "rock_shield" and stand.get("trigger_round",-1) != b.turn:
			stand.trigger_round = b.turn
			Skills.repair_player_shield(b,floori(stats.attack*float(stand_effects.get("hit_repair",0))))
			b.enemy.hp -= floori(stats.attack*float(stand_effects.get("hit_rebound",0)))
	p.hp -= _incoming_damage(p,stats,amount)
	return before - int(p.hp)

func _incoming_damage(p: Dictionary, stats: Dictionary, amount: int) -> int:
	var percent := Fortunes.modifier(p,"incoming_final") - int(stats.get("equipment_effects",{}).get("final_reduction",0))
	if p.hp * 100 < stats.hp * 30:
		percent += Fortunes.modifier(p,"incoming_low_hp")
	return maxi(0,roundi(amount * (100 + percent) / 100.0))

func _end_action(s: Dictionary, stats: Dictionary, data: Dictionary, player: bool) -> void:
	var b: Dictionary = s.battle
	var config: Dictionary = data.spell_growth
	for id in b.status.keys():
		if Status.is_player(id) != player:
			continue
		var value: Dictionary = b.status[id]
		if value.get("applied_actor","player") == b.acting and value.get("applied_round",-1) == b.turn:
			continue
		match id:
			"burn","poison","bleed":
				var amount := Status.dot(b,id,config) if value.has("layers") else int(data.rules.burn_damage)
				if id == "burn":
					amount = roundi(amount * (1.0 + float(stats.get("equipment_effects",{}).get("burn_damage",0))/100.0))
				b.enemy.hp -= amount
			"player_burn","player_poison","player_bleed":
				var amount := Status.dot(b,id,config)
				if id == "player_poison":
					amount = roundi(amount * (100 + Fortunes.modifier(s.player,"poison_damage")) / 100.0)
				s.player.hp -= _incoming_damage(s.player,stats,amount)
			"life":
				Skills.heal_player(s,stats,floori(value.attack*value.value),b,config)
			"spring":
				Skills.gain_mana(s.player,stats,int(value.effects.periodic_mana))
		Status.tick(b,id)

func _frame(s: Dictionary) -> Dictionary:
	return {"player":{"hp":s.player.hp,"mp":s.player.mp,"statuses":Status.visible(s.battle.status,true),"defending":s.battle.guard},"enemy":{"hp":s.battle.enemy.hp,"mp":s.battle.enemy.mp,"statuses":Status.visible(s.battle.status,false),"defending":bool(s.battle.get("enemy_guard",false))}}

func _append_event_log(s: Dictionary,event: Dictionary,definitions: Dictionary) -> void:
	var names: Dictionary={"player":s.player.name,"enemy":s.battle.enemy.name}
	s.battle.log_entries.append_array(log_records(event,names))
	s.battle.log.append("第%d回合：%s使用%s。" % [event.turn,names[event.actor],event.label])
	for id in event.after:
		var change: int=int(event.after[id].hp)-int(event.before[id].hp)
		if change!=0:s.battle.log.append("%s%s%d；生命 %d → %d。" % [names[id],"恢复" if change>0 else "受到伤害 ",absi(change),maxi(0,event.before[id].hp),maxi(0,event.after[id].hp)])
		for status in event.after[id].statuses:
			if event.before[id].statuses.get(status,{})!=event.after[id].statuses[status]:
				var label: String = "护体" if status == "guard" else definitions.get(status.trim_prefix("player_"),{}).get("name",status)
				s.battle.log.append("%s状态：%s（%d回合）。" % [names[id],label,event.after[id].statuses[status].turns])

# Read-only view of the existing fixed per-round order; shared by execution and UI.
func action_order(stats: Dictionary,battle: Dictionary,config: Dictionary = {}) -> Array:
	var speed := float(stats.speed)
	var enemy_speed := float(battle.enemy.speed)
	if not config.is_empty():
		speed *= 1.0+Status.ratio(battle,"wind_force",config)+float(battle.status.get("wind_step",{}).get("effects",{}).get("speed",0))+Status.stat_modifier(battle,"player","speed",config)
		enemy_speed *= maxf(0,1.0+Status.stat_modifier(battle,"enemy","speed",config)-Status.ratio(battle,"chill",config)-Status.ratio(battle,"root",config)-float(battle.status.get("slow",{}).get("value",0)))
	return ["player","enemy"] if speed>=enemy_speed else ["enemy","player"]

# Compact immutable presentation records derived only from already-settled action snapshots.
static func log_records(event: Dictionary,names: Dictionary) -> Array:
	var records: Array=[{"type":"action","actor":names[event.actor],"kind":event.kind,"label":event.label}]
	for id in event.after:
		var old: Dictionary=event.before[id]
		var current: Dictionary=event.after[id]
		for stat in ["hp","mp"]:
			var amount: int=int(current[stat])-int(old[stat])
			if amount!=0:records.append({"type":stat,"target":names[id],"amount":amount,"before":old[stat],"after":current[stat],"critical":event.get("critical",false) and id!=event.actor and amount<0 and stat=="hp","source_spell":event.label if event.kind=="spell" else ""})
		if not old.get("defending",false) and current.get("defending",false):records.append({"type":"defend","target":names[id]})
		for status in current.statuses:
			var previous: Dictionary=old.statuses.get(status,{})
			if previous==current.statuses[status]:continue
			var change: String="apply" if previous.is_empty() else "refresh" if int(current.statuses[status].turns)>int(previous.turns) else "tick"
			records.append({"type":"status","target":names[id],"id":status,"turns":current.statuses[status].turns,"change":change})
		for status in old.statuses:
			if not current.statuses.has(status):records.append({"type":"status","target":names[id],"id":status,"turns":0,"change":"expire"})
	return records

static func valid_log_entries(value: Variant) -> bool:
	if not value is Array:return false
	var strings: Dictionary={"round":[],"action":["actor","kind","label"],"hp":["target"],"mp":["target"],"status":["target","id","change"],"defend":["target"],"avoidance":["target","outcome"],"result":["result"],"system":["text"],"legacy":["text"]}
	for entry in value:
		if not entry is Dictionary or not entry.get("type") is String or not strings.has(entry.type):return false
		for key in strings[entry.type]:
			if not entry.get(key) is String:return false
		var numeric: Array=["amount","before","after"] if entry.type in ["hp","mp"] else ["turn"] if entry.type=="round" else ["turns"] if entry.type=="status" else []
		for key in numeric:
			if not (entry.get(key) is int or entry.get(key) is float):return false
			if not is_finite(float(entry[key])) or floorf(float(entry[key]))!=float(entry[key]):return false
		if entry.type in ["hp","mp"]:
			if entry.amount!=entry.after-entry.before or not entry.get("critical",false) is bool or not entry.get("source_spell","") is String:return false
		if entry.type=="round" and entry.turn<1:return false
		if entry.type=="status" and (entry.turns<0 or entry.change not in ["apply","refresh","tick","expire"]):return false
		if entry.type=="action" and entry.kind not in ["attack","defend","spell","item","escape","special"]:return false
		if entry.type=="avoidance" and entry.outcome not in ["dodge","block"]:return false
		if entry.type=="result" and entry.result not in ["win","lose","escape","enemy_escape"]:return false
	return true
