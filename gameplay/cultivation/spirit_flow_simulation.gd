extends RefCounted
## Shared reservoir rules and isolated developer trial.
const Flow := preload("res://gameplay/cultivation/spirit_flow.gd")
const CONCENTRATION_NAMES := ["灵气枯竭","灵气稀薄","灵气平常","灵气充裕","灵气浓郁","灵气极盛","灵气化雾"]

static func validate(rules: Dictionary, technique_table: Dictionary, roots: Array) -> String:
	if rules.get("schema_version") != 1 or rules.get("rate_scale") != Flow.RATE_SCALE:
		return "不支持的试算配置版本或精度"
	for key in ["default_aptitude","qi_channel_per_meridian","qi_refinement_per_spirituality",
			"body_absorption_base","body_absorption_per_constitution","body_channel_per_bone",
			"body_channel_per_physique","affinity_refinement_bonus","formation_hourly"]:
		if not _whole(rules.get(key),0,200000):
			return "无效速率或资质参数：" + key
	if rules.default_aptitude>100:
		return "默认资质必须在 0–100"
	for key in ["qi_per_cultivation","qi_per_nurture","stone_points"]:
		if not _whole(rules.get(key),1,10000):
			return "无效换算参数：" + key
	for key in ["draw_hourly","root_absorption_hourly","quality_channel_bonus","environments","techniques","nurture_share","locations"]:
		if not rules.get(key) is Dictionary:
			return "缺少试算配置：" + key
	for key in ["natural","practice","retreat"]:
		if not _whole(rules.draw_hourly.get(key),1,200000):
			return "无效引气速率：" + key
	var previous := 0
	for key in ["refinement","balance","nurture"]:
		if not _whole(rules.nurture_share.get(key),previous+1,9999):
			return "温养分配比例必须递增并介于 0% 与 100%"
		previous = int(rules.nurture_share[key])
	for id in ["town_qinglan","town_yunxi","area_qinglan_outskirts","cave_qinglan"]:
		if not rules.locations.get(id) is String or not rules.environments.has(rules.locations[id]):
			return "地点未配置灵气环境：" + id
	for key in ["ordinary","fine","superior","heavenly"]:
		if not _whole(rules.root_absorption_hourly.get(key),1,200000):
			return "无效灵根吸纳：" + key
	if rules.get("default_root_quality") not in ["ordinary","fine","superior","heavenly"]:
		return "无效默认灵根品质"
	for key in ["base","middle","high"]:
		if not _whole(rules.quality_channel_bonus.get(key),0,200000):
			return "无效突破品质运转加成：" + key
	for id in technique_table:
		var row: Variant = rules.techniques.get(id)
		if not row is Dictionary or (row.get("element") != "" and row.get("element") not in roots):
			return "无效功法炼化配置：" + id
		if not _whole(row.get("hourly"),1,200000) or not _whole(row.get("hourly_step"),0,200000) or not _whole(row.get("loss"),0,10000):
			return "无效功法炼化参数：" + id
	for id in ["town","cave","advanced_cave","sparse","rich","starved"]:
		var row: Variant = rules.environments.get(id)
		if not row is Dictionary or not _whole(row.get("capacity"),1,10000):
			return "无效环境容量：" + id
		if not _whole(row.get("baseline"),1,row.capacity) or not _whole(row.get("initial",row.baseline),0,row.capacity):
			return "无效环境储量：" + id
		for key in ["recovery_hourly","diffusion_hourly","access","surrounding"]:
			if not _whole(row.get(key),0,200000):
				return "无效环境流量：" + id + "/" + key
	var thresholds: Variant = rules.get("concentration_thresholds")
	if not thresholds is Array or thresholds.size() != 6:
		return "需要六个浓度分级阈值"
	var last := 0
	for value in thresholds:
		if not _whole(value,last+1,10000):
			return "浓度阈值必须递增，且不得超过 10000"
		last = int(value)
	return ""

