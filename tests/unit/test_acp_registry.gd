extends "test_case.gd"
## Registro de agentes ACP (m11-12): elegir cómo se instala cada agente, armar su perfil y
## descomprimir los binarios.

const AcpRegistry := preload("res://addons/godot_agent/core/acp_registry.gd")
const AcpRegistryDialog := preload("res://addons/godot_agent/ui/settings/acp_registry_dialog.gd")
const AddonUpdater := preload("res://addons/godot_agent/core/addon_updater.gd")

const DATA := {"version": "1.0.0", "agents": [
	{"id": "kilo", "name": "Kilo", "version": "7.8", "authors": ["Kilo Code"], "distribution": {
		"binary": {"linux-x86_64": {"archive": "https://x/kilo.tar.gz", "cmd": "./kilo", "args": ["acp"]}},
		"npx": {"package": "@kilocode/cli@7.8", "args": ["acp"]}}},
	{"id": "antigravity-acp", "name": "Google Antigravity", "version": "1.4.3", "authors": ["Google LLC"], "distribution": {
		"binary": {"linux-x86_64": {"archive": "https://dl/agy.zip", "cmd": "./agy_acp_server.par", "args": ["--uid="], "sha256": "ABC"}}}},
	{"id": "fast-agent", "name": "fast-agent", "version": "0.10", "authors": [], "distribution": {
		"uvx": {"package": "fast-agent-acp==0.10.1", "args": ["-x"], "env": {"FAST_AGENT_MODEL": "codexplan"}}}},
	{"id": "mac-only", "name": "Mac only", "version": "1", "distribution": {"binary": {"darwin-aarch64": {"archive": "https://x/a.zip", "cmd": "./a"}}}},
	{"id": "../evil", "name": "Evil", "distribution": {"npx": {"package": "evil"}}},
	"basura",
]}


func test_parse_picks_how_to_install() -> void:
	var agents := AcpRegistry.parse(DATA, "linux-x86_64")
	assert_eq(agents.map(func(a: Dictionary) -> String: return a.id), ["fast-agent", "antigravity-acp", "kilo"], "por nombre; sin los de otra plataforma ni ids raros")
	assert_eq(agents[2].kind, "npx", "npx antes que el binario")
	assert_eq(agents[1].kind, "binary", "el binario de esta plataforma")
	assert_eq(agents[1].binary.sha256, "ABC", "con su checksum")
	assert_eq(agents[0].kind, "uvx", "uvx")


func test_profiles() -> void:
	var agents := AcpRegistry.parse(DATA, "linux-x86_64")
	var uvx := AcpRegistry.profile_for(agents[0], "")
	assert_eq([uvx.command, uvx.args, uvx.env], ["uvx", ["fast-agent-acp==0.10.1", "-x"], {"FAST_AGENT_MODEL": "codexplan"}], "uvx con sus args y env")
	var npx := AcpRegistry.profile_for(agents[2], "")
	assert_eq([npx.id, npx.display_name, npx.command, npx.args], ["kilo", "Kilo", "npx", ["-y", "@kilocode/cli@7.8", "acp"]], "npx")
	var binary := AcpRegistry.profile_for(agents[1], "/data/agents/antigravity-acp/1.4.3")
	assert_eq([binary.command, binary.args], ["/data/agents/antigravity-acp/1.4.3/agy_acp_server.par", ["--uid="]], "el binario instalado")
	assert_true(AcpRegistry.platform_key().contains("-"), "plataforma-arquitectura: %s" % AcpRegistry.platform_key())


func test_extract() -> void:
	var root := ProjectSettings.globalize_path("user://unit_tests/acp_registry")
	AddonUpdater._remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)
	var zip := root.path_join("agent.zip")
	var packer := ZIPPacker.new()
	packer.open(zip)
	for name: String in ["agy_acp_server.par", "lib/data.txt", "../evil.txt"]:
		packer.start_file(name)
		packer.write_file("x".to_utf8_buffer())
		packer.close_file()
	packer.close()
	assert_eq(AcpRegistry.extract(zip, "https://dl/agy.zip", root.path_join("zip"), "./agy_acp_server.par"), "", "zip")
	assert_true(FileAccess.file_exists(root.path_join("zip/lib/data.txt")), "con subcarpetas")
	assert_false(FileAccess.file_exists(root.path_join("evil.txt")), "sin rutas que salgan")
	if OS.get_name() != "Windows":
		assert_eq(OS.execute("test", ["-x", root.path_join("zip/agy_acp_server.par")]), 0, "queda ejecutable")
		assert_eq(OS.execute("test", ["-x", root.path_join("zip/lib/data.txt")]), 0, "los demás del zip también (Antigravity lanza otro)")
		OS.execute("tar", ["-czf", root.path_join("kilo.tar.gz"), "-C", root.path_join("zip"), "agy_acp_server.par"])
		assert_eq(AcpRegistry.extract(root.path_join("kilo.tar.gz"), "https://x/kilo-linux.tar.gz", root.path_join("tar"), "./agy_acp_server.par"), "", "tar.gz con el tar del sistema")
		assert_true(FileAccess.file_exists(root.path_join("tar/agy_acp_server.par")), "descomprimido")
	assert_eq(AcpRegistry.extract(zip, "https://x/tool-linux-amd64", root.path_join("raw"), "./tool"), "", "un ejecutable suelto se guarda tal cual")
	assert_true(FileAccess.file_exists(root.path_join("raw/tool")), "con el nombre del comando")
	assert_false(AcpRegistry.extract(zip, "https://dl/agy.zip", root.path_join("zip2"), "./missing").is_empty(), "si falta el comando, error")


