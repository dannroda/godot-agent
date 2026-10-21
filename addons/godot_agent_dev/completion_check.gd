@tool
extends RefCounted
## Completado en el Script Editor real (M8a): abre un script adjunto a una escena, tipea con
## eventos de teclado como el usuario y comprueba el ghost text de `@onready var `, `func _` y una
## línea repetida del proyecto, Tab para aceptar (una acción de undo), Esc, Tab sin sugerencia que
## indenta y el popup nativo. Deja capturas si se pasa un prefijo.

const SERVICE_SCRIPT := "res://addons/godot_agent/completion/completion_service.gd"
const DIR := "res://tests/tmp/cc"
const TARGET := DIR + "/target.gd"
const SCENE := DIR + "/target.tscn"
const INDEX_TIMEOUT_S := 20.0
const SUGGESTION_TIMEOUT_S := 3.0
const REPEATED := "\tscore_board.add_points(points_for_hit * combo_multiplier)"

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
		_write(DIR + "/scorer_%d.gd" % i, "extends Node\n\nvar score_board\nvar points_for_hit := 5\nvar combo_multiplier := 1\n\n\nfunc hit() -> void:\n%s\n" % REPEATED)


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


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
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

