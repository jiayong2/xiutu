extends RefCounted
const Mental = preload("res://gameplay/character/mental_attributes.gd")
const Cultivation = preload("res://gameplay/cultivation/cultivation_system.gd")

static func npc_lifespan(npc: Dictionary, data: Dictionary) -> int:
	var tier: Dictionary = data.realm_tiers.get("tier_%d" % Cultivation.tier_index(int(npc.realm)), {})
	return maxi(int(npc.get("lifespan", data.prototype.npc_lifespan)), int(tier.get("lifespan", 0)))

## Monthly NPC and economy simulation, independent of UI.
func settle_month(s: Dictionary, data: Dictionary, random: RefCounted, month: int) -> void:
	var rules: Dictionary = data.prototype
	for npc in s.npcs.values():
		var years := int(month / 12) - int(npc.get("introduced_year", 0))
		npc.age = int(npc.get("initial_age", rules.npc_initial_age)) + maxi(0, years)
		if npc.age >= npc_lifespan(npc,data):
			npc.alive = false
		if not npc.alive:
			continue
		if npc.realm > 0:
			npc.cultivation += int(rules.npc_month_gain)
			if npc.realm < 9 and npc.cultivation >= data.realms["qi_" + str(int(npc.realm))].required:
				npc.cultivation -= int(data.realms["qi_" + str(int(npc.realm))].required)
				var previous := int(npc.realm)
				npc.realm += 1
				Mental.advance_npc(npc,previous,data.progression.mental)
		if random.roll("world") < rules.npc_migration_chance and not npc.get("stationary", false):
			npc.location = "town_yunxi" if npc.location == "town_qinglan" else "town_qinglan"
	for town in ["town_qinglan", "town_yunxi"]:
		# Integer basis points keep prices exact across JSON save/load.
		s.prices[town] = roundi(10000 * (rules.price_min + random.roll("world") * (rules.price_max - rules.price_min)))
	s.news.append("第 %s 月：NPC 修炼与城镇供需已结算" % month)
	if s.news.size() > 100:
		s.news.pop_front()
