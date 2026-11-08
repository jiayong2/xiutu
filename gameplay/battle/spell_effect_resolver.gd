extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")
const Status = preload("res://gameplay/battle/battle_status.gd")
const Spells = preload("res://gameplay/battle/spell_progression.gd")

static func mana_cost(spell: Dictionary, b: Dictionary, actor: Dictionary = {}) -> int:
	var cost := int(spell.mp)
	if cost == 0:
		return 0
	var statuses: Dictionary = b.get("status",{})
	var discount := int(statuses.get("spring",{}).get("effects",{}).get("spring_discount",0))
	discount += int(statuses.get("discount",{}).get("value",0))
	if spell.element == "风" and _is_attack(spell):
		discount += int(statuses.get("wind_ready",{}).get("effects",{}).get("wind_discount",0))
	var adjusted := roundi(maxi(1,cost-discount) * (100 + Fortunes.modifier(actor,"spell_cost")) / 100.0)
	# The current battle contract permits one player command per round.
	return maxi(1,adjusted + Fortunes.modifier(actor,"first_spell_cost","","fixed"))

static func _is_attack(spell: Dictionary) -> bool:
	return spell.get("target","") in ["enemy","all","chain"] or (not spell.has("levels") and spell.multiplier > 0)

func cast(s: Dictionary, spell: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, roll: Callable) -> bool:
	var b: Dictionary = s.battle
	var p: Dictionary = s.player
	var config: Dictionary = data.spell_growth
	var level := int(p.spells[spell.id])
	var e := Spells.effects(spell,level) if spell.has("levels") else {}
	var wind: Dictionary = b.status.get("wind_ready",{}).get("effects",{})
	var affixes: Array = p.get("spell_affixes",{}).get(spell.id,{}).values()
	var cost := mana_cost(spell,b,p)
	p.mp -= cost
	if spell.mp > 0:
		Status.consume(b,"discount")
	if spell.element == "风" and _is_attack(spell):
		Status.consume(b,"wind_ready")
	b.cooldowns[spell.id] = spell.cd
	if spell.has("levels"):
		if e.has("power"):
			var critical := _attack(s,spell,e,stats,data,random,roll,affixes,wind)
			return critical
		_support(s,e,stats,config,spell.element)
		return false
	if spell.heal > 0:
		var recovery := 1.0 + Fortunes.modifier(p,"wood_heal",spell.element) / 100.0
		heal(p,stats,floori((spell.heal+(level-1)*10)*recovery),b,config)
	elif spell.guard > 0:
		b.status.guard = {"turns":int(data.rules.status_turns)+1,"amount":spell.guard+(level-1)*2}
	else:
		var critical := _attack(s,spell,{"power":spell.multiplier+(level-1)*.1},stats,data,random,roll,affixes,wind)
		if b.enemy.hp > 0 and not spell.status.is_empty() and random.roll("battle") < data.rules.status_chance:
			if b.status.get(spell.status,{}).has("layers"):
				Status.apply(b,spell.status,config,stats.attack)
			else:
				b.status[spell.status] = {"turns":int(data.rules.status_turns)}
		return critical
	return false

func basic_attack(s: Dictionary, stats: Dictionary, data: Dictionary, roll: Callable) -> void:
	var b: Dictionary = s.battle
	var config: Dictionary = data.spell_growth
	var defense := float(b.enemy.defense)*(1.0-clampf(Status.ratio(b,"armor_break",config)+float(stats.get("equipment_effects",{}).get("defense_ignore",0))/100.0,0.0,1.0))
	var fortune_scale := 1.0 + (Fortunes.modifier(s.player,"damage") + Fortunes.modifier(s.player,"normal_damage") + Fortunes.modifier(s.player,"beast_damage",b.monster)) / 100.0
	var amount: int = roll.call(stats.attack,defense,(1.0+Status.ratio(b,"vulnerability",config))*fortune_scale,data)
	_hit(b,amount,float(stats.get("equipment_effects",{}).get("shield_damage",0))/100.0)
	_electrify(b,config)

