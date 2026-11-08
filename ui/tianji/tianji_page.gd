extends Control

signal closed

func _ready() -> void:
	%PreviewIntel.hide()
	%EmptyIntel.show()
	%Back.pressed.connect(func(): closed.emit())
	for tab: Button in %Navigation.get_children():
		tab.pressed.connect(_select_tab.bind(tab))
	for row: HBoxContainer in %RankCategories.get_children():
		for tab: Button in row.get_children():
			tab.pressed.connect(_select_rank.bind(tab))
	%FullRanking.pressed.connect(func(): _show_full_ranking(not %FullEmpty.visible))

func set_spirit_stones(amount: int) -> void:
	%Stones.text = "灵石：%d" % amount

func _select_tab(selected: Button) -> void:
	for tab: Button in %Navigation.get_children():
		tab.set_pressed_no_signal(tab == selected)
	%Overview.visible = selected.get_index() == 0
	%Section.visible = not %Overview.visible
	%SectionTitle.text = selected.text

func _select_rank(selected: Button) -> void:
	for row: HBoxContainer in %RankCategories.get_children():
		for tab: Button in row.get_children():
			tab.set_pressed_no_signal(tab == selected)
	_show_full_ranking(%FullEmpty.visible)

func _show_full_ranking(show_full: bool) -> void:
	for row: HBoxContainer in %RankCategories.get_children():
		for tab: Button in row.get_children():
			if tab.button_pressed:
				%RankTitle.text = tab.text + (" · 完整榜单" if show_full else " · 前三名")
	%TopThree.visible = not show_full
	%FullEmpty.visible = show_full
	%FullRanking.text = "返回前三名" if show_full else "查看完整榜单"
