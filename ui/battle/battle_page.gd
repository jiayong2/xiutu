extends Control
const LOG_FORMAT=preload("res://ui/battle/battle_log_formatter.gd")
const Status=preload("res://gameplay/battle/battle_status.gd")
const Battle=preload("res://gameplay/battle/battle_system.gd")
signal navigate(destination: String)
signal presentation_finished
signal action_requested(action: String,args: Dictionary)
var service: RefCounted
var state: Dictionary
var data: Dictionary
var skill_page := 0
var units: Array = []
var selected := ""
var playing := false
var animation_speed := 1.0

func _status_text(id: String, effect: Dictionary) -> String:
	var title := LOG_FORMAT.status_name(id,data.spell_growth.statuses)
	var detail := "%d点" % int(effect.amount) if effect.has("maximum") else "%d层" % int(effect.layers) if int(effect.get("layers",1)) > 1 else ""
	return "%s%s · 剩余%d次行动" % [title," "+detail if not detail.is_empty() else "",effect.turns]
var skip_presentation := false
var active_tweens: Array[Tween]=[]
var floating_labels: Array[Label]=[]
var actor_origins: Dictionary={}
var active_actor := ""
var last_frame: Dictionary={}
var round_order: Array=[]
var turn_queue: Array=[]
func field(key: String) -> Node:return find_child(key,true,false)
func box(color: Color,active: bool=false) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new()
	b.bg_color=color
	b.set_corner_radius_all(6)
	b.set_border_width_all(2 if active else 0)
	b.border_color=Color("e9d6a9")
	return b
func _ready() -> void:
	var t:=Theme.new()
	t.default_font_size=22
	for key in ["normal","hover","pressed","disabled","focus"]:
		t.set_stylebox(key,"Button",box(Color("486471") if key!="disabled" else Color("334650")))
	var panel_style:=box(Color("2c4551"))
	panel_style.content_margin_left=16
	panel_style.content_margin_right=16
	panel_style.content_margin_top=12
	panel_style.content_margin_bottom=12
	t.set_stylebox("panel","PanelContainer",panel_style)
	theme=t
	for pair in [["Attack","attack"],["Defend","defend"]]:
		field(pair[0]).pressed.connect(_act.bind(pair[1],""))
	field("Begin").pressed.connect(func():action_requested.emit("begin_battle",{}))
	field("Item").pressed.connect(_items)
	field("Escape").pressed.connect(_escape)
	field("Skill5").pressed.connect(func():skill_page=1-skill_page;_skills())
	field("Auto").disabled=true
	field("Auto").tooltip_text="当前战斗系统尚未实现自动战斗"
	field("Speed").pressed.connect(func():animation_speed=1.5 if animation_speed==1.0 else 2.0 if animation_speed==1.5 else 1.0;field("Speed").text="×"+str(animation_speed);field("TurnOrder").set_speed(animation_speed))
	field("TurnOrder").current_changed.connect(_highlight_actor)
	field("Log").bbcode_enabled=true
	field("Log").add_theme_color_override("default_color",Color(LOG_FORMAT.COLORS.normal))
	field("Log").scroll_following=false
	field("Skip").pressed.connect(skip_animations)
	field("Skip").hide()
	for key in ["AllyFormation","EnemyFormation"]:field(key).resized.connect(_layout)
