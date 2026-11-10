@tool
extends RefCounted
## Registro del harness: entradas con hora, canal y mensaje, más el JSON crudo opcional.
## Acotado (ring buffer) para que una sesión larga no crezca sin límite.

signal entry_added(entry: Dictionary)
signal cleared

const CH_ACP := &"acp"
const CH_MCP := &"mcp"
const CH_FS := &"fs"
const CH_PERM := &"perm"
const CH_PROC := &"proc"
const CH_QUOTA := &"quota"
const CH_CMP := &"cmp"
const CH_UPDATE := &"update"
const CH_STATE := &"state"
const CHANNELS: Array[StringName] = [CH_ACP, CH_MCP, CH_FS, CH_PERM, CH_PROC, CH_QUOTA, CH_CMP, CH_UPDATE, CH_STATE]

const DEFAULT_CAPACITY := 2000
## Tope de caracteres del JSON crudo guardado por entrada.
const RAW_LIMIT := 20000
const REDACTED := "«secret»"

var capacity: int = DEFAULT_CAPACITY
var _entries: Array[Dictionary] = []
var _next_seq: int = 1
var _secrets: PackedStringArray = []


## Agrega una entrada. `raw` es el mensaje JSON-RPC completo (se muestra en modo raw).
## Textos que nunca se muestran en el log (p. ej. el token del server MCP).
func add_secret(secret: String) -> void:
	if secret.length() >= 8 and not secret in _secrets:
		_secrets.append(secret)


func remove_secret(secret: String) -> void:
	var index := _secrets.find(secret)
	if index >= 0:
		_secrets.remove_at(index)


## `text` sin los secretos registrados (el token del server MCP…). add() lo aplica a cada entrada;
## lo que se muestra sin pasar por el log (la tarjeta de caída, m13-22) lo llama antes.
func redact(text: String) -> String:
	for secret: String in _secrets:
		text = text.replace(secret, REDACTED)
	return text


## `value` con los secretos redactados en todas sus cadenas, anidadas en diccionarios y arrays
## (los mensajes JSON-RPC del agente al entrar, un registro del historial al reproducirlo). Devuelve
## una copia; sin secretos registrados, el mismo valor.
func redact_data(value: Variant) -> Variant:
	if _secrets.is_empty():
		return value
	match typeof(value):
		TYPE_STRING:
			return redact(value)
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value:
				result[key] = redact_data(value[key])
			return result
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(redact_data(item))
			return items
		TYPE_PACKED_STRING_ARRAY:
			var strings: PackedStringArray = []
			for item: String in value:
				strings.append(redact(item))
			return strings
	return value


## Como redact_data, pero solo dentro de las claves `fields` (a cualquier profundidad): lo demás
## queda tal cual. Para lo que mezcla texto que se muestra con valores que se usan (un formulario de
## elicitation, m13-28: los títulos se redactan, los defaults y las opciones vuelven al agente reales).
## Los hijos de una clave de `named` son entradas con nombre (las `properties` de un JSON Schema): sus
## claves son nombres, no campos, así que una propiedad llamada «title» no se redacta entera.
func redact_fields(value: Variant, fields: PackedStringArray, named: PackedStringArray = ["properties"], _names_level := false) -> Variant:
	if _secrets.is_empty():
		return value
	match typeof(value):
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key: Variant in value:
				if _names_level:
					result[key] = redact_fields(value[key], fields, named)
				elif str(key) in fields:
					result[key] = redact_data(value[key])
				else:
					result[key] = redact_fields(value[key], fields, named, str(key) in named)
			return result
		TYPE_ARRAY:
			var items: Array = []
			for item: Variant in value:
				items.append(redact_fields(item, fields, named))
			return items
	return value


func add(channel: StringName, message: String, raw: String = "") -> Dictionary:
	message = redact(message)
	raw = redact(raw)
	var entry := {
		"seq": _next_seq,
		"time": Time.get_time_string_from_system(),
		"channel": channel,
		"message": message,
		"raw": raw.left(RAW_LIMIT),
	}
	_next_seq += 1
	_entries.append(entry)
	if _entries.size() > capacity:
		_entries = _entries.slice(_entries.size() - capacity)
	entry_added.emit(entry)
	return entry


## El `seq` de la última entrada (0 = ninguna): un aviso de error lo guarda para saltar a su línea.
func last_seq() -> int:
	return _next_seq - 1


func entries() -> Array[Dictionary]:
	return _entries


func clear() -> void:
	_entries.clear()
	cleared.emit()


## Texto plano para copiar: hora · canal · mensaje (y el raw si se pide).
static func format_entry(entry: Dictionary, include_raw: bool = false) -> String:
	var line := "%s  %-4s  %s" % [entry.time, entry.channel, entry.message]
	if include_raw and not str(entry.raw).is_empty():
		line += "\n" + str(entry.raw)
	return line
