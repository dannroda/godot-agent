@tool
extends RefCounted
## Exportar una sesión para compartirla (m11-32): un session.md con los pedidos, las respuestas, las
## tool calls resumidas (plegadas, con sus diffs) y las capturas como PNG al lado. Sale del modelo de
## la pestaña, no del historial: el historial no guarda las imágenes.
## Privacidad: antes de guardar, el usuario ve el texto y elige qué sacar. find() cuenta lo que hay;
## build() lo saca según `options`:
## - paths: rutas absolutas. La del proyecto queda relativa (`./`), la carpeta personal como `~`, y
##   cualquier otra carpeta de usuario (/home/x, /Users/x, C:\Users\x) también como `~`.
## - emails: el email de la cuenta y cualquier otra dirección.
## - untrusted: el contenido de los sobres no confiables (lo que vino del juego, las escenas o internet).
## - images: las capturas.
## Los secretos registrados (el token del server MCP…) salen siempre, con `redact`.

const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const ToolCall := preload("tool_call.gd")
const TurnReport := preload("turn_report.gd")

const DIR := "res://.godot_agent/reports"
const FILE_NAME := "session.md"
const UNTRUSTED_PATTERN := "<untrusted nonce=\"([^\"]*)\">([\\s\\S]*?)</untrusted nonce=\"\\1\">"
const EMAIL_PATTERN := "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
## Rutas absolutas que quedan después de pasar el proyecto y la carpeta personal a relativas.
## Cada tramo termina en algo que no es puntuación: el punto final de una oración no es parte de la ruta.
const PATH_PATTERN := "(?<![\\w.~])(?:/(?:home|Users|tmp|var|opt|mnt|media|private|root|srv)(?:/[^\\s`'\")\\]>]*[^\\s`'\")\\]>.,;:!?])+|[A-Za-z]:\\\\(?:[^\\s`'\")\\]>\\\\]*[^\\s`'\")\\]>\\\\.,;:!?]\\\\?)+)"
const USER_HOME_PATTERN := "(?:/home/|/Users/|[A-Za-z]:\\\\Users\\\\)[^/\\\\\\s`'\")\\]>]+"
const UNTRUSTED_REMOVED := "[content from outside the project removed]"
const PATH_REMOVED := "<path>"
const EMAIL_REMOVED := "<email>"
const TOOL_TEXT_MAX := 1500



## Lo que hay para sacar en `markdown` (el texto sin filtrar de build): {paths, emails, untrusted}
## con las coincidencias distintas, para que el diálogo diga cuántas son.
static func find(markdown: String, context: Dictionary) -> Dictionary:
	var paths: Dictionary = {}
	var relative := _relative_paths(markdown, context)
	for prefix: String in _absolute_prefixes(context):
		if markdown.contains(prefix):
			paths[prefix] = true
	for found: RegExMatch in RegEx.create_from_string(USER_HOME_PATTERN).search_all(markdown):
		paths[found.get_string()] = true
	for found: RegExMatch in RegEx.create_from_string(PATH_PATTERN).search_all(relative):
		paths[found.get_string()] = true
	var emails: Dictionary = {}
	for email: String in context.get("emails", PackedStringArray()):
		if not email.is_empty() and markdown.contains(email):
			emails[email] = true
	for found: RegExMatch in RegEx.create_from_string(EMAIL_PATTERN).search_all(markdown):
		emails[found.get_string()] = true
	return {"paths": PackedStringArray(paths.keys()), "emails": PackedStringArray(emails.keys()),
		"untrusted": RegEx.create_from_string(UNTRUSTED_PATTERN).search_all(markdown).size()}


## {markdown, images: [{name, mime, data}], raw (el texto sin filtrar, para find)}. `context`: {title, project (ruta absoluta), home,
## emails, redact: Callable(text) -> text}. `options`: {paths, emails, untrusted, images} (true = sacar).
static func build(model: SessionModel, context: Dictionary, options: Dictionary) -> Dictionary:
	var lines: PackedStringArray = ["# %s" % context.get("title", "Session"), ""]
	var images: Array[Dictionary] = []
	for entry: ChatEntry in model.entries():
		_entry_lines(model, entry, lines, images, options.get("images", false))
	var markdown := "\n".join(lines).strip_edges() + "\n"
	return {"markdown": filter(markdown, context, options), "images": images, "raw": markdown}


