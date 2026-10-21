extends "test_case.gd"
## Contenido de tool calls en el dock (spec §6): imágenes ACP en base64.

const ToolGroupView := preload("res://addons/godot_agent/ui/dock/entries/tool_group_view.gd")


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
