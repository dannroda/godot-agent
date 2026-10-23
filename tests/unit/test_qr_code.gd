extends "test_case.gd"
## Código QR del link de Remote Control (m7-25). Las matrices de referencia son de qrencode 4
## (`qrencode -l M -8 -m 0 -t ASCII`), en tests/fixtures/qr/.

const QrCode := preload("res://addons/godot_agent/core/qr_code.gd")
const REMOTE_URL := "https://claude.ai/code/session_01FakeRemoteSession"
const UTF8_TEXT := "Godot Agent Harness · Remote Control: https://claude.ai/code/session_01AbCdEfGhIjKlMnOpQrStUvWxYz0123456789"


func _fixture(name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/qr/%s.txt" % name).strip_edges()


func test_matches_reference() -> void:
	var qr := QrCode.new(REMOTE_URL)
	assert_eq(qr.version, 4, "versión")
	assert_eq(qr.size, 33, "tamaño")
	assert_eq(qr.to_text(), _fixture("remote_v4"), "matriz igual a la de qrencode (misma máscara elegida)")


func test_version_block_and_utf8() -> void:
	# Versión 7: lleva el bloque de versión. qrencode elige otra máscara (calcula la penalización
	# distinto); con la misma máscara la matriz es idéntica.
	var qr := QrCode.new(UTF8_TEXT, 3)
	assert_eq(qr.version, 7, "versión")
	assert_eq(qr.to_text(), _fixture("utf8_v7"), "matriz igual a la de qrencode con la máscara 3")


func test_limits() -> void:
	assert_eq(QrCode.new("a").version, 1, "texto corto: versión 1")
	assert_eq(QrCode.new("x".repeat(213)).version, 10, "213 bytes entran en la versión 10")
	assert_eq(QrCode.new("x".repeat(214)).size, 0, "más no entra: queda vacío")
	assert_eq(QrCode.new("").size, 0, "vacío")


func test_image() -> void:
	var qr := QrCode.new(REMOTE_URL)
	var image := qr.to_image(3, 4)
	assert_eq(image.get_width(), (33 + 8) * 3, "ancho con zona de silencio")
	assert_eq(image.get_pixel(0, 0).r, 1.0, "zona de silencio blanca")
	assert_eq(image.get_pixel(4 * 3, 4 * 3).r, 0.0, "esquina del patrón de posición oscura")
