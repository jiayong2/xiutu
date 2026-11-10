extends RefCounted
## Shared direct-damage formula. Kept side-agnostic so player, NPC and monster
## damage all use the same defensive coefficient.

static func direct_damage(attack: float, defense: float, multiplier: float, data: Dictionary) -> int:
	return maxi(1, floori(attack * multiplier * 100.0 / (100.0 + float(data.rules.direct_defense_coefficient) * maxf(0.0, defense))))
