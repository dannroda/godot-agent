@tool
extends Control
## Cuota del plan en la fila del composer (spec §9.1, §10.1): dos anillos con _draw, la ventana
## actual afuera y la semanal adentro, del color del umbral. El detalle va en un panel que se abre al
## pasar el mouse. Sin datos del agente queda gris y el panel dice por qué (Claude Code la informa
## con el primer mensaje de cada sesión, D22).
##
## No es el tooltip de Godot (m17-14): el anillo está abajo de todo y el detalle es alto, así que
## Godot lo corría hacia arriba para que entre en la pantalla, quedaba debajo del mouse y se cerraba
## solo. El panel se abre siempre arriba del anillo y no toma el mouse.

const QuotaMonitor := preload("../../core/quota_monitor.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")

const SIZE_PX := 16
const RING_WIDTH_PX := 2.5
const TRACK_COLOR := Color(1, 1, 1, 0.14)
const HOVER_DELAY_S := 0.35
const HOVER_GAP_PX := 6

var _quota: QuotaMonitor
var _accent: Color
## Contexto usado de la sesión (m12-18): va primero en el tooltip.
var _context_used: int = 0
var _context_total: int = 0
var _drawn_state: Array = []
## El detalle (lo que antes era el tooltip).
var hint_text: String = ""
var _hint_panel: PanelContainer
var _hint_label: Label
var _hover_timer: Timer


func setup(quota: QuotaMonitor, accent: Color) -> void:
	_quota = quota
	_accent = accent


func _ready() -> void:
	custom_minimum_size = Vector2.ONE * AgentTheme.px(SIZE_PX)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = HOVER_DELAY_S
	_hover_timer.timeout.connect(_show_hint)
	add_child(_hover_timer)
	mouse_entered.connect(_hover_timer.start)
	mouse_exited.connect(_hide_hint)
	if _quota:
		_quota.changed.connect(refresh)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_hide_hint()


func is_hint_visible() -> bool:
	return _hint_panel != null and _hint_panel.visible


func _show_hint() -> void:
	if hint_text.is_empty() or not is_visible_in_tree():
		return
	if _hint_panel == null:
		_hint_panel = PanelContainer.new()
		_hint_panel.top_level = true  # fuera del layout y del recorte del dock
		_hint_panel.z_index = 100
		_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := get_theme_stylebox(&"panel", &"TooltipPanel")
		if style:
			_hint_panel.add_theme_stylebox_override(&"panel", style)
		_hint_label = Label.new()
		_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if has_theme_color(&"font_color", &"TooltipLabel"):
			_hint_label.add_theme_color_override(&"font_color", get_theme_color(&"font_color", &"TooltipLabel"))
		_hint_panel.add_child(_hint_label)
		add_child(_hint_panel)
	_hint_label.text = hint_text
	_hint_panel.visible = true
	_hint_panel.reset_size()
	_place_hint()


func _hide_hint() -> void:
	if _hover_timer:
		_hover_timer.stop()
	if _hint_panel:
		_hint_panel.visible = false


## Arriba del anillo y dentro de la ventana; abajo solo si arriba no entra.
func _place_hint() -> void:
	var area := get_viewport().get_visible_rect()
	var ring := get_global_rect()
	var panel_size := _hint_panel.get_combined_minimum_size()
	var gap := AgentTheme.px(HOVER_GAP_PX)
	var x := clampf(ring.get_center().x - panel_size.x / 2.0, area.position.x, maxf(area.position.x, area.end.x - panel_size.x))
	var y := ring.position.y - gap - panel_size.y
	if y < area.position.y:
		y = ring.end.y + gap
	_hint_panel.global_position = Vector2(x, y)


func set_context(used: int, total: int) -> void:
	if used == _context_used and total == _context_total:
		return
	_context_used = used
	_context_total = total
	refresh()


static func context_line(used: int, total: int) -> String:
	if total <= 0:
		return ""
	return I18n.t("Context: %s of %s (%d %%)") % [_short(used), _short(total), roundi(100.0 * used / total)]


static func _short(value: int) -> String:
	return "%dk" % roundi(value / 1000.0) if value >= 1000 else str(value)


## El dock la llama cada segundo: solo toca el tooltip y el dibujo si cambiaron. En el editor del
## usuario el tooltip se cerraba al segundo de abrirse (m17-14).
func refresh() -> void:
	if not _quota:
		return
	var text := describe()
	if text != hint_text:
		hint_text = text
		if is_hint_visible():
			_hint_label.text = text
			_hint_panel.reset_size()
			_place_hint()
	var state := _draw_state()
	if state != _drawn_state:
		_drawn_state = state
		queue_redraw()


## Lo que define el dibujo: si no cambia, no se redibuja.
func _draw_state() -> Array:
	var state: Array = [_quota.is_limited(), _quota.has_data()]
	for window: String in [QuotaMonitor.WINDOW_CURRENT, QuotaMonitor.WINDOW_WEEKLY]:
		var used := _quota.utilization(window)
		state.append_array([snappedf(used, 0.001), color_for(used)])
	return state


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
