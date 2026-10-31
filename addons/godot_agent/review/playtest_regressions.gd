@tool
extends RefCounted
## Un playtest que pasó, para repetirlo sin agente (m16-06): el game_script que el agente deja con su
## veredicto, en res://.godot_agent/playtests/regressions/. Un archivo JSON por pedido.

const DIR := "res://.godot_agent/playtests/regressions"
const PASS_MARK := "run() returned: true"
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


## El aviso con los resultados ({goal, passed, output}): texto y si pasaron todos.
static func summary(results: Array) -> Dictionary:
	var failed := results.filter(func(result: Dictionary) -> bool: return not result.passed)
	var lines: PackedStringArray = []
	for result: Dictionary in failed:
		lines.append("• %s\n  %s" % [result.goal, str(result.output).strip_edges().left(400)])
	return {"ok": failed.is_empty(), "failed": failed.size(), "details": "\n".join(lines)}