func bind_data(operations: RefCounted,message: String="",background: Dictionary={}) -> void:
	service=operations;state=service.snapshot();data=service.data
	if not background.is_empty():state.player=background.player;state.battle=background.battle
	if state.battle.is_empty():
		set_units([])
		update_log([],message)
		field("Begin").text="返回地点"
		for key in ["Attack","Defend","Item","Escape"]:field(key).disabled=true
		field("Begin").pressed.disconnect(field("Begin").pressed.get_connections()[0].callable)
		field("Begin").pressed.connect(func():navigate.emit("地点场景"))
		_skills()
		return
	var b: Dictionary=state.battle
	var stats: Dictionary=service.stats()
	field("Round").text="第 %d 回合" % service.battle.display_round(b)
	field("Title").text=str(b.enemy.name)+" · 战斗"
	var ally: Dictionary={"id":"player","name":state.player.name,"hp":state.player.hp,"mp":state.player.mp,"max_hp":stats.hp,"max_mp":stats.mp,"speed":stats.speed,"side":"ally","statuses":[]}
	if state.player.has("blood"):
		ally.blood=state.player.blood
		ally.max_blood=stats.blood if background.is_empty() else service.character.stats(state.player,data).blood
	var enemy: Dictionary=b.enemy.duplicate(true)
	enemy.merge({"id":"enemy","side":"enemy","max_hp":data.monsters[b.monster].hp,"max_mp":data.monsters[b.monster].mp,"statuses":[]},true)
	for id in b.status:
		var effect: Dictionary=b.status[id]
		var entry := _status_text(id,effect)
		if Status.is_player(id):ally.statuses.append(entry)
		else:enemy.statuses.append(entry)
	if b.guard:ally.statuses.append("防御 · 本轮减伤")
	var prepare: bool=b.phase=="prepare"
	var waiting: bool=not service.battle.needs_round(b) and background.is_empty()
	var queue: Array=service.battle.waiting_order(b) if waiting else service.battle.action_order(stats,b,data.spell_growth)
	field("TurnOrder").set_caption("等待指令" if waiting else "待开战" if prepare else "准备行动")
	set_units([ally,enemy],queue,false)
	field("Begin").visible=prepare
	for key in ["Attack","Defend","Escape"]:field(key).disabled=not waiting
	field("Item").disabled=not (prepare or waiting)
	field("ActionTitle").text="战斗准备" if prepare else "轮到你行动" if waiting else "战斗操作"
	update_log(b.get("log",[]),message,b.get("log_entries",[]))
	_skills()
func update_log(lines: Array,message: String="",entries: Array=[]) -> void:
	var log_scroll: VScrollBar=field("Log").get_v_scroll_bar()
	var at_bottom: bool=log_scroll.value+log_scroll.page>=log_scroll.max_value-2
	var old_scroll: float=log_scroll.value
	var formatted: String=LOG_FORMAT.render(entries,lines,message,data.spell_growth.statuses)
	if field("Log").text==formatted:return
	field("Log").text=formatted
	call_deferred("_restore_log_scroll",at_bottom,old_scroll)
func _restore_log_scroll(follow: bool,old_scroll: float) -> void:
	var scroll: VScrollBar=field("Log").get_v_scroll_bar()
	scroll.value=scroll.max_value if follow else old_scroll
func append_log_message(message: String) -> void:
	var formatted: String=LOG_FORMAT.system_message(message)
	if formatted.is_empty():return
	var scroll: VScrollBar=field("Log").get_v_scroll_bar()
	var at_bottom: bool=scroll.value+scroll.page>=scroll.max_value-2
	var old_scroll: float=scroll.value
	field("Log").append_text("\n"+formatted)
	call_deferred("_restore_log_scroll",at_bottom,old_scroll)
func _act(kind: String,id: String) -> void:
	if playing:return
	var args: Dictionary={"kind":kind}
	if not id.is_empty():args.id=id
	action_requested.emit("battle_action",args)
func _skills() -> void:
	var equipped: Array=state.get("player",{}).get("spell_slots",[])
	for i in range(5):
		var button: Button=field("Skill"+str(i))
		for connection in button.pressed.get_connections():button.pressed.disconnect(connection.callable)
		var index: int=skill_page*5+i
		button.disabled=true;button.text="未装备";button.tooltip_text="尚未装备主动法术"
		if index>=equipped.size():continue
		var id: String=equipped[index]
		var spell: Dictionary=data.spells[id]
		var cost := service.battle.effects.mana_cost(spell,state.battle,state.player) as int
		button.text="%s\n%d 灵力" % [spell.name,cost]
		var b: Dictionary=state.battle
		var reason: String=""
		if b.is_empty():reason="战斗已结束"
		elif b.phase=="prepare":reason="请先开始战斗"
		elif service.battle.needs_round(b):reason="请等待轮到玩家"
		elif b.cooldowns.get(id,0)>0:reason="冷却剩余%d回合" % b.cooldowns[id]
		elif state.player.mp<cost:reason="灵力不足"
		button.disabled=not reason.is_empty();button.tooltip_text=reason
		button.pressed.connect(_act.bind("spell",id))
	field("Skill5").disabled=false
	field("Skill5").text="展开" if skill_page==0 else "返回"
