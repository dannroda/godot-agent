@tool
extends AcceptDialog
## Diálogo con un diff completo por líneas (conflictos, "Revisar cambios"). Dos escenas .tscn se
## muestran por nodos (m11-57), con «Ver crudo» para el diff de texto.

const AgentTheme := preload("agent_theme.gd")
const LineDiff := preload("../core/line_diff.gd")
const SceneDiff := preload("../core/scene_diff.gd")
const MarkdownBBCode := preload("markdown/markdown_bbcode.gd")
const I18n := preload("../core/i18n.gd")

## Cuántas líneas muestra el diff por nodos: lo de más se resume (el crudo lo tiene entero).
const SCENE_MAX_LINES := 200
## Un valor más largo que esto se corta con «…».
const SCENE_MAX_VALUE := 100
const RAW_ACTION := &"raw"

var _label: RichTextLabel
var _raw_button: Button
var _scene_text := ""
var _raw_text := ""
var _showing_raw := false
var _make_raw: Callable


func _ready() -> void:
	min_size = Vector2i(AgentTheme.px(720), AgentTheme.px(480))
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.selection_enabled = true
	_label.add_theme_font_override(&"normal_font", AgentTheme.mono_font())
	_label.add_theme_font_size_override(&"normal_font_size", AgentTheme.mono_font_size())
	add_child(_label)
	_raw_button = add_button(I18n.t("View raw"), true, RAW_ACTION)
	_raw_button.hide()
	custom_action.connect(func(action: StringName) -> void:
		if action == RAW_ACTION:
			_show_raw(not _showing_raw))


func show_diff(dialog_title: String, old_label: String, old_text: String, new_label: String, new_text: String) -> void:
	title = dialog_title
	_scene_text = scene_bbcode(old_label, old_text, new_label, new_text)
	# El diff de texto de una escena grande es caro: se arma recién al pedirlo.
	_raw_text = ""
	_make_raw = func() -> String: return diff_bbcode(old_label, old_text, new_label, new_text)
	_raw_button.visible = not _scene_text.is_empty()
	_show_raw(_scene_text.is_empty())
	popup_centered_ratio(0.6)


## Lo que se ve ahora: el diff de texto, o el de nodos de una escena.
func shown_text() -> String:
	return _label.text


func _show_raw(raw: bool) -> void:
	_showing_raw = raw
	if raw and _raw_text.is_empty():
		_raw_text = _make_raw.call()
	_label.text = _raw_text if raw else _scene_text
	_label.scroll_to_line(0)
	_raw_button.text = I18n.t("View by nodes") if raw else I18n.t("View raw")


## El diff por nodos de dos escenas en BBCode, o "" si no son dos .tscn (una vacía vale: no existía).
## Acotado a SCENE_MAX_LINES líneas y valores de SCENE_MAX_VALUE caracteres.
static func scene_bbcode(old_label: String, old_text: String, new_label: String, new_text: String) -> String:
	if not (SceneDiff.is_scene_text(old_text) or SceneDiff.is_scene_text(new_text)):
		return ""
	var result := SceneDiff.diff(old_text, new_text)
	if not str(result.error).is_empty():
		return ""
	var added := AgentTheme.color_hex(AgentTheme.ADDED)
	var removed := AgentTheme.color_hex(AgentTheme.REMOVED)
	var muted := "#8a8f98"
	var props := 0
	for node: Dictionary in result.changed:
		props += node.props.size()
	var summary: PackedStringArray = []
	if not result.added.is_empty():
		summary.append(_count(_node_count(result.added), I18n.t("1 node added"), I18n.t("%d nodes added")))
	if not result.removed.is_empty():
		summary.append(_count(_node_count(result.removed), I18n.t("1 node removed"), I18n.t("%d nodes removed")))
	if not result.moved.is_empty():
		summary.append(_count(result.moved.size(), I18n.t("1 moved or renamed"), I18n.t("%d moved or renamed")))
	if props > 0:
		summary.append(_count(props, I18n.t("1 property changed"), I18n.t("%d properties changed")))
	var connections: int = result.connections_added.size() + result.connections_removed.size()
	if connections > 0:
		summary.append(_count(connections, I18n.t("1 connection"), I18n.t("%d connections")))
	var lines: PackedStringArray = [
		"[color=%s]− %s[/color]   [color=%s]+ %s[/color]   %s" % [removed, _esc(old_label), added, _esc(new_label),
			I18n.t("%d nodes → %d") % [result.nodes_before, result.nodes_after]],
		"[b]%s[/b]\n" % (" · ".join(summary) if not summary.is_empty() else I18n.t("No node, property or connection changed."))
	]
	var body: PackedStringArray = []
	for node: Dictionary in result.added:
		body.append("[color=%s]+ %s[/color] %s%s" % [added, _esc(_shown_path(node.path)), _type(node.type, muted), _children(node.children, muted)])
	for node: Dictionary in result.removed:
		body.append("[color=%s]− %s[/color] %s%s" % [removed, _esc(_shown_path(node.path)), _type(node.type, muted), _children(node.children, muted)])
	for node: Dictionary in result.moved:
		body.append("→ %s [color=%s]%s[/color] %s %s" % [_esc(_shown_path(node.from)), muted, I18n.t("now"), _esc(_shown_path(node.to)), _type(node.type, muted)])
	for node: Dictionary in result.changed:
		body.append("~ %s %s" % [_esc(_shown_path(node.path)), _type(node.type, muted)])
		for prop: Dictionary in node.props:
			body.append("    %s: [color=%s]%s[/color] → [color=%s]%s[/color]" % [_esc(prop.name), removed, _value(prop.before), added, _value(prop.after)])
	for connection: String in result.connections_added:
		body.append("[color=%s]+ %s[/color]" % [added, _esc(connection)])
	for connection: String in result.connections_removed:
		body.append("[color=%s]− %s[/color]" % [removed, _esc(connection)])
	if body.size() > SCENE_MAX_LINES:
		var rest := body.size() - SCENE_MAX_LINES
		body.resize(SCENE_MAX_LINES)
		body.append("[color=%s]%s[/color]" % [muted, I18n.t("… and %d more lines: «View raw» has the whole text diff.") % rest])
	lines.append_array(body)
	return "\n".join(lines)


