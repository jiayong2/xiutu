extends RefCounted

const MapData = preload("res://core/exploration/map_data.gd")
const Config = preload("res://core/exploration/legend_config.gd")
const REWARDS := ["O01", "O02", "O08"]

static func validate_catalog(catalog: Dictionary) -> String:
	var random := preload("res://core/random_service.gd").new()
	random.initialize(1)
	for definition in catalog.exploration_maps.values():
		if not MapData.valid_id(definition.id) or not MapData.valid_id(definition.get("location_id")):
			return "探索地图目录 ID 无效：" + definition.id
		var label: Variant = definition.get("entry_label")
		if not label is String or label.strip_edges().is_empty():
			return "探索地图缺少入口名称：" + definition.id
		for key in ["template_path", "config_path"]:
			var path: Variant = definition.get(key)
			if not path is String or not path.begins_with("res://data/") or not FileAccess.file_exists(path):
				return "探索地图缺少随包数据：%s · %s" % [definition.id, key]
		var result := open(definition, catalog, random, false)
		if result.has("error"):
			return "%s：%s" % [definition.id, result.error]
	return ""

static func find_map(catalog: Dictionary, location_id: String, map_id: String) -> Dictionary:
	var maps: Dictionary = catalog.get("exploration_maps", {})
	if not map_id.is_empty():
		var definition: Dictionary = maps.get(map_id, {})
		return definition if definition.get("location_id") == location_id else {}
	for definition in maps.values():
		if definition.location_id == location_id:
			return definition
	return {}

static func open(definition: Dictionary, catalog: Dictionary, random: RefCounted, author_override: bool, previous := {}) -> Dictionary:
	var map_path: String = definition.template_path
	var config_path: String = definition.config_path
	var author_map := MapData.DIRECTORY.path_join(definition.id + ".json")
	if not FileAccess.file_exists(author_map):
		author_map = MapData.LEGACY_DIRECTORY.path_join(definition.id + ".json")
	var author_config := Config.author_read_path()
	if author_override and FileAccess.file_exists(author_map) and FileAccess.file_exists(author_config):
		var author := _read_sources(definition.id, author_map, author_config, catalog)
		if not author.has("error") and author.config.allocations.has(definition.id):
			var before: Dictionary = random.snapshot()
			var candidate := create_run(author.map, author.config, random, previous)
			if not candidate.has("error"):
				return candidate
			random.restore(before)
			push_warning("本机探索配置无法分配，改用随包配置：" + str(candidate.error))
		elif author.has("error"):
			push_warning("本机探索配置读取失败，改用随包配置：" + str(author.error))
	var bundled := _read_sources(definition.id, map_path, config_path, catalog)
	if bundled.has("error"):
		return bundled
	if not bundled.config.allocations.has(definition.id):
		return {"error": "随包地图缺少分配配置：" + definition.id}
	return create_run(bundled.map, bundled.config, random, previous)

static func _read_sources(map_id: String, map_path: String, config_path: String, catalog: Dictionary) -> Dictionary:
	var loaded := MapData.read(map_path)
	if loaded.has("error"):
		return loaded
	if loaded.map.map_id != map_id:
		return {"error": "地图文件 ID 与目录不一致：" + map_id}
	var config := Config.read(catalog, config_path)
	if config.has("error"):
		return config
	return {"map": loaded.map, "config": config}

static func index(map: Dictionary) -> Dictionary:
	var graph := {}
	for node in map.nodes:
		graph[node.node_id] = []
	for edge in map.edges:
		graph[edge.from_node_id].append(edge.to_node_id)
		graph[edge.to_node_id].append(edge.from_node_id)
	return graph

static func adjacent(map: Dictionary, from: String, to: String) -> bool:
	for edge in map.edges:
		if (edge.from_node_id == from and edge.to_node_id == to) or (edge.from_node_id == to and edge.to_node_id == from):
			return true
	return false

static func entry(map: Dictionary) -> String:
	if not map.entry_node_id.is_empty():
		return map.entry_node_id
	var markers: Array = map.nodes.filter(func(node: Dictionary) -> bool: return node.get("icon_id") == "S07")
	return markers[0].node_id if markers.size() == 1 else ""

