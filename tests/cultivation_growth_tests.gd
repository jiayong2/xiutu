extends SceneTree

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
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	check(gm.new_game("温养验收", "金").is_empty(), "new character initializes")
	var operations: RefCounted = gm.operations
	var data: Dictionary = operations.data
	var cultivation: RefCounted = operations.cultivation
	var player: Dictionary = operations.snapshot().player
	var before: Dictionary = player.duplicate(true)
	check(not cultivation.promote_body(player, data).is_empty() and player == before,
		"body breakthrough at insufficient cultivation leaves all values intact")

	player.growth.body_cultivation = 100
	check(cultivation.promote_body(player, data).is_empty(), "body breakthrough succeeds at 100")
	check(cultivation.body_realm_name(player,data) == "通脉一层" and player.growth.body_cultivation == 0
		and player.realm == before.realm and player.cultivation == before.cultivation,
		"body breakthrough consumes only body cultivation")
	check(cultivation.attribute_cap(player, "body", data) == 31 and player.growth.attributes.bones == 20,
		"breakthrough raises capacity without granting current attribute points")

	player.techniques.technique_iron_body = 1
	player.technique_slots.append("technique_iron_body")
	player.growth.focus.body = "nurture"
	var snapshot: Dictionary = operations.snapshot()
	snapshot.player=player
	var split: Dictionary = snapshot.duplicate(true)
	operations.clock.advance_seconds(snapshot,30*3600,data,operations.random,"practice","body")
	for hour in range(30):
		operations.clock.advance_seconds(split,3600,data,operations.random,"practice","body")
	check(snapshot == split and player.growth.attributes.bones == 21 and player.growth.attributes.physique == 21
		and player.growth.attributes.qi_sea == 20, "nurture is interval independent and confined to its route")
	operations.clock.advance_seconds(snapshot,2000*3600,data,operations.random,"practice","body")
	check(player.growth.attributes.bones == 31 and snapshot.spirit.progress.body.nurture == 0,
		"capacity prevents banking excess progress")

	var save: Dictionary = operations.export_save()
	save.state.player.erase("growth")
	save.state.erase("spirit")
	check(operations.restore_save(save).is_empty() and operations.snapshot().player.growth.body_level == 0,
		"older saves initialize body cultivation without changing the old file")
	var invalid: Dictionary = operations.export_save()
	invalid.state.player.growth.attributes.bones = 999
	before = operations.snapshot()
	check(not operations.restore_save(invalid).is_empty() and operations.snapshot() == before,
		"invalid growth is rejected without replacing live state")

	var result: Dictionary = operations.request("practice", {"route":"body", "days":1})
	check(not result.success and result.message.contains("炼体功法") and operations.snapshot()==before,
		"body practice requires a matching equipped technique and spends no time on failure")
	save = operations.export_save()
	save.state.player.techniques.technique_iron_body = 1
	check(operations.restore_save(save).is_empty() and operations.request("slot", {"id":"technique_iron_body"}).success,
		"existing Iron Body technique enables the body route")
	operations.advance_realtime(24 * 3600)
	var current: Dictionary = operations.snapshot().player
	check(current.cultivation > 0 and current.growth.body_cultivation == 0 and operations.snapshot().spirit.progress.body.nurture == 0,
		"online breathing gives growth only to qi even with both technique types equipped")
	check(operations.request("cultivation_focus", {"route":"body", "focus":"nurture"}).success,
		"body focus can be set separately")
	before = operations.snapshot()
	check(operations.request("practice", {"route":"body", "days":1}).success, "body practice succeeds")
	current = operations.snapshot().player
	check(current.growth.body_cultivation == 19 and current.cultivation == before.player.cultivation
		and absf(operations.clock.spirit.nurture_points(operations.snapshot(),"body",data)-9.778)<0.002,
		"body nurture uses its focus without qi growth or qi technique speed bonuses")
	check(operations.request("slot", {"id":"technique_qi_flow"}).success, "qi technique can be removed")
	before = operations.snapshot()
	operations.advance_realtime(24 * 3600)
	current = operations.snapshot().player
	check(current.cultivation == before.player.cultivation and current.growth == before.player.growth,
		"online breathing without a matching qi technique does not grow either route")
	check(not operations.request("practice", {"days":1}).success, "qi practice requires a qi technique")
	check(operations.request("travel", {"id":"cave_qinglan"}).success, "enter cave")
	save = operations.export_save()
	var quote: Dictionary = operations.retreat_preview(0, 0, 0, true, "body")
	check(quote.success and quote.after == 100 and operations.export_save() == save,
		"target retreat preview finds the body bottleneck and leaves the live state intact")
	result = operations.request("retreat_target", {"route":"body"}, "growth-body-retreat")
	var after: Dictionary = operations.snapshot()
	check(result.success and after.retreat_report.route == "body" and after.retreat_report.after == 100
		and after.retreat_report.elapsed == quote.elapsed and after.player.cultivation == save.state.player.cultivation,
		"body retreat commits once and reports the same route and elapsed time as the preview")
	check(not operations.request("retreat_target", {"route":"body"}, "growth-body-retreat").success
		and operations.snapshot() == after, "replaying a retreat does not grant more cultivation or consume time")
	check(operations.request("promote", {"route":"body"}).success
		and operations.snapshot().player.growth.body_level == 1, "body promotion works through the public action")
	save = operations.export_save()
	check(operations.restore_save(save).is_empty() and operations.export_save() == save,
		"body progress, cultivation focus and body retreat report round-trip")

	print("CULTIVATION GROWTH: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
