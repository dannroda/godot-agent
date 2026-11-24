@tool
extends ConfirmationDialog
## Elegir variantes (m11-90): lo que propuso el agente con godot.propose_variants, una por fila con su
## casilla y su texto editable, más las que agregue el usuario. «Abrir N copias» se habilita con 2 a 4
## tildadas. pick() se espera con await: {goal, variants} o {} si cerró sin abrir.

signal _decided(result: Dictionary)

const I18n := preload("../core/i18n.gd")
const AgentTheme := preload("agent_theme.gd")
const ExtensionsUi := preload("extensions/extensions_ui.gd")
const Variants := preload("../session/variants.gd")

## Las que vienen tildadas: las primeras, hasta este número.
const CHECKED := 3

var _goal: LineEdit
var _rows: VBoxContainer
var _judges: Label


func _init() -> void:
	title = I18n.t("Try variants in parallel")
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(AgentTheme.px(520), 0)
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("Each variant you check is built by its own agent, in its own tab and copy of the project (from your last commit), all at the same time. It costs about that many times the usage of one.")))
	_goal = LineEdit.new()
	_goal.name = "Goal"
	_goal.placeholder_text = I18n.t("What all the variants try to achieve")
	_goal.text_changed.connect(func(_text: String) -> void: _refresh())
	page.add_child(_goal)
	_rows = VBoxContainer.new()
	page.add_child(_rows)
	var add := Button.new()
	add.name = "AddVariant"
	add.text = I18n.t("Add variant")
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void:
		var line := _add_row("", true).get_child(1) as LineEdit
		if line.is_inside_tree():
			line.grab_focus())
	page.add_child(add)
	_judges = ExtensionsUi.muted("")
	page.add_child(_judges)
	confirmed.connect(func() -> void: _decided.emit({"goal": _goal.text.strip_edges(), "variants": chosen()}))
	canceled.connect(func() -> void: _decided.emit({}))


## Muestra lo propuesto y espera la decisión. `judges`: cuántas regresiones guardadas hay.
func pick(goal: String, variants: PackedStringArray, judges: int) -> Dictionary:
	fill(goal, variants, judges)
	popup_centered()
	return await _decided


func fill(goal: String, variants: PackedStringArray, judges: int) -> void:
	_goal.text = goal
	for row in _rows.get_children():
		row.free()
	for i in variants.size():
		_add_row(variants[i], i < CHECKED)
	_judges.text = I18n.t("%d saved regressions will judge them the same way.") % judges if judges > 0 \
		else I18n.t("⚠ The project has no saved regressions: you will compare the variants by playing them. A playtest that passes saves one.")
	_refresh()


## Las tildadas, limpias (sin vacías ni repetidas).
func chosen() -> PackedStringArray:
	var picked: Array = []
	for row in _rows.get_children():
		if (row.get_child(0) as CheckBox).button_pressed:
			picked.append((row.get_child(1) as LineEdit).text)
	return Variants.clean(picked)


func _add_row(text: String, checked: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var box := CheckBox.new()
	box.button_pressed = checked
	box.toggled.connect(func(_on: bool) -> void: _refresh())
	row.add_child(box)
	var line := LineEdit.new()
	line.text = text
	line.max_length = Variants.TEXT_MAX
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.placeholder_text = I18n.t("Another way to do it, in one line")
	line.text_changed.connect(func(_text: String) -> void: _refresh())
	row.add_child(line)
	_rows.add_child(row)
	_refresh()
	return row


func _refresh() -> void:
	var count := chosen().size()
	var ok := count >= Variants.MIN and count <= Variants.MAX and not _goal.text.strip_edges().is_empty()
	get_ok_button().disabled = not ok
	get_ok_button().text = I18n.t("Open %d copies") % count if ok else I18n.t("Check 2 to 4 variants")
