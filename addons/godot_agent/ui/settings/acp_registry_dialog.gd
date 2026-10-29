@tool
extends AcceptDialog
## Agentes del registro de ACP (m11-12): la lista con buscador y «Agregar», que arma el perfil
## (npx o uvx) o baja e instala el binario de esta plataforma. Un binario sin sha256 en el
## registro pide un segundo clic, porque no hay cómo verificar lo que se baja.

signal profile_added(profile: Dictionary)

const I18n := preload("../../core/i18n.gd")
const AgentTheme := preload("../agent_theme.gd")
const AcpRegistry := preload("../../core/acp_registry.gd")
const ExtensionsUi := preload("../extensions/extensions_ui.gd")
const SuggestedAgents := preload("../../core/suggested_agents.gd")

## `() -> PackedStringArray`: los ids de los perfiles que ya están en Ajustes. Lo pone Ajustes.
var added_ids: Callable

var registry: AcpRegistry
var _agents: Array[Dictionary] = []
var _query: LineEdit
var _box: VBoxContainer
var _status: Label
var _progress: ProgressBar
var _busy: bool = false
var _downloading: String = ""  # nombre del agente cuyo binario se está bajando


func _init() -> void:
	title = I18n.t("Agents from the ACP registry")
	ok_button_text = I18n.t("Close")
	# Sin wrap_controls la ventana no crece con la lista (~40 agentes): scrollea, como Extensiones.
	wrap_controls = false
	min_size = Vector2i(AgentTheme.px(480), AgentTheme.px(400))
	registry = AcpRegistry.new()
	add_child(registry)
	var page := VBoxContainer.new()
	add_child(page)
	page.add_child(ExtensionsUi.muted(I18n.t("Agents that speak ACP, from the public registry that Zed and JetBrains use. Adding one creates its profile; a program is downloaded only for agents that ship one for this platform.")))
	_query = LineEdit.new()
	_query.placeholder_text = I18n.t("Filter by name, author or description")
	_query.clear_button_enabled = true
	_query.text_changed.connect(func(_text: String) -> void: _rebuild())
	page.add_child(_query)
	_box = ExtensionsUi.scroll_list(page)
	_status = ExtensionsUi.muted("")
	page.add_child(_status)
	_progress = ProgressBar.new()
	_progress.visible = false
	_progress.editor_preview_indeterminate = true  # el diálogo corre en el editor: sin esto no se anima ni se dibuja
	page.add_child(_progress)
	registry.unpacking.connect(func() -> void:
		_downloading = ""
		_progress.indeterminate = true
		_status.text = I18n.t("Verifying and unpacking…"))
	set_process(false)


func _process(_delta: float) -> void:
	if _downloading.is_empty():
		return
	var bytes: Array[int] = registry.download_progress()
	var done := String.humanize_size(bytes[0])
	_progress.indeterminate = bytes[1] <= 0
	if bytes[1] > 0:
		_progress.value = 100.0 * bytes[0] / bytes[1]
		_status.text = I18n.t("Downloading %s: %s of %s") % [_downloading, done, String.humanize_size(bytes[1])]
	else:
		_status.text = I18n.t("Downloading %s: %s") % [_downloading, done]


## Abre el diálogo y, la primera vez, lee el registro. `query` lo abre filtrado.
func open(query: String = "") -> void:
	_query.text = query
	popup_centered_clamped(Vector2i(AgentTheme.px(560), AgentTheme.px(560)), 0.8)
	ExtensionsUi.refit_dialog(self)
	if _agents.is_empty() and not _busy:
		_busy = true
		_status.text = I18n.t("Reading the ACP registry…")
		var result: Dictionary = await registry.fetch()
		_busy = false
		_agents = result.agents
		_status.text = I18n.t("Could not read the ACP registry: %s") % result.error if not result.error.is_empty() else I18n.t("%d agents for this platform.") % _agents.size()
	_rebuild()


## Los agentes que coinciden con el filtro (todas las palabras, sin mayúsculas).
static func filter(agents: Array[Dictionary], query: String) -> Array[Dictionary]:
	var words := query.to_lower().split(" ", false)
	return agents.filter(func(agent: Dictionary) -> bool:
		var text := " ".join(PackedStringArray([agent.name, agent.id, agent.description, ", ".join(agent.authors)])).to_lower()
		return Array(words).all(func(word: String) -> bool: return text.contains(word)))


