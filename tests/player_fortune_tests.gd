extends SceneTree

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)

func run() -> void:
	var ids := {}
	var qualities := {}
	var kinds := {}
	var valid := true
	for id in Fortunes.DEFINITIONS:
		var definition: Dictionary = Fortunes.DEFINITIONS[id]
		kinds[definition.kind] = kinds.get(definition.kind,0) + 1
		qualities[definition.quality] = true
		for effect in definition.effects:
			valid = valid and not ids.has(effect.id) and effect.status in ["A","B","C","D","E"]
			valid = valid and effect.implemented == (effect.status == "A")
			ids[effect.id] = true
	check(kinds == {"innate":48,"acquired":48,"negative":12} and qualities.size() == 7,"108 definitions and seven palettes")
	check(ids.size() >= 195 and valid,"effect identifiers and statuses")
	var manager: Node = root.get_node("GameManager")
	var op: RefCounted = manager.operations
	check(manager.new_game("气运验收","火").is_empty(),"legacy creation")
	var baseline: Dictionary = op.stats()
	check(manager.new_game("气运验收","火","battle_veteran") != "","reject acquired trait at birth")
	check(manager.new_game("气运验收","火","mountain_origin").is_empty(),"select innate trait")
	check(op.stats().hp == baseline.hp + roundi(baseline.hp * 0.05),"innate bonus")
	var payload: Dictionary = op.export_save()
	payload.state.player.fortune_wins = 49
	payload.state.player.location = "area_qinglan_outskirts"
	op.battle.start(payload.state,"monster_gray_wolf",op.data,"fortune_fixture")
	payload.state.battle.enemy.hp = 1
	check(op.restore_save(payload).is_empty(),"restore partial victory progress")
	check(op.request("battle_action",{"kind":"attack"},"fortune_test_win").success,"settle real battle")
	var saved: Dictionary = op.export_save()
	check(saved.state.player.get("fortune_wins",0) == 50 and saved.state.player.fortunes.has("battle_veteran"),"grant at victory threshold")
	check(op.stats().hp == baseline.hp + roundi(baseline.hp * 0.08),"add percentages before rounding")
	check(op.restore_save(saved).is_empty() and op.export_save() == saved,"round trip without reapplying awards")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.state.player.fortunes.unknown = {}
	check(not op.restore_save(invalid).is_empty(),"reject unknown trait")
	var page: Control = load("res://ui/character/character_page.tscn").instantiate()
	root.add_child(page)
	page.bind_data(op)
	check(page.field("TalentGrid").get_child(0).get_child(0).text == "山野出身","innate tag")
	check(page.field("StatusGrid").get_child(0).tooltip_text.contains("战斗胜利"),"acquired tag source")
	var simulated: Dictionary = op.export_save()
	var actor: Dictionary = simulated.state.player
	var now: int = op.clock.seconds(simulated.state)
	check(Fortunes.grant(actor,"battle_streak",now,"测试连续胜利"),"grant timed trait")
	check(not Fortunes.grant(actor,"battle_streak",now,"重复发放"),"duplicate timed grant rejected")
	check(Fortunes.modifier(actor,"damage") == 5,"timed damage active")
	var negative := "fortune_097"
	check(Fortunes.grant(actor,negative,now,"测试负面气运"),"grant negative test trait")
	actor.mp = mini(int(actor.mp),roundi(baseline.mp * 0.9))
	check(op.restore_save(simulated).is_empty(),"restore timed and negative records")
	var caps: Dictionary = op.stats()
	check(caps.mp == roundi(baseline.mp * 0.9),"negative reduces resource cap")
	page.bind_data(op)
	var tag: PanelContainer = page.field("StatusGrid").get_child(2)
	check(tag.get_theme_stylebox("panel").bg_color == Color("29292B"),"negative scheme D")
	check(Fortunes.remove(actor,negative) and op.restore_save(simulated).is_empty() and op.stats().mp == baseline.mp,"removal restores capacity")
	var next: Dictionary = op.snapshot()
	var seconds: int = next.player.fortunes.battle_streak.expires_at-op.clock.seconds(next)
	op.clock.advance_seconds(next,seconds,op.data,op.random,"none")
	check(not next.player.fortunes.has("battle_streak") and Fortunes.modifier(next.player,"damage") == 0,"expires exactly on world clock boundary")
	var counter := {"turn":1}
	check(Fortunes.use_battle_trigger(counter,"lightning_first_hit",true),"first battle trigger")
	counter.turn = 2
	check(not Fortunes.use_battle_trigger(counter,"lightning_first_hit",true),"battle trigger cannot repeat next round")
	check(Fortunes.valid_battle_triggers(counter),"battle trigger state is serializable")
	var dormant := {}
	check(Fortunes.record_event(dormant,"fortune_096",0,86400,"未接入事件").is_empty(),"unconnected events cannot grant production traits")
	check(Fortunes.grant(dormant,"fortune_053",0,"隔离测试") and Fortunes.consume(dormant,"fortune_053") and not Fortunes.consume(dormant,"fortune_053"),"single-use record consumes once")
	check(manager.new_game("气血验收","火","fortune_004").is_empty() and op.restore_save(op.export_save()).is_empty(),"negative innate capacity remains saveable")
	check(manager.new_game("交易验收","火").is_empty(),"new trade fixture")
	var trader: Dictionary = op.export_save()
	trader.state.player.fortune_progress = {"trade_expert":19}
	check(op.restore_save(trader).is_empty(),"restore trade progress")
	var args := {"shop":"shop_qinglan_general","item":"item_healing_powder","quantity":1}
	var before_quote: Dictionary = op.trade_quote(args.shop,args.item,true)
	check(op.request("buy",args,"fortune_trade_test").success and op.snapshot().player.fortunes.has("trade_expert"),"successful trade awards trait")
	var after_quote: Dictionary = op.trade_quote(args.shop,args.item,true)
	check(after_quote.unit < before_quote.unit,"next trade quote applies discount")
	check(not op.request("buy",args,"fortune_trade_test").success and op.snapshot().player.fortune_progress.trade_expert == 20,"trade retry cannot increase progress")
	var natural: Dictionary = op.snapshot()
	var boosted: Dictionary = natural.duplicate(true)
	check(Fortunes.grant(boosted.player,"fortune_033",op.clock.seconds(boosted),"修炼夹具"),"load cultivation talent")
	var normal_step: Dictionary = op.clock.spirit.plan(natural,"practice","qi",op.data,op.cultivation)
	var boosted_step: Dictionary = op.clock.spirit.plan(boosted,"practice","qi",op.data,op.cultivation)
	check(normal_step.efficiency == 100 and boosted_step.efficiency == 115 and boosted_step.nurture_need == normal_step.nurture_need,"cultivation modifier changes conversion without changing nurture")
	var npc: Dictionary = op.snapshot().npcs.values()[0]
	check(Fortunes.grant(npc,negative,0,"NPC 测试") and Fortunes.modifier(npc,"spell_cost") == 5,"shared NPC effect processing")
	check(Fortunes.modifier(actor,"breakthrough_chance","","个百分点") == 0,"pending rules never modify computation")
	page.queue_free()
	quit(0 if failures == 0 else 1)
