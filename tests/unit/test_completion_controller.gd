extends "test_case.gd"
## Completado (M8a): CompletionController sobre un CodeEdit real con reloj simulado: debounce,
## condiciones de disparo, invalidación, type-through, Tab/Esc y una sola acción de undo.

const CompletionController := preload("res://addons/godot_agent/completion/completion_controller.gd")
const TypedHistory := preload("res://addons/godot_agent/completion/local/typed_history.gd")
const FakeProvider := preload("res://tests/fake_completion_provider.gd")
const CompletionResult := preload("res://addons/godot_agent/completion/completion_result.gd")

var _now: int = 1000
var _code_edit: CodeEdit
var _controller: CompletionController
var _provider: FakeProvider
var _outcomes: PackedStringArray = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _setup(text: String, line: int, column: int) -> void:
	await _tree().process_frame  # en _initialize la raíz todavía no está en el árbol
	_code_edit = CodeEdit.new()
	_code_edit.size = Vector2(800, 400)
	_code_edit.text = text
	_tree().root.add_child(_code_edit)
	_code_edit.set_caret_line(line)
	_code_edit.set_caret_column(column)
	_code_edit.clear_undo_history()
	_provider = FakeProvider.new()
	_controller = CompletionController.new()
	_controller.provider = _provider
	_controller.history = TypedHistory.new()
	_controller.clock = func() -> int: return _now
	_controller.finished.connect(func(_r: RefCounted, outcome: String) -> void: _outcomes.append(outcome))
	_controller.attach(_code_edit, "res://x.gd")
	_code_edit.grab_focus()


## Corta los ciclos (los lambdas del controller capturan esta suite) y libera el CodeEdit ya.
func _teardown() -> void:
	_controller.detach()
	_controller.clock = Callable()
	for connection: Dictionary in _controller.finished.get_connections():
		_controller.finished.disconnect(connection.callable)
	_controller = null
	_code_edit.free()


## Escribe como el usuario (un carácter por vez, con las señales diferidas del CodeEdit).
func _type(text: String) -> void:
	for c in text:
		_code_edit.insert_text_at_caret(c)
		await _tree().process_frame


func _key(keycode: Key, alt: bool = false, control: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.alt_pressed = alt
	event.command_or_control_autoremap = control
	event.pressed = true
	_tree().root.push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	_tree().root.push_input(release)
	await _tree().process_frame


func _advance(ms: int) -> void:
	_now += ms
	_controller.tick(_now)


func test_debounce_and_accept() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	_provider.responses = {"pri": "nt(\"hola\")"}
	await _type("pri")
	_advance(10)
	assert_eq(_provider.calls.size(), 0, "dentro del debounce no pide")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS)
	assert_eq(_provider.calls.size(), 1, "vencido el debounce pide una vez")
	assert_eq(_controller.suggestion, "nt(\"hola\")", "muestra la sugerencia")
	await _key(KEY_TAB)
	assert_eq(_code_edit.get_line(1), "\tprint(\"hola\")", "Tab acepta la sugerencia (sin indentar)")
	assert_false(_controller.is_visible(), "después de aceptar no queda ghost text")
	assert_eq(_outcomes, PackedStringArray(["accepted"]), "resultado accepted")
	_code_edit.undo()
	assert_eq(_code_edit.get_line(1), "\tpri", "una sola acción de undo deshace la aceptación")
	_teardown()


