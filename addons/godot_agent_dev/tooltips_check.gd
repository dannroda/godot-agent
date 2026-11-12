@tool
extends RefCounted
## ui-tooltips (m12-51) con el agente falso (tests/scripts/ui_tooltips.json): un turno largo que manda
## usage_update y la cuota del plan cada poco, como Claude Code mientras trabaja. Con el mouse quieto
## encima (y moviéndose de a un píxel, como una mano), el tooltip de cada control de la barra del
## composer (anillo de contexto, cuota, plan, modo, modelo, Detener/Enviar) y del encabezado (el chip
## del agente, la línea de estado, los chips de máquinas) tiene que seguir abierto HOLD_S segundos:
## antes se cerraba enseguida porque el texto se reescribía cada segundo (la antigüedad de los estados)
## o con cada usage_update, y Godot cierra el tooltip cuando, al mover el mouse, el texto cambió.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const LayoutCheck := preload("layout_check.gd")
## Angosto: la fila del composer se compacta (Enviar solo con el símbolo, sin el medidor…).
const NARROW_WIDTH := 300
const WIDE_WIDTH := 460
const MAIN_PLUGIN_SCRIPT := "res://addons/godot_agent/agent_plugin.gd"
## Lo que tiene que durar abierto: más que el tick de un segundo de los chips y la cuota.
const HOLD_S := 3.0
const WAIT_MS := 20000

var failures: Array[String] = []
var _tree: SceneTree


func run(tree: SceneTree, _plugin: Object, dock: Control, _shot_path: String) -> Array[String]:
	_tree = tree
	var model: Object = dock.get(&"_model")
	var composer: Control = dock.get(&"_composer")
	dock.get(&"_controller").call(&"send_prompt", "Trabajá un rato")  # sin await: se mide durante el turno
	# Esperar a que el turno esté en marcha y haya llegado el primer usage_update.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WAIT_MS and (int(model.get(&"usage_size")) <= 0 or int(model.get(&"state")) != SessionModel.SessionState.PROMPTING):
		await _tree.process_frame
	if int(model.get(&"usage_size")) <= 0:
		failures.append("no llegó el usage_update del agente falso")
		return failures
	composer.call(&"set_plan_available", true)  # la lista de tareas (☰) al lado del modo
	# Ancho para que la fila entre entera (el dock de Xvfb es angosto y compacta el medidor).
	var width := dock.size.x
	await LayoutCheck.set_dock_width(dock, WIDE_WIDTH)
	# El primer usage_update muestra el medidor y la fila se reacomoda: se mide con la fila quieta.
	await _tree.create_timer(1.0).timeout
	var targets: Array = [
		["anillo de contexto", composer.get(&"_meter")],
		["modo", composer.get(&"_mode_button")],
		["modelo", composer.get(&"_model_button")],
		["Detener", composer.get(&"_send_button")],
		["plan", composer.get(&"_plan_button")],
		["cuota", dock.get(&"_quota_ring")],
		["chip del agente", dock.get(&"_agent_chip")],
		["línea de estado", dock.get(&"_state_line")],
	]
	for target: Array in targets:
		await _check_hold(str(target[0]), target[1] as Control)
	# Lo mismo con el dock angosto, donde el medidor que cambia de ancho puede recompactar la fila.
	await LayoutCheck.set_dock_width(dock, NARROW_WIDTH)
	await _tree.create_timer(0.5).timeout
	for target: Array in targets.slice(1, 4):
		await _check_hold(str(target[0]) + " (dock angosto)", target[1] as Control)
	await LayoutCheck.set_dock_width(dock, int(width))
	# Al salir, el tooltip tiene lo último (lo que llegó con el mouse encima).
	var meter: Control = composer.get(&"_meter")
	await _tree.create_timer(0.8).timeout
	_expect(meter.tooltip_text.contains("%d%%" % int(100.0 * int(model.get(&"usage_used")) / int(model.get(&"usage_size")))), "al salir el mouse, el tooltip del anillo dice lo último · %s" % meter.tooltip_text)
	# Al final, con el turno terminado: Enviar.
	while Time.get_ticks_msec() - started < WAIT_MS * 3 and int(model.get(&"state")) == SessionModel.SessionState.PROMPTING:
		await _tree.process_frame
	await _check_hold("Enviar", composer.get(&"_send_button"))
	dock.call(&"_refresh_plan_button")
	return failures


## Pone el mouse sobre `control`, espera a que aparezca el tooltip y comprueba que siga abierto
## HOLD_S segundos mientras el mouse tiembla un píxel.
func _check_hold(label: String, control: Control) -> void:
	if control == null or not control.is_visible_in_tree() or (not control.has_method(&"is_hint_visible") and control.tooltip_text.is_empty()):
		print("[tooltips-check] (sin %s visible o sin tooltip: no se prueba)" % label)
		return
	var viewport := control.get_viewport()
	# Afuera primero, para que el próximo movimiento sea una entrada.
	_move(viewport, Vector2(4, 4))
	for i in 3:
		await _tree.process_frame
	var center := control.get_global_rect().get_center()
	_move(viewport, center)
	var delay := float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5))
	if Engine.is_editor_hint():
		delay = float(EditorInterface.get_editor_settings().get_setting("interface/editor/tooltip_delay_sec")) if EditorInterface.get_editor_settings().has_setting("interface/editor/tooltip_delay_sec") else delay
	var row_before := _row_dump(control)
	var appear := Time.get_ticks_msec()
	while _tooltip(control) == null and Time.get_ticks_msec() - appear < int((delay + 2.0) * 1000.0):
		await _tree.process_frame
	if _tooltip(control) == null:
		failures.append("el tooltip de %s no apareció (visible %s, mouse en %s, el control en %s, debajo %s, fila %s)" % [label, control.is_visible_in_tree(), center, control.get_global_rect(), viewport.gui_get_hovered_control(), _row_dump(control)])
		return
	var start := Time.get_ticks_msec()
	var wiggle := 0
	while Time.get_ticks_msec() - start < int(HOLD_S * 1000.0):
		await _tree.create_timer(0.1).timeout
		wiggle += 1
		_move(viewport, center + Vector2(wiggle % 2, 0))
		await _tree.process_frame
		if _tooltip(control) == null:
			failures.append("el tooltip de %s se cerró a los %.1f s (mouse en %s, el control en %s)" % [label, (Time.get_ticks_msec() - start) / 1000.0, center, control.get_global_rect()])
			failures.append("la fila del composer antes: %s · después: %s" % [row_before, _row_dump(control)])
			return
	print("[tooltips-check] ok: %s" % label)
	_move(viewport, Vector2(4, 4))


static func _move(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## El tooltip abierto de `control` (Godot lo cuelga del control que lo da), o null. La cuota tiene
## su propio panel (m17-14): vale el control mismo mientras el panel se vea.
static func _tooltip(control: Control) -> Object:
	if control.has_method(&"is_hint_visible"):
		return control if control.call(&"is_hint_visible") else null
	for node: Node in [control] + control.find_children("*", "Control", true, false):
		for child: Node in node.get_children(true):
			if child is PopupPanel and (child as Window).visible:
				return child
	return null


static func _row_dump(control: Control) -> String:
	var parts: PackedStringArray = []
	for child: Node in control.get_parent().get_children():
		if child is Control and (child as Control).visible:
			parts.append("%s:%d+%d" % [child.name, (child as Control).position.x, (child as Control).size.x])
	return " ".join(parts)