func _attack(s: Dictionary, spell: Dictionary, e: Dictionary, stats: Dictionary, data: Dictionary, random: RefCounted, roll: Callable, affixes: Array, wind: Dictionary) -> bool:
	var b: Dictionary = s.battle
	var p: Dictionary = s.player
	var config: Dictionary = data.spell_growth
	var attack := float(stats.attack)
	var before: Dictionary = b.status.duplicate(true)
	var start_hp := int(b.enemy.hp)
	var poison := Status.layers(b,"poison")
	var burn := Status.layers(b,"burn")
	var wet := Status.layers(b,"wet") > 0
	var mark := Status.layers(b,"sword_mark")
	var thunder_mark := Status.layers(b,"thunder_mark")
	var chill := Status.layers(b,"chill")
	var shield := not Status.shield_id(b).is_empty()
	var consumed := Status.consume(b,e.consume_enemy) if e.has("consume_enemy") else 0
	var self_used := Status.consume(b,e.consume_self) if e.has("consume_self") else 0
	var bonus := 0.0
	var equipment: Dictionary = stats.get("equipment_effects",{})
	var pierce := float(e.get("pierce",0)) + float(equipment.get("defense_ignore",0))/100.0
	var crit := float(wind.get("wind_crit",0)) if spell.element == "风" else 0.0
	crit += float(equipment.get("critical",0))/100.0
	var crit_damage := 0.0
	if spell.element == "金":
		bonus += Status.ratio(b,"sword_mark",config)+Status.ratio(b,"sword_intent",config)
		if e.get("consume_enemy","") == "sword_mark":
			bonus += consumed*float(config.statuses.sword_mark.value)
		if not e.has("consume_self"):
			Status.consume(b,"sword_intent")
		if before.has("armor_break"):
			bonus += float(e.get("armor_bonus",0))
		if mark > 0:
			pierce += float(e.get("mark_pierce",0))
	if spell.element == "火":
		if not e.has("consume_self"):
			bonus += Status.ratio(b,"flame_force",config)
			Status.consume(b,"flame_force")
	if spell.element == "雷":
		if wet:
			bonus += float(config.statuses.wet.value)
		if thunder_mark > 0:
			crit += float(e.get("mark_crit",0))
		crit += Status.ratio(b,"thunder_force",config)
		Status.consume(b,"thunder_force")
	if spell.element == "冰":
		bonus += chill*float(e.get("chill_bonus",0))
		bonus += Status.ratio(b,"ice_vulnerability",config)
		Status.consume(b,"ice_vulnerability")
	if shield:
		bonus += float(e.get("shield_damage_bonus",0))
	bonus += float(b.status.get("focus",{}).get("value",Status.ratio(b,"focus",config)))+Status.ratio(b,"vulnerability",config)
	Status.consume(b,"focus")
	bonus += self_used*float(e.get("self_bonus",0))+Status.layers(b,"wind_force")*float(e.get("wind_bonus",0))
	if e.has("consume_crit") and consumed >= e.consume_crit:
		crit += float(e.crit_bonus)
	if e.has("self_crit_threshold") and self_used >= e.self_crit_threshold:
		crit += float(e.self_crit)
	if e.has("consume_crit_damage") and consumed >= e.consume_crit_damage:
		crit_damage = float(e.crit_damage)
	if e.has("consume_pierce_threshold") and consumed >= e.consume_pierce_threshold:
		pierce += float(e.consume_pierce)
	if "pierce" in affixes:
		pierce += float(config.affixes.pierce.value)
	var defense := float(b.enemy.defense)*(1.0-Status.ratio(b,"armor_break",config))*(1.0-clampf(pierce,0,1))
	var scale := (1.1 if p.root == spell.element else 1.0)*(1.0+float(stats.spell_bps)/10000.0)
	if spell.element == "火":
		scale *= 1.0+float(stats.fire)
	scale *= 1.0+bonus
	scale *= 1.0 + (Fortunes.modifier(p,"damage") + Fortunes.modifier(p,"spell_damage",spell.element) + Fortunes.modifier(p,"beast_damage",b.monster)) / 100.0
	if spell.element in ["金","木","水","火","土"]:
		scale *= 1.0 + float(equipment.get("five_element_damage",0))/100.0
	var hits: Array[float] = []
	for index in range(int(e.get("hits",1))):
		hits.append(float(e.power))
	var added: bool = e.has("extra_hit") and random.roll("battle") < e.extra_hit
	if added:
		hits.append(float(e.power))
	if e.has("wind_consume") and Status.layers(b,"wind_force") >= e.wind_consume:
		Status.consume(b,"wind_force",int(e.wind_consume))
		hits.append(float(e.wind_hit))
	if e.has("execute") and start_hp < int(data.monsters[b.monster].hp)*e.execute:
		hits.append(float(e.execute_hit))
	var critical := false
	var shield_broken := false
	var landed := 0
	var direct_loss := 0
	for power in hits:
		if b.enemy.hp <= 0:
			break
		var crit_scale := 1.0
		if random.roll("battle") < clampf(float(data.rules.crit_chance)+crit,0,1):
			crit_scale = float(data.rules.crit_multiplier)+crit_damage
			critical = true
		var amount: int = roll.call(attack,defense,power*scale*crit_scale,data)
		var previous_hp := int(b.enemy.hp)
		if b.status.has("enemy_shield"):
			amount += floori(amount*float(e.get("shield_break_bonus",0)))
			shield_broken = _hit(b,amount,float(equipment.get("shield_damage",0))/100.0) or shield_broken
		else:
			_hit(b,amount)
		direct_loss += previous_hp-maxi(0,int(b.enemy.hp))
		landed += 1
		_electrify(b,config)
	var extra := Fortunes.modifier(p,"lightning_first_hit",spell.element)
	if landed > 0 and extra > 0 and Fortunes.use_battle_trigger(b,"lightning_first_hit",true) and b.enemy.hp > 0:
		_hit(b,floori(attack * extra / 100.0))
	var special := consumed*float(e.get("detonate",0))
	if wet:
		special += float(e.get("wet_bonus",0))
	if poison > 0:
		special += float(e.get("poison_bonus",0))
	if burn > 0:
		special += float(e.get("burn_bonus",0))
	if before.has("electrified"):
		special += float(e.get("electrified_bonus",0))
	if spell.element == "土" and Status.consume(b,"shock") > 0:
		special += float(config.statuses.shock.value)
	var detonation_start := int(b.enemy.hp)
	if special > 0 and b.enemy.hp > 0:
		b.enemy.hp -= floori(attack*special)
	var special_loss := maxi(0,detonation_start)-maxi(0,int(b.enemy.hp))
	if poison >= int(e.get("poison_echo",999)) and b.enemy.hp > 0:
		b.enemy.hp -= Status.dot(b,"poison",config)
	if landed > 0 and b.enemy.hp > 0:
		_enemy_effects(b,e,config,attack,random,poison,burn,wet,chill,consumed,critical,shield_broken)
	if e.has("self_status"):
		Status.apply(b,e.self_status,config,attack)
	if e.has("hit_intent") and landed > 0:
		Status.apply(b,"sword_intent",config,attack)
	if burn > 0 and e.has("burn_intent"):
		Status.apply(b,"flame_force",config,attack,int(e.burn_intent))
	if e.has("consume_self_status") and consumed >= e.consume_self_threshold:
		Status.apply(b,e.consume_self_status,config,attack,int(e.consume_self_layers))
	if added and landed >= hits.size() and e.has("extra_hit_status"):
		Status.apply(b,e.extra_hit_status,config,attack)
	if before.has("shock") and shield:
		repair(b,floori(attack*float(e.get("shock_repair",0))))
	if shield_broken and e.has("shield_break_gain"):
		var shield_effect := {"shield":e.shield_break_gain}
		Status.create_shield(b,"rock_shield",config,stats,shield_effect)
	var leech := float(e.get("poison_leech",e.get("leech",0))) if poison > 0 else float(e.get("leech",0))
	heal(p,stats,floori(direct_loss*leech),b,config)
	if e.has("consume_leech") and consumed >= e.consume_leech:
		heal(p,stats,mini(floori(special_loss*e.leech_special),floori(stats.hp*e.leech_special)),b,config)
	var mana := int(e.get("wet_mana",0)) if wet else 0
	if poison >= 3:
		mana += int(e.get("poison_mana",0))
	if b.enemy.hp <= 0:
		mana += int(e.get("kill_mana",0))
	if spell.element == "风" and landed >= 2:
		mana += int(wind.get("wind_mana",0))
	if direct_loss > 0:
		mana += affixes.count("mana")*int(config.affixes.mana.value)
	gain_mana(p,stats,mana)
	if landed > 0 and b.enemy.hp > 0:
		if "burn" in affixes:
			Status.apply(b,"burn",config,attack,affixes.count("burn")*int(config.affixes.burn.value))
		_thunder_echo(s,stats,config,random,before.has("electrified"))
	if "focus" in affixes:
		Status.apply(b,"focus",config,attack,1,{"value":config.affixes.focus.value})
	return critical

