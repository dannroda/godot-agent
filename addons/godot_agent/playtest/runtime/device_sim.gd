extends RefCounted
## Dispositivo simulado de run_scene (m11-51): tamaño de ventana, escala, táctil desde el mouse e
## idioma, para revisar un HUD o textos traducidos en otro aspecto sin tocar project.godot.
## El editor lo valida (normalize) y se lo pasa al juego en la variable de entorno ENV, que el proceso
## hereda al lanzarse (como RealGamepads); el probe lo aplica en su _ready, antes que el _ready de la
## escena principal, y lo informa con el pedido «device». Corre también dentro del juego: nada de
## editor acá.

const ENV := "GODOT_AGENT_DEVICE"
const MIN_SIDE := 64
const MAX_SIDE := 8192
const MAX_SCALE := 4.0
## Tamaños en píxeles físicos; `orientation` los da vuelta.
const PRESETS: Dictionary = {
	"phone": {"size": [1080, 2400], "touch": true},
	"tablet": {"size": [2048, 1536], "touch": true},
	"steam-deck": {"size": [1280, 800]},
	"1080p": {"size": [1920, 1080]},
	"4k": {"size": [3840, 2160]},
}


## El parámetro `device` de run_scene → {device: {name, size: [w, h], scale, touch, locale}} o
## {error}. Acepta un preset suelto ("phone") o {preset, size, orientation, scale, touch, locale};
## lo que se pasa pisa al preset. Sin nada que simular, {}.
static func normalize(value: Variant) -> Dictionary:
	if value == null:
		return {}
	var spec: Dictionary = {"preset": value} if value is String else (value if value is Dictionary else {})
	if spec.is_empty() and not value is Dictionary:
		return {"error": "`device` must be a preset name (%s) or an object {preset, size: [w, h], orientation, scale, touch, locale}." % ", ".join(PRESETS.keys())}
	var device := {"name": "", "size": [], "scale": 1.0, "touch": false, "locale": ""}
	var preset := str(spec.get("preset", "")).strip_edges().to_lower()
	if not preset.is_empty():
		if not PRESETS.has(preset):
			return {"error": "Unknown device preset '%s'. Presets: %s." % [preset, ", ".join(PRESETS.keys())]}
		device.name = preset
		device.size = (PRESETS[preset].size as Array).duplicate()
		device.touch = bool(PRESETS[preset].get("touch", false))
	if spec.has("size"):
		var size: Variant = spec.size
		if not size is Array or (size as Array).size() != 2 or not (size[0] is float or size[0] is int) or not (size[1] is float or size[1] is int):
			return {"error": "`device.size` must be [width, height] in pixels."}
		device.size = [int(size[0]), int(size[1])]
	if not device.size.is_empty():
		for side: int in device.size:
			if side < MIN_SIDE or side > MAX_SIDE:
				return {"error": "`device.size` sides go from %d to %d pixels." % [MIN_SIDE, MAX_SIDE]}
	if spec.has("orientation"):
		var orientation := str(spec.orientation).to_lower()
		if not orientation in ["portrait", "landscape"]:
			return {"error": "`device.orientation` is portrait or landscape."}
		if device.size.is_empty():
			return {"error": "`device.orientation` needs a preset or a size."}
		var tall: bool = device.size[1] > device.size[0]
		if tall != (orientation == "portrait"):
			device.size = [device.size[1], device.size[0]]
	if spec.has("scale"):
		var scale := float(spec.scale)
		if scale <= 0.0 or scale > MAX_SCALE:
			return {"error": "`device.scale` goes from more than 0 to %d." % MAX_SCALE}
		device.scale = scale
	if spec.has("touch"):
		device.touch = spec.touch == true
	if spec.has("locale"):
		device.locale = str(spec.locale).strip_edges()
	if device.size.is_empty() and is_equal_approx(device.scale, 1.0) and not device.touch and device.locale.is_empty():
		return {"error": "`device` has nothing to simulate: pass a preset, size, scale, touch or locale."}
	return {"device": device}


## Una línea para el informe de run_scene con lo que se pidió.
static func describe(device: Dictionary) -> String:
	var parts: PackedStringArray = []
	if not str(device.get("name", "")).is_empty():
		parts.append(str(device.name))
	if not (device.get("size", []) as Array).is_empty():
		parts.append("%d×%d" % [device.size[0], device.size[1]])
	if not is_equal_approx(float(device.get("scale", 1.0)), 1.0):
		parts.append("scale %s" % device.scale)
	if device.get("touch", false):
		parts.append("touch from the mouse")
	if not str(device.get("locale", "")).is_empty():
		parts.append("locale %s" % device.locale)
	return ", ".join(parts)


