@tool
extends VBoxContainer
## Medidor de la cuota del plan en el dock (spec §9.1, §10.1): ventana actual y semanal, con
## porcentaje y tiempo hasta el reinicio. Sin datos del agente queda oculto.

const QuotaMonitor := preload("../../core/quota_monitor.gd")
const AgentTheme := preload("../agent_theme.gd")

const WINDOWS: PackedStringArray = [QuotaMonitor.WINDOW_CURRENT, QuotaMonitor.WINDOW_WEEKLY]

var _quota: QuotaMonitor
var _accent: Color
var _rows: Dictionary = {}  # ventana -> {label: Label, bar: ProgressBar}
var _limited_label: Label


func setup(quota: QuotaMonitor, accent: Color) -> void:
	_quota = quota
	_accent = accent


func _ready() -> void:
	add_theme_constant_override(&"separation", AgentTheme.px(2))
	for window: String in WINDOWS:
		var label := Label.new()
		label.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.custom_minimum_size.y = AgentTheme.px(4)
		bar.add_theme_stylebox_override(&"background", AgentTheme.panel(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 2, 0))
		add_child(bar)
		_rows[window] = {"label": label, "bar": bar}
	_limited_label = Label.new()
	_limited_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_limited_label.add_theme_color_override(&"font_color", AgentTheme.ERROR)
	add_child(_limited_label)
	_quota.changed.connect(refresh)
	refresh()


func refresh() -> void:
	visible = _quota.has_data() or _quota.is_limited()
	for window: String in WINDOWS:
		var row: Dictionary = _rows[window]
		var known := _quota.utilization(window) >= 0.0
		(row.label as Label).visible = known
		(row.bar as ProgressBar).visible = known
		if not known:
			continue
		var used := _quota.utilization(window)
		var color := _color_for(used)
		(row.label as Label).text = _quota.describe_window(window)
		(row.label as Label).add_theme_color_override(&"font_color", color if used >= _quota.warn_threshold else AgentTheme.MUTED)
		(row.bar as ProgressBar).value = used
		(row.bar as ProgressBar).add_theme_stylebox_override(&"fill", AgentTheme.panel(color, Color.TRANSPARENT, 2, 0))
		(row.bar as ProgressBar).tooltip_text = "Cuota del plan informada por el agente: %d %%" % roundi(used * 100.0)
	_limited_label.visible = _quota.is_limited()
	if _quota.is_limited():
		var wait := _quota.seconds_until_retry()
		_limited_label.text = ("Límite del plan alcanzado · se puede volver a enviar en %s" % QuotaMonitor.format_duration(wait)) if wait > 0 else "Límite del plan alcanzado · ya se puede reintentar"


func _color_for(used: float) -> Color:
	if _quota.is_limited() or used >= 1.0:
		return AgentTheme.ERROR
	if used >= _quota.pause_threshold and _quota.pause_enabled:
		return AgentTheme.ERROR.lerp(AgentTheme.WARNING, 0.5)
	if used >= _quota.warn_threshold:
		return AgentTheme.WARNING
	return _accent
