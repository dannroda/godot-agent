@tool
extends RefCounted
## Un CompletionController por cada CodeEdit de script (spec §16.1, §16.5, §16.7): escucha texto y
## caret, dispara con debounce, invalida, hace type-through y acepta con Tab (una sola acción de
## undo). El reloj y el disparo (`tick`) los maneja CompletionService, así los tests usan un reloj
## simulado.
## Modos (M8c): solo local; híbrido (el local responde al instante y, si no tiene nada, se pide al
## LLM con su debounce, contado desde la última tecla; lo del LLM se muestra solo si no se tipeó nada
## desde el pedido y nunca reemplaza una sugerencia visible; Alt+\ fuerza el LLM); solo LLM. Una
## request LLM en vuelo como máximo: cualquier cambio la cancela.

signal shown(result: CompletionResult)
## outcome: accepted, typed_through, discarded:<motivo>
signal finished(result: CompletionResult, outcome: String)
## Ctrl+→ aceptó una palabra; la sugerencia sigue con el resto.
signal accepted_partial(result: CompletionResult)
## Un pedido al LLM: state = thinking, done (con o sin sugerencia), error o cancelled. `result` es la
## respuesta (o null) y `error`, el motivo; para el log y el indicador.
signal llm_finished(state: String, result: CompletionResult, error: String, latency_ms: float)
signal llm_started
## El buffer cambió y quedó quieto un rato: hay que reindexarlo (ProjectContext.update_buffer).
signal buffer_idle(path: String, text: String, caret_line: int)

const CompletionProvider := preload("completion_provider.gd")
const CompletionRequest := preload("completion_request.gd")
const CompletionResult := preload("completion_result.gd")
const GhostTextRenderer := preload("ghost_text_renderer.gd")
const TypedHistory := preload("local/typed_history.gd")
const SuggestionCache := preload("suggestion_cache.gd")

const CLOSERS := ")]}\"'"
const DEFAULT_DEBOUNCE_MS := 30
const DEFAULT_LLM_DEBOUNCE_MS := 200
const MODE_LOCAL := "local"
const MODE_HYBRID := "hybrid"
const MODE_LLM := "llm"
const BUFFER_IDLE_MS := 800

var code_edit: CodeEdit
var path: String = ""
var provider: CompletionProvider
## Proveedor LLM (null = no hay): se usa en los modos híbrido y solo LLM.
var llm_provider: CompletionProvider
var mode: String = MODE_LOCAL
var llm_debounce_ms: int = DEFAULT_LLM_DEBOUNCE_MS
## Distingue en el dibujo lo que vino del LLM (spec §16.7).
var llm_marker: bool = true
var history: TypedHistory
var renderer: GhostTextRenderer = GhostTextRenderer.new()
var cache: SuggestionCache = SuggestionCache.new()
var debounce_ms: int = DEFAULT_DEBOUNCE_MS
var enabled: bool = true
## Reloj en ms (los tests lo reemplazan).
var clock: Callable = Time.get_ticks_msec

## Resto visible de la sugerencia ("" = no hay).
var suggestion: String = ""
var _result: CompletionResult
var _anchor_line: int = -1
var _anchor_column: int = -1
var _anchor_prefix: String = ""
var _anchor_suffix: String = ""
var _anchor_version: int = -1
var _due: int = -1
var _llm_due: int = -1
var _llm_busy: bool = false
## Sube con cada pedido y cada cancelación: la respuesta de un pedido cancelado se ignora aunque el
## número de secuencia no haya cambiado todavía (`dismiss` cancela antes de que `_sync` lo suba).
var _llm_token: int = 0
var _last_change: int = 0
var _seq: int = 0
var _seen_line: int = -1
var _seen_column: int = -1
var _seen_version: int = -1
var _seen_line_text: String = ""
var _line_edited: bool = false
var _buffer_dirty_since: int = -1


func attach(p_code_edit: CodeEdit, p_path: String) -> void:
	code_edit = p_code_edit
	path = p_path
	code_edit.text_changed.connect(_sync)
	code_edit.caret_changed.connect(_sync)
	code_edit.focus_exited.connect(_on_focus_exited)
	code_edit.gui_input.connect(_on_gui_input)
	code_edit.draw.connect(_on_draw)
	_remember_state()


func detach() -> void:
	if code_edit == null:
		return
	if is_instance_valid(code_edit):
		for connection: Array in [[code_edit.text_changed, _sync], [code_edit.caret_changed, _sync], [code_edit.focus_exited, _on_focus_exited], [code_edit.gui_input, _on_gui_input], [code_edit.draw, _on_draw]]:
			var sig: Signal = connection[0]
			if sig.is_connected(connection[1]):
				sig.disconnect(connection[1])
		if not suggestion.is_empty():
			code_edit.queue_redraw()
	if renderer:
		renderer.release()
	if provider:
		provider.cancel()
	_cancel_llm()
	suggestion = ""
	code_edit = null


