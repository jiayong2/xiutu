extends RefCounted
## Read-only reference queries for the item database editor.
## All rows come from the loaded content catalog or from the live runtime snapshot;
## no demonstration references are fabricated.

const SLOTS := {"weapon": "武器", "head": "头冠", "armor": "法衣", "wrist": "护腕",
	"waist": "腰带", "shoes": "灵靴", "necklace": "项链", "ring": "戒指"}
const UNCHECKED := ["历史存档（未逐个枚举）", "authoring/ 作者草稿覆盖（不参与正式静态配置）",
	"战斗/探索临时状态（仅检查当前运行快照）"]

static func all_references(catalog: Dictionary, runtime: Dictionary = {}) -> Dictionary:
	var result := {}
	for id in _item_rows(catalog):
		result[id] = _empty(id)
	for ref in _static_references(catalog):
		_add(result, ref)
	for ref in _runtime_references(runtime):
		_add(result, ref)
	for id in result:
		var entry: Dictionary = result[id]
		var total := 0
		for group in entry.groups:
			total += group.rows.size()
		entry.total = total
		entry.blocking = total > 0
	return result

static func query(item_id: String, catalog: Dictionary, runtime: Dictionary = {}) -> Dictionary:
	var all := all_references(catalog, runtime)
	return all.get(item_id, _empty(item_id))

static func catalog_error(catalog: Dictionary, ids: Dictionary) -> String:
	var issues := catalog_issues(catalog, ids)
	return issues[0] if not issues.is_empty() else ""

