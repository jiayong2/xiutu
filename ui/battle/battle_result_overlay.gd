extends Control
const LOG_FORMAT=preload("res://ui/battle/battle_log_formatter.gd")
signal confirm_requested(id: String)
var report: Dictionary
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	var theme_style:=Theme.new()
	theme_style.default_font_size=20
	var panel:=StyleBoxFlat.new();panel.bg_color=Color("304955");panel.border_color=Color("78939f");panel.set_border_width_all(1);panel.set_corner_radius_all(8)
	theme_style.set_stylebox("panel","PanelContainer",panel)
	var inner:=panel.duplicate()
	inner.bg_color=Color("2b424d")
	inner.content_margin_left=12;inner.content_margin_right=12;inner.content_margin_top=12;inner.content_margin_bottom=12
	field("GrowthPanel").add_theme_stylebox_override("panel",inner)
	field("LootPanel").add_theme_stylebox_override("panel",inner)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var button:=StyleBoxFlat.new();button.bg_color=Color("52717f") if state!="disabled" else Color("3d5059");button.set_corner_radius_all(6)
		theme_style.set_stylebox(state,"Button",button)
	theme=theme_style
	var confirm:=StyleBoxFlat.new();confirm.bg_color=Color("719b85");confirm.set_corner_radius_all(6)
	field("ConfirmButton").add_theme_stylebox_override("normal",confirm)
	resized.connect(_fit);_fit()
	field("ConfirmButton").pressed.connect(func():
		if field("ConfirmButton").disabled:return
		field("ConfirmButton").disabled=true
		confirm_requested.emit(report.id))
	field("DetailButton").pressed.connect(func():
		field("Details").visible=not field("Details").visible
		field("Content").visible=not field("Details").visible
		field("DetailButton").text="返回" if field("Details").visible else "战斗详情")
func _fit() -> void:
	var panel: Control=field("ResultPanel")
	var factor: float=minf(1.5,minf((size.x-32)/960.0,(size.y-32)/620.0))
	panel.scale=Vector2.ONE*maxf(0.1,factor)
	panel.position=(size-Vector2(960,620)*panel.scale)/2
func bind_data(value: Dictionary,data: Dictionary) -> void:
	report=value.duplicate(true)
	field("ResultTitle").text={"win":"战斗胜利","lose":"战斗失败","escape":"脱离战斗"}[report.result]
	field("ResultTitle").modulate=Color("c5e5c9") if report.result=="win" else Color("d7a3a5")
	var places: Dictionary=preload("res://ui/world/world_page.gd").PLACES
	field("Summary").text="%s · %s · 共 %d 回合" % [places[report.location],data.monsters[report.monster].name,report.turns]
	for key in ["GrowthList","LootGrid"]:
		for child in field(key).get_children():field(key).remove_child(child);child.queue_free()
	var members: Array=report.growth
	for member in members:
		var row:=VBoxContainer.new();row.add_theme_constant_override("separation",8);field("GrowthList").add_child(row)
		var header:=HBoxContainer.new();row.add_child(header)
		var avatar:=ColorRect.new();avatar.custom_minimum_size=Vector2(48,48);avatar.color=Color("7a9ba7");header.add_child(avatar)
		var name_label:=Label.new();name_label.text=member.name;name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(name_label)
		var gain:=Label.new();gain.text="+%d %s" % [member.gain,member.type];gain.modulate=Color("b5dcb9");header.add_child(gain)
		if members.size()==1:
			var realm:=Label.new()
			realm.text=preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(member.realm,"qi",GameManager.catalog.tables)
			row.add_child(realm)
		if member.target>0:
			var bar:=ProgressBar.new();bar.custom_minimum_size.y=14;bar.show_percentage=false;bar.max_value=member.target;bar.value=member.current
			var fill:=StyleBoxFlat.new();fill.bg_color=Color("86b193");bar.add_theme_stylebox_override("fill",fill);row.add_child(bar)
			var progress:=Label.new();progress.text="%d / %d" % [member.current,member.target];if members.size()==1:row.add_child(progress)
			else:progress.queue_free()
			if members.size()==1 and member.type=="修为":
				var hint:=Label.new();hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
				hint.text="修为已满，可在安全地点手动晋升。" if member.current>=member.target and member.realm<9 else "修为已满，筑基仍需满足原有条件。" if member.current>=member.target else "当前战斗不奖励修为，修炼请前往安全地点。"
				row.add_child(hint)
	field("Money").text=("获得灵石：+%d" if report.money>=0 else "损失灵石：%d") % absi(int(report.money))
	field("Loss").text="战败后 HP %d · MP %d\n返回：%s" % [report.hp,report.mp,places[report.return_location]] if report.result=="lose" else ""
	for id in report.drops:
		var item: Dictionary=data.items[id]
		var card:=VBoxContainer.new();card.custom_minimum_size=Vector2(112,130)
		field("LootGrid").add_child(card)
		var icon:=ColorRect.new();icon.custom_minimum_size=Vector2(52,52);icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;icon.color={"common":Color("7a9ba7"),"rare":Color("839d88"),"epic":Color("95819e")}.get(item.rarity,Color("7a9ba7"));card.add_child(icon)
		var label:=Label.new();label.text=item.name;label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_size_override("font_size",18);card.add_child(label)
		var quantity:=Label.new();quantity.text="×%d" % report.drops[id];quantity.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;card.add_child(quantity)
		card.tooltip_text="%s\n%s · %s\n%s" % [item.name,item.type,item.rarity,item.description]
	field("Empty").visible=report.drops.is_empty()
	field("Details").bbcode_enabled=true
	field("Details").text=LOG_FORMAT.colored("共 %d 回合" % report.turns,"system")+"\n\n"+LOG_FORMAT.render(report.background.battle.get("log_entries",[]),report.log)
	field("DetailButton").disabled=report.log.is_empty() and report.background.battle.get("log_entries",[]).is_empty()
	_fit()
