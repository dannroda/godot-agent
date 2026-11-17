extends "test_case.gd"
## Al agotarse la cuota, elegir otra cuenta o perfil (m6-22): la cuota anotada por cuenta, la lista
## de cuentas y perfiles para «Cambiar de cuenta» (y la cadena de reserva, m6-21) y la sesión de
## Claude Code copiada a la carpeta de la otra cuenta.

const AccountChoices := preload("res://addons/godot_agent/session/agents/account_choices.gd")
const AccountQuotaBook := preload("res://addons/godot_agent/core/account_quota_book.gd")
const AccountSwitchMenu := preload("res://addons/godot_agent/ui/account_switch_menu.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const AgentAdapters := preload("res://addons/godot_agent/session/agents/agent_adapters.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const QuotaMonitor := preload("res://addons/godot_agent/core/quota_monitor.gd")

const TMP := "user://test_account_choices"

var _now: int = 1_000_000


func test_book_records_and_describes() -> void:
	var book := _book()
	assert_eq(book.lookup("claude-code", ""), {}, "sin nada anotado")
	assert_eq(book.describe("claude-code", ""), "", "y sin texto")
	var quota := QuotaMonitor.new()
	book.record("claude-code", "", quota)
	assert_eq(book.lookup("claude-code", ""), {}, "sin datos de cuota no anota")
	quota.observe_windows({"five_hour": {"utilization": 0.62, "resets_at": _now + 7200}}, "")
	book.record("claude-code", "", quota)
	assert_eq(book.describe("claude-code", ""), "62 % used", "lo usado")
	assert_false(book.is_exhausted("claude-code", ""), "no agotada")
	assert_true(book.is_exhausted("claude-code", "", 0.6), "en el umbral de pausa cuenta como agotada (m6-21)")
	assert_false(book.is_exhausted("claude-code", "", 0.9), "debajo del umbral, no")
	quota.state = QuotaMonitor.QuotaState.LIMITED
	quota.limited_until = _now + 7200
	book.record("claude-code", "/c/trabajo", quota)
	assert_true(book.is_exhausted("claude-code", "/c/trabajo"), "agotada, por cuenta")
	assert_eq(book.describe("claude-code", "/c/trabajo"), "exhausted, resets in %s" % QuotaMonitor.format_duration(7200), "agotada y cuándo se libera")
	assert_eq(book.describe("claude-code", ""), "62 % used", "la otra cuenta no cambia")
	_now += 7201
	assert_false(book.is_exhausted("claude-code", "/c/trabajo"), "pasado el reinicio, ya no está agotada")
	assert_eq(book.describe("claude-code", "/c/trabajo"), "quota reset", "y lo dice")


func test_list_same_agent_first() -> void:
	var home := _home()
	var saved_home := OS.get_environment("HOME")
	var saved_config := OS.get_environment("CLAUDE_CONFIG_DIR")
	OS.set_environment("HOME", home)
	OS.unset_environment("CLAUDE_CONFIG_DIR")
	var settings := HarnessSettings.new()
	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
	var other: AgentProfile = AgentProfile.from_dict({"id": "mio", "display_name": "Mío", "command": "mi-agente"})
	settings.save_profiles([other, claude] as Array[AgentProfile])
	var book := _book()
	var limited := QuotaMonitor.new()
	limited.state = QuotaMonitor.QuotaState.LIMITED
	limited.limited_until = _now + 600
	book.record("claude-code", "", limited)

	var choices := AccountChoices.list(settings, claude, book)
	assert_eq(choices.map(func(c: Dictionary) -> String: return "%s|%s" % [c.profile_id, c.account_dir]),
		["claude-code|", "claude-code|" + home.path_join(".claude-profiles/trabajo"), "mio|"], "las cuentas del agente que corre primero, después los otros perfiles")
	assert_eq(choices.map(func(c: Dictionary) -> bool: return c.current), [true, false, false], "la que está en uso")
	assert_eq(choices.map(func(c: Dictionary) -> bool: return c.same_agent), [true, true, false], "mismo agente u otro")
	assert_true(bool(choices[0].exhausted), "la actual, agotada según lo anotado")
	assert_eq(str(choices[1].label), "trabajo · yo@empresa.com", "otra cuenta: nombre y email")
	assert_eq(str(choices[2].label), "Mío", "otro perfil sin cuentas: su nombre")
	assert_eq((choices[1].profile as AgentProfile).resolved_env().get("CLAUDE_CONFIG_DIR"), home.path_join(".claude-profiles/trabajo"), "el perfil listo para lanzar con esa cuenta")
	assert_eq(AccountChoices.next_available(choices).get("account_dir"), home.path_join(".claude-profiles/trabajo"), "la siguiente libre, del mismo agente")
	assert_eq(AccountChoices.resolve(settings, "claude-code", home.path_join(".claude-profiles/trabajo")).resolved_env().get("CLAUDE_CONFIG_DIR"), home.path_join(".claude-profiles/trabajo"), "resolve: perfil y cuenta guardados → perfil a lanzar")
	assert_eq(AccountChoices.resolve(settings, "borrado", ""), null, "resolve: un perfil que ya no está")
	book.record("claude-code", home.path_join(".claude-profiles/trabajo"), limited)
	choices = AccountChoices.list(settings, claude, book)
	assert_eq(AccountChoices.next_available(choices).get("profile_id"), "mio", "si las del agente están agotadas, otro perfil")
	assert_eq(AccountChoices.next_available(choices, true), {}, "o ninguna, si solo valen las del mismo agente")

	var popup := PopupMenu.new()
	AccountSwitchMenu.fill(popup, choices, [{"id": "claude-login", "label": "Claude"}] as Array[Dictionary])
	var texts: PackedStringArray = []
	for i in popup.item_count:
		texts.append(popup.get_item_text(i))
	assert_true(texts.has("~/.claude — exhausted, resets in %s (in use)" % QuotaMonitor.format_duration(600)), "la actual, marcada y agotada (%s)" % ", ".join(texts))
	assert_true(popup.is_item_disabled(popup.get_item_index(AccountSwitchMenu.CHOICE_BASE)), "la actual no se elige")
	assert_true(texts.has("Another agent (new session)"), "los otros agentes, aparte")
	assert_true(texts.has("Sign in with another account · Claude"), "sigue el login con otra cuenta")
	assert_eq(AccountSwitchMenu.choice_of(AccountSwitchMenu.CHOICE_BASE + 2, choices).get("profile_id"), "mio", "el id lleva a la cuenta")
	assert_eq(AccountSwitchMenu.choice_of(0, choices), {}, "un login no es una cuenta")
	popup.free()
	OS.set_environment("HOME", saved_home)
	if not saved_config.is_empty():
		OS.set_environment("CLAUDE_CONFIG_DIR", saved_config)
	_remove_tree(ProjectSettings.globalize_path(TMP))


func test_claude_carries_session() -> void:
	var root := ProjectSettings.globalize_path(TMP)
	_remove_tree(root)
	var from := root.path_join("a")
	var to := root.path_join("b")
	DirAccess.make_dir_recursive_absolute(from.path_join("projects/-x-proj/s1/subagents"))
	_write_text(from.path_join("projects/-x-proj/s1.jsonl"), "{\"n\":1}\n")
	_write_text(from.path_join("projects/-x-proj/s1/subagents/agent-1.jsonl"), "{}\n")
	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE)
	var adapter := AgentAdapters.for_profile(claude.command, claude.args, claude.id)
	assert_true(adapter.carry_session("s1", from, to), "copiada")
	assert_eq(FileAccess.get_file_as_string(to.path_join("projects/-x-proj/s1.jsonl")), "{\"n\":1}\n", "en la misma subcarpeta del proyecto")
	assert_true(FileAccess.file_exists(to.path_join("projects/-x-proj/s1/subagents/agent-1.jsonl")), "con lo de sus subagentes")
	assert_false(adapter.carry_session("otra", from, to), "una sesión que no está: no")
	assert_false(adapter.carry_session("../s1", from, to), "un id que no es un nombre de archivo: no")
	var generic := AgentAdapters.for_profile("mi-agente", PackedStringArray(), "mio")
	assert_false(generic.carry_session("s1", from, to), "un agente que no se sabe dónde guarda: no")

	var at_a: AgentProfile = claude.with_account(from, "CLAUDE_CONFIG_DIR")
	var at_b: AgentProfile = claude.with_account(root.path_join("c"), "CLAUDE_CONFIG_DIR")
	assert_true(AccountChoices.carry_session(at_a, at_b, "s1"), "entre cuentas del mismo perfil")
	var other: AgentProfile = AgentProfile.from_dict({"id": "mio", "command": "claude-code-acp"}).with_account(root.path_join("d"), "CLAUDE_CONFIG_DIR")
	assert_false(AccountChoices.carry_session(at_a, other, "s1"), "a otro perfil, no")
	assert_false(AccountChoices.carry_session(at_a, at_a, "s1"), "a la misma carpeta, no")
	_remove_tree(root)


func _book() -> AccountQuotaBook:
	var book := AccountQuotaBook.new()
	book.path = TMP.path_join("account_quota.json")
	if FileAccess.file_exists(book.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(book.path))
	book.now_provider = func() -> int: return _now
	return book


func _home() -> String:
	var home := ProjectSettings.globalize_path(TMP).path_join("home")
	_remove_tree(home)
	for dir: String in [".claude", ".claude-profiles/trabajo"]:
		DirAccess.make_dir_recursive_absolute(home.path_join(dir))
	_write_text(home.path_join(".claude-profiles/trabajo/.claude.json"), JSON.stringify({"oauthAccount": {"emailAddress": "yo@empresa.com"}}))
	return home


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	for file: String in access.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for dir: String in access.get_directories():
		_remove_tree(path.path_join(dir))
	DirAccess.remove_absolute(path)
