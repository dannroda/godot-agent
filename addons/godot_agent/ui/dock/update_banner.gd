@tool
extends PanelContainer
## Aviso de versión nueva del addon (m7-38), arriba del chat: «Novedades», «Actualizar» y «Después».
## Mientras baja e instala muestra el progreso; si falla, el motivo y el link al release.

signal update_requested
signal dismissed

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const MarkdownBBCode := preload("../markdown/markdown_bbcode.gd")

var _release: Dictionary = {}
var _label: Label
var _buttons: HBoxContainer
var _update_button: Button
var _notes_dialog: AcceptDialog
var _notes_text: RichTextLabel


func _ready() -> void:
	visible = false
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(6))
	add_child(margin)
	var content := VBoxContainer.new()
	margin.add_child(content)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_label)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(_buttons)
	var notes := Button.new()
	notes.text = I18n.t("What's new")
	notes.flat = true
	notes.pressed.connect(_show_notes)
	_buttons.add_child(notes)
	var later := Button.new()
	later.text = I18n.t("Later")
	later.flat = true
	later.tooltip_text = I18n.t("Don't show this version again. Settings → Interface checks again.")
	later.pressed.connect(func() -> void:
		visible = false
		dismissed.emit())
	_buttons.add_child(later)
	_update_button = Button.new()
	_update_button.name = "UpdateButton"
	_update_button.text = I18n.t("Update")
	_update_button.pressed.connect(func() -> void: update_requested.emit())
	_buttons.add_child(_update_button)
	_notes_dialog = AcceptDialog.new()
	_notes_dialog.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_notes_text = RichTextLabel.new()
	_notes_text.bbcode_enabled = true
	_notes_text.selection_enabled = true
	_notes_text.custom_minimum_size = Vector2(AgentTheme.px(560), AgentTheme.px(360))
	_notes_text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	_notes_dialog.add_child(_notes_text)
	add_child(_notes_dialog)


## `release` como lo da AddonUpdater.pick_release().
func show_release(release: Dictionary, current_version: String) -> void:
	_release = release
	_label.text = I18n.t("Godot Agent Harness %s is available (you have %s).") % [release.version, current_version]
	_set_buttons_enabled(true)
	visible = true


func set_progress(text: String) -> void:
	_label.text = text
	_set_buttons_enabled(false)
	visible = true


func set_error(text: String) -> void:
	_label.text = I18n.t("The update failed: %s") % text
	_set_buttons_enabled(true)
	visible = true


func release() -> Dictionary:
	return _release


func _set_buttons_enabled(enabled: bool) -> void:
	for button: Node in _buttons.get_children():
		(button as Button).disabled = not enabled


func _show_notes() -> void:
	_notes_dialog.title = I18n.t("What's new in %s") % _release.get("version", "")
	var notes := str(_release.get("notes", "")).strip_edges()
	if notes.is_empty():
		notes = I18n.t("This release has no notes.")
	var link := str(_release.get("html_url", ""))
	if not link.is_empty():
		notes += "\n\n[%s](%s)" % [I18n.t("See the release on GitHub"), link]
	_notes_text.text = MarkdownBBCode.new().convert(notes)
	_notes_dialog.popup_centered_clamped(Vector2i(AgentTheme.px(600), AgentTheme.px(440)), 0.8)
