@tool
extends VBoxContainer
## Primer arranque del dock (m12-15, canvas «Primer arranque»): los agentes sugeridos con lo que
## piden y «Agregar» (el primero, recomendado), los otros caminos y los tres pasos.

## «Agregar» en un sugerido (un elemento de SuggestedAgents.AGENTS).
signal add_requested(agent: Dictionary)
signal registry_requested(query: String)
signal manual_requested

const SuggestedAgents := preload("../../core/suggested_agents.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")


func setup(accent: Color) -> void:
	name = "SuggestedAgents"
	add_theme_constant_override(&"separation", AgentTheme.px(6))
	for agent: Dictionary in SuggestedAgents.AGENTS:
		add_child(_suggested_row(agent, agent == SuggestedAgents.AGENTS[0], accent))
	var links := HFlowContainer.new()
	links.add_theme_constant_override(&"h_separation", AgentTheme.px(16))
	var registry := LinkButton.new()
	registry.text = I18n.t("See all the agents in the ACP registry")
	registry.pressed.connect(func() -> void: registry_requested.emit(""))
	links.add_child(registry)
	var manual := LinkButton.new()
	manual.text = I18n.t("Add one by hand")
	manual.pressed.connect(manual_requested.emit)
	links.add_child(manual)
	for link: LinkButton in [registry, manual]:
		link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		link.add_theme_color_override(&"font_color", accent)
	add_child(links)
	var steps_panel := PanelContainer.new()
	steps_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 6, 10))
	var steps := Label.new()
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steps.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	steps.text = "\n".join([
		"1. " + I18n.t("Add an agent. If it has to be downloaded, the progress shows here."),
		"2. " + I18n.t("Sign in with the account it asks for, from the browser."),
		"3. " + I18n.t("Ask it something, with @ to name nodes and files."),
	])
	steps_panel.add_child(steps)
	add_child(steps_panel)


## Un agente sugerido: nombre, lo que pide y «Agregar».
func _suggested_row(agent: Dictionary, recommended: bool, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 6, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(8))
	card.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	row.add_child(text)
	var name_row := HBoxContainer.new()
	text.add_child(name_row)
	var name_label := Label.new()
	name_label.text = str(agent.name)
	name_row.add_child(name_label)
	if recommended:
		var tag := Label.new()
		tag.text = I18n.t("recommended")
		tag.add_theme_color_override(&"font_color", accent)
		tag.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
		name_row.add_child(tag)
	var needs := Label.new()
	needs.text = I18n.t(str(agent.needs))
	needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	needs.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	text.add_child(needs)
	var add := Button.new()
	add.text = I18n.t("Add")
	add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add.pressed.connect(func() -> void: add_requested.emit(agent))
	if recommended:
		AgentTheme.style_accent_button(add, accent)
	row.add_child(add)
	return card
