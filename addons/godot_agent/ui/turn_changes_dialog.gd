@tool
extends AcceptDialog
## Los archivos que cambió un turno (m11-02): cada uno con su diff y «Volver atrás», que lo deja
## como estaba antes del turno.

## Pide el diff de un archivo (el plugin lo muestra en el DiffDialog).
signal diff_requested(data: Dictionary, path: String)
## Pide volver atrás un archivo; el plugin llama a mark_reverted() cuando terminó.
signal revert_requested(data: Dictionary, path: String)

const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("agent_theme.gd")
const ExtensionsUi := preload("extensions/extensions_ui.gd")

var _box: VBoxContainer
var _data: Dictionary = {}
var _reverted: Dictionary = {}


func _init() -> void:
	title = I18n.t("Changes of the turn")
	ok_button_text = I18n.t("Close")
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(AgentTheme.px(480), AgentTheme.px(320))
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("What the agent changed in the project during that turn. «Go back» leaves a file as it was before the turn.")))
	_box = ExtensionsUi.scroll_list(page)


func show_turn(data: Dictionary) -> void:
	_data = data
	_reverted.clear()
	_rebuild()
	popup_centered()


func mark_reverted(path: String) -> void:
	_reverted[path] = true
	_rebuild()


func _rebuild() -> void:
	ExtensionsUi.clear(_box)
	for file: Dictionary in _data.get("files", []):
		var row := HBoxContainer.new()
		var status := Label.new()
		status.text = {"A": "+", "D": "−"}.get(file.status, "~")
		status.add_theme_color_override(&"font_color", {"A": AgentTheme.ADDED, "D": AgentTheme.REMOVED}.get(file.status, AgentTheme.MUTED))
		row.add_child(status)
		var path := Label.new()
		path.text = str(file.path)
		path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		path.clip_text = true
		path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		path.tooltip_text = str(file.path)
		path.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(path)
		row.add_child(ExtensionsUi.muted("+%d −%d" % [file.added, file.removed]))
		var diff := Button.new()
		diff.text = I18n.t("Diff")
		diff.flat = true
		diff.pressed.connect(func() -> void: diff_requested.emit(_data, str(file.path)))
		row.add_child(diff)
		var back := Button.new()
		back.text = I18n.t("Went back") if _reverted.has(file.path) else I18n.t("Go back")
		back.disabled = _reverted.has(file.path)
		back.pressed.connect(func() -> void:
			back.disabled = true
			revert_requested.emit(_data, str(file.path)))
		row.add_child(back)
		_box.add_child(row)
