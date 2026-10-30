extends Node
## Autoload de playtest: corre dentro del juego lanzado por el harness.
## Aislado a propósito: sin class_name y sin referencias a scripts @tool del addon, para que cargarlo
## no arrastre código de editor (spec §6, punto 5). Solo precarga los scripts de esta carpeta.
## Habla con el editor por el canal del debugger, prefijo `godot_agent:`:
## - juego → editor: `ready` [versión], `frame` [png], `inputs_done` [cantidad], `problem` [texto],
##   `reply` [id, {text} o {error}], `finding` [{detector, summary, signature, …}] y `finding_frame`
##   [firma, png] (m15-07, m15-08), `film_frame` [n, t, jpeg] (m15-22).
## - editor → juego: `capture` [lado máximo], `inputs` [[paso, …]], `request` [id, op, params]
##   con op tree, get, set, call, wait, input, find, ui, ui_act, script, pause, step, watch, film u
##   opening, y `quit` (cierra el juego por su cuenta: así el Movie Maker termina de escribir el video).

const Detectors := preload("detectors.gd")
const GameUi := preload("game_ui.gd")
const GameWorld := preload("game_world.gd")
const ScriptKit := preload("script_kit.gd")
const Watcher := preload("watcher.gd")
const Film := preload("film.gd")

const PREFIX := "godot_agent"
const PROTOCOL := 3
const TREE_DEPTH := 4
const TREE_LIMIT := 300
const VALUE_LIMIT := 300
const WAIT_MAX_S := 60.0
const SCRIPT_MAX_S := 60.0
const WATCH_MAX_S := 60.0
const STEP_MAX_FRAMES := 60 * 60
const FINDING_FRAME_SIDE := 640
## Entre dos capturas automáticas de un hallazgo (m15-08).
const FINDING_FRAME_GAP_MS := 5000
## Propiedades que `get` muestra cuando no se piden nombres (además de las variables del script).
const SUMMARY_PROPERTIES: PackedStringArray = ["position", "global_position", "rotation", "scale", "velocity", "linear_velocity", "visible", "text", "value", "modulate"]

## Señales esperadas por `wait`: id → argumentos recibidos.
var _signal_hits: Dictionary = {}
var _next_wait: int = 0
var _detectors := Detectors.new()
var _film: Film
var _ui: GameUi
var _last_frame_ms: int = 0
var _finding_frame_at: int = -FINDING_FRAME_GAP_MS
## Último lugar del mouse: de ahí sale el `relative` de un movimiento a un punto.
var _mouse_at := Vector2.ZERO


func _ready() -> void:
	if not OS.has_feature("editor_runtime") or not EngineDebugger.is_active():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_film = Film.new(self)
	_ui = GameUi.new(self)
	_last_frame_ms = Time.get_ticks_msec()
	EngineDebugger.register_message_capture(PREFIX, _on_message)
	EngineDebugger.send_message(PREFIX + ":ready", [PROTOCOL])


func _exit_tree() -> void:
	if EngineDebugger.is_active() and EngineDebugger.has_capture(PREFIX):
		EngineDebugger.unregister_message_capture(PREFIX)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_dt := (now - _last_frame_ms) / 1000.0
	_last_frame_ms = now
	_detectors.tick(self, _on_finding, real_dt)
	_film.tick(now / 1000.0, now / 1000.0, _send_film_frame)


func _send_film_frame(number: int, game_time: float, jpeg: PackedByteArray) -> void:
	EngineDebugger.send_message(PREFIX + ":film_frame", [number, game_time, jpeg])


## Un hallazgo: al editor, con una foto del momento salvo que acaba de sacar otra (m15-08).
func _on_finding(finding: Dictionary) -> void:
	finding.t = Time.get_ticks_msec() / 1000.0
	EngineDebugger.send_message(PREFIX + ":finding", [finding])
	var now := Time.get_ticks_msec()
	if int(finding.count) == 1 and now - _finding_frame_at >= FINDING_FRAME_GAP_MS and Film.no_picture().is_empty():
		_finding_frame_at = now
		_send_finding_frame(str(finding.signature))


