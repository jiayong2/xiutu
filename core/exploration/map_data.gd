@tool
extends RefCounted

const DIRECTORY := "res://authoring/exploration/maps"
const LEGACY_DIRECTORY := "user://exploration_maps"
const Legend = preload("res://core/exploration/symbols.gd")

static func blank() -> Dictionary:
	return {
		"map_id": "new_map", "map_name": "未命名地图", "background_color": "#102a28",
		"cell_style": {"width": 80, "height": 80, "fill": "#265548",
			"border": "#85c1a9", "radius": 5, "stroke": 2},
		"line_style": {"color": "#70a996", "width": 8},
		"nodes": [], "edges": [], "entry_node_id": "",
	}

static func valid_id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 64 and 		value == value.to_lower() and value.is_valid_ascii_identifier()

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and value >= minimum and value <= maximum

static func color(value: Variant) -> bool:
	return value is String and Color.html_is_valid(value)

static func bounds(node: Dictionary, style: Dictionary) -> Rect2:
	var dimensions: Array = node.size
	var cell_size := Vector2(style.width, style.height) if dimensions.is_empty() 		else Vector2(dimensions[0], dimensions[1])
	var center := Vector2(node.position[0], node.position[1])
	return Rect2(center - cell_size / 2.0, cell_size)

static func validate(map: Dictionary) -> String:
	if not valid_id(map.get("map_id")) or not map.get("map_name") is String 			or map.map_name.strip_edges().is_empty():
		return "地图 ID 须为小写 ASCII 标识符，地图名称不能为空。"
	var cell: Variant = map.get("cell_style")
	var line: Variant = map.get("line_style")
	if not cell is Dictionary or not line is Dictionary or not color(map.get("background_color")) 			or not color(cell.get("fill")) or not color(cell.get("border")) 			or not color(line.get("color")) or not number(cell.get("width"), 16, 512) 			or not number(cell.get("height"), 16, 512) or not number(cell.get("radius"), 0, 64) 			or not number(cell.get("stroke"), 0, 16) or not number(line.get("width"), 1, 32):
		return "地图样式无效。"
	if not map.get("nodes") is Array or not map.get("edges") is Array or map.nodes.size() > 1000:
		return "节点或路线列表无效，节点上限为 1000。"
	var ids := {}
	var rectangles: Array[Rect2] = []
	for node in map.nodes:
		if not node is Dictionary or not valid_id(node.get("node_id")) or ids.has(node.node_id):
			return "节点 ID 无效或重复。"
		var icon_id: Variant = node.get("icon_id", "")
		if not icon_id is String or (not icon_id.is_empty() and not Legend.ICONS.has(icon_id)):
			return "节点 %s 的图例 ID 无效。" % node.node_id
		var p: Variant = node.get("position")
		var s: Variant = node.get("size")
		if not p is Array or p.size() != 2 or not number(p[0], -1000000, 1000000) 				or not number(p[1], -1000000, 1000000) or not s is Array 				or (not s.is_empty() and (s.size() != 2 or not number(s[0], 16, 512) 				or not number(s[1], 16, 512))):
			return "节点 %s 的位置或尺寸无效。" % node.node_id
		var rect := bounds(node, cell)
		for other in rectangles:
			if rect.intersects(other):
				return "节点 %s 与其他节点重叠。" % node.node_id
		rectangles.append(rect)
		ids[node.node_id] = icon_id
	if not map.get("entry_node_id") is String or 			(not map.entry_node_id.is_empty() and not ids.has(map.entry_node_id)):
		return "入口引用不存在。"
	var edge_ids := {}
	var pairs := {}
	for edge in map.edges:
		if not edge is Dictionary or not valid_id(edge.get("edge_id")) or edge_ids.has(edge.edge_id):
			return "路线 ID 无效或重复。"
		var a: Variant = edge.get("from_node_id")
		var b: Variant = edge.get("to_node_id")
		if not a is String or not b is String or a == b or not ids.has(a) or not ids.has(b):
			return "路线 %s 的端点无效。" % edge.edge_id
		var pair := "%s/%s" % [a, b] if a < b else "%s/%s" % [b, a]
		if pairs.has(pair):
			return "同一对节点之间已有路线。"
		pairs[pair] = true
		edge_ids[edge.edge_id] = true
	if map.has("portal_pairs"):
		if not map.portal_pairs is Array:
			return "传送配对格式无效。"
		var paired := {}
		for pair in map.portal_pairs:
			if not pair is Array or pair.size() != 2 or pair[0] == pair[1]:
				return "传送配对需要两个不同的节点。"
			for id in pair:
				if not id is String or ids.get(id) != "S01" or paired.has(id):
					return "传送配对引用无效或重复。"
				paired[id] = true
	return ""

static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "无法打开地图文件。"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"error": "地图文件不是有效的 JSON 对象。"}
	var issue := validate(parser.data)
	return {"map": parser.data} if issue.is_empty() else {"error": issue}

static func write(path: String, map: Dictionary) -> String:
	var issue := validate(map)
	if not issue.is_empty():
		return issue
	return write_json(path, map)

static func write_json(path: String, data: Dictionary) -> String:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return "无法创建地图目录。"
	var staged := path + ".tmp"
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null:
		return "无法写入临时地图文件。"
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(staged, path)
	if result != OK:
		DirAccess.remove_absolute(staged)
		return "保存失败。"
	return ""
