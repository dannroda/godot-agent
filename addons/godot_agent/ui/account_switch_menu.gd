@tool
extends RefCounted
## El menú «Cambiar de cuenta» (m6-15, m6-22), igual en la pantalla del One-shot y en el dock: las
## cuentas y perfiles configurados (AccountChoices.list), marcando la que está en uso y la cuota que
## se sabe de cada una; después, iniciar sesión con otra cuenta y «ya cambié en una terminal».

const I18n := preload("../core/i18n.gd")

const ALREADY_SWITCHED := 1000
const CHOICE_BASE := 2000
const CONFIRM_NAME := "AccountSwitchConfirm"


## Llena `popup`. Los ids: 0..n-1 los métodos de login, ALREADY_SWITCHED, CHOICE_BASE + i las cuentas.
static func fill(popup: PopupMenu, choices: Array[Dictionary], methods: Array[Dictionary]) -> void:
	popup.clear()
	var other_started := false
	if not choices.is_empty():
		popup.add_separator(I18n.t("Continue with"))
	for i in choices.size():
		var choice := choices[i]
		if not bool(choice.same_agent) and not other_started:
			other_started = true
			popup.add_separator(I18n.t("Another agent (new session)"))
		var text := str(choice.label)
		if bool(choice.current):
			text = I18n.t("%s (in use)") % text
		popup.add_item(text, CHOICE_BASE + i)
		var index := popup.item_count - 1
		popup.set_item_disabled(index, bool(choice.current))
		if bool(choice.same_agent):
			popup.set_item_tooltip(index, I18n.t("Restarts the agent with this account and resumes the same session."))
		else:
			popup.set_item_tooltip(index, I18n.t("Another agent: opens a new session with the plan summary. The conversation is not carried over."))
	if not choices.is_empty():
		popup.add_separator()
	for i in methods.size():
		popup.add_item(I18n.t("Sign in with another account · %s") % methods[i].label, i)
	popup.add_item(I18n.t("I already signed in with another account (in a terminal): restart the agent"), ALREADY_SWITCHED)


## La cuenta del id elegido en el menú, o {} si el id es de otra cosa.
static func choice_of(id: int, choices: Array[Dictionary]) -> Dictionary:
	var index := id - CHOICE_BASE
	return choices[index] if index >= 0 and index < choices.size() else {}


## Pasar a otro agente pierde la conversación: se confirma antes. Otra cuenta del mismo agente, no.
## `on_ok` se llama con el perfil a lanzar.
static func confirm(parent: Node, choice: Dictionary, what: String, on_ok: Callable) -> void:
	if bool(choice.same_agent):
		on_ok.call(choice.profile)
		return
	var dialog := parent.get_node_or_null(CONFIRM_NAME) as ConfirmationDialog
	if dialog == null:
		dialog = ConfirmationDialog.new()
		dialog.name = CONFIRM_NAME
		dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		dialog.title = I18n.t("Switch agent")
		dialog.ok_button_text = I18n.t("Switch")
		dialog.cancel_button_text = I18n.t("Cancel")
		parent.add_child(dialog)
	for connection: Dictionary in dialog.confirmed.get_connections():
		dialog.confirmed.disconnect(connection.callable)
	dialog.dialog_text = what % str(choice.name)
	dialog.confirmed.connect(func() -> void: on_ok.call(choice.profile), CONNECT_ONE_SHOT)
	dialog.popup_centered()
