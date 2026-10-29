@tool
extends RefCounted
## Preautorizaciones de una sesión (sacado de SessionController, m13-02): un permiso de edición
## concedido cubre la escritura por fs/* que le sigue al mismo archivo, y uno de shell cubre el
## terminal/create que le sigue con el mismo comando, durante TTL_MS y una sola vez.

const PermissionRequest := preload("permission_request.gd")
const PermissionPolicy := preload("permission_policy.gd")

const TTL_MS := 120000

var _writes: Dictionary = {}  # ruta absoluta -> vencimiento (msec)
var _commands: Dictionary = {}  # clave del comando -> vencimiento (msec)


func clear() -> void:
	_writes.clear()
	_commands.clear()


## true (y la gasta) si hay una preautorización vigente para escribir `path`.
func consume_write(path: String) -> bool:
	return _consume(_writes, path)


## true (y la gasta) si hay una preautorización vigente para correr `command_line`.
func consume_command(command_line: String) -> bool:
	return _consume(_commands, command_key(command_line))


static func _consume(table: Dictionary, key: String) -> bool:
	var expiry: int = table.get(key, 0)
	if expiry <= Time.get_ticks_msec():
		return false
	table.erase(key)
	return true


## Un permiso de edición concedido cubre la escritura por fs/* que le sigue al mismo archivo; uno de
## shell cubre el terminal/create que le sigue con el mismo comando.
## Las palabras del comando sin las comillas: `npm run "a b"` (lo que pidió el agente) y
## `npm run 'a b'` (lo que arma terminal/create) son la misma clave. Un carácter de control del
## shell citado o escapado queda marcado: `echo 'a;rm x'` (aprobado) no cubre `echo a;rm x`.
static func command_key(command: String) -> String:
	var words: PackedStringArray = []
	var word := ""
	var in_word := false
	var quote := ""
	var i := 0
	while i < command.length():
		var c := command[i]
		if quote == "'":
			if c == "'":
				quote = ""
			else:
				word += _literal(c)
		elif quote == "\"":
			if c == "\"":
				quote = ""
			elif c == "\\" and i + 1 < command.length():
				i += 1
				word += _literal(command[i])
			else:
				word += c if c in "$`" else _literal(c)  # entre comillas dobles $ y ` siguen activos
		elif c == "'" or c == "\"":
			quote = c
			in_word = true
		elif c == "\\" and i + 1 < command.length():
			i += 1
			word += _literal(command[i])
			in_word = true
		elif c == " " or c == "\t":
			if in_word:
				words.append(word)
			word = ""
			in_word = false
		else:
			word += c
			in_word = true
		i += 1
	if in_word:
		words.append(word)
	return "\u0001".join(words)


## Un carácter que el shell no interpreta por estar citado: los de control llevan una marca.
static func _literal(c: String) -> String:
	return "\u0002" + c if c in ";|&<>$`()\n*?" else c


## Lo que concede un permiso aprobado (o permitido por el modo) para el paso que le sigue.
func grant(request: PermissionRequest, call: Variant) -> void:
	if request.group == PermissionPolicy.GROUP_SHELL:
		if not request.description.is_empty():
			_commands[command_key(request.description)] = Time.get_ticks_msec() + TTL_MS
		return
	if request.group != PermissionPolicy.GROUP_EDIT_FILES:
		return
	for path: String in write_paths(request, call):
		_writes[path] = Time.get_ticks_msec() + TTL_MS


## Archivos que escribe un pedido de edición: el del diff, los del input y las ubicaciones.
static func write_paths(request: PermissionRequest, call: Variant) -> PackedStringArray:
	var paths: PackedStringArray = []
	if not request.diff.is_empty():
		paths.append(str(request.diff.get("path", "")))
	if call and call.raw_input is Dictionary:
		for key: String in ["file_path", "path", "notebook_path"]:
			if call.raw_input.get(key) is String:
				paths.append(call.raw_input[key])
	if call:
		for location: Variant in call.locations:
			if location is Dictionary and location.get("path") is String:
				paths.append(location.path)
	var result: PackedStringArray = []
	for path: String in paths:
		if not path.is_empty() and not path.simplify_path() in result:
			result.append(path.simplify_path())
	return result
