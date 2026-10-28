@tool
extends EditorContextMenuPlugin
## «Pedirle un cambio al agente» en el menú contextual del código del Script Editor (m11-05).

const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("../ui/agent_theme.gd")

## El InlineEdit que abre el campo.
var inline_edit: Node


## Con CONTEXT_SLOT_SCRIPT_EDITOR_CODE, `paths` trae la ruta del CodeEdit.
func _popup_menu(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	add_context_menu_item(I18n.t("Ask the agent to change this… (Alt+I)"), func(code_edit: Variant) -> void:
		if code_edit is CodeEdit and is_instance_valid(inline_edit):
			inline_edit.call(&"open_for", code_edit), AgentTheme.icon(&"Edit"))
