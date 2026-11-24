@tool
extends RefCounted
## Variantes en paralelo (m11-90): el agente propone con godot.propose_variants varias
## formas de hacer lo mismo, el usuario elige cuáles van (y edita o agrega), y cada una se implementa
## en su propia copia (git worktree) a la vez. Las regresiones guardadas del proyecto las juzgan a
## todas igual: el juez corre regression_cli en cada copia con las regresiones del proyecto (rutas
## absolutas), no con las de la copia, que el agente podría cambiar y que, copiadas adentro, se
## commitearían en su rama. Acá lo que no depende del editor: limpiar lo propuesto, los textos de la
## pestaña, el prompt de cada copia y el juez.

const NativeTest := preload("../core/native_test.gd")
const CLI := "res://addons/godot_agent/playtest/regression_cli.gd"
## Cada regresión, tantas veces: una variante que pasa a veces es inestable, no buena.
const REPEAT := 3
const JUDGE_TIMEOUT_S := 900.0

const MIN := 2
const MAX := 4
const GOAL_MAX := 1000
const TEXT_MAX := 300
const LABEL_MAX := 24


## Las variantes sin vacías ni repetidas (sin distinguir mayúsculas), cada una cortada a TEXT_MAX.
static func clean(variants: Array) -> PackedStringArray:
	var result: PackedStringArray = []
	var seen := {}
	for variant: Variant in variants:
		var text := str(variant).strip_edges().left(TEXT_MAX)
		if text.is_empty() or seen.has(text.to_lower()):
			continue
		seen[text.to_lower()] = true
		result.append(text)
	return result


## Por qué no vale lo que propone el agente, o "". Puede proponer más de MAX: el usuario elige.
static func check(goal: String, variants: PackedStringArray) -> String:
	if goal.strip_edges().is_empty():
		return "`goal` is empty: say in one line what all the variants try to achieve."
	if variants.size() < MIN:
		return "Propose at least %d different variants (one line each)." % MIN
	return ""


## El nombre de la pestaña: «V2 · Coyote time + buffer».
static func tab_label(index: int, variant: String) -> String:
	var short := variant.strip_edges()
	if short.length() > LABEL_MAX:
		short = short.left(LABEL_MAX - 1).strip_edges() + "…"
	return "V%d · %s" % [index + 1, short]


## Lo que recibe el agente de la copia `index`: el objetivo, su variante, las otras (para no
## hacerlas) y qué la juzga. `judges`: cuántas regresiones guardadas tiene el proyecto, en `judges_dir`
## (ruta absoluta, fuera de la copia); `copy_project`: la carpeta del proyecto en la copia.
static func copy_prompt(goal: String, variants: PackedStringArray, index: int, judges: int, judges_dir: String = "", copy_project: String = "") -> String:
	var others: PackedStringArray = []
	for i in variants.size():
		if i != index:
			others.append("- V%d: %s" % [i + 1, variants[i]])
	var judged := "The project's %d saved regressions will judge every variant the same way, with their invariants and budgets, when your turn ends. They stay in the project, outside your copy; to try them yourself: \"$GODOT\" --headless --path %s --script %s -- %s" % [judges, copy_project, CLI, judges_dir] \
		if judges > 0 else "The project has no saved regressions, so the user will compare the variants by playing them."
	return "You are implementing variant V%d of %d for this goal: %s\n\nYour variant: %s\n\nThe other variants are being built in parallel in their own copies, so don't build them here:\n%s\n\n%s Implement your variant fully and keep the rest of the game working; check it headless as the guide above says. When you are done, end your turn with a short summary of what you changed and anything the user should try when playing it." % [
		index + 1, variants.size(), goal.strip_edges().left(GOAL_MAX), variants[index], "\n".join(others), judged]


## Lo que vuelve al agente que propuso, según lo que eligió el usuario.
static func result_text(opened: PackedStringArray, failed: PackedStringArray) -> String:
	if opened.is_empty():
		return "No copy could be opened: %s" % "; ".join(failed)
	var text := "The user picked %d variants; each one is being built in its own tab and copy: %s. Don't build them here. The user will compare them and apply one." % [opened.size(), ", ".join(opened)]
	if not failed.is_empty():
		text += " Could not open: %s" % "; ".join(failed)
	return text


