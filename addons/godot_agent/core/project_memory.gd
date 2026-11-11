@tool
extends RefCounted
## Lo que se recuerda del proyecto (m11-36), fuera de lo que guardan los playtests (PlaytestMemory):
##
## - «Recordado»: una sección entre marcadores en el archivo de instrucciones del agente activo
##   (CLAUDE.md, AGENTS.md, GEMINI.md…), una línea por recuerdo. La escribe `/remember` y la pestaña
##   Memoria de Extensiones. El resto del archivo es del usuario y del agente: no se toca (como la
##   sección de ProjectFacts).
## - Las memorias de Claude Code: `<carpeta de config de la cuenta>/projects/<ruta del proyecto>/memory/*.md`.
##   ACP no las expone, así que se leen del disco, y solo esos .md (nada más de la carpeta de config):
##   al abrir la pestaña Memoria, nunca en segundo plano. Borrar una va a la papelera del sistema.

const AtomicFile := preload("atomic_file.gd")

const BEGIN := "<!-- godot-agent:remembered -->"
const END := "<!-- /godot-agent:remembered -->"
const HEADING := "## Remembered by the harness"
const INTRO := "Facts the user asked to remember with /remember. Manage them from Extensions → Memory."
const CLAUDE_CONFIG_VARIABLE := "CLAUDE_CONFIG_DIR"
const CLAUDE_DEFAULT_DIR := "~/.claude"
const CLAUDE_INDEX := "MEMORY.md"
## Más largo que esto, una línea de /remember se corta (es una nota, no un documento).
const LINE_MAX := 500


# --- la sección «Recordado» de un archivo de instrucciones ----------------------------------------

