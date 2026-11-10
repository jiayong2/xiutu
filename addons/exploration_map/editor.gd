@tool
extends VBoxContainer

signal close_requested

const Data = preload("res://core/exploration/map_data.gd")
const Legend = preload("res://addons/exploration_map/legend.gd")
const LEGEND_SAMPLE := "res://tests/fixtures/exploration_legend_map.json"
const TOOLS := {"Select": "选择／拖动", "Place": "单格放置", "Link": "选择连线起点",
	"Erase": "点击格子或路线删除", "Box": "拖动框选", "Region": "拖动生成区域"}
const STYLE_FIELDS := {
	"Background": ["background_color"], "Fill": ["cell_style", "fill"],
	"Border": ["cell_style", "border"], "LineColor": ["line_style", "color"],
	"Width": ["cell_style", "width"], "Height": ["cell_style", "height"],
	"Radius": ["cell_style", "radius"], "Stroke": ["cell_style", "stroke"],
	"LineWidth": ["line_style", "width"], "MapId": ["map_id"], "MapName": ["map_name"],
}

var map := Data.blank()
var saved := map.duplicate(true)
var source_path := ""
var selected: Array[String] = []
var history: Array[Dictionary] = []
var future: Array[Dictionary] = []
var clipboard := {}
var mode := "Select"
var link_from := ""
var zoom := 1.0
var offset := Vector2(60, 60)
var pointer := Vector2.ZERO
var gesture_start := Vector2.ZERO
var gesture_active := false
var panning := false
var drag_snapshot := {}
var message := ""
var refreshing := false
var pending: Callable
@onready var canvas: Control = %Canvas

func _ready() -> void:
	if get_tree().edited_scene_root == self:
		return
	for key in TOOLS:
		get_node("%" + key).pressed.connect(_set_mode.bind(key))
	for key in STYLE_FIELDS:
		var field := get_node("%" + key)
		if field is SpinBox:
			field.value_changed.connect(_set_style.bind(key))
		elif field is ColorPickerButton:
			field.color_changed.connect(_set_style.bind(key))
		else:
			field.text_changed.connect(_set_style.bind(key))
	%New.pressed.connect(_discard_or.bind(_load_map.bind(Data.blank(), ""), "新建地图"))
	%Open.pressed.connect(_discard_or.bind(_open_dialog.bind(Data.DIRECTORY), "打开地图"))
	%OpenLegacy.pressed.connect(_discard_or.bind(_open_dialog.bind(Data.LEGACY_DIRECTORY), "打开旧地图"))
	%Save.pressed.connect(_save.bind(false))
	%SaveAs.pressed.connect(_save.bind(true))
	%Remove.pressed.connect(_confirm_remove)
	%Close.pressed.connect(_discard_or.bind(_close, "关闭编辑器"))
	%Check.pressed.connect(_check)
	%OpenDialog.file_selected.connect(_open)
	%Confirm.confirmed.connect(func() -> void: pending.call())
	%Copy.pressed.connect(_copy)
	%Paste.pressed.connect(_paste)
	%Undo.pressed.connect(_restore.bind(history, future))
	%Redo.pressed.connect(_restore.bind(future, history))
	%Fit.pressed.connect(_fit)
	%Inspector.pressed.connect(func() -> void: %Properties.visible = not %Properties.visible)
	%ResizeNodes.pressed.connect(_resize_selected.bind(false))
	%ResetSize.pressed.connect(_resize_selected.bind(true))
	%Entry.pressed.connect(_set_entry)
	%Generate.pressed.connect(_generate_visible)
	%LegendSample.pressed.connect(_discard_or.bind(_open_legend_sample, "打开图例示例"))
	_setup_legend()
	%Grid.button_pressed = true
	%Grid.toggled.connect(func(_active: bool) -> void: canvas.queue_redraw())
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_canvas_input)
	_refresh_fields()
	_set_mode("Select")

