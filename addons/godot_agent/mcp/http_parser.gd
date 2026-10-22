@tool
extends RefCounted
## Parser HTTP/1.1 incremental y mínimo para el server MCP (spec §5): request line, headers y
## body por Content-Length. Sin chunked: 411. Acepta requests partidos en varios paquetes y
## varios requests seguidos en el mismo paquete (keep-alive).

const MAX_HEADER_BYTES := 16384
const MAX_BODY_BYTES := 8 * 1024 * 1024
const CRLFCRLF := "\r\n\r\n"


## Request completo.
class ParsedRequest:
	extends RefCounted
	var method: String = ""
	var path: String = ""
	var version: String = ""
	## Nombres en minúscula -> valor (si se repite, el último).
	var headers: Dictionary = {}
	var body: PackedByteArray = PackedByteArray()

	func header(name: String, default_value: String = "") -> String:
		return headers.get(name.to_lower(), default_value)

	func body_text() -> String:
		return body.get_string_from_utf8()

	## HTTP/1.1 mantiene la conexión salvo `Connection: close`; HTTP/1.0 la cierra salvo keep-alive.
	func keep_alive() -> bool:
		var connection := header("connection").to_lower()
		if version == "HTTP/1.0":
			return connection.contains("keep-alive")
		return not connection.contains("close")


var _buffer: PackedByteArray = PackedByteArray()
## Request con headers leídos, esperando el body.
var _pending: ParsedRequest
var _pending_length: int = 0
## Código HTTP del error que cortó el stream (0 = sin error).
var error_status: int = 0
var error_message: String = ""


## Agrega bytes y devuelve los requests que quedaron completos. Si hay un error de formato,
## deja `error_status` (400, 411, 413, 431, 505) y no devuelve nada más: la conexión se cierra.
func feed(data: PackedByteArray) -> Array[ParsedRequest]:
	var result: Array[ParsedRequest] = []
	if error_status != 0:
		return result
	_buffer.append_array(data)
	while error_status == 0:
		if _pending == null:
			if not _parse_head():
				break
		if _buffer.size() < _pending_length:
			break
		_pending.body = _buffer.slice(0, _pending_length)
		_buffer = _buffer.slice(_pending_length)
		result.append(_pending)
		_pending = null
		_pending_length = 0
	return result


func has_partial_request() -> bool:
	return _pending != null or not _buffer.is_empty()


func _parse_head() -> bool:
	var end := _find_header_end()
	if end < 0:
		if _buffer.size() > MAX_HEADER_BYTES:
			return _fail(431, "headers too long")
		return false
	if end > MAX_HEADER_BYTES:
		return _fail(431, "headers too long")
	var head := _buffer.slice(0, end).get_string_from_ascii()
	_buffer = _buffer.slice(end + CRLFCRLF.length())
	var lines := head.split("\r\n")
	# Se toleran líneas vacías antes del request (RFC 9112 §2.2).
	while not lines.is_empty() and lines[0].is_empty():
		lines.remove_at(0)
	if lines.is_empty():
		return _fail(400, "empty request")
	var parts := lines[0].split(" ", false)
	if parts.size() != 3:
		return _fail(400, "invalid request line")
	if not parts[2].begins_with("HTTP/1."):
		return _fail(505, "unsupported HTTP version")
	var request := ParsedRequest.new()
	request.method = parts[0]
	request.path = parts[1]
	request.version = parts[2]
	for i in range(1, lines.size()):
		var line: String = lines[i]
		var colon := line.find(":")
		if colon <= 0:
			return _fail(400, "invalid header")
		request.headers[line.left(colon).strip_edges().to_lower()] = line.substr(colon + 1).strip_edges()
	if request.header("transfer-encoding") != "":
		return _fail(411, "Transfer-Encoding not supported: send Content-Length")
	var length_text := request.header("content-length", "0")
	if not length_text.is_valid_int() or int(length_text) < 0:
		return _fail(400, "invalid Content-Length")
	var length := int(length_text)
	if length > MAX_BODY_BYTES:
		return _fail(413, "body too large")
	_pending = request
	_pending_length = length
	return true


func _find_header_end() -> int:
	var size := _buffer.size()
	for i in range(0, size - 3):
		if _buffer[i] == 13 and _buffer[i + 1] == 10 and _buffer[i + 2] == 13 and _buffer[i + 3] == 10:
			return i
	return -1


func _fail(status: int, message: String) -> bool:
	error_status = status
	error_message = message
	_buffer.clear()
	_pending = null
	return false


## Respuesta HTTP serializada.
static func response(status: int, body: PackedByteArray = PackedByteArray(), headers: Dictionary = {}) -> PackedByteArray:
	var lines: PackedStringArray = ["HTTP/1.1 %d %s" % [status, reason(status)]]
	for name: String in headers:
		lines.append("%s: %s" % [name, headers[name]])
	lines.append("Content-Length: %d" % body.size())
	var bytes := ("\r\n".join(lines) + CRLFCRLF).to_utf8_buffer()
	bytes.append_array(body)
	return bytes


static func reason(status: int) -> String:
	match status:
		200: return "OK"
		202: return "Accepted"
		204: return "No Content"
		400: return "Bad Request"
		401: return "Unauthorized"
		403: return "Forbidden"
		404: return "Not Found"
		405: return "Method Not Allowed"
		411: return "Length Required"
		413: return "Content Too Large"
		431: return "Request Header Fields Too Large"
		500: return "Internal Server Error"
		505: return "HTTP Version Not Supported"
	return "Status"
