@tool
extends RefCounted
## Medir las regresiones con mutantes (m11-41). Arma los mutantes de los scripts de las escenas de las
## regresiones guardadas (GDScriptMutator) y corre cada uno en un Godot headless aparte con
## regression_cli --mutant: el script cambia solo en la memoria de ese proceso y un SaveGuard aborta
## si algo intenta guardar. Un proceso por mutante: uno que cuelga (timeout, cuenta como detectado) o
## se cae no arrastra a los demás. Antes corren las regresiones sin mutar: si alguna falla, no se mide.
## Sirve al editor y a la CLI: solo espera con timers del SceneTree que esté corriendo.

const GDScriptMutator := preload("gdscript_mutator.gd")
const CLI := "res://addons/godot_agent/playtest/regression_cli.gd"
const RESULT_FILE := "res://.godot_agent/playtests/mutation.json"
const DEFAULT_COUNT := 20
const POLL_S := 0.1
## Un mutante tiene hasta TIMEOUT_FACTOR veces lo que tardó la corrida sin mutar, más el arranque.
const TIMEOUT_FACTOR := 3.0
const TIMEOUT_EXTRA_S := 15.0

const STATUS_KILLED := "killed"
const STATUS_SURVIVED := "survived"
const STATUS_INVALID := "invalid"
const STATUS_TIMEOUT := "timeout"
const STATUS_ERROR := "error"

const ERROR_NONE_SAVED := "There are no saved regressions yet: a playtest that passes saves one."  # i18n
const ERROR_BASELINE_FAILS := "The regressions fail without mutants: fix them first, then measure."  # i18n
const ERROR_BASELINE_BROKEN := "The regressions could not run in a separate Godot."  # i18n
const ERROR_CANCELLED := "Measuring the regressions was cancelled."  # i18n
## Sobrevivientes con botón «Abrir» en el aviso (el resto va en la sección).
const OPEN_BUTTONS := 3

## Callable(done: int, total: int, mutant: Dictionary): después de cada mutante.
var on_progress: Callable
var executable: String = OS.get_executable_path()
var project: String = ProjectSettings.globalize_path("res://")
## Carpeta del usuario para los resultados de cada proceso (no la del proyecto).
var scratch: String = ProjectSettings.globalize_path("user://mutation")
var _cancelled: bool = false
var _pid: int = 0


func cancel() -> void:
	_cancelled = true
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)


## Los scripts del proyecto que usa una escena (sus nodos y lo que precargan), sin addons/ ni autoloads.
static func scripts_of(scene: String) -> PackedStringArray:
	var autoloads: Dictionary = {}
	for property: Dictionary in ProjectSettings.get_property_list():
		var name := str(property.name)
		if name.begins_with("autoload/"):
			autoloads[str(ProjectSettings.get_setting(name)).trim_prefix("*")] = true
	var seen: Dictionary = {}
	var pending: Array[String] = [scene]
	var scripts: PackedStringArray = []
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		if path.get_extension() == "gd" and not path.begins_with("res://addons/") and not autoloads.has(path):
			scripts.append(path)
		for dependency: String in ResourceLoader.get_dependencies(path):
			var dep := dependency.get_slice("::", dependency.get_slice_count("::") - 1) if dependency.contains("::") else dependency
			if dep.begins_with("uid://"):
				dep = ResourceUID.get_id_path(ResourceUID.text_to_id(dep)) if ResourceUID.has_id(ResourceUID.text_to_id(dep)) else ""
			if dep.begins_with("res://") and not dep.begins_with("res://addons/") and dep.get_extension() in ["gd", "tscn", "scn", "tres", "res"]:
				pending.append(dep)
	scripts.sort()
	return scripts


