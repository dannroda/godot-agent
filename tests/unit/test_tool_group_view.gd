extends "test_case.gd"
## Contenido de tool calls en el dock (spec §6): imágenes ACP en base64; subagentes plegados.

const ToolGroupView := preload("res://addons/godot_agent/ui/dock/entries/tool_group_view.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")


func test_decode_image() -> void:
	var source := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	source.fill(Color.RED)
	var data := Marshalls.raw_to_base64(source.save_png_to_buffer())
	var image := ToolGroupView.decode_image(data, "image/png")
	assert_true(image != null, "png válido")
	if image:
		assert_eq(image.get_size(), Vector2i(4, 3), "tamaño")
	assert_true(ToolGroupView.decode_image(data, "image/gif") == null, "mime no soportado")
	assert_true(ToolGroupView.decode_image("", "image/png") == null, "sin datos")
	assert_true(ToolGroupView.decode_image("bm8gZXMgdW5hIGltYWdlbg==", "image/png") == null, "datos que no son imagen")


func test_subagent_rows() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	var child_meta := {"claudeCode": {"parentToolUseId": "agent"}}
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "agent", "title": "Buscar usos", "kind": "think", "status": "in_progress",
		"rawInput": {"description": "Buscar usos", "subagent_type": "Explore"}, "_meta": {"claudeCode": {"toolName": "Agent"}},
		"content": [{"type": "content", "content": {"type": "text", "text": "Buscá los usos\nde la pelota"}}]})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "r1", "title": "Read", "status": "completed", "_meta": child_meta})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "g1", "title": "Grep", "status": "in_progress", "_meta": child_meta})
	model.apply_update({"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Sigo buscando."}, "_meta": child_meta})
	var view: Control = ToolGroupView.new()
	view.call(&"setup", model.entries()[0], Color.ORANGE, MarkdownBBCode.new())
	view.set(&"tool_call_lookup", model.tool_call)
	tree.root.add_child(view)
	await tree.process_frame
	var rows: Dictionary = view.get(&"_rows")
	assert_eq(rows.keys(), ["agent"], "cerrado, solo la fila del subagente")
	assert_eq((rows.agent.summary as Label).text, "subagent · Explore", "resumen con el tipo")
	var toggle: Button = rows.agent.toggle
	assert_true((rows.agent.nested as Control).visible, "el subagente tiene su desplegable")
	assert_eq(toggle.text, "▸ 2 subagent tools · Grep", "cantidad y lo que está haciendo")
	assert_true(_has_button_text(rows.agent.extra, "▸ prompt · 2 lines"), "mientras trabaja muestra el prompt")
	toggle.button_pressed = true
	assert_eq(rows.size(), 3, "abierto, las filas de los hijos")
	assert_true((rows.r1.row as Control).get_parent().get_parent() == rows.agent.children, "los hijos van dentro del subagente")
	assert_eq((rows.agent.note as Label).text, "💬 Sigo buscando.", "último texto del subagente")
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "agent", "status": "completed",
		"content": [{"type": "content", "content": {"type": "text", "text": "Hay dos usos."}}]})
	view.call(&"refresh")
	assert_eq(toggle.text, "▾ 2 subagent tools", "terminado, sin actividad")
	assert_true(_has_button_text(rows.agent.extra, "▸ report · 1 line"), "terminado muestra el informe")
	view.queue_free()