func test_accept_word() -> void:
	assert_eq(CompletionController.next_word("velocity.x = 1"), "velocity", "identificador")
	assert_eq(CompletionController.next_word(".x = 1"), ".", "signos hasta el siguiente nombre")
	assert_eq(CompletionController.next_word(" = 1"), " =", "con los espacios de adelante")
	assert_eq(CompletionController.next_word("\n\tpass"), "\n\tpass", "con el salto de línea y la sangría")
	await _setup("func f() -> void:\n\t", 1, 1)
	var partial: Array[RefCounted] = []
	_controller.accepted_partial.connect(func(result: RefCounted) -> void: partial.append(result))
	_provider.responses = {"vel": "ocity = Vector2.ZERO\n\tmove_and_slide()"}
	await _type("vel")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	await _key(KEY_RIGHT, false, true)
	assert_eq(_code_edit.get_line(1), "\tvelocity", "Ctrl+→ inserta la palabra")
	assert_eq(_controller.suggestion, " = Vector2.ZERO\n\tmove_and_slide()", "el resto sigue a la vista")
	assert_eq(partial.size(), 1, "accepted_partial")
	await _tree().process_frame
	await _key(KEY_RIGHT, false, true)
	await _key(KEY_RIGHT, false, true)
	assert_eq(_code_edit.get_line(1), "\tvelocity = Vector2", "palabra por palabra (%s)" % _code_edit.get_line(1))
	_code_edit.undo()
	assert_eq(_code_edit.get_line(1), "\tvelocity =", "cada palabra es su propio paso de undo")
	_code_edit.redo()
	await _tree().process_frame
	await _key(KEY_TAB)
	assert_eq(_code_edit.text, "func f() -> void:\n\tvelocity = Vector2.ZERO\n\tmove_and_slide()", "Tab acepta el resto")
	assert_eq(_provider.calls.size(), 1, "aceptar por palabra no pide otra sugerencia")
	_teardown()


func test_tab_without_suggestion_indents() -> void:
	await _setup("func f() -> void:\n\tpass", 1, 5)
	await _key(KEY_TAB)
	assert_true(_code_edit.get_line(1).count("\t") >= 2 or _code_edit.get_line(1).contains("    "), "Tab sin sugerencia sigue indentando: %s" % _code_edit.get_line(1).c_escape())
	_teardown()


func test_type_through_and_invalidation() -> void:
	await _setup("func f() -> void:\n\t\n\tpass", 1, 1)
	_provider.responses = {"var spe": "ed := 10.0"}
	await _type("var spe")
	_advance(100)
	assert_eq(_controller.suggestion, "ed := 10.0", "sugerencia visible")
	await _type("ed")
	assert_eq(_controller.suggestion, " := 10.0", "type-through: consume lo tipeado sin pedir otra")
	assert_eq(_provider.calls.size(), 1, "no hubo otro pedido")
	await _type("x")
	assert_false(_controller.is_visible(), "tipear algo distinto invalida")
	assert_true(_controller.is_pending(), "y programa un pedido nuevo")
	_provider.responses = {"var speedx": " = 1"}
	_advance(100)
	assert_eq(_controller.suggestion, " = 1", "nueva sugerencia")
	_code_edit.set_caret_line(2)
	await _tree().process_frame
	assert_false(_controller.is_visible(), "mover el caret a otra línea invalida")
	assert_true(_outcomes.has("discarded:typed") and _outcomes.has("discarded:line"), "motivos: %s" % ", ".join(_outcomes))
	assert_eq(_controller.history.query("var spe").size(), 1, "la línea editada que se dejó entra al historial")
	_teardown()


## Una tecla y Tab en el mismo frame: las señales diferidas de la primera todavía no llegaron, y Tab
## no tiene que aceptar la sugerencia vieja (revisión de M8b).
func test_tab_after_key_in_same_frame() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	_provider.responses = {"pri": "nt()"}
	await _type("pri")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(_controller.suggestion, "nt()", "sugerencia visible")
	_code_edit.insert_text_at_caret("x")  # sin esperar el frame
	await _key(KEY_TAB)
	assert_false(_code_edit.get_line(1).contains("nt()"), "Tab no inserta la sugerencia vieja (%s)" % _code_edit.get_line(1).c_escape())
	assert_false(_controller.is_visible(), "la sugerencia se descartó")
	_teardown()


