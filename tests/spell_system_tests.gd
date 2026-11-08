extends SceneTree

const Battle = preload("res://gameplay/battle/battle_system.gd")
const Status = preload("res://gameplay/battle/battle_status.gd")
const Effects = preload("res://gameplay/battle/spell_effect_resolver.gd")
const Progress = preload("res://gameplay/battle/spell_progression.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var gm: Node = root.get_node("GameManager")
	check(gm.boot_ok,"configuration boot")
	if not gm.boot_ok:
		quit(1)
		return
	var op: RefCounted = gm.operations
	var data: Dictionary = op.data
	var config: Dictionary = data.spell_growth
	var table: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "spell_trials"
	check(gm.new_game("法术试验", "金").is_empty(),"new game")
	var fresh: Dictionary = op.export_save()
	check(fresh.state.player.spell_slots == ["skill_spirit_bolt"],"existing starting equipment")
	check(fresh.state.player.spells.size() == 33,"learn all 32 plus spirit bolt")
	for id in data[table]:
		check(fresh.state.player.spells[id] == 1,id+" starts at level one")
		for level in range(1,6):
			var fixture: Dictionary = fresh.duplicate(true)
			var s: Dictionary = fixture.state
			s.player.spells[id] = level
			s.player.spell_slots = [id]
			s.player.hp = 65
			s.player.mp = 25
			check(op.battle.start(s,"monster_gray_wolf",data,"test-battle").is_empty(),"test setup")
			s.battle.enemy.hp = 800
			s.battle.enemy.attack = 16
			for status in ["wet","poison","burn","sword_mark","thunder_mark","chill","shock","electrified"]:
				Status.apply(s.battle,status,config,25,3)
			Status.apply(s.battle,"enemy_shield",config,25,1,{"amount":3,"maximum":3})
			Status.create_shield(s.battle,"rock_shield",config,{"attack":28,"hp":120},{"shield":.8})
			Status.apply(s.battle,"wind_force",config,25,3)
			Status.apply(s.battle,"sword_intent",config,25,3)
			Status.apply(s.battle,"flame_force",config,25,3)
			check(op.restore_save(fixture).is_empty(),id+" restore fixture")
			var expected_cost: int = data.spells[id].mp
			var cast: Dictionary = op.request("battle_action",{"kind":"spell","id":id})
			check(cast.success,id+" cast level "+str(level))
			var live: Dictionary = op.snapshot()
			check(live.battle.turn == 1 and live.battle.cooldowns.get(id,-1) == data.spells[id].cd,id+" turn and cooldown")
			check(live.player.get("spell_mastery",{}).get(id,-1) == (0 if level == 5 else 1),id+" cast mastery")
			check(live.player.mp >= 25-expected_cost and live.player.mp <= op.stats().mp,id+" resource bounds")
			if data.spells[id].target in ["enemy","all","chain"]:
				check(live.battle.enemy.hp < 800,id+" attack applied")
			var saved: Dictionary = op.export_save()
			check(op.restore_save(saved).is_empty() and op.snapshot() == saved.state,id+" active battle round-trip")
			check(op.request("battle_action",{"kind":"defend"}).success,id+" subsequent action")
	var old: Dictionary = fresh.duplicate(true)
	old.state.player.spells = {"skill_spirit_bolt":2}
	old.state.player.spirit_stones = 60
	check(op.restore_save(old).is_empty() and op.snapshot().player.spells.size() == 33 and op.snapshot().player.spells.skill_spirit_bolt == 2,"legacy save gets trial spells while retaining progress")
	var id := "skill_metal_edge"
	check(op.spell_training(id,"quiet",10).gain == 80,"configured quiet preview")
	var before: Dictionary = op.snapshot()
	var result: Dictionary = op.request("spell_train",{"id":id,"method":"quiet","days":10},"test-training")
	var after: Dictionary = op.snapshot()
	check(result.success and after.hours-before.hours == 240 and after.player.spell_mastery[id] == 80 and before.player.cultivation == after.player.cultivation,"time and mastery settle together")
	check(not op.request("spell_train",{"id":id,"method":"quiet","days":10},"test-training").success and op.snapshot() == after,"training request is idempotent")
	check(op.request("spell_train",{"id":id,"method":"stones","days":10}).success and op.snapshot().player.spells[id] == 3,"multi-level overflow")
	check(not op.request("spell_train",{"id":id,"method":"stones","days":10}).success,"insufficient funds rejects")
	check(op.restore_save(fresh).is_empty(),"reset test fixture")
	var trained: Dictionary = op.export_save()
	trained.state.player.spells[id] = 5
	check(op.restore_save(trained).is_empty(),"max level loads")
	check(op.request("spell_affix_roll",{"id":id,"slot":1}).success,"second affix slot works")
	var pending: Dictionary = op.snapshot().player.spell_affix_pending
	check(not op.request("spell_affix_roll",{"id":id,"slot":1}).success,"duplicate roll rejected")
	check(op.restore_save(op.export_save()).is_empty(),"pending affix round-trip")
	check(op.request("spell_affix_resolve",{"token":pending.token,"option":pending.candidates[0]}).success,"confirm affix")
	check(op.snapshot().player.spell_affixes[id]["1"] == pending.candidates[0],"confirmed effect saved")
	check(not op.request("spell_affix_resolve",{"token":pending.token,"option":pending.candidates[0]}).success,"duplicate confirm rejected")
	check(op.battle.damage(30,20,1.0,data,op.random,false) == 15,"approved defense formula")
	_check_effects(op,fresh)
	print("%s: %d checks, %d failures" % [table,checks,failures])
	quit(1 if failures else 0)

func cast_fixture(op: RefCounted, fresh: Dictionary, id: String, level: int, setup: Callable) -> Dictionary:
	var fixture: Dictionary = fresh.duplicate(true)
	var s: Dictionary = fixture.state
	s.player.spells[id] = level
	s.player.spell_slots = [id]
	s.player.mp = 30
	op.battle.start(s,"monster_gray_wolf",op.data,"specific-effect")
	s.battle.enemy.hp = 500
	s.battle.enemy.speed = 0
	setup.call(s)
	check(op.restore_save(fixture).is_empty(),"specific effect fixture restores: "+id)
	check(op.request("battle_action",{"kind":"spell","id":id}).success,"specific spell casts: "+id)
	return op.snapshot()

func _check_effects(op: RefCounted, fresh: Dictionary) -> void:
	var rules: Dictionary = op.data.rules
	var config: Dictionary = op.data.spell_growth
	rules.crit_chance = 0.0
	var base_setup := func(_s: Dictionary): pass
	var atk: float = op.stats().attack
	var wind := cast_fixture(op,fresh,"skill_wind_blade",1,base_setup)
	check(wind.battle.enemy.hp == 500-2*floori(atk*.55*100/(100+5*4)),"wind applies defense to each of two hits")
	var poison := cast_fixture(op,fresh,"skill_wood_vine",1,base_setup)
	check(poison.battle.status.poison.layers == 1 and poison.battle.status.poison.turns == 1,"poison acts once on enemy turn")
	check(poison.battle.enemy.hp == 500-floori(atk*.85*100/(100+5*4))-floori(atk*.05),"poison uses attack snapshot")
	check(op.request("battle_action",{"kind":"defend"}).success and not op.snapshot().battle.status.has("poison"),"poison expires after second action")
	var arc := cast_fixture(op,fresh,"skill_thunder_chain",3,func(s: Dictionary): Status.apply(s.battle,"wet",config,atk))
	check(arc.battle.enemy.hp == 500-floori(atk*1.1*100/(100+5*4)) and arc.battle.status.has("electrified"),"wet boosts lightning and unlocks electrified")
	var ice := cast_fixture(op,fresh,"skill_ice_cone",1,func(s: Dictionary): Status.apply(s.battle,"wet",config,atk))
	check(ice.battle.status.chill.layers == 2,"wet increases chill layers")
	var detonated := cast_fixture(op,fresh,"skill_thunder_five",4,func(s: Dictionary): Status.apply(s.battle,"thunder_mark",config,atk,3))
	check(not detonated.battle.status.has("thunder_mark") and detonated.battle.enemy.hp == 500-floori(atk*1.75*100/(100+5*4))-floori(atk*.75),"lightning detonation consumes mark and adds special damage")
	var fox := cast_fixture(op,fresh,"skill_ice_seal",5,func(s: Dictionary):
		s.battle.monster = "monster_green_fox"
		s.battle.turn = 1
		s.battle.enemy.special_every = 2
		s.battle.enemy.mp = 20
		Status.apply(s.battle,"chill",config,atk,2))
	check(fox.battle.enemy.mp == 20 and fox.battle.status.has("control_resistance") and not fox.battle.status.has("chill"),"sealing prevents special cast and consumes chill")
	var shield := cast_fixture(op,fresh,"skill_earth_rock_armor",1,base_setup)
	check(shield.player.hp == fresh.state.player.hp and shield.battle.status.rock_shield.amount < shield.battle.status.rock_shield.maximum,"rock shield absorbs direct damage")
	var cleared := cast_fixture(op,fresh,"skill_wood_spring_heal",5,func(s: Dictionary):
		s.player.hp = 10
		Status.apply(s.battle,"player_poison",config,atk))
	check(not cleared.battle.status.has("player_poison") and cleared.battle.status.has("life"),"low-life healing cleanses and adds regeneration")
	var prepared := cast_fixture(op,fresh,"skill_water_return_to_sea",5,func(s: Dictionary):
		s.player.mp = 15
		Status.apply(s.battle,"discount",config,atk,1,{"value":3}))
	check(prepared.player.mp == 27 and prepared.battle.status.discount.value == 3,"zero-cost return does not use its own reduction")
	var baseline := cast_fixture(op,fresh,"skill_spirit_bolt",3,base_setup)
	var pierced := cast_fixture(op,fresh,"skill_spirit_bolt",3,func(s: Dictionary): s.player.spell_affixes={"skill_spirit_bolt":{"0":"pierce"}})
	check(pierced.battle.enemy.hp == 500-floori(atk*1.3*100/(100+5*3.6)) and pierced.battle.enemy.hp <= baseline.battle.enemy.hp,"pierce uses reduced effective defense")
	var mana := cast_fixture(op,fresh,"skill_spirit_bolt",3,func(s: Dictionary): s.player.spell_affixes={"skill_spirit_bolt":{"0":"mana"}})
	check(mana.player.mp == baseline.player.mp+1,"mana affix restores on life damage")
	var burning := cast_fixture(op,fresh,"skill_spirit_bolt",3,func(s: Dictionary): s.player.spell_affixes={"skill_spirit_bolt":{"0":"burn"}})
	check(burning.battle.status.burn.layers == 1,"burn affix applies a true status")
	var focus := cast_fixture(op,fresh,"skill_spirit_bolt",3,func(s: Dictionary): s.player.spell_affixes={"skill_spirit_bolt":{"0":"focus"}})
	check(focus.battle.status.has("focus") and op.request("battle_action",{"kind":"spell","id":"skill_spirit_bolt"}).success,"focus is available for next cast")
	check(op.snapshot().battle.enemy.hp == focus.battle.enemy.hp-floori(atk*1.3*1.1*100/(100+5*4)),"focus amplifies the next attack")
	var save := preload("res://core/save_service.gd").new()
	var path := save.write(op.export_save(),"user://spell_test_saves")
	check(not path.is_empty() and op.restore_save(save.read(path)).is_empty(),"isolated disk save round-trip")
	if not path.is_empty():
		DirAccess.remove_absolute(path)
