extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")
## Applies the shared spirit ledger to the operation service's candidate state.
const Flow := preload("res://gameplay/cultivation/spirit_flow.gd")
const Reservoir := preload("res://gameplay/cultivation/spirit_flow_simulation.gd")
const Growth := preload("res://gameplay/cultivation/cultivation_system.gd")
const Mental = preload("res://gameplay/character/mental_attributes.gd")
const UNIT := Flow.QUANTA_PER_POINT
const BPS := Flow.RATE_SCALE
const CAPACITY_LIMIT := 1000000000000000

func environment(s: Dictionary, id: String, rules: Dictionary) -> Dictionary:
	var profile: String = rules.locations[id]
	if id=="cave_qinglan" and s.cave_level>1:
		profile = "advanced_cave"
	return rules.environments[profile]

func initialize(s: Dictionary, data: Dictionary) -> void:
	var rules: Dictionary = data.spirit_flow
	var p: Dictionary = s.player
	if not s.has("spirit"):
		var pools := {}
		for id in rules.locations:
			var row := environment(s,id,rules)
			var stock: int = int(row.get("initial",row.baseline))*UNIT
			pools[id]={"stock":stock,"reference":stock,"surrounding":int(row.surrounding)*UNIT,"pending":0}
		var progress := {}
		for route in ["qi","body"]:
			var old_fraction: int = int(s.get("cultivation_fraction",0)) if route=="qi" else int(p.growth.get("body_fraction",0))
			var old_nurture: int = int(p.growth.get("nurture_fraction",{}).get(route,0))
			progress[route] = {
				"cultivation": old_fraction*int(rules.qi_per_cultivation)/int(data.rules.hours_day),
				"nurture": old_nurture*10*int(rules.qi_per_nurture),
				"loss_carry":0,"split_carry":0,
			}
		s.spirit={"pools":pools,"progress":progress,"hour_attributes":p.growth.attributes.duplicate()}
	for key in Mental.KEYS:
		if not s.spirit.hour_attributes.has(key):
			s.spirit.hour_attributes[key] = p.growth.attributes[key]
	s.erase("cultivation_fraction")
	p.growth.erase("body_fraction")
	p.growth.erase("nurture_fraction")

func validate(s: Dictionary, data: Dictionary) -> String:
	if not s.has("spirit"):
		return ""
	var spirit: Variant = s.spirit
	if not spirit is Dictionary or not spirit.get("pools") is Dictionary or not spirit.get("progress") is Dictionary or not spirit.get("hour_attributes") is Dictionary:
		return "灵气存档结构无效"
	var rules: Dictionary = data.spirit_flow
	for id in rules.locations:
		var pool: Variant = spirit.pools.get(id)
		var capacity: int = int(environment(s,id,rules).capacity)*UNIT
		if not pool is Dictionary:
			return "缺少地点灵气池：" + id
		for key in ["stock","reference","pending","surrounding"]:
			if not _integer(pool.get(key),CAPACITY_LIMIT if key=="surrounding" else capacity):
				return "地点灵气数量无效：" + id
		if pool.stock+pool.pending>capacity:
			return "地点灵气超过容量：" + id
	for route in ["qi","body"]:
		var partial: Variant = spirit.progress.get(route)
		if not partial is Dictionary:
			return "缺少灵气成长进度"
		if not _integer(partial.get("cultivation"),UNIT*int(rules.qi_per_cultivation)-1) or not _integer(partial.get("nurture"),_nurture_cost(data)-1):
			return "灵气成长余量无效"
		if not _integer(partial.get("loss_carry"),BPS-1) or not _integer(partial.get("split_carry"),BPS-1) or not _integer(partial.get("fortune_carry",0),99):
			return "灵气换算余量无效"
	for key in ["qi_sea","meridians","bones","physique"]:
		if not _integer(spirit.hour_attributes.get(key),int(s.player.growth.attributes[key])):
			return "小时根基快照无效"
	for key in Mental.KEYS:
		if spirit.hour_attributes.has(key) and not _integer(spirit.hour_attributes[key],int(s.player.growth.attributes.get(key,data.progression.mental.initial[key]))):
			return "小时神识根基快照无效"
	return ""

