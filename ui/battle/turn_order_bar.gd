extends Control
signal current_changed(unit_id: String)
# IDs arrive in real execution order (earliest first). Never sort by UI position or faction.
var action_queue: Array=[]
var upcoming_round: Array=[]
var unit_data: Dictionary={}
var portraits: Dictionary={}
var layout_tween: Tween
var revision := 0
var animation_speed := 1.0
var current_id := ""
var caption := "行动中"
var target_width := 200.0
const PORTRAIT=preload("res://ui/battle/turn_portrait.tscn")
func _ready() -> void:
	for child in $Track.get_children():$Track.remove_child(child);child.queue_free()
	$Overflow.pressed.connect(_show_queue)
func set_queue(entries: Array,queue: Array,next_round: Array=[],animate: bool=true) -> Tween:
	for child in $Track.get_children():
		if child not in portraits.values():$Track.remove_child(child);child.queue_free()
	revision+=1
	if layout_tween!=null and layout_tween.is_valid():layout_tween.kill()
	unit_data.clear()
	for unit in entries:unit_data[unit.id]=unit.duplicate(true)
	action_queue=[]
	for id in queue:
		if unit_data.has(id) and unit_data[id].hp>0 and id not in action_queue:action_queue.append(id)
	upcoming_round=next_round.duplicate()
	current_id=""
	current_changed.emit(current_id)
	var shown: Array=action_queue.slice(0,9)
	target_width=650.0 if action_queue.size()>9 else clampf(32+shown.size()*48+maxi(0,shown.size()-1)*16,200,650)
	layout_tween=create_tween().set_parallel(true).set_speed_scale(animation_speed)
	layout_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var duration: float=.5 if animate else 0.0
	layout_tween.tween_property($Track,"size:x",target_width,duration)
	layout_tween.tween_property($CurrentMarker,"position:x",target_width+12,duration)
	layout_tween.tween_property($Overflow,"position:x",target_width+158,duration)
	$CurrentMarker.text="◀ "+caption
	$Overflow.visible=action_queue.size()>9
	$Overflow.text="全部 %d" % action_queue.size()
	for id in portraits.keys():
		if id in action_queue:continue
		var departing: Control=portraits[id]
		portraits.erase(id)
		departing.name="Leaving_"+str(revision)+"_"+str(id)
		layout_tween.tween_property(departing,"modulate:a",0.0,duration)
		layout_tween.tween_callback(departing.queue_free).set_delay(duration)
	for id in action_queue:
		var fresh: bool=not portraits.has(id)
		if fresh:
			var portrait: Button=PORTRAIT.instantiate();portrait.name=id;$Track.add_child(portrait);portraits[id]=portrait
		var portrait: Button=portraits[id]
		portrait.configure(unit_data[id],id in upcoming_round,false)
		portrait.modulate=Color.WHITE
		portrait.visible=id in shown
		if id not in shown:continue
		var target:=Vector2(target_width-16-48-shown.find(id)*64,12)
		if fresh:portrait.position=target
		layout_tween.tween_property(portrait,"position",target,duration)
	if not animate:
		layout_tween.custom_step(1.0)
		_finish(revision)
	else:layout_tween.finished.connect(_finish.bind(revision))
	return layout_tween
func _finish(expected_revision: int) -> void:
	if revision!=expected_revision:return
	current_id=str(action_queue[0]) if not action_queue.is_empty() else ""
	$CurrentMarker.text="◀ "+caption if not current_id.is_empty() else "暂无行动"
	for id in portraits:portraits[id].configure(unit_data[id],id in upcoming_round,id==current_id)
	$CurrentMarker.tooltip_text=str(unit_data.get(current_id,{}).get("name",""))
	current_changed.emit(current_id)
func set_caption(value: String) -> void:
	caption=value
	$CurrentMarker.text="◀ "+caption if not current_id.is_empty() else "暂无行动"
func set_speed(value: float) -> void:
	animation_speed=value
	if layout_tween!=null and layout_tween.is_valid():layout_tween.set_speed_scale(value)
func snap_latest() -> void:
	if layout_tween!=null and layout_tween.is_valid():layout_tween.custom_step(10.0)
	_finish(revision)
func _show_queue() -> void:
	var popup:=PopupMenu.new();add_child(popup)
	for index in range(action_queue.size()):
		var id: String=action_queue[index]
		popup.add_item("%d. %s%s" % [index+1,unit_data[id].name,"（下轮）" if id in upcoming_round else ""])
	popup.popup_hide.connect(popup.queue_free)
	popup.position=Vector2i($Overflow.global_position+Vector2(0,48));popup.popup()
func _exit_tree() -> void:
	if layout_tween!=null and layout_tween.is_valid():layout_tween.kill()
