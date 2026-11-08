extends Control
signal closed
var report: Dictionary
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	field("Close").pressed.connect(close)
	for key in ["all","cultivation","npc","sect","economy","world","quest"]:field("Tab_"+key).pressed.connect(_category.bind(key))
func bind_data(value: Dictionary) -> void:
	report=value.duplicate(true)
	field("Summary").text="实际闭关 %.2f 日 / 选择 %.2f 日　修为 +%d　年龄 %d\n%s" % [report.elapsed/86400.0,report.requested/86400.0,report.gain,report.age,report.reason if not report.reason.is_empty() else "修为封顶后剩余时间照常推进；境界突破需要手动确认。"]
	var realm: String = preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(report.realm,report.get("route","qi"),GameManager.catalog.tables)
	field("Summary").text+="\n当前境界："+realm
	_category("all")
func _category(key: String) -> void:
	var titles: Dictionary={"cultivation":"修炼","npc":"人物","sect":"宗门","economy":"经济","world":"世界","quest":"任务"}
	var lines: PackedStringArray=[]
	for group in titles:
		if key!="all" and key!=group:continue
		lines.append("【"+titles[group]+"】")
		var entries: Array=report.groups[group]
		if entries.is_empty():lines.append("现有宗门系统暂无按时间演变规则。" if group=="sect" else "本次没有此类实际变化。")
		else:
			for entry in entries:lines.append("• "+str(entry))
		lines.append("")
	field("Details").text="\n".join(lines);field("Details").scroll_to_line(0)
func close() -> void:closed.emit();queue_free()
