@tool
extends RefCounted
## Verificación de M5 dentro del editor: modo Revisar con un agente (falso o Claude real) sobre
## tests/fixtures/review/, que tiene tres bugs sembrados. Comprueba hallazgos en las líneas
## correctas, marcas y tarjeta en el Script Editor, Descartar, Preguntar (no reemplaza la revisión),
## Aplicar arreglo y Arreglar en modo Construir (pasan a Construir y sacan lo arreglado), y la vista
## previa de Exportar a CLAUDE.md.

const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")
const ReviewStore := preload("res://addons/godot_agent/review/review_store.gd")
const ReviewAnnotations := preload("res://addons/godot_agent/review/review_annotations.gd")
const DOCK_SCRIPT := "res://addons/godot_agent/ui/dock/agent_dock.gd"
const ANNOTATIONS_SCRIPT := "res://addons/godot_agent/review/review_annotations.gd"
const FIXTURE_DIR := "res://tests/fixtures/review"
const REVIEW_PROMPT := "Revisá los scripts de tests/fixtures/review/ (review_player.gd, review_spawner.gd y review_hud.gd). Son tres archivos chicos: leelos y reportá solo los problemas reales."
## Bug sembrado → texto de la línea con el bug y severidades aceptadas.
const SEEDED: Array[Dictionary] = [
	{"path": "res://tests/fixtures/review/review_player.gd", "code": "position += direction * speed", "severities": ["bug", "perf"]},
	{"path": "res://tests/fixtures/review/review_spawner.gd", "code": "_timer.wait_time = value", "severities": ["order", "bug"]},
	{"path": "res://tests/fixtures/review/review_hud.gd", "code": "get_node(\"Margin/ScoreLabel\")", "severities": ["perf", "style"]},
]
const TURN_TIMEOUT_S := 240.0

var failures: PackedStringArray = []
var _tree: SceneTree
var _dock: Control
var _model: Object
var _controller: Object
var _annotations: ReviewAnnotations