func _enemy_effects(b: Dictionary, e: Dictionary, config: Dictionary, attack: float, random: RefCounted, poison: int, burn: int, wet: bool, chill: int, consumed: int, critical: bool, shield_broken: bool) -> void:
	if e.has("status"):
		var layers := int(e.get("layers",1))
		match e.status:
			"poison":
				if poison > 0:
					layers += int(e.get("extra_poison",0))
			"burn":
				if burn >= int(e.get("extra_burn",999)):
					layers += 1
			"chill":
				if wet:
					layers += 1+int(e.get("wet_chill",0))
			"thunder_mark":
				if critical:
					layers += int(e.get("crit_mark",0))
		Status.apply(b,e.status,config,attack,layers)
	if e.has("secondary_status"):
		Status.apply(b,e.secondary_status,config,attack)
	if e.has("consume_status") and consumed >= int(e.get("consume_threshold",1)):
		Status.apply(b,e.consume_status,config,attack)
	if shield_broken and e.has("shield_break_status"):
		Status.apply(b,e.shield_break_status,config,attack)
	if wet:
		if e.has("wet_weaken"):
			Status.apply(b,"weak_attack",config,attack,1,{"value":e.wet_weaken})
		if e.has("wet_status"):
			Status.apply(b,e.wet_status,config,attack)
	if e.has("slow"):
		Status.apply(b,"slow",config,attack,1,{"value":e.slow})
		if chill >= int(e.seal):
			Status.consume(b,"chill",int(e.seal))
			var rule: Dictionary = config.control
			var rank: String = rule.monster_ranks.get(b.monster,"normal")
			var resistance: float = b.status.get("control_resistance",{}).get("value",0)
			if random.roll("battle") < maxf(0,float(rule[rank])-resistance):
				Status.apply(b,"seal",config,attack)
				Status.apply(b,"control_resistance",config,attack,1,{"value":minf(1.0,resistance+float(rule.resistance_gain))})
				if e.has("seal_weaken"):
					Status.apply(b,"weak_attack",config,attack,1,{"value":e.seal_weaken})