## `one` y `many` ya traducidos (con I18n.t literal, así el catálogo los ve).
static func _count(n: int, one: String, many: String) -> String:
	return one if n == 1 else many % n


static func _node_count(nodes: Array) -> int:
	var total := 0
	for node: Dictionary in nodes:
		total += 1 + int(node.children)
	return total


static func _shown_path(path: String) -> String:
	return I18n.t("(root)") if path == "." else path


static func _type(type: String, color: String) -> String:
	if type.is_empty():
		return ""
	if type.begins_with("res://") or type.begins_with("uid://"):
		return "[color=%s](%s)[/color]" % [color, _esc(I18n.t("instance of %s") % type.get_file())]
	return "[color=%s](%s)[/color]" % [color, _esc(type)]


static func _children(children: int, color: String) -> String:
	if children <= 0:
		return ""
	return " [color=%s]%s[/color]" % [color, _count(children, I18n.t("with 1 node below"), I18n.t("with %d nodes below"))]


static func _value(value: Variant) -> String:
	if value == null:
		return "[i]%s[/i]" % I18n.t("default")
	var text := _ext_path(str(value).replace("\n", " "))
	if text.length() > SCENE_MAX_VALUE:
		text = text.substr(0, SCENE_MAX_VALUE) + "…"
	return _esc(text)


## `ExtResource("res://a.gd")` se lee mejor como `res://a.gd`.
static func _ext_path(text: String) -> String:
	if not text.contains("ExtResource(\""):
		return text
	var re := RegEx.create_from_string("ExtResource\\(\"([^\"]*)\"\\)")
	return re.sub(text, "$1", true)


static func _esc(text: String) -> String:
	return MarkdownBBCode.escape(text)


## El diff por líneas en BBCode, con un encabezado de qué es cada lado y cuántas líneas cambian.
static func diff_bbcode(old_label: String, old_text: String, new_label: String, new_text: String) -> String:
	var ops := LineDiff.diff(old_text, new_text)
	var counts := LineDiff.count(ops)
	var lines: PackedStringArray = [
		"[color=%s]− %s[/color]   [color=%s]+ %s[/color]   (+%d −%d)\n" % [
			AgentTheme.color_hex(AgentTheme.REMOVED), old_label, AgentTheme.color_hex(AgentTheme.ADDED), new_label, counts.added, counts.removed
		]
	]
	for op: Dictionary in ops:
		var text := MarkdownBBCode.escape(str(op.text))
		match int(op.kind):
			LineDiff.ADD:
				lines.append("[bgcolor=#%s]+ %s[/bgcolor]" % [AgentTheme.ADDED_BG.to_html(true), text])
			LineDiff.REMOVE:
				lines.append("[bgcolor=#%s]− %s[/bgcolor]" % [AgentTheme.REMOVED_BG.to_html(true), text])
			_:
				lines.append("[color=#8a8f98]  %s[/color]" % text)
	return "\n".join(lines)
