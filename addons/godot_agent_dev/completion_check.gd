@tool
extends RefCounted
## Completado en el Script Editor real (M8a): abre un script adjunto a una escena, tipea con
## eventos de teclado como el usuario y comprueba el ghost text de `@onready var `, `func _` y una
## línea repetida del proyecto, Tab para aceptar (una acción de undo), Esc, Tab sin sugerencia que
## indenta, el popup nativo y (M8b) un bloque de varias líneas con Ctrl+→. Deja capturas si se pasa
## un prefijo. M8c: el indicador en la barra del Script Editor y los modos híbrido y local contra un
## LLM falso (tests/fake_llm_server.gd), cambiando de modo sin reiniciar.

const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const CompletionIndicator := preload("res://addons/godot_agent/completion/completion_indicator.gd")
const FakeLlmServer := preload("res://tests/fake_llm_server.gd")
const SERVICE_SCRIPT := "res://addons/godot_agent/completion/completion_service.gd"
const DIR := "res://tests/tmp/cc"
const TARGET := DIR + "/target.gd"
const SCENE := DIR + "/target.tscn"
const INDEX_TIMEOUT_S := 20.0
const SUGGESTION_TIMEOUT_S := 3.0
const REPEATED := "\tscore_board.add_points(points_for_hit * combo_multiplier)"
const RESET_BODY := "\tcombo_multiplier = 1\n\tpoints_for_hit = 0\n\tset_process(false)"
## Settings que toca el paso del LLM (son los EditorSettings reales: se restauran al final).
const LLM_KEYS: PackedStringArray = [HarnessSettings.KEY_COMPLETION_MODE, HarnessSettings.KEY_COMPLETION_LLM_PROFILES,
	HarnessSettings.KEY_COMPLETION_LLM_ACTIVE, HarnessSettings.KEY_COMPLETION_LLM_DEBOUNCE, HarnessSettings.KEY_COMPLETION_ENABLED]

var failures: PackedStringArray = []
var report: PackedStringArray = []
var _tree: SceneTree
var _service: Node
var _code_edit: CodeEdit


