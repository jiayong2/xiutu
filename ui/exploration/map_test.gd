extends PanelContainer

signal closed
signal movement_finished
signal encounter_started

const MapData = preload("res://core/exploration/map_data.gd")
const Symbols = preload("res://addons/exploration_map/legend.gd")
const Exploration = preload("res://gameplay/exploration_run.gd")
const VISION_RADIUS := 240.0
const WALK_SPEED := 270.0

var map_path := ""
var map := {}
var nodes := {}
var neighbors := {}
var portals: Array[String] = []
var portal_links := {}
var current := ""
var fit_bounds := Rect2()
var player_position := Vector2.ZERO
var movement: Tween
var marker_parts: Array[StyleBoxFlat] = []
var revealed_centers := {}
var revealed_segments := {}
var runtime_state: Callable
var runtime_request: Callable
var save_game: Callable
var run := {}
var auto_route: Array = []

func _ready() -> void:
	%Back.pressed.connect(func() -> void: closed.emit())
	%NoEncounters.visible = OS.is_debug_build()
	%Interact.pressed.connect(_interact)
	%SaveRun.visible = save_game.is_valid()
	%SaveRun.pressed.connect(func() -> void: %Status.text = save_game.call())
	%Reveal.toggled.connect(_set_fog_hidden)
	%Canvas.draw.connect(_draw_map)
	%Canvas.resized.connect(_resize_canvas)
	%Canvas.gui_input.connect(_canvas_input)
	%MaskDrawing.draw.connect(_draw_visibility_mask)
	%PlayerMarker.draw.connect(_draw_marker)
	%FogMask.world_2d = World2D.new()
	var material: ShaderMaterial = %Fog.material
	material.set_shader_parameter("explored_mask", %FogMask.get_texture())
	for multiplier in [0.5, 1.0, 2.0, 4.0]:
		%MoveSpeed.add_item("×%s" % str(multiplier))
		%MoveSpeed.set_item_metadata(%MoveSpeed.item_count - 1, multiplier)
	%MoveSpeed.select(1)
	%MoveSpeed.item_selected.connect(_update_move_speed)
	for part in [[Color("#d6e2d6"), 2], [Color("#eed8b7"), 5], [Color("#72ada3"), 3]]:
		var style := StyleBoxFlat.new()
		style.bg_color = part[0]
		style.set_corner_radius_all(part[1])
		marker_parts.append(style)
	var result: Dictionary = {"map": runtime_state.call().map} if runtime_state.is_valid() else MapData.read(map_path)
	if result.has("error"):
		%Status.text = "无法打开探索地图。%s" % result.error
		return
	_load_map(result.map)
	if runtime_state.is_valid():
		resume_run()

func _load_map(definition: Dictionary) -> void:
	map = definition
	%Fog.material.set_shader_parameter("fog_color", Color(map.background_color))
	neighbors = Exploration.index(map)
	portal_links = Exploration.portal_links(map)
	portals.assign(portal_links.keys())
	for node in map.nodes:
		nodes[node.node_id] = node
		var rect := MapData.bounds(node, map.cell_style)
		fit_bounds = rect if nodes.size() == 1 else fit_bounds.merge(rect)
	var entry := Exploration.entry(map)
	%Title.text = "%s · 地图测试" % map.map_name
	if entry.is_empty():
		%Status.text = "请在地图编辑器设置入口，或放置唯一的入口图例后保存。"
		return
	_arrive(entry)
	_resize_canvas()
	%Status.text = "从入口出发，点击有路线相连的相邻格。"

func _arrive(id: String) -> void:
	current = id
	var center := _center(id)
	revealed_centers[id] = center
	_set_player_position(center)

func _step(id: String) -> bool:
	if movement != null:
		return false
	if current.is_empty() or not neighbors[current].has(id):
		%Status.text = "只能移动到有路线相连的相邻格。"
		return false
	var destination := _center(id)
	var duration := maxf(0.15, player_position.distance_to(destination) / WALK_SPEED)
	%Status.text = "移动中…"
	movement = create_tween()
	movement.set_speed_scale(%MoveSpeed.get_selected_metadata())
	movement.tween_method(_set_player_position, player_position, destination, duration)
	movement.tween_callback(_finish_step.bind(id))
	return true

