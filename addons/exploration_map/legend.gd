@tool
extends RefCounted

const Metadata = preload("res://core/exploration/symbols.gd")
const GROUPS := Metadata.GROUPS
const ICONS := Metadata.ICONS
const LIGHT := Color("#ffe0ab")
const INK := Color("#152e33")

static func title(id: String) -> String:
	return Metadata.title(id)

static func paint(canvas: CanvasItem, id: String, rect: Rect2) -> void:
	if not ICONS.has(id):
		return
	var scale_factor := minf(rect.size.x, rect.size.y) / 116.0
	if scale_factor <= 0.0:
		return
	canvas.draw_set_transform(rect.get_center(), 0.0, Vector2.ONE * scale_factor)
	var color := Color(ICONS[id][1])
	match ICONS[id][2]:
		"beast": _beast(canvas, id, color)
		"person": _person(canvas, id, color)
		"chest": _chest(canvas, id, color)
		"herb": _herb(canvas, color)
		"ore": _ore(canvas, color)
		"furnace": _furnace(canvas, color)
		"spring": _spring(canvas, color)
		"relic", "disc": _emblem(canvas, id, color)
		"gate": _gate(canvas, id, color)
		"trap": _trap(canvas, color)
		"question": _question(canvas, color)
		"star": _star(canvas, color)
	canvas.draw_set_transform(Vector2.ZERO)

static func _polygon(c: CanvasItem, points: PackedVector2Array, fill: Color, stroke: Color, width := 3.5) -> void:
	c.draw_colored_polygon(points, fill)
	points.append(points[0])
	c.draw_polyline(points, stroke, width, true)

static func _ring(c: CanvasItem, radius: float, color: Color, dashed := false) -> void:
	if dashed:
		for index in 12:
			var start := TAU * index / 12.0
			c.draw_arc(Vector2.ZERO, radius, start, start + 0.34, 6, color, 3.5, true)
	else:
		c.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, 3.5, true)

static func _beast(c: CanvasItem, id: String, color: Color) -> void:
	if id in ["M02", "M03"]:
		_ring(c, 50, color, true)
	if id == "M03":
		_ring(c, 44, color.darkened(0.35))
	_polygon(c, [Vector2(-34,-15), Vector2(-28,-44), Vector2(-10,-21),
		Vector2(10,-21), Vector2(28,-44), Vector2(34,-15), Vector2(25,23),
		Vector2(0,40), Vector2(-25,23)], Color("#66363e"), color)
	for x in [-14, 14]:
		c.draw_circle(Vector2(x, 1), 4.5, LIGHT, true, -1, true)
	if id == "M03":
		c.draw_circle(Vector2(0, 11), 8, Color("#ff684e"), true, -1, true)
		c.draw_circle(Vector2(0, 11), 4, LIGHT)
	elif id == "M04":
		_polygon(c, [Vector2(-11,-22), Vector2(0,-36), Vector2(11,-22), Vector2(0,-11)], LIGHT, color, 2.0)

static func _person(c: CanvasItem, id: String, color: Color) -> void:
	if id == "N02":
		_ring(c, 49, color)
	c.draw_circle(Vector2(0, -25), 15, Color("#325859"), true, -1, true)
	c.draw_circle(Vector2(0, -25), 15, color, false, 3.5, true)
	_polygon(c, [Vector2(-15,-3), Vector2(15,-3), Vector2(33,40), Vector2(-33,40)],
		Color("#295052"), color)
	c.draw_line(Vector2(0, 2), Vector2(0, 32), color, 3.0, true)
	if id == "N03":
		c.draw_circle(Vector2(34,-21), 10, color, true, -1, true)
		c.draw_rect(Rect2(31,-24,6,6), Color("#795521"))
	elif id == "N04":
		c.draw_line(Vector2(-9,-29), Vector2(-3,-24), color, 3.0, true)
		c.draw_line(Vector2(9,-29), Vector2(3,-24), color, 3.0, true)

static func _chest(c: CanvasItem, id: String, color: Color) -> void:
	if id == "O02":
		_ring(c, 45, color, true)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#684d2b")
	style.border_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(4)
	c.draw_style_box(style, Rect2(-39,-24,78,50))
	c.draw_line(Vector2(-37,-5), Vector2(37,-5), color, 4.0)
	c.draw_line(Vector2(0,-22), Vector2(0,24), color, 4.0)
	c.draw_rect(Rect2(-7,-9,14,18), color)
	if id == "O02":
		c.draw_circle(Vector2.ZERO, 2.5, LIGHT)

static func _herb(c: CanvasItem, color: Color) -> void:
	var leaf := Color("#367c5c")
	_polygon(c, [Vector2(0,13), Vector2(-20,15), Vector2(-33,8), Vector2(-38,-16),
		Vector2(-22,-14), Vector2(-10,-7)], leaf, color, 2.5)
	_polygon(c, [Vector2(0,-4), Vector2(10,-24), Vector2(22,-32), Vector2(37,-36),
		Vector2(35,-18), Vector2(24,-8), Vector2(11,-4)], leaf, color, 2.5)
	c.draw_line(Vector2(0,-43), Vector2(0,39), color, 4.0, true)

