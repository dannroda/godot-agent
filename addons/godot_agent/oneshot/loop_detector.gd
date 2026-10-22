@tool
extends RefCounted
## Loops del One-shot (D38): el agente repite lo mismo sin avanzar ("loop forever, retry bad
## actions"). Mira tres huellas:
## - un check que falla con el mismo detalle en `repeats` reportes seguidos;
## - una tool call que falla con los mismos argumentos `repeats` veces (una lectura o verificación
##   que falla cuenta de nuevo después de cada cambio: editar y volver a probar no es un loop);
## - una tool call que cambia algo (no lectura ni verificación) repetida igual, con los mismos
##   argumentos, `repeats + 1` veces entre las últimas WINDOW.
## Cada vez que una huella llega al umbral devuelve un hallazgo y su cuenta vuelve a 0: la primera
## vez el run le pide otro enfoque al agente; si la misma huella vuelve a llegar, pausa.
## El hallazgo trae `text` en inglés (va en el prompt del agente) y `label` traducido (la UI).

const I18n := preload("../core/i18n.gd")

## Tool calls recientes que se miran para las repeticiones.
const WINDOW := 40
## Lecturas y verificaciones: repetirlas con los mismos argumentos es normal (playtest después de
## cada cambio, releer un archivo).
const REPEATABLE_KINDS: PackedStringArray = ["read", "search", "think", "fetch"]
## open_scene y save_scene entran acá: abrir o guardar la misma escena después de cada cambio es normal.
## Textos de los hallazgos: en inglés para el agente, traducidos para la UI.
const CHECK_TEXT := "the check “%s” failed %d times in a row"  # i18n
const CHECK_DETAIL_TEXT := "the check “%s” failed %d times in a row with “%s”"  # i18n
const FAILED_TEXT := "“%s” failed %d times with the same arguments"  # i18n
const SAME_TEXT := "“%s” was repeated %d times, unchanged"  # i18n
const REPEATABLE_GODOT_TOOLS: PackedStringArray = ["run_scene", "stop_scene", "capture_game_frame", "capture_editor_viewport", "get_errors", "validate_scripts", "editor_state", "scene_tree", "get_node", "list_files", "project_info", "open_scene", "save_scene"]

var repeats: int = 3

## label -> {detail, count}
var _check_streaks: Dictionary = {}
## huellas de las tool calls recientes que cambian algo
var _recent: PackedStringArray = []
## huella -> {count, repeatable}
var _failed: Dictionary = {}
## huella -> veces que ya se avisó
var _reported: Dictionary = {}


func reset() -> void:
	_check_streaks.clear()
	_recent.clear()
	_failed.clear()
	_reported.clear()


## Checks de un reporte (`{label, status, detail}`). Un check que pasa o cambia de detalle corta su
## racha. Devuelve el hallazgo o {}.
func observe_checks(checks: Array) -> Dictionary:
	for check: Variant in checks:
		if not check is Dictionary:
			continue
		var label := str(check.get("label", ""))
		if str(check.get("status", "")) != "fail":
			_check_streaks.erase(label)
			continue
		var detail := str(check.get("detail", ""))
		var streak: Dictionary = _check_streaks.get(label, {"detail": detail, "count": 0})
		if streak.detail != detail:
			streak = {"detail": detail, "count": 0}
		streak.count += 1
		_check_streaks[label] = streak
		if streak.count >= repeats:
			_check_streaks.erase(label)
			var key := "check:%s|%s" % [label, detail]
			if detail.is_empty():
				return _finding(key, CHECK_TEXT, [label, repeats])
			return _finding(key, CHECK_DETAIL_TEXT, [label, repeats, detail.left(80)])
	return {}


## Una tool call terminada. `godot_tool` es el nombre de la tool godot.* ("" si no es una).
func observe_call(title: String, kind: String, godot_tool: String, input: Variant, failed: bool) -> Dictionary:
	var key := fingerprint(title, input)
	var repeatable := kind in REPEATABLE_KINDS or godot_tool in REPEATABLE_GODOT_TOOLS
	if failed:
		var entry: Dictionary = _failed.get(key, {"count": 0, "repeatable": repeatable})
		entry.count += 1
		_failed[key] = entry
		if entry.count >= repeats:
			_failed.erase(key)
			return _finding("failed:" + key, FAILED_TEXT, [title.left(60), repeats])
		return {}
	_failed.erase(key)
	if repeatable:
		return {}
	for other: String in _failed.keys():  # algo cambió: la próxima verificación puede dar distinto
		if _failed[other].repeatable:
			_failed.erase(other)
	_recent.append(key)
	if _recent.size() > WINDOW:
		_recent.remove_at(0)
	if _recent.count(key) > repeats:
		for i in range(_recent.size() - 1, -1, -1):
			if _recent[i] == key:
				_recent.remove_at(i)
		return _finding("same:" + key, SAME_TEXT, [title.left(60), repeats + 1])
	return {}


## Nombre + argumentos con las claves ordenadas: dos llamadas iguales dan la misma huella.
static func fingerprint(title: String, input: Variant) -> String:
	return "%s %s" % [title, JSON.stringify(input, "", true)]


## {key, text, label, repeated}: `text` en inglés, `label` traducido; `repeated` = ya se había
## avisado de esta huella.
func _finding(key: String, format: String, values: Array) -> Dictionary:
	var times := int(_reported.get(key, 0))
	_reported[key] = times + 1
	return {"key": key, "text": format % values, "label": I18n.t(format) % values, "repeated": times > 0}