func _items() -> void:
	if playing:return
	var popup:=PopupMenu.new();add_child(popup)
	var ids: Array[String]=[]
	for id in Battle.RECOVERY_ITEMS:
		ids.append(id)
		var count: int=state.player.inventory.get(id,0)
		popup.add_item("%s ×%d" % [data.items[id].name,count])
		popup.set_item_disabled(ids.size()-1,count<=0)
	popup.id_pressed.connect(func(index: int):
		if state.battle.phase=="prepare":action_requested.emit("prepare_use",{"id":ids[index]})
		else:_act("item",ids[index]))
	popup.popup_hide.connect(popup.queue_free)
	popup.position=Vector2i(get_global_mouse_position());popup.popup()
func _escape() -> void:
	if playing:return
	var dialog:=ConfirmationDialog.new();add_child(dialog)
	dialog.dialog_text="尝试逃跑？成功率 %d%%，失败将按原规则结算本轮。" % int(data.rules.escape_chance*100)
	dialog.confirmed.connect(_act.bind("escape",""))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
func set_units(entries: Array,order: Array=[],animate: bool=true) -> void:
	if playing:skip_animations()
	units=entries
	var ids: Array=entries.map(func(u):return u.id)
	for key in ["AllyFormation","EnemyFormation"]:
		for child in field(key).get_children():
			if str(child.name) not in ids:field(key).remove_child(child);child.queue_free()
	# Generic previews provide their queue in entry order; production always passes the system queue.
	round_order=order.duplicate() if not order.is_empty() else entries.map(func(u):return u.id)
	turn_queue=round_order.duplicate()
	var turn_bar: Control=field("TurnOrder")
	var live_ids: Array=entries.filter(func(unit):return unit.hp>0).map(func(unit):return unit.id)
	var live_order: Array=turn_queue.filter(func(id):return id in live_ids)
	turn_bar.set_queue(entries,turn_queue,[],animate and not turn_bar.action_queue.is_empty() and turn_bar.action_queue!=live_order)
	for u in entries:
		var area: Control=field("AllyFormation" if u.side=="ally" else "EnemyFormation")
		var view: VBoxContainer=area.get_node_or_null(NodePath(u.id))
		if view==null:
			view=preload("res://ui/battle/unit_view.tscn").instantiate();view.name=u.id;area.add_child(view)
		view.set_meta("unit",u)
		view.add_theme_constant_override("separation",5)
		var statuses: HBoxContainer=view.get_node("StatusContainer")
		for child in statuses.get_children():statuses.remove_child(child);child.queue_free()
		var effects: Array=u.get("statuses",[])
		for i in range(mini(3,effects.size())):
			var badge:=Button.new();badge.add_theme_font_size_override("font_size",16)
			badge.text=str(effects[i]).split(" · ")[0] if i<2 else "+%d" % (effects.size()-2)
			badge.tooltip_text="\n".join(effects);statuses.add_child(badge)
		var square: Button=view.get_node("Square");square.text=u.name
		square.disabled=u.hp<=0
		if not square.pressed.is_connected(_select.bind(u.id)):square.pressed.connect(_select.bind(u.id))
		var label: Label=view.get_node("NameLabel");label.text=u.name
		for stat in ["hp","mp","blood"]:
			var bar: ProgressBar=view.get_node(stat)
			bar.visible=u.has(stat) and (stat!="blood" or u.id=="player")
			if not bar.visible:continue
			bar.max_value=maxf(1,u["max_"+stat]);bar.value=maxf(0,u[stat]);bar.show_percentage=false;bar.custom_minimum_size.y=12
			bar.tooltip_text="%s %s / %s" % ["气血" if stat=="blood" else stat.to_upper(),u[stat],u["max_"+stat]]
			if stat=="blood":continue
			bar.add_theme_stylebox_override("background",box(Color("3d5660")))
			bar.add_theme_stylebox_override("fill",box(Color("bf8391") if stat=="hp" else Color("83b2cc")))
	selected=""
	for u in entries:
		if u.side=="enemy" and u.hp>0:selected=u.id;break
	if not playing:active_actor=field("TurnOrder").current_id
	_layout();_select(selected)
