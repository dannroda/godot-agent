@tool
extends RefCounted
## Errores y warnings del editor con número de secuencia, para `get_errors(since)` (spec §6).
## Fuentes:
## - un Logger propio (OS.add_logger, editor_logger.gd) con los errores del editor;
## - el árbol de errores del Debugger (errores del juego corriendo).

const EditorLogger := preload("../core/editor_logger.gd")

const MAX_ENTRIES := 500
const LOGGER_TYPES: Dictionary = {0: "error", 1: "warning", 2: "script", 3: "shader"}
const TIME_PATTERN := "^\\d+:\\d+:\\d+"

## `{seq, kind, message, file, line, source}`
var _entries: Array[Dictionary] = []
var _next_seq: int = 1
var _logger: EditorLogger
var _debugger_seen: Dictionary = {}
var _time_regex := RegEx.create_from_string(TIME_PATTERN)


func start() -> void:
	if _logger:
		return
	_logger = EditorLogger.new()
	OS.add_logger(_logger)


func stop() -> void:
	if _logger:
		OS.remove_logger(_logger)
		_logger = null


## Última marca (para `since`).
func mark() -> int:
	return _next_seq - 1


## Junta lo nuevo de todas las fuentes y devuelve las entradas con seq > since.
func entries_since(since: int) -> Array[Dictionary]:
	collect()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if int(entry.seq) > since:
			result.append(entry)
	return result


func collect() -> void:
	if _logger:
		for item: Array in _logger.drain():
			var message := str(item[4]) if not str(item[4]).is_empty() else str(item[3])
			add(LOGGER_TYPES.get(int(item[5]), "error"), message, str(item[1]), int(item[2]), "editor")
	_collect_debugger()


func add(kind: String, message: String, file: String = "", line: int = 0, source: String = "editor") -> void:
	_entries.append({"seq": _next_seq, "kind": kind, "message": message, "file": file, "line": line, "source": source})
	_next_seq += 1
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)


static func format_entry(entry: Dictionary) -> String:
	var location := ""
	if not str(entry.file).is_empty():
		location = " %s:%d" % [entry.file, entry.line] if int(entry.line) > 0 else " %s" % entry.file
	return "#%d [%s/%s]%s — %s" % [entry.seq, entry.source, entry.kind, location, entry.message]


# --- panel Output -------------------------------------------------------------------------------

## Texto actual del panel Output (incluye lo que imprime el juego corriendo).
func output_text() -> String:
	var label := _output_label()
	return label.get_parsed_text() if label else ""


func _output_label() -> RichTextLabel:
	var base := EditorInterface.get_base_control()
	for log_node: Node in base.find_children("*", "EditorLog", true, false):
		for label: Node in log_node.find_children("*", "RichTextLabel", true, false):
			return label
	return null


## "at: func (res://a.gd:12)" → ["res://a.gd", 12]
static func _parse_location(text: String) -> Array:
	var open := text.rfind("(")
	var close := text.rfind(")")
	if open < 0 or close <= open:
		return ["", 0]
	var inside := text.substr(open + 1, close - open - 1)
	var colon := inside.rfind(":")
	if colon <= 0 or not inside.substr(colon + 1).is_valid_int():
		return [inside, 0]
	return [inside.left(colon), int(inside.substr(colon + 1))]


# --- Debugger ------------------------------------------------------------------------------------

func _collect_debugger() -> void:
	var base := EditorInterface.get_base_control()
	for debugger: Node in base.find_children("*", "ScriptEditorDebugger", true, false):
		for tree_node: Node in debugger.find_children("*", "Tree", true, false):
			var tree := tree_node as Tree
			if tree.columns != 2 or not tree.hide_root or tree.get_root() == null:
				continue
			for item: TreeItem in tree.get_root().get_children():
				if _time_regex.search(item.get_text(0)) == null:
					break  # no es el árbol de errores
				var key := "%d|%s|%s" % [debugger.get_instance_id(), item.get_text(0), item.get_text(1)]
				if _debugger_seen.has(key):
					continue
				_debugger_seen[key] = true
				var file := ""
				var line := 0
				var meta: Variant = item.get_metadata(0)
				if meta is Array and meta.size() >= 2:
					file = str(meta[0])
					line = int(meta[1])
				var details: PackedStringArray = []
				for child: TreeItem in item.get_children():
					if child.get_metadata(0) is Array:
						break  # stack trace
					details.append(child.get_text(1))
				var message := item.get_text(1)
				if not details.is_empty():
					message += " (%s)" % "; ".join(details)
				var kind := "warning" if item.get_icon(0) == _warning_icon() else "error"
				add(kind, message, file, line, "game")


static func _warning_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Warning", &"EditorIcons")
