@tool
extends RefCounted
## Idioma de la interfaz (D46). El texto fuente está en inglés y cada idioma extra es un `.po` en
## `addons/godot_agent/i18n/` (hoy, español). `t("Budgets")` devuelve la traducción o el mismo
## texto. Una constante con textos que se traducen al mostrarlos lleva `# i18n` al final de cada
## línea con un texto: el último literal de la línea es el msgid (lo usa test_i18n).
## Lo que lee el agente (prompts, descripciones de tools, resultados de tools) y los logs no pasan
## por acá: van siempre en inglés.
##
## El idioma sale de, en orden: la variable de entorno GODOT_AGENT_LANGUAGE (pruebas), el setting
## Settings → Interfaz → Idioma, y el idioma del editor. Se elige al habilitar el plugin: cambiarlo
## se aplica al reabrir el editor, como el resto de la interfaz ya armada.

const DIR := "res://addons/godot_agent/i18n/"
const AUTO := "auto"
const SOURCE := "en"
## Para Settings: código y nombre (en su idioma, como los muestra Godot).
const LANGUAGES: Array[Dictionary] = [
	{"code": AUTO, "name": "Automatic (editor language)"},  # i18n
	{"code": "en", "name": "English"},
	{"code": "es", "name": "Español"},
]
const ENV_OVERRIDE := "GODOT_AGENT_LANGUAGE"

static var _translation: Translation = null
static var _locale: String = SOURCE


## `language`: el setting ("auto", "en", "es"…).
static func setup(language: String) -> void:
	var code := OS.get_environment(ENV_OVERRIDE)
	if code.is_empty():
		code = language
	if code.is_empty() or code == AUTO:
		code = editor_language()
	set_locale(code)


## "es_AR" → "es". Sin traducción para ese idioma queda en inglés.
static func set_locale(code: String) -> void:
	var base := code.strip_edges().get_slice("_", 0).get_slice("-", 0).to_lower()
	_translation = null
	_locale = SOURCE
	if base.is_empty() or base == SOURCE:
		return
	var path := DIR + base + ".po"
	if not FileAccess.file_exists(path):
		return
	var loaded := load(path) as Translation
	if loaded:
		_translation = loaded
		_locale = base


static func locale() -> String:
	return _locale


static func editor_language() -> String:
	if Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		if settings and settings.has_setting("interface/editor/editor_language"):
			return str(settings.get_setting("interface/editor/editor_language"))
	return OS.get_locale_language()


## La traducción de `text` (un msgid en inglés), o `text` si no hay.
static func t(text: String) -> String:
	if _translation == null:
		return text
	var translated := String(_translation.get_message(text))
	return text if translated.is_empty() else translated
