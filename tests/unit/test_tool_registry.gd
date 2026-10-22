extends "test_case.gd"
## ToolRegistry y McpTool (spec §5–6): validación, política, truncado, imágenes y errores.

const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")


func _registry() -> ToolRegistry:
	var registry := ToolRegistry.new()
	registry.agent_log = AgentLog.new()
	registry.register(McpTool.create("echo", "read", "Repite", {"text": {"type": "string"}, "times": {"type": "integer"}, "mode": {"type": "string", "enum": ["a", "b"]}}, ["text"],
		func(args: Dictionary) -> String: return str(args.text).repeat(McpTool.int_arg(args, "times", 1))))
	registry.register(McpTool.create("broken", "read", "Devuelve null", {}, [], func(_args: Dictionary) -> Variant: return null))
	registry.register(McpTool.create("picture", "diagnostics", "Imagen grande", {}, [], func(_args: Dictionary) -> Image:
		var image := Image.create(3000, 1000, false, Image.FORMAT_RGB8)
		image.fill(Color.BLUE)
		return image))
	return registry


func test_list() -> void:
	var tools := _registry().list()
	assert_eq(tools.size(), 3, "tres tools")
	assert_eq(tools[0].name, "echo", "orden de registro")
	assert_eq(tools[0].inputSchema.required, ["text"], "required en el schema")


func test_validation() -> void:
	var registry := _registry()
	var missing: Dictionary = await registry.call_tool("echo", {})
	assert_true(missing.isError and str(missing.content[0].text).contains("text"), "falta required")
	var wrong_type: Dictionary = await registry.call_tool("echo", {"text": 3})
	assert_true(wrong_type.isError, "tipo incorrecto")
	var unknown_arg: Dictionary = await registry.call_tool("echo", {"text": "a", "otro": 1})
	assert_true(unknown_arg.isError and str(unknown_arg.content[0].text).contains("otro"), "argumento desconocido")
	var bad_enum: Dictionary = await registry.call_tool("echo", {"text": "a", "mode": "z"})
	assert_true(bad_enum.isError, "enum")
	var ok: Dictionary = await registry.call_tool("echo", {"text": "ab", "times": 2.0})
	assert_false(ok.isError, "float entero vale como integer")
	assert_eq(ok.content[0].text, "abab", "resultado")
	var unknown_tool: Dictionary = await registry.call_tool("nada", {})
	assert_true(unknown_tool.isError, "tool desconocida")
	var broken: Dictionary = await registry.call_tool("broken", {})
	assert_true(broken.isError, "handler sin resultado → error")


func test_authorizer() -> void:
	var registry := _registry()
	var asked: Array = []
	registry.authorizer = func(group: String, title: String, _description: String) -> bool:
		asked.append([group, title])
		await (Engine.get_main_loop() as SceneTree).process_frame
		return group != "read"
	var denied: Dictionary = await registry.call_tool("echo", {"text": "x"})
	assert_true(denied.isError and str(denied.content[0].text).contains("denied"), "denegado")
	assert_eq(asked[0], ["read", "godot.echo"], "pregunta con grupo y nombre")
	var allowed: Dictionary = await registry.call_tool("picture", {})
	assert_false(allowed.isError, "permitido")


func test_limits() -> void:
	var registry := _registry()
	registry.max_output_chars = 50
	var long: Dictionary = await registry.call_tool("echo", {"text": "x", "times": 500})
	var text := str(long.content[0].text)
	assert_true(text.begins_with("x".repeat(50)) and text.contains("truncated"), "texto truncado con aviso")
	registry.max_image_side = 300
	var picture: Dictionary = await registry.call_tool("picture", {})
	var image := Image.new()
	image.load_png_from_buffer(Marshalls.base64_to_raw(picture.content[0].data))
	assert_eq(image.get_size(), Vector2i(300, 100), "imagen reescalada")


func test_log() -> void:
	var registry := _registry()
	await registry.call_tool("echo", {"text": "hola"})
	var entries := registry.agent_log.entries()
	assert_eq(entries.size(), 1, "una entrada")
	assert_eq(entries[0].channel, AgentLog.CH_MCP, "canal mcp")
	assert_true(str(entries[0].message).contains("godot.echo") and str(entries[0].message).contains("ms"), "nombre y duración")


func test_secret_redaction() -> void:
	var log := AgentLog.new()
	log.add_secret("abcdef0123456789")
	var entry := log.add(AgentLog.CH_ACP, "token abcdef0123456789", "{\"v\":\"Bearer abcdef0123456789\"}")
	assert_false(str(entry.message).contains("abcdef0123456789"), "mensaje sin el secreto")
	assert_false(str(entry.raw).contains("abcdef0123456789"), "raw sin el secreto")
