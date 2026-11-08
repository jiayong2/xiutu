extends RefCounted

const Fortunes := preload("res://gameplay/character/player_fortunes.gd")
const Character := preload("res://gameplay/character/character_system.gd")
var world := preload("res://world/world_simulator.gd").new()
var cultivation := preload("res://gameplay/cultivation/cultivation_system.gd").new()
var spirit := preload("res://gameplay/cultivation/spirit_cultivation.gd").new()
## The only writer of absolute world time, including its sub-hour remainder.
func seconds(s: Dictionary) -> int:return int(s.hours)*3600+int(s.get("time_seconds",0))
func advance(s: Dictionary,hours: int,data: Dictionary,random: RefCounted,mode: String="natural") -> Dictionary:
	return advance_seconds(s,hours*3600,data,random,mode)
func advance_seconds(s: Dictionary,duration: int,data: Dictionary,random: RefCounted,mode: String="natural",route: String="qi",goal: int=-1) -> Dictionary:
	assert(duration>=0)
	var started: int=seconds(s)
	var life_end: int=(int(s.player.lifespan)-int(s.initial_age))*int(data.rules.days_year)*int(data.rules.hours_day)*3600
	var target: int=mini(started+duration,maxi(started,life_end))
	var month_seconds: int=calendar_units(data).month_days*int(data.rules.hours_day)*3600
	var before_gain: int=cultivation.progress(s.player,route)
	var months:=0
	var ledger := {"processed":0,"loss":0,"cultivation":0,"nurture":0,"returned":0}
	spirit.initialize(s,data)
	while seconds(s)<target:
		var now: int=seconds(s)
		var boundary: int=(int(now/month_seconds)+1)*month_seconds
		var finish: int=Fortunes.next_expiry(s.player,mini(target,boundary))
		var step := spirit.plan(s,mode,route,data,cultivation)
		if not step.is_empty() or not spirit.environment_is_stable(s,data):
			finish=mini(finish,(int(now/3600)+1)*3600)
		if goal>=0:
			var exact: int=spirit.seconds_to_goal(step,finish-now)
			if exact>=0:
				finish=now+exact
		var amounts := spirit.apply(s,step,finish-now,route,data,cultivation)
		for key in amounts:
			ledger[key]+=amounts[key]
		s.hours=int(finish/3600);s.time_seconds=finish%3600
		if Fortunes.expire(s.player,finish):
			var caps := Character.new().stats(s.player,data)
			for key in ["hp","mp","blood"]:
				s.player[key] = mini(int(s.player[key]),int(caps[key]))
		if s.time_seconds==0 and (not step.is_empty() or not spirit.environment_is_stable(s,data)):
			spirit.settle_hour(s,data)
		if finish==boundary:
			_settle_month(s,data,random,int(boundary/month_seconds));months+=1
		if goal>=0 and cultivation.progress(s.player,route)>=goal:
			break
	s.player.age=projected_age(s,0,data)
	return {"start":started,"end":seconds(s),"elapsed":seconds(s)-started,"gain":cultivation.progress(s.player,route)-before_gain,"route":route,"months":months,"ledger":ledger,"interrupted":target<started+duration,"reason":"寿元已尽" if seconds(s)>=life_end and duration>0 else ""}
func _settle_month(s: Dictionary,data: Dictionary,random: RefCounted,month: int) -> void:
	for shop in data.shops.values():
		if shop.restock:
			for id in shop.stock:
				if not id.begins_with("book_") and id!="pill_foundation":s.stocks[shop.id][id]=int(shop.stock[id])
	if s.formation:
		if s.player.spirit_stones>=data.rules.formation_upkeep:s.player.spirit_stones-=int(data.rules.formation_upkeep)
		else:s.formation=false
	world.settle_month(s,data,random,month)
func calendar_units(data: Dictionary) -> Dictionary:
	return {"day_hours":int(data.rules.hours_day),"month_days":int(data.rules.days_year/12),"year_days":int(data.rules.days_year)}
func projected_age(s: Dictionary,days: int,data: Dictionary) -> int:
	return int(s.initial_age)+int((seconds(s)+days*data.rules.hours_day*3600)/(data.rules.hours_day*data.rules.days_year*3600))
func format_date(s: Dictionary,data: Dictionary) -> String:
	var total: int=seconds(s)
	var day: int=total/(int(data.rules.hours_day)*3600)
	var year_days: int=int(data.rules.days_year)
	var month_days: int=calendar_units(data).month_days
	return "玄灵历%d年%d月%d日 · %02d:%02d" % [int(day/year_days)+1,int((day%year_days)/month_days)+1,day%month_days+1,int(total/3600)%int(data.rules.hours_day),int(total/60)%60]
func validate_rules(rules: Dictionary) -> String:
	var speed: Variant=rules.get("game_seconds_per_real_second")
	if not (speed is float or speed is int) or not is_finite(float(speed)) or speed<=0 or floorf(speed)!=speed:
		return "时间配置倍率无效"
	return ""
