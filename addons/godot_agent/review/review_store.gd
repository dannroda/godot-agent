@tool
extends RefCounted
## Hallazgos de la última revisión (spec §9.4). Los llena SessionController al terminar un turno en
## modo Revisar; los leen las anotaciones del Script Editor y el panel del dock.
## Cada turno con un bloque `findings` reemplaza la revisión anterior (D23).

signal changed

const FindingsParser := preload("findings_parser.gd")
const AtomicFile := preload("../core/atomic_file.gd")

const SEVERITY_LABELS: Dictionary = {
	"bug": "bug",  # i18n
	"order": "execution order",  # i18n
	"perf": "performance",  # i18n
	"style": "style",  # i18n
}
const SEVERITY_SHORT: Dictionary = {
	"bug": "BUG",  # i18n
	"order": "ORDER",  # i18n
	"perf": "PERF",  # i18n
	"style": "STYLE",  # i18n
}
const CLAUDE_MD_PATH := "res://CLAUDE.md"

## Cada hallazgo es el Dictionary del parser más `id` (int, estable mientras dure la revisión).
var findings: Array[Dictionary] = []
## Unix del turno que produjo la revisión; 0 = no hubo revisión todavía.
var reviewed_at: int = 0

var _next_id: int = 1


func set_findings(list: Array[Dictionary]) -> void:
	findings.clear()
	for finding: Dictionary in list:
		var copy := finding.duplicate()
		copy["id"] = _next_id
		_next_id += 1
		findings.append(copy)
	findings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a.path, a.line] < [b.path, b.line])
	reviewed_at = int(Time.get_unix_time_from_system())
	changed.emit()


## Busca un bloque `findings` en el texto de un turno. Devuelve si había uno (aunque esté vacío).
func ingest_turn_text(text: String, project_root: String = "") -> bool:
	if not text.contains("\"findings\""):
		return false
	var parsed := FindingsParser.parse(text, project_root)
	if parsed.findings.is_empty() and not RegEx.create_from_string("\"findings\"\\s*:\\s*\\[\\s*\\]").search(text):
		return false  # mencionó "findings" pero no hubo un bloque legible
	set_findings(parsed.findings)
	return true


func clear() -> void:
	findings.clear()
	reviewed_at = 0
	changed.emit()


func dismiss(id: int) -> void:
	for i in findings.size():
		if int(findings[i].id) == id:
			findings.remove_at(i)
			changed.emit()
			return


func get_finding(id: int) -> Dictionary:
	for finding: Dictionary in findings:
		if int(finding.id) == id:
			return finding
	return {}


func for_path(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for finding: Dictionary in findings:
		if finding.path == path:
			out.append(finding)
	return out


func counts() -> Dictionary:
	var out := {"bug": 0, "order": 0, "perf": 0, "style": 0}
	for finding: Dictionary in findings:
		out[finding.severity] = int(out.get(finding.severity, 0)) + 1
	return out


func paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for finding: Dictionary in findings:
		if not finding.path in out:
			out.append(finding.path)
	return out


## Carpeta común de los archivos con hallazgos ("src/", "res://" si no hay una).
func scope_label() -> String:
	var dirs: Array[String] = []
	for path: String in paths():
		dirs.append(path.trim_prefix("res://").get_base_dir())
	if dirs.is_empty():
		return "res://"
	var common: String = dirs[0]
	for dir: String in dirs:
		while not common.is_empty() and dir != common and not dir.begins_with(common + "/"):
			common = common.get_base_dir() if common.contains("/") else ""
	return common + "/" if not common.is_empty() else "res://"


static func location(finding: Dictionary) -> String:
	var file := str(finding.path).trim_prefix("res://")
	return "%s:%d" % [file, finding.line] if int(finding.line) > 0 else file


## Prompt para Construir: arreglar los hallazgos indicados.
static func fix_prompt(list: Array[Dictionary]) -> String:
	var lines: PackedStringArray = ["Fix these review findings, one by one, with minimal changes:"]
	for finding: Dictionary in list:
		var line := "- %s [%s] %s" % [location(finding), finding.severity, finding.title]
		if not str(finding.body).is_empty():
			line += " — " + str(finding.body).replace("\n", " ")
		if not str(finding.suggestion).is_empty():
			line += "\n  Suggestion: " + str(finding.suggestion).replace("\n", "\n  ")
		lines.append(line)
	return "\n".join(lines)


static func question_prompt(finding: Dictionary) -> String:
	return "About the finding at %s («%s»): explain why it is a problem and what the alternatives are. Do not modify anything." % [location(finding), finding.title]


## Sección para CLAUDE.md con las convenciones que salen de la revisión.
static func claude_md_section(list: Array[Dictionary], date: String) -> String:
	var lines: PackedStringArray = ["## Conventions from the agent review (%s)" % date, ""]
	for severity: String in SEVERITY_LABELS:
		var group := list.filter(func(f: Dictionary) -> bool: return f.severity == severity)
		if group.is_empty():
			continue
		var label := str(SEVERITY_LABELS[severity])
		lines.append("### " + label.left(1).to_upper() + label.substr(1))
		for finding: Dictionary in group:
			var line := "- %s (e.g. `%s`)" % [finding.title, location(finding)]
			if not str(finding.suggestion).is_empty() and not str(finding.suggestion).contains("\n"):
				line += ": `%s`" % finding.suggestion
			lines.append(line)
		lines.append("")
	return "\n".join(lines)


## Agrega la sección al final de CLAUDE.md (lo crea si no existe). Devuelve "" o el error.
static func append_to_claude_md(section: String, path: String = CLAUDE_MD_PATH) -> String:
	var previous := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var separator := "" if previous.is_empty() else ("\n" if previous.ends_with("\n") else "\n\n")
	var error := AtomicFile.write_text(path, previous + separator + section.strip_edges() + "\n")
	return "" if error == OK else error_string(error)
