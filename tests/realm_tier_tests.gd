extends SceneTree

const Cultivation := preload("res://gameplay/cultivation/cultivation_system.gd")
const RandomService := preload("res://core/random_service.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.new_game("九阶验收","金")
	var ops: RefCounted = gm.operations
	var data: Dictionary = ops.data
	var cultivation: RefCounted = ops.cultivation
	var clean: Dictionary = ops.export_save()
	var old: Dictionary = clean.duplicate(true)
	old.state.player.realm = 10
	old.state.player.lifespan = 150
	old.state.player.erase("growth")
	old.state.erase("spirit")
	old.state.player.erase("traits")
	old.state.player.erase("blood")
	check(ops.restore_save(old).is_empty(),"old Foundation save migrates")
	var migrated: Dictionary = ops.snapshot().player
	check(Cultivation.realm_name(migrated.realm,"qi",data)=="筑基一层" and not migrated.growth.has("breakthrough_quality"),
		"old Foundation starts at its original level and does not receive retrospective quality")
	check(migrated.traits.root_quality=="ordinary" and migrated.traits.aptitudes.spirituality==20 and migrated.blood==80,
		"old character fields receive deterministic defaults")
	var developed: Dictionary = clean.duplicate(true)
	developed.state.player.growth.attributes = {"qi_sea":25,"meridians":23,"bones":24,"physique":25}
	check(ops.restore_save(developed).is_empty(),"developed roots restore")
	var stats: Dictionary = ops.stats()
	check(stats.hp==130 and stats.mp==45 and stats.attack==28 and stats.defense==10 and stats.blood==90 and stats.spell_bps==30,
		"root points affect the configured combat and resource capacities")
	var vitals: Dictionary = ops.snapshot().player
	check(vitals.hp==120 and vitals.mp==40 and vitals.blood==80,"increasing capacities does not refill current resources")
	developed.state.player.blood = 91
	check(not ops.restore_save(developed).is_empty() and ops.snapshot().player==vitals,
		"invalid blood above capacity cannot replace state")
	for route in ["qi","body"]:
		for level in range(9,81,9):
			var fixture: Dictionary = clean.duplicate(true)
			var p: Dictionary = fixture.state.player
			if route=="qi":
				p.realm = level
			else:
				p.growth.body_level = level
			var required: int = cultivation.requirement(p,route,data)
			if route=="qi":
				p.cultivation = required
			else:
				p.growth.body_cultivation = required
			var target: Dictionary = data.realm_tiers["tier_%d" % Cultivation.tier_index(level+1)]
			var resources: Dictionary = target[route+"_materials"]
			var cap: int = cultivation.attribute_cap(p,route,data)
			for key in Cultivation.GROWTH_ATTRIBUTES[route]:
				p.growth.attributes[key] = cap
			check(ops.restore_save(fixture).is_empty(),"major tier fixture validates")
			var before: Dictionary = ops.snapshot()
			var missing: Dictionary = ops.request("promote",{"route":route})
			check(not missing.success and ops.snapshot()==before,"missing resources cannot consume time, materials or progress")
			for id in resources:
				p.inventory[id] = int(resources[id])
			if route=="body" or level>9:
				var key: String = Cultivation.GROWTH_ATTRIBUTES[route][0]
				p.growth.attributes[key] = cap-3
				check(ops.restore_save(fixture).is_empty(),"weak foundation fixture validates")
				before = ops.snapshot()
				var blocked: Dictionary = ops.request("promote",{"route":route})
				check(not blocked.success and ops.snapshot()==before,"insufficient foundation leaves materials and clock intact")
				p.growth.attributes[key] = cap
			if route=="qi" and level==9:
				var rng := RandomService.new()
				for seed_value in range(1,100):
					rng.initialize(seed_value)
					var candidate: Dictionary = rng.snapshot()
					if rng.roll("world")<0.8:
						fixture.random = candidate
						break
			if route=="body" and level==9:
				p.techniques.technique_iron_body = 3
				p.technique_slots.append("technique_iron_body")
			check(ops.restore_save(fixture).is_empty(),"resource-bearing fixture validates")
			var result: Dictionary = ops.request("promote",{"route":route})
			var after: Dictionary = ops.snapshot()
			var next_level: int = after.player.realm if route=="qi" else after.player.growth.body_level
			check(result.success and next_level==level+1 and after.player.lifespan==target.lifespan
				and after.hours==fixture.state.hours+240,"major breakthrough advances the correct route, lifespan and clock")
			var all_spent := true
			for id in resources:
				all_spent = all_spent and after.player.inventory.get(id,0)==0
			check(all_spent,"major resources are consumed exactly once")
			if level==9:
				check(after.player.growth.breakthrough_quality.get(route)=="high","quality uses actual roots and is stored on the first major success")
			check(after.player.get("fortunes",{}).has("stable_foundation") == (level==9),"only a qualifying high-quality breakthrough grants the trait")
			check(ops.restore_save(ops.export_save()).is_empty(),"new tier and quality survive save restore")
	var maximum: Dictionary = clean.duplicate(true)
	maximum.state.player.realm = 81
	maximum.state.player.growth.body_level = 81
	maximum.state.player.lifespan = 12000
	check(ops.restore_save(maximum).is_empty(),"both ninth tiers can be loaded")
	check(Cultivation.realm_name(81,"qi",data)=="渡劫九层" and Cultivation.realm_name(81,"body",data)=="渡劫九层",
		"ninth tiers display their terminal layer")
	check(not ops.request("promote",{"route":"qi"}).success and not ops.request("promote",{"route":"body"}).success,
		"both routes stop at the ninth tier's ninth layer")
	print("REALM TIERS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
