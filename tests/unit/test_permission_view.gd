extends "test_case.gd"
## Tarjeta de permiso (m12-10): el orden de los botones no depende del agente.

const PermissionView := preload("res://addons/godot_agent/ui/dock/entries/permission_view.gd")
const PermissionRequest := preload("res://addons/godot_agent/session/permission_request.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ConversationView := preload("res://addons/godot_agent/ui/dock/conversation_view.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")


func test_sorted_options() -> void:
	var options := [
		{"optionId": "a", "kind": "allow_always"},
		{"optionId": "x", "kind": "something_else"},
		{"optionId": "r", "kind": "reject_once"},
		{"optionId": "o", "kind": "allow_once"},
		"no es un diccionario",
	]
	var ids := PermissionView.sorted_options(options).map(func(option: Dictionary) -> String: return option.optionId)
	assert_eq(ids, ["o", "r", "a", "x"], "permitir, denegar, siempre; lo desconocido al final")


## El pendiente va a la barra fija sobre el composer; resuelto, vuelve al chat en su orden.
func test_pending_permission_goes_to_the_sticky_slot() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	var conversation := ConversationView.new()
	conversation.setup(model, Color.ORANGE)
	var sticky := VBoxContainer.new()
	conversation.sticky_slot = sticky
	tree.root.add_child(conversation)
	tree.root.add_child(sticky)
	model.add_notice("antes")
	var first := _request()
	model.add_permission(first)
	model.add_notice("entre")
	var second := _request()
	model.add_permission(second)
	await tree.process_frame
	await tree.process_frame
	assert_eq(sticky.get_child_count(), 2, "los dos pendientes, en la barra")
	second.select("o")
	await tree.process_frame
	await tree.process_frame
	var list: VBoxContainer = conversation.get(&"_list")
	assert_eq(sticky.get_child_count(), 1, "el resuelto sale de la barra")
	assert_eq(list.get_child_count(), 4, "«Mostrar anteriores», dos avisos y el resuelto")
	assert_true(list.get_child(3) is PermissionView, "el segundo vuelve al final")
	first.select("o")
	await tree.process_frame
	await tree.process_frame
	assert_eq(sticky.get_child_count(), 0, "barra vacía")
	assert_true(list.get_child(2) is PermissionView, "el primero vuelve entre los avisos")
	conversation.free()
	sticky.free()


## m17-26: un comando de cientos de líneas no empuja los botones fuera de la vista.
func test_long_command_is_folded() -> void:
	assert_eq(PermissionView.short_text("ls -la"), "ls -la", "corto: igual")
	assert_eq(PermissionView.short_text("python3 - << 'EOF'\nprint(1)\nEOF"), "python3 - << 'EOF' …", "multilínea: la primera")
	assert_eq(PermissionView.short_text("x".repeat(300)).length(), PermissionView.TITLE_MAX_CHARS + 1, "larga: cortada con «…»")
	var tree := Engine.get_main_loop() as SceneTree
	var model := SessionModel.new()
	var request := _request()
	var lines: PackedStringArray = ["python3 - << 'EOF'"]
	for i in 200:
		lines.append("content line %d" % i)
	lines.append("EOF")
	request.title = "\n".join(lines)
	request.description = request.title
	var entry := model.add_permission(request)
	var view := PermissionView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	view.call(&"_build")
	view.refresh()
	var title: Label = view.get(&"_title")
	assert_eq(title.text.count("\n"), 0, "el título es una línea: %s" % title.text.left(80))
	assert_true(title.text.contains("python3 - << 'EOF'"), "con el comienzo del comando")
	var toggle: Button = view.get(&"_full_toggle")
	var box: Control = view.get(&"_full_box")
	assert_true(toggle.visible and toggle.text.contains("202"), "ofrece ver todo, con las líneas: %s" % toggle.text)
	assert_false(box.visible, "el comando entero arranca plegado")
	assert_true((view.get(&"_buttons") as Control).visible, "los botones están")
	toggle.button_pressed = true
	assert_true(box.visible, "se abre con un clic")
	assert_true(str((view.get(&"_full_text") as Label).text).contains("content line 199"), "con el comando entero")
	view.free()


## godot.request_mode (m11-68): la tarjeta del harness usa los nombres de sus opciones, muestra la
## descripción entera (el aviso de más permisos no queda plegado) y el resultado dice la opción elegida.
func test_own_labels() -> void:
	var model := SessionModel.new()
	var request := PermissionRequest.new()
	request.title = "Switch to Auto"
	request.description = "From Build to Auto.\n⚠ More permissions: Auto edits without asking.\nThe agent says: «Many small edits»"
	request.options = [
		{"optionId": "switch", "name": "Switch to Auto", "kind": PermissionRequest.KIND_ALLOW_ONCE},
		{"optionId": "stay", "name": "Stay in Build", "kind": PermissionRequest.KIND_REJECT_ONCE},
	]
	request.own_labels = true
	var entry := model.add_permission(request)
	var view := PermissionView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	view.call(&"_build")
	view.refresh()
	var texts: Array = (view.get(&"_buttons") as Control).get_children().map(func(button: Button) -> String: return button.text)
	assert_eq(texts.slice(0, 2), ["Switch to Auto", "Stay in Build"], "los botones con el nombre de cada opción")
	assert_true(str((view.get(&"_description") as Label).text).contains("⚠ More permissions"), "la descripción entera, con el aviso")
	assert_false((view.get(&"_full_toggle") as Button).visible, "sin «Show all»")
	request.deny_with_reason("Not now")
	view.refresh()
	assert_eq((view.get(&"_result") as Label).text, "✗ Stay in Build · Not now", "el resultado dice qué se eligió")
	view.free()
	# Sin own_labels, como siempre.
	var plain := PermissionRequest.new()
	plain.title = "Edit player.gd"
	plain.options = request.options.duplicate(true)
	view = PermissionView.new()
	view.setup(model.add_permission(plain), Color.ORANGE, MarkdownBBCode.new())
	view.call(&"_build")
	view.refresh()
	assert_eq(((view.get(&"_buttons") as Control).get_child(0) as Button).text, "Allow once", "una tarjeta de agente lleva los nombres de siempre")
	view.free()


static func _request() -> PermissionRequest:
	var request := PermissionRequest.new()
	request.title = "Edit player.gd"
	request.options = [{"optionId": "o", "kind": PermissionRequest.KIND_ALLOW_ONCE}]
	return request
