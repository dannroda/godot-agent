@tool
extends Button
## Indicador del completado en la barra del Script Editor (spec §16.7): estado (activo, pensando,
## error, apagado) y modo (local, híbrido o LLM con su modelo). Un clic lo prende o lo apaga.

signal toggle_requested

const I18n := preload("../core/i18n.gd")

enum IndicatorState { ACTIVE, THINKING, ERROR, OFF }

const STATE_COLORS: Dictionary = {
	IndicatorState.ACTIVE: Color(0.45, 0.8, 0.5),
	IndicatorState.THINKING: Color(0.95, 0.75, 0.35),
	IndicatorState.ERROR: Color(0.95, 0.4, 0.4),
	IndicatorState.OFF: Color(0.55, 0.55, 0.55),
}
const STATE_LABELS: Dictionary = {
	IndicatorState.ACTIVE: "active",  # i18n
	IndicatorState.THINKING: "thinking",  # i18n
	IndicatorState.ERROR: "error",  # i18n
	IndicatorState.OFF: "off",  # i18n
}

var state: IndicatorState = IndicatorState.ACTIVE
var mode_label: String = "local"
var detail: String = ""
var shortcut_text: String = ""


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void: toggle_requested.emit())
	_refresh()


func set_state(p_state: IndicatorState, p_mode_label: String, p_detail: String = "") -> void:
	if p_state == state and p_mode_label == mode_label and p_detail == detail:
		return
	state = p_state
	mode_label = p_mode_label
	detail = p_detail
	_refresh()


func _refresh() -> void:
	text = "● " + I18n.t("Completion: %s") % (mode_label if state != IndicatorState.OFF else I18n.t(STATE_LABELS[IndicatorState.OFF]))
	add_theme_color_override(&"font_color", STATE_COLORS[state])
	add_theme_color_override(&"font_hover_color", (STATE_COLORS[state] as Color).lightened(0.2))
	var lines := PackedStringArray([I18n.t("Inline completion: %s · %s") % [I18n.t(STATE_LABELS[state]), mode_label]])
	if not detail.is_empty():
		lines.append(detail)
	var click := I18n.t("Click: turn on") if state == IndicatorState.OFF else I18n.t("Click: turn off")
	lines.append(click + (" (%s)" % shortcut_text if not shortcut_text.is_empty() else ""))
	tooltip_text = "\n".join(lines)


## La barra de menús del Script Editor (Archivo, Editar, …): el primer HBoxContainer con MenuButton.
static func menu_bar(script_editor: Control) -> HBoxContainer:
	for box: Node in script_editor.find_children("*", "HBoxContainer", true, false):
		for child: Node in box.get_children():
			if child is MenuButton:
				return box as HBoxContainer
	return null