func _integer(value: Variant, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value==floor(float(value)) and value>=0 and value<=upper

func _nurture_cost(data: Dictionary) -> int:
	return UNIT*int(data.spirit_flow.qi_per_nurture)*int(data.progression.nurture_per_point)

func grade(s: Dictionary, id: String, data: Dictionary) -> String:
	if not s.spirit.pools.has(id):
		return "未开放灵气池"
	var rules: Dictionary = data.spirit_flow
	var pool: Dictionary = s.spirit.pools[id]
	return Reservoir.concentration(int(pool.stock)+int(pool.pending),int(environment(s,id,rules).capacity)*UNIT,rules)

func stone_capacity(s: Dictionary, data: Dictionary) -> int:
	var id: String = s.player.location
	if not s.spirit.pools.has(id):
		return 0
	var pool: Dictionary = s.spirit.pools[id]
	var capacity: int = int(environment(s,id,data.spirit_flow).capacity)*UNIT
	return (capacity-int(pool.stock)-int(pool.pending))/(UNIT*int(data.spirit_flow.stone_points))

func release_stones(s: Dictionary, count: int, data: Dictionary) -> String:
	if count<=0 or count>s.player.spirit_stones:
		return "灵石数量不足或无效"
	if count>stone_capacity(s,data):
		return "当前环境没有足够空间释放这些灵石"
	var pool: Dictionary = s.spirit.pools[s.player.location]
	s.player.spirit_stones-=count
	pool.stock+=count*int(data.spirit_flow.stone_points)*UNIT
	pool.reference=pool.stock
	return ""

func settle_hour(s: Dictionary, data: Dictionary) -> void:
	var rules: Dictionary = data.spirit_flow
	for id in rules.locations:
		Reservoir.settle_reservoir(s.spirit.pools[id],environment(s,id,rules),rules,s.formation and id=="cave_qinglan")
	s.spirit.hour_attributes=s.player.growth.attributes.duplicate()

func environment_is_stable(s: Dictionary, data: Dictionary) -> bool:
	var rules: Dictionary = data.spirit_flow
	if s.spirit.hour_attributes!=s.player.growth.attributes:
		return false
	for id in rules.locations:
		var pool: Dictionary = s.spirit.pools[id]
		var row := environment(s,id,rules)
		if pool.pending!=0 or pool.reference!=pool.stock:
			return false
		var changes := Reservoir.reservoir_changes(pool,row,rules,s.formation and id=="cave_qinglan")
		if changes.recovered!=0 or changes.transferred!=changes.diffused:
			return false
	return true

func plan(s: Dictionary, mode: String, route: String, data: Dictionary, cultivation: RefCounted) -> Dictionary:
	if mode=="none" or not s.spirit.pools.has(s.player.location):
		return {}
	var p: Dictionary = s.player
	var rules: Dictionary = data.spirit_flow
	var progress: Dictionary = s.spirit.progress[route]
	var cost: int = UNIT*int(rules.qi_per_cultivation)
	var nurture_cost: int = _nurture_cost(data)
	var efficiency := maxi(1,100 + Fortunes.modifier(p,"cultivation_gain","法修" if route == "qi" else "体修"))
	var remaining: int = maxi(0,(cultivation.requirement(p,route,data)-cultivation.progress(p,route))*cost-int(progress.cultivation))
	var work: int = maxi(0,remaining*100-int(progress.get("fortune_carry",0)))
	var cultivation_need: int = (work + efficiency - 1) / efficiency
	var points_to_cap := 0
	var cap: int = cultivation.attribute_cap(p,route,data)
	for key in Growth.GROWTH_ATTRIBUTES[route]:
		points_to_cap=maxi(points_to_cap,cap-int(p.growth.attributes[key]))
	if route=="qi":
		for key in Mental.KEYS:
			points_to_cap=maxi(points_to_cap,Mental.cap(key,cap,data.progression)-int(p.growth.attributes[key]))
	var nurture_need: int = maxi(0,points_to_cap*nurture_cost-int(progress.nurture))
	if cultivation_need==0 and nurture_need==0:
		return {}
	var pool: Dictionary = s.spirit.pools[p.location]
	var draw: int = Reservoir.draw_rate(environment(s,p.location,rules),rules,mode,pool.reference)
	if pool.stock==0 or draw==0:
		return {}
	var profile_player: Dictionary = p.duplicate()
	profile_player.growth=p.growth.duplicate()
	profile_player.growth.attributes=s.spirit.hour_attributes.duplicate()
	profile_player.growth.attributes.meridians += Fortunes.modifier(p,"stat","meridians","fixed")
	var profile := Flow.profile(profile_player,route,data.techniques,rules,{
		"root_quality":p.traits.root_quality,"constitution":p.traits.aptitudes.constitution,
		"spirituality":p.traits.aptitudes.spirituality})
	var rate: int = mini(mini(draw,profile.absorption),mini(profile.channel,profile.refinement))
	if rate==0 or profile.loss>=BPS:
		return {}
	return {"draw":draw,"profile":profile,"rate":rate,
		"stock":pool.stock,"cultivation_need":cultivation_need,"nurture_need":nurture_need,
		"cost":cost,"efficiency":efficiency,"remaining":remaining,"nurture_cost":nurture_cost,"share":int(rules.nurture_share[p.growth.focus[route]]),
		"loss_carry":progress.loss_carry,"split_carry":progress.split_carry}

func _allocation(step: Dictionary, gross: int) -> Dictionary:
	var loss_numerator: int = gross*int(step.profile.loss)+int(step.loss_carry)
	var loss: int = loss_numerator/BPS
	var refined: int = gross-loss
	var split_numerator: int = refined*int(step.share)+int(step.split_carry)
	var nurture: int = split_numerator/BPS
	return {"loss":loss,"loss_carry":loss_numerator%BPS,"split_carry":split_numerator%BPS,
		"cultivation":refined-nurture,"nurture":nurture}

func seconds_to_goal(step: Dictionary, seconds: int) -> int:
	if step.is_empty() or _allocation(step,mini(int(step.stock),int(step.rate)*seconds)).cultivation<step.cultivation_need:
		return -1
	var low := 1
	var high := seconds
	while low<high:
		var mid: int=(low+high)/2
		if _allocation(step,mini(int(step.stock),int(step.rate)*mid)).cultivation>=step.cultivation_need:
			high=mid
		else:
			low=mid+1
	return low

func apply(s: Dictionary, step: Dictionary, seconds: int, route: String, data: Dictionary, cultivation: RefCounted) -> Dictionary:
	if step.is_empty():
		return {}
	var pool: Dictionary = s.spirit.pools[s.player.location]
	var gross: int = mini(int(step.stock),int(step.rate)*seconds)
	var allocation := _allocation(step,gross)
	if allocation.cultivation>=step.cultivation_need and allocation.nurture>=step.nurture_need:
		var low := 0
		var high := gross
		while low<high:
			var mid: int=(low+high)/2
			var attempt := _allocation(step,mid)
			if attempt.cultivation>=step.cultivation_need and attempt.nurture>=step.nurture_need:
				high=mid
			else:
				low=mid+1
		gross=low
		allocation=_allocation(step,gross)
	var cultivation_energy: int = mini(allocation.cultivation,step.cultivation_need)
	var nurture_energy: int = mini(allocation.nurture,step.nurture_need)
	var recycled: int = gross-int(allocation.loss)-cultivation_energy-nurture_energy
	pool.stock-=gross
	pool.pending+=recycled
	var progress: Dictionary = s.spirit.progress[route]
	progress.loss_carry=allocation.loss_carry
	progress.split_carry=allocation.split_carry
	var work: int = cultivation_energy*int(step.efficiency)+int(progress.get("fortune_carry",0))
	var converted: int = mini(int(step.remaining),work/100)
	if step.efficiency != 100 or progress.has("fortune_carry"):
		progress.fortune_carry = work%100 if converted < step.remaining else 0
	var total: int = int(progress.cultivation)+converted
	var gain: int = total/int(step.cost)
	progress.cultivation=total%int(step.cost)
	if route=="qi":
		s.player.cultivation+=gain
	else:
		s.player.growth.body_cultivation+=gain
	total=int(progress.nurture)+nurture_energy
	gain=total/int(step.nurture_cost)
	progress.nurture=total%int(step.nurture_cost)
	var cap: int = cultivation.attribute_cap(s.player,route,data)
	for key in Growth.GROWTH_ATTRIBUTES[route]:
		s.player.growth.attributes[key]=mini(cap,int(s.player.growth.attributes[key])+gain)
	if route=="qi":
		for key in Mental.KEYS:
			s.player.growth.attributes[key]=mini(Mental.cap(key,cap,data.progression),int(s.player.growth.attributes[key])+gain)
	return {"processed":gross,"loss":allocation.loss,"cultivation":cultivation_energy,"nurture":nurture_energy,"returned":recycled}

func hourly_estimate(s: Dictionary, mode: String, route: String, data: Dictionary, cultivation: RefCounted) -> Vector2:
	var step := plan(s,mode,route,data,cultivation)
	if step.is_empty():
		return Vector2.ZERO
	var value := _allocation(step,mini(int(step.stock),int(step.rate)*3600))
	return Vector2(float(mini(value.cultivation,step.cultivation_need))/step.cost,
		float(mini(value.nurture,step.nurture_need))/(UNIT*int(data.spirit_flow.qi_per_nurture)))

func nurture_points(s: Dictionary, route: String, data: Dictionary) -> float:
	return float(s.spirit.progress[route].nurture)/(UNIT*int(data.spirit_flow.qi_per_nurture))