func _finish_step(id: String) -> void:
	if runtime_request.is_valid():
		_finish_runtime_step(id)
		return
	var first := current if current < id else id
	var last := id if current < id else current
	revealed_segments[first + "/" + last] = PackedVector2Array([_center(first), _center(last)])
	movement = null
	_arrive(id)
	var symbol: String = nodes[id].get("icon_id", "")
	if portal_links.has(id):
		_arrive(portal_links[id])
		%Status.text = "已传送到另一座法阵。"
	elif symbol == "S08":
		%Status.text = "已到达出口。可点击「返回外围」。"
	else:
		%Status.text = "已到达 · %s" % (Symbols.title(symbol) if not symbol.is_empty() else "空格")
	movement_finished.emit()
	_continue_route()

func resume_run() -> void:
	run = runtime_state.call()
	if run.is_empty():
		return
	revealed_centers.clear()
	revealed_segments.clear()
	for id in run.revealed:
		revealed_centers[id] = _center(id)
	for pair in run.paths:
		revealed_segments[pair[0] + "/" + pair[1]] = PackedVector2Array([_center(pair[0]), _center(pair[1])])
	_arrive(run.current)
	%Canvas.queue_redraw()
	_update_interaction()

func _finish_runtime_step(id: String) -> void:
	movement = null
	var result: Dictionary = runtime_request.call("exploration_step", {
		"node_id": id, "skip_encounters": %NoEncounters.button_pressed})
	resume_run()
	%Status.text = result.message
	if not result.success:
		auto_route.clear()
	elif result.exploration.encounter:
		auto_route.clear()
		encounter_started.emit()
	elif run.current == id:
		var symbol: String = nodes[id].get("icon_id", "")
		%Status.text = "已到达 · %s" % (Symbols.title(symbol) if not symbol.is_empty() else "空格")
		if symbol in ["M01", "M02", "M03", "O01", "O02", "O03", "O04", "O07", "O08"] and not run.assigned.has(id):
			%Status.text += " · 此格尚未绑定配置"
	movement_finished.emit()
	_continue_route()

func _update_interaction() -> void:
	var definition: Dictionary = run.get("assigned", {}).get(current, {})
	var labels := {"reward": "领取奖励", "herb": "采集灵草", "ore": "采矿", "spring": "饮用泉水"}
	var behavior := Exploration.Config.behavior(definition)
	%Interact.visible = labels.has(behavior)
	%Interact.text = "已领取" if run.get("claimed", {}).has(current) else labels.get(behavior, "")
	%Interact.disabled = run.get("claimed", {}).has(current) or movement != null

func _interact() -> void:
	if movement != null or not runtime_request.is_valid():
		return
	var result: Dictionary = runtime_request.call("exploration_interact", {"node_id": current})
	resume_run()
	%Status.text = result.message

func _route_to(target: String) -> Array:
	return Exploration.shortest_route(neighbors, portal_links, current, target)

func _travel_to(target: String) -> bool:
	if movement != null or target == current:
		return false
	auto_route = _route_to(target)
	if auto_route.is_empty():
		%Status.text = "没有通往该格的路线。"
		return false
	_continue_route()
	return true

func _continue_route() -> void:
	if movement == null and not auto_route.is_empty() and not _step(auto_route.pop_front()):
		auto_route.clear()

func _update_move_speed(index: int) -> void:
	if movement != null:
		movement.set_speed_scale(%MoveSpeed.get_item_metadata(index))

func _set_player_position(value: Vector2) -> void:
	player_position = value
	%Canvas.queue_redraw()
	%PlayerMarker.queue_redraw()
	_refresh_mask()

func _center(id: String) -> Vector2:
	var position: Array = nodes[id].position
	return Vector2(position[0], position[1])

func _is_visible(id: String) -> bool:
	return _is_point_visible(_center(id))

func _is_point_visible(point: Vector2) -> bool:
	var radius_squared := VISION_RADIUS * VISION_RADIUS
	if point.distance_squared_to(player_position) <= radius_squared:
		return true
	for center in revealed_centers.values():
		if point.distance_squared_to(center) <= radius_squared:
			return true
	for segment in revealed_segments.values():
		if _distance_to_path_squared(point, segment[0], segment[1]) <= radius_squared:
			return true
	return movement != null and _distance_to_path_squared(point, _center(current), player_position) <= radius_squared

func _distance_to_path_squared(point: Vector2, start: Vector2, end: Vector2) -> float:
	return point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, start, end))

func _resize_canvas() -> void:
	%FogMask.size = Vector2i(%Canvas.size).max(Vector2i(2, 2))
	%Canvas.queue_redraw()
	%PlayerMarker.queue_redraw()
	_refresh_mask()

func _set_fog_hidden(active: bool) -> void:
	%Fog.visible = not active
	_refresh_mask()

