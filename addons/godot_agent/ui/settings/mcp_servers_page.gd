@tool
extends VBoxContainer
## MCP servers de terceros en Settings → MCP (m7-34): la lista del proyecto y la del usuario, con
## un formulario para agregar o editar e importar del `.mcp.json` del proyecto. Se edita una copia
## y se guarda con el resto del diálogo.

signal servers_changed

const I18n := preload("../../core/i18n.gd")
const ExternalMcpServers := preload("../../mcp/external_mcp_servers.gd")
const AgentTheme := preload("../agent_theme.gd")

const SCOPE_PROJECT := "project"
const SCOPE_USER := "user"
const SCOPES: PackedStringArray = [SCOPE_PROJECT, SCOPE_USER]
const SCOPE_LABELS: Dictionary = {
	SCOPE_PROJECT: "This project",  # i18n
	SCOPE_USER: "All my projects",  # i18n
}
const MCP_JSON := "res://.mcp.json"

const GUIDE_URL := "https://github.com/dannroda/godot-agent/wiki/Settings#other-mcp-servers"
const GUIDE_URL_ES := "https://github.com/dannroda/godot-agent/wiki/Settings-es#otros-servidores-mcp"

var _list: VBoxContainer
var _form: GridContainer
var _fields: Dictionary = {}  # nombre -> control
## Filas del formulario que solo valen para un transporte: nombre -> [label, control].
var _rows: Dictionary = {}
var _import: Button
var _import_result: Label
## Copia en edición: los servers con `scope` (SCOPE_PROJECT o SCOPE_USER).
var _servers: Array = []
var _editing: int = -1


func _init() -> void:
	add_theme_constant_override(&"separation", AgentTheme.px(6))
	var title := Label.new()
	title.text = I18n.t("Other MCP servers")
	title.add_theme_font_size_override(&"font_size", AgentTheme.px(15))
	add_child(title)
	# Una línea y la guía (m12-23): el detalle ($VAR, los servers propios del agente, /mcp) está en la wiki.
	var intro := HBoxContainer.new()
	add_child(intro)
	var hint := _hint(I18n.t("Tools from other programs (Blender, a database…) for the agent, besides godot.*. They apply from the next session."))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_child(hint)
	var guide := LinkButton.new()
	guide.text = I18n.t("Guide")
	guide.tooltip_text = guide_url()
	guide.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	guide.pressed.connect(func() -> void: OS.shell_open(guide_url()))
	intro.add_child(guide)
	_list = VBoxContainer.new()
	add_child(_list)
	var actions := HBoxContainer.new()
	add_child(actions)
	var add := Button.new()
	add.text = I18n.t("+ Add server")
	add.pressed.connect(func() -> void:
		var entry := ExternalMcpServers.make(_free_name("server"))
		entry["scope"] = SCOPE_PROJECT
		_servers.append(entry)
		_edit(_servers.size() - 1))
	actions.add_child(add)
	_import = Button.new()
	_import.text = I18n.t("Import .mcp.json")
	_import.tooltip_text = I18n.t("Adds the servers of the project's .mcp.json (the file Claude Code and other agents read) that are not on the list yet.")
	_import.pressed.connect(_on_import)
	actions.add_child(_import)
	_import_result = _hint("")
	_import_result.visible = false
	add_child(_import_result)
	_form = GridContainer.new()
	_form.columns = 2
	_form.visible = false
	add_child(_form)
	_add_field("name", I18n.t("Name"), LineEdit.new())
	var scope := OptionButton.new()
	for key: String in SCOPES:
		scope.add_item(I18n.t(SCOPE_LABELS[key]))
	scope.tooltip_text = I18n.t("This project: saved in addons/godot_agent/config/project_config.tres, so it goes with the project. All my projects: saved in the editor settings.")
	_add_field("scope", I18n.t("Saved in"), scope)
	var transport := OptionButton.new()
	transport.add_item(I18n.t("Command (stdio)"))
	transport.add_item(I18n.t("URL (HTTP)"))
	transport.item_selected.connect(func(_index: int) -> void: _update_transport_rows())
	_add_field("transport", I18n.t("Type"), transport)
	_add_field("command", I18n.t("Command"), LineEdit.new())
	_add_field("args", I18n.t("Arguments (one per line)"), _code_edit())
	_add_field("env", I18n.t("Environment (KEY=value or KEY=$VAR)"), _code_edit())
	_add_field("url", I18n.t("URL"), LineEdit.new())
	_add_field("headers", I18n.t("Headers (Name: value)"), _code_edit())
	(_fields.command as LineEdit).placeholder_text = "uvx"
	(_fields.url as LineEdit).placeholder_text = "https://mcp.example.com/mcp"
	(_fields.headers as TextEdit).placeholder_text = "Authorization: Bearer $EXAMPLE_TOKEN"
	_form.add_child(Control.new())
	var done := Button.new()
	done.text = I18n.t("Done")
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(_apply_form)
	_form.add_child(done)