func is_visible() -> bool:
	return not suggestion.is_empty()


func is_pending() -> bool:
	return _due >= 0


## Dispara el pedido si venció el debounce, y avisa si el buffer quedó quieto. Una vez por frame.
func tick(now: int) -> void:
	if code_edit == null:
		return
	if _due >= 0 and now >= _due:
		_due = -1
		request(false)
	if _llm_due >= 0 and now >= _llm_due:
		_llm_due = -1
		if suggestion.is_empty() and can_trigger(false):
			request_llm(false)
	if _buffer_dirty_since >= 0 and now - _buffer_dirty_since >= BUFFER_IDLE_MS:
		_buffer_dirty_since = -1
		buffer_idle.emit(path, code_edit.text, code_edit.get_caret_line())


## Pide una sugerencia ya. `manual` (Alt+\) ignora la condición de fin de línea.
func request(manual: bool) -> void:
	if not can_trigger(manual):
		return
	if _uses_llm() and (mode == MODE_LLM or manual):
		_seq += 1
		request_llm(manual)
		return
	_seq += 1
	var seq := _seq
	var line := code_edit.get_caret_line()
	var column := code_edit.get_caret_column()
	var version := code_edit.get_version()
	var request_data := build_request(line, column)
	request_data.manual = manual
	request_data.seq = seq
	var key := SuggestionCache.key_for(request_data, provider.cache_generation())
	var cached := cache.lookup(key)
	var result: CompletionResult
	if cached.found:
		result = (cached.result as CompletionResult).cached_copy() if cached.result else null
	else:
		result = await provider.complete(request_data)
		# Respuesta vieja: llegó otra tecla, se movió el caret o se pidió otra cosa.
		if seq != _seq or code_edit == null:
			return
		cache.store(key, result)
	if seq != _seq or code_edit == null:
		return
	if code_edit.get_version() != version or code_edit.get_caret_line() != line or code_edit.get_caret_column() != column:
		return
	if result:
		show(result)
	elif _uses_llm() and mode == MODE_HYBRID:
		# Nada local: el LLM, con su debounce desde la última tecla (lo local ya se mostró o no hay).
		_llm_due = maxi(int(clock.call()), _last_change + llm_debounce_ms)


## Pide al LLM. Usa el número de secuencia actual: cualquier cambio desde acá lo invalida (y
## `_sync` cancela la request). La respuesta no reemplaza una sugerencia visible.
func request_llm(manual: bool) -> void:
	if llm_provider == null or code_edit == null:
		return
	_cancel_llm()
	_llm_token += 1
	var token := _llm_token
	var seq := _seq
	var line := code_edit.get_caret_line()
	var column := code_edit.get_caret_column()
	var version := code_edit.get_version()
	var request_data := build_request(line, column)
	request_data.manual = manual
	request_data.seq = seq
	var key := "llm|" + SuggestionCache.key_for(request_data, llm_provider.cache_generation())
	var cached := cache.lookup(key)
	var result: CompletionResult
	if cached.found:
		result = (cached.result as CompletionResult).cached_copy() if cached.result else null
	else:
		_llm_busy = true
		llm_started.emit()
		var started := Time.get_ticks_usec()
		result = await llm_provider.complete(request_data)
		var latency_ms := (Time.get_ticks_usec() - started) / 1000.0
		if token != _llm_token or seq != _seq or code_edit == null:
			return  # cancelada (`_cancel_llm` ya avisó) o vieja
		_llm_busy = false
		var error := str(llm_provider.get(&"last_error")) if &"last_error" in llm_provider else ""
		llm_finished.emit("error" if not error.is_empty() else "done", result, error, latency_ms)
		if error.is_empty():
			cache.store(key, result)
	if result == null or seq != _seq or code_edit == null or not suggestion.is_empty():
		return
	if code_edit.get_version() != version or code_edit.get_caret_line() != line or code_edit.get_caret_column() != column:
		return
	show(result)


func is_llm_busy() -> bool:
	return _llm_busy


func _uses_llm() -> bool:
	return llm_provider != null and mode != MODE_LOCAL


## Corta la request LLM en vuelo (y la programada).
func _cancel_llm() -> void:
	_llm_due = -1
	if _llm_busy:
		_llm_busy = false
		_llm_token += 1
		llm_provider.cancel()
		llm_finished.emit("cancelled", null, "", 0.0)


