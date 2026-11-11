@tool
extends EditorContextMenuPlugin
## «Preguntar al agente» en los menús contextuales del editor (m11-54): FileSystem, árbol de escena y
## Script Editor con texto seleccionado. Deja lo elegido en el composer de la pestaña activa (archivos y
## nodos como @mención, la selección de código como bloque con su ruta y sus líneas) sin mandarlo.
## Una instancia por slot: el editor la registra en uno solo.

const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("../ui/agent_theme.gd")

## Selecciones más largas se cortan: el agente puede leer el archivo entero con la @mención.
const SELECTION_MAX_CHARS := 4000

## El slot de EditorContextMenuPlugin donde está registrada.
var slot: int
## Callable(text: String): lo pone en el composer y muestra el dock.
var ask: Callable


func _init(menu_slot: int = CONTEXT_SLOT_FILESYSTEM) -> void:
	slot = menu_slot


func _popup_menu(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	var label := I18n.t("Ask the agent")
	var icon := AgentTheme.icon(&"Help")
	match slot:
		CONTEXT_SLOT_FILESYSTEM:
			add_context_menu_item(label, func(selected: Variant) -> void: _ask(files_text(selected as PackedStringArray)), icon)
		CONTEXT_SLOT_SCENE_TREE:
			add_context_menu_item(label, func(nodes: Variant) -> void:
				_ask(nodes_text(EditorInterface.get_edited_scene_root(), nodes as Array)), icon)
		CONTEXT_SLOT_SCRIPT_EDITOR_CODE:
			var editor := EditorInterface.get_script_editor().get_current_editor()
			var code := editor.get_base_editor() as CodeEdit if editor else null
			if code == null or not code.has_selection():
				return
			# En este slot `paths` trae la ruta del nodo CodeEdit, no la del script.
			var script := EditorInterface.get_script_editor().get_current_script()
			var path := script.resource_path if script else ""
			if path.is_empty() or not path.begins_with("res://"):
				return
			add_context_menu_item(label, func(code_edit: Variant) -> void:
				if code_edit is CodeEdit:
					_ask(selection_text(path, code_edit as CodeEdit)), icon)


func _ask(text: String) -> void:
	if not text.is_empty() and ask.is_valid():
		ask.call(text)


## «@res://a.gd @res://b.tscn » para los archivos (y carpetas) elegidos en el FileSystem.
static func files_text(paths: PackedStringArray) -> String:
	var mentions: PackedStringArray = []
	for path in paths:
		mentions.append("@" + path)
	return " ".join(mentions) + " " if not mentions.is_empty() else ""


## «@Player/Sprite @. » para los nodos elegidos, relativos a la escena abierta (como arrastrarlos).
static func nodes_text(root: Node, nodes: Array) -> String:
	var mentions: PackedStringArray = []
	for node: Variant in nodes:
		if root and node is Node and (node == root or root.is_ancestor_of(node)):
			mentions.append("@" + ("." if node == root else String(root.get_path_to(node))))
	return " ".join(mentions) + " " if not mentions.is_empty() else ""


## La selección del CodeEdit como bloque de código con la @mención del archivo y las líneas (desde 1).
static func selection_text(path: String, code: CodeEdit) -> String:
	if not code.has_selection():
		return ""
	var from := code.get_selection_from_line() + 1
	var to := code.get_selection_to_line() + 1
	if code.get_selection_to_column() == 0 and to > from:
		to -= 1  # seleccionar hasta el principio de la línea siguiente no la incluye
	var selected := code.get_selected_text()
	var cut := selected.length() > SELECTION_MAX_CHARS
	if cut:
		selected = selected.left(SELECTION_MAX_CHARS)
	var lines := ("%d" % from) if from == to else ("%d-%d" % [from, to])
	var language := "gdscript" if path.get_extension() == "gd" else path.get_extension()
	# En inglés, como los prompts del harness: es para el agente.
	return "@%s (%s %s)%s:\n```%s\n%s\n```\n" % [path, "lines" if from != to else "line", lines,
		(" [cut at %d characters]" % SELECTION_MAX_CHARS) if cut else "", language, selected.rstrip("\n")]
