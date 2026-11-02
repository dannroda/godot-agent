extends "test_case.gd"
## Una cuenta por pestaña para cualquier agente (m17-12): carpetas de configuración en la variable que
## dice el adaptador o el perfil, el historial que recuerda la cuenta y las listas de Editor Settings.

const AgentAccounts := preload("res://addons/godot_agent/session/agents/agent_accounts.gd")
const AgentAdapters := preload("res://addons/godot_agent/session/agents/agent_adapters.gd")
const AgentAdapter := preload("res://addons/godot_agent/session/agents/agent_adapter.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")

const TMP_HOME := "user://test_agent_accounts_home"


func test_variables_by_agent() -> void:
	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
	var antigravity: AgentProfile = AgentProfile.from_dict({"id": "antigravity", "display_name": "Google Antigravity", "command": "/x/agy_acp_server.par"})
	var codex: AgentProfile = AgentProfile.from_dict({"id": "codex", "display_name": "Codex", "command": "npx", "args": ["@agentclientprotocol/codex-acp"]})
	var other: AgentProfile = AgentProfile.from_dict({"id": "mio", "display_name": "Mío", "command": "mi-agente"})
	var custom: AgentProfile = AgentProfile.from_dict({"id": "mio2", "display_name": "Mío", "command": "mi-agente", "account_variable": "MI_AGENTE_HOME"})
	var found: Array = []
	for profile: AgentProfile in [claude, antigravity, codex, other, custom]:
		found.append(AgentAccounts.variable_for(profile, AgentAdapters.for_profile(profile.command, profile.args, profile.id)))
	assert_eq(found, ["CLAUDE_CONFIG_DIR", "GEMINI_HOME", "CODEX_HOME", "", "MI_AGENTE_HOME"], "la variable de cada agente; uno desconocido, la de su perfil")
	assert_eq(custom.to_dict().get("account_variable"), "MI_AGENTE_HOME", "la variable se guarda con el perfil")
	assert_false(claude.to_dict().has("account_variable"), "sin variable propia, no se guarda")


func test_profile_account_override() -> void:
	var profile: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE.merged({"env": {"CLAUDE_CONFIG_DIR": "/a", "DEBUG": "1"}}))
	var other: AgentProfile = profile.with_account("/home/ana/.claude-profiles/trabajo", "CLAUDE_CONFIG_DIR")
	assert_eq(other.resolved_env(), {"CLAUDE_CONFIG_DIR": "/home/ana/.claude-profiles/trabajo", "DEBUG": "1"}, "la cuenta pisa la carpeta del perfil")
	assert_eq(profile.resolved_env().get("CLAUDE_CONFIG_DIR"), "/a", "el perfil original no cambia")
	assert_eq(other.label(), "Claude Code · trabajo", "el chip dice qué cuenta")
	assert_eq(profile.label(), "Claude Code", "sin cuenta, el nombre solo")
	assert_false(other.to_dict().has("account_dir"), "la cuenta no se guarda con el perfil")
	assert_eq(other.with_account("", "CLAUDE_CONFIG_DIR").resolved_env().get("CLAUDE_CONFIG_DIR"), "/a", "sin cuenta vuelve a la del perfil")
	var gemini: AgentProfile = AgentProfile.from_dict({"id": "agy", "display_name": "Antigravity", "command": "agy"}).with_account("/g/trabajo", "GEMINI_HOME")
	assert_eq(gemini.resolved_env(), {"GEMINI_HOME": "/g/trabajo"}, "otro agente, otra variable")


