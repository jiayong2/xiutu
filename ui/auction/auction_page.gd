extends Control

signal closed
const Auction = preload("res://gameplay/auction/auction_system.gd")
const Cultivation = preload("res://gameplay/cultivation/cultivation_system.gd")
const Participant = preload("res://ui/auction/auction_participant.tscn")
const LogText = preload("res://ui/battle/battle_log_formatter.gd")
const MOOD_LABELS := {"watch":"观望","hesitate":"犹豫","out":"已退出","angry":"愤怒","deterred":"被威慑","quiet":"保持沉默","guarded":"有所防备"}
const LOG_COLORS := {"normal":"#305E4D","player":"#28745E","price":"#945B29","conflict":"#873D38","success":"#2D713E","failure":"#9B4D33"}
const INTERACTIONS := {"Spirit":"spirit","Threat":"threat","Provoke":"provoke","Pressure":"pressure"}
const MODES := {"Standard":"standard","Quick":"quick","Custom":"custom"}

var service: RefCounted
var venue_id := ""
var state: Dictionary
var definition: Dictionary
var terms: Dictionary
var a: Dictionary
var lot: Dictionary
var target := ""
var mode := "standard"
var submitting := false
var shown_step := -1

func field(key: String) -> Node:
	return find_child(key,true,false)

func _ready() -> void:
	field("Close").pressed.connect(back)
	field("Enter").pressed.connect(_enter)
	field("Bid").pressed.connect(_bid)
	field("Pass").pressed.connect(_submit.bind("auction_pass",{}))
	field("Watch").pressed.connect(_submit.bind("auction_watch",{}))
	field("Next").pressed.connect(_submit.bind("auction_next",{}))
	for key in MODES:
		field(key).pressed.connect(_mode.bind(MODES[key]))
	field("CustomInput").text_changed.connect(func(_value: String): _quote())
	for key in INTERACTIONS:
		field(key).pressed.connect(_interact.bind(INTERACTIONS[key]))
	field("Whisper").pressed.connect(_whisper)
	field("Rules").pressed.connect(_rules)
	field("History").pressed.connect(_history)
	field("BoxEntry").toggled.connect(func(_value: bool): _entry_status())
	for key in ["ResultDialog","InfoDialog"]:
		var dialog: AcceptDialog = field(key)
		dialog.ok_button_text = "确定"
		dialog.get_ok_button().custom_minimum_size.x = 115
	var whisper: ConfirmationDialog = field("WhisperDialog")
	whisper.title = "私下传音"
	whisper.ok_button_text = "劝退"
	whisper.cancel_button_text = "取消"
	whisper.add_button("收买",true,"bribe")
	whisper.confirmed.connect(_interact.bind("persuade"))
	whisper.custom_action.connect(func(_action: String): whisper.hide(); _interact("bribe"))

func bind_data(operations: RefCounted, id: String) -> void:
	service = operations
	venue_id = id
	definition = service.data.auctions[id]
	var rules: Dictionary = service.data.auction_rules
	field("Standard").text = "+%s%%" % str(snappedf(float(rules.minimum_bps)/100.0,.01)).trim_suffix(".0")
	field("Quick").text = "+%s%%" % str(snappedf(float(rules.quick_bps)/100.0,.01)).trim_suffix(".0")
	field("Anonymous").visible = definition.entry.anonymous
	field("BoxEntry").visible = definition.entry.box_fee >= 0
	field("BoxEntry").text = "选择雅间（另付 %d 灵石）" % definition.entry.box_fee
	refresh_state()

