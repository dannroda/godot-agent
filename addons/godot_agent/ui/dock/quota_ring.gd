@tool
extends Control
## Cuota del plan en la fila del composer (spec §9.1, §10.1): dos anillos con _draw, la ventana
## actual afuera y la semanal adentro, del color del umbral. El detalle va en el tooltip. Sin datos
## del agente queda gris y el tooltip dice por qué (Claude Code la informa con el primer mensaje de
## cada sesión, D22).

const QuotaMonitor := preload("../../core/quota_monitor.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")

const SIZE_PX := 16
const RING_WIDTH_PX := 2.5
const TRACK_COLOR := Color(1, 1, 1, 0.14)

var _quota: QuotaMonitor
var _accent: Color
## Contexto usado de la sesión (m12-18): va primero en el tooltip.
var _context_used: int = 0
var _context_total: int = 0


func setup(quota: QuotaMonitor, accent: Color) -> void:
	_quota = quota
	_accent = accent


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * AgentTheme.px(SIZE_PX)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _quota:
		_quota.changed.connect(refresh)
	refresh()


func set_context(used: int, total: int) -> void:
	_context_used = used
	_context_total = total
	refresh()


static func context_line(used: int, total: int) -> String:
	if total <= 0:
		return ""
	return I18n.t("Context: %s of %s (%d %%)") % [_short(used), _short(total), roundi(100.0 * used / total)]


static func _short(value: int) -> String:
	return "%dk" % roundi(value / 1000.0) if value >= 1000 else str(value)


func refresh() -> void:
	if not _quota:
		return
	tooltip_text = describe()
	queue_redraw()


## Texto del tooltip: cada ventana con su porcentaje y reinicio, el límite si lo hay, o por qué no
## hay datos.
func describe() -> String:
	var lines: PackedStringArray = []
	var context := context_line(_context_used, _context_total)
	if not context.is_empty():
		lines.append_array([context, ""])
	lines.append(I18n.t("Plan quota"))
	if _quota.is_limited():
		var wait := _quota.seconds_until_retry()
		lines.append((I18n.t("Plan limit reached · you can send again in %s") % QuotaMonitor.format_duration(wait)) if wait > 0 else I18n.t("Plan limit reached · you can retry now"))
	if not _quota.has_data():
		if not _quota.is_limited():
			lines.append(I18n.t("No data yet: Claude Code reports it with the first message of each session. Other agents may not report it."))
		return "\n".join(lines)
	if _quota.utilization(QuotaMonitor.WINDOW_CURRENT) >= 0.0:
		lines.append(I18n.t("Outer ring: %s") % _quota.describe_window(QuotaMonitor.WINDOW_CURRENT))
	if _quota.utilization(QuotaMonitor.WINDOW_WEEKLY) >= 0.0:
		lines.append(I18n.t("Inner ring: %s") % _quota.describe_window(QuotaMonitor.WINDOW_WEEKLY))
	var group_lines := _quota.describe_groups()
	if not group_lines.is_empty():
		lines.append("")
		lines.append_array(group_lines)
	return "\n".join(lines)


func _draw() -> void:
	if not _quota:
		return
	var center := size / 2.0
	var width := AgentTheme.px(RING_WIDTH_PX)
	var outer := minf(size.x, size.y) / 2.0 - width / 2.0
	var inner := outer - width * 1.6
	_ring(center, outer, width, QuotaMonitor.WINDOW_CURRENT)
	_ring(center, inner, width, QuotaMonitor.WINDOW_WEEKLY)


func _ring(center: Vector2, radius: float, width: float, window: String) -> void:
	draw_arc(center, radius, 0.0, TAU, 32, TRACK_COLOR, width, true)
	var used := _quota.utilization(window)
	if _quota.is_limited() and used < 0.0:
		used = 1.0
	if used <= 0.0:
		return
	# Desde arriba, en sentido horario.
	draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * clampf(used, 0.0, 1.0), 32, color_for(used), width, true)


func color_for(used: float) -> Color:
	if _quota.is_limited() or used >= 1.0:
		return AgentTheme.ERROR
	if used >= _quota.pause_threshold and _quota.pause_enabled:
		return AgentTheme.ERROR.lerp(AgentTheme.WARNING, 0.5)
	if used >= _quota.warn_threshold:
		return AgentTheme.WARNING
	return _accent
