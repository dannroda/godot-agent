extends "test_case.gd"
## Cola de prompts del dock: orden, pausa y reanudación, quitar y editar desde la vista.

const PromptQueue := preload("res://addons/godot_agent/session/prompt_queue.gd")
const PromptQueueView := preload("res://addons/godot_agent/ui/dock/prompt_queue_view.gd")


func test_order_and_pause() -> void:
	var queue := PromptQueue.new()
	var changes := [0]
	queue.changed.connect(func() -> void: changes[0] += 1)
	queue.pause("nada que pausar")
	assert_false(queue.paused, "vacía no se pausa")
	queue.add("uno", [{"type": "text", "text": "ctx"}])
	queue.add("dos")
	queue.add("tres")
	assert_eq(queue.take_next().text, "uno", "en orden")
	queue.pause("el turno se canceló")
	assert_true(queue.paused, "pausada")
	assert_eq(queue.take_next(), {}, "en pausa no sale nada")
	queue.resume()
	assert_eq(queue.take_next().text, "dos", "retoma")
	assert_eq(queue.remove_at(5), {}, "índice fuera de rango")
	queue.pause("x")
	assert_eq(queue.remove_at(0).text, "tres", "quitar el último")
	assert_false(queue.paused, "vacía deja de estar en pausa")
	assert_true(changes[0] >= 7, "avisa cada cambio")


func test_view() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var queue := PromptQueue.new()
	var view: PanelContainer = PromptQueueView.new()
	view.call(&"setup", queue)
	tree.root.add_child(view)
	await tree.process_frame
	assert_false(view.visible, "oculta sin prompts")
	queue.add("primero\ncon dos líneas")
	queue.add("segundo")
	await tree.process_frame
	assert_true(view.visible, "visible con prompts")
	var title: Label = view.get(&"_title")
	assert_eq(title.text, "En cola (2)", "cuenta")
	var send_now: Button = view.get(&"_send_now")
	assert_false(send_now.visible, "sin pausa no hay «Enviar ahora»")
	queue.pause("el turno se canceló")
	await tree.process_frame
	assert_true(send_now.visible, "en pausa ofrece «Enviar ahora»")
	view.call(&"set_send_available", false)
	assert_true(send_now.disabled, "sin sesión lista, deshabilitado")
	var edited: PackedStringArray = []
	view.connect(&"edit_requested", func(text: String) -> void: edited.append(text))
	var rows: VBoxContainer = view.get(&"_rows")
	var first_row := rows.get_child(0)
	var row_label := first_row.get_child(0) as Label
	assert_eq(row_label.text, "primero ⏎ con dos líneas", "una línea por prompt")
	(first_row.get_child(1) as Button).pressed.emit()
	assert_eq(edited, PackedStringArray(["primero\ncon dos líneas"]), "editar lo devuelve completo")
	assert_eq(queue.size(), 1, "y sale de la cola")
	await tree.process_frame
	(rows.get_child(rows.get_child_count() - 1).get_child(2) as Button).pressed.emit()
	assert_true(queue.is_empty(), "quitar")
	await tree.process_frame
	assert_false(view.visible, "vacía se oculta")
	view.queue_free()
