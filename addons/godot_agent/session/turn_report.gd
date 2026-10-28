@tool
extends RefCounted
## Reporte de un turno para mirar o compartir (m11-06): una carpeta con report.md (lo que contó el
## agente, los archivos que cambió) y las capturas del juego o del editor que tomó en ese turno.

const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")

const DIR := "res://.godot_agent/reports"
const EXTENSIONS := {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"}


## Lo que dejó el turno desde la entrada `first_entry`: `{summary, images: [{title, mime, data}]}`
## (`data` en base64, como llegó por ACP).
static func collect(model: SessionModel, first_entry: int) -> Dictionary:
	var summary: PackedStringArray = []
	var images: Array[Dictionary] = []
	var entries := model.entries()
	for i in range(maxi(first_entry, 0), entries.size()):
		var entry := entries[i]
		if entry.kind == ChatEntry.EntryKind.AGENT:
			summary.append(entry.text.strip_edges())
		for id: String in entry.tool_call_ids:
			var call := model.tool_call(id)
			if call == null:
				continue
			for item: Variant in call.content:
				var block: Variant = item.get("content") if item is Dictionary else null
				if block is Dictionary and block.get("type") == "image" and EXTENSIONS.has(str(block.get("mimeType", ""))):
					images.append({"title": call.title, "mime": str(block.mimeType), "data": str(block.get("data", ""))})
	return {"summary": "\n\n".join(summary).strip_edges(), "images": images}


## Escribe el reporte en `<root>/<stamp>/` y devuelve la ruta de report.md ("" si no se pudo).
static func write(root: String, stamp: String, title: String, collected: Dictionary, files: Array) -> String:
	var dir := root.path_join(stamp)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var lines: PackedStringArray = ["# %s" % title, ""]
	if not str(collected.summary).is_empty():
		lines.append_array(["## What the agent did", "", str(collected.summary), ""])
	if not files.is_empty():
		var added := 0
		var removed := 0
		for file: Dictionary in files:
			added += int(file.added)
			removed += int(file.removed)
		lines.append_array(["## Files changed (+%d −%d)" % [added, removed], ""])
		for file: Dictionary in files:
			lines.append("- `%s` %s (+%d −%d)" % [file.path, {"A": "new", "D": "deleted"}.get(file.status, "changed"), file.added, file.removed])
		lines.append("")
	if not collected.images.is_empty():
		lines.append_array(["## Captures", ""])
		for i in collected.images.size():
			var image: Dictionary = collected.images[i]
			var name := "capture-%d.%s" % [i + 1, EXTENSIONS[image.mime]]
			var out := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
			if out == null:
				return ""
			out.store_buffer(Marshalls.base64_to_raw(str(image.data)))
			out.close()
			lines.append_array(["![%s](%s)" % [str(image.title).replace("]", ""), name], ""])
	var report := FileAccess.open(dir.path_join("report.md"), FileAccess.WRITE)
	if report == null:
		return ""
	report.store_string("\n".join(lines))
	report.close()
	return dir.path_join("report.md")