func test_esc_and_native_popup() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	_provider.responses = {"pri": "nt()"}
	await _type("pri")
	_advance(100)
	assert_true(_controller.is_visible(), "visible")
	await _key(KEY_ESCAPE)
	assert_false(_controller.is_visible(), "Esc descarta")
	assert_true(_outcomes.has("discarded:esc"), "motivo esc")

	await _type("n")
	_provider.responses = {"prin": "t()"}
	_advance(100)
	assert_true(_controller.is_visible(), "visible otra vez")
	_code_edit.code_completion_enabled = true
	_code_edit.add_code_completion_option(CodeEdit.KIND_FUNCTION, "print_debug", "print_debug")
	_code_edit.update_code_completion_options(true)
	await _tree().process_frame
	if _controller.native_popup_open():
		await _key(KEY_TAB)
		assert_false(_code_edit.get_line(1).contains("print()"), "con el popup nativo abierto Tab no acepta el ghost text")
		assert_true(_code_edit.get_line(1).contains("print_debug"), "Tab elige la opción del popup")
	else:
		assert_true(false, "no se pudo abrir el popup nativo en headless")
	_teardown()


func test_trigger_conditions() -> void:
	await _setup("func f() -> void:\n\tfoo(bar)", 1, 5)
	_provider.responses = {"foo(": "x"}
	_code_edit.insert_text_at_caret("")
	_controller.request(false)
	assert_eq(_provider.calls.size(), 0, "con texto (no cierres) a la derecha no dispara")
	_code_edit.set_line(1, "\tfoo()")
	_code_edit.set_caret_column(5)
	_controller.request(false)
	assert_eq(_provider.calls.size(), 1, "con solo cierres a la derecha sí")
	_code_edit.select(1, 1, 1, 3)
	_controller.request(false)
	assert_eq(_provider.calls.size(), 1, "con selección no")
	_code_edit.deselect()
	_code_edit.set_line(1, "\tfoo(bar)")
	_code_edit.set_caret_column(5)
	await _tree().process_frame
	await _key(KEY_BACKSLASH, true)
	assert_eq(_provider.calls.size(), 2, "Alt+\\ pide a mano aunque no esté al final")
	_controller.path = "res://shader.gdshader"
	_controller.request(true)
	assert_eq(_provider.calls.size(), 2, "solo archivos .gd")
	_teardown()


func test_stale_response_discarded() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	_provider.responses = {"pri": "nt()", "prin": "t()"}
	_provider.latency_ms = 50
	await _type("pri")
	_advance(100)
	await _type("n")
	await _tree().create_timer(0.12).timeout
	assert_false(_controller.is_visible(), "la respuesta vieja (pedida antes de la última tecla) se descarta")
	_teardown()


func test_tab_with_selection_never_replaces() -> void:
	await _setup("func f() -> void:\n\tvar a := 1\n\t", 2, 1)
	_provider.responses = {"pri": "nt()"}
	await _type("pri")
	_advance(100)
	assert_true(_controller.is_visible(), "visible")
	_code_edit.select_all()
	await _key(KEY_TAB)
	assert_true(_code_edit.text.contains("var a := 1"), "Tab con todo seleccionado no reemplaza el archivo con el ghost text")
	assert_false(_code_edit.text.contains("print()"), "ni inserta la sugerencia")
	assert_false(_controller.is_visible(), "la descarta")
	_teardown()


func test_manual_shortcut_not_swallowed_when_off() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	_controller.enabled = false
	var event := InputEventKey.new()
	event.keycode = KEY_BACKSLASH
	event.alt_pressed = true
	event.pressed = true
	_controller.call(&"_on_gui_input", event)
	assert_false(_controller.can_trigger(true), "apagado no se puede pedir: la tecla sigue su camino")
	assert_eq(_provider.calls.size(), 0, "no pide")
	_teardown()


