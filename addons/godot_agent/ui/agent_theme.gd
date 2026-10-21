@tool
extends RefCounted
## Estilos compartidos por la UI del addon. Los colores base salen del theme del editor; lo del
## agente usa un único color de acento (spec §9). Fuera del editor (tests) usa valores por defecto.

const CHANNEL_COLORS: Dictionary = {
	&"acp": Color("#6cb4ff"),
	&"mcp": Color("#b493ff"),
	&"fs": Color("#e8e8e8"),
	&"perm": Color("#f0a85a"),
	&"proc": Color("#9aa0a6"),
	&"cmp": Color("#7fd98b"),
}
const USER_BUBBLE := Color("#33405a")
const GODOT_TOOL := Color("#b493ff")
const ADDED := Color("#7fd98b")
const REMOVED := Color("#ff7a7a")
const ADDED_BG := Color(0.2, 0.55, 0.3, 0.22)
const REMOVED_BG := Color(0.7, 0.2, 0.2, 0.22)
const MUTED := Color(1, 1, 1, 0.55)
const ERROR := Color("#ff7a7a")
const WARNING := Color("#f5c26b")


static func has_editor() -> bool:
	return Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface")


static func editor_scale() -> float:
	return EditorInterface.get_editor_scale() if has_editor() else 1.0


static func px(value: float) -> int:
	return int(round(value * editor_scale()))


static func editor_theme() -> Theme:
	return EditorInterface.get_editor_theme() if has_editor() else ThemeDB.get_default_theme()


static func icon(name: StringName) -> Texture2D:
	var theme := editor_theme()
	return theme.get_icon(name, &"EditorIcons") if theme.has_icon(name, &"EditorIcons") else null


static func mono_font() -> Font:
	var theme := editor_theme()
	if theme.has_font(&"source", &"EditorFonts"):
		return theme.get_font(&"source", &"EditorFonts")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])
	return font


static func mono_font_size() -> int:
	var theme := editor_theme()
	if theme.has_font_size(&"source_size", &"EditorFonts"):
		return theme.get_font_size(&"source_size", &"EditorFonts")
	return px(13)


static func base_color() -> Color:
	var theme := editor_theme()
	return theme.get_color(&"base_color", &"Editor") if theme.has_color(&"base_color", &"Editor") else Color("#202531")


static func dark_color() -> Color:
	var theme := editor_theme()
	return theme.get_color(&"dark_color_2", &"Editor") if theme.has_color(&"dark_color_2", &"Editor") else Color("#191d26")


static func font_color() -> Color:
	var theme := editor_theme()
	return theme.get_color(&"font_color", &"Editor") if theme.has_color(&"font_color", &"Editor") else Color("#dfe2e7")


static func panel(bg: Color, border: Color = Color.TRANSPARENT, radius: float = 6.0, padding: float = 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(px(radius))
	box.set_content_margin_all(px(padding))
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(maxi(1, px(1)))
	return box


static func color_hex(color: Color) -> String:
	return "#" + color.to_html(false)
