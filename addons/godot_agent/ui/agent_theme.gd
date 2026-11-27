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


## Fuera del editor (la app aparte, m21-07), los colores del diseño: fondo, la barra y paneles, las
## superficies (campos, botones), los bordes y el texto.
const APP_BASE := Color("#1d2026")
const APP_DARK := Color("#181b20")
const APP_SURFACE := Color("#23272e")
const APP_BORDER := Color("#363c46")
const APP_TEXT := Color("#e6e8eb")

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
	var bundled := bundled_font(MONO_FONT)  # la del diseño, con el addon
	if bundled:
		return bundled
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
	return theme.get_color(&"base_color", &"Editor") if theme.has_color(&"base_color", &"Editor") else APP_BASE


static func dark_color() -> Color:
	var theme := editor_theme()
	return theme.get_color(&"dark_color_2", &"Editor") if theme.has_color(&"dark_color_2", &"Editor") else APP_DARK


static func font_color() -> Color:
	var theme := editor_theme()
	return theme.get_color(&"font_color", &"Editor") if theme.has_color(&"font_color", &"Editor") else APP_TEXT


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


## El tema de la app aparte (m21-07): el de Godot con las superficies del diseño en botones, campos,
## menús y paneles. En el editor no se usa: el dock sigue el tema del editor.
static func app_theme() -> Theme:
	var theme := Theme.new()
	var hover := APP_SURFACE.lightened(0.08)
	for type: StringName in [&"Button", &"MenuButton", &"OptionButton"]:
		theme.set_stylebox(&"normal", type, panel(APP_SURFACE, APP_BORDER, 8.0, 6.0))
		theme.set_stylebox(&"hover", type, panel(hover, APP_BORDER.lightened(0.15), 8.0, 6.0))
		theme.set_stylebox(&"pressed", type, panel(APP_BORDER, APP_BORDER.lightened(0.15), 8.0, 6.0))
		theme.set_stylebox(&"hover_pressed", type, panel(APP_BORDER, APP_BORDER.lightened(0.15), 8.0, 6.0))
		theme.set_stylebox(&"disabled", type, panel(Color(APP_SURFACE, 0.5), Color(APP_BORDER, 0.5), 8.0, 6.0))
		theme.set_stylebox(&"focus", type, panel(Color.TRANSPARENT, APP_BORDER.lightened(0.3), 8.0, 6.0))
		theme.set_color(&"font_color", type, APP_TEXT)
	for type: StringName in [&"LineEdit", &"TextEdit", &"CodeEdit"]:
		theme.set_stylebox(&"normal", type, panel(APP_SURFACE, APP_BORDER, 8.0, 8.0))
		theme.set_stylebox(&"focus", type, panel(Color.TRANSPARENT, APP_BORDER.lightened(0.3), 8.0, 8.0))
		theme.set_stylebox(&"read_only", type, panel(APP_DARK, APP_BORDER, 8.0, 8.0))
		theme.set_color(&"font_color", type, APP_TEXT)
	theme.set_stylebox(&"panel", &"PopupMenu", panel(APP_SURFACE, APP_BORDER, 8.0, 6.0))
	theme.set_stylebox(&"hover", &"PopupMenu", panel(APP_BORDER, Color.TRANSPARENT, 6.0, 4.0))
	theme.set_stylebox(&"panel", &"PopupPanel", panel(APP_SURFACE, APP_BORDER, 8.0, 8.0))
	theme.set_stylebox(&"panel", &"PanelContainer", panel(APP_BASE, Color.TRANSPARENT, 0.0, 0.0))
	theme.set_stylebox(&"panel", &"Panel", panel(APP_BASE, Color.TRANSPARENT, 0.0, 0.0))
	theme.set_stylebox(&"panel", &"AcceptDialog", panel(APP_BASE, Color.TRANSPARENT, 0.0, 8.0))
	theme.set_stylebox(&"panel", &"TabContainer", panel(APP_BASE, Color.TRANSPARENT, 0.0, 0.0))
	theme.set_color(&"font_color", &"Label", APP_TEXT)
	# Las casillas y los interruptores no son botones con caja: heredaban la de Button.
	for type: StringName in [&"CheckBox", &"CheckButton"]:
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
			theme.set_stylebox(state, type, panel(Color.TRANSPARENT, Color.TRANSPARENT, 6.0, 4.0))
		theme.set_stylebox(&"hover", type, panel(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 6.0, 4.0))
		theme.set_stylebox(&"hover_pressed", type, panel(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 6.0, 4.0))
	# La fuente del diseño (m21-25): Inter, que viene con el addon (OFL, ui/fonts).
	var inter := bundled_font(INTER_FONT)
	if inter:
		theme.default_font = inter
	return theme


