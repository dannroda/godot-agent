@tool
extends RefCounted
## m7-44 en el editor: «+» abre una segunda sesión en otra pestaña del dock (sin One-shot), con su
## token del server MCP; un archivo que una sesión escribe en su turno queda fuera del alcance de la
## otra hasta que el turno termina; godot.sessions lo muestra; cerrar la pestaña suelta todo.
## Guarda capturas en `<prefijo>_*.png`.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")

const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/plugin.gd"
const SOURCE := "res://tests/tmp/sessions_source.txt"
const TARGET := "res://tests/tmp/sessions_target.txt"


func run(tree: SceneTree, main_plugin: Object, dock: Control, prefix: String) -> PackedStringArray:
	var failures: PackedStringArray = []
	var tabs: Control = main_plugin.get(&"_tabs")
	var coordinator: Object = main_plugin.get(&"_coordinator")
	var registry: Object = main_plugin.get(&"_registry")
	var server: Object = main_plugin.get(&"_mcp_server")
	var bar: TabBar = tabs.get(&"_bar")
	if bar.tab_count != 1 or bar.get_tab_button_icon(0) != null:
		failures.append("la primera sesión no va sola y sin botón de cerrar")
	(tabs.find_child("NewSessionTabButton", true, false) as Button).pressed.emit()
	(tabs.get(&"_new_menu") as PopupMenu).id_pressed.emit(0)
	await tree.process_frame
	await tree.process_frame
	var ids: PackedStringArray = tabs.call(&"ids")
	if ids.size() != 2 or bar.tab_count != 2 or bar.get_tab_button_icon(1) == null:
		return ["«+» no abrió otra pestaña: %s" % [ids]]
	var second: String = ids[1]
	var second_dock: Control = tabs.call(&"dock", second)
	if not second_dock.visible or dock.visible:
		failures.append("la pestaña nueva no quedó al frente")
	if second_dock.get(&"allow_oneshot") != false:
		failures.append("la segunda sesión ofrece One-shot")
	if coordinator.call(&"sessions") != PackedStringArray(["s1", second]):
		failures.append("sesiones en el coordinador: %s" % [coordinator.call(&"sessions")])
	var second_session: Dictionary = (main_plugin.get(&"_extra_sessions") as Dictionary).get(second, {})
	var entries: Array = main_plugin.call(&"_mcp_servers", second, second_session.get("model"))
	# HTTP lleva el token en el header; el shim stdio (sin agente conectado), en su entorno.
	var token := ""
	if not entries.is_empty() and entries[0].has("headers"):
		token = str(entries[0].headers[0].value).trim_prefix("Bearer ")
	elif not entries.is_empty() and entries[0].has("env"):
		for variable: Dictionary in entries[0].env:
			if variable.name == "GODOT_AGENT_MCP_TOKEN":
				token = str(variable.value)
	if token.is_empty() or token == server.get(&"token"):
		failures.append("la segunda sesión no tiene token propio del server MCP: %s" % [entries])
	await _save_shot(tree, tabs, "%s_two_tabs.png" % prefix)

	# Las dos en Auto: escribir archivos se permite sin tarjeta.
	(main_plugin.get(&"_model") as SessionModel).set_harness_mode(SessionModel.HarnessMode.AUTO)
	(second_session.model as SessionModel).set_harness_mode(SessionModel.HarnessMode.AUTO)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/tmp"))
	var file := FileAccess.open(SOURCE, FileAccess.WRITE)
	file.store_string("hello\n")
	file.close()
	for path: String in [TARGET, TARGET + ".2"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var first: Dictionary = await registry.call(&"call_tool", "copy_file", {"from": SOURCE, "to": TARGET}, "")
	if first.isError:
		failures.append("la primera sesión no pudo copiar: %s" % first.content[0].text)
	var blocked: Dictionary = await registry.call(&"call_tool", "delete_file", {"path": TARGET}, second)
	if not blocked.isError or not str(blocked.content[0].text).contains("being edited by «Session 1»"):
		failures.append("la segunda tocó un archivo de la primera: %s" % blocked.content[0].text)
	var listing: Dictionary = await registry.call(&"call_tool", "sessions", {}, second)
	var text := str(listing.content[0].text)
	if not text.contains("«Session 1»") or not text.contains(TARGET):
		failures.append("godot.sessions no muestra lo que edita la otra: %s" % text)
	var message: Dictionary = await registry.call(&"call_tool", "session_send", {"to": "Session 1", "message": "hi"}, second)
	if not message.isError or not str(message.content[0].text).contains("not connected"):
		failures.append("un mensaje a una sesión sin agente no avisa: %s" % message.content[0].text)
	(main_plugin.get(&"_model") as SessionModel).turn_finished.emit("end_turn")
	var after: Dictionary = await registry.call(&"call_tool", "copy_file", {"from": SOURCE, "to": TARGET + ".2"}, second)
	if after.isError:
		failures.append("al terminar el turno de la primera, la segunda sigue sin poder: %s" % after.content[0].text)
	await _save_shot(tree, tabs, "%s_second.png" % prefix)

	# Renombrar (m7-53): doble clic abre el campo; el nombre vale también para los agentes.
	tabs.call(&"start_rename", second)
	var popup: PopupPanel = tabs.get(&"_rename_popup")
	var edit: LineEdit = tabs.get(&"_rename_edit")
	if not popup.visible or edit.text != "Session 2":
		failures.append("renombrar no abrió el campo con el nombre actual")
	await _save_shot(tree, tabs, "%s_rename.png" % prefix)
	edit.text_submitted.emit("  Level design ")
	await tree.process_frame
	if bar.get_tab_title(1) != "Level design" or coordinator.call(&"label", second) != "Level design":
		failures.append("el nombre no llegó a la pestaña y al coordinador: %s / %s" % [bar.get_tab_title(1), coordinator.call(&"label", second)])
	var renamed: Dictionary = await registry.call(&"call_tool", "sessions", {}, "")
	if not str(renamed.content[0].text).contains("«Level design»"):
		failures.append("godot.sessions no usa el nombre nuevo: %s" % renamed.content[0].text)
	tabs.rename_requested.emit(second, "session 1")
	if coordinator.call(&"label", second) != "Level design":
		failures.append("se aceptó un nombre repetido")
	tabs.rename_requested.emit(second, "")
	if bar.get_tab_title(1) != "Session 2":
		failures.append("un nombre vacío no volvió a «Session 2»: %s" % bar.get_tab_title(1))

	# m11-03: un permiso en la sesión que no está a la vista marca su pestaña hasta que se responde.
	bar.current_tab = 0
	var request := PermissionRequest.new()
	request.title = "Edit main.gd"
	(second_session.model as SessionModel).add_permission(request)
	if not bar.get_tab_title(1).begins_with("⚠ "):
		failures.append("la pestaña que espera un permiso no se marca: %s" % bar.get_tab_title(1))
	await _save_shot(tree, tabs, "%s_waiting.png" % prefix)
	request.cancel()
	if bar.get_tab_title(1).begins_with("⚠ "):
		failures.append("la marca sigue después de responder el permiso")

	# Cada pestaña con su cuenta de Claude Code: elegir otra en la segunda no cambia la de la primera,
	# y lo que depende del agente (Extensiones, el adaptador) toma la de la pestaña activa.
	var settings: Object = main_plugin.get(&"_settings")
	var saved_profiles: Array = settings.call(&"profiles")
	var saved_last: Variant = settings.call(&"get_value", "agents/last_profile", "")
	var saved_account: Variant = settings.call(&"get_value", "agents/last_account", {})
	var saved_accounts: Variant = settings.call(&"get_value", "agents/accounts", {})
	# Sin la cuenta que haya elegido quien corre el test en este editor (se restaura al final).
	settings.call(&"set_value", "agents/last_account", {})
	settings.call(&"set_value", "agents/accounts", {})
	for each_dock: Control in [dock, second_dock]:
		each_dock.set(&"_accounts", {})
	var claude: Array[AgentProfile] = [AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)]
	settings.call(&"save_profiles", claude)
	dock.call(&"_on_profile_selected", 0)
	second_dock.call(&"_on_profile_selected", 0)
	var work := ProjectSettings.globalize_path("res://tests/tmp/claude-work")
	DirAccess.make_dir_recursive_absolute(work)  # una cuenta que no existe no se aplica
	second_dock.call(&"_on_account_selected", work)
	var first_profile: AgentProfile = dock.call(&"selected_profile")
	var second_profile: AgentProfile = second_dock.call(&"selected_profile")
	if first_profile == null or not first_profile.account_dir.is_empty():
		failures.append("elegir cuenta en la segunda cambió la de la primera: %s" % [first_profile.account_dir if first_profile else "sin perfil"])
	if second_profile == null or second_profile.resolved_env().get("CLAUDE_CONFIG_DIR") != work:
		failures.append("la segunda pestaña no lanza con su cuenta: %s" % [second_profile.resolved_env() if second_profile else {}])
	bar.current_tab = 1
	var tab_profile: AgentProfile = main_plugin.call(&"_tab_profile")
	if tab_profile == null or tab_profile.account_dir != work:
		failures.append("Extensiones no toma la cuenta de la pestaña activa: %s" % [tab_profile.account_dir if tab_profile else ""])
	bar.current_tab = 0
	tab_profile = main_plugin.call(&"_tab_profile")
	if tab_profile == null or not tab_profile.account_dir.is_empty():
		failures.append("la primera pestaña da la cuenta de la segunda")
	bar.current_tab = 1
	second_dock.call(&"_show_agent_menu")
	var menu: PopupMenu = second_dock.get(&"_agent_menu")
	var texts: PackedStringArray = []
	for i in menu.item_count:
		texts.append(menu.get_item_text(i))
	if not texts.has("Claude Code account") or not texts.has("Other folder…"):
		failures.append("el menú del agente no ofrece cuentas: %s" % [texts])
	await _save_shot(tree, tabs, "%s_accounts.png" % prefix)
	await tree.process_frame
	if menu.visible:  # el menú es una ventana aparte: se captura la suya
		var image := menu.get_texture().get_image() if menu.get_texture() else null
		if image:
			image.save_png("%s_accounts_menu.png" % prefix)
	menu.hide()
	# Lo mismo con otro agente: Antigravity lleva la cuenta en GEMINI_HOME, y volver a Claude Code en
	# la pestaña recupera la cuenta que tenía.
	var both: Array[AgentProfile] = [AgentProfile.from_dict(AgentProfile.CLAUDE_CODE), AgentProfile.from_dict({"id": "antigravity", "display_name": "Google Antigravity", "command": "/x/antigravity-acp/1.4.3/agy_acp_server.par"})]
	settings.call(&"save_profiles", both)
	second_dock.call(&"_on_profile_selected", 1)
	var gemini_work := ProjectSettings.globalize_path("res://tests/tmp/gemini-work")
	DirAccess.make_dir_recursive_absolute(gemini_work)
	second_dock.call(&"_on_account_selected", gemini_work)
	second_profile = second_dock.call(&"selected_profile")
	if second_profile == null or second_profile.resolved_env().get("GEMINI_HOME") != gemini_work or second_profile.resolved_env().has("CLAUDE_CONFIG_DIR"):
		failures.append("Antigravity no lanza con su cuenta en GEMINI_HOME: %s" % [second_profile.resolved_env() if second_profile else {}])
	second_dock.call(&"_show_agent_menu")
	texts = []
	for i in menu.item_count:
		texts.append(menu.get_item_text(i))
	if not texts.has("Google Antigravity account"):
		failures.append("el menú no ofrece cuentas de Antigravity: %s" % [texts])
	await tree.process_frame
	if menu.visible and menu.get_texture():
		menu.get_texture().get_image().save_png("%s_accounts_menu_antigravity.png" % prefix)
	menu.hide()
	second_dock.call(&"_on_profile_selected", 0)
	second_profile = second_dock.call(&"selected_profile")
	if second_profile == null or second_profile.resolved_env().get("CLAUDE_CONFIG_DIR") != work:
		failures.append("volver a Claude Code perdió la cuenta de la pestaña: %s" % [second_profile.resolved_env() if second_profile else {}])
	bar.current_tab = 0
	settings.call(&"save_profiles", saved_profiles)
	settings.call(&"set_active_profile", str(saved_last))
	settings.call(&"set_value", "agents/last_account", saved_account)
	settings.call(&"set_value", "agents/accounts", saved_accounts)

	# m17-17: con la primera en un turno, «Nueva sesión» y el historial van a otra pestaña, y una
	# sesión que ya está abierta en otra pestaña se elige en lugar de abrirla dos veces.
	var first_model := main_plugin.get(&"_model") as SessionModel
	first_model.set_state(SessionModel.SessionState.PROMPTING)
	await tree.process_frame
	var new_button: Button = dock.get(&"_new_session_button")
	if new_button.disabled or not dock.call(&"_must_open_elsewhere"):
		failures.append("con un turno en curso, «Nueva sesión» sigue bloqueada")
	var originals := dock.get_signal_connection_list(&"open_elsewhere_requested")
	for connection: Dictionary in originals:
		dock.disconnect(&"open_elsewhere_requested", connection.callable)
	var asked: Array[String] = []
	var spy := func(session_id: String) -> void: asked.append(session_id)
	dock.connect(&"open_elsewhere_requested", spy)
	(dock.get(&"_new_menu") as PopupMenu).id_pressed.emit(0)  # NEW_MENU_SESSION
	var items: Array[Dictionary] = [{"id": "otra-sesion"}]
	dock.set(&"_history_items", items)
	dock.call(&"_on_history_selected", 0)
	if asked != ["", "otra-sesion"]:
		failures.append("con la pestaña ocupada, «Nueva sesión» y el historial no van a otra: %s" % [asked])
	dock.disconnect(&"open_elsewhere_requested", spy)
	for connection: Dictionary in originals:
		dock.connect(&"open_elsewhere_requested", connection.callable)
	(second_session.model as SessionModel).session_id = "abierta-en-la-segunda"
	bar.current_tab = 0
	if not (dock.get(&"session_focuser") as Callable).call("abierta-en-la-segunda") or bar.current_tab != 1:
		failures.append("una sesión abierta en otra pestaña no se elige: pestaña %d" % bar.current_tab)
	(second_session.model as SessionModel).session_id = ""
	bar.current_tab = 0
	var before_ids := (tabs.call(&"ids") as PackedStringArray).size()
	main_plugin.call(&"_open_elsewhere", "s1", "no-existe")  # no lanza ningún agente: la sesión no está
	await tree.process_frame
	var after_ids: PackedStringArray = tabs.call(&"ids")
	if after_ids.size() != before_ids + 1 or str(tabs.call(&"active_id")) != after_ids[after_ids.size() - 1]:
		failures.append("abrir en otra pestaña no creó ni eligió la pestaña: %s" % [after_ids])
	else:
		main_plugin.call(&"_close_session_tab", after_ids[after_ids.size() - 1])
		await tree.process_frame
	first_model.set_state(SessionModel.SessionState.DISCONNECTED)
	bar.current_tab = 0

	# Cerrar la pestaña: el coordinador y el server MCP la olvidan.
	bar.tab_button_pressed.emit(1)
	await tree.process_frame
	if (tabs.call(&"ids") as PackedStringArray).size() != 1 or bar.tab_count != 1 or not dock.visible:
		failures.append("cerrar la pestaña no volvió a la primera sola")
	if coordinator.call(&"sessions") != PackedStringArray(["s1"]):
		failures.append("la sesión cerrada sigue en el coordinador")
	if server.call(&"_caller", "Bearer " + token) != null:
		failures.append("el token de la sesión cerrada sigue valiendo")
	for path: String in [SOURCE, TARGET, TARGET + ".2"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	(main_plugin.get(&"_model") as SessionModel).set_harness_mode(SessionModel.HarnessMode.ASK)

	# m11-09: una sesión en una copia aparte (git worktree de este repo, al lado).
	(tabs.get(&"_new_menu") as PopupMenu).id_pressed.emit(1)
	var deadline := Time.get_ticks_msec() + 30000
	while (tabs.call(&"ids") as PackedStringArray).size() < 2 and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	var copy_ids: PackedStringArray = tabs.call(&"ids")
	if copy_ids.size() < 2:
		failures.append("no se abrió la sesión en una copia")
		return failures
	var copy_id := copy_ids[1]
	var copy_session: Dictionary = (main_plugin.get(&"_extra_sessions") as Dictionary).get(copy_id, {})
	var copy: Object = copy_session.get("copy")
	var copy_dir: String = copy.get(&"info").dir if copy else ""
	if copy == null or not DirAccess.dir_exists_absolute(copy_dir) or not str(coordinator.call(&"label", copy_id)).ends_with("(copy)"):
		failures.append("la copia no quedó armada: %s" % copy_dir)
	if (copy_session.controller as Object).get(&"cwd") == ProjectSettings.globalize_path("res://").trim_suffix("/"):
		failures.append("la sesión en una copia trabaja en el proyecto")
	var edit_in_copy: Dictionary = await registry.call(&"call_tool", "delete_file", {"path": TARGET}, copy_id)
	if not edit_in_copy.isError or not str(edit_in_copy.content[0].text).contains("separate copy"):
		failures.append("una tool de edición del editor no se rechaza en la copia: %s" % edit_in_copy.content[0].text)
	var read_in_copy: Dictionary = await registry.call(&"call_tool", "sessions", {}, copy_id)
	if read_in_copy.isError:
		failures.append("en la copia no anda una tool de lectura: %s" % read_in_copy.content[0].text)
	await _save_shot(tree, tabs, "%s_copy.png" % prefix)
	bar.tab_button_pressed.emit(1)
	deadline = Time.get_ticks_msec() + 30000
	while (tabs.call(&"ids") as PackedStringArray).size() > 1 and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	if (tabs.call(&"ids") as PackedStringArray).size() != 1 or DirAccess.dir_exists_absolute(copy_dir):
		failures.append("cerrar una copia sin cambios no la borró: %s" % copy_dir)
	return failures


func _save_shot(tree: SceneTree, control: Control, path: String) -> void:
	await tree.process_frame
	var image := control.get_viewport().get_texture().get_image()
	var rect := Rect2i(control.get_global_rect())
	if rect.size.x > 0 and rect.size.y > 0:
		image.get_region(rect).save_png(path)