func test_dialog_filter() -> void:
	var agents := AcpRegistry.parse(DATA, "linux-x86_64")
	assert_eq(AcpRegistryDialog.filter(agents, "google").map(func(a: Dictionary) -> String: return a.id), ["antigravity-acp"], "por autor")
	assert_eq(AcpRegistryDialog.filter(agents, "").size(), 3, "sin filtro, todos")
	assert_eq(AcpRegistryDialog.filter(agents, "kilo code").size(), 1, "todas las palabras")


## m12-13: el aviso de error ofrece reinstalar solo los binarios que bajó el registro.
func test_is_registry_binary() -> void:
	const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
	assert_true(SessionController.is_registry_binary("/home/u/.local/share/godot/godot_agent/agents/antigravity/1.2/agy"), "binario del registro")
	assert_true(SessionController.is_registry_binary("C:\\Users\\u\\AppData\\Roaming\\Godot\\godot_agent\\agents\\x\\1\\x.exe"), "en Windows")
	assert_false(SessionController.is_registry_binary("npx"), "npx no")


## m12-27: agregados arriba, después los sugeridos y el resto; cómo se instala cada uno.
func test_grouped_and_install_summary() -> void:
	var agents := AcpRegistry.parse(DATA, "linux-x86_64")
	var groups := AcpRegistryDialog.grouped(agents, PackedStringArray(["kilo"]))
	assert_eq(groups.map(func(group: Dictionary) -> String: return group.group), ["added", "suggested", "other"], "en ese orden")
	assert_eq((groups[0].agents as Array).map(func(a: Dictionary) -> String: return a.id), ["kilo"], "el agregado")
	assert_eq((groups[1].agents as Array).map(func(a: Dictionary) -> String: return a.id), ["antigravity-acp"], "Antigravity es sugerido")
	assert_eq(AcpRegistryDialog.grouped(agents, PackedStringArray()).size(), 2, "sin agregados, sin ese grupo")
	assert_eq(AcpRegistryDialog.install_summary(agents[2]), "npx @kilocode/cli@7.8 · Node.js downloads it the first time", "npx")
	var big := agents[1].duplicate(true)
	big.binary.size = 912 * 1024 * 1024
	assert_true(AcpRegistryDialog.install_summary(big).contains("912"), "el tamaño si el registro lo trae: %s" % AcpRegistryDialog.install_summary(big))
	assert_eq(AcpRegistryDialog.install_summary(agents[1]), "program for this platform: the harness downloads it", "sin tamaño")


## m12-28: los sugeridos usan una descripción propia, traducible; el resto, la del registro.
func test_description_of() -> void:
	var agents := AcpRegistry.parse(DATA, "linux-x86_64")
	assert_eq(AcpRegistryDialog.description_of(agents[1]), "Google's coding agent, with Gemini, Claude and GPT models in its plan.", "Antigravity: la propia")
	var other := {"id": "kilo", "name": "Kilo", "description": "Kilo's own text"}
	assert_eq(AcpRegistryDialog.description_of(other), "Kilo's own text", "otro: la del registro")


## Revisión de seguridad (M11): ni el zip ni el `cmd` del registro escriben fuera de la carpeta.
func test_safe_relative_paths() -> void:
	for ok: String in ["agy", "./bin/agy", "dist/agy_acp_server.par"]:
		assert_true(AcpRegistry.is_safe_relative(ok), "vale: %s" % ok)
	for bad: String in ["../x", "a/../../x", "..\\..\\x", "/etc/passwd", "C:\\Windows\\x.exe", "C:/x", ""]:
		assert_false(AcpRegistry.is_safe_relative(bad), "no vale: %s" % bad)
	var data := {"agents": [{"id": "evil-cmd", "name": "Evil", "version": "1", "distribution": {
		"binary": {"linux-x86_64": {"archive": "https://x/a.bin", "cmd": "../../.bashrc"}}}}]}
	assert_true(AcpRegistry.parse(data, "linux-x86_64").is_empty(), "un cmd que sale se descarta")
