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
	assert_eq((rows.agent.summary as Label).text, "subagente · Explore", "resumen con el tipo")
	var toggle: Button = rows.agent.toggle
	assert_true((rows.agent.nested as Control).visible, "el subagente tiene su desplegable")
	assert_eq(toggle.text, "▸ 2 herramientas del subagente · Grep", "cantidad y lo que está haciendo")
	assert_true(_has_button_text(rows.agent.extra, "▸ prompt · 2 líneas"), "mientras trabaja muestra el prompt")
	toggle.button_pressed = true
	assert_eq(rows.size(), 3, "abierto, las filas de los hijos")
	assert_true((rows.r1.row as Control).get_parent().get_parent() == rows.agent.children, "los hijos van dentro del subagente")
	assert_eq((rows.agent.note as Label).text, "💬 Sigo buscando.", "último texto del subagente")
	model.apply_update({"sessionUpdate": "tool_call_update", "toolCallId": "agent", "status": "completed",
		"content": [{"type": "content", "content": {"type": "text", "text": "Hay dos usos."}}]})
	view.call(&"refresh")
	assert_eq(toggle.text, "▾ 2 herramientas del subagente", "terminado, sin actividad")
	assert_true(_has_button_text(rows.agent.extra, "▸ informe · 1 línea"), "terminado muestra el informe")
	view.queue_free()


func _has_button_text(root: Node, text: String) -> bool:
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return true
	return false
