@tool
extends RefCounted
## Ícono del harness (el globo con el prompt, docs/images/logo.svg sin el fondo) para la main screen
## y el dock, a la escala del editor. Va como texto y se rasteriza acá: un .svg dentro del addon
## tendría que importarse antes de que el plugin lo pueda cargar.

## 16×16, con el «›_» calado en el globo (evenodd) para que se lea sobre cualquier tema del editor.
const SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
<path fill="#f0a85a" fill-rule="evenodd" d="M4 1.5H12A3 3 0 0 1 15 4.5V9A3 3 0 0 1 12 12H7.5L3.5 15L4.3 12H4A3 3 0 0 1 1 9V4.5A3 3 0 0 1 4 1.5Z M4.2 6.3L5.3 5L8.6 7.5L5.3 10L4.2 8.7L6 7.5Z M9 9H12V10.5H9Z"/>
</svg>"""

static var _texture: Texture2D


## null si no se pudo rasterizar.
static func texture() -> Texture2D:
	if _texture == null:
		var image := Image.new()
		var scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
		if image.load_svg_from_string(SVG, scale) == OK:
			_texture = ImageTexture.create_from_image(image)
	return _texture
