extends Button
var unit_id := ""
var next_round := false
func configure(unit: Dictionary,is_next_round: bool,is_current: bool) -> void:
	unit_id=unit.id;next_round=is_next_round
	text=str(unit.name).left(2)
	tooltip_text=str(unit.name)+(" · 下轮" if next_round else " · 本轮")
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("7196a2") if unit.side=="ally" else Color("947984")
	style.set_corner_radius_all(6)
	style.set_border_width_all(2 if is_current else 0)
	style.border_color=Color("edcf82")
	for key in ["normal","hover","pressed","focus"]:add_theme_stylebox_override(key,style)
	get_node("NextRound").visible=next_round
