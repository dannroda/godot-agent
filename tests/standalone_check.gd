extends SceneTree
## m20-04: la app aparte (addons/godot_agent/standalone/main.tscn) fuera del editor, con el agente falso,
## sobre un proyecto git temporal (la última carpeta abierta). m20-09: ver los cambios del turno y deshacerlo.
## m20-05, m20-06: las tools godot.* de un editor abierto en la carpeta, por el MCP de la app.
## Uso: XDG_DATA_HOME=<carpeta temporal> godot --headless --path . --script tests/standalone_check.gd
## (sin XDG_DATA_HOME guarda en los datos del editor del usuario). Sale con 1 si algo falla.

const EditorContext := preload("res://addons/godot_agent/ui/editor_context.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const Main := preload("res://addons/godot_agent/standalone/main.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const McpPublication := preload("res://addons/godot_agent/mcp/mcp_publication.gd")
const McpServer := preload("res://addons/godot_agent/mcp/mcp_server.gd")
const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const PROJECT := "user://standalone_check_project"

var _project := ""
var _touched: Array = []

var _checks := 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var here := ProjectSettings.globalize_path("res://tests").trim_suffix("/")
	_check(Main.project_from_args(PackedStringArray(["--project=%s/" % here]), "/x") == here, "--project gana y sin barra final")
	_check(Main.absolute_path("~/juegos/a", "/home/u", "/w") == "/home/u/juegos/a", "~ se expande (el shell no lo hace después de =)")
	_check(Main.absolute_path("~", "/home/u", "/w") == "/home/u", "~ solo")
	_check(Main.absolute_path("juego/../otro", "/home/u", "/w") == "/w/otro", "relativa a la carpeta desde donde se lanzó")
	_check(Main.project_from_args(PackedStringArray(["--project=/no/existe"]), "") == "", "un --project que no existe no se usa")
	_check(Main.project_from_args(PackedStringArray(), "/no/existe") == "", "una última carpeta que ya no existe no se usa")
	_project = _make_project()
	HarnessSettings.new(null, Main.settings_path()).set_value(Main.KEY_LAST_PROJECT, _project)
	var app: Control = load("res://addons/godot_agent/standalone/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(EditorContext.project_path() == _project, "sin --project, la última carpeta abierta")
	_check(app._tabs.ids() == PackedStringArray(["s1"]), "arranca con una pestaña")
	app._open_settings()
	await process_frame
	_check(app._settings_dialog.visible, "los ajustes se abren")
	_check(not root.gui_embed_subwindows, "diálogos y menús en ventanas del sistema, no embebidos")
	app._settings_dialog.hide()
	var controller = app._sessions["s1"].controller
	var broker = controller.permissions
	_check(app._editor_mcp("s1").is_empty(), "sin editor abierto, la sesión arranca sin su MCP")
	_check(not broker._read_only_reason().contains("godot.") and not broker._godot_window_reason("x").contains("godot."), "sin MCP del editor, los rechazos no nombran tools godot.*")
	_check(controller._note_for_agent.contains("godot.* tools are not available"), "el agente sabe que no tiene las tools del editor")
	var scene := _project.path_join("main.tscn")
	var refused: Variant = await controller.fs.write_text_file({"path": scene, "content": "[gd_scene format=3]"})
	_check(not FileAccess.file_exists(scene) and not str(refused.error).contains("godot.") and str(refused.error).contains("headless"), "sin editor, una escena a mano se rechaza y el motivo manda a Godot headless")
	controller._note_for_agent = ""
	var editor := _fake_editor()  # como un editor abierto en la carpeta, con su MCP publicado
	var servers: Array = app._editor_mcp("s1")
	_check(servers.size() == 1 and str(servers[0]).contains(app._mcp.url()) and not str(servers[0]).contains(editor.token), "con el editor abierto, la sesión usa el MCP de la app, sin ver el token del editor")
	_check(broker.editor_tools and controller._note_for_agent.contains("editor is open"), "y el agente sabe que tiene las tools godot.* del editor")
	var asked := []
	var real_authorize: Callable = app._bridge.authorize
	app._bridge.authorize = func(caller: String, info: Dictionary) -> String:
		asked.append([caller, info.group, info.title])
		return "" if asked.size() == 1 else "Permission denied by the user."  # la primera se aprueba, la segunda no
	var reply := await _post(app._mcp.url(), app._mcp.session_token("s1"), {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "touch", "arguments": {"name": "x"}}})
	_check(asked == [["s1", "edit_files", "godot.touch"]], "la app autoriza en la pestaña que llama, con el grupo y el título que dice el editor")
	_check(_touched == ["x"] and str(reply).contains("touched x"), "aprobada, la tool corre en el editor y el resultado vuelve al agente")
	reply = await _post(app._mcp.url(), app._mcp.session_token("s1"), {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "touch", "arguments": {"name": "y"}}})
	_check(_touched == ["x"] and str(reply).contains("Permission denied"), "rechazada, no llega al editor")
	app._bridge.authorize = real_authorize
	controller.model.project_mode = {"name": "UI", "editable": PackedStringArray(["ui/**"])}
	reply = await _post(app._mcp.url(), app._mcp.session_token("s1"), {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "save", "arguments": {"path": "res://data/a.tres"}}})
	_check(_touched == ["x"] and str(reply).contains("UI"), "el modo del proyecto de la pestaña rechaza escribir fuera de sus archivos, sin tarjeta")
	reply = await _post(app._mcp.url(), app._mcp.session_token("s1"), {"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "touch", "arguments": {"name": "w"}}})
	_check(_touched == ["x"] and str(reply).contains("UI"), "y una tool que escribe sin decir dónde")
	controller.model.project_mode = {}
	var other: String = app.open_tab()
	app._coordinator.claim_label(other, PackedStringArray([_project.path_join("data/a.tres")]))
	var refused_lock: String = await app._authorize_editor_tool("s1", {"group": "edit_files", "title": "godot.save", "description": "", "targets": {"declared": true, "paths": ["res://data/a.tres"]}})
	_check(refused_lock.contains("is being edited by"), "un archivo que tiene otra pestaña de la app no se toca por godot.*")
	app.close_tab(other)
	reply = await _post(editor.url(), "not-the-token", {"jsonrpc": "2.0", "id": 3, "method": "godot_agent/describe", "params": {"name": "touch"}})
	_check(str(reply).contains("Invalid token"), "el editor no describe ni corre nada sin su token")
	editor.stop()
	reply = await _post(app._mcp.url(), app._mcp.session_token("s1"), {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "touch", "arguments": {"name": "z"}}})
	_check(str(reply).contains("no longer open"), "con el editor cerrado, la tool lo dice")
	editor.queue_free()
	McpPublication.remove(_project)
	controller._note_for_agent = ""
	var second: String = app.open_tab()
	_check(app._tabs.ids().size() == 2, "una segunda pestaña")
	await _turn(app, "s1", "a")
	await _turn(app, second, "b")
	_check(FileAccess.file_exists(_project.path_join("a.gd")) and FileAccess.file_exists(_project.path_join("b.gd")), "cada pestaña escribió su archivo por ACP en la carpeta abierta")
	var refs: Array = []
	OS.execute("git", ["-C", _project, "for-each-ref", "--format=%(refname)", "refs/godot-agent/turns/"], refs)
	_check(str(refs).contains("turns/app-s1/") and not str(refs).contains("turns/s1/"), "las fotos de la app no usan las claves de las pestañas del editor (s1, s2…)")
	var data := _turn_data(app._sessions["s1"].model)
	_check(not data.is_empty() and data.get("files", []).map(func(file: Dictionary) -> String: return str(file.path)) == ["a.gd"], "el turno de s1 ofrece Ver cambios y Deshacer turno, con a.gd")
	if not data.is_empty():
		app._on_dock_action(SessionController.ACTION_TURN_CHANGES, data)
		await process_frame
		_check(app._turn_changes.dialog.visible, "Ver cambios abre el diálogo")
		app._turn_changes.dialog.hide()
		_check(await app._turn_changes.changed_after(data) == PackedStringArray(), "nada del turno cambió después")
		FileAccess.open(_project.path_join("a.gd"), FileAccess.WRITE).store_string("# later\n")
		_check(await app._turn_changes.changed_after(data) == PackedStringArray(["a.gd"]), "la confirmación nombra a.gd, que cambió después del turno")
		await app._turn_changes.restore(data)
		_check(not FileAccess.file_exists(_project.path_join("a.gd")), "Deshacer turno saca a.gd")
		_check(FileAccess.file_exists(_project.path_join("b.gd")), "y deja b.gd, que escribió la otra pestaña después (m20-10)")
	app.close_tab(second)
	await process_frame
	_check(app._tabs.ids() == PackedStringArray(["s1"]), "cerrar la segunda deja la primera")
	_check(FileAccess.file_exists(Main.settings_path()), "los ajustes quedaron en su archivo")
	app.queue_free()  # con un agente vivo: _exit_tree lo para y el proceso sale sin caerse
	await process_frame
	print("standalone_check: %d checks, %d fallos" % [_checks, _failures.size()])
	for failure: String in _failures:
		print("  FALLA: " + failure)
	quit(1 if not _failures.is_empty() else 0)


func _turn(app: Control, id: String, file: String) -> void:
	var model = app._sessions[id].model
	var profile := AgentProfile.from_dict({"id": "fake", "display_name": "Fake", "command": OS.get_executable_path(), "args": [
		"--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/standalone_write_%s.json" % file]})
	model.harness_mode = model.HarnessMode.AUTO
	await app._tabs.dock(id).start_with_prompt(profile, "hello")
	for i in 200:
		await create_timer(0.05).timeout
		if i > 20 and not model.is_busy():
			break
	_check(not model.is_busy(), "%s: el turno termina" % id)


## El MCP de un editor, armado como en agent_plugin: confía en el token de la app y le describe las tools.
func _fake_editor() -> McpServer:
	var registry := ToolRegistry.new()
	registry.register(McpTool.create("touch", "edit_files", "Escribe", {"name": {"type": "string"}}, ["name"],
		func(args: Dictionary) -> String:
			_touched.append(args.name)
			return "touched %s" % args.name))
	var save := McpTool.create("save", "edit_files", "Guarda", {"path": {"type": "string"}}, ["path"],
		func(args: Dictionary) -> String:
			_touched.append(args.path)
			return "saved")
	save.write_targets = func(args: Dictionary) -> PackedStringArray: return PackedStringArray([args.path])
	registry.register(save)
	registry.session_authorizer = func(caller: String, _group: String, _title: String, _description: String) -> bool: return caller == McpPublication.APP_CALLER
	var server := McpServer.new()
	server.registry = registry
	server.describer = func(caller: String, tool_name: String, args: Dictionary) -> Dictionary:
		return registry.describe(tool_name, args) if caller == McpPublication.APP_CALLER else {}
	root.add_child(server)
	server.start(0)
	McpPublication.publish(_project, server.url(), server.session_token(McpPublication.APP_CALLER))
	return server


func _post(url: String, token: String, message: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	root.add_child(request)
	request.request(url, ["Content-Type: application/json", "Accept: application/json", "Authorization: Bearer " + token], HTTPClient.METHOD_POST, JSON.stringify(message))
	var response: Array = await request.request_completed
	request.queue_free()
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## Un proyecto git con un commit, para las fotos por turno.
func _make_project() -> String:
	var path := ProjectSettings.globalize_path(PROJECT).trim_suffix("/")
	OS.execute("rm", ["-rf", path])
	DirAccess.make_dir_recursive_absolute(path)
	FileAccess.open(path.path_join("README.md"), FileAccess.WRITE).store_string("check\n")
	for args: Array in [["init", "-q"], ["add", "-A"], ["-c", "user.name=check", "-c", "user.email=check@example.invalid", "commit", "-q", "-m", "init"]]:
		OS.execute("git", ["-C", path] + args)
	return path


func _turn_data(model: Variant) -> Dictionary:
	for entry: ChatEntry in model.entries():
		for action: Dictionary in entry.actions:
			if action.id == SessionController.ACTION_TURN_RESTORE:
				return action.data
	return {}


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