func refresh_state() -> void:
	state = service.snapshot()
	a = Auction.session(state,venue_id)
	var active: bool = not a.is_empty() and a.phase != "finished"
	terms = a.terms if active else definition
	var bidding: bool = active and a.phase == "bidding"
	var index := int(a.index) if active else 0
	lot = terms.lots[index]
	var item: Dictionary = service.data.items[lot.item]
	field("Title").text = terms.name
	field("Count").text = "第 %d / %d 件" % [index+1,terms.lots.size()] if active else "共 %d 件拍品" % terms.lots.size()
	field("Wallet").text = "可用灵石 %d" % state.player.spirit_stones
	field("Venue").text = "%s · %s" % [terms.scale,"雅间" if active and a.box else "匿名入场" if active and a.anonymous else "公开席"]
	field("HostName").text = "拍卖师 · "+terms.host.name
	var path: String = terms.host.get("portrait","")
	var portrait: TextureRect = field("HostImage")
	portrait.texture = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path,"Texture2D") else null
	portrait.visible = portrait.texture != null
	field("HostGlyph").visible = not portrait.visible
	field("HostCall").text = _host_line(active,bidding)
	field("LotName").text = "%s ×%d" % [item.name,lot.quantity]
	field("LotMeta").text = "%s · %s · %s" % [lot.quality,lot.category,lot.rarity]
	field("LotEffect").text = item.description
	field("LotEffect").tooltip_text = item.description
	field("LotEffect").mouse_filter = Control.MOUSE_FILTER_PASS
	field("Lobby").visible = not active
	field("Modes").visible = bidding
	field("BidActions").visible = bidding
	field("QuoteRow").visible = bidding
	field("Watch").text = "稳住心神" if bidding and a.restricted else "继续询价" if bidding and (a.calls>0 or a.withdrawn or a.round>=terms.round_limit) else "观望"
	field("Watch").tooltip_text = "让竞拍继续，直到有新的 NPC 出价或拍卖师落槌。"
	field("Next").visible = active and not bidding
	field("RoundActions").visible = active and not bidding
	field("Next").text = "结束本场" if index+1==terms.lots.size() else "下一件拍品"
	var window := Auction.schedule(state,definition,service.data)
	var same_cycle: bool = a.get("cycle",-1)==window.cycle
	field("Phase").text = "竞价阶段" if bidding else "已落槌" if active else "本期已结束" if same_cycle else "入场前" if window.open else "等待开场"
	var notice := ""
	if bidding:
		if a.restricted:
			notice = "神识受扰，点击「稳住心神」后恢复竞价。"
		elif a.withdrawn:
			notice = "你已退出当前拍品。点击「继续询价」可看到本件结算。"
		elif a.leader=="player":
			notice = "已暂扣 %d 灵石。被超价后自动退回。" % a.price
		elif a.round>=terms.round_limit:
			notice = "本件竞价已到轮次上限。点击「继续询价」完成结算。"
	field("Notice").text = notice
	field("Notice").visible = not notice.is_empty()
	field("Pass").disabled = bidding and a.withdrawn
	if bidding and int(a.step)!=shown_step:
		field("CustomInput").clear()
	shown_step = int(a.get("step",-1))
	_entry_status()
	_participants(active)
	_quote()
	_interaction_status()
	var lines: PackedStringArray = []
	for entry in a.get("log",[]):
		lines.append("[color=%s]%s[/color]" % [LOG_COLORS[entry.role],LogText.escape_text(entry.text)])
	field("ActivityLog").text = "\n".join(lines) if not lines.is_empty() else "入场后将在这里记录喊价、竞拍与成交。"

func back() -> void:
	for key in ["WhisperDialog","ResultDialog","InfoDialog"]:
		if field(key).visible:
			field(key).hide()
			return
	closed.emit()

func _host_line(active: bool, bidding: bool) -> String:
	if not active:
		return "请在开场期间入席。"
	if not bidding:
		return "当前拍品已落槌。"
	var amount := int(lot.start) if a.leader.is_empty() else int(a.price)
	if a.calls > 0:
		return "%d 灵石，第 %d 次询价。还有道友愿意出价吗？" % [amount,a.calls]
	return "起拍 %d 灵石，请诸位出价。" % amount if a.leader.is_empty() else "当前喊价 %d 灵石。你可以跟价、观望或互动。" % amount

func _entry_status() -> void:
	if service == null or not field("Lobby").visible:
		return
	var reason := Auction.entry_reason(state,definition,service.data)
	var base := int(definition.entry.fee)
	var fee := base+int(definition.entry.box_fee) if field("BoxEntry").button_pressed else base
	field("Enter").disabled = not reason.is_empty() or state.player.spirit_stones < fee
	field("LobbyInfo").text = reason if not reason.is_empty() else "入场需 %d 灵石。%s" % [fee,"可用灵石不足。" if state.player.spirit_stones < fee else "每件拍品独立竞拍。"]

