@tool
extends EditorPlugin

var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/exploration_map/editor.tscn").instantiate()
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.hide()
	panel.close_requested.connect(EditorInterface.set_main_screen_editor.bind("2D"))

func _exit_tree() -> void:
	panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "探索地图"

func _make_visible(active: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = active

func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(panel) and panel.is_dirty():
		return "探索地图编辑器有未保存的地图。"
	return ""