## Las fuentes del diseño, con su licencia (SIL OFL 1.1) al lado. Solo las usa la app: el dock sigue
## las del editor.
const INTER_FONT := "res://addons/godot_agent/ui/fonts/InterVariable.ttf"
const MONO_FONT := "res://addons/godot_agent/ui/fonts/JetBrainsMono-Regular.ttf"
static var _fonts: Dictionary = {}


## Una fuente del addon: importada si Godot ya la importó (la app y el ejecutable exportado); si no,
## leída del .ttf (el addon recién copiado, los tests). null si no está.
static func bundled_font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var font: Font = null
	if ResourceLoader.exists(path):
		font = load(path) as Font
	elif FileAccess.file_exists(path):
		var file := FontFile.new()
		if file.load_dynamic_font(path) == OK:
			font = file
	_fonts[path] = font
	return font


## El logo del proyecto (docs/images/logo.svg): el globo de chat ámbar con el prompt «›_». Entero, con
## su fondo, es el ícono de la ventana y del proyecto de la app (m21-15); el glifo sin fondo, de 16 px
## con el «›_» calado, va en la cabecera de la app y en el editor (AgentIcon).
const LOGO_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<rect x="4" y="4" width="120" height="120" rx="28" fill="#262b38"/>
<path d="M38 22 H90 A18 18 0 0 1 108 40 V74 A18 18 0 0 1 90 92 H62 L40 108 L44 92 H38 A18 18 0 0 1 20 74 V40 A18 18 0 0 1 38 22Z" fill="#f0a85a"/>
<path d="M42 44 L58 57 L42 70" fill="none" stroke="#262b38" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M68 70 H88" fill="none" stroke="#262b38" stroke-width="9" stroke-linecap="round"/>
</svg>"""
const LOGO_GLYPH_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
<path fill="#f0a85a" fill-rule="evenodd" d="M4 1.5H12A3 3 0 0 1 15 4.5V9A3 3 0 0 1 12 12H7.5L3.5 15L4.3 12H4A3 3 0 0 1 1 9V4.5A3 3 0 0 1 4 1.5Z M4.2 6.3L5.3 5L8.6 7.5L5.3 10L4.2 8.7L6 7.5Z M9 9H12V10.5H9Z"/>
</svg>"""


static func app_icon() -> Image:
	var image := Image.new()
	return image if image.load_svg_from_string(LOGO_SVG) == OK else null


## El glifo del logo a `side_px` de alto.
static func logo_glyph(side_px: float = 22.0) -> Texture2D:
	var image := Image.new()
	if image.load_svg_from_string(LOGO_GLYPH_SVG, px(side_px) / 16.0) != OK:
		return null
	return ImageTexture.create_from_image(image)


## Un ícono de trazo dibujado de un SVG de 24×24 (`paths`: los `<path>`/`<circle>` de adentro), en
## `color`, a `side_px`. Fuera del editor no están sus íconos (m21-08).
static func stroke_icon(paths: String, color: Color, side_px: float = 18.0) -> Texture2D:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [color.to_html(false), paths]
	var image := Image.new()
	if image.load_svg_from_string(svg, px(side_px) / 24.0) != OK:
		return null
	return ImageTexture.create_from_image(image)


## Un fondo con borde solo en algunos lados (las líneas entre columnas de la app, m21-16).
static func edged(bg: Color, border: Color, left := 0, top := 0, right := 0, bottom := 0, padding: float = 8.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width_left = left
	box.border_width_top = top
	box.border_width_right = right
	box.border_width_bottom = bottom
	box.set_content_margin_all(px(padding))
	return box


## Un título de sección como los del diseño: en mayúsculas, chico y apagado.
static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", px(12))
	label.add_theme_color_override(&"font_color", Color(APP_TEXT, 0.55))
	return label


## Una insignia redondeada (el modo de una sesión).
static func badge(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", px(11))
	label.add_theme_color_override(&"font_color", Color(APP_TEXT, 0.8))
	var box := panel(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 9.0, 0.0)
	box.content_margin_left = px(7)
	box.content_margin_right = px(7)
	box.content_margin_top = px(1)
	box.content_margin_bottom = px(1)
	label.add_theme_stylebox_override(&"normal", box)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


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