## Los recuerdos de la sección (sin el «- »), en orden.
static func remembered(text: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var start := text.find(BEGIN)
	var end := text.find(END)
	if start < 0 or end < start:
		return lines
	for line: String in text.substr(start + BEGIN.length(), end - start - BEGIN.length()).split("\n"):
		if line.begins_with("- "):
			lines.append(line.substr(2).strip_edges())
	return lines


## El texto con la sección reescrita con `lines`. Sin recuerdos, la sección sale entera; sin sección
## previa, va al final del archivo.
static func with_remembered(text: String, lines: PackedStringArray) -> String:
	var section := ""
	if not lines.is_empty():
		var body: PackedStringArray = [BEGIN, HEADING, "", INTRO, ""]
		for line: String in lines:
			body.append("- " + line)
		body.append(END)
		section = "\n".join(body)
	var start := text.find(BEGIN)
	var end := text.find(END)
	if start >= 0 and end > start:
		var before := text.left(start)
		var after := text.substr(end + END.length())
		if section.is_empty():
			# Sin la sección, que no queden renglones vacíos de más donde estaba.
			var head := before.rstrip("\n")
			var rest := after.lstrip("\n")
			if head.is_empty():
				return rest
			return head + "\n" if rest.is_empty() else head + "\n\n" + rest
		return before + section + after
	if section.is_empty():
		return text
	if text.strip_edges().is_empty():
		return section + "\n"
	return text.rstrip("\n") + "\n\n" + section + "\n"


## Una línea de recuerdo limpia: un renglón, sin «- » al principio, hasta LINE_MAX.
static func clean_line(value: String) -> String:
	var line := " ".join(value.strip_edges().split("\n", false)).strip_edges()
	while line.begins_with("- ") or line.begins_with("* "):
		line = line.substr(2).strip_edges()
	return line if line.length() <= LINE_MAX else line.left(LINE_MAX - 1) + "…"


static func read_remembered(path: String) -> PackedStringArray:
	return remembered(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else PackedStringArray()


## Agrega un recuerdo al archivo (lo crea si no existe). "" o el error. Uno repetido no se duplica.
static func remember(path: String, value: String) -> String:
	var line := clean_line(value)
	if line.is_empty():
		return "empty"
	var lines := read_remembered(path)
	if line in lines:
		return ""
	lines.append(line)
	return _write_lines(path, lines)


## Saca un recuerdo. "" o el error.
static func forget(path: String, value: String) -> String:
	var lines := read_remembered(path)
	var at := lines.find(value)
	if at < 0:
		return ""
	lines.remove_at(at)
	return _write_lines(path, lines)


## Cambia un recuerdo por otro texto ("" lo saca). "" o el error.
static func replace(path: String, old: String, value: String) -> String:
	var line := clean_line(value)
	if line.is_empty():
		return forget(path, old)
	var lines := read_remembered(path)
	var at := lines.find(old)
	if at < 0:
		lines.append(line)
	else:
		lines[at] = line
	return _write_lines(path, lines)


static func _write_lines(path: String, lines: PackedStringArray) -> String:
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var text := with_remembered(previous, lines)
	if text == previous:
		return ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := AtomicFile.write_text(path, text)
	return "" if error == OK else error_string(error)


# --- memorias de Claude Code ----------------------------------------------------------------------

## La carpeta de config de Claude Code de un entorno (el del perfil con su cuenta): la variable del
## perfil, la del editor o ~/.claude.
static func claude_config_dir(env: Dictionary, home: String) -> String:
	var dir := str(env.get(CLAUDE_CONFIG_VARIABLE, ""))
	if dir.is_empty():
		dir = OS.get_environment(CLAUDE_CONFIG_VARIABLE)
	if dir.is_empty():
		dir = CLAUDE_DEFAULT_DIR
	if dir == "~" or dir.begins_with("~/"):
		dir = home + dir.substr(1)
	return dir.replace("\\", "/").simplify_path().trim_suffix("/")


## Cómo nombra Claude Code la carpeta de un proyecto: la ruta absoluta con todo lo que no es letra o
## número cambiado por «-» (/home/a/my.game → -home-a-my-game).
static func claude_project_slug(project_path: String) -> String:
	var path := project_path.replace("\\", "/").trim_suffix("/")
	return RegEx.create_from_string("[^A-Za-z0-9]").sub(path, "-", true)


static func claude_memory_dir(config_dir: String, project_path: String) -> String:
	return config_dir.path_join("projects").path_join(claude_project_slug(project_path)).path_join("memory")


## Las memorias de la carpeta (solo los .md de esa carpeta, sin subcarpetas): [{path, file, name,
## description, text, index}], el índice (MEMORY.md) primero.
static func claude_memories(dir: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		return result
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String) -> bool: return f.get_extension().to_lower() == "md")
	files.sort()
	if CLAUDE_INDEX in files:
		files.erase(CLAUDE_INDEX)
		files.push_front(CLAUDE_INDEX)
	for file: String in files:
		var path := dir.path_join(file)
		var text := FileAccess.get_file_as_string(path)
		var front := frontmatter(text)
		result.append({"path": path, "file": file, "index": file == CLAUDE_INDEX,
			"name": str(front.get("name", file.get_basename())), "description": str(front.get("description", "")), "text": text})
	return result


## Los campos `clave: valor` del frontmatter (entre «---»), sin anidar.
static func frontmatter(text: String) -> Dictionary:
	var result := {}
	if not text.begins_with("---"):
		return result
	var end := text.find("\n---", 3)
	if end < 0:
		return result
	for line: String in text.substr(3, end - 3).split("\n"):
		var colon := line.find(":")
		if colon > 0 and not line.begins_with(" "):
			result[line.left(colon).strip_edges()] = line.substr(colon + 1).strip_edges()
	return result


## Manda una memoria a la papelera y saca su renglón del índice. Solo un .md que esté directo en
## `dir` y que no sea el índice. "" o el error. `trash`: para las pruebas (por defecto, OS.move_to_trash).
static func trash_claude_memory(path: String, dir: String, trash: Callable = Callable()) -> String:
	var clean := path.simplify_path()
	if clean.get_base_dir() != dir.simplify_path() or clean.get_extension().to_lower() != "md" or clean.get_file() == CLAUDE_INDEX:
		return "not a memory file"
	if not FileAccess.file_exists(clean):
		return "not found"
	var error: int = trash.call(clean) if trash.is_valid() else OS.move_to_trash(clean)
	if error != OK:
		return error_string(error)
	var index := dir.path_join(CLAUDE_INDEX)
	if FileAccess.file_exists(index):
		var text := FileAccess.get_file_as_string(index)
		var kept := without_index_line(text, clean.get_file())
		if kept != text:
			AtomicFile.write_text(index, kept)
	return ""


## El índice sin los renglones que enlazan a `file` (`[…](file)`).
static func without_index_line(text: String, file: String) -> String:
	var kept: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.contains("](%s)" % file):
			kept.append(line)
	return "\n".join(kept)
