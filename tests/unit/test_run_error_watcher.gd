extends "test_case.gd"
## m11-55: un run manual con errores deja un aviso una vez por run; los del agente, el ajuste apagado
## y los runs limpios no; el texto del aviso y el prompt llevan el motivo y los errores.

const RunErrorWatcher := preload("res://addons/godot_agent/editor/run_error_watcher.gd")
const ErrorCollector := preload("res://addons/godot_agent/editor/error_collector.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")


## Sin editor: no hay panel del debugger que leer.
class FakeErrors extends ErrorCollector:
	func collect() -> void:
		pass


func _watcher(errors: ErrorCollector) -> RunErrorWatcher:
	var watcher := RunErrorWatcher.new()
	watcher.errors = errors
	return watcher


func _collect(watcher: RunErrorWatcher) -> Array:
	var found: Array = []
	watcher.error_found.connect(func(info: Dictionary) -> void: found.append(info))
	return found


func test_manual_run_with_errors_notifies_once() -> void:
	var errors := FakeErrors.new()
	errors.add("error", "antes del run", "res://old.gd", 1, "game")  # no cuenta: es de antes
	var watcher := _watcher(errors)
	var found := _collect(watcher)
	watcher.on_game_started()
	errors.add("error", "Invalid call. Nonexistent function 'queue_free' in base 'Nil'.", "res://tests/fixtures/run_broken.gd", 8, "game")
	errors.add("warning", "un warning", "res://a.gd", 2, "game")  # los warnings no cuentan
	errors.add("error", "del editor", "res://b.gd", 3, "editor")  # ni los del editor
	watcher.break_reason = func() -> String: return "Invalid call (res://tests/fixtures/run_broken.gd:8 in _ready)"
	watcher.on_game_breaked()
	assert_eq(found.size(), 1, "la pausa del debugger avisa")
	assert_true(found[0].breaked and found[0].count == 1 and str(found[0].reason).begins_with("Invalid call"), "con el motivo y el error · %s" % [found[0]])
	assert_true(str(found[0].lines[0]).contains("run_broken.gd:8") and not "\n".join(found[0].lines).contains("warning"), "solo los errores del juego · %s" % [found[0].lines])
	errors.add("error", "otro al cerrar", "res://c.gd", 4, "game")
	watcher.on_game_stopped()
	assert_eq(found.size(), 1, "una vez por run")
	watcher.on_game_started()
	errors.add("error", "run nuevo", "res://d.gd", 5, "game")
	watcher.on_game_stopped()
	assert_eq(found.size(), 2, "el run siguiente avisa de nuevo")
	assert_true(not found[1].breaked and found[1].count == 1 and str(found[1].lines[0]).contains("run nuevo"), "terminó con errores, sin pausa · %s" % [found[1]])


func test_clean_harness_and_disabled_runs_stay_quiet() -> void:
	var errors := FakeErrors.new()
	var watcher := _watcher(errors)
	var found := _collect(watcher)
	watcher.on_game_started()
	watcher.on_game_stopped()
	assert_eq(found.size(), 0, "sin errores no avisa")
	watcher.launched_by_harness = func() -> bool: return true
	watcher.on_game_started()
	errors.add("error", "del run del agente", "res://a.gd", 1, "game")
	watcher.on_game_breaked()
	watcher.on_game_stopped()
	assert_eq(found.size(), 0, "un run del agente no avisa: el agente ya ve sus errores")
	watcher.launched_by_harness = func() -> bool: return false
	watcher.enabled = func() -> bool: return false
	watcher.on_game_started()
	errors.add("error", "apagado", "res://a.gd", 1, "game")
	watcher.on_game_stopped()
	assert_eq(found.size(), 0, "apagado en Ajustes no avisa")
	watcher.enabled = func() -> bool: return true
	watcher.on_game_started()
	errors.add("error", "Node not found: \"@implicit_new\" (absolute paths from outside the active scene tree)", "", 0, "game")
	watcher.on_game_stopped()
	assert_eq(found.size(), 0, "el ruido del motor no cuenta")
	watcher.on_game_breaked()
	assert_eq(found.size(), 0, "sin run en curso, nada")


## m11-56: parar en un breakpoint no es un error; los errores de ese run se avisan al terminar.
func test_breakpoint_pause_is_not_an_error() -> void:
	var errors := FakeErrors.new()
	var watcher := _watcher(errors)
	var found := _collect(watcher)
	watcher.on_game_started()
	errors.add("error", "algo falló antes", "res://a.gd", 3, "game")
	watcher.break_reason = func() -> String: return "Breakpoint (0 - res://player.gd:12 - at function: _process)"
	watcher.on_game_breaked()
	assert_eq(found.size(), 0, "la pausa en un breakpoint no avisa")
	watcher.on_game_stopped()
	assert_eq(found.size(), 1, "los errores se avisan al terminar")
	assert_true(not found[0].breaked and str(found[0].lines[0]).contains("algo falló antes"), "sin la pausa · %s" % [found[0]])