## Saca de `text` lo que piden `options`; los secretos, siempre.
static func filter(text: String, context: Dictionary, options: Dictionary) -> String:
	var untrusted := RegEx.create_from_string(UNTRUSTED_PATTERN)
	var redact: Callable = context.get("redact", Callable())
	if redact.is_valid():
		text = redact.call(text)
	if options.get("untrusted", false):
		text = untrusted.sub(text, UNTRUSTED_REMOVED, true)
	else:
		text = untrusted.sub(text, "$2", true)  # el contenido queda; las marcas son ruido
	if options.get("emails", false):
		for email: String in context.get("emails", PackedStringArray()):
			if not email.is_empty():
				text = text.replace(email, EMAIL_REMOVED)
		text = RegEx.create_from_string(EMAIL_PATTERN).sub(text, EMAIL_REMOVED, true)
	if options.get("paths", false):
		text = RegEx.create_from_string(PATH_PATTERN).sub(_relative_paths(text, context), PATH_REMOVED, true)
	return text


## Escribe session.md y las capturas en `<root>/<stamp>-session/`; devuelve la ruta de session.md.
static func write(root: String, stamp: String, built: Dictionary) -> String:
	var dir := root.path_join(stamp + "-session")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK:
		return ""
	for image: Dictionary in built.images:
		var out := FileAccess.open(dir.path_join(image.name), FileAccess.WRITE)
		if out == null:
			return ""
		out.store_buffer(Marshalls.base64_to_raw(str(image.data)))
		out.close()
	var file := FileAccess.open(dir.path_join(FILE_NAME), FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(str(built.markdown))
	file.close()
	return dir.path_join(FILE_NAME)


static func _entry_lines(model: SessionModel, entry: ChatEntry, lines: PackedStringArray, images: Array[Dictionary], skip_images: bool) -> void:
	match entry.kind:
		ChatEntry.EntryKind.USER:
			lines.append("## You")
			lines.append("")
			# Un prompt del harness (traspaso, playtest, revisión…) es largo y lo armó el harness: va su etiqueta.
			lines.append("_%s_" % entry.harness_label if not entry.harness_label.is_empty() else entry.text.strip_edges())
			for attachment: Dictionary in entry.attachments:
				lines.append("- 📎 %s" % str(attachment.get("label", attachment.get("title", ""))))
		ChatEntry.EntryKind.AGENT:
			lines.append("## Agent")
			lines.append("")
			lines.append(entry.text.strip_edges())
		ChatEntry.EntryKind.THOUGHT:
			_details(lines, "Thinking", entry.text.strip_edges())
			return
		ChatEntry.EntryKind.PLAN:
			lines.append("**Plan**")
			lines.append("")
			for item: Variant in entry.plan:
				if item is Dictionary:
					lines.append("- [%s] %s" % ["x" if item.get("status") == "completed" else " ", str(item.get("content", ""))])
		ChatEntry.EntryKind.TOOL_GROUP:
			for id: String in entry.tool_call_ids:
				var call := model.tool_call(id)
				if call:
					_tool_lines(call, lines, images, skip_images)
			return
		ChatEntry.EntryKind.PERMISSION:
			var permission: Object = entry.permission
			if permission:
				lines.append("> Permission: %s" % str(permission.get(&"title")))
		ChatEntry.EntryKind.NOTICE:
			var notice := entry.title if not entry.title.is_empty() else entry.text
			lines.append("> %s" % notice.strip_edges().replace("\n", "\n> "))
			if not entry.title.is_empty() and not entry.text.is_empty():
				lines.append("> " + entry.text.strip_edges().replace("\n", "\n> "))
			if not entry.details.is_empty():
				lines.append("")
				_details(lines, entry.details_title if not entry.details_title.is_empty() else "Details", entry.details)
				return
		_:
			return
	lines.append("")


## Una tool call en una línea, con lo que devolvió y sus diffs plegados; las imágenes van como PNG.
static func _tool_lines(call: ToolCall, lines: PackedStringArray, images: Array[Dictionary], skip_images: bool) -> void:
	var mark := {ToolCall.STATUS_COMPLETED: "✓", ToolCall.STATUS_FAILED: "✗", ToolCall.STATUS_CANCELLED: "⊘"}.get(call.status, "…")
	var body: PackedStringArray = []
	var captures: PackedStringArray = []
	for item: Variant in call.content:
		if not item is Dictionary:
			continue
		if item.get("type") == "diff":
			body.append("`%s`\n\n```diff\n%s\n```" % [str(item.get("path", "")), _diff(str(item.get("oldText", "")), str(item.get("newText", "")))])
			continue
		var block: Variant = item.get("content")
		if block is Dictionary and block.get("type") == "text":
			var text := str(block.get("text", "")).strip_edges()
			if not text.is_empty():
				body.append("```\n%s\n```" % _trim(text))
		elif block is Dictionary and block.get("type") == "image" and TurnReport.EXTENSIONS.has(str(block.get("mimeType", ""))):
			if skip_images:
				captures.append("_(capture removed)_")
			else:
				var name := "capture-%d.%s" % [images.size() + 1, TurnReport.EXTENSIONS[str(block.mimeType)]]
				images.append({"name": name, "mime": str(block.mimeType), "data": str(block.get("data", ""))})
				captures.append("![%s](%s)" % [call.title.replace("]", ""), name])
	if body.is_empty() and call.raw_output is String and not str(call.raw_output).strip_edges().is_empty():
		body.append("```\n%s\n```" % _trim(str(call.raw_output).strip_edges()))
	var summary := "%s `%s`" % [mark, call.title.replace("`", "'")]
	if body.is_empty():
		lines.append("- " + summary)
	else:
		lines.append("<details><summary>%s</summary>" % summary.replace("`", ""))
		lines.append("")
		lines.append("\n\n".join(body))
		lines.append("")
		lines.append("</details>")
	lines.append("")
	for capture: String in captures:
		lines.append(capture)
		lines.append("")


static func _details(lines: PackedStringArray, title: String, text: String) -> void:
	if text.is_empty():
		return
	lines.append_array(["<details><summary>%s</summary>" % title, "", text, "", "</details>", ""])


static func _trim(text: String) -> String:
	return text if text.length() <= TOOL_TEXT_MAX else text.left(TOOL_TEXT_MAX) + "\n… (trimmed)"


## Un diff simple línea por línea (las líneas que se fueron y las que llegaron), suficiente para leerlo.
static func _diff(old_text: String, new_text: String) -> String:
	var out: PackedStringArray = []
	var old_lines := old_text.split("\n") if not old_text.is_empty() else PackedStringArray()
	var new_lines := new_text.split("\n") if not new_text.is_empty() else PackedStringArray()
	var start := 0
	while start < old_lines.size() and start < new_lines.size() and old_lines[start] == new_lines[start]:
		start += 1
	var end_old := old_lines.size()
	var end_new := new_lines.size()
	while end_old > start and end_new > start and old_lines[end_old - 1] == new_lines[end_new - 1]:
		end_old -= 1
		end_new -= 1
	for i in range(start, end_old):
		out.append("-" + old_lines[i])
	for i in range(start, end_new):
		out.append("+" + new_lines[i])
	return _trim("\n".join(out))


## La carpeta del proyecto y la personal, como aparecen en el texto (con / y con \ en Windows).
static func _absolute_prefixes(context: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = []
	for key: String in ["project", "home"]:
		var path := str(context.get(key, "")).trim_suffix("/").trim_suffix("\\")
		if path.length() > 1:
			result.append(path)
			if path.contains("/"):
				result.append(path.replace("/", "\\"))
	return result


## Rutas del proyecto relativas (./) y de la carpeta personal (o la de otro usuario) con ~.
static func _relative_paths(text: String, context: Dictionary) -> String:
	var project := str(context.get("project", "")).trim_suffix("/")
	if project.length() > 1:
		text = text.replace(project + "/", "./").replace(project, ".")
	var home := str(context.get("home", "")).trim_suffix("/")
	if home.length() > 1:
		text = text.replace(home, "~")
	return RegEx.create_from_string(USER_HOME_PATTERN).sub(text, "~", true)