func _participants(active: bool) -> void:
	var list: VBoxContainer = field("ParticipantsList")
	var offset: int = field("ParticipantScroll").scroll_vertical
	for row in list.get_children():
		list.remove_child(row)
		row.queue_free()
	for profile in terms.participants:
		var id: String = profile.id
		var npc: Dictionary = state.npcs[id]
		if not npc.alive and not (active and a.actors.has(id)):
			continue
		if active and not a.actors.has(id):
			continue
		var row: Button = Participant.instantiate()
		row.set_meta("npc",id)
		row.find_child("NpcName",true,false).text = npc.name
		row.find_child("NpcRealm",true,false).text = Cultivation.npc_realm_label(npc,service.data)
		var mood: String = a.actors[id].mood if active and npc.alive else "quiet" if not active else "out"
		var leading: bool = active and a.leader == id
		var participated: bool = active and a.actors[id].get("bids",0)>0
		var status: String = ("最高出价 · "+MOOD_LABELS[mood]) if leading and mood not in ["watch","quiet"] else "正在竞价" if leading else ("已出价 · " if participated else "")+MOOD_LABELS[mood]
		row.find_child("NpcMood",true,false).text = status
		row.pressed.connect(_select.bind(id))
		list.add_child(row)
	field("ParticipantScroll").set_deferred("scroll_vertical",offset)
	_select(target)

func _select(id: String) -> void:
	target = id
	for row in field("ParticipantsList").get_children():
		row.theme_type_variation = &"Selected" if row.get_meta("npc")==id else &""
	field("ParticipantHint").text = "互动目标　"+state.npcs[id].name if state.npcs.has(id) else "选择一名修士作为互动目标"
	_interaction_status()

func _mode(next_mode: String) -> void:
	mode = next_mode
	_quote()
	if mode=="custom":
		field("CustomInput").grab_focus()

func _quote() -> void:
	if service == null:
		return
	var bidding: bool = a.get("phase")=="bidding"
	var leader: String = a.get("leader","") if not a.is_empty() and a.phase!="finished" else ""
	var price: int = int(lot.start) if leader.is_empty() else int(a.price)
	field("PriceLabel").text = "起拍价" if leader.is_empty() else "当前最高出价"
	field("PriceValue").text = "%d 灵石" % price
	field("Leader").text = "暂无出价" if leader.is_empty() else "竞价者　"+Auction.actor_name(state,a,leader,true)
	field("Leader").tooltip_text = field("Leader").text
	var rules: Dictionary = service.data.auction_rules
	var increment := Auction.increment(price,int(rules.minimum_bps))
	field("MinRaise").text = "最低加价 %d" % increment if not leader.is_empty() else "首笔可按起拍价"
	field("Available").text = "可用灵石 %d" % state.player.spirit_stones
	field("CustomInput").visible = bidding and mode=="custom"
	field("Quote").visible = bidding
	for key in MODES:
		field(key).theme_type_variation = &"Selected" if MODES[key]==mode else &""
	if not bidding:
		return
	var amount := _amount()
	var legal: bool = amount>=Auction.minimum(a,lot,rules) and amount<=rules.max_price
	var available: bool = amount<=state.player.spirit_stones
	field("Bid").disabled = not legal or not available or a.withdrawn or a.restricted or a.leader=="player" or a.round>=terms.round_limit
	field("Quote").text = ("本次出价 %d 灵石%s" % [amount," · 灵石不足" if not available else ""]) if legal else "请输入至少 %d 灵石的有效总出价" % Auction.minimum(a,lot,rules)

func _amount() -> int:
	var input: String = field("CustomInput").text.strip_edges()
	var custom := int(input) if input.is_valid_int() else 0
	return Auction.proposed(a,lot,service.data.auction_rules,mode,custom)