## El pedido con las líneas de contexto leídas del CodeEdit (sin partir el buffer).
func build_request(line: int, column: int) -> CompletionRequest:
	var above := PackedStringArray()
	for i in range(maxi(0, line - CompletionRequest.CONTEXT_ABOVE), line):
		above.append(code_edit.get_line(i))
	var below := PackedStringArray()
	for i in range(line + 1, mini(code_edit.get_line_count(), line + 1 + CompletionRequest.CONTEXT_BELOW)):
		below.append(code_edit.get_line(i))
	var request_data: CompletionRequest = CompletionRequest.from_lines(path, code_edit.text, line, column, code_edit.get_line(line), above, below)
	request_data.indent_spaces = code_edit.indent_use_spaces
	request_data.indent_size = code_edit.indent_size
	return request_data


## Condiciones de disparo (spec §16.5).
func can_trigger(manual: bool) -> bool:
	if not enabled or code_edit == null or provider == null or path.get_extension() != "gd":
		return false
	if code_edit.has_selection() or code_edit.get_caret_count() > 1 or native_popup_open():
		return false
	if manual:
		return true
	var rest := code_edit.get_line(code_edit.get_caret_line()).substr(code_edit.get_caret_column())
	for c: String in rest:
		if not (c == " " or c == "\t" or CLOSERS.contains(c)):
			return false
	return true


func native_popup_open() -> bool:
	return code_edit != null and code_edit.get_code_completion_selected_index() != -1


func show(result: CompletionResult) -> void:
	_result = result
	suggestion = result.text
	renderer.marked = llm_marker and result.source == CompletionResult.SOURCE_LLM
	_anchor_line = code_edit.get_caret_line()
	_anchor_column = code_edit.get_caret_column()
	var line := code_edit.get_line(_anchor_line)
	_anchor_prefix = line.left(_anchor_column)
	_anchor_suffix = line.substr(_anchor_column)
	_anchor_version = code_edit.get_version()
	code_edit.queue_redraw()
	shown.emit(result)


## Tab: inserta la sugerencia en una sola acción de undo y la suma al historial.
func accept() -> bool:
	if suggestion.is_empty() or code_edit == null:
		return false
	var text := suggestion
	var result := _result
	_clear()
	code_edit.begin_complex_operation()
	code_edit.insert_text_at_caret(text, 0)
	code_edit.end_complex_operation()
	if history:
		history.record(code_edit.get_line(code_edit.get_caret_line()))
	finished.emit(result, "accepted")
	return true


## Ctrl+→: inserta la siguiente palabra de la sugerencia (con los espacios o el salto de línea que
## la preceden) y deja el resto a la vista.
func accept_word() -> bool:
	if suggestion.is_empty() or code_edit == null:
		return false
	var word := next_word(suggestion)
	if word.length() >= suggestion.length():
		return accept()
	code_edit.begin_complex_operation()
	code_edit.insert_text_at_caret(word, 0)
	code_edit.end_complex_operation()
	suggestion = suggestion.substr(word.length())
	# El ancla pasa al caret nuevo (puede ser otra línea si la palabra traía un salto).
	_anchor_line = code_edit.get_caret_line()
	_anchor_column = code_edit.get_caret_column()
	var line := code_edit.get_line(_anchor_line)
	_anchor_prefix = line.left(_anchor_column)
	_anchor_suffix = line.substr(_anchor_column)
	_anchor_version = code_edit.get_version()
	code_edit.queue_redraw()
	accepted_partial.emit(_result)
	return true


## La siguiente palabra: espacios (o saltos de línea) y después un identificador o una tira de
## signos.
static func next_word(text: String) -> String:
	var i := 0
	while i < text.length() and (text[i] == " " or text[i] == "\t" or text[i] == "\n"):
		i += 1
	if i >= text.length():
		return text
	var word := _is_word_char(text.unicode_at(i))
	while i < text.length() and text[i] != " " and text[i] != "\t" and text[i] != "\n" and _is_word_char(text.unicode_at(i)) == word:
		i += 1
	return text.left(i)


