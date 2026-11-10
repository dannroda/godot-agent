extends "test_case.gd"
## m12-44: los prompts que arma el harness se ven como del harness (atenuados, plegados, con la
## etiqueta en el idioma de la interfaz) y al agente le llega el texto en inglés sin cambios.

const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const SessionHistory := preload("res://addons/godot_agent/session/session_history.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const HarnessPrompts := preload("res://addons/godot_agent/session/harness_prompts.gd")
const UserMessageView := preload("res://addons/godot_agent/ui/dock/entries/user_message_view.gd")
const PromptQueue := preload("res://addons/godot_agent/session/prompt_queue.gd")
const PromptQueueView := preload("res://addons/godot_agent/ui/dock/prompt_queue_view.gd")
const MarkdownBBCode := preload("res://addons/godot_agent/ui/markdown/markdown_bbcode.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")

const PROMPT := "Keep going with the plan: the next pending task is “Score”. Verify with run_scene."


func _view(entry: ChatEntry) -> UserMessageView:
	var view := UserMessageView.new()
	view.setup(entry, Color.ORANGE, MarkdownBBCode.new())
	# Sin frames en run_all, _ready no corre: se arma a mano.
	view.call(&"_build")
	view.refresh()
	return view


func test_harness_entry_is_folded_and_translated() -> void:
	I18n.set_locale("es")
	var model := SessionModel.new()
	var entry := model.add_user_message(PROMPT, [], HarnessPrompts.ONESHOT_NEXT_TASK)
	assert_eq(entry.text, PROMPT, "el texto queda en inglés, como le llegó al agente")
	var view := _view(entry)
	var caption: Label = view.get(&"_caption")
	var toggle: Button = view.get(&"_toggle")
	var label: Label = view.get(&"_label")
	assert_true(view.is_harness(), "es del harness")
	assert_eq(caption.text, "⚙ One-shot · siguiente tarea del plan", "etiqueta traducida")
	assert_true((view.get(&"_header") as Control).visible, "línea del harness visible")
	assert_false(label.visible, "el prompt arranca plegado")
	assert_eq(toggle.text, "Ver prompt", "botón para verlo")
	toggle.pressed.emit()
	assert_true(label.visible and label.text == PROMPT, "desplegado muestra el prompt en inglés")
	assert_eq(toggle.text, "Ocultar prompt", "y el botón para plegarlo")
	toggle.pressed.emit()
	assert_false(label.visible, "se vuelve a plegar")
	I18n.set_locale("en")
	view.refresh()
	assert_eq(caption.text, "⚙ One-shot · next task in the plan", "la etiqueta sigue el idioma de la interfaz")
	view.free()


func test_user_entry_unchanged() -> void:
	var entry := SessionModel.new().add_user_message("Hacé el puntaje")
	var view := _view(entry)
	assert_false(view.is_harness(), "lo que escribió el usuario no es del harness")
	assert_false((view.get(&"_header") as Control).visible, "sin línea del harness")
	assert_true((view.get(&"_label") as Label).visible, "el texto a la vista")
	view.free()


## Todas las etiquetas tienen traducción (las constantes llevan `# i18n`; test_i18n lo exige, acá se
## comprueba que ninguna quedó sin marca).
func test_every_label_is_translated() -> void:
	I18n.set_locale("es")
	for label: String in (HarnessPrompts as Script).get_script_constant_map().values():
		if label != HarnessPrompts.ONESHOT:
			assert_true(I18n.t(label) != label, "traducida: %s" % label)
	I18n.set_locale("en")


func test_history_keeps_the_label() -> void:
	var history := SessionHistory.new()
	history.dir = "user://test_harness_prompts_history"
	history.begin("s-m12-44", "p", "Agente", "/tmp")
	history.record_prompt(PROMPT, HarnessPrompts.ONESHOT_NEXT_TASK)
	history.record_prompt("Hacé el puntaje")
	var record := history.load_record("s-m12-44")
	var events: Array = record.get("events", [])
	assert_eq(events.size(), 2, "dos prompts guardados")
	if events.size() == 2:
		assert_eq(events[0].get("harness"), HarnessPrompts.ONESHOT_NEXT_TASK, "el evento guarda el msgid")
		assert_false(events[1].has("harness"), "el del usuario, sin marca")
		var model := SessionModel.new()
		SessionHistory.replay(record, model)
		assert_eq(model.entries()[0].harness_label, HarnessPrompts.ONESHOT_NEXT_TASK, "el replay la recupera")
		assert_eq(model.entries()[1].harness_label, "", "y el del usuario sigue siendo del usuario")
	history.end()
	history.remove("s-m12-44")
	history.flush()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(history.dir).path_join("index.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(history.dir))


func test_controller_registry() -> void:
	var controller := SessionController.new()
	assert_eq(controller.label_prompt(PROMPT, HarnessPrompts.TURN_CHECK), PROMPT, "devuelve el mismo texto")
	assert_eq(controller.prompt_label(PROMPT), HarnessPrompts.TURN_CHECK, "queda registrada")
	assert_eq(controller.prompt_label("otro"), "", "lo demás es del usuario")
	controller.label_prompt("vacía", "")
	assert_eq(controller.prompt_label("vacía"), "", "sin etiqueta no se registra")


func test_queue_row_shows_the_label() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var queue := PromptQueue.new()
	var view: PanelContainer = PromptQueueView.new()
	view.call(&"setup", queue)
	view.set(&"harness_label_of", func(text: String) -> String: return HarnessPrompts.SUPERVISOR if text == PROMPT else "")
	tree.root.add_child(view)
	queue.add(PROMPT)
	queue.add("Hacé el puntaje")
	await tree.process_frame
	var rows: Array = (view.get(&"_rows") as Node).get_children().filter(func(row: Node) -> bool: return not row.is_queued_for_deletion())
	assert_eq(rows.size(), 2, "dos filas")
	if rows.size() == 2:
		assert_eq((rows[0].get_child(0) as Label).text, "⚙ What the supervisor saw while the editor was closed", "la del harness, con su etiqueta")
		assert_eq((rows[1].get_child(0) as Label).text, "Hacé el puntaje", "la del usuario, con su texto")
	view.queue_free()
