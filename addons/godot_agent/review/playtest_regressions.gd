@tool
extends RefCounted
## Un playtest que pasó, para repetirlo sin agente (m16-06): el game_script que el agente deja con su
## veredicto, en res://.godot_agent/playtests/regressions/. Un archivo JSON por pedido.

const UntrustedText := preload("../mcp/untrusted_text.gd")

const DIR := "res://.godot_agent/playtests/regressions"
const PASS_MARK := "run() returned: true"
## Cuántas veces se puede repetir cada regresión de una tanda.
const MAX_REPEAT := 20
## Corridas de una marcada inestable que falla con `repeat` 1 (retry_marked).
const MARKED_TRIES := 3
const FLAKY := "flaky"  # i18n
const PASSED_OF := "passed %d of %d"  # i18n
## Cuánto de la salida de cada regresión que falla muestra el aviso.
const DETAILS_CHARS := 400
## APIs que game_script no puede usar: el evaluador del One-shot y el Playtest no tocan el proyecto (m15-12).
## shortcut: una lista de nombres frena un descuido, no a alguien que quiera esquivarla; si eso importa, hace falta correr el juego en un sandbox.
const SCRIPT_BLOCKED := "\\b(FileAccess|DirAccess|ResourceSaver|ConfigFile|ZIPPacker|OS\\s*\\.\\s*(execute|execute_with_pipe|create_process|create_instance|shell_open|shell_show_in_file_manager|move_to_trash|kill)|ProjectSettings\\s*\\.\\s*save)\\b|\\.save_(png|jpg|webp|exr)\\s*\\("

var base: String


func _init(dir: String = DIR) -> void:
	base = dir


## Guarda (o reemplaza, si es el mismo pedido) y devuelve la ruta.
func save(goal: String, scene: String, code: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var path := base.path_join("%s.json" % goal.strip_edges().md5_text().left(12))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify({"goal": goal.strip_edges(), "scene": scene, "code": code}, "\t"))
	file.close()
	return path


func list() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)):
		return entries
	for name: String in DirAccess.get_files_at(base):
		if name.get_extension() != "json":
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(base.path_join(name)))
		if parsed is Dictionary and parsed.get("scene") is String and parsed.get("code") is String:
			parsed["file"] = base.path_join(name)
			entries.append(parsed)
	return entries


## La API prohibida que usa un script, o "". Acá y no en RunTools porque la línea de comandos corre sin
## editor, y un script guardado por el agente pasa por la misma guarda que game_script.
static func blocked_api(code: String) -> String:
	var found := RegEx.create_from_string(SCRIPT_BLOCKED).search(code)
	return found.get_string(0) if found else ""


## Solo pasa si el script devolvió true: sin errores ni vencimiento, que también dejan otro texto.
static func passed(output: String) -> bool:
	return output.contains(PASS_MARK) and not output.contains("Script error") and not output.contains("timed out")


## Con el sabotaje puesto (`sabotage`: código que rompe en el juego lo que la regresión prueba) tiene
## que terminar y no devolver true; si pasa igual, no detecta el bug (m16-09). Un error o un
## vencimiento no cuentan como detectarlo.
static func detects(output_with_sabotage: String) -> bool:
	return output_with_sabotage.contains("run() returned:") and not passed(output_with_sabotage) and not output_with_sabotage.contains("Script error")


## Una regresión corrida `runs` veces (m11-42): {goal, passed, output, passes, runs, flaky, file}.
## Pasa solo si pasaron todas (pass^k). Inestable: pasó algunas y falló otras. El texto es el de la
## primera que falló.
static func tally(entry: Dictionary, results: Array) -> Dictionary:
	var passes := results.filter(func(result: Dictionary) -> bool: return result.passed).size()
	var failing := results.filter(func(result: Dictionary) -> bool: return not result.passed)
	var tallied := {"goal": str(entry.get("goal", "")), "file": str(entry.get("file", "")), "passes": passes, "runs": results.size(),
		"passed": not results.is_empty() and passes == results.size(), "output": str(failing[0].output) if not failing.is_empty() else ""}
	tallied.flaky = passes > 0 and passes < results.size()
	return tallied