func _select(id: String) -> void:
	if not id.is_empty():
		var valid: bool=false
		for u in units:
			if u.id==id and u.hp>0:valid=true
		if not valid:return
	selected=id
	for key in ["AllyFormation","EnemyFormation"]:
		for view in field(key).get_children():
			var u: Dictionary=view.get_meta("unit")
			var square: Button=view.get_node("Square")
			var style:=box(Color("7196a2") if u.side=="ally" else Color("947984"),u.id==selected or u.id==active_actor)
			if u.id==active_actor:style.border_color=Color("8bd6b5")
			square.add_theme_stylebox_override("normal",style)
func _layout() -> void:
	if playing:
		skip_animations()
		if not presentation_finished.is_connected(_layout):presentation_finished.connect(_layout,CONNECT_ONE_SHOT|CONNECT_DEFERRED)
		return
	var resource_height: float=104.0
	var player: Control=_view("player")
	if player!=null:
		var blood: ProgressBar=player.get_node("blood")
		if blood.visible:
			resource_height+=blood.custom_minimum_size.y+player.get_theme_constant("separation")
	for key in ["AllyFormation","EnemyFormation"]:
		var area: Control=field(key)
		var count: int=area.get_child_count()
		if count==0:continue
		var rows: int=ceili(count/2.0)
		var columns: int=mini(count,2)
		var reference: float=180 if count==1 else (160 if count==2 else (130 if count<=4 else 100))
		var side: float=maxf(16,minf(reference,minf(area.size.x/columns-32,area.size.y/rows-resource_height)))
		var cell:=Vector2(side+32,side+resource_height)
		for i in range(count):
			var view: Control=area.get_child(i)
			var row: int=i/2
			var row_count: int=mini(2,count-row*2)
			view.position=Vector2((area.size.x-row_count*cell.x)/2+(i%2)*cell.x,(area.size.y-rows*cell.y)/2+row*cell.y)
			var square: Control=view.get_node("Square")
			square.custom_minimum_size=Vector2(side,side)
			view.size=Vector2(side+16,cell.y-12)
			square.size_flags_horizontal=Control.SIZE_SHRINK_CENTER

func _view(id: String) -> Control:
	for key in ["AllyFormation","EnemyFormation"]:
		var view: Control=field(key).get_node_or_null(NodePath(id))
		if view!=null:return view
	return null
func _new_tween() -> Tween:
	var tween: Tween=create_tween();tween.set_speed_scale(animation_speed);active_tweens.append(tween);return tween
func _wait_tween(tween: Tween) -> void:
	while tween!=null and tween.is_valid() and tween.is_running() and not skip_presentation:
		tween.set_speed_scale(animation_speed)
		await get_tree().process_frame