## Agregados primero, después los sugeridos y al final el resto por nombre (m12-27):
## `[{group: "added"|"suggested"|"other", agents}]`, sin grupos vacíos.
static func grouped(agents: Array[Dictionary], added: PackedStringArray) -> Array[Dictionary]:
	var groups := {"added": [], "suggested": [], "other": []}
	for agent: Dictionary in agents:
		if added.has(str(agent.id)):
			groups.added.append(agent)
		elif is_suggested(agent):
			groups.suggested.append(agent)
		else:
			groups.other.append(agent)
	var result: Array[Dictionary] = []
	for key: String in ["added", "suggested", "other"]:
		if not (groups[key] as Array).is_empty():
			result.append({"group": key, "agents": groups[key]})
	return result


## Uno de los agentes sugeridos (Claude Code, Codex, Antigravity): su id o su nombre lo nombra.
static func is_suggested(agent: Dictionary) -> bool:
	var text := ("%s %s" % [agent.id, agent.name]).to_lower()
	for suggested: Dictionary in SuggestedAgents.AGENTS:
		if text.contains(str(suggested.key)):
			return true
	return false


## «npx · se baja al usarlo», «uvx · …» o «programa para esta plataforma · 912 MB».
static func install_summary(agent: Dictionary) -> String:
	match agent.kind:
		AcpRegistry.KIND_NPX:
			return I18n.t("npx %s · Node.js downloads it the first time") % agent.package
		AcpRegistry.KIND_UVX:
			return I18n.t("uvx %s · uv downloads it the first time") % agent.package
	var size := int((agent.binary as Dictionary).get("size", 0))
	return I18n.t("program for this platform · %s download") % String.humanize_size(size) if size > 0 else I18n.t("program for this platform: the harness downloads it")


func _rebuild() -> void:
	ExtensionsUi.clear(_box)
	var added: PackedStringArray = added_ids.call() if added_ids.is_valid() else PackedStringArray()
	var titles := {"added": I18n.t("Already added"), "suggested": I18n.t("Suggested"), "other": I18n.t("All agents")}
	for group: Dictionary in grouped(filter(_agents, _query.text), added):
		var heading := ExtensionsUi.muted(titles[group.group])
		_box.add_child(heading)
		for agent: Dictionary in group.agents:
			_box.add_child(_agent_card(agent, group.group == "added"))


func _agent_card(agent: Dictionary, added := false) -> Control:
	var card := ExtensionsUi.card()
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var heading := Label.new()
	heading.text = "%s %s" % [agent.name, agent.version]
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(heading)
	var add := Button.new()
	# Ya en disco: «Reinstalar» borra esa versión y la vuelve a bajar (m12-13).
	var installed := registry.is_installed(agent)
	add.text = I18n.t("Reinstall") if installed else (I18n.t("Add again") if added else I18n.t("Add"))
	if added and not installed:
		add.tooltip_text = I18n.t("It's already in your agents: adding it again replaces its profile with the registry's.")
	var unverified: bool = agent.kind == AcpRegistry.KIND_BINARY and str(agent.binary.sha256).is_empty()
	if unverified:
		add.tooltip_text = I18n.t("The registry has no checksum for this download: it can't be verified.")
	add.pressed.connect(func() -> void:
		if unverified and not installed and add.text != I18n.t("Add without checksum"):
			add.text = I18n.t("Add without checksum")
			return
		_add(agent, add, installed))
	row.add_child(add)
	if not str(agent.description).is_empty():
		column.add_child(ExtensionsUi.muted(agent.description))
	var meta: PackedStringArray = []
	if added:
		meta.append(I18n.t("✓ added"))
	if not agent.authors.is_empty():
		meta.append(I18n.t("by %s") % ", ".join(agent.authors))
	meta.append(install_summary(agent))
	column.add_child(ExtensionsUi.muted(" · ".join(meta)))
	return card


func _add(agent: Dictionary, button: Button, reinstall := false) -> void:
	if _busy:
		return
	_busy = true
	button.disabled = true
	# Un binario puede pesar cientos de MB (el de Antigravity, ~900): se ve cuánto va.
	if agent.kind == AcpRegistry.KIND_BINARY:
		_downloading = agent.name
		_progress.value = 0
		_progress.visible = true
		set_process(true)
	else:
		_status.text = I18n.t("Installing %s…") % agent.name
	var result: Dictionary = await registry.install(agent, reinstall)
	set_process(false)
	_progress.visible = false
	_busy = false
	button.disabled = false
	if not result.ok:
		_status.text = I18n.t("Could not add %s: %s") % [agent.name, result.error]
		return
	_status.text = I18n.t("%s added to the agents. Save the settings to keep it.") % agent.name
	profile_added.emit(result.profile)
	_rebuild()  # pasa a «Ya agregados»