static func preflight_allocations(maps: Dictionary, rows: Dictionary, allocations: Dictionary) -> String:
	for map_id in allocations:
		if not maps.has(map_id):
			return "找不到分配所引用的地图：" + str(map_id)
		var result := create_run(maps[map_id], {"rows": rows, "allocations": allocations}, null)
		if result.has("error"):
			return "%s：%s" % [map_id, result.error]
	return ""

static func create_run(template: Dictionary, config: Dictionary, random: RefCounted, previous := {}) -> Dictionary:
	var map := template.duplicate(true)
	var start := entry(map)
	if start.is_empty():
		return {"error": "地图未设置入口。"}
	var graph := index(map)
	var links := portal_links(map)
	var reached := {start: true}
	var standable := {start: true}
	var queue := [start]
	while not queue.is_empty():
		for neighbor in graph[queue.pop_front()]:
			reached[neighbor] = true
			var landing: String = links.get(neighbor, neighbor)
			reached[landing] = true
			if not standable.has(landing):
				standable[landing] = true
				queue.append(landing)
	var allocation: Dictionary = config.allocations.get(map.map_id, {"totals": {}, "counts": {}})
	var error := Config.validate_allocations({map.map_id: allocation}, config.rows, {map.map_id: map})
	if not error.is_empty():
		return {"error": error}
	if map.has("portal_pairs") and allocation.totals.has("S01"):
		return {"error": "已指定传送配对的地图，法阵位置由模板固定。"}
	var pools := {}
	var empty := []
	var symbols := {}
	for node in map.nodes:
		var id: String = node.node_id
		var symbol: String = node.get("icon_id", "")
		symbols[id] = symbol
		if id == start or not reached.has(id):
			continue
		if symbol.is_empty():
			empty.append(id)
		elif allocation.totals.has(symbol):
			var group := "reward" if symbol in REWARDS else symbol
			if not pools.has(group):
				pools[group] = []
			pools[group].append(id)
			symbols[id] = ""
	if random != null and pools.has("reward"):
		_shuffle(pools.reward, random)
	var assigned := {}
	var remaining: Dictionary = allocation.counts.duplicate()
	if previous.get("map", {}).get("map_id") == map.map_id:
		_keep_assignments(previous, config.rows, pools, symbols, assigned, remaining)
	for legend_id in remaining:
		var definition: Dictionary = config.rows[legend_id]
		var group: String = "reward" if definition.symbol in REWARDS else definition.symbol
		var pool: Array = pools.get(group, [])
		for number in int(remaining[legend_id]):
			var id: Variant = pool.pop_back() if not pool.is_empty() else empty.pop_back()
			if id == null:
				return {"error": "从入口可达的空格不足，无法分配 %s。" % definition.name}
			symbols[id] = definition.symbol
			assigned[id] = definition.duplicate(true)
	for node in map.nodes:
		node.icon_id = symbols[node.node_id]
	return {"run": {"version": 1, "map": map, "active": true, "current": start, "revealed": [start], "paths": [],
		"assigned": assigned, "cleared": {}, "claimed": {}, "wins": {}, "pending": ""}}

static func _keep_assignments(previous: Dictionary, rows: Dictionary, pools: Dictionary,
		symbols: Dictionary, assigned: Dictionary, remaining: Dictionary) -> void:
	var bindings: Dictionary = previous.get("assigned", {})
	for id in bindings:
		var old: Dictionary = bindings[id]
		var legend_id: String = old.legend_id
		if int(remaining.get(legend_id, 0)) <= 0 or old.symbol in REWARDS:
			continue
		var definition: Dictionary = rows[legend_id]
		if definition.symbol != old.symbol or definition.target_id != old.target_id:
			continue
		var pool: Array = pools.get(definition.symbol, [])
		if not pool.has(id):
			continue
		pool.erase(id)
		symbols[id] = definition.symbol
		assigned[id] = definition.duplicate(true)
		remaining[legend_id] = int(remaining[legend_id]) - 1

static func _shuffle(items: Array, random: RefCounted) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other: int = random.integer("exploration", 0, index)
		var previous: Variant = items[index]
		items[index] = items[other]
		items[other] = previous