func _float_text(id: String,text: String,color: Color,lane: int=0) -> void:
	var view: Control=_view(id)
	if view==null:return
	var label:=Label.new();label.text=text;label.modulate=color;label.add_theme_font_size_override("font_size",42 if lane==0 else 32);label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_outline_color",Color("17232b"));label.add_theme_constant_override("outline_size",4)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.size=Vector2(480,64)
	var square: Control=view.get_node("Square")
	var y: float=square.size.y/2-32 if lane==0 else -64-(lane-1)*56
	label.position=square.global_position-global_position+Vector2(square.size.x/2-label.size.x/2,y)
	add_child(label);floating_labels.append(label)
	var tween:=_new_tween();tween.set_parallel(true)
	tween.tween_property(label,"position:y",label.position.y-64,1.6)
	tween.tween_property(label,"modulate:a",0.0,.55).set_delay(1.05)
	tween.chain().tween_callback(label.queue_free)
func _highlight_actor(id: String) -> void:
	active_actor=id
	_select(selected)
func _indicate_actor(id: String) -> void:
	_highlight_actor(id)
	_float_text(id,"行动中",Color("a8dfc1"),2)
func _shift_queue(events: Array,index: int,waiting: Variant) -> void:
	var frame: Dictionary=events[index].after
	var entries: Array=units.duplicate(true)
	for unit in entries:
		if frame.has(unit.id):unit.hp=frame[unit.id].hp
	var remaining: Array=[]
	for next_index in range(index+1,events.size()):
		var id: String=events[next_index].actor
		if frame.get(id,{}).get("hp",0)>0 and id not in remaining:remaining.append(id)
	var next_round: Array=[]
	for id in round_order if waiting==null else waiting:
		if frame.get(id,{}).get("hp",0)>0 and id not in remaining:
			remaining.append(id);next_round.append(id)
	turn_queue=remaining
	_highlight_actor("")
	field("TurnOrder").set_speed(animation_speed)
	var tween: Tween=field("TurnOrder").set_queue(entries,turn_queue,next_round,true)
	await _wait_tween(tween)