func _send_finding_frame(signature: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var longest := maxi(image.get_width(), image.get_height())
	if longest > FINDING_FRAME_SIDE:
		var scale := float(FINDING_FRAME_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	EngineDebugger.send_message(PREFIX + ":finding_frame", [signature, image.save_png_to_buffer()])


func _on_message(message: String, data: Array) -> bool:
	match message.trim_prefix(PREFIX + ":"):
		"capture":
			_send_frame(int(data[0]) if not data.is_empty() else 1280)
		"inputs":
			_play_and_report(data[0] if not data.is_empty() and data[0] is Array else [])
		"request":
			if data.size() >= 3:
				_answer(int(data[0]), str(data[1]), data[2] if data[2] is Dictionary else {})
		"quit":
			get_tree().quit()
		_:
			return false
	return true


func _send_frame(max_side: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		EngineDebugger.send_message(PREFIX + ":problem", ["Could not read the viewport frame."])
		return
	var longest := maxi(image.get_width(), image.get_height())
	if max_side > 0 and longest > max_side:
		var scale := float(max_side) / longest
		image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
	EngineDebugger.send_message(PREFIX + ":frame", [image.save_png_to_buffer(), image.get_width(), image.get_height()])


# --- pedidos con respuesta -----------------------------------------------------------------------

func _answer(id: int, op: String, params: Dictionary) -> void:
	var result: Dictionary
	match op:
		"tree":
			result = _tree(params)
		"get":
			result = _get_values(params)
		"set":
			result = _set_values(params)
		"call":
			result = _call_method(params)
		"wait":
			result = await _wait(params)
		"input":
			var steps: Array = params.get("steps") if params.get("steps") is Array else []
			var played: int = await _play_inputs(steps, int(params.get("settle_frames", 0)))
			result = {"text": "Inputs: %d of %d played%s." % [played, steps.size(), " (by physics frame)" if _by_frame(steps) else ""]}
		"find":
			result = _find(params)
		"ui":
			result = {"text": _ui_text()}
		"ui_act":
			result = _ui.act(params)
		"script":
			result = await _run_script(params)
		"pause":
			get_tree().paused = params.get("paused") == true
			result = {"text": "The game is %s." % ("paused: it only advances with game_step" if get_tree().paused else "running")}
		"step":
			result = await _step(params)
		"watch":
			result = await _watch(params)
		"film":
			result = _film_op(params)
		"opening":
			result = {"text": _opening()}
		_:
			result = {"error": "Unknown request '%s'." % op}
	if result.has("text"):
		result.text = "%s\n[game time %.2f s, physics frame %d%s]" % [result.text, Time.get_ticks_msec() / 1000.0, Engine.get_physics_frames(), ", paused" if get_tree().paused else ""]
	EngineDebugger.send_message(PREFIX + ":reply", [id, result])


func _find(params: Dictionary) -> Dictionary:
	var lines: PackedStringArray = []
	for node: Node in GameWorld.find(get_tree(), params, self):
		lines.append("%s (%s)" % [node.get_path(), node.get_class()])
	return {"text": "\n".join(lines) if not lines.is_empty() else "No node matches."}


func _ui_text() -> String:
	var texts: PackedStringArray = []
	var on_screen := _ui.texts()
	for key: String in on_screen:
		texts.append("%s: %s" % [key, JSON.stringify(str(on_screen[key]).left(120))])
	var controls := _ui.list()
	return "Controls (use the id with game_ui_act):\n%s\nTexts on screen:\n%s" % ["\n".join(controls) if not controls.is_empty() else "(none)", "\n".join(texts) if not texts.is_empty() else "(none)"]


## Lo primero que se busca al empezar: escena, jugador, controles y qué hay en pantalla (m15-10).
func _opening() -> String:
	var body := GameWorld.player(get_tree())
	var actions: PackedStringArray = []
	for action: StringName in InputMap.get_actions():
		if not str(action).begins_with("ui_"):
			var keys: PackedStringArray = []
			for event: InputEvent in InputMap.action_get_events(action):
				keys.append(event.as_text().get_slice(" (", 0))
			actions.append("%s (%s)" % [action, ", ".join(keys)])
	return "Scene: %s\nPlayer: %s\nInput actions: %s\n%s" % [_scene_path(), body.get_path() if body else "(none: a menu?)", ", ".join(actions) if not actions.is_empty() else "(only the built-in ui_*)", _ui_text()]


## Corre un script del agente adentro del juego (m15-12). Vencido el tiempo, sus esperas no vuelven.
func _run_script(params: Dictionary) -> Dictionary:
	var timeout := clampf(float(params.get("timeout", 10.0)), 0.1, SCRIPT_MAX_S)
	var errors := ScriptKit.ScriptErrors.new()
	OS.add_logger(errors)
	var script := GDScript.new()
	var code := str(params.get("code", ""))
	script.source_code = code if code.begins_with("extends ") else "extends RefCounted\n" + code
	var compiled := script.reload()
	if compiled != OK or not script.can_instantiate():
		OS.remove_logger(errors)
		return {"error": "The script does not compile (the first line of your code is line 2 unless it starts with `extends`).\n%s" % "\n".join(errors.lines)}
	var instance: Variant = script.new()
	if not (instance as Object).has_method(&"run"):
		OS.remove_logger(errors)
		return {"error": "The script needs a `func run(game):`."}
	var kit := ScriptKit.new(self)
	var state := {"done": false, "value": null}
	_drive_script(instance, kit, state)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not state.done and not errors.fatal and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	kit.aborted = not state.done
	kit.release_all()
	OS.remove_logger(errors)
	var lines := kit.lines
	lines.append_array(errors.lines)
	if errors.fatal:
		lines.append("The script stopped on an error; the keys it held were let go.")
	elif not state.done:
		lines.append("The script timed out after %.1f s; the keys it held were let go." % timeout)
		get_tree().paused = true
		lines.append("The game was paused where it stood: game_pause to let it run.")
	else:
		lines.append("run() returned: %s" % _format(state.value))
	return {"text": "\n".join(lines)}


func _drive_script(instance: Variant, kit: ScriptKit, state: Dictionary) -> void:
	state.value = await instance.run(kit)
	state.done = true


## Avanza N frames de física con el juego corriendo, con inputs por frame, y lo deja en pausa (m15-13).
func _step(params: Dictionary) -> Dictionary:
	var steps: Array = params.get("steps") if params.get("steps") is Array else []
	var frames := clampi(int(params.get("frames", 1)), 0, STEP_MAX_FRAMES)
	for step: Variant in steps:
		frames = maxi(frames, int(step.get("frame", 0)) + 1)
	var start := Engine.get_physics_frames()
	get_tree().paused = false
	var played: int = 0
	if not steps.is_empty():
		played = await _play_inputs(steps)
	# La señal sale antes de procesar los nodos: pausar en la siguiente deja justo `frames` procesados.
	while Engine.get_physics_frames() - start <= frames:
		await get_tree().physics_frame
	get_tree().paused = true
	return {"text": "Advanced %d physics frames with %d input events; paused again." % [Engine.get_physics_frames() - start - 1, played]}


## Mira unos nodos cada frame durante `seconds`, opcionalmente con inputs en el medio (m15-20).
func _watch(params: Dictionary) -> Dictionary:
	var nodes: Array[Node] = []
	for path: Variant in params.get("paths", []):
		var found: Variant = _node(str(path))
		if found is String:
			return {"error": found}
		nodes.append(found)
	var seconds := clampf(float(params.get("seconds", 2.0)), 0.05, WATCH_MAX_S)
	var watcher := Watcher.new()
	watcher.start(nodes, PackedStringArray(params.get("properties", [])))
	var steps: Variant = params.get("steps")
	if steps is Array and not (steps as Array).is_empty():
		_play_inputs(steps)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		watcher.tick()
	return {"text": watcher.report()}


func _film_op(params: Dictionary) -> Dictionary:
	if params.get("stop") == true:
		_film.stop()
		return {"text": "Filming stopped."}
	var why := Film.no_picture()
	if not why.is_empty():
		return {"error": "Cannot film: %s." % why}
	_film.start(float(params.get("fps", 4.0)))
	return {"text": "Filming."}


func _tree(params: Dictionary) -> Dictionary:
	var found: Variant = _node(str(params.get("path", "")))
	if found is String:
		return {"error": found}
	var lines: PackedStringArray = []
	_tree_lines(found, 0, clampi(int(params.get("depth", TREE_DEPTH)), 0, 32), lines)
	if lines.size() > TREE_LIMIT:
		lines = lines.slice(0, TREE_LIMIT)
		lines.append("(… more nodes: pass a deeper `path` or a smaller `depth`)")
	var header := "Live tree of %s (current scene: %s, paused: %s)" % [(found as Node).get_path(), _scene_path(), get_tree().paused]
	return {"text": header + "\n" + "\n".join(lines)}


func _tree_lines(node: Node, level: int, depth: int, lines: PackedStringArray) -> void:
	if lines.size() > TREE_LIMIT or node == self:
		return
	var text := "%s%s (%s)" % ["  ".repeat(level), node.name, node.get_class()]
	var script := node.get_script() as Script
	if script:
		text += " [%s]" % (script.resource_path.get_file() if not script.resource_path.is_empty() else "script")
	for property: String in ["position", "text"]:
		if property in node:
			text += " %s=%s" % [property, _format(node.get(property))]
	if "visible" in node and not node.get("visible"):
		text += " hidden"
	lines.append(text)
	if level >= depth:
		if node.get_child_count() > 0:
			lines.append("%s  (… %d children)" % ["  ".repeat(level), node.get_child_count()])
		return
	for child: Node in node.get_children():
		_tree_lines(child, level + 1, depth, lines)


func _get_values(params: Dictionary) -> Dictionary:
	var found: Variant = _node(str(params.get("path", "")))
	if found is String:
		return {"error": found}
	var node: Node = found
	var names: Array = params.get("properties") if params.get("properties") is Array else []
	if names.is_empty():
		var script := node.get_script() as Script
		if script:
			for info: Dictionary in script.get_script_property_list():
				if int(info.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
					names.append(info.name)
		for property: String in SUMMARY_PROPERTIES:
			if property in node:
				names.append(property)
	var lines: PackedStringArray = ["%s (%s)" % [node.get_path(), node.get_class()]]
	for name: Variant in names:
		var property := str(name)
		if not _has_property(node, property):
			lines.append("  %s: (no such property)" % property)
		else:
			lines.append("  %s = %s" % [property, _format(node.get_indexed(NodePath(property)))])
	return {"text": "\n".join(lines)}


func _set_values(params: Dictionary) -> Dictionary:
	var found: Variant = _node(str(params.get("path", "")))
	if found is String:
		return {"error": found}
	var node: Node = found
	var values: Dictionary = params.get("properties") if params.get("properties") is Dictionary else {}
	var changes: Array = []
	for name: Variant in values:
		var property := str(name)
		if not _has_property(node, property):
			return {"error": "%s has no property '%s'." % [node.get_path(), property]}
		var before: Variant = node.get_indexed(NodePath(property))
		var converted := _convert(values[name], typeof(before), before)
		if converted.has("error"):
			return {"error": "%s: %s" % [property, converted.error]}
		changes.append([property, before, converted.value])
	var lines: PackedStringArray = []
	for change: Array in changes:
		node.set_indexed(NodePath(change[0]), change[2])
		lines.append("  %s: %s → %s" % [change[0], _format(change[1]), _format(node.get_indexed(NodePath(change[0])))])
	return {"text": "%s (live only, the scene file is not changed):\n%s" % [node.get_path(), "\n".join(lines)]}


func _call_method(params: Dictionary) -> Dictionary:
	var found: Variant = _node(str(params.get("path", "")))
	if found is String:
		return {"error": found}
	var node: Node = found
	var method := str(params.get("method", ""))
	if not node.has_method(method):
		return {"error": "%s (%s) has no method '%s'." % [node.get_path(), node.get_class(), method]}
	var raw: Array = params.get("args") if params.get("args") is Array else []
	var types: Array = []
	for info: Dictionary in node.get_method_list():
		if info.name == method:
			for arg: Dictionary in info.args:
				types.append(int(arg.type))
			break
	var args: Array = []
	for i: int in raw.size():
		var converted := _convert(raw[i], types[i] if i < types.size() else TYPE_NIL, null)
		if converted.has("error"):
			return {"error": "argument %d: %s" % [i + 1, converted.error]}
		args.append(converted.value)
	var result: Variant = node.callv(method, args)
	var shown: PackedStringArray = []
	for arg: Variant in args:
		shown.append(_format(arg))
	return {"text": "%s.%s(%s) → %s" % [node.get_path(), method, ", ".join(shown), _format(result)]}


## Espera una condición (Expression sobre el nodo), una señal del nodo o simplemente `timeout`.
func _wait(params: Dictionary) -> Dictionary:
	var timeout := clampf(float(params.get("timeout", 5.0)), 0.0, WAIT_MAX_S)
	var found: Variant = _node(str(params.get("path", "")))
	if found is String:
		return {"error": found}
	var node: Node = found
	var started := Time.get_ticks_msec()
	var deadline := started + int(timeout * 1000.0)
	var condition := str(params.get("condition", ""))
	var signal_name := str(params.get("signal", ""))
	if not condition.is_empty():
		var expression := Expression.new()
		if expression.parse(condition) != OK:
			return {"error": "Could not parse the condition: %s" % expression.get_error_text()}
		while true:
			var value: Variant = expression.execute([], node, false)
			if expression.has_execute_failed():
				return {"error": "The condition failed on %s: %s" % [node.get_path(), expression.get_error_text()]}
			if value:
				return {"text": "`%s` became true after %.2f s." % [condition, _elapsed(started)]}
			if Time.get_ticks_msec() >= deadline:
				return {"text": "Timed out after %.1f s: `%s` is still %s.%s" % [timeout, condition, _format(value), " The game is paused: it does not advance while you wait (game_step, or game_pause)." if get_tree().paused else ""]}
			await get_tree().process_frame
	if not signal_name.is_empty():
		if not node.has_signal(signal_name):
			return {"error": "%s (%s) has no signal '%s'." % [node.get_path(), node.get_class(), signal_name]}
		var wait_id := _next_wait
		_next_wait += 1
		var handler := _on_awaited_signal.bind(wait_id)
		node.connect(signal_name, handler)
		while not _signal_hits.has(wait_id) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if is_instance_valid(node) and node.is_connected(signal_name, handler):
			node.disconnect(signal_name, handler)
		if not _signal_hits.has(wait_id):
			return {"text": "Timed out after %.1f s: '%s' was not emitted." % [timeout, signal_name]}
		var shown: PackedStringArray = []
		for arg: Variant in _signal_hits[wait_id]:
			shown.append(_format(arg))
		_signal_hits.erase(wait_id)
		return {"text": "'%s' was emitted after %.2f s%s." % [signal_name, _elapsed(started), " with (%s)" % ", ".join(shown) if not shown.is_empty() else ""]}
	await get_tree().create_timer(timeout, true, false, true).timeout
	return {"text": "Waited %.1f s." % timeout}


func _on_awaited_signal(...args: Array) -> void:
	var wait_id: int = args.pop_back()
	if not _signal_hits.has(wait_id):
		_signal_hits[wait_id] = args


# --- inputs ----------------------------------------------------------------------------------------

func _play_and_report(steps: Array) -> void:
	var played: int = await _play_inputs(steps)
	EngineDebugger.send_message(PREFIX + ":inputs_done", [played])


## Pasos `{t: segundos desde ahora, kind, pressed, …}` reproducidos con Input.parse_input_event.
## kind: action (action, strength), key (keycode y ctrl/shift/alt/meta), mouse_button (button, x, y),
## mouse_motion (x, y), joy_button (button), joy_axis (axis, value). Sin kind es una acción.
## Con `frame` en vez de `t` (m14-01) cada paso sale en ese frame de física contado desde ahora: la
## misma secuencia da lo mismo a cualquier framerate. `settle_frames`: frames de espera al final.
func _play_inputs(steps: Array, settle_frames: int = 0) -> int:
	var ordered := steps.filter(func(step: Variant) -> bool: return step is Dictionary)
	var by_frame := _by_frame(ordered)
	var key := "frame" if by_frame else "t"
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get(key, 0.0)) < float(b.get(key, 0.0)))
	var start_frame := Engine.get_physics_frames()
	var elapsed := 0.0
	var played := 0
	for step: Dictionary in ordered:
		if by_frame:
			while Engine.get_physics_frames() - start_frame < int(step.get("frame", 0)):
				await get_tree().physics_frame
		else:
			var wait := float(step.get("t", 0.0)) - elapsed
			if wait > 0.0:
				await get_tree().create_timer(wait, true, false, true).timeout
				elapsed += wait
		var event: Variant = _event(step)
		if event is String:
			EngineDebugger.send_message(PREFIX + ":problem", [event])
			continue
		Input.parse_input_event(event)
		played += 1
	for _frame in maxi(settle_frames, 0):
		await get_tree().physics_frame
	return played


static func _by_frame(steps: Array) -> bool:
	return steps.any(func(step: Variant) -> bool: return step is Dictionary and step.has("frame"))


func _event(step: Dictionary) -> Variant:
	var pressed := bool(step.get("pressed", true))
	match str(step.get("kind", "action")):
		"action":
			var action := StringName(str(step.get("action", "")))
			if not InputMap.has_action(action):
				return "The action '%s' does not exist in the game's InputMap." % action
			var event := InputEventAction.new()
			event.action = action
			event.pressed = pressed
			event.strength = float(step.get("strength", 1.0)) if pressed else 0.0
			return event
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(step.get("keycode", 0)) as Key
			key.keycode = key.physical_keycode
			key.ctrl_pressed = bool(step.get("ctrl", false))
			key.shift_pressed = bool(step.get("shift", false))
			key.alt_pressed = bool(step.get("alt", false))
			key.meta_pressed = bool(step.get("meta", false))
			key.pressed = pressed
			key.key_label = key.keycode
			if pressed and not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed):
				key.unicode = int(step.get("unicode", _unicode_of(key.keycode, key.shift_pressed)))
			return key
		"mouse_button":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(step.get("button", MOUSE_BUTTON_LEFT)) as MouseButton
			mouse.position = _point(step)
			mouse.global_position = mouse.position
			mouse.pressed = pressed
			if pressed and mouse.button_index <= MOUSE_BUTTON_MIDDLE:
				mouse.button_mask = (1 << (mouse.button_index - 1)) as MouseButtonMask
			return mouse
		"mouse_motion":
			var motion := InputEventMouseMotion.new()
			# `look` mueve la mira sin ir a un punto: lo que lee un juego en primera persona (m15-04).
			if step.has("rel_x"):
				motion.position = _mouse_at
				motion.relative = Vector2(float(step.rel_x), float(step.rel_y))
			else:
				motion.position = _point(step)
				motion.relative = motion.position - _mouse_at
				_mouse_at = motion.position
			motion.screen_relative = motion.relative
			motion.global_position = motion.position
			return motion
		"joy_button":
			var joy := InputEventJoypadButton.new()
			joy.button_index = int(step.get("button", 0)) as JoyButton
			joy.pressed = pressed
			joy.pressure = 1.0 if pressed else 0.0
			return joy
		"joy_axis":
			var axis := InputEventJoypadMotion.new()
			axis.axis = int(step.get("axis", 0)) as JoyAxis
			axis.axis_value = float(step.get("value", 1.0)) if pressed else 0.0
			return axis
	return "Unknown input kind '%s'." % step.get("kind")


## El carácter de una tecla, para que escriba en un LineEdit: sin esto el evento no teclea nada.
static func _unicode_of(keycode: int, shift: bool) -> int:
	if keycode == KEY_SPACE:
		return 32
	var text := OS.get_keycode_string(keycode as Key)
	if text.length() != 1:
		return 0
	return (text if shift else text.to_lower()).unicode_at(0)


static func _point(step: Dictionary) -> Vector2:
	return Vector2(float(step.get("x", 0.0)), float(step.get("y", 0.0)))


# --- utilidades ------------------------------------------------------------------------------------

## El nodo de `path` o el error: vacío o "." es la escena actual; relativo a ella, o absoluto (/root/…).
func _node(path: String) -> Variant:
	var tree := get_tree()
	var base: Node = tree.current_scene if tree.current_scene else tree.root
	if path.is_empty() or path == ".":
		return base
	var found := tree.root.get_node_or_null(path) if path.begins_with("/") else base.get_node_or_null(path)
	if found == null:
		return "No node at '%s' in the running game (relative to %s; game_tree shows the live tree)." % [path, base.get_path()]
	return found


func _scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene and not scene.scene_file_path.is_empty() else "(none)"


static func _has_property(object: Object, property: String) -> bool:
	var base := property.get_slice(":", 0)
	if base in object:
		return true
	for info: Dictionary in object.get_property_list():
		if info.name == base:
			return true
	return false


static func _elapsed(started: int) -> float:
	return (Time.get_ticks_msec() - started) / 1000.0


## Valor de JSON convertido al tipo de destino: {value} o {error}.
static func _convert(value: Variant, type: int, current: Variant) -> Dictionary:
	if value is String and type not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH, TYPE_NIL]:
		var text := str(value)
		if type == TYPE_COLOR and (text.begins_with("#") or Color.html_is_valid(text)):
			return {"value": Color.html(text)}
		if type == TYPE_OBJECT and text.begins_with("res://"):
			if not ResourceLoader.exists(text):
				return {"error": "%s does not exist" % text}
			return {"value": load(text)}
		var parsed: Variant = str_to_var(text)
		if parsed != null and typeof(parsed) == type:
			return {"value": parsed}
		if type in [TYPE_INT, TYPE_FLOAT] and text.is_valid_float() or type == TYPE_BOOL and text.to_lower() in ["true", "false"]:
			return {"value": type_convert(text.to_lower(), type) if type != TYPE_BOOL else text.to_lower() == "true"}
		return {"error": "cannot turn %s into %s (vectors are [x, y], colors \"#rrggbb\", constructors like \"Vector2(1, 2)\")" % [JSON.stringify(value).left(80), type_string(type)]}
	if value is Array:
		var items: Array = value
		match type:
			TYPE_VECTOR2:
				if items.size() == 2:
					return {"value": Vector2(items[0], items[1])}
			TYPE_VECTOR2I:
				if items.size() == 2:
					return {"value": Vector2i(items[0], items[1])}
			TYPE_VECTOR3:
				if items.size() == 3:
					return {"value": Vector3(items[0], items[1], items[2])}
			TYPE_VECTOR3I:
				if items.size() == 3:
					return {"value": Vector3i(items[0], items[1], items[2])}
			TYPE_VECTOR4:
				if items.size() == 4:
					return {"value": Vector4(items[0], items[1], items[2], items[3])}
			TYPE_COLOR:
				if items.size() in [3, 4]:
					return {"value": Color(items[0], items[1], items[2], items[3] if items.size() == 4 else 1.0)}
			TYPE_RECT2:
				if items.size() == 4:
					return {"value": Rect2(items[0], items[1], items[2], items[3])}
			TYPE_ARRAY, TYPE_NIL:
				if current is Array and (current as Array).is_typed():
					var typed: Array = (current as Array).duplicate()
					typed.clear()
					typed.assign(items)
					return {"value": typed}
				return {"value": items}
			TYPE_PACKED_STRING_ARRAY:
				return {"value": PackedStringArray(items)}
			TYPE_PACKED_INT32_ARRAY:
				return {"value": PackedInt32Array(items)}
			TYPE_PACKED_FLOAT32_ARRAY:
				return {"value": PackedFloat32Array(items)}
		return {"error": "cannot turn %s into %s (vectors are [x, y], colors \"#rrggbb\" or [r, g, b, a])" % [JSON.stringify(value).left(80), type_string(type)]}
	if type == TYPE_NIL or (type == TYPE_OBJECT and value == null):
		return {"value": value}
	if type == TYPE_INT and value is float and value != floorf(value):
		return {"error": "expected a whole number, got %s" % value}
	var converted: Variant = type_convert(value, type)
	if typeof(converted) != type:
		return {"error": "cannot turn %s into %s" % [JSON.stringify(value).left(80), type_string(type)]}
	return {"value": converted}


static func _format(value: Variant) -> String:
	if typeof(value) == TYPE_OBJECT:
		if not is_instance_valid(value):
			return "<freed object>"
		if value is Node:
			var node: Node = value
			return "<%s %s>" % [node.get_class(), node.get_path() if node.is_inside_tree() else node.name]
		if value is Resource:
			var resource: Resource = value
			return "<%s %s>" % [resource.get_class(), resource.resource_path if not resource.resource_path.is_empty() else "inline"]
		return "<%s>" % (value as Object).get_class()
	var text := var_to_str(value) if value is String or value is StringName else str(value)
	return text.left(VALUE_LIMIT) + ("…" if text.length() > VALUE_LIMIT else "")