static func arrive(run: Dictionary, target: String, connected: bool = true) -> void:
	if connected and [run.current, target] not in run.paths and [target, run.current] not in run.paths:
		run.paths.append([run.current, target])
	run.current = target
	if target not in run.revealed:
		run.revealed.append(target)

static func validate(run: Variant, catalog: Dictionary) -> String:
	if not run is Dictionary or not run.get("map") is Dictionary or not MapData.validate(run.map).is_empty():
		return "探索地图存档无效"
	if run.get("version", 1) != 1:
		return "探索存档版本不受支持"
	var graph := index(run.map)
	if not run.get("active") is bool or not run.get("current") is String or not graph.has(run.current) or not run.get("pending") is String:
		return "探索位置无效"
	for field in ["assigned", "cleared", "claimed", "wins"]:
		if not run.get(field) is Dictionary:
			return "探索节点记录无效"
		for id in run[field]:
			if not graph.has(id):
				return "探索节点引用无效"
	for id in run.assigned:
		var definition: Variant = run.assigned[id]
		if not definition is Dictionary or not definition.get("legend_id") is String:
			return "探索图例记录无效"
		if not Config.validate({definition.legend_id: definition}, catalog).is_empty():
			return "探索图例定义无效"
	for field in ["cleared", "claimed"]:
		for id in run[field]:
			if run[field][id] != true or not run.assigned.has(id):
				return "探索结算标记无效"
	for id in run.wins:
		var count: Variant = run.wins[id]
		if not run.assigned.has(id) or not MapData.number(count, 1, run.assigned[id].enemy_count) or float(count) != floorf(float(count)):
			return "探索击败数量无效"
	if not run.pending.is_empty() and (not graph[run.current].has(run.pending) or not run.assigned.has(run.pending) or run.assigned[run.pending].target_type != "monster"):
		return "探索遭遇记录无效"
	if not run.get("revealed") is Array or not run.get("paths") is Array:
		return "探索揭雾记录无效"
	for id in run.revealed:
		if not id is String or not graph.has(id):
			return "探索揭雾节点无效"
	for pair in run.paths:
		if not pair is Array or pair.size() != 2 or not graph.has(pair[0]) or not graph[pair[0]].has(pair[1]):
			return "探索揭雾路线无效"
	return ""

static func portal_destination(map: Dictionary, target: String) -> String:
	return portal_links(map).get(target, target)

static func portal_links(map: Dictionary) -> Dictionary:
	var links := {}
	if map.has("portal_pairs"):
		for pair in map.portal_pairs:
			links[pair[0]] = pair[1]
			links[pair[1]] = pair[0]
		return links
	var portals: Array = map.nodes.filter(func(node: Dictionary) -> bool: return node.get("icon_id") == "S01")
	if portals.size() == 2:
		links[portals[0].node_id] = portals[1].node_id
		links[portals[1].node_id] = portals[0].node_id
	return links

static func shortest_route(graph: Dictionary, links: Dictionary, start: String, target: String) -> Array:
	if start == target or not graph.has(start) or not graph.has(target):
		return []
	var queue := [[start, []]]
	var visited := {start: true}
	var index := 0
	while index < queue.size():
		var item: Array = queue[index]
		index += 1
		for next in graph[item[0]]:
			var trail: Array = item[1] + [next]
			if next == target:
				return trail
			var landing: String = links.get(next, next)
			if not visited.has(landing):
				visited[landing] = true
				queue.append([landing, trail])
	return []

static func retain_progress(previous: Dictionary, next: Dictionary) -> void:
	for id in next.assigned:
		var definition: Dictionary = next.assigned[id]
		if definition.symbol in REWARDS or definition.respawn_mode == "reenter":
			continue
		var previous_definition: Dictionary = previous.get("assigned", {}).get(id, {})
		if previous_definition.get("legend_id") != definition.legend_id or previous_definition.get("target_id") != definition.target_id:
			continue
		if previous.get("cleared", {}).has(id) and previous_definition.enemy_count == definition.enemy_count:
			next.cleared[id] = true
			next.wins[id] = int(definition.enemy_count)
		elif previous.get("wins", {}).has(id):
			var count := mini(int(previous.wins[id]), int(definition.enemy_count) - 1)
			if count > 0:
				next.wins[id] = count
		if previous.get("claimed", {}).has(id):
			next.claimed[id] = true
