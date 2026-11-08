extends RefCounted

const COLORS := {
	"凡品":["666D70","92999C","FFFFFF"], "良品":["277B48","50BB76","FFFFFF"],
	"上品":["235EAD","62A8F0","FFFFFF"], "玄品":["6433A5","B785F0","FFFFFF"],
	"地品":["A85A13","F3B74F","FFF1C9"], "天品":["9E222B","FFD36C","FFF0C2"],
	"负面":["29292B","B54C50","F4E8E7"],
}

static func apply(label: Label, definition: Dictionary, panel: PanelContainer = null) -> void:
	var quality: String = definition.get("quality", "凡品")
	if definition.get("kind") == "negative":
		quality = "负面"
	var colors: Array = COLORS.get(quality, COLORS["凡品"])
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colors[0])
	style.border_color = Color(colors[1])
	style.set_border_width_all(2 if quality in ["地品", "天品"] else 1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	label.add_theme_color_override("font_color", Color(colors[2]))
	if panel != null:
		panel.add_theme_stylebox_override("panel", style)
	else:
		label.add_theme_stylebox_override("normal", style)
