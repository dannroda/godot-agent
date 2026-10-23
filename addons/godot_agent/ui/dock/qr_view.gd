@tool
extends Control
## Dibuja un código QR con _draw (m7-25): módulos negros sobre blanco con zona de silencio, del
## tamaño entero de píxel por módulo que entra en el ancho disponible (entre MIN_MODULE_PX y
## MAX_MODULE_PX), centrado.

const QrCode := preload("../../core/qr_code.gd")

const QUIET_ZONE := 4
const MIN_MODULE_PX := 2
const MAX_MODULE_PX := 5

var qr: QrCode
var _text: String = ""


func set_text(text: String) -> void:
	if text == _text:
		return
	_text = text
	qr = QrCode.new(text) if not text.is_empty() else null
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	# Ancho: el del módulo más chico, para no ensanchar el dock. Alto: el del módulo que entra hoy.
	var modules := _modules_with_border()
	return Vector2.ZERO if modules == 0 else Vector2(modules * MIN_MODULE_PX, modules * _module_px())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		update_minimum_size()
		queue_redraw()


func _draw() -> void:
	var modules := _modules_with_border()
	if modules == 0:
		return
	var px := _module_px()
	var origin := Vector2(floorf((size.x - modules * px) / 2.0), 0)
	draw_rect(Rect2(origin, Vector2(modules, modules) * px), Color.WHITE)
	for y in qr.size:
		for x in qr.size:
			if qr.is_dark(x, y):
				draw_rect(Rect2(origin + Vector2(x + QUIET_ZONE, y + QUIET_ZONE) * px, Vector2(px, px)), Color.BLACK)


func _modules_with_border() -> int:
	return 0 if qr == null or qr.size == 0 else qr.size + QUIET_ZONE * 2


## Píxeles por módulo: el mayor entero que entra en el ancho, dentro de los topes.
func _module_px() -> int:
	var modules := _modules_with_border()
	if modules == 0:
		return 0
	return clampi(int(size.x) / modules, MIN_MODULE_PX, MAX_MODULE_PX)
