extends SceneTree
## m20-04: la app aparte (addons/godot_agent/standalone/main.tscn) fuera del editor, con el agente falso.
## Uso: XDG_DATA_HOME=<carpeta temporal> godot --headless --path . --script tests/standalone_check.gd
## (sin XDG_DATA_HOME guarda en los datos del editor del usuario). Sale con 1 si algo falla.

const EditorContext := preload("res://addons/godot_agent/ui/editor_context.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const Main := preload("res://addons/godot_agent/standalone/main.gd")
const OUT := "res://tests/tmp/standalone"

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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT.path_join("a.gd")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT.path_join("b.gd")))
	var app: Control = load("res://addons/godot_agent/standalone/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(EditorContext.project_path() == ProjectSettings.globalize_path("res://").trim_suffix("/"), "sin --project, la carpeta es res://")
	_check(app._tabs.ids() == PackedStringArray(["s1"]), "arranca con una pestaña")
	app._open_settings()
	await process_frame
	_check(app._settings_dialog.visible, "los ajustes se abren")
	_check(not root.gui_embed_subwindows, "diálogos y menús en ventanas del sistema, no embebidos")
	app._settings_dialog.hide()
	var broker = app._sessions["s1"].controller.permissions
	_check(not broker._read_only_reason().contains("godot.") and not broker._godot_window_reason("x").contains("godot."), "sin MCP del editor, los rechazos no nombran tools godot.*")
	_check(app._sessions["s1"].controller._note_for_agent.contains("godot.* tools are not available"), "el agente sabe que no tiene las tools del editor")
	var second: String = app.open_tab()
	_check(app._tabs.ids().size() == 2, "una segunda pestaña")
	await _turn(app, "s1", "a")
	await _turn(app, second, "b")
	_check(FileAccess.file_exists(OUT.path_join("a.gd")) and FileAccess.file_exists(OUT.path_join("b.gd")), "cada pestaña escribió su archivo por ACP")
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


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
