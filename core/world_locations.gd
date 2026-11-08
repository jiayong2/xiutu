@tool
extends RefCounted

const BASE_NAMES := {
	"town_qinglan":"青岚镇", "cave_qinglan":"青岚小洞府",
	"area_qinglan_outskirts":"青岚山外围", "town_yunxi":"云溪城"
}

static func names(data: Dictionary) -> Dictionary:
	var result := {}
	for id in data.spirit_flow.locations:
		result[id] = BASE_NAMES.get(id,id)
	for sect in data.prototype.sects:
		var residence: Dictionary = sect.get("residence", {})
		if not residence.is_empty():
			result[residence.location_id] = residence.name
	return result