func _interaction_status() -> void:
	for key in INTERACTIONS:
		var reason := _reason(INTERACTIONS[key])
		field(key).disabled = not reason.is_empty()
		field(key).tooltip_text = reason
	var reason := _reason("persuade")
	field("Whisper").disabled = not reason.is_empty() and not _reason("bribe").is_empty()
	field("Whisper").tooltip_text = reason if field("Whisper").disabled else ""
	field("InteractionHint").text = "先选择在场修士。" if target.is_empty() else "互动可能引起敌意或拍卖行警告。"

func _reason(kind: String) -> String:
	if a.is_empty() or a.phase != "bidding":
		return "当前不在竞价阶段"
	return Auction.interaction_reason(state,a,terms,kind,target)

func _whisper() -> void:
	var dialog: ConfirmationDialog = field("WhisperDialog")
	var persuade := _reason("persuade")
	var bribe := _reason("bribe")
	dialog.get_ok_button().disabled = not persuade.is_empty()
	for child in dialog.find_children("*","Button",true,false):
		if child.text=="收买":
			child.disabled = not bribe.is_empty()
	dialog.dialog_text = "与%s私下交涉。收买成功时支付 %d 灵石。%s%s" % [
		state.npcs[target].name,terms.bribe,"\n劝退："+persuade if not persuade.is_empty() else "","\n收买："+bribe if not bribe.is_empty() else ""]
	dialog.popup_centered(Vector2i(650,260))

func _enter() -> void:
	_submit("auction_enter",{"anonymous":field("Anonymous").button_pressed,"box":field("BoxEntry").button_pressed})

func _bid() -> void:
	if not field("Bid").disabled:
		_submit("auction_bid",{"amount":_amount()})

func _interact(kind: String) -> void:
	_submit("auction_interact",{"kind":kind,"target":target})

func _submit(action: String, args: Dictionary) -> void:
	if submitting:
		return
	submitting = true
	args = args.duplicate()
	args.merge({"id":venue_id,"cycle":a.get("cycle",-1),"step":a.get("step",-1)})
	var old_phase: String = a.get("phase","")
	var response: Dictionary = GameManager.request(action,args) if service==GameManager.operations else service.request(action,args)
	if response.success and action in ["auction_enter","auction_next"]:
		mode = "standard"
		target = ""
	refresh_state()
	submitting = false
	if not response.success or action=="auction_interact" or (old_phase=="bidding" and a.get("phase")=="settled"):
		_dialog("ResultDialog","竞拍回执" if response.success else "暂无法操作",response.message)

func _dialog(key: String, title: String, message: String) -> void:
	var dialog: AcceptDialog = field(key)
	dialog.title = title
	if key == "InfoDialog":
		field("InfoText").text = message
		field("InfoText").scroll_to_line(0)
	else:
		dialog.dialog_text = message
	dialog.popup_centered(Vector2i(700,340) if key=="InfoDialog" else Vector2i(700,270))

func _rules() -> void:
	var rules: Dictionary = service.data.auction_rules
	var text := "每 %d 日举办一次，开放入场 %d 日。入场要求 %s。\n首笔可按起拍价，后续至少加价 %s%%，向上取整。\n最高出价暂扣灵石，被超过后退回。放弃仅退出当前拍品。\n观望推进至新的出价或落槌。三次询价无需逐次确认。\n从成交款内划分 %s%% 佣金。关闭页面后可继续当前场次。" % [
		terms.schedule.period_days,terms.schedule.duration_days,Cultivation.realm_name(int(terms.entry.min_realm),"qi",service.data),
		str(float(rules.minimum_bps)/100.0),str(float(terms.commission_bps)/100.0)]
	_dialog("InfoDialog","拍卖规则",text)

func _history() -> void:
	var history: Array = a.get("history",[])
	var lines: PackedStringArray = []
	for record in history:
		var item: Dictionary = service.data.items[record.item]
		var result := "%s · %d 灵石（佣金 %d）" % [Auction.actor_name(state,a,record.winner,true),record.price,record.commission] if not record.winner.is_empty() else "流拍"
		lines.append("%s ×%d · %s" % [item.name,record.quantity,result])
	_dialog("InfoDialog","成交记录","\n".join(lines) if not lines.is_empty() else "本期尚无成交记录。")
