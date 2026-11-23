@tool
extends VBoxContainer
## Panel inferior "Agent Log" (spec §9.3): `hora · canal · mensaje` en mono, filtros por canal,
## copiar y modo raw con el JSON-RPC completo.

const AgentLog := preload("../../core/agent_log.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")
const I18n := preload("../../core/i18n.gd")
const DiagnosticReportDialog := preload("../diagnostic_report_dialog.gd")

## Tope de caracteres del raw por línea en pantalla (el log guarda hasta AgentLog.RAW_LIMIT).
const RAW_DISPLAY_LIMIT := 4000

var _log: AgentLog
## `() -> Dictionary`: el informe de diagnóstico de la pestaña activa (m11-80). Sin asignar, no hay botón.
var diagnostic_report: Callable
var _diagnostic_button: Button
var _enabled_channels: Dictionary = {}  # StringName -> bool
## La línea resaltada (m12-36: «Abrir el log» desde un error) y el párrafo de cada entrada a la vista.
var _highlight_seq: int = 0
var _paragraph_of: Dictionary = {}  # seq -> índice de párrafo

@onready var _channel_filters: HBoxContainer = %ChannelFilters
@onready var _count_label: Label = %CountLabel
@onready var _raw_toggle: CheckButton = %RawToggle
@onready var _copy_button: Button = %CopyButton
@onready var _clear_button: Button = %ClearButton
@onready var _output: RichTextLabel = %Output


func setup(agent_log: AgentLog) -> void:
	_log = agent_log


func _ready() -> void:
	_output.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	_output.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	for channel: StringName in AgentLog.CHANNELS:
		_enabled_channels[channel] = true
		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.button_pressed = true
		toggle.flat = true
		toggle.text = "● " + String(channel)
		toggle.tooltip_text = I18n.t("Show the %s channel") % channel
		toggle.add_theme_color_override(&"font_pressed_color", AgentTheme.CHANNEL_COLORS[channel])
		toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		toggle.toggled.connect(_on_channel_toggled.bind(channel))
		# El color solo no alcanza para ver si el canal está prendido (m12-05).
		toggle.toggled.connect(func(on: bool) -> void: toggle.text = ("● " if on else "○ ") + String(channel))
		_channel_filters.add_child(toggle)
	# Los textos del .tscn están en inglés: el panel no usa la traducción automática del editor.
	_raw_toggle.tooltip_text = I18n.t("Show the full JSON-RPC messages")
	# Íconos con tooltip: con texto, en el ancho por defecto del panel «Limpiar» quedaba cortado.
	_copy_button.text = ""
	_copy_button.tooltip_text = I18n.t("Copy the visible lines")
	_clear_button.text = ""
	_clear_button.tooltip_text = I18n.t("Clear the log")
	if Engine.is_editor_hint():
		_copy_button.icon = EditorInterface.get_editor_theme().get_icon(&"ActionCopy", &"EditorIcons")
		_clear_button.icon = EditorInterface.get_editor_theme().get_icon(&"Clear", &"EditorIcons")
	_raw_toggle.toggled.connect(func(_on: bool) -> void: _rebuild())
	_copy_button.pressed.connect(_on_copy_pressed)
	# Informe de diagnóstico (m11-80): al lado de Copiar, que copia las líneas (con rutas y texto).
	_diagnostic_button = Button.new()
	_diagnostic_button.name = "DiagnosticButton"
	_diagnostic_button.flat = true
	_diagnostic_button.tooltip_text = I18n.t("Copy diagnostic report…") + "\n" + I18n.t("A report to paste in a bug report: versions, system, agent and connection state, with no paths, conversation text or account. You see it before copying.")
	if Engine.is_editor_hint():
		_diagnostic_button.icon = EditorInterface.get_editor_theme().get_icon(&"Debug", &"EditorIcons")
	else:
		_diagnostic_button.text = "Report"
	_diagnostic_button.pressed.connect(open_diagnostic_dialog)
	_copy_button.add_sibling(_diagnostic_button)
	_clear_button.pressed.connect(_on_clear_pressed)
	if _log:
		_log.entry_added.connect(_on_entry_added)
		_log.cleared.connect(_rebuild)
	_rebuild()


func open_diagnostic_dialog() -> DiagnosticReportDialog:
	if not diagnostic_report.is_valid():
		return null
	var dialog := DiagnosticReportDialog.new()
	dialog.setup(diagnostic_report.call())
	add_child(dialog)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	dialog.popup_centered()
	return dialog


func _on_channel_toggled(on: bool, channel: StringName) -> void:
	_enabled_channels[channel] = on
	_rebuild()


func _on_entry_added(entry: Dictionary) -> void:
	if not is_node_ready():
		return
	# Al pasar la capacidad, el log descarta las más viejas: se reconstruye de a tandas.
	if _output.get_paragraph_count() > _log.capacity + 200:
		_rebuild()
		return
	if _visible(entry):
		_append(entry)
	_update_count()


func _rebuild() -> void:
	if not is_node_ready():
		return
	_output.clear()
	_paragraph_of.clear()
	if _log:
		for entry: Dictionary in _log.entries():
			if _visible(entry):
				_append(entry)
	_update_count()


func _append(entry: Dictionary) -> void:
	var color := AgentTheme.color_hex(AgentTheme.CHANNEL_COLORS.get(entry.channel, AgentTheme.MUTED))
	var line := "[color=#8a8f98]%s[/color]  [color=%s]%-4s[/color]  %s" % [
		entry.time, color, entry.channel, MarkdownBBCode.escape(str(entry.message))
	]
	if _raw_toggle.button_pressed and not str(entry.raw).is_empty():
		line += "\n[color=#8a8f98]%s[/color]" % MarkdownBBCode.escape(str(entry.raw).left(RAW_DISPLAY_LIMIT))
	if int(entry.seq) == _highlight_seq:
		line = "[bgcolor=%s]%s[/bgcolor]" % ["#" + Color(AgentTheme.WARNING, 0.25).to_html(true), line]
	_paragraph_of[int(entry.seq)] = maxi(0, _output.get_paragraph_count() - 1)
	_output.append_text(line + "\n")


## Muestra la línea `seq` resaltada y la lleva a la vista (con todos los canales prendidos, para
## que no quede escondida por un filtro).
func focus_entry(seq: int) -> void:
	if not is_node_ready():
		return
	_highlight_seq = seq
	for toggle: Node in _channel_filters.get_children():
		if toggle is Button and not (toggle as Button).button_pressed:
			(toggle as Button).button_pressed = true
	for channel: StringName in _enabled_channels:
		_enabled_channels[channel] = true
	_rebuild()
	if _paragraph_of.has(seq):
		_output.scroll_to_paragraph(_paragraph_of[seq])


func _visible(entry: Dictionary) -> bool:
	return _enabled_channels.get(entry.channel, true)


func _update_count() -> void:
	_count_label.text = I18n.t("%d entries") % (_log.entries().size() if _log else 0)


func _on_clear_pressed() -> void:
	if _log:
		_log.clear()


func _on_copy_pressed() -> void:
	if _log == null:
		return
	var lines: PackedStringArray = []
	for entry: Dictionary in _log.entries():
		if _visible(entry):
			lines.append(AgentLog.format_entry(entry, _raw_toggle.button_pressed))
	DisplayServer.clipboard_set("\n".join(lines))
