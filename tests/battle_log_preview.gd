extends SceneTree
const FORMAT=preload("res://ui/battle/battle_log_formatter.gd")
var gm: Node
var page: Control
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(title)
func settle() -> void:
	for index in range(6):await process_frame
	await RenderingServer.frame_post_draw
func choose_seed(critical: bool,status: bool=false) -> void:
	for value in range(10000):
		var rng=load("res://core/random_service.gd").new();rng.initialize(value)
		var is_crit: bool=rng.roll("battle")<gm.operations.data.rules.crit_chance
		var has_status: bool=rng.roll("battle")<gm.operations.data.rules.status_chance
		if is_crit==critical and (not status or has_status):gm.operations.random.initialize(value);return
	check(false,"deterministic seed available")
func fixture(spell: String="skill_spirit_bolt",outcome: String="") -> void:
	gm.new_game("日志验收","木")
	var saved: Dictionary=gm.operations.export_save()
	saved.state.player.location="area_qinglan_outskirts";saved.state.player.hp=50
	saved.state.player.spells[spell]=1;saved.state.player.spell_slots=[spell]
	gm.operations.battle.start(saved.state,"monster_mountain_boar",gm.operations.data,"log_fixture")
	saved.state.battle.phase="active"
	if outcome=="win":saved.state.battle.enemy.hp=1
	if outcome=="lose":saved.state.player.hp=1;saved.state.battle.enemy.speed=999
	check(gm.operations.restore_save(saved).is_empty(),"valid isolated fixture")
	choose_seed(false)
	page.bind_data(gm.operations)
func current_battle() -> Dictionary:
	var state: Dictionary=gm.operations.snapshot()
	return state.battle if not state.battle.is_empty() else state.battle_report.background.battle