func load_from(user_list: Array, project_list: Array) -> void:
	_servers = []
	for pair: Array in [[project_list, SCOPE_PROJECT], [user_list, SCOPE_USER]]:
		for entry: Dictionary in ExternalMcpServers.normalize_list(pair[0]):
			entry["scope"] = pair[1]
			_servers.append(entry)
	_editing = -1
	_form.visible = false
	_import_result.visible = false
	_import.disabled = not FileAccess.file_exists(MCP_JSON)
	_rebuild()


## Aplica el formulario abierto (al guardar el diálogo con un server a medio editar).
func apply_pending() -> void:
	if _form.visible:
		_apply_form()


func project_servers() -> Array:
	return _of_scope(SCOPE_PROJECT)


func user_servers() -> Array:
	return _of_scope(SCOPE_USER)


## Nombres de todos los servers de la lista (para las filas de la matriz de permisos).
func server_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for entry: Dictionary in _servers:
		if not entry.name in names:
			names.append(entry.name)
	return names


## Mensaje del primer problema, o "".
func validate() -> String:
	for scope: String in SCOPES:
		var error := ExternalMcpServers.validate(_of_scope(scope))
		if not error.is_empty():
			return error
	return ""


## Agrega los servers del `.mcp.json` del proyecto que no están en la lista. Devuelve cuántos.
func import_mcp_json(text: String) -> int:
	var added := 0
	for entry: Dictionary in ExternalMcpServers.from_mcp_json(text):
		if entry.name == ExternalMcpServers.RESERVED_NAME or entry.name in server_names():
			continue
		entry["scope"] = SCOPE_PROJECT
		_servers.append(entry)
		added += 1
	_rebuild()
	return added


func _on_import() -> void:
	var added := import_mcp_json(FileAccess.get_file_as_string(MCP_JSON))
	_import_result.visible = true
	_import_result.text = I18n.t("%d servers added from .mcp.json.") % added if added > 0 else I18n.t("The servers of .mcp.json are already on the list.")


func _rebuild() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _servers.is_empty():
		_list.add_child(_hint(I18n.t("No other servers yet.")))
	for i in _servers.size():
		var entry: Dictionary = _servers[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, 8))
		var row := HBoxContainer.new()
		card.add_child(row)
		var enabled := CheckBox.new()
		enabled.button_pressed = bool(entry.enabled)
		enabled.tooltip_text = I18n.t("Off: the server stays on the list but the agent doesn't get it.")
		enabled.toggled.connect(func(on: bool) -> void:
			_servers[i].enabled = on
			servers_changed.emit())
		row.add_child(enabled)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name_label := Label.new()
		name_label.text = "%s · %s" % [entry.name, I18n.t(SCOPE_LABELS[entry.scope])]
		info.add_child(name_label)
		var command := Label.new()
		command.text = ExternalMcpServers.describe(entry)
		command.clip_text = true
		command.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		command.add_theme_font_override(&"font", AgentTheme.mono_font())
		command.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		info.add_child(command)
		for action: Array in [[I18n.t("Edit"), _edit], [I18n.t("Remove"), _remove]]:
			var button := Button.new()
			button.text = action[0]
			button.flat = true
			button.pressed.connect((action[1] as Callable).bind(i))
			row.add_child(button)
		_list.add_child(card)