func _animate_attack(actor: String,event: Dictionary) -> void:
	var view: Control=_view(actor)
	if view==null:return
	var origin: Vector2=view.position
	var direction: float=1.0 if view.get_meta("unit").side=="ally" else -1.0
	var distance: float=75
	for target in event.after:
		if target==actor or event.after[target].hp>=event.before[target].hp:continue
		var other: Control=_view(target)
		if other!=null:distance=minf(distance,maxf(0,absf(other.global_position.x-view.global_position.x)-view.size.x-24)*.4)
	var tween:=_new_tween()
	tween.tween_interval(.08)
	tween.tween_property(view,"position",origin+Vector2(direction*distance,0),.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await _wait_tween(tween)
func _apply_event(event: Dictionary) -> void:
	for id in event.after:
		var view: Control=_view(id)
		if view==null:continue
		var old: Dictionary=event.before[id]
		var current: Dictionary=event.after[id]
		var delta: int=int(current.hp)-int(old.hp)
		var square: Control=view.get_node("Square")
		if delta!=0:
			var crit: bool=delta<0 and event.get("critical",false) and id!=event.actor
			_float_text(id,("+" if delta>0 else "-")+str(absi(delta))+(" 暴击" if crit else ""),Color("a1e2a6") if delta>0 else Color(LOG_FORMAT.COLORS.critical) if crit else Color("ff6868"))
			var flash:=_new_tween()
			flash.tween_property(square,"modulate",Color("8ee394") if delta>0 else Color("f18c8c"),.08)
			flash.tween_property(square,"modulate",Color.WHITE,.16)
		if event.kind=="attack" and id!=event.actor and delta<0:
			var origin: Vector2=actor_origins.get(id,view.position)
			var nudge:=_new_tween()
			nudge.tween_property(view,"position",origin+Vector2(-8 if view.get_meta("unit").side=="ally" else 8,0),.08)
			nudge.tween_property(view,"position",origin,.16)
		for stat in ["hp","mp"]:
			if not current.has(stat):continue
			var bar: ProgressBar=view.get_node_or_null(NodePath(stat))
			if bar==null:continue
			var tween:=_new_tween();tween.tween_property(bar,"value",maxf(0,current[stat]),.3)
		var statuses: HBoxContainer=view.get_node("StatusContainer")
		for child in statuses.get_children():statuses.remove_child(child);child.queue_free()
		var effect_names: Array=[]
		for status in current.statuses:
			var title: String=LOG_FORMAT.status_name(status,data.spell_growth.statuses)
			effect_names.append(_status_text(status,current.statuses[status]))
			if not old.statuses.has(status) or current.statuses[status].turns>old.statuses[status].turns:
				_float_text(id,title,Color("c1d9df"),0 if id==event.actor else 1)
		if current.get("defending",false):effect_names.append("防御")
		for i in range(mini(3,effect_names.size())):
			var badge:=Button.new();badge.text=str(effect_names[i]).split(" · ")[0] if i<2 else "+%d" % (effect_names.size()-2)
			badge.tooltip_text="\n".join(effect_names);badge.add_theme_font_size_override("font_size",16);statuses.add_child(badge)
		if old.statuses!=current.statuses:
			statuses.modulate.a=0.4
			var fade:=_new_tween();fade.tween_property(statuses,"modulate:a",1.0,.16)
	var pause:=_new_tween();pause.tween_interval(1.0);await _wait_tween(pause)
func play_events(events: Array,waiting: Variant=null) -> void:
	playing=true;skip_presentation=false;actor_origins.clear()
	field("TurnOrder").set_caption("行动中")
	if waiting!=null:
		field("Begin").hide()
		field("ActionTitle").text="行动结算中"
		field("TurnOrder").set_queue(units,events.map(func(event):return event.actor),[],false)
	field("Skip").show()
	last_frame=events.back().after if not events.is_empty() else {}
	for u in units:
		var view: Control=_view(u.id)
		if view!=null:actor_origins[u.id]=view.position
	for button in field("BasicActions").get_children():button.disabled=true
	for i in range(6):field("Skill"+str(i)).disabled=true
	await _wait_tween(field("TurnOrder").layout_tween)
	for event_index in range(events.size()):
		var event: Dictionary=events[event_index]
		if skip_presentation:break
		if event.has("turn"):field("Round").text="第 %d 回合" % event.turn
		_indicate_actor(event.actor)
		if event.kind=="attack":await _animate_attack(event.actor,event)
		elif event.kind=="spell" or event.kind=="item" or event.kind=="special":_float_text(event.actor,event.label,Color("d3e5eb"),1)
		if skip_presentation:break
		await _apply_event(event)
		var actor_view: Control=_view(event.actor)
		if actor_view!=null and actor_origins.has(event.actor):
			var tween:=_new_tween();tween.tween_property(actor_view,"position",actor_origins[event.actor],.2)
			await _wait_tween(tween)
		for id in event.after:
			if event.after[id].hp<=0 and _view(id)!=null:_view(id).modulate=Color(1,1,1,.35)
		if not skip_presentation and (waiting==null or event_index+1<events.size()):
			await _shift_queue(events,event_index,waiting)
	_cleanup_presentation()
	playing=false
	field("Skip").hide()
	presentation_finished.emit()
func skip_animations() -> void:
	skip_presentation=true
	field("TurnOrder").snap_latest()
	for tween in active_tweens:
		if tween.is_valid():tween.kill()
func _cleanup_presentation() -> void:
	skip_animations()
	for id in actor_origins:
		var view: Control=_view(id)
		if view!=null:
			view.position=actor_origins[id]
			view.get_node("Square").modulate=Color.WHITE
			view.get_node("StatusContainer").modulate=Color.WHITE
	for label in floating_labels:
		if is_instance_valid(label):label.queue_free()
	floating_labels.clear();active_tweens.clear();active_actor=""
	for id in last_frame:
		var view: Control=_view(id)
		if view==null:continue
		for stat in ["hp","mp"]:
			var bar: ProgressBar=view.get_node_or_null(NodePath(stat))
			if bar!=null and last_frame[id].has(stat):bar.value=maxf(0,last_frame[id][stat])
	_select(selected)
func _exit_tree() -> void:
	skip_animations()