## El botón de subagentes del dock lleva a uno: se abre su grupo y su lista de herramientas.
func test_reveal_opens_group_and_subagent() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "agent", "title": "Buscar usos", "kind": "think", "status": "completed",
		"rawInput": {"description": "Buscar usos", "subagent_type": "Explore"}, "_meta": {"claudeCode": {"toolName": "Agent"}}})
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "r1", "title": "Read", "status": "completed",
		"_meta": {"claudeCode": {"parentToolUseId": "agent"}}})
	var group: SessionModel.ChatEntry = model.entries()[0]
	assert_true(model.group_of_call("agent") == group and model.group_of_call("r1") == group, "el subagente y sus tools viven en el grupo")
	assert_true(model.group_of_call("nada") == null, "sin grupo")
	var view: Control = ToolGroupView.new()
	view.call(&"setup", group, Color.ORANGE, MarkdownBBCode.new())
	view.set(&"tool_call_lookup", model.tool_call)
	tree.root.add_child(view)
	await tree.process_frame
	var header: Button = view.get(&"_header")
	header.button_pressed = false
	var block: Control = view.call(&"reveal", "agent")
	var rows: Dictionary = view.get(&"_rows")
	assert_true(header.button_pressed, "abre el grupo")
	assert_true((rows.agent.toggle as Button).button_pressed, "y las herramientas del subagente")
	assert_true(block == rows.agent.block, "devuelve su bloque")
	assert_true(rows.has("r1"), "con sus filas")
	assert_true(view.call(&"reveal", "otro") == null, "un id que no está")
	view.queue_free()


func _has_button_text(root: Node, text: String) -> bool:
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return true
	return false


## m12-17: las tools del editor con nombre para personas, y ninguno más largo que el tope.
func test_short_names_for_people() -> void:
	const ToolCallScript := preload("res://addons/godot_agent/session/tool_call.gd")
	var call := ToolCallScript.new()
	call.title = "mcp__godot__connect_signal"
	assert_eq(ToolGroupView._short_name(call), "Connect signal", "godot.connect_signal")
	call.title = "Read"
	assert_eq(ToolGroupView._short_name(call), "Read", "las del agente quedan")
	call.title = "mcp__godot__set_project_setting_override_feature"
	assert_true((ToolGroupView._short_name(call) as String).length() <= 22, "con tope y «…»")


## Cada tool del editor tiene nombre para personas: validate_physics y validate_tilemap no tenían (m17-07).
func test_every_godot_tool_has_a_name() -> void:
	var dir := "res://addons/godot_agent/mcp/tools"
	var regex := RegEx.create_from_string("McpTool\\.create\\(\"([a-z_0-9]+)\"")
	var missing: PackedStringArray = []
	var count := 0
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		for found: RegExMatch in regex.search_all(FileAccess.get_file_as_string(dir.path_join(file))):
			count += 1
			if not ToolGroupView.GODOT_TOOL_NAMES.has(found.get_string(1)):
				missing.append(found.get_string(1))
	assert_true(count > 50, "encontró las tools (%d)" % count)
	assert_eq(missing, PackedStringArray(), "tools sin nombre")


## m7-55: una fila sin abrir no arma lo que no se ve. La salida plegada no tiene texto hasta que se abre
## (cada Label oculto con la vista previa pesaba ~340 KB), y el bloque del subagente no existe en una
## llamada común.
func test_rows_build_hidden_parts_on_demand() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	model.apply_update({"sessionUpdate": "tool_call", "toolCallId": "b1", "title": "Bash", "status": "completed",
		"content": [{"type": "content", "content": {"type": "text", "text": "línea uno\nlínea dos"}}]})
	var view: Control = ToolGroupView.new()
	view.call(&"setup", model.entries()[0], Color.ORANGE, MarkdownBBCode.new())
	view.set(&"tool_call_lookup", model.tool_call)
	tree.root.add_child(view)
	await tree.process_frame
	var rows: Dictionary = view.get(&"_rows")
	assert_false(rows.b1.has("nested"), "sin bloque de subagente en una llamada común")
	var extra: Node = rows.b1.extra
	var toggle: Button = null
	for node: Node in extra.find_children("*", "Button", true, false):
		if (node as Button).text.begins_with("▸ output"):
			toggle = node
	assert_true(toggle != null, "el toggle de la salida")
	var output: Label = extra.find_children("*", "Label", true, false)[0]
	assert_eq(output.text, "", "plegada, sin texto")
	toggle.button_pressed = true
	assert_eq(output.text, "línea uno\nlínea dos", "al abrirla, la vista previa")
	assert_true(output.visible, "y se ve")
	toggle.button_pressed = false
	assert_false(output.visible, "se vuelve a plegar")
	view.queue_free()