func _edit(index: int) -> void:
	if _form.visible and _editing >= 0 and _editing != index:
		_apply_form()  # no perder lo que se estaba editando en otro server
	_editing = index
	var entry: Dictionary = _servers[index]
	(_fields.name as LineEdit).text = entry.name
	(_fields.scope as OptionButton).select(maxi(SCOPES.find(entry.scope), 0))
	(_fields.transport as OptionButton).select(1 if entry.transport == ExternalMcpServers.TRANSPORT_HTTP else 0)
	(_fields.command as LineEdit).text = entry.command
	(_fields.args as TextEdit).text = "\n".join(entry.args)
	(_fields.env as TextEdit).text = _join_pairs(entry.env, "=")
	(_fields.url as LineEdit).text = entry.url
	(_fields.headers as TextEdit).text = _join_pairs(entry.headers, ": ")
	_form.visible = true
	_update_transport_rows()
	_rebuild()


func _apply_form() -> void:
	if _editing < 0 or _editing >= _servers.size():
		_form.visible = false
		return
	var entry: Dictionary = _servers[_editing]
	entry.name = (_fields.name as LineEdit).text.strip_edges()
	entry.scope = SCOPES[(_fields.scope as OptionButton).selected]
	entry.transport = ExternalMcpServers.TRANSPORT_HTTP if (_fields.transport as OptionButton).selected == 1 else ExternalMcpServers.TRANSPORT_STDIO
	entry.command = (_fields.command as LineEdit).text.strip_edges()
	entry.args = Array(_lines((_fields.args as TextEdit).text))
	entry.env = _split_pairs((_fields.env as TextEdit).text, "=")
	entry.url = (_fields.url as LineEdit).text.strip_edges()
	entry.headers = _split_pairs((_fields.headers as TextEdit).text, ":")
	_editing = -1
	_form.visible = false
	_rebuild()
	servers_changed.emit()


func _remove(index: int) -> void:
	_servers.remove_at(index)
	if _editing == index:
		_editing = -1
		_form.visible = false
	elif _editing > index:
		_editing -= 1
	_rebuild()
	servers_changed.emit()


func _update_transport_rows() -> void:
	var http := (_fields.transport as OptionButton).selected == 1
	for name: String in _rows:
		var visible_row := (name == "url" or name == "headers") == http
		for control: Control in _rows[name]:
			control.visible = visible_row


func _of_scope(scope: String) -> Array:
	var result: Array = []
	for entry: Dictionary in _servers:
		if entry.scope == scope:
			var copy := entry.duplicate(true)
			copy.erase("scope")
			result.append(copy)
	return result


func _free_name(base: String) -> String:
	var names := server_names()
	var name := base
	var n := 2
	while name in names:
		name = "%s-%d" % [base, n]
		n += 1
	return name


func _add_field(key: String, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	_form.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(control)
	_fields[key] = control
	if key in ["command", "args", "env", "url", "headers"]:
		_rows[key] = [label, control]


func _code_edit() -> TextEdit:
	var text := TextEdit.new()
	text.custom_minimum_size.y = AgentTheme.px(60)
	text.add_theme_font_override(&"font", AgentTheme.mono_font())
	return text


## La sección de la wiki sobre otros servidores MCP, en el idioma de la interfaz.
static func guide_url() -> String:
	return GUIDE_URL_ES if I18n.locale() == "es" else GUIDE_URL


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label


static func _join_pairs(values: Dictionary, separator: String) -> String:
	var lines: PackedStringArray = []
	for key: String in values:
		lines.append("%s%s%s" % [key, separator, values[key]])
	return "\n".join(lines)


static func _split_pairs(text: String, separator: String) -> Dictionary:
	var result: Dictionary = {}
	for line: String in _lines(text):
		var at := line.find(separator)
		if at > 0:
			result[line.left(at).strip_edges()] = line.substr(at + 1).strip_edges()
	return result


static func _lines(text: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.strip_edges().is_empty():
			result.append(line.strip_edges())
	return result