func test_notice_and_prompt_texts() -> void:
	var entries: Array[Dictionary] = []
	for i in 14:
		entries.append({"seq": i + 1, "kind": "error", "message": "error %d" % (i + 1), "file": "res://a.gd", "line": i + 1, "source": "game"})
	var info := RunErrorWatcher.summary(false, "", entries)
	assert_eq(info.count, 14, "cuenta todos")
	assert_eq((info.lines as PackedStringArray).size(), RunErrorWatcher.MAX_LINES, "pero lleva las últimas %d" % RunErrorWatcher.MAX_LINES)
	I18n.set_locale("en")
	assert_eq(RunErrorWatcher.notice_title(info), "The game ended with errors", "título sin pausa")
	assert_eq(RunErrorWatcher.notice_text(info), "error 3 (res://a.gd:3)\n14 errors in total; they are in the details.", "cuerpo: el primero que se muestra y cuántos")
	var prompt := RunErrorWatcher.prompt(info)
	assert_true(prompt.begins_with("The user ran the game from the editor by hand (not with godot.run_scene) and it ended with errors."), "prompt: qué pasó · " + prompt.left(120))
	assert_true(prompt.contains("Errors since the game started (14, the last 12):\n<untrusted nonce=\"") and prompt.contains("#14 [game/error] res://a.gd:14 — error 14</untrusted nonce=\""), "prompt: los errores, en un sobre (m11-45) · " + prompt)
	var single := RunErrorWatcher.summary(true, "Invalid call (res://b.gd:8 in _ready)", entries.slice(0, 1))
	assert_eq(RunErrorWatcher.notice_title(single), "The game stopped in the debugger with an error", "título con pausa")
	assert_eq(RunErrorWatcher.notice_text(single), "Invalid call (res://b.gd:8 in _ready)", "cuerpo: el motivo de la pausa")
	assert_eq(RunErrorWatcher.notice_details(single), "Invalid call (res://b.gd:8 in _ready)\n#1 [game/error] res://a.gd:1 — error 1", "detalles: motivo y errores")
	assert_true(RunErrorWatcher.prompt(single).contains("stopped in the debugger with an error") and RunErrorWatcher.prompt(single).contains("Debugger: <untrusted nonce=\"") and RunErrorWatcher.prompt(single).contains("\">Invalid call (res://b.gd:8 in _ready)</untrusted"), "prompt con el motivo en un sobre")
	I18n.set_locale("es")
	assert_eq(RunErrorWatcher.notice_title(single), "El juego paró en el debugger con un error", "título en español")
	assert_true(RunErrorWatcher.prompt(single).begins_with("The user ran"), "el prompt sigue en inglés")
	I18n.set_locale("en")


## Revisión de next2 #22: el motivo se lee 0,5 s después; si el usuario ya continuó o hizo un paso, el
## panel no lo dice y podía ser un breakpoint: no se avisa la pausa, los errores salen al terminar.
func test_pause_already_over_is_not_reported() -> void:
	var errors := FakeErrors.new()
	var watcher := _watcher(errors)
	var found := _collect(watcher)
	watcher.on_game_started()
	errors.add("error", "algo falló antes", "res://a.gd", 3, "game")
	watcher.still_breaked = func() -> bool: return false
	watcher.on_game_breaked()
	assert_eq(found.size(), 0, "la pausa ya terminó: no avisa")
	watcher.on_game_stopped()
	assert_eq(found.size(), 1, "los errores se avisan al terminar")
	assert_false(found[0].breaked, "sin la pausa")


## m11-24: game_ended sale con cada run (para los hooks), con quién lo lanzó y los errores del juego,
## aunque el aviso de m11-55 esté apagado o el run sea del agente.
func test_game_ended_for_hooks() -> void:
	var errors := FakeErrors.new()
	var watcher := _watcher(errors)
	var ended: Array = []
	watcher.game_ended.connect(func(info: Dictionary) -> void: ended.append(info))
	watcher.on_game_started()
	watcher.on_game_stopped()
	assert_eq(ended.size(), 1, "un run limpio también")
	assert_eq([ended[0].by, ended[0].count], ["user", 0], "del usuario, sin errores")
	watcher.on_game_stopped()
	assert_eq(ended.size(), 1, "un stop sin run no repite")
	watcher.launched_by_harness = func() -> bool: return true
	watcher.enabled = func() -> bool: return false
	watcher.on_game_started()
	errors.add("error", "del agente", "res://a.gd", 1, "game")
	errors.add("error", "del editor", "res://b.gd", 2, "editor")
	watcher.on_game_stopped()
	assert_eq([ended[1].by, ended[1].count], ["agent", 1], "del agente, con el error del juego y no el del editor")
