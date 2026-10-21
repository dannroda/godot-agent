@tool
extends Button
## Indicador del completado en la barra del Script Editor (spec §16.7): estado (activo, pensando,
## error, apagado) y modo (local, híbrido o LLM con su modelo). Un clic lo prende o lo apaga.

signal toggle_requested

enum State { ACTIVE, THINKING, ERROR, OFF }

const STATE_COLORS: Dictionary = {
	State.ACTIVE: Color(0.45, 0.8, 0.5),
	State.THINKING: Color(0.95, 0.75, 0.35),
	State.ERROR: Color(0.95, 0.4, 0.4),
	State.OFF: Color(0.55, 0.55, 0.55),
}
const STATE_LABELS: Dictionary = {State.ACTIVE: "activo", State.THINKING: "pensando", State.ERROR: "error", State.OFF: "apagado"}

var state: State = State.ACTIVE
var mode_label: String = "local"
var detail: String = ""
var shortcut_text: String = ""


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void: toggle_requested.emit())
	_refresh()


func set_state(p_state: State, p_mode_label: String, p_detail: String = "") -> void:
	if p_state == state and p_mode_label == mode_label and p_detail == detail:
		return
	state = p_state
	mode_label = p_mode_label
	detail = p_detail
	_refresh()


func _refresh() -> void:
	text = "● Completado: " + (mode_label if state != State.OFF else "apagado")
	add_theme_color_override(&"font_color", STATE_COLORS[state])
	add_theme_color_override(&"font_hover_color", (STATE_COLORS[state] as Color).lightened(0.2))
	var lines := PackedStringArray(["Completado inline: %s · %s" % [STATE_LABELS[state], mode_label]])
	if not detail.is_empty():
		lines.append(detail)
	lines.append("Clic: %s%s" % ["prender" if state == State.OFF else "apagar", " (%s)" % shortcut_text if not shortcut_text.is_empty() else ""])
	tooltip_text = "\n".join(lines)


## La barra de menús del Script Editor (Archivo, Editar, …): el primer HBoxContainer con MenuButton.
static func menu_bar(script_editor: Control) -> HBoxContainer:
	for box: Node in script_editor.find_children("*", "HBoxContainer", true, false):
		for child: Node in box.get_children():
			if child is MenuButton:
				return box as HBoxContainer
	return null