func _refresh_mask() -> void:
	if not current.is_empty() and not %Reveal.button_pressed:
		%MaskDrawing.queue_redraw()
		%FogMask.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_visibility_mask() -> void:
	var drawing: Node2D = %MaskDrawing
	drawing.draw_rect(Rect2(Vector2.ZERO, Vector2(%FogMask.size)), Color.BLACK)
	if current.is_empty():
		return
	var zoom := _scale()
	var radius := VISION_RADIUS * zoom
	for center in revealed_centers.values():
		drawing.draw_circle(_to_screen(center, zoom), radius, Color.WHITE, true, -1.0, true)
	for segment in revealed_segments.values():
		drawing.draw_line(_to_screen(segment[0], zoom), _to_screen(segment[1], zoom),
			Color.WHITE, radius * 2.0, true)
	if movement != null:
		drawing.draw_line(_to_screen(_center(current), zoom), _to_screen(player_position, zoom),
			Color.WHITE, radius * 2.0, true)
		drawing.draw_circle(_to_screen(player_position, zoom), radius, Color.WHITE, true, -1.0, true)

func _scale() -> float:
	var available: Vector2 = %Canvas.size - Vector2(32, 32)
	return maxf(0.01, minf(available.x / fit_bounds.size.x, available.y / fit_bounds.size.y))

func _screen_rect(id: String, zoom: float) -> Rect2:
	var rect := MapData.bounds(nodes[id], map.cell_style)
	return Rect2(_to_screen(rect.position, zoom), rect.size * zoom)

func _to_screen(point: Vector2, zoom: float) -> Vector2:
	return %Canvas.size / 2.0 + (point - player_position) * zoom

func _canvas_input(event: InputEvent) -> void:
	if current.is_empty() or not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var zoom := _scale()
	var point: Vector2 = player_position + (event.position - %Canvas.size / 2.0) / zoom
	if not %Reveal.button_pressed and not _is_point_visible(point):
		return
	for id in nodes:
		if _screen_rect(id, zoom).has_point(event.position):
			_travel_to(id)
			%Canvas.accept_event()
			return

func _draw_map() -> void:
	var canvas: Control = %Canvas
	if map.is_empty():
		return
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(map.background_color))
	if current.is_empty():
		return
	var zoom := _scale()
	var screen := Rect2(Vector2.ZERO, canvas.size)
	var line_width := maxf(1.0, map.line_style.width * zoom)
	for edge in map.edges:
		var a: String = edge.from_node_id
		var b: String = edge.to_node_id
		var start := _screen_rect(a, zoom).get_center()
		var end := _screen_rect(b, zoom).get_center()
		if screen.intersects(Rect2(start, end - start).abs().grow(line_width)):
			canvas.draw_line(start, end, Color(map.line_style.color), line_width, true)
	for id in nodes:
		var rect := _screen_rect(id, zoom)
		if not screen.intersects(rect):
			continue
		canvas.draw_rect(rect, Color(map.cell_style.fill))
		canvas.draw_rect(rect, Color(map.cell_style.border), false, maxf(1.0, map.cell_style.stroke * zoom))
		var completed: bool = run.get("cleared", {}).has(id) or run.get("claimed", {}).has(id)
		var hide_icon: bool = completed and run.assigned[id].get("completion_behavior") == "hide"
		if not hide_icon:
			Symbols.paint(canvas, nodes[id].get("icon_id", ""), rect)

func _draw_marker() -> void:
	if current.is_empty():
		return
	var canvas: Control = %PlayerMarker
	var zoom := _scale()
	var cell := _screen_rect(current, zoom)
	var scale_factor := minf(cell.size.x, cell.size.y) / 118.0
	_draw_player(canvas, _to_screen(player_position, zoom), scale_factor)

func _draw_player(canvas: Control, position: Vector2, scale_factor: float) -> void:
	canvas.draw_set_transform(position, 0.0, Vector2.ONE * scale_factor)
	canvas.draw_style_box(marker_parts[0], Rect2(-6, -33, 12, 10))
	canvas.draw_style_box(marker_parts[1], Rect2(-10, -22, 20, 19))
	var robe := PackedVector2Array([Vector2(-11, -3), Vector2(11, -3), Vector2(17, 33), Vector2(-17, 33)])
	canvas.draw_colored_polygon(robe, Color("#72ada3"))
	robe.append(robe[0])
	canvas.draw_polyline(robe, Color("#bce8dd"), 1.8, true)
	canvas.draw_style_box(marker_parts[2], Rect2(-25, 0, 12, 26))
	canvas.draw_style_box(marker_parts[2], Rect2(13, 0, 12, 26))
	canvas.draw_rect(Rect2(-12, 22, 24, 3), Color("#edd98e"))
	canvas.draw_set_transform(Vector2.ZERO)
