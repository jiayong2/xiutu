extends RefCounted
# One palette for all combat-log BBCode. Roles come from typed records, never words.
const COLORS={
	"normal":"#D5DFE4","damage":"#F07878","heal":"#78C995","critical":"#F4C766",
	"mana":"#82BCE5","buff":"#86CDB3","debuff":"#C8A1E8","avoidance":"#D6C990",
	"system":"#A4B7C1","victory":"#F0D597"
}
const Status = preload("res://gameplay/battle/battle_status.gd")
const LEGACY_NAMES := {"guard":"护体","burn":"灼烧","wet":"潮湿"}
static func status_name(id: String, definitions: Dictionary) -> String:
	return definitions.get(id.trim_prefix("player_"),{}).get("name",LEGACY_NAMES.get(id,id))
static func escape_text(value: Variant) -> String:
	var parts: PackedStringArray=[]
	for character in str(value):parts.append("[lb]" if character=="[" else "[rb]" if character=="]" else character)
	return "".join(parts)
static func colored(value: Variant,role: String="normal") -> String:
	return "[color=%s]%s[/color]" % [COLORS.get(role,COLORS.normal),escape_text(value)]
static func system_message(message: String) -> String:
	return "" if message.is_empty() or message=="操作成功" else colored(message,"system")
static func record(entry: Dictionary, definitions: Dictionary = {}) -> String:
	var target: String=escape_text(entry.get("target",""))
	match str(entry.get("type","")):
		"round":return colored("── 第 %d 回合 ──" % int(entry.turn),"system")
		"action":
			return "%s使用%s。" % [escape_text(entry.actor),colored(entry.label,"mana" if entry.kind=="spell" else "normal")]
		"hp":
			var amount: int=int(entry.amount)
			var role: String="heal" if amount>0 else "critical" if entry.get("critical",false) else "damage"
			var source: String=str(entry.get("source_spell",""))
			var phrase: String="恢复" if amount>0 else "受到"
			if not source.is_empty():phrase=("通过"+colored(source,"mana")+"恢复") if amount>0 else ("受到"+colored(source,"mana")+"造成的")
			var number: String=("暴击 " if entry.get("critical",false) and amount<0 else "")+str(absi(amount))
			return "%s%s%s%s（生命 %d → %d）。" % [target,phrase,colored(number,role),"点生命" if amount>0 else "点伤害",maxi(0,int(entry.before)),maxi(0,int(entry.after))]

		"mp":
			return "%s%s%s%s（%d → %d）。" % [target,"恢复" if entry.amount>0 else "消耗",colored(absi(int(entry.amount)),"mana"),colored("点灵气","mana"),int(entry.before),int(entry.after)]
		"status":
			var role: String = "buff" if entry.id in Status.PLAYER or entry.id=="enemy_shield" else "debuff"
			var change: String={"apply":"获得","refresh":"刷新","tick":"状态","expire":"结束"}.get(entry.change,"状态")
			return "%s%s%s%s。" % [target,change,colored(status_name(entry.id,definitions),role),"（剩余%d回合）" % int(entry.turns) if entry.change!="expire" else ""]
		"defend":return "%s进入%s。" % [target,colored("防御","buff")]
		"avoidance":
			# Only display when a real producer supplies this outcome. Defence != block.
			var outcome: String={"dodge":"闪避","block":"格挡"}.get(entry.get("outcome",""),"")
			return "%s%s。" % [target,colored(outcome,"avoidance")] if not outcome.is_empty() else ""
		"result":
			match str(entry.result):
				"win":return colored("战斗胜利","victory")+"，战利品已结算。"
				"lose":return colored("战斗失败，已返回青岚镇。","system")
				"escape":return colored("逃跑成功，无战利品。","system")
		"system":return colored(entry.get("text",""),"system")
		"legacy":return escape_text(entry.get("text",""))
	return ""
static func render(entries: Array,legacy: Array=[],message: String="",definitions: Dictionary={}) -> String:
	var lines: PackedStringArray=[]
	var has_result:=false
	if entries.is_empty():
		for line in legacy:lines.append(escape_text(line))
	else:
		for entry in entries:
			var line: String=record(entry,definitions)
			if not line.is_empty():lines.append(line)
			has_result=has_result or entry.get("type","")=="result"
	if lines.is_empty():lines.append(colored("遭遇已锁定。准备好后开始战斗。","system"))
	var extra: String=system_message(message)
	if not extra.is_empty() and not has_result:lines.append(extra)
	return "[color=%s]%s[/color]" % [COLORS.normal,"\n".join(lines)]
