@tool
extends RefCounted
## Los planes aprobados (m11-22) quedan en el proyecto, en `.godot_agent/plans/<fecha>-<slug>.md`,
## para retomarlos en otra sesión (con @ en el composer). El slug sale del primer título del plan.

const DIR := ".godot_agent/plans"
const SLUG_MAX := 48


## Guarda `text` con la fecha de aprobación y devuelve la ruta absoluta ("" si no se pudo escribir).
## Si ya hay un plan con ese nombre se agrega -2, -3…: no se pisa uno aprobado antes.
static func save_approved(project_dir: String, text: String, date: String = "") -> String:
	if project_dir.is_empty() or text.strip_edges().is_empty():
		return ""
	if date.is_empty():
		date = Time.get_date_string_from_system()
	var dir := project_dir.path_join(DIR)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var base := "%s-%s" % [date, slug(text)]
	var path := dir.path_join(base + ".md")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s-%d.md" % [base, n])
		n += 1
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string("%s\n\n<!-- Approved: %s -->\n" % [text.strip_edges(), date])
	file.close()
	return path


## Del primer título (sin «Plan:»), en minúsculas y con guiones; «plan» si no hay nada útil.
static func slug(text: String) -> String:
	var title := ""
	for line: String in text.split("\n"):
		var clean := line.strip_edges()
		if clean.begins_with("#"):
			title = clean.lstrip("#").strip_edges()
			break
		if title.is_empty() and not clean.is_empty():
			title = clean
	if title.to_lower().begins_with("plan:"):
		title = title.substr(5)
	var out := ""
	var dash := false
	for c: String in title.to_lower():
		var code := c.unicode_at(0)
		var ok := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if ok:
			out += c
			dash = false
		elif not dash and not out.is_empty():
			out += "-"
			dash = true
	out = out.left(SLUG_MAX).trim_suffix("-")
	return out if not out.is_empty() else "plan"


## Suma al plan guardado la sección «## Verification» con lo que salió de jugar sus criterios (m11-23):
## el resumen y una línea por criterio con lo que vio el playtest. Si ya tenía una, la reemplaza.
static func append_verification(path: String, criteria: Array, summary: String, when: String = "") -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	if when.is_empty():
		when = Time.get_datetime_string_from_system(false, true)
	var text := FileAccess.get_file_as_string(path)
	var start := text.find("\n## Verification\n")
	if start >= 0:
		text = text.left(start)
	var lines: PackedStringArray = ["", "## Verification", "", "Checked by playing (%s): %s" % [when, summary], ""]
	for item: Dictionary in criteria:
		if str(item.status) == "skipped":
			lines.append("- · %s (not played)" % item.goal)
			continue
		var mark := {"pass": "✓", "fail": "✗", "retest": "✗"}.get(str(item.status), "⊘") as String
		lines.append("- %s %s" % [mark, item.goal])
		if not str(item.summary).is_empty():
			lines.append("  - %s" % str(item.summary).replace("\n", " "))
		for evidence: Variant in item.get("evidence", []):
			lines.append("  - %s" % str(evidence).replace("\n", " "))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text.strip_edges(false, true) + "\n" + "\n".join(lines) + "\n")
	file.close()
	return true
