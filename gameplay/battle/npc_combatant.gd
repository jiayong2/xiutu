extends RefCounted
## Builds a disposable combat snapshot from a live NPC.
## The live NPC dictionary is never stored or written back.

const Character := preload("res://gameplay/character/character_system.gd")

static func profile_of(npc: Dictionary, data: Dictionary) -> Dictionary:
	var profile: Dictionary = {}
	for definition in data.get("prototype", {}).get("npcs", []):
		if definition is Dictionary and str(definition.get("id", "")) == str(npc.get("id", "")):
			profile = definition.get("profile", {}).duplicate(true)
			break
	if npc.get("profile") is Dictionary:
		profile = npc.profile.duplicate(true)
	return profile

static func stats_of(npc: Dictionary, data: Dictionary) -> Dictionary:
	return Character.new().npc_stats(npc, profile_of(npc, data), data)

## Returns {enemy, stats}. enemy is the mutable battle unit; stats is the
## permanent attribute snapshot used by the shared formulas.
static func build(npc: Dictionary, data: Dictionary) -> Dictionary:
	var profile := profile_of(npc, data)
	var stats := Character.new().npc_stats(npc, profile, data)
	var max_hp := int(stats.get("hp", 0))
	var max_mp := int(stats.get("mp", 0))
	if max_hp < 1 or max_mp < 0:
		return {}
	var learned := {}
	var slots: Array = []
	if npc.get("spells") is Dictionary:
		learned = npc.spells.duplicate(true)
	elif profile.get("spells") is Array:
		for id in profile.spells:
			learned[str(id)] = 1
	if npc.get("spell_slots") is Array:
		slots = npc.spell_slots.duplicate()
	elif profile.get("spells") is Array:
		slots = profile.spells.duplicate()
	var hp := clampi(int(npc.get("hp", max_hp)), 0, max_hp)
	var mp := clampi(int(npc.get("mp", max_mp)), 0, max_mp)
	var enemy := {
		"name": str(npc.get("name", "")),
		"hp": hp,
		"mp": mp,
		"attack": stats.get("attack", 0),
		"defense": stats.get("defense", 0),
		"speed": stats.get("speed", 0),
		"critical": stats.get("critical", data.rules.crit_chance),
		"critical_damage": stats.get("critical_damage", data.rules.crit_multiplier),
		"dodge": stats.get("dodge", 0.0),
		"spells": learned,
		"spell_slots": slots,
		"fortunes": npc.get("fortunes", {}).duplicate(true) if npc.get("fortunes") is Dictionary else {},
		"root": str(profile.get("root", npc.get("root", ""))),
		"realm": int(npc.get("realm", 0)),
		"body_realm": str(profile.get("body_realm", "")),
	}
	return {"enemy": enemy, "stats": stats.duplicate(true)}
