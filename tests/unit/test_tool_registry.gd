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


## tools/list compacto (D56): núcleo tipado más methods y run para las extendidas.
func _compact_registry() -> ToolRegistry:
	var registry := _registry()
	registry.compact = true
	registry.mark_extended(PackedStringArray(["picture"]))
	registry.register(McpTool.create("paint", "edit_scene", "Pinta celdas. Detalle largo que no va en la lista.", {"cells": {"type": "array"}, "layer": {"type": "string"}}, ["layer"],
		func(args: Dictionary) -> String: return "pintado %s" % args.layer))
	registry.mark_extended(PackedStringArray(["paint"]))
	return registry


func test_compact_list() -> void:
	var registry := _compact_registry()
	var names: Array = registry.list().map(func(tool: Dictionary) -> String: return tool.name)
	assert_eq(names, ["echo", "broken", "methods", "run"], "sin las extendidas, con methods y run")
	assert_true(registry.has_tool("run") and registry.has_tool("methods") and registry.has_tool("paint"), "has_tool")
	registry.compact = false
	assert_eq(registry.list().size(), 4, "sin compact, todas y sin methods/run")


func test_methods() -> void:
	var registry := _compact_registry()
	var listed: Dictionary = await registry.call_tool("methods", {})
	var text: String = listed.content[0].text
	assert_true(text.contains("- picture(): Imagen grande") and text.contains("- paint(cells?, layer): Pinta celdas.") and not text.contains("Detalle largo"), "una línea por método " + text)
	assert_false(text.contains("echo"), "el núcleo no se repite")
	var filtered: Dictionary = await registry.call_tool("methods", {"query": "celdas"})
	assert_true(str(filtered.content[0].text).contains("paint") and not str(filtered.content[0].text).contains("picture"), "filtro")
	var detail: Dictionary = await registry.call_tool("methods", {"method": "paint"})
	assert_true(str(detail.content[0].text).contains("Detalle largo") and str(detail.content[0].text).contains("\"required\":[\"layer\"]") and str(detail.content[0].text).contains("edit_scene"), "detalle con schema y grupo")
	var missing: Dictionary = await registry.call_tool("methods", {"method": "nada"})
	assert_true(missing.isError, "método inexistente")


func test_run() -> void:
	var registry := _compact_registry()
	var asked: Array = []
	registry.authorizer = func(group: String, title: String, _description: String) -> bool:
		asked.append([group, title])
		return true
	var ran: Dictionary = await registry.call_tool("run", {"method": "paint", "params": {"layer": "suelo"}})
	assert_false(ran.isError, "corre el método")
	assert_eq(ran.content[0].text, "pintado suelo", "resultado del método")
	assert_eq(asked, [["edit_scene", "godot.paint"]], "permiso con el grupo del método, una sola vez")
	var invalid: Dictionary = await registry.call_tool("run", {"method": "paint", "params": {}})
	assert_true(invalid.isError and str(invalid.content[0].text).contains("layer"), "valida los params del método")
	var unknown: Dictionary = await registry.call_tool("run", {"method": "volar"})
	assert_true(unknown.isError and str(unknown.content[0].text).contains("godot.methods"), "método inexistente")
	var no_method: Dictionary = await registry.call_tool("run", {"params": {}})
	assert_true(no_method.isError and str(no_method.content[0].text).contains("method"), "falta method")
	var direct: Dictionary = await registry.call_tool("paint", {"layer": "x"})
	assert_false(direct.isError, "por su nombre sigue andando")


func test_default_describe() -> void:
	var tool := McpTool.new()
	assert_eq(tool.describe({"node_path": "World/Sun", "value": 1.2}), "node_path: World/Sun\nvalue: 1.2", "una línea por argumento, sin JSON")
	assert_eq(tool.describe({}), "", "sin argumentos")
	assert_true(tool.describe({"text": "x".repeat(300)}).ends_with("…"), "valores largos recortados")
