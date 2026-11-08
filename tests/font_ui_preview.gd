extends SceneTree
const REGULAR="res://assets/fonts/source_han_sans_cn/SourceHanSansCN-Regular.otf"
const BOLD="res://assets/fonts/source_han_sans_cn/SourceHanSansCN-Bold.otf"
var checked:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
func inspect(node: Node) -> void:
	if node is Label or node is Button or node is LineEdit:
		checked+=1
		if node.get_theme_font("font").resource_path!=REGULAR:failures+=1;push_error(str(node.get_path())+" font mismatch")
	if node is RichTextLabel:
		checked+=2
		if node.get_theme_font("normal_font").resource_path!=REGULAR:failures+=1;push_error("rich normal mismatch")
		if node.get_theme_font("bold_font").resource_path!=BOLD:failures+=1;push_error("rich bold mismatch")
	for child in node.get_children():inspect(child)
func run() -> void:
	root.size=Vector2i(1920,1080)
	var gm: Node=root.get_node("GameManager")
	gm.new_game("思源黑体检查","金")
	var main=load("res://ui/main/main.tscn").instantiate()
	root.add_child(main)
	for page in ["主菜单","创建角色","主界面","角色","功法","洞府","背包","任务","地图","地点场景","宗门","商店","战斗"]:
		main.page=page;main._refresh();await settle();inspect(main)
		if page=="主界面":root.get_texture().get_image().save_png("res://docs/screenshots/font_home_1920.png")
	root.size=Vector2i(1280,720)
	main.page="主界面";main._refresh();await settle()
	root.get_texture().get_image().save_png("res://docs/screenshots/font_home_1280.png")
	var overlay=load("res://ui/battle/battle_result_overlay.tscn").instantiate()
	root.add_child(overlay);await settle();inspect(overlay)
	print("FONT CHECK: %d font bindings, %d failures" % [checked,failures])
	quit(0 if failures==0 else 1)
