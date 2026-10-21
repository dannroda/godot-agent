extends "test_case.gd"
## Parser HTTP/1.1 del server MCP (spec §5).

const HttpParser := preload("res://addons/godot_agent/mcp/http_parser.gd")


func _post(body: String, extra: String = "") -> String:
	return "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n%sContent-Length: %d\r\n\r\n%s" % [extra, body.to_utf8_buffer().size(), body]


func test_single_request() -> void:
	var parser := HttpParser.new()
	var requests := parser.feed(_post("{\"a\":1}", "Authorization: Bearer x\r\n").to_utf8_buffer())
	assert_eq(requests.size(), 1, "un request")
	var request := requests[0]
	assert_eq(request.method, "POST", "método")
	assert_eq(request.path, "/mcp", "ruta")
	assert_eq(request.header("AUTHORIZATION"), "Bearer x", "headers sin mayúsculas")
	assert_eq(request.body_text(), "{\"a\":1}", "body")
	assert_true(request.keep_alive(), "HTTP/1.1 mantiene la conexión")
	assert_false(parser.has_partial_request(), "sin resto")


func test_split_and_concatenated() -> void:
	var parser := HttpParser.new()
	var raw := (_post("{\"ñ\":\"á\"}") + _post("[]", "Connection: close\r\n")).to_utf8_buffer()
	var received: Array = []
	# Byte a byte: los requests se arman igual.
	for i in raw.size():
		received.append_array(parser.feed(raw.slice(i, i + 1)))
	assert_eq(received.size(), 2, "dos requests byte a byte")
	assert_eq(received[0].body_text(), "{\"ñ\":\"á\"}", "body utf-8 completo")
	assert_false(received[1].keep_alive(), "Connection: close")
	var together := HttpParser.new().feed(raw)
	assert_eq(together.size(), 2, "dos requests en un paquete")


func test_waits_for_body() -> void:
	var parser := HttpParser.new()
	var raw := _post("0123456789").to_utf8_buffer()
	assert_eq(parser.feed(raw.slice(0, raw.size() - 3)).size(), 0, "body incompleto")
	assert_true(parser.has_partial_request(), "queda pendiente")
	assert_eq(parser.feed(raw.slice(raw.size() - 3)).size(), 1, "completa con el resto")


func test_errors() -> void:
	var chunked := HttpParser.new()
	chunked.feed("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n".to_utf8_buffer())
	assert_eq(chunked.error_status, 411, "chunked → 411")
	var bad_length := HttpParser.new()
	bad_length.feed("POST /mcp HTTP/1.1\r\nContent-Length: diez\r\n\r\n".to_utf8_buffer())
	assert_eq(bad_length.error_status, 400, "Content-Length inválido → 400")
	var negative := HttpParser.new()
	negative.feed("POST /mcp HTTP/1.1\r\nContent-Length: -1\r\n\r\n".to_utf8_buffer())
	assert_eq(negative.error_status, 400, "Content-Length negativo → 400")
	var bad_line := HttpParser.new()
	bad_line.feed("GARBAGE\r\n\r\n".to_utf8_buffer())
	assert_eq(bad_line.error_status, 400, "request line inválida → 400")
	var version := HttpParser.new()
	version.feed("GET / HTTP/2.0\r\n\r\n".to_utf8_buffer())
	assert_eq(version.error_status, 505, "HTTP/2 → 505")
	var huge := HttpParser.new()
	huge.feed(("POST /mcp HTTP/1.1\r\nX: " + "a".repeat(HttpParser.MAX_HEADER_BYTES)).to_utf8_buffer())
	assert_eq(huge.error_status, 431, "headers enormes → 431")
	var too_big := HttpParser.new()
	too_big.feed(("POST /mcp HTTP/1.1\r\nContent-Length: %d\r\n\r\n" % (HttpParser.MAX_BODY_BYTES + 1)).to_utf8_buffer())
	assert_eq(too_big.error_status, 413, "body enorme → 413")
	assert_eq(too_big.feed("más".to_utf8_buffer()).size(), 0, "después de un error no se parsea más")


func test_response() -> void:
	var bytes := HttpParser.response(200, "{}".to_utf8_buffer(), {"Content-Type": "application/json"})
	var text := bytes.get_string_from_utf8()
	assert_true(text.begins_with("HTTP/1.1 200 OK\r\n"), "status line")
	assert_true(text.contains("Content-Type: application/json\r\n"), "header")
	assert_true(text.ends_with("Content-Length: 2\r\n\r\n{}"), "content-length y body")
