extends SceneTree
const Ops = preload("res://core/operation_service.gd")
var data: Dictionary
var base: Dictionary
var count := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	count += 1
	if not ok: failures += 1; push_error(title)
	print("%s %s" % ["PASS" if ok else "FAIL",title])
func make_op(seed_value: int=1) -> RefCounted:
	var op := Ops.new(); op.configure(data); op.new_game("战斗测试","火",base,seed_value)
	return op
func fixture(op: RefCounted, monster: String) -> void:
	var payload: Dictionary = op.export_save()
	payload.state.player.spells={"skill_spirit_bolt":1,"skill_fire_bolt":1,"skill_earth_guard":1,"skill_water_arrow":1,"skill_wood_heal":1}
	payload.state.player.spell_slots=["skill_fire_bolt","skill_water_arrow","skill_earth_guard"]
	payload.state.player.inventory.item_healing_powder=10
	payload.state.player.inventory.item_aura_powder=10
	payload.state.player.location="area_qinglan_outskirts"
	op.battle.start(payload.state,monster,data,"fixture_battle")
	check(op.restore_save(payload).is_empty(),"battle fixture validates")
func run() -> void:
	data=root.get_node("GameManager").catalog.tables; base=root.get_node("GameManager").repository.starting_character()
	var op := make_op(); fixture(op,"monster_gray_wolf")
	var before: Dictionary = op.snapshot()
	check(not op.request("battle_action",{"kind":"item","id":"item_healing_powder"}).success and op.snapshot()==before,"full HP item rejects without consuming turn")
	check(op.request("battle_action",{"kind":"defend"}).success,"defend action")
	check(op.snapshot().player.hp == 115,"defend halves floor damage")
	check(op.request("battle_action",{"kind":"item","id":"item_healing_powder"}).success,"battle healing item action")
	check(op.request("battle_action",{"kind":"spell","id":"skill_earth_guard"}).success,"guard spell action")
	check(op.snapshot().battle.status.guard.turns == 2,"guard persists for two enemy turns")
	check(op.request("battle_action",{"kind":"spell","id":"skill_fire_bolt"}).success,"fire spell action")
	before=op.snapshot()
	check(not op.request("battle_action",{"kind":"spell","id":"skill_fire_bolt"}).success and op.snapshot()==before,"cooldown rejects without advancing")
	# Force defeat from valid isolated state, without changing production content.
	op=make_op(); fixture(op,"monster_wolf_leader")
	var payload: Dictionary = op.export_save(); payload.state.player.hp=1
	check(op.restore_save(payload).is_empty(),"low HP fixture")
	check(op.request("battle_action",{"kind":"attack"}).success,"defeat resolution action")
	check(op.snapshot().battle.is_empty() and op.snapshot().player.location=="town_qinglan" and op.snapshot().player.hp==36 and op.snapshot().player.spirit_stones==108,"T015 defeat recovery and loss exact")
	var escaped := false
	for seed_value in range(1,10):
		op=make_op(seed_value); fixture(op,"monster_gray_wolf")
		check(op.request("battle_action",{"kind":"escape"}).success,"escape action valid")
		if op.snapshot().battle.is_empty():
			check(op.snapshot().player.spirit_stones==120 and not op.snapshot().player.inventory.has("material_wolf_fang"),"escape no rewards")
			escaped=true; break
	check(escaped,"escape deterministic samples include success")
	# 100 complete exploration outcomes repeat, including battles and drops.
	var sequences := []
	for repeat in range(2):
		op=make_op(99)
		var sequence := []
		for iteration in range(100):
			var reset: Dictionary = op.export_save()
			reset.state.player.hp=120; reset.state.player.mp=40
			reset.state.player.location="area_qinglan_outskirts"
			op.restore_save(reset)
			op.request("explore")
			var monster: String = op.snapshot().battle.get("monster","")
			for turn in range(50):
				if op.snapshot().battle.is_empty(): break
				op.request("battle_action",{"kind":"attack"})
			sequence.append([monster,op.snapshot().player.spirit_stones,op.snapshot().player.inventory,op.snapshot().hours])
		sequences.append(sequence)
	check(sequences[0]==sequences[1],"T017 100 actual exploration/battle/loot outcomes deterministic")
	# Corrupt save rejected without replacing live state.
	op=make_op()
	for key in ["plots","stocks","npcs","quests","warehouse","prices","battle"]:
		var invalid: Dictionary = op.export_save(); invalid.state[key]=null
		before=op.snapshot()
		check(not op.restore_save(invalid).is_empty() and before==op.snapshot(),"malformed save isolated: "+key)
	var expired: Dictionary = op.export_save()
	expired.state.player.age = expired.state.player.lifespan
	check(op.restore_save(expired).is_empty(),"expired player record can load")
	before = op.snapshot()
	check(not op.request("practice",{"days":1}).success and before == op.snapshot(),"lifespan end rejects gameplay without changing state")
	print("BOUNDARIES: %s checks, %s failures" % [count,failures])
	quit(0 if failures==0 else 1)
