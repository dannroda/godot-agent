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
	&"quota": Color("#f2d16b"),
	&"cmp": Color("#7fd98b"),
	&"update": Color("#6fd3c8"),
	&"state": Color("#ff8fb8"),
}
const USER_BUBBLE := Color("#33405a")
const ADDED := Color("#7fd98b")
const REMOVED := Color("#ff7a7a")
const ADDED_BG := Color(0.2, 0.55, 0.3, 0.22)
const REMOVED_BG := Color(0.7, 0.2, 0.2, 0.22)
const MUTED := Color(1, 1, 1, 0.55)
const ERROR := Color("#ff7a7a")
const WARNING := Color("#f5c26b")
## Severidades de la revisión (spec §9.4, mockup Review): texto/marca y fondo de etiqueta.
const SEVERITY_COLORS: Dictionary = {"bug": Color("#f0a640"), "order": Color("#c9a2ff"), "perf": Color("#6cb4ff"), "style": Color("#a8a8a8")}
const SEVERITY_BG: Dictionary = {"bug": Color("#3a2e1c"), "order": Color("#2f2438"), "perf": Color("#1d2a36"), "style": Color("#2c2c2e")}


## Texto sobre fondo de acento.
const ACCENT_TEXT := Color("#1d1d1d")

static func has_editor() -> bool:
	return Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface")


## El EditorInterface, o null fuera del editor. Por el singleton y no por su nombre (m20-07): en una
## plantilla de exportación las clases del editor no existen y un script que las nombra no parsea.
static func editor() -> Object:
	return Engine.get_singleton(&"EditorInterface") if has_editor() else null


## EditorFileDialog en el editor; FileDialog en la app (las dos tienen file_mode, access y current_dir).
static func file_dialog() -> ConfirmationDialog:
	return ClassDB.instantiate(&"EditorFileDialog") if has_editor() else FileDialog.new()


static func editor_scale() -> float:
	return editor().get_editor_scale() if has_editor() else 1.0


static func px(value: float) -> int:
	return int(round(value * editor_scale()))


static func editor_theme() -> Theme:
	return editor().get_editor_theme() if has_editor() else ThemeDB.get_default_theme()


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


## Botón principal con fondo de acento y texto oscuro en todos los estados: el tema del editor
## pinta en blanco el texto con foco o apretado, ilegible sobre el naranja.
static func style_accent_button(button: Button, accent: Color, radius: float = 4.0, padding: float = 5.0) -> void:
	button.add_theme_stylebox_override(&"normal", panel(accent, Color.TRANSPARENT, radius, padding))
	button.add_theme_stylebox_override(&"hover", panel(accent.lightened(0.15), Color.TRANSPARENT, radius, padding))
	button.add_theme_stylebox_override(&"pressed", panel(accent.darkened(0.12), Color.TRANSPARENT, radius, padding))
	button.add_theme_stylebox_override(&"disabled", panel(Color(accent, 0.35), Color.TRANSPARENT, radius, padding))
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, ACCENT_TEXT)


## Un punto lleno de `color` (estado del agente, severidad de un hallazgo).
static func dot(color: Color, side_px: float = 8.0) -> Texture2D:
	var side := px(side_px)
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2(side, side) / 2.0
	for y in side:
		for x in side:
			image.set_pixel(x, y, color if Vector2(x + 0.5, y + 0.5).distance_to(center) <= side / 2.0 else Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)


## Un punto de `color` a la izquierda de `icon` (el estado de una pestaña junto a su pin, m21-03), con el
## ícono a 16 px de alto como mucho; sin `icon` (o sin su imagen), el punto solo.
static func dot_beside(color: Color, icon: Texture2D) -> Texture2D:
	var marker := dot(color)
	var picture := icon.get_image() if icon else null
	if picture == null:
		return marker
	if picture.is_compressed():
		picture.decompress()
	picture.convert(Image.FORMAT_RGBA8)
	if picture.get_height() > px(16):
		picture.resize(maxi(1, picture.get_width() * px(16) / picture.get_height()), px(16), Image.INTERPOLATE_BILINEAR)
	var point := marker.get_image()
	var gap := px(4)
	var height := maxi(point.get_height(), picture.get_height())
	var image := Image.create(point.get_width() + gap + picture.get_width(), height, false, Image.FORMAT_RGBA8)
	image.blit_rect(point, Rect2i(Vector2i.ZERO, point.get_size()), Vector2i(0, (height - point.get_height()) / 2))
	image.blit_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), Vector2i(point.get_width() + gap, (height - picture.get_height()) / 2))
	return ImageTexture.create_from_image(image)


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