func _setup_legend() -> void:
	%Legend.add_item("无图例")
	%Legend.set_item_metadata(0, "")
	for group in Legend.GROUPS:
		%Legend.add_separator(group)
		for id in Legend.GROUPS[group]:
			%Legend.add_item(Legend.title(id))
			var index: int = %Legend.item_count - 1
			%Legend.set_item_metadata(index, id)
			%Legend.get_popup().set_item_tooltip(index, Legend.title(id))
	%Legend.selected = 0
	%Legend.item_selected.connect(func(_index: int) -> void:
		%LegendPreview.tooltip_text = Legend.title(_chosen_icon())
		%LegendPreview.queue_redraw())
	%LegendPreview.draw.connect(func() -> void:
		Legend.paint(%LegendPreview, _chosen_icon(), Rect2(Vector2.ZERO, %LegendPreview.size)))
	%LegendPaint.toggled.connect(_toggle_legend_paint)

func _chosen_icon() -> String:
	return %Legend.get_item_metadata(%Legend.selected)

func _toggle_legend_paint(active: bool) -> void:
	_report("点击格子放置当前图例" if active else TOOLS[mode])

func _paint_legend(node_id: String) -> void:
	var next := map.duplicate(true)
	var id := _chosen_icon()
	for node in next.nodes:
		if node.node_id == node_id:
			node.icon_id = id
			break
	_commit(next)
	_report("已设置图例 · %s" % Legend.title(id))

func _open_legend_sample() -> void:
	var result := Data.read(LEGEND_SAMPLE)
	if result.has("error"):
		_report(result.error)
		return
	_load_map(result.map, "")
	_report("图例示例 · 54 格，包含全部 24 种图例")

func is_dirty() -> bool:
	return map != saved

func _set_mode(value: String) -> void:
	mode = value
	link_from = ""
	%LegendPaint.set_pressed_no_signal(false)
	_report(TOOLS[value])

func _report(value: String) -> void:
	message = value
	_update_status()
	canvas.queue_redraw()

func _update_status() -> void:
	%Status.text = "%d%% · 坐标 (%d, %d) · 节点 %d · 路线 %d · %s%s" % [
		roundi(zoom * 100), roundi(pointer.x), roundi(pointer.y), map.nodes.size(),
		map.edges.size(), "未保存 · " if is_dirty() else "", message]
	%Undo.disabled = history.is_empty()
	%Redo.disabled = future.is_empty()

func _refresh_fields() -> void:
	refreshing = true
	for key in STYLE_FIELDS:
		var path: Array = STYLE_FIELDS[key]
		var value: Variant = map[path[0]] if path.size() == 1 else map[path[0]][path[1]]
		var field := get_node("%" + key)
		if field is SpinBox:
			field.set_value_no_signal(value)
		elif field is ColorPickerButton:
			field.color = Color(value)
		else:
			field.text = value
	refreshing = false

func _set_style(value: Variant, key: String) -> void:
	if refreshing:
		return
	var next := map.duplicate(true)
	var path: Array = STYLE_FIELDS[key]
	if value is Color:
		value = "#" + value.to_html(false)
	if path.size() == 1:
		next[path[0]] = value
	else:
		next[path[0]][path[1]] = value
	if key == "MapId" or key == "MapName":
		_commit(next, false)
	else:
		_commit(next)

func _commit(next: Dictionary, validate := true) -> void:
	if validate:
		var candidate := next.duplicate()
		candidate.map_id = "draft"
		candidate.map_name = "draft"
		var issue := Data.validate(candidate)
		if not issue.is_empty():
			_refresh_fields()
			_report(issue)
			return
	if next != map:
		history.append(map)
		if history.size() > 64:
			history.pop_front()
		future.clear()
		map = next
	_report("")

func _restore(from: Array[Dictionary], to: Array[Dictionary]) -> void:
	if from.is_empty():
		return
	to.append(map)
	map = from.pop_back()
	selected.clear()
	link_from = ""
	_refresh_fields()
	_report("")

