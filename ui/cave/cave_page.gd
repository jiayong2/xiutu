extends Control
signal navigate(destination: String)
signal action_requested(action: String,args: Dictionary)
signal selection_changed(saved: Dictionary)
var service: RefCounted
var state: Dictionary
var data: Dictionary
var tab: String="Overview"
var plot_index: int=0
var seed: String=""
var recipe: String=""
var preview: Dictionary={}
var binding:=false
var target_mode:=false
var retreat_route := "qi"
var retreat_busy:=false
var retreat_request_id:=Crypto.new().generate_random_bytes(12).hex_encode()
func field(key: String) -> Node:return find_child(key,true,false)
func _ready() -> void:
	field("Back").pressed.connect(func():navigate.emit("地点场景"))
	for pair in [["OverviewTab","Overview"],["RetreatTab","Retreat"],["FieldsTab","Fields"],["AlchemyTab","Alchemy"],["RetreatCardEnter","Retreat"],["FieldsCardEnter","Fields"],["AlchemyCardEnter","Alchemy"],["Warehouse","WarehousePage"],["WarehouseBack","Overview"]]:
		field(pair[0]).pressed.connect(_tab.bind(pair[1]))
	for key in ["Years","Months","Days"]:
		field(key).value_changed.connect(func(_value: float):_preview())
		field(key+"Plus").pressed.connect(_adjust.bind(key,1))
		field(key+"Minus").pressed.connect(_adjust.bind(key,-1))
	for pair in [["OneDay",0,0,1],["TenDays",0,0,10],["OneMonth",0,1,0],["ThreeMonths",0,3,0],["OneYear",1,0,0],["TenYears",10,0,0]]:
		field(pair[0]).pressed.connect(_duration.bind(pair[1],pair[2],pair[3]))
	field("TargetRetreat").toggled.connect(func(value: bool):target_mode=value;_preview())
	field("RetreatRoute").item_selected.connect(_choose_retreat_route)
	field("StartRetreat").pressed.connect(_start_retreat)
	field("FieldAction").pressed.connect(_field_action)
	field("Craft").pressed.connect(func():
		if not field("Craft").disabled:action_requested.emit("craft",{"id":recipe}))
	field("Formation").pressed.connect(func():action_requested.emit("formation",{}))
	field("UpgradeCave").pressed.connect(func():action_requested.emit("cave_upgrade",{}))
	field("Promote").pressed.connect(func():action_requested.emit("promote",{"route":retreat_route}))
func bind_data(operations: RefCounted,saved: Dictionary={},message: String="") -> void:
	service=operations;state=service.snapshot();data=service.data
	tab=saved.get("tab","Overview");plot_index=clampi(saved.get("plot",0),0,maxi(0,state.plots.size()-1));seed=saved.get("seed","");recipe=saved.get("recipe","")
	binding=true
	target_mode=saved.get("target",false);field("TargetRetreat").button_pressed=target_mode
	retreat_route=saved.get("retreat_route","qi");field("RetreatRoute").select(1 if retreat_route=="body" else 0)
	for pair in [["Years","years"],["Months","months"],["Days","days"]]:field(pair[0]).value=saved.get(pair[1],1 if pair[1]=="months" else 0)
	binding=false
	field("Message").text=message
	_overview();_retreat_info();_fields();_recipes();_warehouse();_preview();_tab(tab)
func _remember() -> void:
	selection_changed.emit({"target":target_mode,"retreat_route":retreat_route,"tab":tab,"plot":plot_index,"seed":seed,"recipe":recipe,"years":int(field("Years").value),"months":int(field("Months").value),"days":int(field("Days").value)})
func _tab(value: String) -> void:
	tab=value
	for name in ["Overview","Retreat","Fields","Alchemy","WarehousePage"]:field(name).visible=name==tab
	for pair in [["OverviewTab","Overview"],["RetreatTab","Retreat"],["FieldsTab","Fields"],["AlchemyTab","Alchemy"]]:_style(field(pair[0]),pair[1]==tab)
	_remember()
func _style(node: Control,active: bool) -> void:
	var style:=StyleBoxFlat.new();style.bg_color=Color("70988a") if active else Color("415b67")
	node.add_theme_stylebox_override("normal",style)
func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()
func _realm(level: int) -> String:return preload("res://gameplay/cultivation/cultivation_system.gd").realm_name(level,"qi",data)
func _overview() -> void:
	var idle:=0;var growing:=0;var mature:=0
	for plot in state.plots:
		if plot.is_empty():idle+=1
		elif state.hours>=plot.ready_at:mature+=1
		else:growing+=1
	var p: Dictionary=state.player
	field("Summary").text="洞府 %d 级    灵田 %d 块    修炼：空闲    种植 %d 块    炼丹：已开放 / 空闲" % [state.cave_level,state.plots.size(),growing+mature]
	field("RetreatCardText").text="%s · 修为 %d
闭关消耗游戏时间，按现有规则结算" % [_realm(p.realm),p.cultivation]
	field("FieldsCardText").text="共 %d 块 · 空闲 %d · 种植中 %d · 成熟 %d" % [state.plots.size(),idle,growing,mature]
	field("AlchemyCardText").text="已开放 · %d 个已有丹方