func _support(s: Dictionary, e: Dictionary, stats: Dictionary, config: Dictionary, element: String) -> void:
	var b: Dictionary = s.battle
	var p: Dictionary = s.player
	if e.has("heal"):
		var low: bool = p.hp < stats.hp*.3
		var recovery := 1.0 + Fortunes.modifier(p,"wood_heal",element) / 100.0
		heal(p,stats,floori(stats.attack*e.heal*recovery*(1.0+float(e.get("low_heal",0)) if low else 1.0)),b,config)
		if e.has("periodic_heal"):
			Status.apply(b,"life",config,stats.attack,1,{"value":e.periodic_heal})
		if low and e.has("cleanse"):
			for id in ["player_poison","player_burn"]:
				if Status.consume(b,id) > 0:
					break
	if e.has("shield"):
		Status.create_shield(b,e.get("shield_status","rock_shield"),config,stats,e)
	if e.has("self_status"):
		Status.apply(b,e.self_status,config,stats.attack,int(e.get("self_layers",1)),{"effects":e})
	if e.has("wind_discount"):
		Status.apply(b,"wind_ready",config,stats.attack,1,{"effects":e})
	if e.has("thunder_echo"):
		Status.apply(b,"thunder_echo",config,stats.attack,1,{"effects":e})
	if e.has("next_discount"):
		Status.apply(b,"discount",config,stats.attack,1,{"value":e.next_discount})
	gain_mana(p,stats,int(e.get("mana",0)))

func _thunder_echo(s: Dictionary, stats: Dictionary, config: Dictionary, random: RefCounted, electrified: bool) -> void:
	var b: Dictionary = s.battle
	var echo: Dictionary = b.status.get("thunder_echo",{})
	if echo.is_empty():
		return
	b.enemy.hp -= floori(echo.attack*echo.effects.thunder_echo)
	if b.enemy.hp > 0 and echo.effects.has("echo_mark") and random.roll("battle") < echo.effects.echo_mark:
		Status.apply(b,"thunder_mark",config,echo.attack)
	if electrified:
		gain_mana(s.player,stats,int(echo.effects.get("echo_mana",0)))

func _electrify(b: Dictionary, config: Dictionary) -> void:
	var status: Dictionary = b.status.get("electrified",{})
	if status.is_empty() or b.enemy.hp <= 0:
		return
	if status.get("trigger_round",-1) != b.turn:
		status.trigger_round = b.turn
		status.triggers = 0
	if int(status.triggers) < 2:
		status.triggers += 1
		b.enemy.hp -= floori(status.attack*config.statuses.electrified.value)

func _hit(b: Dictionary, amount: int, shield_bonus: float = 0.0) -> bool:
	if not b.status.has("enemy_shield"):
		b.enemy.hp -= amount
		return false
	var shield: Dictionary = b.status.enemy_shield
	var absorbed := mini(roundi(amount*(1.0+shield_bonus)),int(shield.amount))
	shield.amount -= absorbed
	b.enemy.hp -= maxi(0,amount-ceili(absorbed/(1.0+shield_bonus)))
	if shield.amount == 0:
		Status.consume(b,"enemy_shield")
		return true
	return false

static func repair(b: Dictionary, amount: int) -> void:
	var id := Status.shield_id(b)
	if not id.is_empty() and amount > 0:
		var shield: Dictionary = b.status[id]
		shield.amount = mini(int(shield.maximum),int(shield.amount)+amount)

static func gain_mana(p: Dictionary, stats: Dictionary, amount: int) -> void:
	p.mp = mini(int(stats.mp),int(p.mp)+amount)

static func heal(p: Dictionary, stats: Dictionary, amount: int, b: Dictionary, config: Dictionary) -> void:
	p.hp = mini(int(stats.hp),int(p.hp)+floori(amount*(1.0-Status.ratio(b,"player_corrosion",config))*(1.0+float(stats.get("equipment_effects",{}).get("healing_received",0))/100.0)))