func _load_map(value: Dictionary, path: String) -> void:
	map = value
	saved = value.duplicate(true)
	source_path = path
	history.clear()
	future.clear()
	selected.clear()
	link_from = ""
	_refresh_fields()
	_fit()

func _discard_or(action: Callable, title: String) -> void:
	if is_dirty():
		_confirm("地图有未保存的修改。放弃修改并%s？" % title, action)
	else:
		action.call()

func _confirm(prompt: String, action: Callable) -> void:
	pending = action
	%Confirm.dialog_text = prompt
	%Confirm.popup_centered()

func _close() -> void:
	_load_map(saved.duplicate(true), source_path)
	close_requested.emit()

func _open_dialog(directory: String) -> void:
	var legacy := directory == Data.LEGACY_DIRECTORY
	if legacy and not DirAccess.dir_exists_absolute(directory):
		_report("没有找到旧版地图目录。")
		return
	if not legacy and DirAccess.make_dir_recursive_absolute(directory) != OK:
		_report("无法创建地图目录。")
		return
	%OpenDialog.access = FileDialog.ACCESS_USERDATA if legacy else FileDialog.ACCESS_RESOURCES
	%OpenDialog.current_dir = directory
	%OpenDialog.popup_centered_ratio(0.65)

func _open(path: String) -> void:
	var directory := path.get_base_dir().simplify_path()
	if directory not in [Data.DIRECTORY, Data.LEGACY_DIRECTORY] or path.get_extension() != "json":
		_report("请选择探索地图目录中的 JSON 文件。")
		return
	var result := Data.read(path)
	if result.has("error"):
		_report(result.error)
	else:
		_load_map(result.map, path)
		_report("已打开旧地图，保存将写入工程目录。" if directory == Data.LEGACY_DIRECTORY else "已打开地图")

func _save(save_as: bool) -> void:
	if not Data.valid_id(map.map_id):
		_report("请在属性中填写有效的地图 ID。")
		return
	var path := Data.DIRECTORY.path_join(map.map_id + ".json")
	if save_as and path == source_path:
		_report("请先修改地图 ID，再另存为。")
		return
	if path != source_path and FileAccess.file_exists(path):
		_report("该地图 ID 已存在，请使用不同 ID。")
		return
	var issue := Data.write(path, map)
	if not issue.is_empty():
		_report(issue)
		return
	saved = map.duplicate(true)
	source_path = path
	_report("已保存地图")

func _confirm_remove() -> void:
	if source_path.is_empty():
		_report("当前地图还未保存。")
		return
	if source_path.get_base_dir() == Data.LEGACY_DIRECTORY:
		_report("旧目录地图仅用于读取，请在工程中保存后再管理副本。")
		return
	_confirm("删除 %s？当前未保存的修改也会丢弃。" % source_path.get_file(), _remove)

func _remove() -> void:
	if DirAccess.remove_absolute(source_path) != OK:
		_report("删除地图失败。")
		return
	_load_map(Data.blank(), "")
	_report("已删除地图")

func _check() -> void:
	var issue := Data.validate(map)
	if not issue.is_empty():
		_report(issue)
		return
	var connected := {}
	for edge in map.edges:
		connected[edge.from_node_id] = true
		connected[edge.to_node_id] = true
	_report("结构有效 · %d 个孤立格 · %s" % [
		map.nodes.size() - connected.size(), "已设置入口" if not map.entry_node_id.is_empty() else "尚未设置入口"])

func _node_rect(node: Dictionary) -> Rect2:
	return Data.bounds(node, map.cell_style)

func _view(point: Vector2) -> Vector2:
	return point * zoom + offset

func _world(point: Vector2) -> Vector2:
	return (point - offset) / zoom

