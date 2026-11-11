@tool
extends VBoxContainer
## Qué puede hacer el agente (m12-46): las tools godot.* del server MCP del addon, agrupadas por
## función, con la descripción corta que ve el agente, su grupo de permisos y qué pide en cada modo
## (✓ sin preguntar, ? pregunta, ✗ no). Las tools que la lista compacta esconde van marcadas: el
## agente llega a ellas por godot.methods / godot.run. Un filtro busca por nombre, descripción y grupo.

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")
const SessionModel := preload("../../session/session_model.gd")
const ToolSummaries := preload("../../mcp/tool_summaries.gd")
const MachineApproval := preload("../../core/machine_approval.gd")

## Nombre del proveedor (ToolRegistry.category_of) → título del grupo, en el orden en que se muestran.
const CATEGORY_LABELS: Dictionary = {
	"read": "Read the project",  # i18n
	"scene_edit": "Edit scenes",  # i18n
	"file": "Files",  # i18n
	"run": "Run the game",  # i18n
	"diagnostic": "Diagnostics",  # i18n
	"validate": "Validation",  # i18n
	"project": "Project",  # i18n
	"resource": "Resources",  # i18n
	"tilemap": "TileMaps",  # i18n
	"animation": "Animation",  # i18n
	"api": "Godot API",  # i18n
	"asset": "Asset Store",  # i18n
	"profile": "Profiler",  # i18n
	"session": "Sessions",  # i18n
	"agent_tools": "Project tools",  # i18n
}
const MODES: Array[SessionModel.HarnessMode] = [SessionModel.HarnessMode.ASK, SessionModel.HarnessMode.REVIEW, SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO, SessionModel.HarnessMode.ONESHOT]
const COLUMN_NAME := 0
const COLUMN_SUMMARY := 1
const COLUMN_GROUP := 2
const COLUMN_MODES := 3
const MARKS: Dictionary = {PermissionPolicy.ALLOW: "✓", PermissionPolicy.ASK: "?", PermissionPolicy.DENY: "✗"}

## () -> Array[Dictionary]: ToolRegistry.catalog().
var catalog_provider: Callable
## () -> PermissionPolicy: la política del proyecto (sin los permisos concedidos en una sesión).
var policy_provider: Callable
## () -> bool: la lista compacta está activa (Ajustes).
var compact_provider: Callable
## (data) -> void: abre «Aprobar…» de una tool del proyecto frenada (m11-46).
var approve: Callable

var _filter: LineEdit
var _tree: Tree
var _count: Label
var _note: Label
var _catalog: Array = []
var _allow: Button


