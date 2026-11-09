extends "test_case.gd"
## SessionState (m13-13): la tabla de transiciones cubre todos los estados, set_state aplica todo
## cambio y anota los que no están en la tabla, el controller los manda al Agent Log, y nadie
## cambia `state` por fuera del setter.

const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")

const ADDON_DIRS: PackedStringArray = ["res://addons/godot_agent", "res://addons/godot_agent_dev"]
const MODEL_SCRIPT := "res://addons/godot_agent/session/session_model.gd"


func _name(state: int) -> String:
	return SessionModel.state_name(state)


func test_table_covers_every_state() -> void:
	var table: Dictionary = SessionModel.SESSION_STATE_TRANSITIONS
	var states: Array = SessionModel.SessionState.values()
	assert_eq(table.size(), states.size(), "una fila por estado")
	for state: int in states:
		assert_true(table.has(state), "%s tiene fila" % _name(state))
		var targets: Array = table.get(state, [])
		assert_false(targets.is_empty(), "%s sale a algún lado" % _name(state))
		for target: int in targets:
			assert_true(target in states, "%s → %s: destino del enum" % [_name(state), str(target)])
			assert_true(target != state, "%s: sin transición a sí mismo" % _name(state))
			assert_eq(targets.count(target), 1, "%s → %s una sola vez" % [_name(state), _name(target)])
	# Todo estado se alcanza desde algún otro (nada queda huérfano en la tabla).
	for state: int in states:
		if state == SessionModel.SessionState.DISCONNECTED:
			continue  # el inicial
		var reachable := false
		for from: int in table:
			reachable = reachable or state in table[from]
		assert_true(reachable, "%s se alcanza desde algún estado" % _name(state))
	# LOGIN_REQUIRED va al final: los valores de los demás no cambian (el historial y los tests los conocen).
	assert_eq(SessionModel.SessionState.FAILED, 5, "FAILED conserva su valor")
	assert_eq(SessionModel.SessionState.LOGIN_REQUIRED, 6, "LOGIN_REQUIRED al final del enum")


func test_login_required_is_a_failed_state_that_is_not_busy() -> void:
	var model := SessionModel.new()
	assert_false(model.has_failed(), "arranca sin fallo")
	model.set_state(SessionModel.SessionState.STARTING)
	model.set_state(SessionModel.SessionState.LOGIN_REQUIRED)
	assert_true(model.has_failed(), "LOGIN_REQUIRED cuenta como sesión no abierta")
	assert_false(model.is_busy(), "LOGIN_REQUIRED no está ocupada")
	model.set_state(SessionModel.SessionState.STARTING)
	model.set_state(SessionModel.SessionState.FAILED)
	assert_true(model.has_failed(), "FAILED también")
	model.set_state(SessionModel.SessionState.STARTING)
	model.set_state(SessionModel.SessionState.READY)
	assert_false(model.has_failed(), "READY no")


## Recorre todos los pares: el cambio se aplica siempre y state_changed sale una vez; el aviso sale
## solo si el par no está en la tabla.
func test_every_change_is_applied_and_unexpected_ones_are_reported() -> void:
	var model := SessionModel.new()
	var table: Dictionary = SessionModel.SESSION_STATE_TRANSITIONS
	var reported: Array = []
	var changed: Array = []
	model.unexpected_transition.connect(func(from: SessionModel.SessionState, to: SessionModel.SessionState) -> void: reported.append([from, to]))
	model.state_changed.connect(func(state: SessionModel.SessionState) -> void: changed.append(state))
	for from: int in SessionModel.SessionState.values():
		for to: int in SessionModel.SessionState.values():
			if from == to:
				continue
			model.set_state(from)
			reported.clear()
			changed.clear()
			model.set_state(to)
			var label := "%s → %s" % [_name(from), _name(to)]
			assert_eq(model.state, to, "%s se aplica" % label)
			assert_eq(changed, [to], "%s emite state_changed una vez" % label)
			if to in table[from]:
				assert_eq(reported, [], "%s está en la tabla: sin aviso" % label)
			else:
				assert_eq(reported, [[from, to]], "%s no está en la tabla: se anota" % label)
	# Mismo estado: no pasa nada.
	reported.clear()
	changed.clear()
	model.set_state(model.state)
	assert_eq(changed, [], "mismo estado: sin state_changed")
	assert_eq(reported, [], "mismo estado: sin aviso")


func test_controller_logs_unexpected_transitions_in_the_state_channel() -> void:
	var model := SessionModel.new()
	var log := AgentLog.new()
	var controller := SessionController.new()
	controller.setup(model, log, "/tmp/project")
	var state_lines := func() -> Array:
		return log.entries().filter(func(entry: Dictionary) -> bool: return entry.channel == AgentLog.CH_STATE)
	model.set_state(SessionModel.SessionState.STARTING)
	model.set_state(SessionModel.SessionState.READY)
	assert_eq(state_lines.call().size(), 0, "las transiciones de la tabla no dejan rastro")
	model.set_state(SessionModel.SessionState.CANCELLING)
	assert_eq(model.state, SessionModel.SessionState.CANCELLING, "se aplica igual")
	var lines: Array = state_lines.call()
	assert_eq(lines.size(), 1, "una línea en el canal state")
	if not lines.is_empty():
		assert_eq(lines[0].message, "session: unexpected transition READY -> CANCELLING", "formato común del aviso")
	assert_true(AgentLog.CH_STATE in AgentLog.CHANNELS, "el canal state está en la lista del panel")


## `state` solo se asigna en set_state: ni el controller, ni el dock, ni los checks lo tocan directo.
func test_state_only_changes_through_the_setter() -> void:
	var assignment := RegEx.create_from_string("model\\.state\\s*=(?!=)")
	var found: PackedStringArray = []
	for dir: String in ADDON_DIRS:
		for path: String in _scripts(dir):
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				if assignment.search(lines[i]):
					found.append("%s:%d" % [path.get_file(), i + 1])
	assert_eq(found, PackedStringArray(), "asignación directa de model.state")

	var own_assignment := RegEx.create_from_string("^\\s*state\\s*=(?!=)")
	var model_lines := FileAccess.get_file_as_string(MODEL_SCRIPT).split("\n")
	var setter_start := -1
	var setter_end := model_lines.size()
	for i in model_lines.size():
		if model_lines[i].begins_with("func set_state("):
			setter_start = i
		elif setter_start >= 0 and setter_end == model_lines.size() and model_lines[i].begins_with("func "):
			setter_end = i
	assert_true(setter_start >= 0, "session_model.gd tiene set_state")
	var assignments: PackedStringArray = []
	for i in model_lines.size():
		if own_assignment.search(model_lines[i]):
			assignments.append(str(i + 1))
			assert_true(i > setter_start and i < setter_end, "session_model.gd:%d asigna state fuera de set_state" % (i + 1))
	assert_eq(assignments.size(), 1, "una sola asignación de state en el modelo (%s)" % ", ".join(assignments))


func _scripts(dir: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		result.append_array(_scripts(dir.path_join(sub)))
	return result