func _fit() -> void:
	if map.nodes.is_empty() or canvas.size.x < 100 or canvas.size.y < 100:
		zoom = 1.0
		offset = Vector2(60, 60)
	else:
		var bounds := _node_rect(map.nodes[0])
		for node in map.nodes:
			bounds = bounds.merge(_node_rect(node))
		var available := canvas.size - Vector2(72, 72)
		zoom = clampf(minf(available.x / bounds.size.x, available.y / bounds.size.y), 0.02, 2.0)
		offset = canvas.size / 2.0 - bounds.get_center() * zoom
	_report("")

func _edge_segment(a: Rect2, b: Rect2) -> PackedVector2Array:
	var direction := (b.get_center() - a.get_center()).normalized()
	return [_view(_boundary(a, direction)), _view(_boundary(b, -direction))]

func _boundary(rect: Rect2, direction: Vector2) -> Vector2:
	var half := rect.size / 2.0
	var distance := minf(half.x / maxf(absf(direction.x), 0.000001),
		half.y / maxf(absf(direction.y), 0.000001))
	return rect.get_center() + direction * distance

func _draw_canvas() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(map.background_color))
	if %Grid.button_pressed:
		var step := 20.0 * zoom
		while step < 16.0:
			step *= 2.0
		var grid := Color(0.6, 0.85, 0.77, 0.09)
		for x in range(ceili(canvas.size.x / step) + 1):
			var at := fposmod(offset.x, step) + x * step
			canvas.draw_line(Vector2(at, 0), Vector2(at, canvas.size.y), grid)
		for y in range(ceili(canvas.size.y / step) + 1):
			var at := fposmod(offset.y, step) + y * step
			canvas.draw_line(Vector2(0, at), Vector2(canvas.size.x, at), grid)
	var rects := {}
	var icons := {}
	for node in map.nodes:
		rects[node.node_id] = _node_rect(node)
		icons[node.node_id] = node.get("icon_id", "")
	for edge in map.edges:
		var segment := _edge_segment(rects[edge.from_node_id], rects[edge.to_node_id])
		canvas.draw_line(segment[0], segment[1], Color(map.line_style.color), maxf(1.0, map.line_style.width * zoom), true)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(map.cell_style.fill)
	style.border_color = Color(map.cell_style.border)
	style.set_border_width_all(roundi(map.cell_style.stroke * zoom))
	style.set_corner_radius_all(roundi(map.cell_style.radius * zoom))
	for id in rects:
		var rect: Rect2 = rects[id]
		var displayed := Rect2(_view(rect.position), rect.size * zoom)
		canvas.draw_style_box(style, displayed)
		if not icons[id].is_empty():
			Legend.paint(canvas, icons[id], displayed)
		if id in selected or id == link_from:
			canvas.draw_rect(displayed.grow(2), Color("#f0d897"), false, 2)
			canvas.draw_circle(displayed.get_center(), 3.0, Color("#f0d897"))
	if gesture_active and mode in ["Box", "Region"]:
		var area := Rect2(_view(gesture_start), _view(pointer) - _view(gesture_start)).abs()
		canvas.draw_rect(area, Color(0.4, 0.8, 0.7, 0.18))
		canvas.draw_rect(area, Color("#85c1a9"), false, 1)

func _hit(point: Vector2) -> String:
	for node in map.nodes:
		if _node_rect(node).has_point(point):
			return node.node_id
	return ""

func _tooltip_at(point: Vector2) -> String:
	for node in map.nodes:
		if _node_rect(node).has_point(point):
			var id: String = node.get("icon_id", "")
			return Legend.title(id) if not id.is_empty() else ""
	return ""

func _snap(point: Vector2) -> Vector2:
	return point.snapped(Vector2(20, 20)) if %Snap.button_pressed else point

