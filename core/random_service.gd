extends RefCounted
var streams: Dictionary = {}

func initialize(seed_value: int) -> void:
	streams.clear()
	for name in ["battle", "loot", "exploration", "world", "spell_affix", "auction"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + int(name.hash())
		streams[name] = rng

func roll(stream: String) -> float:
	return streams[stream].randf()

func integer(stream: String, low: int, high: int) -> int:
	return streams[stream].randi_range(low, high)

func snapshot() -> Dictionary:
	var result := {}
	for name in streams:
		# Strings avoid JSON double precision loss for 64-bit RNG states.
		result[name] = str(streams[name].state)
	return result

func restore(value: Dictionary) -> void:
	for name in streams:
		if value.has(name):
			streams[name].state = int(value[name])
		elif name in ["spell_affix","auction"]:
			streams[name].seed = hash(str(value.battle)+name)