func run(tree: SceneTree, shot_prefix: String) -> PackedStringArray:
	_tree = tree
	for node: Node in tree.root.find_children("*", "Node", true, false):
		if node.get_script() and (node.get_script() as Script).resource_path == SERVICE_SCRIPT:
			_service = node
	if _service == null:
		failures.append("no se encontró CompletionService")
		return failures
	_write_fixture()
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	var waited := 0.0
	var context: Object = _service.get(&"context")
	while waited < INDEX_TIMEOUT_S and not ((context.get(&"index") as Object).get(&"script_nodes") as Dictionary).has(TARGET):
		await tree.create_timer(0.25).timeout
		waited += 0.25
	if not ((context.get(&"index") as Object).get(&"script_nodes") as Dictionary).has(TARGET):
		failures.append("el índice no vio la escena nueva en %.0f s" % INDEX_TIMEOUT_S)
		return failures
	report.append("índice listo en %.1f s" % waited)

	EditorInterface.set_main_screen_editor("Script")
	EditorInterface.edit_script(load(TARGET), 9, 0)
	await tree.create_timer(1.0).timeout
	_code_edit = EditorInterface.get_script_editor().get_current_editor().get_base_editor() as CodeEdit
	if _code_edit == null:
		failures.append("no se abrió el script")
		return failures
	_code_edit.grab_focus()
	await tree.process_frame
	if not _code_edit.is_visible_in_tree() or not _code_edit.has_focus():
		failures.append("el CodeEdit no quedó visible y con foco (visible=%s, foco=%s)" % [_code_edit.is_visible_in_tree(), _code_edit.has_focus()])
		return failures
	var controller: Object = _service.call(&"controller_for", TARGET)
	if controller == null:
		failures.append("el CodeEdit del script no tiene controller")
		return failures

	# 1. @onready var -> primer hijo no declarado, con tipo y ruta.
	_goto_new_line(5)
	await _type("@onready var ")
	if await _expect(controller, "cooldown: Timer = $Cooldown", "@onready var"):
		await _shot(shot_prefix, "onready")
		await _key(KEY_TAB)
		_check(_code_edit.get_line(_code_edit.get_caret_line()) == "@onready var cooldown: Timer = $Cooldown", "Tab inserta la línea (%s)" % _code_edit.get_line(_code_edit.get_caret_line()))
		_code_edit.undo()
		await _tree.process_frame
		_check(_code_edit.get_line(_code_edit.get_caret_line()) == "@onready var ", "un solo undo deshace la aceptación (%s)" % _code_edit.get_line(_code_edit.get_caret_line()))
		await _type("ba")
		await _expect(controller, "r: ProgressBar = %Bar", "@onready var con nodo único")
		var anchor: Vector2 = (controller.get(&"renderer") as Object).call(&"anchor_position", _code_edit, _code_edit.get_caret_line(), _code_edit.get_caret_column())
		_check(is_equal_approx(anchor.x, _code_edit.get_caret_draw_pos().x) and anchor.y >= 0.0, "el ghost text arranca en el caret (%s vs %s)" % [anchor, _code_edit.get_caret_draw_pos()])
		await _key(KEY_ESCAPE)
		_check(not controller.call(&"is_visible"), "Esc descarta")

	# 2. func _ -> virtual con firma (no _ready, que ya está).
	_goto_new_line(_code_edit.get_line_count())
	await _type("func _")
	if await _expect(controller, "process(delta: float) -> void:", "func _"):
		await _shot(shot_prefix, "virtual")
		await _key(KEY_TAB)

	# 3. Línea repetida en otros archivos del proyecto.
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tscore_bo")
	if await _expect(controller, REPEATED.strip_edges().substr("score_bo".length()), "línea repetida"):
		await _shot(shot_prefix, "retrieval")
		await _key(KEY_ESCAPE)

	# 4. Tab sin sugerencia sigue indentando.
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tvar zz := 1")
	await _tree.create_timer(0.3).timeout
	_code_edit.set_caret_column(1)
	await _tree.process_frame
	var before := _code_edit.get_line(_code_edit.get_caret_line())
	await _key(KEY_TAB)
	var after := _code_edit.get_line(_code_edit.get_caret_line())
	_check(after.length() > before.length() and after.begins_with("\t\t"), "Tab sin sugerencia indenta (%s -> %s)" % [before.c_escape(), after.c_escape()])

	# 5. Con el autocierre del editor a la derecha (`")`), el ghost text va entre el caret y el cierre.
	# En la ventana de Xvfb el área de texto es angosta: se oculta la lista de scripts en este paso.
	var panel := _scripts_panel()
	if panel:
		panel.visible = false
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tpreload(\"res://tests/tmp/cc/sco")
	var rest := _code_edit.get_line(_code_edit.get_caret_line()).substr(_code_edit.get_caret_column())
	if await _expect(controller, "rer_0.gd", "preload con autocierre (a la derecha: %s)" % rest):
		await _shot(shot_prefix, "closers")
		await _key(KEY_TAB)
		var accepted := _code_edit.get_line(_code_edit.get_caret_line()).strip_edges()
		_check(accepted == "preload(\"res://tests/tmp/cc/scorer_0.gd\")", "Tab respeta el cierre que ya estaba (%s)" % accepted)
	if panel:
		panel.visible = true

	# 6. Popup nativo: abierto, el ghost text no se dibuja y Tab es del popup.
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tscore_bo")
	await _expect(controller, REPEATED.strip_edges().substr("score_bo".length()), "línea repetida (otra vez)")
	# El autocompletado del Script Editor no siempre abre solo en Xvfb: se abre con una opción propia
	# y Tab se manda enseguida (el editor cierra un popup que no pidió él al frame siguiente).
	_code_edit.add_code_completion_option(CodeEdit.KIND_VARIABLE, "score_board_native", "score_board_native")
	_code_edit.update_code_completion_options(true)
	if _code_edit.get_code_completion_selected_index() == -1:
		failures.append("no se pudo abrir el popup nativo")
	else:
		_check(not controller.call(&"can_trigger", true), "con el popup abierto no se pide sugerencia")
		await _key(KEY_TAB)
		var line := _code_edit.get_line(_code_edit.get_caret_line())
		_check(not line.contains("add_points(points_for_hit") and line.contains("score_board_native"), "con el popup abierto Tab es del popup, no del ghost text (%s)" % line)

	# 7. Línea vacía después de un func que el proyecto ya tiene: el bloque entero (M8b), dibujado
	# en la caja de abajo; Ctrl+→ acepta una palabra y deja el resto, Tab el resto.
	if panel:
		panel.visible = false
	_goto_new_line(_code_edit.get_line_count())
	_code_edit.insert_text_at_caret("func reset() -> void:")
	await _key(KEY_ENTER)
	if await _expect(controller, RESET_BODY.substr(1), "bloque en línea vacía"):
		await _shot(shot_prefix, "multiline")
		var box: Rect2 = (controller.get(&"renderer") as Object).get(&"box")
		_check(box.size.y >= 2 * _code_edit.get_line_height() - 1, "la caja muestra las dos líneas siguientes (%s)" % box)
		await _key(KEY_RIGHT, true)
		_check(_code_edit.get_line(_code_edit.get_caret_line()) == "\tcombo_multiplier", "Ctrl+→ inserta una palabra (%s)" % _code_edit.get_line(_code_edit.get_caret_line()).c_escape())
		_check(str(controller.get(&"suggestion")) == RESET_BODY.substr(1 + "combo_multiplier".length()), "Ctrl+→ deja el resto a la vista (%s)" % str(controller.get(&"suggestion")).c_escape())
		await _shot(shot_prefix, "partial")
		await _key(KEY_TAB)
		var last := _code_edit.get_caret_line()
		var block := "\n".join(PackedStringArray([_code_edit.get_line(last - 2), _code_edit.get_line(last - 1), _code_edit.get_line(last)]))
		_check(block == RESET_BODY, "Tab inserta el resto del bloque (%s)" % block.c_escape())
	if panel:
		panel.visible = true

	# 8. Indicador e híbrido contra un LLM falso; después solo local, sin reiniciar.
	var settings: HarnessSettings = _service.get(&"_settings")
	var saved: Dictionary = {}
	for key: String in LLM_KEYS:
		saved[key] = settings.get_value(key)
	var server := FakeLlmServer.new()
	_tree.root.add_child(server)
	if server.start() != OK:
		failures.append("no se pudo levantar el LLM falso")
	else:
		await _llm_step(controller, settings, server, shot_prefix)
	for key: String in LLM_KEYS:
		settings.set_value(key, saved[key])
	_service.call(&"apply_settings")
	server.queue_free()

	# Texto original y marcado como guardado: al salir el editor no intenta guardar en DIR, que se borra.
	_code_edit.text = FileAccess.get_file_as_string(TARGET)
	_code_edit.tag_saved_version()
	return failures