## Modo híbrido (M8c): lo local sale al instante y el LLM solo cuando no hay nada local, con su
## debounce desde la última tecla; tipear cancela la request en vuelo y su respuesta no se muestra.
func test_hybrid_mode() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	var llm: FakeProvider = FakeProvider.new()
	llm.source = CompletionResult.SOURCE_LLM
	llm.latency_ms = 300
	_controller.llm_provider = llm
	_controller.mode = CompletionController.MODE_HYBRID
	var states: PackedStringArray = []
	_controller.llm_finished.connect(func(state: String, _r: RefCounted, _e: String, _ms: float) -> void: states.append(state))
	_provider.responses = {"pri": "nt()"}
	llm.responses = {"pri": "nt(\"llm\")", "foo": "_bar()"}
	await _type("pri")
	var started := Time.get_ticks_msec()
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(_controller.suggestion, "nt()", "lo local se muestra sin esperar al LLM")
	assert_true(Time.get_ticks_msec() - started < 100, "en el mismo frame")
	_advance(1000)
	assert_eq(llm.calls.size(), 0, "con sugerencia local no se pide al LLM")

	_controller.dismiss("test")
	await _type("\n\tfoo")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(_controller.suggestion, "", "nada local")
	assert_eq(llm.calls.size(), 0, "el LLM espera su debounce")
	_advance(CompletionController.DEFAULT_LLM_DEBOUNCE_MS)
	assert_eq(llm.calls.size(), 1, "vencido el debounce del LLM, un pedido")
	assert_true(_controller.is_llm_busy(), "en vuelo")
	await _tree().create_timer(0.45).timeout
	assert_eq(_controller.suggestion, "_bar()", "la respuesta del LLM se muestra")
	assert_eq(_controller.renderer.marked, true, "con el marcador del LLM")
	assert_eq(states, PackedStringArray(["done"]), "terminó")

	# Tipear con una request en vuelo la cancela y su respuesta no aparece.
	_controller.dismiss("test")
	await _type("\n\tfoo")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + CompletionController.DEFAULT_LLM_DEBOUNCE_MS + 1)
	assert_eq(llm.calls.size(), 2, "otro pedido")
	var cancelled_before := llm.cancelled
	await _type("x")
	assert_true(llm.cancelled > cancelled_before and not _controller.is_llm_busy(), "tipear cancela")
	await _tree().create_timer(0.45).timeout
	assert_eq(_controller.suggestion, "", "la respuesta cancelada no se muestra")
	assert_eq(states[states.size() - 1], "cancelled", "avisado como cancelado")

	# Con el LLM lento en vuelo, lo local que aparece al seguir tipeando no lo espera.
	_controller.dismiss("test")
	await _type("\n\tfoo")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + CompletionController.DEFAULT_LLM_DEBOUNCE_MS + 1)
	assert_true(_controller.is_llm_busy(), "LLM en vuelo")
	await _type("\n\tpri")
	started = Time.get_ticks_msec()
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(_controller.suggestion, "nt()", "lo local no espera al LLM en vuelo")
	assert_true(Time.get_ticks_msec() - started < 100 and not _controller.is_llm_busy(), "en el mismo frame, y el pedido viejo cancelado")

	# Alt+\ en híbrido fuerza el LLM aunque haya algo local.
	_controller.dismiss("test")
	await _type("\n\tpri")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(_controller.suggestion, "nt()", "local")
	await _key(KEY_BACKSLASH, true)
	assert_eq(llm.calls.size(), 4, "Alt+\\ pide al LLM")
	await _tree().create_timer(0.45).timeout
	assert_eq(_controller.suggestion, "nt(\"llm\")", "y muestra lo del LLM")
	_teardown()


## Solo LLM: el debounce es el del LLM y el proveedor local no se consulta.
func test_llm_only_mode() -> void:
	await _setup("func f() -> void:\n\t", 1, 1)
	var llm: FakeProvider = FakeProvider.new()
	_controller.llm_provider = llm
	_controller.mode = CompletionController.MODE_LLM
	llm.responses = {"pri": "nt(1)"}
	_provider.responses = {"pri": "nt()"}
	await _type("pri")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(llm.calls.size(), 0, "el debounce local no alcanza")
	_advance(CompletionController.DEFAULT_LLM_DEBOUNCE_MS)
	assert_eq([llm.calls.size(), _provider.calls.size()], [1, 0], "pide solo al LLM")
	assert_eq(_controller.suggestion, "nt(1)", "muestra lo del LLM")
	_controller.mode = CompletionController.MODE_LOCAL
	_controller.dismiss("test")
	await _type("n")
	_advance(CompletionController.DEFAULT_DEBOUNCE_MS + 1)
	assert_eq(_provider.calls.size(), 1, "de vuelta en local, sin reiniciar nada")
	_teardown()

