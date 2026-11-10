@tool
extends PanelContainer
## Read-only catalogue; no technique ownership, learning or exchange settlement.
signal closed
const BOOK_SCENE := preload("res://ui/sect/library_book.tscn")
var books: Dictionary = {}
var selected := ""

func field(key: String) -> Node:
	return find_child(key, true, false)

func _ready() -> void:
	field("Books").resized.connect(_fit_books)
	field("Books").child_entered_tree.connect(func(_child: Node): _fit_books.call_deferred())
	if Engine.is_editor_hint():
		var preview_visible := visible
		var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills/techniques.json"))
		var preview := {}
		if rows is Array:
			for row in rows:
				preview[row.id] = row
		show_library(preview)
		visible = preview_visible
		return
	field("Exit").pressed.connect(func(): hide(); closed.emit())
	field("Read").pressed.connect(func(): field("Feedback").text = "研读规则尚未开放")
	field("Take").pressed.connect(func(): field("Feedback").text = "取出规则尚未开放")

func show_library(definitions: Dictionary) -> void:
	books = definitions
	var grid: GridContainer = field("Books")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	# Existing authored techniques are display entries, not granted inventory.
	for id in books:
		var card := BOOK_SCENE.instantiate()
		grid.add_child(card)
		if Engine.is_editor_hint():
			card.owner = self
		var button: Button = card.get_node("Square/Select")
		button.text = str(books[id].name).left(1)
		button.tooltip_text = str(books[id].name)
		button.toggle_mode = true
		button.pressed.connect(select_book.bind(str(id)))
		card.get_node("Name").text = str(books[id].name)
	# Keep six shelf positions without inventing extra formal techniques.
	for i in range(maxi(0, 6 - books.size())):
		var empty := BOOK_SCENE.instantiate()
		grid.add_child(empty)
		if Engine.is_editor_hint():
			empty.owner = self
		empty.get_node("Square/Select").text = "+"
		empty.get_node("Square/Select").disabled = true
		empty.get_node("Name").text = "空置"
	field("Identity").text = "功法陈列 · %d 本" % books.size()
	field("ShelfScroll").scroll_vertical = 0
	field("Feedback").text = "仅查阅 · 研读与取出尚未开放"
	show()
	select_book(str(books.keys()[0]) if not books.is_empty() else "")

func select_book(id: String) -> void:
	selected = id
	var definition: Dictionary = books.get(id, {})
	field("BookName").text = str(definition.get("name", "暂无功法"))
	field("CoverGlyph").text = str(definition.get("name", "空")).left(1)
	var route := "炼体" if definition.get("cultivation_route", "qi") == "body" else "炼气"
	field("BookMeta").text = "%s · %s" % [definition.get("rarity", "未配置"), route]
	field("BasicParametersText").text = "修炼路线：%s" % route if not definition.is_empty() else "暂无基础参数"
	var effects: PackedStringArray = []
	for key in {"hp":"气血", "defense":"防御", "attack":"攻击", "fire":"火系加成"}:
		var value := float(definition.get(key, 0))
		var growth := float(definition.get(key + "_step", 0))
		var label: String = {"hp":"气血", "defense":"防御", "attack":"攻击", "fire":"火系加成"}[key]
		if not is_zero_approx(value):
			effects.append("%s %+.2f%s" % [label, value * 100.0 if key == "fire" else value, "%" if key == "fire" else ""])
		if not is_zero_approx(growth):
			effects.append("每级成长 · %s %+.2f%s" % [label, growth * 100.0 if key == "fire" else growth, "%" if key == "fire" else ""])
	field("SkillEffectsText").text = "\n".join(effects) if not effects.is_empty() else "当前配置无基础属性加成"
	field("SkillDescriptionText").text = str(definition.get("description", "暂无描述"))
	for card in field("Books").get_children():
		var button: Button = card.get_node("Square/Select")
		button.set_pressed_no_signal(not button.disabled and button.tooltip_text == field("BookName").text)
	field("DetailScroll").scroll_vertical = 0
	# Reapply after containers finish reflowing a different length of text.
	field("DetailScroll").set_deferred("scroll_vertical", 0)

func _fit_books() -> void:
	var grid: GridContainer = field("Books")
	var width := maxf(1.0, (grid.size.x - grid.get_theme_constant("h_separation") * (grid.columns - 1)) / grid.columns)
	for card in grid.get_children():
		card.get_node("Square").custom_minimum_size.y = width
