@tool
extends Control
## No polygon is drawn until six real values are supplied.
@export var attribute_names: PackedStringArray=["根骨","灵性","悟性","气运","魅力","心性"]
var values: Array=[]
func _ready() -> void:resized.connect(queue_redraw)
func set_values(actual: Array) -> void:
	values=actual.duplicate();queue_redraw()
func _draw() -> void:
	var center:=size*0.5
	var radius:=minf(size.x*0.32,size.y*0.36)
	var axes:=PackedVector2Array()
	for i in range(6):axes.append(Vector2.from_angle(-PI/2+i*TAU/6))
	for ring in range(1,4):
		var points:=PackedVector2Array()
		for axis in axes:points.append(center+axis*radius*ring/3.0)
		points.append(points[0]);draw_polyline(points,Color("71868c"),1.0,true)
	for i in range(6):
		draw_line(center,center+axes[i]*radius,Color("71868c"))
		var pos: Vector2=center+axes[i]*(radius+24)
		var width: float=get_theme_default_font().get_string_size(attribute_names[i],HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		draw_string(get_theme_default_font(),pos-Vector2(width/2,-6),attribute_names[i],HORIZONTAL_ALIGNMENT_LEFT,-1,20)
	if values.size()==6:
		var polygon:=PackedVector2Array()
		for i in range(6):polygon.append(center+axes[i]*radius*clampf(float(values[i])/100.0,0,1))
		draw_colored_polygon(polygon,Color(0.85,0.73,0.4,0.22))
		polygon.append(polygon[0]);draw_polyline(polygon,Color("d8bb66"),2.0,true)
	else:
		draw_string(get_theme_default_font(),center+Vector2(-60,6),"暂无六维数据",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("bac9ce"))
