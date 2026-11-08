extends SceneTree

const Flow := preload("res://gameplay/cultivation/spirit_flow.gd")
const Simulation := preload("res://gameplay/cultivation/spirit_flow_simulation.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var unit: int = Flow.QUANTA_PER_POINT
	var example: Dictionary = Flow.flow(80 * unit, 60 * unit, 48 * unit, 44 * unit, 909)
	check(example.absorbed == 60 * unit and example.channelled == 48 * unit
		and example.processed == 44 * unit, "the stages apply independent limits")
	check(example.unabsorbed + example.channel_return + example.refinement_return + example.refinement_loss
		+ example.refined == example.available, "unabsorbed, returned, lost and refined quantities balance")
	check(example.refined + example.refinement_loss == example.consumed, "returns are not deducted from the reservoir")
	var empty: Dictionary = Flow.flow(0, 60 * unit, 48 * unit, 44 * unit, 909)
	check(empty.consumed == 0 and empty.refined == 0, "an empty reservoir cannot give cultivation energy")

	var duration := 86400
	var rate := 33831
	var interval: int = Flow.interval_quantity(rate, duration)
	var full: Dictionary = Flow.flow(interval, interval, interval, interval, 1733)
	var total_loss := 0
	var remainder := 0
	var slice: int = Flow.interval_quantity(rate, duration / 1440)
	for index in range(1440):
		var chunk: Dictionary = Flow.flow(slice, slice, slice, slice, 1733, remainder)
		total_loss += int(chunk.refinement_loss)
		remainder = chunk.loss_remainder
	check(total_loss == full.refinement_loss and remainder == full.loss_remainder, "splitting the same rate does not change loss")

	var overflow: Dictionary = Flow.transfer(100, 95, 100, 20)
	check(overflow.moved == 5 and overflow.source + overflow.target == 195, "a full target cannot create or destroy energy")
	var drained: Dictionary = Flow.transfer(2, 0, 100, 20)
	check(drained.moved == 2 and drained.source == 0 and drained.target == 2, "transfer is limited by source stock")
	_balance_trials()
	print("SPIRIT FLOW: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _balance_trials() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.new_game("灵气试算验收","木")
	var data: Dictionary = gm.operations.data
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cultivation/spirit_flow.json"))
	check(Simulation.validate(rules,data.techniques,data.rules.roots).is_empty(),"default configuration validates")
	var malformed: Dictionary = rules.duplicate(true)
	malformed.environments.town.baseline = 0
	check(not Simulation.validate(malformed,data.techniques,data.rules.roots).is_empty(),"invalid reservoir parameters rejected")
	var initial: Dictionary = gm.operations.export_save()
	var player: Dictionary = initial.state.player.duplicate(true)
	var ordinary := {"root_quality":"ordinary","spirituality":20,"constitution":20}
	var profile := Flow.profile(player,"qi",data.techniques,rules,ordinary)
	for scenario in [["natural","town",11.0,10.0],["practice","town",22.0,22.0],["retreat","cave",48.4,48.4]]:
		var ledger: Dictionary = Simulation.simulate(profile,rules.environments[scenario[1]],rules,scenario[0],86400)
		check(absf(ledger.cultivation-scenario[3])<0.015,"migration rate calibrates: " + scenario[0])
		print("CALIBRATION %s old=%.3f supply=%.3f absorbed=%.3f channelled=%.3f refined=%.3f loss=%.3f new=%.3f" %
			[scenario[0],scenario[2],_points(ledger.available),_points(ledger.absorbed),_points(ledger.channelled),
			_points(ledger.refined),_points(ledger.refinement_loss),ledger.cultivation])
	player.techniques.technique_iron_body = 1
	player.technique_slots.append("technique_iron_body")
	var weak: Dictionary = player.duplicate(true)
	weak.growth.attributes.meridians = 8
	var improved: Dictionary = player.duplicate(true)
	improved.growth.attributes.meridians = 40
	improved.techniques.technique_qi_flow = 3
	improved.growth.attributes.bones = 40
	improved.growth.attributes.physique = 40
	var cases := [
		[player,"qi",ordinary],
		[player,"qi",{"root_quality":"heavenly","spirituality":20,"constitution":20}],
		[player,"qi",{"root_quality":"ordinary","spirituality":60,"constitution":20}],
		[player,"qi",{"root_quality":"heavenly","spirituality":60,"constitution":20}],
		[improved,"qi",ordinary],
		[improved,"body",{"root_quality":"ordinary","spirituality":20,"constitution":60}],
		[weak,"qi",ordinary],
		[player,"body",ordinary],
	]
	var environments := [["town",0,false],["cave",0,false],["advanced_cave",0,false],["sparse",0,false],
		["rich",0,false],["cave",1,false],["cave",0,true],["starved",0,false]]
	for scenario in cases:
		var caps := Flow.profile(scenario[0],scenario[1],data.techniques,rules,scenario[2])
		for env in environments:
			var all_conserved := true
			for hours in [1,24,240,8640]:
				var result := Simulation.simulate(caps,rules.environments[env[0]],rules,"retreat",hours*3600,env[1],env[2])
				all_conserved = all_conserved and _balanced(result)
			check(all_conserved,"short and long scenarios conserve all energy: " + str(env))
	var untrained: Dictionary = player.duplicate(true)
	untrained.technique_slots.erase("technique_iron_body")
	var no_body := Flow.profile(untrained,"body",data.techniques,rules,ordinary)
	var blocked := Simulation.simulate(no_body,rules.environments.cave,rules,"retreat",86400)
	check(blocked.refined==0 and blocked.consumed==0,"a second route without an equipped technique consumes no energy")
	var channel_limited := Flow.profile(weak,"qi",data.techniques,rules,ordinary)
	var channel_result := Simulation.simulate(channel_limited,rules.environments.rich,rules,"retreat",86400)
	check(channel_result.channel_return>0,"meridians can be an actual bottleneck")
	check(gm.operations.export_save()==initial,"trial leaves real time, progress, equipment and random state untouched")

func _points(quanta: int) -> float:
	return float(quanta)/Flow.QUANTA_PER_POINT

func _balanced(result: Dictionary) -> bool:
	var local_ok: bool = result.start+result.recovered+result.released+result.transferred == result.end+result.diffused+result.consumed
	var surroundings_ok: bool = result.surrounding_start+result.diffused == result.surrounding_end+result.transferred
	var refinement_ok: bool = result.refined+result.refinement_loss==result.consumed
	return local_ok and surroundings_ok and refinement_ok and result.end>=0 and result.surrounding_end>=0