func _init() -> void:
	name = "Tools"
	add_theme_constant_override(&"separation", AgentTheme.px(6))
	var intro := Label.new()
	intro.text = I18n.t("Everything the agent can do in the editor through the addon's MCP server, by function. The last column says what each tool asks for in each mode, in this order: Ask, Review, Build, Auto, One-shot (✓ without asking · ? asks you · ✗ not allowed); change it in Settings → Permissions.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	add_child(intro)
	var bar := HBoxContainer.new()
	add_child(bar)
	_filter = LineEdit.new()
	_filter.placeholder_text = I18n.t("Search tools…")
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(func(_text: String) -> void: _rebuild())
	bar.add_child(_filter)
	_count = Label.new()
	_count.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	bar.add_child(_count)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = COLUMN_MODES + 1
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.set_column_title(COLUMN_NAME, I18n.t("Tool"))
	_tree.set_column_title(COLUMN_SUMMARY, I18n.t("What it does"))
	_tree.set_column_title(COLUMN_GROUP, I18n.t("Permission"))
	# Tool y Qué hace se reparten el ancho; el mínimo de Tool deja entera la categoría más larga.
	_tree.set_column_expand(COLUMN_NAME, true)
	_tree.set_column_expand_ratio(COLUMN_NAME, 2)
	_tree.set_column_custom_minimum_width(COLUMN_NAME, AgentTheme.px(172))
	_tree.set_column_expand(COLUMN_SUMMARY, true)
	_tree.set_column_expand_ratio(COLUMN_SUMMARY, 3)
	_tree.set_column_custom_minimum_width(COLUMN_SUMMARY, AgentTheme.px(120))
	_tree.set_column_expand(COLUMN_GROUP, false)
	_tree.set_column_custom_minimum_width(COLUMN_GROUP, AgentTheme.px(78))
	_tree.set_column_title(COLUMN_MODES, I18n.t("By mode"))
	_tree.set_column_expand(COLUMN_MODES, false)
	_tree.set_column_custom_minimum_width(COLUMN_MODES, AgentTheme.px(104))
	_tree.set_column_title_alignment(COLUMN_MODES, HORIZONTAL_ALIGNMENT_CENTER)
	_tree.item_selected.connect(_on_selected)
	add_child(_tree)
	# Una tool del proyecto sin aprobar en esta máquina (m11-46): seleccionada, este botón.
	_allow = Button.new()
	_allow.name = "AllowTool"
	_allow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_allow.visible = false
	_allow.pressed.connect(func() -> void:
		var item := _tree.get_selected()
		if item and approve.is_valid() and item.get_metadata(COLUMN_NAME) is Dictionary:
			approve.call(MachineApproval.request(MachineApproval.KIND_TOOL, [item.get_metadata(COLUMN_NAME)])))
	add_child(_allow)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	_note.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
	add_child(_note)


## Vuelve a leer el catálogo y arma el árbol.
func refresh() -> void:
	_catalog = catalog_provider.call() if catalog_provider.is_valid() else []
	_rebuild()


## Cuántas tools hay (para el título de la pestaña).
func tool_count() -> int:
	return _catalog.size()


func _rebuild() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var policy: PermissionPolicy = policy_provider.call() if policy_provider.is_valid() else PermissionPolicy.new()
	var compact: bool = bool(compact_provider.call()) if compact_provider.is_valid() else false
	var query := _filter.text.strip_edges().to_lower()
	var shown := 0
	var hidden_by_compact := 0
	for category: String in _categories():
		var tools: Array = _catalog.filter(func(tool: Dictionary) -> bool: return str(tool.category) == category and _matches(tool, query))
		if tools.is_empty():
			continue
		var parent := _tree.create_item(root)
		parent.set_text(COLUMN_NAME, "%s (%d)" % [_category_label(category), tools.size()])
		parent.set_selectable(COLUMN_NAME, false)
		parent.collapsed = query.is_empty() and category != str(_categories()[0])
		for tool: Dictionary in tools:
			shown += 1
			var item := _tree.create_item(parent)
			var via_methods: bool = compact and bool(tool.get("extended", false))
			if via_methods:
				hidden_by_compact += 1
			item.set_text(COLUMN_NAME, "godot.%s%s" % [tool.name, " ⋯" if via_methods else ""])
			item.set_tooltip_text(COLUMN_NAME, str(tool.description) + ("\n\n" + I18n.t("With the compact tool list on, the agent reaches it through godot.methods and godot.run.") if via_methods else ""))
			# La línea para las personas, traducida (ToolSummaries); la descripción del agente en el tooltip.
			var summary := ToolSummaries.summary(str(tool.name))
			item.set_text(COLUMN_SUMMARY, summary if not summary.is_empty() else str(tool.summary))
			item.set_tooltip_text(COLUMN_SUMMARY, I18n.t("What the agent reads:") + "\n" + str(tool.description))
			item.set_text_overrun_behavior(COLUMN_SUMMARY, TextServer.OVERRUN_TRIM_ELLIPSIS)
			item.set_text(COLUMN_GROUP, PermissionPolicy.group_label(str(tool.group)))
			item.set_text(COLUMN_MODES, mode_marks(policy, str(tool.group)))
			item.set_text_alignment(COLUMN_MODES, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_tooltip_text(COLUMN_MODES, mode_tooltip(policy, str(tool.group)))
			if tool.has("state"):
				# Del proyecto, sin cargar: frenada (sin aprobar) o con un error que dice qué arreglar.
				item.set_text(COLUMN_SUMMARY, I18n.t("Not approved on this machine") if tool.has("held") else str(tool.summary))
				item.set_custom_color(COLUMN_NAME, AgentTheme.WARNING)
				item.set_custom_color(COLUMN_SUMMARY, AgentTheme.WARNING)
				if tool.has("held"):
					item.set_metadata(COLUMN_NAME, tool.held)
	_count.text = I18n.t("%d of %d tools") % [shown, _catalog.size()] if not query.is_empty() else I18n.t("%d tools") % _catalog.size()
	_note.text = I18n.t("⋯ %d tools are behind godot.methods / godot.run because the compact tool list is on (Settings → MCP servers → Advanced).") % hidden_by_compact if hidden_by_compact > 0 else ""
	_note.visible = not _note.text.is_empty()
	_on_selected()


func _on_selected() -> void:
	var item := _tree.get_selected()
	var held: Variant = item.get_metadata(COLUMN_NAME) if item else null
	_allow.visible = held is Dictionary
	if held is Dictionary:
		_allow.text = I18n.t("Review and allow «%s» on this machine…") % held.name


## «✓ ✓ ? ✓ ✗»: una marca por modo (Preguntar, Revisar, Construir, Auto, One-shot) para `group`.
static func mode_marks(policy: PermissionPolicy, group: String) -> String:
	var marks: PackedStringArray = []
	for mode in MODES:
		var value := policy.matrix_value(group, mode)
		marks.append(str(MARKS.get(value, value)))
	return " ".join(marks)


## Una línea por modo con lo que pide, para el tooltip de la celda.
static func mode_tooltip(policy: PermissionPolicy, group: String) -> String:
	var lines: PackedStringArray = []
	for mode in MODES:
		lines.append("%s: %s" % [I18n.t(SessionModel.HARNESS_MODE_LABELS[mode]), _mark_tooltip(policy.matrix_value(group, mode))])
	return "\n".join(lines)


## Las categorías del catálogo: primero las conocidas en su orden, después las demás por nombre.
func _categories() -> PackedStringArray:
	var known: PackedStringArray = []
	for category: String in CATEGORY_LABELS:
		known.append(category)
	var others: PackedStringArray = []
	for tool: Dictionary in _catalog:
		var category := str(tool.category)
		if not CATEGORY_LABELS.has(category) and not category in others:
			others.append(category)
	others.sort()
	known.append_array(others)
	return known


static func _category_label(category: String) -> String:
	if CATEGORY_LABELS.has(category):
		return I18n.t(CATEGORY_LABELS[category])
	return category.capitalize() if not category.is_empty() else I18n.t("Other")


static func _matches(tool: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var haystack := "godot.%s %s %s %s" % [tool.name, tool.get("description", ""), tool.get("category", ""), PermissionPolicy.group_label(str(tool.group))]
	return haystack.to_lower().contains(query)


static func _mark_tooltip(value: String) -> String:
	match value:
		PermissionPolicy.ALLOW:
			return I18n.t("Runs without asking")
		PermissionPolicy.ASK:
			return I18n.t("Asks you before running")
	return I18n.t("Not allowed in this mode")