func cleanup() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _write_fixture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_write(TARGET, "extends Node2D\n\nvar score_board\nvar points_for_hit := 10\nvar combo_multiplier := 2\n\n\nfunc _ready() -> void:\n\tpass\n")
	_write(SCENE, "[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n\n[node name=\"Target\" type=\"Node2D\"]\nscript = ExtResource(\"1\")\n\n[node name=\"Cooldown\" type=\"Timer\" parent=\".\"]\n\n[node name=\"Sprite\" type=\"Sprite2D\" parent=\".\"]\n\n[node name=\"UI\" type=\"CanvasLayer\" parent=\".\"]\n\n[node name=\"Bar\" type=\"ProgressBar\" parent=\"UI\"]\nunique_name_in_owner = true\n" % TARGET)
	for i in 2:
		_write(DIR + "/scorer_%d.gd" % i, "extends Node\n\nvar score_board\nvar points_for_hit := 5\nvar combo_multiplier := 1\n\n\nfunc hit() -> void:\n%s\n\n\nfunc reset() -> void:\n%s\n" % [REPEATED, RESET_BODY])


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _goto_new_line(line: int) -> void:
	_code_edit.deselect()
	var target := mini(line, _code_edit.get_line_count())
	if target >= _code_edit.get_line_count():
		_code_edit.set_caret_line(_code_edit.get_line_count() - 1)
		_code_edit.set_caret_column(_code_edit.get_line(_code_edit.get_caret_line()).length())
		_code_edit.insert_text_at_caret("\n")
	else:
		_code_edit.set_caret_line(target)
		_code_edit.set_caret_column(0)
		_code_edit.insert_text_at_caret("\n")
		_code_edit.set_caret_line(target)
		_code_edit.set_caret_column(0)
	_code_edit.set_line(_code_edit.get_caret_line(), "")
	_code_edit.grab_focus()


