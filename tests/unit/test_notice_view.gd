extends "test_case.gd"
## Avisos del dock: acciones, la principal y el menú de las demás (m12-11).

const NoticeView := preload("res://addons/godot_agent/ui/dock/entries/notice_view.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")


func test_login_card_primary_and_more_menu() -> void:
	var entry := ChatEntry.new()
	entry.kind = ChatEntry.EntryKind.NOTICE
	entry.text = "Sign in to Claude Code to continue."
	entry.actions = [
		{"id": "login", "label": "Claude account", "data": "claude", "primary": true},
		{"id": "login", "label": "Anthropic Console", "data": "console", "more": "Other ways to sign in"},
		{"id": "login", "label": "API key", "data": "key", "more": "Other ways to sign in"},
	]
	var view := NoticeView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	# Sin frames en run_all, _ready no corre: se arma a mano.
	view.call(&"_build")
	view.refresh()
	var actions: Node = view.get(&"_actions")
	var live := actions.get_children().filter(func(child: Node) -> bool: return not child.is_queued_for_deletion())
	assert_eq(live.size(), 2, "un botón y un menú")
	assert_eq((live[0] as Button).text, "Claude account", "el método principal como botón")
	var menu := live[1] as MenuButton
	assert_true(menu != null and menu.get_popup().item_count == 2, "los otros dos en el menú")
	var got: Array = []
	view.action_requested.connect(func(action: String, data: Variant) -> void: got.append([action, data]))
	menu.get_popup().id_pressed.emit(1)
	assert_eq(got, [["login", "key"]], "el ítem del menú corre su acción")
	view.free()


## m12-13: un error del agente con título, causa, las líneas del log y su acción.
func test_agent_error_card() -> void:
	var entry := ChatEntry.new()
	entry.kind = ChatEntry.EntryKind.NOTICE
	entry.level = ChatEntry.NoticeLevel.ERROR
	entry.title = "Claude Code stopped"
	entry.text = "The agent's process ended unexpectedly (code 1)."
	entry.details = "Error: Cannot find module\n    at node:internal"
	entry.actions = [{"id": "retry", "label": "Retry", "primary": true}]
	var view := NoticeView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	view.call(&"_build")
	view.refresh()
	assert_true((view.get(&"_title") as Label).visible, "título a la vista")
	assert_true((view.get(&"_details") as Control).visible, "las líneas del log")
	assert_eq((view.get(&"_details_text") as Label).text, entry.details, "tal cual")
	entry.details = ""
	entry.title = ""
	view.refresh()
	assert_false((view.get(&"_details") as Control).visible or (view.get(&"_title") as Label).visible, "sin título ni log, no se muestran")
	view.free()


## m12-20: el pie del turno, a la izquierda y con las acciones como enlaces.
func test_turn_footer() -> void:
	var entry := ChatEntry.new()
	entry.kind = ChatEntry.EntryKind.NOTICE
	entry.footer = true
	entry.text = "This turn changed 1 file (+3 −1): player.gd"
	entry.actions = [{"id": "turn_changes", "label": "View changes"}, {"id": "turn_restore", "label": "Undo turn", "tooltip": "Go back to before this turn"}]
	var view := NoticeView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	view.call(&"_build")
	view.refresh()
	assert_eq((view.get(&"_label") as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT, "texto a la izquierda")
	var buttons := (view.get(&"_actions") as Node).get_children().filter(func(child: Node) -> bool: return not child.is_queued_for_deletion())
	assert_true(buttons.all(func(button: Button) -> bool: return button.flat), "acciones como enlaces")
	assert_eq((buttons[1] as Button).tooltip_text, "Go back to before this turn", "con su tooltip")
	view.free()
