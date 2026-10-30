@tool
extends RefCounted
## Lo que los playtests aprenden de este juego (m15-15), en res://.godot_agent/playtests/ (nunca llega
## a un export): hechos verificados, scripts que sirvieron, hallazgos marcados «no es un bug» y qué
## archivos había la última vez, para avisar qué cambió y que una nota vieja hay que volver a comprobarla.
## Idea de memory.py y codex.py de Autopilot (ramenvr/autopilot, Apache 2.0).

const DIR := "res://.godot_agent/playtests"
const NOTES_FILE := "notes.md"
const NOT_A_BUG_FILE := "not_a_bug.json"
const SEEN_FILE := "seen.json"
const SCRIPTS_DIR := "scripts"
const SCRIPTS_KEPT := 20
const NOTES_MAX_CHARS := 6000
const CHANGED_SHOWN := 30
const EXTENSIONS: PackedStringArray = ["gd", "cs", "tscn", "tres", "gdshader"]
const SKIPPED_DIRS: PackedStringArray = ["addons", "tests"]
const FILES_MAX := 5000

var base: String


## `dir`: otra carpeta, para las pruebas.
func _init(dir: String = DIR) -> void:
	base = dir


# --- notas ------------------------------------------------------------------------------------------

func notes() -> PackedStringArray:
	var path := base.path_join(NOTES_FILE)
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var kept: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		if line.begins_with("- "):
			kept.append(line.trim_prefix("- "))
	return kept


## Suma hechos y saca los que el agente comprobó que ya no valen. Una línea por hecho.
func update_notes(added: PackedStringArray, stale: PackedStringArray) -> void:
	if added.is_empty() and stale.is_empty():
		return
	var kept := notes()
	for note: String in stale:
		var at := kept.find(note)
		if at >= 0:
			kept.remove_at(at)
	for note: String in added:
		var line := note.replace("\n", " ").strip_edges()
		if not line.is_empty() and not line in kept:
			kept.append(line)
	var text := "# What playtests verified about this game\n\n"
	for note: String in kept:
		text += "- %s\n" % note
	_write(NOTES_FILE, text)


# --- no es un bug -----------------------------------------------------------------------------------

func not_a_bug() -> PackedStringArray:
	var text := _read(NOT_A_BUG_FILE)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	return PackedStringArray(parsed) if parsed is Array else PackedStringArray()


func mark_not_a_bug(signature: String) -> void:
	var list := not_a_bug()
	if not signature.is_empty() and not signature in list:
		list.append(signature)
		_write(NOT_A_BUG_FILE, JSON.stringify(list, "\t"))


# --- scripts que sirvieron ----------------------------------------------------------------------------

func save_script(code: String) -> void:
	var dir := base.path_join(SCRIPTS_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var name := "%s.gd.txt" % code.md5_text().left(12)  # .txt: Godot no lo toma por un script del proyecto
	var file := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	if file:
		file.store_string(code)
		file.close()
	var files := Array(DirAccess.get_files_at(dir))
	files.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(dir.path_join(a)) > FileAccess.get_modified_time(dir.path_join(b)))
	for old: String in files.slice(SCRIPTS_KEPT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(old)))


# --- qué cambió -------------------------------------------------------------------------------------

## ruta → md5 de los archivos del juego.
static func fingerprint(root: String = "res://") -> Dictionary:
	var result := {}
	var pending: PackedStringArray = [root]
	while not pending.is_empty() and result.size() < FILES_MAX:
		var dir: String = pending[pending.size() - 1]
		pending.remove_at(pending.size() - 1)
		if FileAccess.file_exists(dir.path_join(".gdignore")):
			continue
		for name: String in DirAccess.get_directories_at(dir):
			if not name.begins_with(".") and not name in SKIPPED_DIRS:
				pending.append(dir.path_join(name))
		for name: String in DirAccess.get_files_at(dir):
			if name.get_extension() in EXTENSIONS:
				result[dir.path_join(name)] = FileAccess.get_md5(dir.path_join(name))
	return result


static func changes(before: Dictionary, now: Dictionary) -> PackedStringArray:
	var changed: PackedStringArray = []
	for path: String in now:
		if before.has(path) and before[path] != now[path]:
			changed.append(path)
		elif not before.has(path):
			changed.append(path + " (new)")
	for path: String in before:
		if not now.has(path):
			changed.append(path + " (deleted)")
	changed.sort()
	return changed


func record_seen(root: String = "res://") -> void:
	_write(SEEN_FILE, JSON.stringify(fingerprint(root)))


## Lo que el agente lee al empezar un playtest. "" si todavía no hay nada.
func brief(root: String = "res://") -> String:
	var lines: PackedStringArray = []
	var known := notes()
	if not known.is_empty():
		var text := "\n".join(Array(known).map(func(note: String) -> String: return "- " + note))
		lines.append("Earlier playtests verified this about the game:\n%s" % text.right(NOTES_MAX_CHARS))
	var seen_text := _read(SEEN_FILE)
	var seen: Variant = JSON.parse_string(seen_text) if not seen_text.is_empty() else null
	if seen is Dictionary:
		var changed := changes(seen, fingerprint(root))
		if not changed.is_empty():
			var shown := changed.slice(0, CHANGED_SHOWN)
			lines.append("Changed since the last playtest (a note about this code may be out of date: check it before you rely on it):\n%s%s" % ["\n".join(shown), "\n… +%d" % (changed.size() - CHANGED_SHOWN) if changed.size() > CHANGED_SHOWN else ""])
	var dismissed := not_a_bug()
	if not dismissed.is_empty():
		lines.append("The user marked these as not a bug, don't report them: %s" % ", ".join(dismissed))
	var dir := base.path_join(SCRIPTS_DIR)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)) and not DirAccess.get_files_at(dir).is_empty():
		lines.append("game_script code that worked before is in %s." % dir)
	return "\n".join(lines)


func _read(file_name: String) -> String:
	var path := base.path_join(file_name)
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _write(file_name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var file := FileAccess.open(base.path_join(file_name), FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