## `profile` vacío = agente falso con tests/scripts/review.json. Con Claude real se valida lo que
## no depende del texto exacto: los tres bugs anotados en su línea.
func run_review(tree: SceneTree, profile: AgentProfile, shot_path: String = "") -> PackedStringArray:
	_tree = tree
	var fake := profile == null
	for node: Node in tree.root.find_children("*", "Node", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == DOCK_SCRIPT:
			_dock = node
		elif script and script.resource_path == ANNOTATIONS_SCRIPT:
			_annotations = node
	if _dock == null or _annotations == null:
		failures.append("no se encontró el dock o las anotaciones")
		return failures
	_model = _dock.get(&"_model")
	_controller = _dock.get(&"_controller")
	if fake:
		profile = AgentProfile.from_dict({
			"id": "fake", "display_name": "Agente falso", "command": OS.get_executable_path(),
			"args": ["--headless", "--no-header", "--path", ProjectSettings.globalize_path("res://"),
				"--script", "res://tests/fake_agent.gd", "--", "--scenario=res://tests/scripts/review.json"],
		})
	if not await _controller.call(&"start", profile):
		failures.append("no arrancó la sesión: %s" % _model.get(&"failure_message"))
		return failures

	_model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	var panel: Control = _dock.get(&"_review_panel")
	_expect(panel.visible, "el panel de revisión se ve en modo Revisar")
	_dock.call(&"_on_submitted", REVIEW_PROMPT)
	await _wait_turn()
	var store: ReviewStore = _controller.get(&"review")
	print("[review-check] %d hallazgos: %s" % [store.findings.size(), ", ".join(store.findings.map(func(f: Dictionary) -> String: return "%s [%s] %s" % [ReviewStore.location(f), f.severity, f.title]))])
	_expect(_model.get(&"current_agent_mode") == "plan", "el agente pasó a plan (modo %s)" % _model.get(&"current_agent_mode"))

	var seeded_ids: Array[int] = []
	for seeded: Dictionary in SEEDED:
		var line := _line_of(seeded.path, seeded.code)
		var match_finding := _finding_at(store, seeded.path, line)
		if match_finding.is_empty():
			failures.append("falta el hallazgo de %s:%d" % [seeded.path.get_file(), line])
			continue
		seeded_ids.append(int(match_finding.id))
		if fake:
			_expect(match_finding.severity == seeded.severities[0], "severidad de %s: %s" % [seeded.path.get_file(), match_finding.severity])
		else:
			_expect(match_finding.severity in seeded.severities, "severidad razonable en %s: %s" % [seeded.path.get_file(), match_finding.severity])
		await _check_annotation(match_finding)
	if fake:
		_expect(store.findings.size() == 3, "exactamente 3 hallazgos (%d)" % store.findings.size())
		_expect(store.scope_label() == "tests/fixtures/review/", "alcance: %s" % store.scope_label())
	var fold: FoldableContainer = panel.get(&"_fold")
	_expect(fold.title.begins_with("Review of tests/fixtures/review/"), "título del panel: %s" % fold.title)
	if not shot_path.is_empty() and not seeded_ids.is_empty():
		_annotations.focus_finding(seeded_ids[0])
		await _frames(10)
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(shot_path)

	if fake and seeded_ids.size() == 3:
		await _check_actions(store, seeded_ids)
	var agent_log: Object = _controller.get(&"agent_log")
	for entry: Dictionary in agent_log.call(&"entries"):
		if entry.channel == &"perm":
			print("[review-check] perm: ", entry.message)
	_controller.call(&"stop")
	return failures


func _check_annotation(finding: Dictionary) -> void:
	_expect(_annotations.focus_finding(int(finding.id)), "abre %s" % ReviewStore.location(finding))
	await _frames(6)
	var lines := _annotations.annotated_lines(finding.path)
	_expect(lines.has(int(finding.line) - 1), "marca en %s (líneas %s)" % [ReviewStore.location(finding), lines.keys()])
	var code_edit := _annotations.editor_for(finding.path)
	var has_gutter := false
	if code_edit:
		for i in code_edit.get_gutter_count():
			has_gutter = has_gutter or code_edit.get_gutter_name(i) == ReviewAnnotations.GUTTER_NAME
		_expect(code_edit.get_caret_line() == int(finding.line) - 1, "cursor en la línea de %s" % ReviewStore.location(finding))
	_expect(has_gutter, "gutter de la revisión en %s" % finding.path.get_file())
	var band := _annotations.band_for(finding.path)
	_expect(band != null and band.is_visible_in_tree() and band.text.contains("Agent review · read-only"), "banda de revisión en %s" % finding.path.get_file())
	_expect(band != null and band.get_parent() is HBoxContainer, "la banda va en la barra de estado")
	var card := _annotations.card_for(finding.path)
	_expect(card != null and card.visible, "tarjeta visible para %s" % ReviewStore.location(finding))
	if card:
		var texts := _texts(card)
		_expect(finding.title in texts, "la tarjeta muestra el título de %s" % ReviewStore.location(finding))
		for label: String in ["Apply fix", "Ask", "Dismiss"]:
			_expect(label in texts, "botón %s en la tarjeta" % label)


func _check_actions(store: ReviewStore, ids: Array[int]) -> void:
	# Descartar desde la tarjeta.
	_annotations.focus_finding(ids[2])
	await _frames(6)
	var hud_path: String = store.get_finding(ids[2]).path
	_press(_annotations.card_for(hud_path), "Dismiss")
	await _frames(3)
	_expect(store.get_finding(ids[2]).is_empty() and store.findings.size() == 2, "Descartar saca el hallazgo")
	_expect(_annotations.annotated_lines(hud_path).is_empty(), "sin marcas en el archivo descartado")
	_expect(not _annotations.card_for(hud_path).visible, "la tarjeta se cierra")

	# Preguntar: el agente responde con un bloque, pero la revisión no se reemplaza.
	_annotations.focus_finding(ids[0])
	await _frames(6)
	var player_path: String = store.get_finding(ids[0]).path
	_press(_annotations.card_for(player_path), "Ask")
	await _wait_turn()
	_expect(store.findings.size() == 2, "Preguntar no reemplaza la revisión (%d)" % store.findings.size())
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.REVIEW, "Preguntar no cambia el modo")

	# Exportar a CLAUDE.md: vista previa (sin escribir el archivo del proyecto).
	var review_panel: Object = _dock.get(&"_review_panel")
	review_panel.call(&"_on_export_requested")
	await _frames(2)
	var preview: TextEdit = review_panel.get(&"_export_preview")
	_expect(preview.text.contains("## Conventions from the agent review") and preview.text.contains("El movimiento depende del framerate"), "vista previa de CLAUDE.md")
	(review_panel.get(&"_export_dialog") as ConfirmationDialog).hide()

	# Aplicar arreglo: pasa a Construir y, al terminar bien el turno, el hallazgo sale.
	_press(_annotations.card_for(player_path), "Apply fix")
	await _frames(2)
	_expect(int(_model.get(&"harness_mode")) == SessionModel.HarnessMode.BUILD, "Aplicar arreglo pasa a Construir")
	await _wait_turn()
	await _frames(2)
	_expect(store.get_finding(ids[0]).is_empty() and store.findings.size() == 1, "el hallazgo arreglado sale de la revisión")
	_expect(_model.get(&"current_agent_mode") == "default", "el agente volvió a default")
	var last_user := ""
	for entry: Object in _model.call(&"entries"):
		if int(entry.get(&"kind")) == 0:  # USER
			last_user = str(entry.get(&"text"))
	_expect(last_user.contains("review_player.gd:13") and last_user.contains("Suggestion: position += direction * speed * delta"), "prompt del arreglo: %s" % last_user.left(200))

	# Arreglar en modo Construir desde el panel del dock.
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	await _frames(2)
	var panel: Control = _dock.get(&"_review_panel")
	(panel.get(&"_fold") as FoldableContainer).expand()  # plegado desde m12-03: las acciones no se ven
	await _frames(2)
	_press(panel, "Fix in Build mode")
	await _frames(2)
	await _wait_turn()
	await _frames(2)
	_expect(store.findings.is_empty(), "Arreglar en modo Construir vacía la revisión (%d)" % store.findings.size())
	_expect(not panel.visible, "el panel se oculta fuera de Revisar")

	# Playtest (m14-03): el prompt del panel va al agente y su veredicto queda como aviso.
	_model.call(&"set_harness_mode", SessionModel.HarnessMode.REVIEW)
	await _frames(2)
	panel.emit_signal(&"prompt_requested", "Playtest: the score goes up")
	await _frames(2)
	await _wait_turn()
	var verdicts := (_model.call(&"entries") as Array).filter(func(entry: Object) -> bool: return str(entry.get(&"text")).begins_with(I18n.t("Playtest: failed")))
	_expect(verdicts.size() == 1 and str(verdicts[0].get(&"text")).contains("score = 0") and str(verdicts[0].get(&"text")).contains("2. "), "playtest: el veredicto queda como aviso con evidencia y pasos")