## Tipea con eventos de teclado (pasan por el gui_input del CodeEdit, como una persona).
func _type(text: String) -> void:
	for c in text:
		var event := InputEventKey.new()
		event.pressed = true
		if c == "\t":
			event.keycode = KEY_TAB
		else:
			event.unicode = c.unicode_at(0)
		_code_edit.get_viewport().push_input(event)
		var release := event.duplicate() as InputEventKey
		release.pressed = false
		_code_edit.get_viewport().push_input(release)
		await _tree.process_frame


func _key(keycode: Key, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.command_or_control_autoremap = control
	event.pressed = true
	_code_edit.get_viewport().push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	_code_edit.get_viewport().push_input(release)
	await _tree.process_frame
	await _tree.process_frame


func _expect(controller: Object, expected: String, label: String) -> bool:
	var waited := 0.0
	while waited < SUGGESTION_TIMEOUT_S and str(controller.get(&"suggestion")) != expected:
		await _tree.create_timer(0.05).timeout
		waited += 0.05
	var got := str(controller.get(&"suggestion"))
	_check(got == expected, "%s: esperado «%s», obtenido «%s» (línea «%s»)" % [label, expected, got, _code_edit.get_line(_code_edit.get_caret_line())])
	if got == expected:
		report.append("%s ok en %.0f ms" % [label, waited * 1000.0])
	return got == expected


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _shot(prefix: String, name: String) -> void:
	if prefix.is_empty():
		return
	await _tree.process_frame
	_code_edit.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, name])


## Lista de scripts del Script Editor: el primer hijo del primer HSplitContainer.
func _scripts_panel() -> Control:
	var splits := EditorInterface.get_script_editor().find_children("*", "HSplitContainer", true, false)
	if splits.is_empty() or (splits[0] as Node).get_child_count() == 0:
		return null
	return (splits[0] as Node).get_child(0) as Control