## Lo pone en el entorno para los procesos que se lancen desde ahora. Devuelve lo que había (restore).
static func set_env(device: Dictionary) -> Variant:
	var previous: Variant = OS.get_environment(ENV) if OS.has_environment(ENV) else null
	OS.set_environment(ENV, JSON.stringify(device))
	return previous


static func restore_env(previous: Variant) -> void:
	if previous == null:
		OS.unset_environment(ENV)
	else:
		OS.set_environment(ENV, str(previous))


## Dentro del juego: el dispositivo que pidió el editor, o {}.
static func from_env() -> Dictionary:
	if not OS.has_environment(ENV):
		return {}
	var parsed: Variant = JSON.parse_string(OS.get_environment(ENV))
	if not parsed is Dictionary:
		return {}
	var device: Dictionary = parsed
	if device.get("size") is Array:  # JSON devuelve floats
		device.size = (device.size as Array).map(func(side: Variant) -> int: return int(side))
	return device


## Dentro del juego, en el _ready del probe: ventana, escala, táctil e idioma.
static func apply(window: Window, device: Dictionary) -> void:
	apply_size(window, device)
	if not is_equal_approx(float(device.get("scale", 1.0)), 1.0):
		window.content_scale_factor = float(device.scale)
	if device.get("touch", false):
		Input.emulate_touch_from_mouse = true
	if not str(device.get("locale", "")).is_empty():
		TranslationServer.set_locale(str(device.locale))


## El tamaño de la ventana. En el _ready de un autoload la ventana todavía no terminó de armarse y
## vuelve al tamaño del proyecto: el probe lo repite en los primeros frames. true si ya lo tiene.
static func apply_size(window: Window, device: Dictionary) -> bool:
	var size: Array = device.get("size", [])
	if size.size() != 2 or embedded():
		return true
	var asked := Vector2i(int(size[0]), int(size[1]))
	if window.size == asked:
		return true
	window.mode = Window.MODE_WINDOWED
	window.size = asked
	return false


## El juego corre dentro de la vista Game del editor (4.4+): el tamaño de la ventana lo pone el editor.
## OS.get_cmdline_args() no trae los flags del motor (--embedded, --wid).
static func embedded() -> bool:
	return Engine.has_method(&"is_embedded_in_editor") and bool(Engine.call(&"is_embedded_in_editor"))


## Cómo correr el juego en su propia ventana: en 4.8 el menú de la vista Game cambió por tres botones.
static func _own_window_hint() -> String:
	if Engine.get_version_info().hex >= 0x040800:
		return "the user can pick «Run the game in a floating window without the toolbar» in the Game view's toolbar."
	return "the user can turn off «Embed Game on Next Play» in the Game view's menu."


## Dentro del juego: lo que quedó aplicado, para el informe (pedido «device» del probe).
static func report(window: Window, device: Dictionary) -> String:
	if device.is_empty():
		return "No simulated device."
	var lines: PackedStringArray = ["Simulated device: %s." % describe(device)]
	var size: Array = device.get("size", [])
	if size.size() == 2:
		var asked := Vector2i(int(size[0]), int(size[1]))
		if embedded():
			lines.append("The game runs embedded in the editor's Game view, which sets its window size (%d×%d), so the size was not simulated: %s" % [window.size.x, window.size.y, _own_window_hint()])
		elif window.size != asked:
			lines.append("The window got %d×%d, not %d×%d (the screen or the window manager limits it): check the layout at that size." % [window.size.x, window.size.y, asked.x, asked.y])
		else:
			lines.append("Window %d×%d; the game draws at %d×%d (its stretch settings)." % [window.size.x, window.size.y, int(window.get_visible_rect().size.x), int(window.get_visible_rect().size.y)])
	if device.get("touch", false):
		lines.append("Mouse clicks and drags arrive as touch events too (emulate_touch_from_mouse); code that asks DisplayServer.is_touchscreen_available() still gets false.")
	var locale := str(device.get("locale", ""))
	if not locale.is_empty():
		var loaded := TranslationServer.get_loaded_locales()
		var matched := Array(loaded).any(func(each: String) -> bool: return each == locale or each.get_slice("_", 0) == locale.get_slice("_", 0))
		if matched:
			lines.append("Locale %s (TranslationServer.get_locale() = %s). Texts set before the probe started, or built with OS.get_locale(), keep their language." % [locale, TranslationServer.get_locale()])
		else:
			lines.append("Locale %s, but the project has no translation for it (loaded: %s): the texts stay as they are." % [locale, ", ".join(loaded) if not loaded.is_empty() else "none"])
	return "\n".join(lines)