## Corriendo una vez (`repeat` 1), una marcada inestable que falla se reintenta hasta MARKED_TRIES
## corridas en total, hasta que pase una: si pasa alguna es inestable, y si fallan todas, falla. Así
## una inestable que se rompió de verdad no queda tapada por la marca. true si hay que correrla otra vez.
static func retry_marked(entry: Dictionary, runs: Array, repeat: int) -> bool:
	return repeat == 1 and is_flaky(entry) and runs.size() < MARKED_TRIES and runs.all(func(result: Dictionary) -> bool: return not result.passed)


## La última repetición de varias corridas la dejó como inestable.
static func is_flaky(entry: Dictionary) -> bool:
	var runs: Variant = entry.get("runs")
	return runs is Dictionary and int(runs.get("passed", 0)) > 0 and int(runs.get("passed", 0)) < int(runs.get("total", 0))


## Guarda en la regresión que es inestable y cuántas pasaron de cuántas (solo con 2 o más corridas:
## con una no se sabe). Una que después pasa todas, o falla todas, deja de estar marcada. El archivo se
## versiona: se reescribe solo si la marca cambia (revisión de next2 #15).
static func record_runs(tallied: Dictionary) -> void:
	var path := str(tallied.get("file", ""))
	if int(tallied.runs) < 2 or path.is_empty() or not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var passes := int(tallied.passes)
	var total := int(tallied.runs)
	var before: Variant = parsed.get("runs")
	if passes == 0 or passes == total:
		if before == null:
			return
		parsed.erase("runs")
	elif before is Dictionary and int(before.get("passed", -1)) == passes and int(before.get("total", -1)) == total:
		return
	else:
		parsed.runs = {"passed": passes, "total": total, "at": int(Time.get_unix_time_from_system())}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(parsed, "\t"))
		file.close()


## Cuántas de `entries` quedaron marcadas como inestables.
static func flaky_count(entries: Array[Dictionary]) -> int:
	return entries.filter(func(entry: Dictionary) -> bool: return is_flaky(entry)).size()


## El aviso con los resultados ({goal, passed, output}, o los de tally): texto, cuántas fallan y
## cuántas son inestables. Una inestable no cuenta como falla salvo con `fail_on_flaky`.
## `translate`: Callable(msgid) -> String para el panel (la línea de comandos queda en inglés).
static func summary(results: Array, fail_on_flaky: bool = false, translate: Callable = Callable()) -> Dictionary:
	var failed := results.filter(func(result: Dictionary) -> bool: return not result.passed and not result.get("flaky", false))
	var flaky := results.filter(func(result: Dictionary) -> bool: return result.get("flaky", false))
	var lines: PackedStringArray = []
	for result: Dictionary in failed:
		var count := count_text(result, translate)
		lines.append("• %s%s\n  %s" % [result.goal, " (%s)" % count if not count.is_empty() else "", _short_output(result.output)])
	for result: Dictionary in flaky:
		var count := count_text(result, translate)
		var flaky_word: String = translate.call(FLAKY) if translate.is_valid() else FLAKY
		lines.append("• %s (%s)\n  %s" % [result.goal, flaky_word + (": " + count if not count.is_empty() else ""), _short_output(result.output)])
	return {"ok": failed.is_empty() and (flaky.is_empty() or not fail_on_flaky), "failed": failed.size(), "flaky": flaky.size(), "details": "\n".join(lines)}


## La salida de una regresión para el aviso: los primeros DETAILS_CHARS caracteres, con el sobre que
## el corte deja abierto cerrado (la salida de game_script trae los textos del juego en sobres).
static func _short_output(output: Variant) -> String:
	return UntrustedText.close_cut(str(output).strip_edges().left(DETAILS_CHARS))


## «passed 2 of 3» con varias corridas; "" con una.
static func count_text(result: Dictionary, translate: Callable = Callable()) -> String:
	var runs := int(result.get("runs", 1))
	if runs < 2:
		return ""
	var text: String = translate.call(PASSED_OF) if translate.is_valid() else PASSED_OF
	return text % [int(result.get("passes", 0)), runs]