炼制材料、消耗与时间读取配置" % data.recipes.size()
	field("OtherCardText").text="已有聚灵阵、洞府升级与仓库"
	field("Activity").text="已有 %d 块灵田成熟，可前往收获" % mature if mature>0 else "%d 块灵田生长中" % growing if growing>0 else "当前暂无洞府动态"
	field("Formation").text="关闭聚灵阵" if state.formation else "启用聚灵阵"
	for pair in [["Formation","formation"],["UpgradeCave","cave_upgrade"]]:
		var result: Dictionary=service.cave_quote(pair[1],{})
		field(pair[0]).disabled=not result.success;field(pair[0]).tooltip_text=result.message if not result.success else ""
func _choose_retreat_route(index: int) -> void:
	retreat_route="body" if index==1 else "qi"
	_retreat_info()
	_preview()

func _retreat_info() -> void:
	var p: Dictionary=state.player
	var growth: RefCounted=service.cultivation
	var body: bool=retreat_route=="body"
	field("CurrentRealm").text=growth.body_realm_name(p,data) if body else _realm(p.realm)
	var required: int=growth.requirement(p,retreat_route,data)
	var current: int=growth.progress(p,retreat_route)
	field("CurrentCultivation").text="%s %d / %s" % ["炼体修为" if body else "修为",current,str(required) if required>0 else "已达上限"]
	field("CultivationProgress").max_value=maxi(1,required);field("CultivationProgress").value=current
	var quote: Dictionary=service.cave_quote("promote",{"route":retreat_route}) if required>0 and current>=required else {}
	field("Promote").text="体修突破" if body else "晋升 / 筑基" if p.realm==9 else "法修突破"
	field("Promote").disabled=not quote.get("success",false)
	field("Promote").tooltip_text=quote.get("message","已达当前境界上限" if required<=0 else "修为不足")
	var spirit: RefCounted=service.clock.spirit
	var estimate: Vector2=spirit.hourly_estimate(state,"retreat",retreat_route,data,growth)
	field("Efficiency").text="%s\n当前约 %.3f 修为 / 时\n根基温养约 %.3f / 时\n洞府等级：%d\n年龄：%d / 寿元 %d" % [
		spirit.grade(state,p.location,data),estimate.x,estimate.y,state.cave_level,p.age,p.lifespan]
func _adjust(key: String,delta: int) -> void:field(key).value=maxf(0,field(key).value+delta)
func _duration(years: int,months: int,days: int) -> void:
	binding=true
	field("Years").value=years;field("Months").value=months;field("Days").value=days
	binding=false;_preview()
func _preview() -> void:
	if binding or service==null:return
	var years: int=int(field("Years").value);var months: int=int(field("Months").value);var days: int=int(field("Days").value)
	preview=service.retreat_preview(years,months,days,target_mode,retreat_route)
	field("Duration").text="%d 年 %d 月 %d 天" % [years,months,days]
	field("Preview").text="合计 %d 日

预计获得修为：%s
预计闭关后修为：%s
当前修为：%d

当前年龄：%d
闭关后年龄：%d
寿元上限：%d
预计剩余寿元：%d
%s" % [preview.days,str(preview.gain) if preview.success else "待计算",str(preview.after) if preview.success else "待计算",service.cultivation.progress(state.player,retreat_route),state.player.age,preview.age,state.player.lifespan,preview.remaining,"此次闭关将达到寿元，结束后无法继续操作" if preview.age>=state.player.lifespan else ""]
	field("StartRetreat").disabled=not preview.success;field("RetreatReason").text=preview.reason if not preview.success else "\n".join(preview.warnings)
	field("Preview").text+="\n\n实际推进：%.2f 日；%s\n封顶后继续所选时间，寿元到期会中止。" % [preview.elapsed/86400.0,"目标圆满后出关" if target_mode else "按选定时长结算"]
	_remember()
func _plot(index: int) -> void:plot_index=index;_fields();_remember()
func _seed(id: String) -> void:seed=id;_fields();_remember()
func _fields() -> void:
	_clear(field("PlotGrid"));_clear(field("SeedList"))
	field("FieldsHeading").text="灵田区域 · %d 块" % state.plots.size()
	for i in range(state.plots.size()):
		var plot: Dictionary=state.plots[i]
		var button: Button=preload("res://ui/cave/field_card.tscn").instantiate()
		button.text="灵田 %d