func _llm_step(controller: Object, settings: HarnessSettings, server: Node, shot_prefix: String) -> void:
	var indicator: CompletionIndicator = _service.get(&"indicator")
	var bar := CompletionIndicator.menu_bar(EditorInterface.get_script_editor())
	_check(indicator != null and bar != null and indicator.get_parent() == bar and indicator.is_visible_in_tree(), "el indicador está en la barra del Script Editor")
	if indicator == null:
		return
	_check(indicator.mode_label == "local" and indicator.state == CompletionIndicator.State.ACTIVE, "indicador: local y activo (%s, %d)" % [indicator.mode_label, indicator.state])
	server.set(&"routes", {"/api/generate": {"status": 200, "body": {"response": "ave(3)\n", "done": true}, "delay_ms": 150}})
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_PROFILES, JSON.stringify([{"id": "fake", "kind": "ollama", "display_name": "Falso", "url": server.call(&"url"), "model": "fake-coder"}]))
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_ACTIVE, "fake")
	settings.set_value(HarnessSettings.KEY_COMPLETION_LLM_DEBOUNCE, 100)
	settings.set_value(HarnessSettings.KEY_COMPLETION_MODE, HarnessSettings.COMPLETION_MODES.find("hybrid"))
	_service.call(&"apply_settings")
	_check(str(controller.get(&"mode")) == "hybrid", "el controller pasa a híbrido sin reiniciar (%s)" % controller.get(&"mode"))
	_check(indicator.mode_label == "híbrido · fake-coder", "indicador: modo y modelo (%s)" % indicator.mode_label)

	# Nada local para `spawn_w`: el LLM completa después del debounce y la sugerencia lleva la marca.
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tspawn_w")
	var thinking := false
	var waited := 0.0
	while waited < SUGGESTION_TIMEOUT_S and str(controller.get(&"suggestion")).is_empty():
		thinking = thinking or indicator.state == CompletionIndicator.State.THINKING
		await _tree.create_timer(0.02).timeout
		waited += 0.02
	_check(thinking, "el indicador muestra «pensando» mientras espera al LLM")
	if await _expect(controller, "ave(3)", "híbrido: sugerencia del LLM"):
		_check(bool((controller.get(&"renderer") as Object).get(&"marked")), "la sugerencia del LLM va marcada")
		_check(indicator.state == CompletionIndicator.State.ACTIVE, "el indicador vuelve a activo")
		await _shot(shot_prefix, "llm")
		await _key(KEY_TAB)
		_check(_code_edit.get_line(_code_edit.get_caret_line()) == "\tspawn_wave(3)", "Tab acepta la del LLM (%s)" % _code_edit.get_line(_code_edit.get_caret_line()).c_escape())
	var requests: Array = server.get(&"requests")
	_check(requests.size() == 1, "un solo pedido al LLM (hubo %d)" % requests.size())
	if not requests.is_empty():
		var body: Variant = (requests[0] as Dictionary).body
		_check(body is Dictionary and (body as Dictionary).get("model") == "fake-coder" and str((body as Dictionary).get("prompt", "")).contains("spawn_w"), "el pedido lleva modelo y prefix")

	# Error del endpoint: el indicador lo muestra y el editor sigue andando.
	server.set(&"routes", {"/api/generate": {"status": 500, "body": {"error": "boom"}, "delay_ms": 0}})
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tspawn_x")
	waited = 0.0
	while waited < SUGGESTION_TIMEOUT_S and indicator.state != CompletionIndicator.State.ERROR:
		await _tree.create_timer(0.05).timeout
		waited += 0.05
	_check(indicator.state == CompletionIndicator.State.ERROR, "un error del LLM se ve en el indicador")

	# Solo local, sin reiniciar: ya no hay pedidos.
	settings.set_value(HarnessSettings.KEY_COMPLETION_MODE, HarnessSettings.COMPLETION_MODES.find("local"))
	_service.call(&"apply_settings")
	var before := (server.get(&"requests") as Array).size()
	_goto_new_line(_code_edit.get_line_count())
	await _type("\tspawn_y")
	await _tree.create_timer(0.6).timeout
	_check((server.get(&"requests") as Array).size() == before and str(controller.get(&"suggestion")).is_empty(), "en modo local no se llama al LLM")
	_check(indicator.mode_label == "local" and indicator.state == CompletionIndicator.State.ACTIVE, "indicador: local otra vez (%s, %d)" % [indicator.mode_label, indicator.state])

	# Alt+Shift+\ apaga y prende.
	await _key_alt_shift_backslash()
	_check(indicator.state == CompletionIndicator.State.OFF, "Alt+Shift+\\ apaga")
	await _key_alt_shift_backslash()
	_check(indicator.state == CompletionIndicator.State.ACTIVE, "Alt+Shift+\\ prende")


func _key_alt_shift_backslash() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_BACKSLASH
	event.alt_pressed = true
	event.shift_pressed = true
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	await _tree.process_frame
	await _tree.process_frame
