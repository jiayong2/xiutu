@tool
extends EditorPlugin

var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/npc_editor/editor.tscn").instantiate()
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)

func _exit_tree() -> void:
	panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "NPC"

func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible

func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(panel) and not panel.queued_drafts.is_empty():
		return "NPC 编辑器仍有待应用到存档的人物。"
	if for_scene.is_empty() and is_instance_valid(panel) and panel.is_dirty():
		return "NPC 编辑器有未保存的初始定义。"
	return ""

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.selected_save.is_empty() and panel.has_unqueued_changes():
		panel.save()