%s
%s" % [i+1,"空闲" if plot.is_empty() else data.items[plot.herb].name,"点击查看" if plot.is_empty() else "已成熟" if state.hours>=plot.ready_at else "剩余 %d 小时" % (plot.ready_at-state.hours)]
		_style(button,i==plot_index);button.pressed.connect(_plot.bind(i));field("PlotGrid").add_child(button)
	var available: Array=[]
	for id in data.herbs:
		var seed_id: String=data.herbs[id].seed_id
		var count: int=int(state.player.inventory.get(seed_id,0))
		if count<=0:continue
		available.append(id)
		var button:=Button.new();button.text="%s ×%d" % [data.items[seed_id].name,count];button.custom_minimum_size.y=72
		button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;_style(button,id==seed);button.pressed.connect(_seed.bind(id));field("SeedList").add_child(button)
	if seed not in available:seed=""
	if available.is_empty():
		var empty:=Label.new();empty.text="背包中没有可用种子";empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;field("SeedList").add_child(empty)
	field("FieldAction").disabled=true
	if state.plots.is_empty():field("FieldDescription").text="请选择灵田";return
	var plot: Dictionary=state.plots[plot_index]
	var is_empty: bool=plot.is_empty()
	var mature: bool=not is_empty and state.hours>=plot.ready_at
	field("ManagementTitle").text="灵田管理 · %d" % (plot_index+1)
	field("FieldDescription").text="状态：%s

当前作物：%s

剩余时间：%s" % ["空闲" if is_empty else "成熟" if mature else "种植中","无" if is_empty else data.items[plot.herb].name,"—" if is_empty else "可收获" if mature else "%d 小时" % (plot.ready_at-state.hours)]
	field("Growth").visible=not is_empty
	if not is_empty:field("Growth").value=clampf(float(state.hours-plot.planted_at)/maxf(1,plot.ready_at-plot.planted_at)*100,0,100)
	field("SelectedSeed").text="已选种子：%s" % (data.items[data.herbs[seed].seed_id].name if not seed.is_empty() else "无")
	field("FieldAction").text="播种" if is_empty else "收获"
	var result: Dictionary={"success":false,"message":"请选择种子"}
	if not is_empty:result=service.cave_quote("harvest",{"plot":plot_index})
	elif not seed.is_empty():result=service.cave_quote("plant",{"plot":plot_index,"id":seed})
	field("FieldAction").disabled=not result.success;field("FieldReason").text="" if result.success else result.message
func _field_action() -> void:
	if field("FieldAction").disabled:return
	action_requested.emit("plant" if state.plots[plot_index].is_empty() else "harvest",{"plot":plot_index,"id":seed})
func _recipe(id: String) -> void:recipe=id;_recipes();_remember()
func _recipes() -> void:
	_clear(field("Recipes"))
	if not data.recipes.has(recipe):recipe=str(data.recipes.keys()[0]) if not data.recipes.is_empty() else ""
	for id in data.recipes:
		var button:=Button.new();button.text=data.recipes[id].name;button.custom_minimum_size.y=48;_style(button,id==recipe);button.pressed.connect(_recipe.bind(id));field("Recipes").add_child(button)
	field("Craft").disabled=true
	if recipe.is_empty():field("RecipeDetail").text="暂无丹方";return
	var r: Dictionary=data.recipes[recipe]
	var lines: Array[String]=["材料："]
	for id in r.materials:lines.append("%s ×%d（持有 %d）" % [data.items[id].name,r.materials[id],state.player.inventory.get(id,0)])
	lines.append("灵石：%d
时间：%d 日
产物：%s ×1" % [r.cost,r.days,data.items[r.output].name])
	field("RecipeDetail").text="
".join(lines)
	var result: Dictionary=service.cave_quote("craft",{"id":recipe})
	field("Craft").disabled=not result.success;field("CraftReason").text="" if result.success else result.message
func _warehouse() -> void:
	_clear(field("WarehouseList"))
	for withdrawing in [false,true]:
		var items: Dictionary=state.warehouse if withdrawing else state.player.inventory
		for id in items:
			if items[id]<=0:continue
			var button:=Button.new();button.custom_minimum_size.y=48;button.text="%s · %s ×%d" % ["取出1" if withdrawing else "存入1",data.items[id].name,items[id]]
			var args: Dictionary={"id":id,"withdraw":withdrawing}
			var quote: Dictionary=service.cave_quote("warehouse",args)
			button.disabled=not quote.success;button.tooltip_text=quote.message if not quote.success else ""
			button.pressed.connect(func():action_requested.emit("warehouse",args));field("WarehouseList").add_child(button)

func _start_retreat() -> void:
	if retreat_busy:return
	for key in ["Years","Months","Days"]:
		if field(key).get_line_edit().has_focus():field(key).apply()
	_preview()
	if not preview.success:return
	retreat_busy=true;field("StartRetreat").disabled=true
	var submit: Callable=func():action_requested.emit("retreat_target" if target_mode else "retreat",{"days":maxi(1,preview.days),"route":retreat_route,"_request_id":retreat_request_id})
	if preview.warnings.is_empty():submit.call();return
	var dialog:=ConfirmationDialog.new();add_child(dialog)
	dialog.title="闭关风险确认";dialog.dialog_text="\n".join(preview.warnings)+"\n仍要继续此次闭关吗？"
	dialog.confirmed.connect(func():submit.call();dialog.queue_free())
	dialog.canceled.connect(func():retreat_busy=false;dialog.queue_free();_preview())
	dialog.popup_centered(Vector2i(760,400))