func test_accounts_on_disk() -> void:
	var home := ProjectSettings.globalize_path(TMP_HOME)
	_remove_tree(home)
	for dir: String in [".claude", ".claude-profiles/personal", ".claude-profiles/trabajo", ".gemini", ".gemini-profiles/trabajo"]:
		DirAccess.make_dir_recursive_absolute(home.path_join(dir))
	_write(home.path_join(".claude.json"), {"oauthAccount": {"emailAddress": "yo@casa.com"}})
	_write(home.path_join(".claude-profiles/personal/.claude.json"), {"oauthAccount": {"emailAddress": "yo@casa.com"}})
	_write(home.path_join(".claude-profiles/trabajo/.claude.json"), {"oauthAccount": {"emailAddress": "yo@empresa.com"}})
	var saved_home := OS.get_environment("HOME")
	var saved_config := OS.get_environment("CLAUDE_CONFIG_DIR")
	OS.set_environment("HOME", home)
	OS.unset_environment("CLAUDE_CONFIG_DIR")

	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
	var adapter: AgentAdapter = AgentAdapters.for_profile(claude.command, claude.args, claude.id)
	assert_eq(AgentAccounts.normalize("~/.claude-profiles/trabajo/"), home.path_join(".claude-profiles/trabajo"), "~/ y la barra final")
	var base := AgentAccounts.base_dir(claude, adapter, "CLAUDE_CONFIG_DIR")
	assert_eq(base, home.path_join(".claude"), "sin variable, la carpeta por defecto del agente")
	var accounts := AgentAccounts.list(base, adapter.default_account_dir(), PackedStringArray(["/otra/cuenta", home.path_join(".claude-profiles/trabajo")]), adapter)
	assert_eq(accounts.map(func(a: Dictionary) -> String: return a.dir), [home.path_join(".claude"), home.path_join(".claude-profiles/personal"), home.path_join(".claude-profiles/trabajo"), "/otra/cuenta"], "la del perfil, las de ~/.claude-profiles y las agregadas, sin repetir")
	assert_eq(accounts.map(func(a: Dictionary) -> String: return AgentAccounts.label_of(a)), ["~/.claude · yo@casa.com", "personal · yo@casa.com", "trabajo · yo@empresa.com", "cuenta"], "nombre y email")

	var agy: AgentProfile = AgentProfile.from_dict({"id": "agy", "display_name": "Antigravity", "command": "/x/agy_acp_server.par"})
	var agy_adapter: AgentAdapter = AgentAdapters.for_profile(agy.command, agy.args, agy.id)
	var agy_accounts := AgentAccounts.list(AgentAccounts.base_dir(agy, agy_adapter, "GEMINI_HOME"), agy_adapter.default_account_dir(), PackedStringArray(), agy_adapter)
	assert_eq(agy_accounts.map(func(a: Dictionary) -> String: return a.name), ["~/.gemini", "trabajo"], "la misma regla para Antigravity: ~/.gemini y ~/.gemini-profiles")

	var unknown: AgentProfile = AgentProfile.from_dict({"id": "mio", "command": "mi-agente", "account_variable": "MI_AGENTE_HOME"})
	var generic := AgentAdapter.new()
	var own := AgentAccounts.list(AgentAccounts.base_dir(unknown, generic, "MI_AGENTE_HOME"), "", PackedStringArray(["/x/cuenta2"]), generic)
	assert_eq(own.map(func(a: Dictionary) -> String: return a.dir), ["", "/x/cuenta2"], "sin carpeta por defecto: la del agente (vacía) y las agregadas")

	# Windows: sin HOME, la carpeta del usuario es USERPROFILE y el email de ~/.claude sigue saliendo.
	var saved_profile := OS.get_environment("USERPROFILE")
	OS.unset_environment("HOME")
	OS.set_environment("USERPROFILE", home)
	assert_eq(adapter.account_email(home.path_join(".claude")), "yo@casa.com", "sin HOME, el email de ~/.claude sale de USERPROFILE")
	OS.set_environment("HOME", home)
	if saved_profile.is_empty():
		OS.unset_environment("USERPROFILE")
	else:
		OS.set_environment("USERPROFILE", saved_profile)

	OS.set_environment("CLAUDE_CONFIG_DIR", home.path_join(".claude-profiles/personal"))
	assert_eq(AgentAccounts.base_dir(claude, adapter, "CLAUDE_CONFIG_DIR"), home.path_join(".claude-profiles/personal"), "con la variable del editor, esa es la del perfil")

	OS.set_environment("HOME", saved_home)
	if saved_config.is_empty():
		OS.unset_environment("CLAUDE_CONFIG_DIR")
	else:
		OS.set_environment("CLAUDE_CONFIG_DIR", saved_config)
	_remove_tree(home)


## Elegir, aplicar y armar el menú (lo que hace el dock): una carpeta borrada no se aplica y elegir
## la del perfil no deja override.
func test_apply_choice_menu() -> void:
	var dir := ProjectSettings.globalize_path(TMP_HOME + "_work")
	DirAccess.make_dir_recursive_absolute(dir)
	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE.merged({"env": {"CLAUDE_CONFIG_DIR": "/base/claude"}}))
	assert_eq(AgentAccounts.apply(claude, dir).resolved_env().get("CLAUDE_CONFIG_DIR"), dir, "una carpeta que existe se aplica")
	assert_eq(AgentAccounts.apply(claude, dir + "-borrada").account_dir, "", "una carpeta borrada no: queda la del perfil")
	assert_eq(AgentAccounts.apply(AgentProfile.from_dict({"id": "x", "command": "otro"}), dir).account_dir, "", "un agente sin variable no lleva cuenta")
	assert_eq(AgentAccounts.choice(claude, "/base/claude/"), "", "elegir la del perfil no guarda override")
	assert_eq(AgentAccounts.choice(claude, dir), dir, "elegir otra la guarda")
	var menu := AgentAccounts.menu(AgentAccounts.apply(claude, dir), PackedStringArray())
	assert_eq([menu.variable, menu.current], ["CLAUDE_CONFIG_DIR", dir], "el menú sabe la variable y la cuenta actual")
	var dirs: Array = (menu.accounts as Array).map(func(a: Dictionary) -> String: return a.dir)
	assert_true(dirs[0] == "/base/claude" and dirs.has(dir), "la del perfil primero y la actual en la lista: %s" % [dirs])
	assert_eq(AgentAccounts.menu(AgentProfile.from_dict({"id": "x", "command": "otro"}), PackedStringArray()).variable, "", "sin variable, sin cuentas")
	assert_eq(AgentAccounts.normalize("C:\\Users\\ana\\.claude\\"), "C:/Users/ana/.claude", "barras de Windows")
	DirAccess.remove_absolute(dir)


