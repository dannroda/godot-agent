extends "test_case.gd"
## MCP servers del proyecto con aprobación por máquina (m13-31): qué se aprueba de un server, el
## aviso de los que no se pasaron, «Aprobar…» y la lista de Settings (qué aprueba guardar y qué no).

const ExternalMcpServers := preload("res://addons/godot_agent/mcp/external_mcp_servers.gd")
const MachineApproval := preload("res://addons/godot_agent/core/machine_approval.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const McpServersPage := preload("res://addons/godot_agent/ui/settings/mcp_servers_page.gd")

const PROJECT := "/p/game"


func _server(name: String, command: String, args: Array = [], env: Dictionary = {}) -> Dictionary:
	var entry := ExternalMcpServers.make(name)
	entry.command = command
	entry.args = args
	entry.env = env
	return entry


func test_approval_definition() -> void:
	var base := _server("blender", "uvx", ["blender-mcp"], {"B": "$TOKEN", "A": "1"})
	var key := ExternalMcpServers.approval_key(PROJECT, base)
	var renamed := base.duplicate(true)
	renamed.name = "other"
	renamed.enabled = false
	assert_eq(ExternalMcpServers.approval_key(PROJECT, renamed), key, "el nombre y el interruptor no cuentan")
	var reordered := _server("blender", "uvx", ["blender-mcp"], {"A": "1", "B": "$TOKEN"})
	assert_eq(ExternalMcpServers.approval_key(PROJECT, reordered), key, "el orden de env no cuenta")
	for change: Array in [["command", "npx"], ["args", ["blender-mcp", "--evil"]], ["env", {"A": "2", "B": "$TOKEN"}], ["transport", "http"], ["url", "https://x"], ["headers", {"X": "1"}]]:
		var changed := base.duplicate(true)
		changed[change[0]] = change[1]
		assert_true(ExternalMcpServers.approval_key(PROJECT, changed) != key, "cambiar %s pide de nuevo" % change[0])
	assert_true(ExternalMcpServers.approval_key("/p/other", base) != key, "otro proyecto, otra clave")
	assert_false(ExternalMcpServers.approval_text(base).contains(OS.get_environment("HOME")) and not OS.get_environment("HOME").is_empty(), "las variables quedan como $VAR")
	assert_eq(ExternalMcpServers.approval_description(base), "uvx blender-mcp\nB=$TOKEN\nA=1", "el diálogo muestra el comando y el env")
	var http := ExternalMcpServers.normalize({"name": "s", "transport": "http", "url": "https://mcp.example.com", "headers": {"Authorization": "Bearer $T"}})
	assert_eq(ExternalMcpServers.approval_description(http), "https://mcp.example.com\nAuthorization: Bearer $T", "http: la URL y los headers")


func test_held_notice() -> void:
	var held := [{"name": "a", "command": "uvx a", "key": "k1"}, {"name": "b", "command": "uvx b", "key": "k2"}]
	var first := SessionController.held_servers_notice(held, true)
	assert_true(str(first.text).contains("«a», «b»") and str(first.text).contains("project_config.tres") and str(first.text).contains("approved"), "la primera vez dice cuáles y por qué: %s" % first.text)
	var later := SessionController.held_servers_notice(held, false)
	assert_true(str(later.text).length() < str(first.text).length() and str(later.text).contains("«a», «b»"), "después, una línea con los nombres")
	assert_eq(first.actions.size(), 3, "uno por server y uno para todos")
	assert_eq(first.actions[0].data, MachineApproval.request(MachineApproval.KIND_MCP, [held[0]]), "«Aprobar «a»…» lleva solo a")
	assert_eq((first.actions[2].data.items as Array).size(), 2, "«Approve all» lleva los dos")
	assert_true(str(first.actions[2].label).contains("2"), first.actions[2].label)
	assert_eq(SessionController.held_servers_notice([held[0]], true).actions.size(), 1, "con uno solo, sin «todos»")


func test_approve_on_machine() -> void:
	var settings := HarnessSettings.new()
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), PROJECT)
	controller.approve_command = settings.approve_command
	controller.approve_on_machine(MachineApproval.request(MachineApproval.KIND_MCP, [{"name": "a", "command": "uvx a", "key": "k1"}, {"name": "b", "command": "uvx b", "key": "k2"}]))
	assert_true(settings.is_command_approved("k1") and settings.is_command_approved("k2"), "aprueba todos los del pedido")
	var last: ChatEntry = controller.model.entries()[-1]
	assert_true(last.text.contains("«a», «b»") and last.text.contains("next session"), "avisa que entran en la próxima sesión: %s" % last.text)
	controller.approve_on_machine(MachineApproval.request(MachineApproval.KIND_CHECK, [{"name": "c", "command": "x", "key": ""}]))
	assert_eq(controller.model.entries()[-1], last, "sin clave no aprueba ni avisa")


func test_settings_page_approval() -> void:
	var settings := HarnessSettings.new()
	var theirs := _server("theirs", "uvx", ["theirs"])
	var trusted := _server("trusted", "uvx", ["trusted"])
	settings.approve_command(ExternalMcpServers.approval_key(PROJECT, trusted))
	var page := McpServersPage.new()
	page.load_from([_server("mine-user", "uvx", ["u"])], [theirs, trusted], settings.is_command_approved, PROJECT)
	var servers: Array = page.get(&"_servers")
	assert_true(page.needs_approval(servers[0]), "uno del archivo sin aprobar muestra el aviso")
	assert_false(page.needs_approval(servers[1]), "uno aprobado no")
	assert_false(page.needs_approval(servers[2]), "los del usuario no cambian")
	assert_eq(Array(page.keys_to_approve()), [], "guardar sin tocar nada no aprueba lo que vino en el archivo")
	servers[0]["_allow"] = true
	assert_eq(Array(page.keys_to_approve()), [ExternalMcpServers.approval_key(PROJECT, theirs)], "marcado, sí")
	assert_false(page.project_servers()[0].has("_allow"), "la marca no se guarda en el proyecto")
	servers[0]["_allow"] = false
	servers[1].args = ["trusted", "--more"]
	assert_eq(Array(page.keys_to_approve()), [ExternalMcpServers.approval_key(PROJECT, servers[1])], "editado acá, se aprueba")
	assert_eq(page.import_mcp_json(JSON.stringify({"mcpServers": {"imported": {"command": "npx", "args": ["x"]}}})), 1, "importa uno")
	servers = page.get(&"_servers")
	assert_true(page.needs_approval(servers[-1]), "uno importado de .mcp.json también pide aprobación")
	assert_false(Array(page.keys_to_approve()).has(ExternalMcpServers.approval_key(PROJECT, servers[-1])), "importarlo no lo aprueba")
	page.free()