func of_type(entries: Array,type: String) -> Array:return entries.filter(func(entry):return entry.type==type)
func run() -> void:
	gm=root.get_node("GameManager");gm.set_process(false);root.size=Vector2i(1920,1080)
	page=load("res://ui/battle/battle_page.tscn").instantiate();root.add_child(page)
	fixture();await settle()
	var log_rect: Rect2=page.field("Log").get_global_rect()
	var panel_rect: Rect2=page.field("LogPanel").get_global_rect()
	check(FORMAT.COLORS=={"normal":"#D5DFE4","damage":"#F07878","heal":"#78C995","critical":"#F4C766","mana":"#82BCE5","buff":"#86CDB3","debuff":"#C8A1E8","avoidance":"#D6C990","system":"#A4B7C1","victory":"#F0D597"},"exact single semantic palette")
	var records: Array=[]
	for scenario in ["attack","critical","heal","mana","mana_restore","buff","debuff","defend"]:
		var spell: String={"heal":"skill_wood_heal","buff":"skill_earth_guard","debuff":"skill_fire_bolt"}.get(scenario,"skill_spirit_bolt")
		fixture(spell);choose_seed(scenario=="critical",scenario=="debuff")
		var args: Dictionary={"kind":"attack"}
		if scenario in ["heal","mana","buff","debuff"]:args={"kind":"spell","id":spell}
		if scenario=="defend":args={"kind":"defend"}
		if scenario=="mana_restore":
			var mana_save: Dictionary=gm.operations.export_save();mana_save.state.player.mp=1
			check(gm.operations.restore_save(mana_save).is_empty(),"low mana fixture valid")
			args={"kind":"item","id":"item_aura_powder"}
		check(gm.operations.request("battle_action",args).success,"real action "+scenario)
		var battle: Dictionary=current_battle()
		var entries: Array=battle.log_entries
		check(of_type(entries,"round").size()==1 and of_type(entries,"action").size()==2,"one separator and exactly two real actions "+scenario)
		var hp: Array=of_type(entries,"hp")
		for entry in hp:check(entry.amount==entry.after-entry.before,"HP delta exact "+scenario)
		for entry in of_type(entries,"mp"):check(entry.amount==entry.after-entry.before,"MP delta exact "+scenario)
		var first_damage: Dictionary=hp[0]
		if scenario=="attack":check(FORMAT.record(first_damage).contains("[color=#F07878]"),"normal damage red")
		if scenario=="critical":
			var line: String=FORMAT.record(first_damage)
			check(first_damage.critical and line.contains("暴击") and line.contains("#F4C766") and not line.contains("#F07878"),"critical exclusively gold")
		if scenario=="heal":check(first_damage.amount>0 and FORMAT.record(first_damage).contains("#78C995"),"actual healing green")
		if scenario=="mana":
			var action_line: String=FORMAT.record(of_type(entries,"action")[0])
			check(action_line.contains("[color=#82BCE5]灵气弹[/color]"),"spell name blue")
			check(FORMAT.record(of_type(entries,"mp")[0]).contains("#82BCE5"),"actual mana cost blue")
			check(FORMAT.record(first_damage).contains("#F07878") and FORMAT.record(first_damage).contains("#82BCE5"),"spell and damage independent colors in one line")
		if scenario=="mana_restore":
			var mp_entry: Dictionary=of_type(entries,"mp")[0]
			check(mp_entry.amount>0 and FORMAT.record(mp_entry).contains("#82BCE5"),"actual item mana recovery blue")
		if scenario in ["buff","debuff"]:
			var status: Dictionary=of_type(entries,"status")[0]
			check(FORMAT.record(status).contains("#86CDB3" if scenario=="buff" else "#C8A1E8"),"actual semantic status "+scenario)
		if scenario=="defend":check(of_type(entries,"avoidance").is_empty() and not of_type(entries,"defend").is_empty(),"defending never misreported as block")
		page.bind_data(gm.operations,"操作成功");await settle()
		var rendered: String=page.field("Log").text
		check(page.field("Log").bbcode_enabled and not page.field("Log").get_parsed_text().contains("操作成功"),"native BBCode and no success spam "+scenario)
		check(page.field("Log").get_global_rect()==log_rect and page.field("LogPanel").get_global_rect()==panel_rect,"panel geometry unchanged "+scenario)
		var before: Dictionary=gm.operations.export_save()
		page.bind_data(gm.operations,"操作成功");await settle()
		check(rendered==page.field("Log").text and before==gm.operations.export_save(),"repeat render no duplication or mutation "+scenario)
		if scenario in ["critical","mana","heal","buff","debuff"]:root.get_texture().get_image().save_png("res://docs/screenshots/battle_log_"+scenario+".png")
		records.append_array(entries.duplicate(true))
	# Refusal/avoidance formatting only: no existing dodge/block mechanics are invented.
	for outcome in ["dodge","block"]:
		var line: String=FORMAT.record({"type":"avoidance","target":"测试对象","outcome":outcome})
		check(line.contains("#D6C990") and not line.contains("#F07878"),"typed avoidance formatter "+outcome)
	for outcome in ["win","lose"]:
		fixture("skill_spirit_bolt",outcome)
		check(gm.operations.request("battle_action",{"kind":"attack"}).success,"real result "+outcome)
		var report: Dictionary=gm.operations.snapshot().battle_report
		check(report.result==outcome,"actual result kind "+outcome)
		var entries: Array=report.background.battle.log_entries
		check(of_type(entries,"result").size()==1,"one result record "+outcome)
		check(FORMAT.record(of_type(entries,"result")[0]).contains("#F0D597" if outcome=="win" else "#A4B7C1"),"result palette "+outcome)
		var payload: Dictionary=gm.operations.export_save()
		check(gm.operations.restore_save(payload).is_empty() and current_battle().log_entries==entries,"structured history save restore "+outcome)
		page.bind_data(gm.operations,"操作成功",report.background);await settle()
		check(page.field("Log").get_parsed_text().count("战斗胜利" if outcome=="win" else "战斗失败")==1,"result not duplicated "+outcome)
		var overlay=load("res://ui/battle/battle_result_overlay.tscn").instantiate();root.add_child(overlay);overlay.bind_data(report,gm.operations.data)
		check(overlay.field("Details").bbcode_enabled and overlay.field("Details").text.contains("#F0D597" if outcome=="win" else "#A4B7C1"),"same formatter in result details "+outcome)
		overlay.queue_free();await settle()
	# Inject BBCode-like dynamic names and strings; parsed text must preserve them literally.
	var malicious: String="[color=#00FF00][b]人名[/b][/color][img]x[/img][lb][rb]"
	var typed: Array=[{"type":"action","actor":malicious,"kind":"spell","label":malicious},{"type":"system","text":malicious},{"type":"action","actor":malicious,"kind":"item","label":malicious}]
	page.update_log([],"",typed);await settle()
	check(page.field("Log").get_parsed_text().count(malicious)==5,"names, spell and system strings escaped literally")
	check(not page.field("Log").text.contains("[img]x[/img]"),"dynamic content cannot inject image tag")
	# Legacy history remains literal and is preserved when the first new action is recorded.
	fixture();var legacy_save: Dictionary=gm.operations.export_save();legacy_save.state.battle.erase("log_entries");legacy_save.state.battle.log=["旧记录 "+malicious]
	check(gm.operations.restore_save(legacy_save).is_empty(),"old save without structured history accepted")
	page.bind_data(gm.operations);await settle()
	check(page.field("Log").get_parsed_text().contains(malicious),"legacy history safely rendered")
	check(gm.operations.request("battle_action",{"kind":"defend"}).success,"continue old battle")
	check(current_battle().log_entries[0].type=="legacy" and current_battle().log_entries[0].text==legacy_save.state.battle.log[0],"old history retained once without keyword parsing")
	var invalid_save: Dictionary=gm.operations.export_save();invalid_save.state.battle.log_entries.append({"type":"hp","target":"x","amount":"invalid"})
	var before_invalid: Dictionary=gm.operations.export_save()
	check(not gm.operations.restore_save(invalid_save).is_empty() and before_invalid==gm.operations.export_save(),"invalid typed log rejected atomically")
	# Large isolated presentation history: keep every row, follow bottom, preserve manual scroll.
	var long_history: Array=[]
	for index in range(180):long_history.append_array(records)
	page.update_log([],"",long_history);await settle()
	check(page.field("Log").get_parsed_text().count("── 第 1 回合 ──")==180*8,"long history no lost or duplicated separators")
	var scroll: VScrollBar=page.field("Log").get_v_scroll_bar()
	check(scroll.value>0 and scroll.value+scroll.page>=scroll.max_value-2,"long history follows bottom")
	scroll.value=0
	long_history.append({"type":"system","text":"尾部追加"})
	page.update_log([],"",long_history);await settle()
	check(is_zero_approx(scroll.value),"manual historical scroll preserved")
	check(page.field("Log").get_parsed_text().ends_with("尾部追加"),"latest history retained")
	page.append_log_message(malicious);await settle()
	check(page.field("Log").get_parsed_text().ends_with(malicious),"failed request message escaped")
	# Compact real colored sample copied solely from settled test battle records.
	page.update_log([],"",records);await settle();scroll.value=0;await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/battle_log_colors.png")
	root.size=Vector2i(1280,720);await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/battle_log_colors_small.png")
	page.queue_free();await settle()
	print("BATTLE LOG: %d checks, %d failures" % [checks,failures]);quit(0 if failures==0 else 1)
