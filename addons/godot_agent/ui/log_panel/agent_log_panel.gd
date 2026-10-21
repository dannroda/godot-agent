@tool
extends VBoxContainer
## Panel inferior "Agent Log" (spec §9.3): `hora · canal · mensaje` en mono, filtros por canal,
## copiar y modo raw con el JSON-RPC completo.

const AgentLog := preload("../../core/agent_log.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")

## Tope de caracteres del raw por línea en pantalla (el log guarda hasta AgentLog.RAW_LIMIT).
const RAW_DISPLAY_LIMIT := 4000

var _log: AgentLog
var _enabled_channels: Dictionary = {}  # StringName -> bool

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
		toggle.text = String(channel)
		toggle.tooltip_text = "Mostrar el canal %s" % channel
		toggle.add_theme_color_override(&"font_pressed_color", AgentTheme.CHANNEL_COLORS[channel])
		toggle.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		toggle.toggled.connect(_on_channel_toggled.bind(channel))
		_channel_filters.add_child(toggle)
	_raw_toggle.toggled.connect(func(_on: bool) -> void: _rebuild())
	_copy_button.pressed.connect(_on_copy_pressed)
	_clear_button.pressed.connect(_on_clear_pressed)
	if _log:
		_log.entry_added.connect(_on_entry_added)
		_log.cleared.connect(_rebuild)
	_rebuild()


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
	_output.append_text(line + "\n")


func _visible(entry: Dictionary) -> bool:
	return _enabled_channels.get(entry.channel, true)


func _update_count() -> void:
	_count_label.text = "%d" % (_log.entries().size() if _log else 0)


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