func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if panning:
			offset += event.relative
		pointer = _world(event.position)
		if gesture_active and not drag_snapshot.is_empty():
			var delta := _snap(pointer - gesture_start)
			for index in map.nodes.size():
				var node: Dictionary = map.nodes[index]
				if node.node_id in selected:
					var original: Array = drag_snapshot.nodes[index].position
					node.position = [original[0] + delta.x, original[1] + delta.y]
		canvas.tooltip_text = "" if gesture_active or panning else _tooltip_at(pointer)
		_update_status()
		canvas.queue_redraw()
	elif event is InputEventMouseButton:
		pointer = _world(event.position)
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom = clampf(zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.02, 4.0)
					offset = event.position - pointer * zoom
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_start_action(event.shift_pressed)
				else:
					_finish_action()
		_update_status()
		canvas.queue_redraw()
		canvas.accept_event()

func _start_action(extend: bool) -> void:
	var id := _hit(pointer)
	if %LegendPaint.button_pressed:
		if not id.is_empty():
			_paint_legend(id)
		return
	gesture_start = pointer
	match mode:
		"Select":
			if not extend and id not in selected:
				selected.clear()
			if not id.is_empty() and id not in selected:
				selected.append(id)
			if not id.is_empty():
				gesture_active = true
				drag_snapshot = map.duplicate(true)
				for node in map.nodes:
					if node.node_id == id:
						var rect := _node_rect(node)
						%NodeWidth.value = rect.size.x
						%NodeHeight.value = rect.size.y
		"Place":
			_generate(1, 1, _snap(pointer), false, _chosen_icon())
		"Link":
			if id.is_empty():
				link_from = ""
			elif link_from.is_empty():
				link_from = id
				_report("请选择路线终点")
			elif id != link_from:
				var next := map.duplicate(true)
				_add_edge(next, link_from, id, _ids(next.edges, "edge_id"))
				link_from = ""
				_commit(next)
		"Erase":
			if not id.is_empty():
				if id not in selected:
					selected.assign([id])
				_delete_selection()
			else:
				_delete_edge_at(pointer)
		"Box", "Region":
			gesture_active = true

func _finish_action() -> void:
	if not gesture_active:
		return
	gesture_active = false
	if not drag_snapshot.is_empty():
		var moved := map
		map = drag_snapshot
		drag_snapshot = {}
		_commit(moved)
		return
	var area := Rect2(gesture_start, pointer - gesture_start).abs()
	if mode == "Box":
		selected.clear()
		for node in map.nodes:
			if area.intersects(_node_rect(node)):
				selected.append(node.node_id)
		_report("选中 %d 个格子" % selected.size())
	elif mode == "Region":
		var gap: float = %Gap.value
		var cell := Vector2(map.cell_style.width, map.cell_style.height)
		var rows := floori((area.size.y + gap) / (cell.y + gap))
		var cols := floori((area.size.x + gap) / (cell.x + gap))
		_generate(rows, cols, _snap(area.position + cell / 2.0), %AutoLink.button_pressed)

func _generate_visible() -> void:
	var half := Vector2(map.cell_style.width, map.cell_style.height) / 2.0
	_generate(int(%Rows.value), int(%Columns.value), _snap(_world(Vector2(24, 24)) + half), %AutoLink.button_pressed)

func _generate(rows: int, columns: int, start: Vector2, auto_link: bool, icon_id := "") -> void:
	if rows <= 0 or columns <= 0 or map.nodes.size() + rows * columns > 1000:
		_report("放置区域太小或节点总数超过 1000。")
		return
	var next := map.duplicate(true)
	var occupied := _ids(next.nodes, "node_id")
	var edge_ids := _ids(next.edges, "edge_id")
	var created: Array[String] = []
	var spacing := Vector2(map.cell_style.width, map.cell_style.height) + Vector2.ONE * float(%Gap.value)
	for row in rows:
		for column in columns:
			var id := _allocate(occupied, "node")
			var center := start + Vector2(column, row) * spacing
			next.nodes.append({"node_id": id, "position": [center.x, center.y], "size": [], "icon_id": icon_id})
			if auto_link:
				if column > 0:
					_add_edge(next, created[-1], id, edge_ids)
				if row > 0:
					_add_edge(next, created[created.size() - columns], id, edge_ids)
			created.append(id)
	_commit(next)

