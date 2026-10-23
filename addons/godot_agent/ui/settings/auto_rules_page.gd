@tool
extends VBoxContainer
## Listas del modo Auto (D57) en Settings → Permisos: qué comandos de shell corren sin preguntar y
## cuáles preguntan siempre, con el origen y la fecha de cada regla. Se edita una copia y se
## guarda con el resto del diálogo.

const I18n := preload("../../core/i18n.gd")
const ShellRules := preload("../../session/shell_rules.gd")
const AgentTheme := preload("../agent_theme.gd")

enum RuleColumn { PATTERN, LIST, ORIGIN, ADDED }
const COLUMN_TITLES: PackedStringArray = [
	"Pattern",  # i18n
	"List",  # i18n
	"Origin",  # i18n
	"Added",  # i18n
]
const LIST_LABELS: Dictionary = {
	ShellRules.LIST_ALLOW: "Allowlist",  # i18n
	ShellRules.LIST_ASK: "Always ask",  # i18n
}
const ORIGIN_LABELS: Dictionary = {
	ShellRules.ORIGIN_DEFAULT: "Default",  # i18n
	ShellRules.ORIGIN_USER: "Added by you",  # i18n
	ShellRules.ORIGIN_CARD: "From a permission card",  # i18n
}
const LISTS: PackedStringArray = [ShellRules.LIST_ALLOW, ShellRules.LIST_ASK]

var _tree: Tree
var _test_edit: LineEdit
var _test_result: Label
## Patrones que decidieron el comando de prueba: se resaltan en la tabla.
var _highlight: PackedStringArray = []
var _filter: OptionButton
var _pattern_edit: LineEdit
var _list_option: OptionButton
## Copia de las reglas que se está editando.
var _rules: Array = []


func _init() -> void:
	add_theme_constant_override(&"separation", AgentTheme.px(6))
	var title := Label.new()
	title.text = I18n.t("Auto mode: shell commands")
	title.add_theme_font_size_override(&"font_size", AgentTheme.px(15))
	add_child(title)
	add_child(_hint(I18n.t("In Auto mode, a command runs without asking if every part of it matches the allowlist and none matches the «Always ask» list. Anything else shows a card. * matches anything, and «git log *» also matches «git log» alone. The agent's permission log (Agent Log, perm channel) records each decision.")))
	# Probar un comando (m2-10): el resultado sale de las reglas que se están editando, sin guardar.
	var test_row := HBoxContainer.new()
	add_child(test_row)
	_test_edit = LineEdit.new()
	_test_edit.placeholder_text = I18n.t("Test a command, e.g. git status && npm test")
	_test_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_test_edit.clear_button_enabled = true
	_test_edit.text_changed.connect(func(_text: String) -> void: _refresh())
	test_row.add_child(_test_edit)
	_test_result = Label.new()
	_test_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_result.visible = false
	add_child(_test_result)
	var bar := HBoxContainer.new()
	add_child(bar)
	_filter = OptionButton.new()
	_filter.add_item(I18n.t("All rules"))
	for list: String in LISTS:
		_filter.add_item(I18n.t(LIST_LABELS[list]))
	_filter.add_item(I18n.t("Added by you or from cards"))
	_filter.item_selected.connect(func(_index: int) -> void: _refresh())
	bar.add_child(_filter)
	_tree = Tree.new()
	_tree.columns = RuleColumn.size()
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.custom_minimum_size.y = AgentTheme.px(240)
	for column: int in RuleColumn.size():
		_tree.set_column_title(column, I18n.t(COLUMN_TITLES[column]))
		_tree.set_column_expand(column, column == RuleColumn.PATTERN)
	_tree.set_column_custom_minimum_width(RuleColumn.LIST, AgentTheme.px(110))
	_tree.set_column_custom_minimum_width(RuleColumn.ORIGIN, AgentTheme.px(170))
	_tree.set_column_custom_minimum_width(RuleColumn.ADDED, AgentTheme.px(100))
	_tree.item_edited.connect(_on_item_edited)
	add_child(_tree)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	_pattern_edit = LineEdit.new()
	_pattern_edit.placeholder_text = I18n.t("e.g. npm test *")
	_pattern_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pattern_edit.text_submitted.connect(func(_text: String) -> void: _on_add())
	add_row.add_child(_pattern_edit)
	_list_option = OptionButton.new()
	for list: String in LISTS:
		_list_option.add_item(I18n.t(LIST_LABELS[list]))
	add_row.add_child(_list_option)
	var add := Button.new()
	add.text = I18n.t("Add")
	add.pressed.connect(_on_add)
	add_row.add_child(add)
	var actions := HBoxContainer.new()
	add_child(actions)
	var remove := Button.new()
	remove.text = I18n.t("Remove selected")
	remove.pressed.connect(_on_remove)
	actions.add_child(remove)
	var defaults := Button.new()
	defaults.text = I18n.t("Restore the default rules")
	defaults.tooltip_text = I18n.t("Puts back the default rules and keeps the ones added by you or from cards.")
	defaults.pressed.connect(_on_restore_defaults)
	actions.add_child(defaults)