## Juzga la copia (m11-90): la importa (una copia nueva no tiene .godot/) y corre regression_cli con
## las regresiones de `judges_dir`, REPEAT veces cada una, sin guardar bases. {ok, error, report}:
## `report` es el JSON de --report (ok, failed, flaky, regressions).
static func judge(copy_project: String, judges_dir: String, report_path: String) -> Dictionary:
	var godot := OS.get_executable_path()
	report_path = ProjectSettings.globalize_path(report_path)  # el otro Godot tiene otro user://
	var imported: Dictionary = await NativeTest._run_process(godot, PackedStringArray(["--headless", "--no-header", "--path", copy_project, "--import"]), NativeTest.IMPORT_TIMEOUT_S)
	if not str(imported.error).is_empty():
		return {"ok": false, "error": "The import failed: %s" % imported.error, "report": {}}
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	DirAccess.remove_absolute(report_path)
	var ran: Dictionary = await NativeTest._run_process(godot, PackedStringArray(["--headless", "--no-header", "--path", copy_project, "--script", CLI, "--",
		"--repeat=%d" % REPEAT, "--no-baselines", "--report=" + report_path, judges_dir]), JUDGE_TIMEOUT_S)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path)) if FileAccess.file_exists(report_path) else null
	if not parsed is Dictionary:
		var tail := "\n".join(PackedStringArray(Array(ran.lines).slice(-8)))
		return {"ok": false, "error": str(ran.error) if not str(ran.error).is_empty() else "The regressions didn't run (exit %d):\n%s" % [int(ran.code), tail], "report": {}}
	return {"ok": true, "error": "", "report": parsed}


## Una línea con el resultado del juez: «3 of 4 pass · 1 flaky · frame_ms_p95 8.2». `t`: I18n.t.
static func judge_line(result: Dictionary, t: Callable) -> String:
	if not result.get("ok", false):
		var error := str(result.get("error", "")).left(300)
		return t.call("Could not judge it: %s") % error  # i18n
	var report: Dictionary = result.report
	var regressions: Array = report.get("regressions", [])
	var passed := regressions.filter(func(r: Dictionary) -> bool: return r.get("passed", false)).size()
	var parts: PackedStringArray = [t.call("%d of %d regressions pass") % [passed, regressions.size()]]  # i18n
	if int(report.get("flaky", 0)) > 0:
		parts.append(t.call("%d flaky") % int(report.flaky))  # i18n
	var worst := worst_measured(regressions)
	for metric: String in worst:
		var value := float(worst[metric])
		parts.append("%s %s" % [metric, str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value])
	return " · ".join(parts)


## El peor valor de cada métrica entre las regresiones de un report.
static func worst_measured(regressions: Array) -> Dictionary:
	var worst := {}
	for regression: Dictionary in regressions:
		var measured: Dictionary = regression.get("measured", {})
		for metric: String in measured:
			worst[metric] = maxf(float(worst.get(metric, -INF)), float(measured[metric]))
	return worst


## El texto de la comparación (m11-90), una línea por variante. `rows`: [{label, state, judged?,
## changed?}], con `state` "working", "judging", "judged" o "closed". `t`: I18n.t.
static func comparison_text(rows: Array, t: Callable) -> String:
	var lines: PackedStringArray = []
	for row: Dictionary in rows:
		var shown := ""
		match str(row.get("state", "")):
			"working":
				shown = t.call("working…")  # i18n
			"judging":
				shown = t.call("judging…")  # i18n
			"closed":
				shown = t.call("closed")  # i18n
			_:
				var changed := int(row.get("changed", 0))
				shown = judge_line(row.get("judged", {}), t) + " · " + t.call("%d files changed") % changed  # i18n
		lines.append("• %s: %s" % [row.get("label", ""), shown])
	lines.append(t.call("«Play» opens the game of that copy; «Apply» puts its changes in the project, uncommitted. Close the other tabs to keep their branch or discard them."))  # i18n
	return "\n".join(lines)


## Lo que guarda Restart and resume de una variante (m11-90): todo menos «juzgando», que no sigue
## después del reinicio (el turno que lo pidió ya terminó; el próximo vuelve a juzgar).
static func to_saved(variant: Dictionary) -> Dictionary:
	var saved := variant.duplicate(true)
	saved.erase("judging")
	if saved.get("changed") is PackedStringArray:
		saved.changed = Array(saved.changed)
	return saved


## La variante al reabrir: `tab_ids` lleva el id de pestaña de antes del reinicio al de ahora, para la
## que propuso (`from`). Del JSON los números vuelven como float y la lista de archivos como Array.
static func from_saved(saved: Dictionary, tab_ids: Dictionary) -> Dictionary:
	var variant := saved.duplicate(true)
	variant.index = int(variant.get("index", 0))
	variant.turns = int(variant.get("turns", 0))
	variant.from = str(tab_ids.get(str(variant.get("from", "")), ""))
	if variant.has("changed"):
		variant.changed = PackedStringArray(variant.changed)
	return variant