func _ids(items: Array, field: String) -> Dictionary:
	var result := {}
	for item in items:
		result[item[field]] = true
	return result

func _allocate(ids: Dictionary, prefix: String) -> String:
	var crypto := Crypto.new()
	var id := prefix + "_" + crypto.generate_random_bytes(12).hex_encode()
	while ids.has(id):
		id = prefix + "_" + crypto.generate_random_bytes(12).hex_encode()
	ids[id] = true
	return id

func _add_edge(next: Dictionary, a: String, b: String, ids: Dictionary) -> void:
	var id := _allocate(ids, "edge")
	next.edges.append({"edge_id": id, "from_node_id": a, "to_node_id": b})

func _delete_selection() -> void:
	var next := map.duplicate(true)
	next.nodes = next.nodes.filter(func(node: Dictionary) -> bool: return node.node_id not in selected)
	next.edges = next.edges.filter(func(edge: Dictionary) -> bool:
		return edge.from_node_id not in selected and edge.to_node_id not in selected)
	if next.has("portal_pairs"):
		next.portal_pairs = next.portal_pairs.filter(func(pair: Array) -> bool:
			return pair[0] not in selected and pair[1] not in selected)
	if next.entry_node_id in selected:
		next.entry_node_id = ""
	selected.clear()
	_commit(next)

func _delete_edge_at(point: Vector2) -> void:
	var rects := {}
	for node in map.nodes:
		rects[node.node_id] = _node_rect(node)
	var hit := -1
	var distance := maxf(5.0, map.line_style.width * zoom / 2.0)
	for index in map.edges.size():
		var edge: Dictionary = map.edges[index]
		var segment := _edge_segment(rects[edge.from_node_id], rects[edge.to_node_id])
		var closest := Geometry2D.get_closest_point_to_segment(_view(point), segment[0], segment[1])
		var difference := closest.distance_to(_view(point))
		if difference <= distance:
			hit = index
			distance = difference
	if hit >= 0:
		var next := map.duplicate(true)
		next.edges.remove_at(hit)
		_commit(next)

func _resize_selected(reset: bool) -> void:
	var next := map.duplicate(true)
	for node in next.nodes:
		if node.node_id in selected:
			node.size = [] if reset else [%NodeWidth.value, %NodeHeight.value]
	_commit(next)

func _set_entry() -> void:
	if selected.size() != 1:
		_report("请选中一个格子作为入口。")
		return
	var next := map.duplicate(true)
	next.entry_node_id = selected[0]
	_commit(next)
	_report("已设入口：%s" % selected[0])

func _copy() -> void:
	if selected.is_empty():
		_report("请先选择要复制的格子。")
		return
	clipboard = {
		"nodes": map.nodes.filter(func(node: Dictionary) -> bool: return node.node_id in selected).duplicate(true),
		"edges": map.edges.filter(func(edge: Dictionary) -> bool:
			return edge.from_node_id in selected and edge.to_node_id in selected).duplicate(true),
	}
	_report("已复制 %d 个格子，点击画布定位后可粘贴。" % clipboard.nodes.size())

func _paste() -> void:
	if clipboard.is_empty():
		return
	var next := map.duplicate(true)
	var occupied := _ids(next.nodes, "node_id")
	var mapping := {}
	var origin: Array = clipboard.nodes[0].position
	var target := _snap(pointer)
	for original in clipboard.nodes:
		var node: Dictionary = original.duplicate(true)
		node.node_id = _allocate(occupied, "node")
		node.position = [target.x + node.position[0] - origin[0], target.y + node.position[1] - origin[1]]
		mapping[original.node_id] = node.node_id
		next.nodes.append(node)
	var edge_ids := _ids(next.edges, "edge_id")
	for edge in clipboard.edges:
		_add_edge(next, mapping[edge.from_node_id], mapping[edge.to_node_id], edge_ids)
	_commit(next)