## Los mutantes a correr: hasta `count`, cada uno con las regresiones (archivos) cuya escena usa su script.
static func plan(entries: Array[Dictionary], count: int = DEFAULT_COUNT) -> Array[Dictionary]:
	var regressions_of: Dictionary = {}
	for entry: Dictionary in entries:
		for script: String in scripts_of(str(entry.get("scene", ""))):
			if not regressions_of.has(script):
				regressions_of[script] = []  # Array: un PackedStringArray sacado del diccionario es una copia
			(regressions_of[script] as Array).append(str(entry.get("file", "")))
	var all: Array[Dictionary] = []
	var scripts := regressions_of.keys()
	scripts.sort()
	for script: String in scripts:
		all.append_array(GDScriptMutator.mutants(FileAccess.get_file_as_string(script), script))
	var chosen := GDScriptMutator.sample(all, count)
	for mutant: Dictionary in chosen:
		mutant.regressions = PackedStringArray(regressions_of[mutant.path])
		mutant.change = GDScriptMutator.describe(FileAccess.get_file_as_string(mutant.path).split("\n")[int(mutant.line) - 1], mutant)
	return chosen


## Corre la medición. {ok, error, baseline_s, mutants: [mutante + status, killed_by: [archivos]], score…}.
## Cada mutante corre todas sus regresiones, no hasta la primera que lo detecta: así el conteo por
## regresión es exacto y «no detecta nada» quiere decir eso.
func run(entries: Array[Dictionary], count: int = DEFAULT_COUNT) -> Dictionary:
	_cancelled = false
	var files := PackedStringArray()
	for entry: Dictionary in entries:
		files.append(str(entry.get("file", "")))
	if files.is_empty():
		return {"ok": false, "error": ERROR_NONE_SAVED}
	var started := Time.get_ticks_msec()
	var baseline := await _process(files, {}, 600.0)
	var baseline_s := (Time.get_ticks_msec() - started) / 1000.0
	if baseline.code != 0:
		return {"ok": false, "error": ERROR_BASELINE_FAILS if baseline.code == 1 else ERROR_BASELINE_BROKEN}
	var mutants := plan(entries, count)
	var timeout_s := baseline_s * TIMEOUT_FACTOR + TIMEOUT_EXTRA_S
	for i in mutants.size():
		if _cancelled:
			return {"ok": false, "error": ERROR_CANCELLED, "cancelled": true}
		var mutant: Dictionary = mutants[i]
		var ran := await _process(mutant.regressions, mutant, timeout_s)
		mutant.merge(ran.report, true)
		if ran.timed_out:
			mutant.status = STATUS_TIMEOUT
		elif not ran.report.has("status"):
			mutant.status = STATUS_ERROR
			mutant.output = "The mutant run ended with exit code %d and no result." % int(ran.code)
		if on_progress.is_valid():
			on_progress.call(i + 1, mutants.size(), mutant)
	var result := score(mutants)
	result.ok = true
	result.error = ""
	result.baseline_s = baseline_s
	result.mutants = mutants
	result.regressions = files
	return result


## {killed, survived, invalid, timeouts, errors, measured, percent, by_regression: {archivo: atrapados}}.
## Un timeout cuenta como detectado; los no válidos y los errores no cuentan.
static func score(mutants: Array) -> Dictionary:
	var counts := {STATUS_KILLED: 0, STATUS_SURVIVED: 0, STATUS_INVALID: 0, STATUS_TIMEOUT: 0, STATUS_ERROR: 0}
	var by_regression: Dictionary = {}
	for mutant: Dictionary in mutants:
		var status := str(mutant.get("status", STATUS_ERROR))
		counts[status] = int(counts.get(status, 0)) + 1
		for file: String in mutant.get("regressions", PackedStringArray()):
			if not by_regression.has(file):
				by_regression[file] = 0
		if status == STATUS_KILLED and mutant.get("killed_by") is Array:
			for file: String in mutant.killed_by:
				by_regression[file] = int(by_regression.get(file, 0)) + 1
	var detected: int = counts[STATUS_KILLED] + counts[STATUS_TIMEOUT]
	var measured: int = detected + counts[STATUS_SURVIVED]
	return {"killed": counts[STATUS_KILLED], "survived": counts[STATUS_SURVIVED], "invalid": counts[STATUS_INVALID],
		"timeouts": counts[STATUS_TIMEOUT], "errors": counts[STATUS_ERROR], "detected": detected, "measured": measured,
		"percent": roundi(100.0 * detected / measured) if measured > 0 else 0, "by_regression": by_regression}