func load_from(rules: Array) -> void:
	_rules = rules.duplicate(true)
	_refresh()


func rules() -> Array:
	return _rules.duplicate(true)


## Mensaje del primer problema, o "".
func validate() -> String:
	var seen: Dictionary = {}
	for rule: Dictionary in _rules:
		var pattern := str(rule.get("pattern", ""))
		if pattern.is_empty():
			return I18n.t("Auto mode: a rule has an empty pattern.")
		var key := "%s|%s" % [rule.get("list"), pattern]
		if seen.has(key):
			return I18n.t("Auto mode: «%s» is twice in the same list.") % pattern
		seen[key] = true
	return ""


func _refresh() -> void:
	_classify_test()
	_tree.clear()
	var root := _tree.create_item()
	var first_highlighted: TreeItem = null
	for index: int in _rules.size():
		var rule: Dictionary = _rules[index]
		if not _passes_filter(rule):
			continue
		var item := _tree.create_item(root)
		item.set_metadata(RuleColumn.PATTERN, index)
		item.set_text(RuleColumn.PATTERN, str(rule.get("pattern", "")))
		item.set_editable(RuleColumn.PATTERN, true)
		item.set_cell_mode(RuleColumn.LIST, TreeItem.CELL_MODE_RANGE)
		item.set_text(RuleColumn.LIST, ",".join(Array(LISTS).map(func(list: String) -> String: return I18n.t(LIST_LABELS[list]))))
		item.set_range(RuleColumn.LIST, maxi(LISTS.find(str(rule.get("list", ""))), 0))
		item.set_editable(RuleColumn.LIST, true)
		item.set_text(RuleColumn.ORIGIN, I18n.t(ORIGIN_LABELS.get(str(rule.get("origin", "")), ORIGIN_LABELS[ShellRules.ORIGIN_USER])))
		item.set_text(RuleColumn.ADDED, str(rule.get("added", "")))
		if rule.get("list") == ShellRules.LIST_ASK:
			item.set_custom_color(RuleColumn.LIST, AgentTheme.WARNING)
		if str(rule.get("pattern", "")) in _highlight:
			for column: int in RuleColumn.size():
				item.set_custom_bg_color(column, Color(AgentTheme.WARNING if rule.get("list") == ShellRules.LIST_ASK else AgentTheme.ADDED, 0.18))
			if first_highlighted == null:
				first_highlighted = item
	if first_highlighted and _tree.is_inside_tree():
		_tree.scroll_to_item(first_highlighted)