## Borrar una sesión del historial: solo se le pide al agente si es suya (mismo perfil y cuenta).
func test_owns_session() -> void:
	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
	var work: AgentProfile = claude.with_account("/c/trabajo", "CLAUDE_CONFIG_DIR")
	assert_true(SessionController.owns_session(claude, "claude-code", ""), "mismo perfil, sin cuenta")
	assert_true(SessionController.owns_session(work, "claude-code", "/c/trabajo"), "misma cuenta")
	assert_false(SessionController.owns_session(work, "claude-code", ""), "la sesión es de la cuenta del perfil, el agente corre con otra")
	assert_false(SessionController.owns_session(claude, "claude-code", "/c/trabajo"), "la sesión es de otra cuenta")
	assert_false(SessionController.owns_session(claude, "otro", ""), "otro agente")


## Las sesiones que lista el agente traen su cuenta, para reabrirlas y borrarlas con la misma.
func test_agent_listed_session_account() -> void:
	var work: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE).with_account("/c/trabajo", "CLAUDE_CONFIG_DIR")
	var item := SessionController.SessionCatalog.normalize_agent_session({"sessionId": "r1", "cwd": "/tmp"}, work)
	assert_eq([item.account, item.agent], ["/c/trabajo", "Claude Code · trabajo"], "cuenta y nombre con la cuenta")


func test_last_account_per_agent() -> void:
	var settings := HarnessSettings.new()
	settings.set_last_account("claude-code", "/c/trabajo")
	settings.set_last_account("agy", "/g/trabajo")
	assert_eq([settings.last_account("claude-code"), settings.last_account("agy"), settings.last_account("otro")], ["/c/trabajo", "/g/trabajo", ""], "la última cuenta, por agente")
	settings.add_account("GEMINI_HOME", "/g/extra")
	settings.add_account("GEMINI_HOME", "/g/extra")
	assert_eq(settings.accounts("GEMINI_HOME"), PackedStringArray(["/g/extra"]), "las agregadas, por variable y sin repetir")
	assert_true(settings.accounts("CLAUDE_CONFIG_DIR").is_empty(), "no se mezclan entre agentes")


func test_history_keeps_account() -> void:
	var history := SessionHistory.new()
	history.begin("s", "claude-code", "Claude Code · trabajo", "/tmp", {}, "/home/ana/.claude-profiles/trabajo")
	assert_eq(SessionHistory.summary_of(history.get(&"_meta")).get("account"), "/home/ana/.claude-profiles/trabajo", "el resumen del historial guarda la cuenta")
	history.begin("s2", "claude-code", "Claude Code", "/tmp")
	assert_eq(SessionHistory.summary_of(history.get(&"_meta")).get("account"), "", "sin cuenta elegida, vacía")


## Las listas eran texto JSON hasta 0.1.15: se leen igual y se guardan como Array.
func test_lists_as_arrays() -> void:
	var settings := HarnessSettings.new()
	settings.set_value(HarnessSettings.KEY_PROFILES, JSON.stringify([AgentProfile.CLAUDE_CODE]))
	assert_eq(settings.profiles().size(), 1, "lee el JSON viejo")
	settings.save_profiles(settings.profiles())
	assert_true(settings.get_value(HarnessSettings.KEY_PROFILES) is Array, "guarda un Array")
	assert_eq(settings.profiles()[0].id, "claude-code", "y lo vuelve a leer")
	settings.save_mcp_servers([{"name": "x", "command": "y"}])
	assert_true(settings.get_value(HarnessSettings.KEY_MCP_SERVERS) is Array, "MCP servers como Array")
	settings.save_llm_profiles(settings.llm_profiles())
	assert_true(settings.get_value(HarnessSettings.KEY_COMPLETION_LLM_PROFILES) is Array, "perfiles LLM como Array")
	settings.set_value(HarnessSettings.KEY_PROFILES, "no es json")
	assert_true(settings.profiles().is_empty(), "un texto roto no rompe")


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for name: String in dir.get_directories():
		_remove_tree(path.path_join(name))
	for name: String in dir.get_files():
		dir.remove(name)
	DirAccess.remove_absolute(path)