## Un Godot headless con regression_cli; con `mutant`, en modo mutante. {code, timed_out, report}.
func _process(files: PackedStringArray, mutant: Dictionary, timeout_s: float) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(scratch)
	var result_path := scratch.path_join("mutant.json")
	DirAccess.remove_absolute(result_path)
	var args := PackedStringArray(["--headless", "--quiet", "--path", project, "--script", CLI, "--"])
	if not mutant.is_empty():
		var sent := {"path": mutant.path, "line": mutant.line, "col": mutant.col, "before": mutant.before, "after": mutant.after, "op": mutant.op}
		args.append("--mutant=" + Marshalls.utf8_to_base64(JSON.stringify(sent)))
		args.append("--mutant-result=" + result_path)
	args.append_array(files)
	_pid = OS.create_process(executable, args)
	if _pid <= 0:
		return {"code": -1, "timed_out": false, "report": {}}
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while OS.is_process_running(_pid):
		if Time.get_ticks_msec() > deadline or _cancelled:
			OS.kill(_pid)
			_pid = 0
			return {"code": -1, "timed_out": not _cancelled, "report": {}}
		await tree.create_timer(POLL_S).timeout
	var code := OS.get_process_exit_code(_pid)
	_pid = 0
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path)) if FileAccess.file_exists(result_path) else null
	return {"code": code, "timed_out": false, "report": report if report is Dictionary else {}}


## El aviso del chat con el resultado: {title, text, sections: [{title, text}], survivors: [{path, line}], level_warning}.
## `goals`: archivo de cada regresión → su objetivo. `t`: la traducción (I18n.t) para los textos.
static func notice(result: Dictionary, goals: Dictionary, t: Callable) -> Dictionary:
	var title: String = t.call("Regressions: mutation score %d/%d (%d %%)") % [int(result.detected), int(result.measured), int(result.percent)]  # i18n
	var lines: PackedStringArray = [t.call("Each mutant is one small change to the game's code, made only in the memory of a separate Godot: the project's files are not touched. A mutant no regression notices is a bug they would let through.")]  # i18n
	var extra: PackedStringArray = []
	if int(result.timeouts) > 0:
		extra.append(t.call("%d hung the game (counted as detected)") % int(result.timeouts))  # i18n
	if int(result.invalid) > 0:
		extra.append(t.call("%d did not compile (not counted)") % int(result.invalid))  # i18n
	if int(result.errors) > 0:
		extra.append(t.call("%d could not run (not counted)") % int(result.errors))  # i18n
	if not extra.is_empty():
		lines.append(" · ".join(extra))
	var sections: Array[Dictionary] = []
	var survived: PackedStringArray = []
	var survivors: Array[Dictionary] = []
	for mutant: Dictionary in result.get("mutants", []):
		if mutant.get("status") == STATUS_SURVIVED:
			survived.append("%s:%d · %s" % [str(mutant.path).trim_prefix("res://"), int(mutant.line), mutant.change])
			survivors.append({"path": mutant.path, "line": int(mutant.line)})
	if not survived.is_empty():
		var not_detected: String = t.call("Not detected")  # i18n
		sections.append({"title": "%s · %d" % [not_detected, survived.size()], "text": "\n".join(survived)})
	var by: PackedStringArray = []
	var by_regression: Dictionary = result.get("by_regression", {})
	for file: String in by_regression:
		var goal := str(goals.get(file, file.get_file()))
		var nothing: String = t.call("detects nothing")  # i18n
		var caught: String = t.call("caught %d")  # i18n
		by.append("«%s»: %s" % [goal, nothing if int(by_regression[file]) == 0 else caught % int(by_regression[file])])
	if not by.is_empty():
		var by_title: String = t.call("By regression")  # i18n
		sections.append({"title": by_title, "text": "\n".join(by)})
	return {"title": title, "text": "\n".join(lines), "sections": sections, "survivors": survivors.slice(0, OPEN_BUTTONS),
		"level_warning": int(result.percent) < 80 or by_regression.values().has(0)}
