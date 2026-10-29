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
