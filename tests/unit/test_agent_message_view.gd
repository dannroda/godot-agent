extends "test_case.gd"
## Vista del texto del agente: bloques de código y el bloque findings plegado (m12-38).

const AgentMessageView := preload("res://addons/godot_agent/ui/dock/entries/agent_message_view.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")
const CodeBlockView := preload("res://addons/godot_agent/ui/markdown/code_block_view.gd")

const TEXT := "Two things.\n\n```json\n{\"findings\": [{\"path\": \"a.gd\", \"line\": 3, \"title\": \"x\"}, {\"path\": \"b.gd\", \"line\": 1, \"title\": \"y\"}]}\n```\n"


func _view(findings_count: int) -> AgentMessageView:
	var entry := ChatEntry.new()
	entry.kind = ChatEntry.EntryKind.AGENT
	entry.text = TEXT
	entry.findings_count = findings_count
	var view := AgentMessageView.new()
	view.setup(entry, Color.WHITE, MarkdownBBCode.new())
	# Sin frames en run_all, _ready no corre: se arma a mano.
	view.call(&"_build")
	view.call(&"_flush")
	return view


func _segments(view: AgentMessageView) -> Array[Node]:
	return (view.get(&"_segments") as Node).get_children()


func test_unread_block_shows_as_code() -> void:
	var view := _view(-1)
	var segments := _segments(view)
	assert_eq(segments.size(), 2, "texto y código")
	assert_true(segments[1] is CodeBlockView, "sin leer: caja de código")
	view.free()


func test_read_block_is_folded() -> void:
	var view := _view(2)
	var fold: Node = _segments(view)[1]
	assert_true(fold.has_meta(&"findings_fold"), "leído: plegado")
	var toggle := fold.get_child(0) as Button
	assert_true(toggle.text.contains("2 findings"), "dice cuántos: %s" % toggle.text)
	assert_false((fold.get_child(1) as Control).visible, "el JSON arranca oculto")
	toggle.button_pressed = true
	assert_true((fold.get_child(1) as Control).visible, "se abre con un clic")
	view.free()


const CHECKS_TEXT := "Done.\n\n```json\n{\"checks\": [{\"label\": \"Paddles move\", \"status\": \"pass\"}, {\"label\": \"Score [ui]\", \"status\": \"fail\", \"detail\": \"stays at 0\"}, {\"label\": \"Sound\", \"status\": \"pending\"}], \"scores\": [{\"criterion\": \"playability\", \"score\": 6, \"reason\": \"ok\"}], \"findings\": [{\"title\": \"Score never rises\", \"path\": \"res://score.gd\", \"line\": 4}]}\n```\n"


func _checks_view(text: String) -> AgentMessageView:
	var entry := ChatEntry.new()
	entry.kind = ChatEntry.EntryKind.AGENT
	entry.text = text
	var view := AgentMessageView.new()
	view.setup(entry, Color.WHITE, MarkdownBBCode.new())
	view.call(&"_build")
	view.call(&"_flush")
	return view


func test_checks_block_is_folded_into_a_summary() -> void:
	var view := _checks_view(CHECKS_TEXT)
	var segments := _segments(view)
	assert_eq(segments.size(), 2, "texto y resumen")
	var fold: Node = segments[1]
	assert_true(fold.has_meta(&"report_fold"), "los checks se pliegan, sin leer el turno")
	var toggle := fold.get_child(0) as Button
	assert_true(toggle.text.contains("1 ✓") and toggle.text.contains("1 ✗"), "cuenta pass y fail: %s" % toggle.text)
	assert_true(toggle.text.contains("1 unverified") and toggle.text.contains("1 score") and toggle.text.contains("1 finding"), "pendientes, puntajes y hallazgos: %s" % toggle.text)
	var body := fold.get_child(1) as Control
	assert_false(body.visible, "arranca cerrado")
	toggle.button_pressed = true
	assert_true(body.visible, "se abre con un clic")
	var list := body.get_child(0) as RichTextLabel
	assert_true(list.text.contains("Paddles move") and list.text.contains("stays at 0"), "lista legible con el detalle")
	assert_true(list.text.contains("Score [lb]ui]"), "escapa el BBCode del agente")
	assert_true(list.text.contains("res://score.gd:4"), "el hallazgo dice dónde")
	assert_false((body.get_child(2) as Control).visible, "el JSON queda detrás de su botón")
	(body.get_child(1) as Button).button_pressed = true
	assert_true((body.get_child(2) as Control).visible, "Ver JSON lo muestra")
	view.free()


func test_other_json_stays_as_code() -> void:
	var view := _checks_view("```json\n{\"name\": \"checks\", \"items\": []}\n```\n")
	assert_true(_segments(view)[0] is CodeBlockView, "un JSON que no es informe queda como código")
	view.free()
	view = _checks_view("```json\n{\"checks\": [{\"label\": \"a\", \"stat")
	assert_true(_segments(view)[0] is CodeBlockView, "a medio llegar sigue como código")
	view.free()