static func _whole(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(float(value)) and value >= lower and value <= upper

static func concentration(stock: int, capacity: int, rules: Dictionary) -> String:
	var grade := 0
	for threshold in rules.concentration_thresholds:
		if stock * Flow.RATE_SCALE >= capacity * int(threshold):
			grade += 1
	return CONCENTRATION_NAMES[grade]

static func draw_rate(environment: Dictionary, rules: Dictionary, mode: String, reference: int) -> int:
	if mode=="none":
		return 0
	var base: int = int(rules.draw_hourly[mode])*int(environment.access)/Flow.RATE_SCALE
	var ratio: int = reference*Flow.RATE_SCALE/(int(environment.baseline)*Flow.QUANTA_PER_POINT)
	return base*ratio/Flow.RATE_SCALE

static func reservoir_changes(pool: Dictionary, environment: Dictionary, rules: Dictionary, formation: bool) -> Dictionary:
	var capacity: int = int(environment.capacity)*Flow.QUANTA_PER_POINT
	var baseline: int = int(environment.baseline)*Flow.QUANTA_PER_POINT
	var stock: int = int(pool.stock)+int(pool.get("pending",0))
	var diffused: int = mini(maxi(0,stock-baseline),int(environment.diffusion_hourly)*3600)
	stock -= diffused
	var recovered: int = mini(maxi(0,baseline-stock),int(environment.recovery_hourly)*3600)
	var moved: int = mini(mini(int(pool.surrounding)+diffused,capacity-stock-recovered),int(rules.formation_hourly)*3600) if formation else 0
	return {"diffused":diffused,"recovered":recovered,"transferred":moved}

static func settle_reservoir(pool: Dictionary, environment: Dictionary, rules: Dictionary, formation: bool) -> Dictionary:
	var changes := reservoir_changes(pool,environment,rules,formation)
	pool.stock += int(pool.get("pending",0)) + int(changes.recovered) + int(changes.transferred) - int(changes.diffused)
	pool.surrounding += int(changes.diffused) - int(changes.transferred)
	pool.pending = 0
	pool.reference=pool.stock
	return changes

static func simulate(profile: Dictionary, environment: Dictionary, rules: Dictionary,
		mode: String, seconds: int, stone_count: int = 0, formation: bool = false,
		focus: String = "balance") -> Dictionary:
	var unit: int = Flow.QUANTA_PER_POINT
	var capacity: int = int(environment.capacity) * unit
	var baseline: int = int(environment.baseline) * unit
	var stock: int = int(environment.get("initial",environment.baseline)) * unit
	var surrounding: int = int(environment.surrounding) * unit
	var release := Flow.transfer(stone_count * int(rules.stone_points) * unit,stock,capacity,
		stone_count * int(rules.stone_points) * unit)
	var result := {"start":stock,"surrounding_start":surrounding,"released":release.moved,
		"stone_unreleased":release.source,"recovered":0,"transferred":0,"diffused":0,
		"available":0,"absorbed":0,"channelled":0,"processed":0,"unabsorbed":0,
		"channel_return":0,"refinement_return":0,"refinement_loss":0,"refined":0,"consumed":0}
	stock = release.target
	var pool := {"stock":stock,"surrounding":surrounding,"pending":0,"reference":stock}
	var remaining := seconds
	var remainder := 0
	while remaining > 0:
		var segment := mini(remaining,3600)
		var draw_limit: int = draw_rate(environment,rules,mode,pool.reference)*segment
		var ledger := Flow.flow(mini(int(pool.stock),draw_limit),Flow.interval_quantity(profile.absorption,segment),
			Flow.interval_quantity(profile.channel,segment),Flow.interval_quantity(profile.refinement,segment),
			profile.loss,remainder)
		remainder = ledger.loss_remainder
		pool.stock -= int(ledger.consumed)
		for key in ledger:
			if key != "loss_remainder":
				result[key] += ledger[key]
		if segment==3600:
			var changes := settle_reservoir(pool,environment,rules,formation)
			for key in changes:
				result[key]+=changes[key]
		remaining -= segment
	result["end"] = pool.stock
	result["surrounding_end"] = pool.surrounding
	result["grade"] = concentration(pool.stock,capacity,rules)
	var nurtured: int = int(result.refined)*int(rules.nurture_share[focus])/Flow.RATE_SCALE
	result["nurture"] = float(nurtured)/float(unit*int(rules.qi_per_nurture))
	result["cultivation"] = float(int(result.refined)-nurtured) / float(unit * int(rules.qi_per_cultivation))
	return result