func _wait_turn() -> void:
	var deadline := Time.get_ticks_msec() + int(TURN_TIMEOUT_S * 1000)
	await _frames(2)
	while int(_model.get(&"state")) != SessionModel.SessionState.READY and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	if int(_model.get(&"state")) != SessionModel.SessionState.READY:
		failures.append("el turno no terminó (estado %d)" % int(_model.get(&"state")))


func _frames(count: int) -> void:
	for i in count:
		await _tree.process_frame


func _line_of(path: String, code: String) -> int:
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		if lines[i].contains(code):
			return i + 1
	return -1


## Hallazgo en ese archivo a ±1 línea (Claude real a veces señala la línea vecina).
func _finding_at(store: ReviewStore, path: String, line: int) -> Dictionary:
	for finding: Dictionary in store.for_path(path):
		if absi(int(finding.line) - line) <= 1:
			return finding
	return {}


func _texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for node: Node in root.find_children("*", "", true, false):
		if node is Label:
			out.append((node as Label).text)
		elif node is Button:
			out.append((node as Button).text)
	return out


func _press(root: Node, text: String) -> void:
	if root == null:
		failures.append("no hay dónde apretar '%s'" % text)
		return
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree():
			(node as Button).pressed.emit()
			return
	failures.append("no se encontró el botón '%s'" % text)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
