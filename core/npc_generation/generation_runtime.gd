@tool
extends RefCounted
## UI-free adapter for future world systems. Callers pass a complete config dictionary;
## authoring templates are excluded from the export pack and are not loaded here.
## generate_instances() returns in-memory NPCs with persist="save". It does not write
## data/world/, npc_overrides, or insert into OperationService. Catalog writes stay in
## generation_store.commit. Persistence, if any, is the existing save snapshot.

const Service := preload("res://core/npc_generation/generation_service.gd")
const Model := preload("res://core/npc_definitions.gd")

const PERSIST_SAVE := "save"

static func occupancy(data: Dictionary, context: Dictionary = {}) -> Dictionary:
	var ids := {}
	var names := {}
	var overrides: Dictionary = context.get("overrides", data.get("npc_overrides", {}))
	var roster: Dictionary = Model.roster(data, overrides)
	for id in roster:
		ids[id] = true
		names[str(roster[id].get("name", ""))] = true
	var save_npcs: Dictionary = context.get("save_npcs", {})
	for npc in save_npcs.values():
		if not npc is Dictionary:
			continue
		var npc_id := str(npc.get("id", ""))
		if not npc_id.is_empty():
			ids[npc_id] = true
		var npc_name := str(npc.get("name", ""))
		if not npc_name.is_empty():
			names[npc_name] = true
	for extra in context.get("existing_ids", []):
		var extra_id := str(extra)
		if not extra_id.is_empty():
			ids[extra_id] = true
	for extra in context.get("existing_names", []):
		var extra_name := str(extra)
		if not extra_name.is_empty():
			names[extra_name] = true
	return {
		"overrides": overrides,
		"existing_ids": ids.keys(),
		"existing_names": names.keys(),
	}

static func generate_definitions(raw_config: Dictionary, data: Dictionary, context: Dictionary = {}) -> Dictionary:
	var held := occupancy(data, context)
	var generate_context: Dictionary = context.duplicate(true)
	generate_context.overrides = held.overrides
	generate_context.existing_ids = held.existing_ids
	generate_context.existing_names = held.existing_names
	var result: Dictionary = Service.new().generate(raw_config, data, generate_context)
	result.persist = PERSIST_SAVE
	result.instances = []
	return result

static func materialize(definition: Dictionary, data: Dictionary) -> Dictionary:
	return Model.initial(definition.duplicate(true), data)

static func generate_instances(raw_config: Dictionary, data: Dictionary, context: Dictionary = {}) -> Dictionary:
	var result := generate_definitions(raw_config, data, context)
	var instances: Array = []
	if result.get("ok", false) == true:
		for npc in result.get("npcs", []):
			instances.append(materialize(npc, data))
	result.instances = instances
	result.persist = PERSIST_SAVE
	return result