static func _is_word_char(c: int) -> bool:
	return c == 95 or (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c > 127


func dismiss(reason: String) -> void:
	_due = -1
	_cancel_llm()
	if suggestion.is_empty():
		return
	var result := _result
	_clear()
	finished.emit(result, "discarded:" + reason)


func _clear() -> void:
	suggestion = ""
	_result = null
	_anchor_line = -1
	if code_edit:
		code_edit.queue_redraw()


func _remember_state() -> void:
	_seen_line = code_edit.get_caret_line()
	_seen_column = code_edit.get_caret_column()
	_seen_version = code_edit.get_version()
	_seen_line_text = code_edit.get_line(_seen_line)


## text_changed y caret_changed llegan diferidos y en cualquier orden: se compara contra el último
## estado visto, así cada cambio se procesa una vez.
func _sync() -> void:
	if code_edit == null:
		return
	var line := code_edit.get_caret_line()
	var column := code_edit.get_caret_column()
	var version := code_edit.get_version()
	if line == _seen_line and column == _seen_column and version == _seen_version:
		return
	var text_changed := version != _seen_version
	var line_changed := line != _seen_line
	if line_changed:
		if _line_edited and history:
			history.record(_seen_line_text)
		_line_edited = false
	if text_changed:
		_buffer_dirty_since = clock.call()
		_last_change = int(clock.call())
		if not line_changed:
			_line_edited = true
	_seen_line = line
	_seen_column = column
	_seen_version = version
	_seen_line_text = code_edit.get_line(line)

	if not suggestion.is_empty() and _type_through(line, column):
		return
	if not suggestion.is_empty():
		dismiss("line" if line_changed else ("typed" if text_changed else "moved"))
	_due = -1
	_seq += 1  # invalida una respuesta en vuelo
	_cancel_llm()
	if text_changed and enabled:
		_due = int(clock.call()) + (llm_debounce_ms if _uses_llm() and mode == MODE_LLM else debounce_ms)


## Si lo nuevo es exactamente el comienzo de la sugerencia, lo consume sin pedir otra (spec §16.5).
func _type_through(line: int, column: int) -> bool:
	if line != _anchor_line or column < _anchor_column:
		return false
	var current := code_edit.get_line(line)
	if current.left(_anchor_column) != _anchor_prefix or current.substr(column) != _anchor_suffix:
		return false
	var typed := current.substr(_anchor_column, column - _anchor_column)
	if not suggestion.begins_with(typed):
		return false
	suggestion = suggestion.substr(typed.length())
	_anchor_column = column
	_anchor_prefix = current.left(column)
	_anchor_version = code_edit.get_version()
	if suggestion.is_empty():
		var result := _result
		_clear()
		finished.emit(result, "typed_through")
	else:
		code_edit.queue_redraw()
	return true


func _on_focus_exited() -> void:
	dismiss("focus")


## Teclas (spec §16.7): solo se interceptan con sugerencia visible y el popup nativo cerrado; si no,
## Tab, Ctrl+→ y Esc siguen su camino normal. La señal gui_input llega antes que el manejo propio del
## CodeEdit, así que `accept_event()` alcanza para que Tab no indente.
func _on_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	# Una tecla anterior del mismo frame ya cambió el texto, pero sus señales diferidas no llegaron:
	# sin esto, Tab aceptaría la sugerencia vieja después de lo tipeado.
	_sync()
	if is_manual_shortcut(key):
		# Solo se consume si de verdad se puede pedir (si no, la tecla es del usuario).
		if can_trigger(true):
			code_edit.accept_event()
			dismiss("manual")
			request(true)
		return
	if suggestion.is_empty() or native_popup_open():
		return
	# Con selección o varios carets, Tab indenta (o lo que sea): nunca reemplaza con el ghost text.
	if code_edit.has_selection() or code_edit.get_caret_count() > 1:
		dismiss("selection")
		return
	if key.keycode == KEY_TAB and not (key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed):
		code_edit.accept_event()
		accept()
	elif key.keycode == KEY_RIGHT and key.is_command_or_control_pressed() and not (key.shift_pressed or key.alt_pressed):
		code_edit.accept_event()
		accept_word()
	elif key.keycode == KEY_ESCAPE:
		code_edit.accept_event()
		dismiss("esc")


## Atajo para pedir sugerencia a mano (default Alt+\).
static func is_manual_shortcut(key: InputEventKey) -> bool:
	return key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed and key.keycode == KEY_BACKSLASH


## Solo con el caret y el texto como cuando se mostró: `draw` puede llegar antes que las señales
## diferidas de la última tecla, y ese frame el ghost text quedaría corrido.
func _on_draw() -> void:
	if suggestion.is_empty() or native_popup_open() or code_edit.has_selection() or code_edit.get_caret_count() > 1:
		renderer.clear()
		return
	if code_edit.get_caret_line() != _anchor_line or code_edit.get_caret_column() != _anchor_column or code_edit.get_version() != _anchor_version:
		renderer.clear()
		return
	renderer.draw(code_edit, suggestion, _anchor_line, _anchor_column, _anchor_suffix)
