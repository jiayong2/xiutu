extends RefCounted
## Deterministic energy accounting. All quantities are integer quanta, not cultivation points.

const RATE_SCALE := 10000
const QUANTA_PER_POINT := 3600 * RATE_SCALE

## A rate in ten-thousandths of a point per game hour converts to quanta per game second.
static func interval_quantity(hourly_rate: int, seconds: int) -> int:
	assert(hourly_rate >= 0 and seconds >= 0)
	return hourly_rate * seconds

static func flow(supply: int, absorption_cap: int, channel_cap: int, refinement_cap: int,
		loss_rate: int, loss_remainder: int = 0) -> Dictionary:
	assert(supply >= 0 and absorption_cap >= 0 and channel_cap >= 0 and refinement_cap >= 0)
	assert(loss_rate >= 0 and loss_rate <= RATE_SCALE and loss_remainder >= 0 and loss_remainder < RATE_SCALE)
	var absorbed: int = mini(supply, absorption_cap)
	var channelled: int = mini(absorbed, channel_cap)
	var processed: int = mini(channelled, refinement_cap)
	var loss_numerator: int = processed * loss_rate + loss_remainder
	var loss: int = loss_numerator / RATE_SCALE
	return {
		"available": supply,
		"absorbed": absorbed,
		"channelled": channelled,
		"processed": processed,
		"unabsorbed": supply - absorbed,
		"channel_return": absorbed - channelled,
		"refinement_return": channelled - processed,
		"refinement_loss": loss,
		"refined": processed - loss,
		"consumed": processed,
		"loss_remainder": loss_numerator % RATE_SCALE,
	}

## A transfer moves existing energy. The unmet amount stays in the source.
static func transfer(source: int, target: int, capacity: int, requested: int) -> Dictionary:
	assert(source >= 0 and target >= 0 and target <= capacity and requested >= 0)
	var moved: int = mini(mini(source, capacity - target), requested)
	return {"source": source - moved, "target": target + moved, "moved": moved}

## Determine each independent rate from the existing equipment and root/foundation inputs.
static func profile(player: Dictionary, route: String, techniques: Dictionary, rules: Dictionary,
		traits: Dictionary) -> Dictionary:
	assert(route in ["qi", "body"])
	var attributes: Dictionary = player.growth.attributes
	var absorption: int
	var channel: int
	if route == "body":
		absorption = int(rules.body_absorption_base) + int(traits.constitution) * int(rules.body_absorption_per_constitution)
		channel = int(attributes.bones) * int(rules.body_channel_per_bone) + int(attributes.physique) * int(rules.body_channel_per_physique)
	else:
		absorption = int(rules.root_absorption_hourly[traits.root_quality])
		channel = int(attributes.meridians) * int(rules.qi_channel_per_meridian)
	var breakthrough_quality: Dictionary = player.growth.get("breakthrough_quality",{})
	channel += int(rules.quality_channel_bonus.get(breakthrough_quality.get(route,""),0))
	var refinement := 0
	var weighted_loss := 0
	var contributors := {}
	for id in player.technique_slots:
		if techniques[id].cultivation_route != route:
			continue
		var rule: Dictionary = rules.techniques[id]
		var capacity: int = int(rule.hourly) + (int(player.techniques[id]) - 1) * int(rule.hourly_step)
		if route == "qi" and rule.element == player.root:
			capacity += int(rules.affinity_refinement_bonus)
		refinement += capacity
		weighted_loss += capacity * int(rule.loss)
		contributors[id] = capacity
	var loss: int = weighted_loss / refinement if refinement > 0 else 0
	if refinement > 0 and route == "qi":
		refinement += int(traits.spirituality) * int(rules.qi_refinement_per_spirituality)
	return {"absorption": absorption, "channel": channel, "refinement": refinement,
		"loss": loss, "techniques": contributors}
