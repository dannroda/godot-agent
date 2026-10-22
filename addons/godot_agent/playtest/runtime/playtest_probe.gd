extends Node
## Autoload de playtest: corre dentro del juego lanzado por el harness.
## Aislado a propósito: sin preload, sin class_name y sin referencias a scripts @tool del addon,
## para que cargarlo no arrastre código de editor (spec §6, punto 5).
## Habla con el editor por el canal del debugger, prefijo `godot_agent:`:
## - juego → editor: `ready` [versión], `frame` [png], `inputs_done` [cantidad], `problem` [texto].
## - editor → juego: `capture` [lado máximo], `inputs` [[{t, action, pressed}, …]].

const PREFIX := "godot_agent"
const PROTOCOL := 1

func _ready() -> void:
	if not OS.has_feature("editor_runtime") or not EngineDebugger.is_active():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	EngineDebugger.register_message_capture(PREFIX, _on_message)
	EngineDebugger.send_message(PREFIX + ":ready", [PROTOCOL])


func _exit_tree() -> void:
	if EngineDebugger.is_active() and EngineDebugger.has_capture(PREFIX):
		EngineDebugger.unregister_message_capture(PREFIX)


func _on_message(message: String, data: Array) -> bool:
	match message.trim_prefix(PREFIX + ":"):
		"capture":
			_send_frame(int(data[0]) if not data.is_empty() else 1280)
		"inputs":
			_play_inputs(data[0] if not data.is_empty() and data[0] is Array else [])
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


## Pasos `{t: segundos desde ahora, action, pressed}` reproducidos con Input.parse_input_event.
func _play_inputs(steps: Array) -> void:
	var ordered := steps.filter(func(step: Variant) -> bool: return step is Dictionary and step.get("action") is String)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
	var elapsed := 0.0
	var played := 0
	for step: Dictionary in ordered:
		var wait := float(step.get("t", 0.0)) - elapsed
		if wait > 0.0:
			await get_tree().create_timer(wait, true, false, true).timeout
			elapsed += wait
		var action := StringName(step.action)
		if not InputMap.has_action(action):
			EngineDebugger.send_message(PREFIX + ":problem", ["The action '%s' does not exist in the game's InputMap." % action])
			continue
		var event := InputEventAction.new()
		event.action = action
		event.pressed = bool(step.get("pressed", true))
		event.strength = 1.0 if event.pressed else 0.0
		Input.parse_input_event(event)
		played += 1
	EngineDebugger.send_message(PREFIX + ":inputs_done", [played])
