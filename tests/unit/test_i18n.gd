extends "test_case.gd"
## Idioma de la interfaz (D46): el texto fuente en inglés, la traducción en i18n/<idioma>.po y que
## cada texto de la interfaz tenga su traducción al español.

const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const ADDON_DIR := "res://addons/godot_agent"
const MARKER := "# i18n"


func test_locale() -> void:
	I18n.set_locale("es_AR")
	assert_eq(I18n.locale(), "es", "es_AR usa el español")
	assert_eq(I18n.t("Language"), "Idioma", "traduce")
	assert_eq(I18n.t("Not in the catalog"), "Not in the catalog", "sin traducción queda en inglés")
	I18n.set_locale("fr")
	assert_eq(I18n.locale(), "en", "sin .po, inglés")
	assert_eq(I18n.t("Language"), "Language", "en inglés no traduce")
	I18n.set_locale("en")


## Cada msgid del código (I18n.t("…") y el último literal de las líneas con `# i18n`) está en es.po con el mismo formato.
func test_spanish_catalog_is_complete() -> void:
	var catalog := _read_po(I18n.DIR + "es.po")
	var used := {}
	for path: String in _scripts(ADDON_DIR):
		for msgid: String in msgids_in(FileAccess.get_file_as_string(path)):
			used[msgid] = path
	var missing: PackedStringArray = []
	var bad_format: PackedStringArray = []
	for msgid: String in used:
		if not catalog.has(msgid) or str(catalog[msgid]).is_empty():
			missing.append("%s (%s)" % [msgid.c_escape(), str(used[msgid]).get_file()])
		elif _placeholders(msgid) != _placeholders(catalog[msgid]):
			bad_format.append(msgid.c_escape())
	var unused: PackedStringArray = []
	for msgid: String in catalog:
		if not used.has(msgid):
			unused.append(msgid.c_escape())
	assert_eq(missing, PackedStringArray(), "falta la traducción")
	assert_eq(bad_format, PackedStringArray(), "los %s/%d de la traducción no coinciden")
	assert_eq(unused, PackedStringArray(), "entradas de es.po que el código ya no usa")


func test_msgids_in() -> void:
	var source := 'a.text = I18n.t("Pause")\nb = I18n.t("Say \\"hi\\"\\n") % x\nconst L := {"x": "Ask"}  # i18n\n# I18n.t("comentario")\n'
	assert_eq(msgids_in(source), PackedStringArray(["Pause", "Say \"hi\"\n", "Ask"]), "llamadas y el último literal de las líneas marcadas")


static func msgids_in(source: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var call := RegEx.create_from_string("I18n\\.t\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*\\)")
	var literal := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for line: String in source.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.ends_with(MARKER):  # constantes que se traducen al mostrarlas: el último literal
			var found := literal.search_all(code.trim_suffix(MARKER))
			if not found.is_empty():
				result.append(found.back().get_string(1).c_unescape())
			continue
		for found: RegExMatch in call.search_all(line):
			result.append(found.get_string(1).c_unescape())
	return result


func _scripts(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		result.append_array(_scripts(dir.path_join(sub)))
	return result


## msgid -> msgstr. Alcanza con el formato que escribe el repo: una línea por campo.
func _read_po(path: String) -> Dictionary:
	var result := {}
	var msgid := ""
	var field := ""
	var values := {"msgid": "", "msgstr": ""}
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("msgid "):
			if not str(values.msgid).is_empty():
				result[values.msgid] = values.msgstr
			values = {"msgid": "", "msgstr": ""}
			field = "msgid"
			line = line.trim_prefix("msgid ")
		elif line.begins_with("msgstr "):
			field = "msgstr"
			line = line.trim_prefix("msgstr ")
		elif not line.begins_with("\""):
			continue
		values[field] = str(values[field]) + line.trim_prefix("\"").trim_suffix("\"").c_unescape()
	if not str(values.msgid).is_empty():
		result[values.msgid] = values.msgstr
	return result


static func _placeholders(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for found: RegExMatch in RegEx.create_from_string("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfxXoc%]").search_all(text):
		result.append(found.get_string())
	return result
