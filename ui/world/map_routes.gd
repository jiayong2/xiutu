@tool
extends Control
## Visual connections only; movement rules remain in OperationService.
func _ready() -> void:
	resized.connect(queue_redraw)
func _draw() -> void:
	var ids:=["town_qinglan","cave_qinglan","area_qinglan_outskirts","town_yunxi"]
	for i in range(ids.size()-1):
		_route(ids[i],ids[i+1])
	_route("area_qinglan_outskirts","sect_qingyue_gate")

func _route(from: String,to: String) -> void:
	var a:=get_node_or_null("../"+from) as Control
	var b:=get_node_or_null("../"+to) as Control
	if a!=null and b!=null:
		draw_dashed_line(a.position+a.size/2,b.position+b.size/2,Color("c5d9dd"),4,14)