## Clasifica el comando de prueba con las reglas en edición y deja el resultado en la etiqueta.
func _classify_test() -> void:
	var command := _test_edit.text.strip_edges() if _test_edit else ""
	_highlight = []
	if command.is_empty():
		_test_result.visible = false
		return
	var verdict := ShellRules.classify(command, _rules)
	if not str(verdict.rule).is_empty():
		_highlight = str(verdict.rule).split(", ")
	_test_result.visible = true
	_test_result.text = describe_verdict(verdict)
	_test_result.add_theme_color_override(&"font_color", AgentTheme.ADDED if verdict.decision == ShellRules.ALLOW else AgentTheme.WARNING)


## El resultado de `ShellRules.classify` en una frase traducida.
static func describe_verdict(verdict: Dictionary) -> String:
	var segment := str(verdict.get("segment", ""))
	match str(verdict.get("code", "")):
		ShellRules.CODE_ALLOWED:
			return I18n.t("Runs without asking: every part is on the allowlist (%s).") % verdict.rule
		ShellRules.CODE_ASK_LIST:
			return I18n.t("Asks: «%s» is on the «Always ask» list (%s).") % [segment, verdict.rule]
		ShellRules.CODE_NOT_ALLOWED:
			return I18n.t("Asks: «%s» is not on the allowlist.") % segment
		ShellRules.CODE_SUBSTITUTION:
			return I18n.t("Asks: it runs a command inside another one ($(…), backticks or <(…)), and the lists can't judge that.")
		ShellRules.CODE_REDIRECT:
			return I18n.t("Asks: it writes its output to a file (%s).") % (segment if not segment.is_empty() else "…")
		ShellRules.CODE_QUOTE:
			return I18n.t("Asks: a quote is not closed.")
	return I18n.t("Asks.")


func _passes_filter(rule: Dictionary) -> bool:
	match _filter.selected:
		1:
			return rule.get("list") == ShellRules.LIST_ALLOW
		2:
			return rule.get("list") == ShellRules.LIST_ASK
		3:
			return rule.get("origin") != ShellRules.ORIGIN_DEFAULT
	return true


## Editar una regla la vuelve del usuario: así se ve qué se cambió respecto de los defaults.
func _on_item_edited() -> void:
	var item := _tree.get_edited()
	if not item:
		return
	var index: int = item.get_metadata(RuleColumn.PATTERN)
	var rule: Dictionary = _rules[index]
	var pattern := ShellRules.normalize(item.get_text(RuleColumn.PATTERN))
	var list: String = LISTS[clampi(int(item.get_range(RuleColumn.LIST)), 0, LISTS.size() - 1)]
	if pattern == rule.get("pattern") and list == rule.get("list"):
		return
	_rules[index] = ShellRules.make_rule(pattern, list, ShellRules.ORIGIN_USER, ShellRules.today())
	_refresh.call_deferred()


func _on_add() -> void:
	var pattern := ShellRules.normalize(_pattern_edit.text)
	if pattern.is_empty():
		return
	var list: String = LISTS[_list_option.selected]
	for rule: Dictionary in _rules:
		if rule.get("pattern") == pattern and rule.get("list") == list:
			return
	_rules.append(ShellRules.make_rule(pattern, list, ShellRules.ORIGIN_USER, ShellRules.today()))
	_pattern_edit.text = ""
	_refresh()


func _on_remove() -> void:
	var selected := _tree.get_selected()
	if not selected:
		return
	_rules.remove_at(int(selected.get_metadata(RuleColumn.PATTERN)))
	_refresh()


func _on_restore_defaults() -> void:
	var kept: Array = _rules.filter(func(rule: Dictionary) -> bool: return rule.get("origin") != ShellRules.ORIGIN_DEFAULT)
	_rules = ShellRules.default_rules()
	for rule: Dictionary in kept:
		var duplicate := _rules.any(func(existing: Dictionary) -> bool: return existing.pattern == rule.get("pattern") and existing.list == rule.get("list"))
		if not duplicate:
			_rules.append(rule)
	_refresh()


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	return label