static func catalog_issues(catalog: Dictionary, ids: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	var seen := {}
	for ref in _static_references(catalog):
		var item_id: String = ref.item_id
		if ids.has(item_id):
			continue
		var key: String = item_id + "|" + str(ref.source)
		if seen.has(key):
			continue
		seen[key] = true
		issues.append("物品 %s 仍被%s引用，不能删除或遗漏。" % [item_id, ref.source])
	return issues

static func _empty(item_id: String) -> Dictionary:
	return {"item_id": item_id, "groups": [], "total": 0, "blocking": false, "unchecked": UNCHECKED.duplicate()}

static func _add(result: Dictionary, ref: Dictionary) -> void:
	var item_id: String = ref.item_id
	if not result.has(item_id):
		result[item_id] = _empty(item_id)
	var entry: Dictionary = result[item_id]
	var group: Dictionary = {}
	for candidate in entry.groups:
		if candidate.key == ref.group_key:
			group = candidate
			break
	if group.is_empty():
		group = {"key": ref.group_key, "title": ref.group_title, "rows": []}
		entry.groups.append(group)
	group.rows.append({"label": ref.label, "detail": ref.detail, "source": ref.source,
		"target_type": ref.target_type, "target_id": ref.target_id, "blocking": ref.blocking})

static func _ref(item_id: String, group_key: String, group_title: String, label: String,
		detail: String, source: String, target_type: String = "", target_id: String = "") -> Dictionary:
	return {"item_id": item_id, "group_key": group_key, "group_title": group_title,
		"label": label, "detail": detail, "source": source,
		"target_type": target_type, "target_id": target_id, "blocking": true}

static func _item_rows(catalog: Dictionary) -> Dictionary:
	var table: Variant = catalog.get("items", {})
	if table is Dictionary:
		return table
	var rows := {}
	if table is Array:
		for row in table:
			if row is Dictionary and row.get("id") is String:
				rows[row.id] = row
	return rows

static func _values(table: Variant) -> Array:
	if table is Dictionary:
		return table.values()
	if table is Array:
		return table
	return []

static func _static_references(catalog: Dictionary) -> Array:
	var refs: Array = []
	_collect_shops(refs, catalog)
	_collect_monsters(refs, catalog)
	_collect_routes(refs, catalog)
	_collect_herbs(refs, catalog)
	_collect_recipes(refs, catalog)
	_collect_quests(refs, catalog)
	_collect_initial(refs, catalog)
	_collect_auctions(refs, catalog)
	_collect_equipment(refs, catalog)
	_collect_npcs(refs, catalog)
	_collect_inns(refs, catalog)
	_collect_exploration(refs, catalog)
	return refs

static func _collect_shops(refs: Array, catalog: Dictionary) -> void:
	for shop in _values(catalog.get("shops", {})):
		if not shop is Dictionary or not shop.get("stock") is Dictionary:
			continue
		var shop_name: String = str(shop.get("name", shop.get("id", "商店")))
		for item_id in shop.stock:
			refs.append(_ref(str(item_id), "shops", "商店库存", shop_name,
				"库存 %d" % int(shop.stock[item_id]), "商店「%s」" % shop_name, "shop", str(shop.get("id", ""))))

static func _collect_monsters(refs: Array, catalog: Dictionary) -> void:
	for monster in _values(catalog.get("monsters", {})):
		if not monster is Dictionary or not monster.get("loot") is Dictionary or not monster.loot.get("entries") is Array:
			continue
		var monster_name: String = str(monster.get("name", monster.get("id", "妖兽")))
		for entry in monster.loot.entries:
			if not entry is Dictionary or not entry.get("item_id") is String:
				continue
			var minimum := int(entry.get("min", 1))
			var maximum := int(entry.get("max", minimum))
			var chance := 100 if bool(entry.get("guaranteed", false)) else int(round(float(entry.get("chance", 0.0)) * 100.0))
			var detail := "%d–%d 件 · %d%%" % [minimum, maximum, chance] if maximum != minimum else "%d 件 · %d%%" % [minimum, chance]
			if entry.get("once") is String:
				detail += " · 单次"
			refs.append(_ref(entry.item_id, "monsters", "怪物掉落", monster_name, detail,
				"妖兽「%s」掉落表" % monster_name, "monster", str(monster.get("id", ""))))

static func _collect_routes(refs: Array, catalog: Dictionary) -> void:
	var prototype: Variant = catalog.get("prototype", {})
	if not prototype is Dictionary or not prototype.get("outskirts_routes") is Array:
		return
	for route in prototype.outskirts_routes:
		if not route is Dictionary:
			continue
		var route_name: String = str(route.get("name", route.get("id", "路线")))
		if route.get("mining") is Array:
			for ore in route.mining:
				if ore is Dictionary and ore.get("item_id") is String:
					refs.append(_ref(ore.item_id, "routes", "地图采集", route_name,
						"采矿 · %d%%" % int(ore.get("chance", 0)), "地点「%s」采矿" % route_name,
						"route", str(route.get("id", ""))))
		if route.get("herbs") is Array:
			for herb_id in route.herbs:
				if herb_id is String:
					refs.append(_ref(herb_id, "routes", "地图采集", route_name,
						"采集", "地点「%s」采集" % route_name, "route", str(route.get("id", ""))))

static func _collect_herbs(refs: Array, catalog: Dictionary) -> void:
	for herb in _values(catalog.get("herbs", {})):
		if not herb is Dictionary:
			continue
		var herb_name: String = str(herb.get("id", "灵草"))
		if herb.get("id") is String:
			refs.append(_ref(herb.id, "herbs", "灵草/种子", "灵草 " + herb_name,
				"成熟 %d 天 · 产出 %d" % [int(herb.get("days", 0)), int(herb.get("yield_count", 0))],
				"灵草定义「%s」" % herb_name, "herb", herb.id))
		if herb.get("seed_id") is String:
			refs.append(_ref(herb.seed_id, "herbs", "灵草/种子", "种子 → " + herb_name,
				"用于种植", "灵草定义「%s」种子" % herb_name, "herb", herb_name))

static func _collect_recipes(refs: Array, catalog: Dictionary) -> void:
	for recipe in _values(catalog.get("recipes", {})):
		if not recipe is Dictionary:
			continue
		var recipe_name: String = str(recipe.get("name", recipe.get("id", "配方")))
		if recipe.get("materials") is Dictionary:
			for item_id in recipe.materials:
				refs.append(_ref(str(item_id), "recipes", "炼丹/炼器配方", recipe_name,
					"材料 ×%d" % int(recipe.materials[item_id]), "配方「%s」材料" % recipe_name,
					"recipe", str(recipe.get("id", ""))))
		if recipe.get("output") is String:
			refs.append(_ref(recipe.output, "recipes", "炼丹/炼器配方", recipe_name,
				"产出", "配方「%s」产出" % recipe_name, "recipe", str(recipe.get("id", ""))))

static func _collect_quests(refs: Array, catalog: Dictionary) -> void:
	var item_ids := _item_rows(catalog)
	for quest in _values(catalog.get("quests", {})):
		if not quest is Dictionary:
			continue
		var quest_name: String = str(quest.get("name", quest.get("title", quest.get("id", "任务"))))
		if quest.get("required_item") is String and not quest.required_item.is_empty():
			refs.append(_ref(quest.required_item, "quests", "任务", quest_name,
				"交付需求", "任务「%s」" % quest_name, "quest", str(quest.get("id", ""))))
		if quest.get("rewards") is Dictionary:
			for item_id in quest.rewards:
				refs.append(_ref(str(item_id), "quests", "任务", quest_name,
					"奖励 ×%d" % int(quest.rewards[item_id]), "任务「%s」奖励" % quest_name,
					"quest", str(quest.get("id", ""))))
		if quest.get("objectives") is Array:
			for objective in quest.objectives:
				if not objective is Dictionary or not objective.get("target_id") is String:
					continue
				if item_ids.has(objective.target_id):
					refs.append(_ref(objective.target_id, "quests", "任务", quest_name,
						"目标 · %s" % str(objective.get("objective_id", "物品目标")),
						"任务「%s」目标" % quest_name, "quest", str(quest.get("id", ""))))

static func _collect_initial(refs: Array, catalog: Dictionary) -> void:
	var rules: Variant = catalog.get("rules", {})
	if not rules is Dictionary:
		return
	if rules.get("initial_items") is Dictionary:
		for item_id in rules.initial_items:
			refs.append(_ref(str(item_id), "initial", "初始配置", "初始背包",
				"×%d" % int(rules.initial_items[item_id]), "初始背包配置", "rules", "initial_items"))
	if rules.get("initial_equipment") is String:
		refs.append(_ref(rules.initial_equipment, "initial", "初始配置", "初始装备",
			"开局装备", "初始装备配置", "rules", "initial_equipment"))
	if rules.get("qi_equipment_set") is Array:
		for item_id in rules.qi_equipment_set:
			if item_id is String:
				refs.append(_ref(item_id, "initial", "初始配置", "炼气套装",
					"一次性领取", "炼气套装配置", "rules", "qi_equipment_set"))

static func _collect_auctions(refs: Array, catalog: Dictionary) -> void:
	for auction in _values(catalog.get("auctions", {})):
		if not auction is Dictionary or not auction.get("lots") is Array:
			continue
		var auction_name: String = str(auction.get("name", auction.get("id", "拍卖会")))
		for lot in auction.lots:
			if not lot is Dictionary or not lot.get("item") is String:
				continue
			refs.append(_ref(lot.item, "auction", "拍卖会", auction_name,
				"拍品 ×%d · 起拍 %d" % [int(lot.get("quantity", 1)), int(lot.get("start", 0))],
				"拍卖会「%s」拍品" % auction_name, "auction", str(auction.get("id", ""))))

static func _collect_equipment(refs: Array, catalog: Dictionary) -> void:
	for definition in _values(catalog.get("equipment", {})):
		if not definition is Dictionary or not definition.get("id") is String:
			continue
		var slot := str(definition.get("slot", ""))
		var slot_name: String = str(SLOTS.get(slot, slot))
		refs.append(_ref(definition.id, "equipment", "装备定义", "装备数值定义",
			"部位 · %s" % slot_name if not slot_name.is_empty() else "装备数值定义",
			"装备表「%s」" % definition.id, "equipment", definition.id))

static func _collect_npcs(refs: Array, catalog: Dictionary) -> void:
	var prototype: Variant = catalog.get("prototype", {})
	if prototype is Dictionary and prototype.get("npcs") is Array:
		for npc in prototype.npcs:
			if not npc is Dictionary:
				continue
			var npc_name: String = str(npc.get("name", npc.get("id", "NPC")))
			var profile: Variant = npc.get("profile", {})
			if not profile is Dictionary:
				continue
			var loadout: Variant = profile.get("loadout", {})
			if loadout is Dictionary and loadout.get("equipment") is Dictionary:
				for slot in loadout.equipment:
					var item_id: Variant = loadout.equipment[slot]
					if item_id is String:
						refs.append(_ref(item_id, "npc", "NPC 配置", npc_name,
							"装备 · %s" % str(SLOTS.get(slot, slot)),
							"NPC「%s」装备配置" % npc_name, "npc", str(npc.get("id", ""))))
	for npc in _values(catalog.get("npc_overrides", {})):
		if not npc is Dictionary:
			continue
		var npc_name: String = str(npc.get("name", npc.get("id", "NPC")))
		if npc.get("inventory") is Dictionary:
			for item_id in npc.inventory:
				refs.append(_ref(str(item_id), "npc", "NPC 配置", npc_name,
					"背包 ×%d" % int(npc.inventory[item_id]), "NPC「%s」背包" % npc_name,
					"npc", str(npc.get("id", ""))))
		if npc.get("equipment_instances") is Dictionary:
			for instance in npc.equipment_instances:
				var item_id: Variant = npc.equipment_instances[instance]
				if item_id is String:
					refs.append(_ref(item_id, "npc", "NPC 配置", npc_name,
						"装备实例", "NPC「%s」装备" % npc_name, "npc", str(npc.get("id", ""))))

static func _collect_inns(refs: Array, catalog: Dictionary) -> void:
	for inn in _values(catalog.get("inns", {})):
		if not inn is Dictionary or not inn.get("menu_items") is Array:
			continue
		var inn_name: String = str(inn.get("name", inn.get("id", "客栈")))
		for entry in inn.menu_items:
			if entry is Dictionary and entry.get("item_id") is String:
				refs.append(_ref(entry.item_id, "inns", "客栈菜单", inn_name,
					"菜单", "客栈「%s」菜单" % inn_name, "inn", str(inn.get("id", ""))))

static func _collect_exploration(refs: Array, catalog: Dictionary) -> void:
	for map in _values(catalog.get("exploration_maps", {})):
		if not map is Dictionary:
			continue
		var map_name: String = str(map.get("name", map.get("entry_label", map.get("id", "探索地图"))))
		var map_id: String = str(map.get("id", ""))
		var config_path: String = str(map.get("config_path", ""))
		if not config_path.is_empty() and FileAccess.file_exists(config_path):
			var legends := _read_legends(config_path)
			for legend in legends:
				var legend_name: String = str(legend.get("name", legend.get("legend_id", "图例")))
				if legend.get("target_type") == "item" and legend.get("target_id") is String:
					refs.append(_ref(legend.target_id, "exploration", "探索地图图例",
						"%s · %s" % [map_name, legend_name], "图例绑定",
						"探索图例「%s」" % legend_name, "legend", str(legend.get("legend_id", ""))))
				if legend.get("loot") is Array:
					for entry in legend.loot:
						if entry is Dictionary and entry.get("item_id") is String:
							var detail := "掉落"
							if entry.get("min") != null and entry.get("max") != null:
								detail = "掉落 %d–%d · %d%%" % [int(entry.min), int(entry.max), int(entry.get("chance", 0))]
							refs.append(_ref(entry.item_id, "exploration", "探索地图图例",
								"%s · %s" % [map_name, legend_name], detail,
								"探索图例「%s」掉落" % legend_name, "legend", str(legend.get("legend_id", ""))))

static func _read_legends(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return []
	file.close()
	var data: Variant = parser.data
	if not data is Dictionary or not data.get("legends") is Dictionary:
		return []
	return data.legends.values()

static func _runtime_references(runtime: Dictionary) -> Array:
	var refs: Array = []
	if runtime.is_empty():
		return refs
	var player: Variant = runtime.get("player", {})
	if player is Dictionary:
		_collect_inventory_refs(refs, player, "玩家", "玩家", false)
		_add_player_equipment_refs(refs, player)
	var warehouse: Variant = runtime.get("warehouse", {})
	if warehouse is Dictionary:
		for item_id in warehouse:
			if int(warehouse[item_id]) != 0:
				refs.append(_ref(str(item_id), "runtime", "当前存档", "洞府仓库",
					"×%d" % int(warehouse[item_id]), "当前存档洞府仓库", "runtime", "warehouse"))
	var npcs: Variant = runtime.get("npcs", {})
	if npcs is Dictionary:
		for npc in npcs.values():
			if npc is Dictionary:
				_collect_inventory_refs(refs, npc, str(npc.get("name", npc.get("id", "NPC"))), "NPC")
	return refs

static func _add_player_equipment_refs(refs: Array, player: Dictionary) -> void:
	if not player.get("equipment_instances") is Dictionary:
		return
	var equipped_by_instance := {}
	if player.get("equipped") is Dictionary:
		for slot in player.equipped:
			var instance: Variant = player.equipped[slot]
			if instance is String:
				equipped_by_instance[instance] = str(SLOTS.get(slot, slot))
	for instance in player.equipment_instances:
		var item_id: Variant = player.equipment_instances[instance]
		if not item_id is String:
			continue
		var detail := "持有"
		if equipped_by_instance.has(str(instance)):
			detail = "已穿戴 · " + str(equipped_by_instance[str(instance)])
		refs.append(_ref(item_id, "runtime", "当前存档", "玩家装备", detail,
			"当前存档玩家装备", "runtime", str(instance)))

static func _collect_inventory_refs(refs: Array, owner: Dictionary, label: String,
		source_prefix: String, include_equipment := true) -> void:
	if owner.get("inventory") is Dictionary:
		for item_id in owner.inventory:
			if int(owner.inventory[item_id]) != 0:
				refs.append(_ref(str(item_id), "runtime", "当前存档", label + "背包",
					"×%d" % int(owner.inventory[item_id]), "当前存档%s背包" % source_prefix,
					"runtime", "inventory"))
	if include_equipment and owner.get("equipment_instances") is Dictionary:
		for instance in owner.equipment_instances:
			var item_id: Variant = owner.equipment_instances[instance]
			if item_id is String:
				refs.append(_ref(item_id, "runtime", "当前存档", label + "装备实例",
					"持有/可穿戴", "当前存档%s装备" % source_prefix, "runtime", str(instance)))