static func _ore(c: CanvasItem, color: Color) -> void:
	_polygon(c, [Vector2(-48,30), Vector2(-37,-7), Vector2(-19,-28), Vector2(-4,-4),
		Vector2(17,-46), Vector2(41,-7), Vector2(49,30)], Color("#405d64"), color)
	c.draw_polyline([Vector2(-37,-7), Vector2(-19,3), Vector2(-4,-4)], color, 2.0, true)
	for segment in [[Vector2(-19,-28), Vector2(-19,30)], [Vector2(17,-46), Vector2(17,30)]]:
		c.draw_line(segment[0], segment[1], color, 2.0, true)

static func _furnace(c: CanvasItem, color: Color) -> void:
	var lid := PackedVector2Array()
	for index in 17:
		var x := lerpf(-41, 41, index / 16.0)
		lid.append(Vector2(x, -11 - 14 * (1.0 - pow(x / 41.0, 2))))
	_polygon(c, lid, Color("#96583f"), color)
	_polygon(c, [Vector2(-36,-11), Vector2(36,-11), Vector2(24,37), Vector2(-24,37)],
		Color("#704a3c"), color)
	c.draw_circle(Vector2(0,13), 12, LIGHT, true, -1, true)

static func _spring(c: CanvasItem, color: Color) -> void:
	var pool := PackedVector2Array()
	for index in 48:
		pool.append(Vector2.from_angle(TAU * index / 48.0) * Vector2(45, 19) + Vector2(0,23))
	_polygon(c, pool, Color("#21626c"), color)
	_polygon(c, [Vector2(0,-42), Vector2(10,-27), Vector2(15,-12), Vector2(13,0),
		Vector2(7,8), Vector2(0,11), Vector2(-7,8), Vector2(-13,0), Vector2(-15,-12),
		Vector2(-10,-27)], color, color, 2.0)

static func _emblem(c: CanvasItem, id: String, color: Color) -> void:
	if id == "O08":
		_polygon(c, [Vector2(0,-44), Vector2(41,0), Vector2(0,44), Vector2(-41,0)],
			Color("#655936"), color)
		_ring(c, 19, color)
		c.draw_circle(Vector2.ZERO, 7, LIGHT)
	else:
		_ring(c, 47, color, true)
		_ring(c, 32, color)
		_polygon(c, [Vector2(0,-30), Vector2(19,0), Vector2(0,30), Vector2(-19,0)],
			color.darkened(0.18), color, 2.0)

static func _gate(c: CanvasItem, id: String, color: Color) -> void:
	for width in [36.0, 20.0]:
		var base := Vector2(0, -6)
		var arch := PackedVector2Array([Vector2(-width, 42)])
		for index in 25:
			arch.append(base + Vector2.from_angle(PI + PI * index / 24.0) * width)
		arch.append(Vector2(width, 42))
		_polygon(c, arch, INK if width < 30.0 else Color("#234442"), color, 4.0 if width > 30.0 else 2.5)
	if id != "S02":
		var direction := 1.0 if id == "S07" else -1.0
		var tip := Vector2(0, 13 + 15 * direction)
		c.draw_line(Vector2(0, 13 - 15 * direction), tip, color, 4.0, true)
		c.draw_polyline([tip + Vector2(-10, -10 * direction), tip,
			tip + Vector2(10, -10 * direction)], color, 4.0, true)

static func _trap(c: CanvasItem, color: Color) -> void:
	_ring(c, 44, color)
	_polygon(c, [Vector2(0,-42), Vector2(41,28), Vector2(-41,28)], Color("#6b3339"), color)
	c.draw_line(Vector2(0,-15), Vector2(0,7), LIGHT, 4.0, true)
	c.draw_circle(Vector2(0,19), 3, LIGHT)

static func _question(c: CanvasItem, color: Color) -> void:
	_ring(c, 43, color)
	var curve := Curve2D.new()
	curve.add_point(Vector2(-15,-17), Vector2.ZERO, Vector2(0,-16))
	curve.add_point(Vector2(17,-18), Vector2(0,-14), Vector2(0,13))
	curve.add_point(Vector2(0,9), Vector2(0,-9))
	c.draw_polyline(curve.get_baked_points(), color, 7.0, true)
	c.draw_line(Vector2(0,9), Vector2(0,15), color, 7.0, true)
	c.draw_circle(Vector2(0,29), 4.5, color, true, -1, true)

static func _star(c: CanvasItem, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 8:
		var radius := 48.0 if index % 2 == 0 else 20.0
		points.append(Vector2.from_angle(PI * index / 4.0) * radius)
	_polygon(c, points, Color("#6b5630"), color)
	c.draw_circle(Vector2.ZERO, 11, LIGHT, true, -1, true)
