@tool
extends Control
## Cuota del plan en la fila del composer (spec §9.1, §10.1): dos anillos con _draw, la ventana
## actual afuera y la semanal adentro, del color del umbral. El detalle va en un panel que se abre al
## pasar el mouse. Sin datos del agente queda gris y el panel dice por qué (Claude Code la informa
## con el primer mensaje de cada sesión, D22).
##
## No es el tooltip de Godot (m17-14): el anillo está abajo de todo y el detalle es alto, así que
## Godot lo corría hacia arriba para que entre en la pantalla, quedaba debajo del mouse y se cerraba
## solo. El panel se abre siempre arriba del anillo y no toma el mouse. Cada porcentaje es una barra
## del color del anillo (m17-23); hint_text guarda lo mismo en texto.

const QuotaMonitor := preload("../../core/quota_monitor.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")

const SIZE_PX := 16
const RING_WIDTH_PX := 2.5
const TRACK_COLOR := Color(1, 1, 1, 0.14)
const HOVER_DELAY_S := 0.35
const HOVER_GAP_PX := 6
const HINT_WIDTH_PX := 280
const BAR_HEIGHT_PX := 6

var _quota: QuotaMonitor
var _accent: Color
## Contexto usado de la sesión (m12-18): va primero en el tooltip.
var _context_used: int = 0
var _context_total: int = 0
var _drawn_state: Array = []
## El detalle (lo que antes era el tooltip).
var hint_text: String = ""
var _hint_panel: PanelContainer
var _hint_rows: VBoxContainer
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
		_hint_rows = VBoxContainer.new()
		_hint_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hint_rows.custom_minimum_size.x = AgentTheme.px(HINT_WIDTH_PX)
		_hint_rows.add_theme_constant_override(&"separation", AgentTheme.px(4))
		_hint_panel.add_child(_hint_rows)
		add_child(_hint_panel)
	_fill_hint()
	_hint_panel.visible = true
	_hint_panel.reset_size()
	_place_hint()


## Arma el panel con hint_rows(): títulos, textos y barras.
func _fill_hint() -> void:
	for child in _hint_rows.get_children():
		_hint_rows.remove_child(child)
		child.queue_free()
	for row: Dictionary in hint_rows():
		match row.kind:
			"title":
				var title := _hint_text_label(row.text, false)
				title.add_theme_color_override(&"font_color", AgentTheme.MUTED)
				_hint_rows.add_child(title)
			"text":
				_hint_rows.add_child(_hint_text_label(row.text, true))
			"bar":
				_hint_rows.add_child(_hint_bar(row))


func _hint_text_label(text: String, wrap: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = AgentTheme.px(HINT_WIDTH_PX)
	if has_theme_color(&"font_color", &"TooltipLabel"):
		label.add_theme_color_override(&"font_color", get_theme_color(&"font_color", &"TooltipLabel"))
	return label


## «Ventana · anillo de afuera        36 % · en 1 h» y abajo la barra, del color del anillo.
func _hint_bar(row: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", AgentTheme.px(2))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _hint_text_label(row.label, false)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var detail := _hint_text_label(row.detail, false)
	detail.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	line.add_child(detail)
	box.add_child(line)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = clampf(row.value, 0.0, 1.0)
	bar.custom_minimum_size.y = AgentTheme.px(BAR_HEIGHT_PX)
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_COLOR
	track.set_corner_radius_all(AgentTheme.px(3))
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = row.color
	bar.add_theme_stylebox_override(&"background", track)
	bar.add_theme_stylebox_override(&"fill", fill)
	box.add_child(bar)
	return box


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
			_fill_hint()
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


## Lo que muestra el panel, en orden: {kind: "title"|"text", text} o {kind: "bar", label, value 0–1,
## detail, color}. El contexto primero, después la cuota: límite, sin datos, ventanas y grupos.
func hint_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _context_total > 0:
		var ratio := float(_context_used) / _context_total
		rows.append({"kind": "bar", "label": I18n.t("Context"), "value": ratio, "color": _context_color(ratio),
			"detail": "%s / %s · %d %%" % [_short(_context_used), _short(_context_total), roundi(100.0 * ratio)]})
	if not _quota:
		return rows
	rows.append({"kind": "title", "text": I18n.t("Plan quota")})
	if _quota.is_limited():
		var wait := _quota.seconds_until_retry()
		rows.append({"kind": "text", "text": (I18n.t("Plan limit reached · you can send again in %s") % QuotaMonitor.format_duration(wait)) if wait > 0 else I18n.t("Plan limit reached · you can retry now")})
	if not _quota.has_data():
		if not _quota.is_limited():
			rows.append({"kind": "text", "text": I18n.t("No data yet: Claude Code reports it with the first message of each session. Other agents may not report it.")})
		return rows
	for window: String in [QuotaMonitor.WINDOW_CURRENT, QuotaMonitor.WINDOW_WEEKLY]:
		if _quota.utilization(window) >= 0.0:
			var ring := I18n.t("%s · outer ring") if window == QuotaMonitor.WINDOW_CURRENT else I18n.t("%s · inner ring")
			rows.append(_window_row(ring % I18n.t(QuotaMonitor.WINDOW_LABELS[window]), _quota.windows[window]))
	for group_name: String in _quota.groups:
		var group: Dictionary = _quota.groups[group_name]
		var windows := [QuotaMonitor.WINDOW_CURRENT, QuotaMonitor.WINDOW_WEEKLY].filter(func(window: String) -> bool: return group.get(window) is Dictionary)
		if windows.is_empty():
			continue
		rows.append({"kind": "title", "text": group_name})
		for window: String in windows:
			rows.append(_window_row(I18n.t(QuotaMonitor.WINDOW_LABELS[window]), group[window]))
	return rows


func _window_row(label: String, data: Dictionary) -> Dictionary:
	var used := float(data.get("utilization", 0.0))
	var detail := "%d %%" % roundi(used * 100.0)
	var reset := _quota.reset_in(data)
	if not reset.is_empty():
		detail = I18n.t("%d %% · resets in %s") % [roundi(used * 100.0), reset]
	return {"kind": "bar", "label": label, "value": used, "detail": detail, "color": color_for(used)}


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


## El contexto no depende de la cuota: acento, amarillo desde el 80 % y rojo desde el 95 %.
func _context_color(ratio: float) -> Color:
	if ratio >= 0.95:
		return AgentTheme.ERROR
	return AgentTheme.WARNING if ratio >= 0.8 else _accent


func color_for(used: float) -> Color:
	if _quota.is_limited() or used >= 1.0:
		return AgentTheme.ERROR
	if used >= _quota.pause_threshold and _quota.pause_enabled:
		return AgentTheme.ERROR.lerp(AgentTheme.WARNING, 0.5)
	if used >= _quota.warn_threshold:
		return AgentTheme.WARNING
	return _accent
