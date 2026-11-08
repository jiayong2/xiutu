extends Node
signal time_ui_changed(interval: Dictionary)
var real_buffer := 0.0
const Repository = preload("res://core/data_repository.gd")
const Catalog = preload("res://core/content_catalog.gd")
const Operations = preload("res://core/operation_service.gd")
const NpcDefinitions = preload("res://core/npc_definitions.gd")
var catalog := Catalog.new()
var operations := Operations.new()
var saves := preload("res://core/save_service.gd").new()
var repository := Repository.new()
var boot_ok := false

func _ready() -> void:
	boot_ok = repository.load_starting_character()
	if boot_ok:
		boot_ok = catalog.load_all()
		if not boot_ok:
			repository.last_error = catalog.error
	if boot_ok:
		operations.configure(catalog.tables)
		operations.time_changed.connect(func(interval: Dictionary):time_ui_changed.emit(interval))
	if boot_ok:
		AppLog.write("INFO", "boot", "S00 configuration validated", "boot")
	else:
		AppLog.write("ERROR", "boot", repository.last_error, "boot")

func new_game(player_name: String, root: String, innate: String = "") -> String:
	if not boot_ok:
		return repository.last_error
	var definitions := NpcDefinitions.load_definitions(catalog.tables)
	if not definitions.error.is_empty():
		return definitions.error
	catalog.tables.npc_overrides = definitions.rows
	operations.data.npc_overrides = definitions.rows.duplicate(true)
	real_buffer=0
	return operations.new_game(player_name,root,repository.starting_character(),1,innate,true)

func request(action: String, args: Dictionary = {}, operation_id: String = "") -> Dictionary:
	var result := operations.request(action,args,operation_id)
	AppLog.write("INFO" if result.success else "WARN",action,result.message,result.get("operation_id",""))
	return result

func debug_npc_definitions() -> Dictionary:
	if not OS.is_debug_build() or not boot_ok:
		return {"rows":{}, "error":"NPC 调试导入仅在开发构建中可用"}
	return NpcDefinitions.load_definitions(catalog.tables)

func debug_import_npc(id: String, refresh: bool = false) -> Dictionary:
	var definitions := debug_npc_definitions()
	if not definitions.error.is_empty():
		return {"success":false, "message":definitions.error}
	if not definitions.rows.has(id):
		return {"success":false, "message":"找不到已保存的 NPC 定义，请先在编辑器保存"}
	return request("debug_import_npc", {"definition":definitions.rows[id], "refresh":refresh})

func save_game() -> String:
	if operations.snapshot().is_empty():
		return "尚未创建角色"
	var path := saves.write(operations.export_save())
	AppLog.write("INFO" if not path.is_empty() else "ERROR","save",path if not path.is_empty() else saves.error)
	return "存档已保存：" + path if not path.is_empty() else saves.error

func load_game(path: String = "") -> String:
	if path.is_empty():
		var paths := saves.list_saves()
		if paths.is_empty():
			return "没有存档"
		path = paths[0]
	var payload := saves.read(path)
	if payload.is_empty():
		return saves.error
	real_buffer=0
	return operations.restore_save(payload)

func _process(delta: float) -> void:advance_session(delta)
func advance_session(delta: float) -> void:
	if not boot_ok:return
	var status: Dictionary=operations.clock_status()
	if not status.exists or status.expired:return
	real_buffer+=delta
	var whole: int=int(real_buffer)
	if whole>0:
		real_buffer-=whole
		operations.advance_realtime(whole*int(catalog.tables.time_rules.game_seconds_per_real_second))
