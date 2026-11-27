@tool
extends RefCounted
## Ícono del harness (el globo con el prompt, docs/images/logo.svg sin el fondo) para la main screen
## y el dock, a la escala del editor. Va como texto y se rasteriza acá: un .svg dentro del addon
## tendría que importarse antes de que el plugin lo pueda cargar.

const AgentTheme := preload("agent_theme.gd")

## 16×16, con el «›_» calado en el globo (evenodd) para que se lea sobre cualquier tema del editor.
const SVG := AgentTheme.LOGO_GLYPH_SVG

static var _texture: Texture2D


## null si no se pudo rasterizar.
static func texture() -> Texture2D:
	if _texture == null:
		var image := Image.new()
		var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
		if image.load_svg_from_string(SVG, scale) == OK:
			_texture = ImageTexture.create_from_image(image)
	return _texture
