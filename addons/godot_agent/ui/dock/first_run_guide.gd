@tool
extends VBoxContainer
## Primer arranque del dock (m12-15; con la forma del rediseño, m21-11): los tres pasos arriba, los
## agentes sugeridos para elegir uno (el primero, recomendado, ya elegido), los otros caminos, el aviso
## de la descarga y un solo botón «Agregar <agente>».

## «Agregar» con el sugerido elegido (un elemento de SuggestedAgents.AGENTS).
signal add_requested(agent: Dictionary)
signal registry_requested(query: String)
signal manual_requested

const SuggestedAgents := preload("../../core/suggested_agents.gd")
const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")

const STEPS := ["Agent", "Account", "First request"]

var _accent: Color
var _group := ButtonGroup.new()
var _cards: Array[Button] = []
var _add: Button
var _picked: Dictionary = {}


func setup(accent: Color) -> void:
	name = "SuggestedAgents"
	_accent = accent
	add_theme_constant_override(&"separation", AgentTheme.px(10))
	add_child(_steps())
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override(&"separation", AgentTheme.px(8))
	for agent: Dictionary in SuggestedAgents.AGENTS:
		cards.add_child(_card(agent, agent == SuggestedAgents.AGENTS[0]))
	add_child(cards)
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
	var note_panel := PanelContainer.new()
	note_panel.add_theme_stylebox_override(&"panel", AgentTheme.panel(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 8, 10))
	var note := Label.new()
	note.name = "DownloadNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	note.text = I18n.t("The first time, its program is downloaded: it can take a minute. Then you sign in with the account it asks for, from the browser.")
	note_panel.add_child(note)
	add_child(note_panel)
	_add = Button.new()
	_add.name = "AddAgentButton"
	_add.custom_minimum_size.y = AgentTheme.px(40)
	AgentTheme.style_accent_button(_add, accent, 8, 8)
	_add.pressed.connect(func() -> void: add_requested.emit(_picked))
	add_child(_add)
	pick(SuggestedAgents.AGENTS[0])


## Elige el agente que agrega el botón.
func pick(agent: Dictionary) -> void:
	_picked = agent
	for card: Button in _cards:
		var on: bool = card.get_meta(&"agent") == agent
		card.set_pressed_no_signal(on)
		_style_card(card, on)
	_add.text = I18n.t("Add %s") % str(agent.name)


## Los tres pasos, el primero marcado.
func _steps() -> Control:
	var row := HBoxContainer.new()
	row.name = "Steps"
	row.add_theme_constant_override(&"separation", AgentTheme.px(6))
	for i in STEPS.size():
		var step := VBoxContainer.new()
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.add_theme_constant_override(&"separation", AgentTheme.px(4))
		var bar := Panel.new()
		bar.custom_minimum_size.y = AgentTheme.px(3)
		bar.add_theme_stylebox_override(&"panel", AgentTheme.panel(_accent if i == 0 else Color(1, 1, 1, 0.14), Color.TRANSPARENT, 2, 0))
		step.add_child(bar)
		var label := Label.new()
		label.text = "%d · %s" % [i + 1, I18n.t(STEPS[i])]
		label.add_theme_font_size_override(&"font_size", AgentTheme.px(12))
		if i > 0:
			label.add_theme_color_override(&"font_color", AgentTheme.MUTED)
		step.add_child(label)
		row.add_child(step)
	return row


## Un agente sugerido para elegir: el círculo, el nombre y lo que pide.
func _card(agent: Dictionary, recommended: bool) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = _group
	card.set_meta(&"agent", agent)
	card.pressed.connect(pick.bind(agent))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, AgentTheme.px(12))
	card.add_child(margin)
	# Un botón no cuenta el alto de sus hijos: toma el de su contenido.
	margin.minimum_size_changed.connect(func() -> void: card.custom_minimum_size.y = margin.get_combined_minimum_size().y)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", AgentTheme.px(10))
	margin.add_child(row)
	var radio := TextureRect.new()
	radio.name = "Radio"
	radio.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	radio.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(radio)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override(&"separation", AgentTheme.px(2))
	row.add_child(text)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_row)
	var name_label := Label.new()
	name_label.text = str(agent.name)
	name_row.add_child(name_label)
	if recommended:
		var tag := Label.new()
		tag.text = I18n.t("recommended")
		tag.add_theme_color_override(&"font_color", _accent)
		tag.add_theme_font_size_override(&"font_size", AgentTheme.px(11))
		name_row.add_child(tag)
	var needs := Label.new()
	needs.text = I18n.t(str(agent.needs))
	needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	needs.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	text.add_child(needs)
	_cards.append(card)
	return card


func _style_card(card: Button, on: bool) -> void:
	var bg := Color(_accent, 0.1) if on else Color(1, 1, 1, 0.04)
	var border := Color(_accent, 0.6) if on else Color(1, 1, 1, 0.1)
	for state: StringName in [&"normal", &"pressed", &"hover_pressed", &"focus"]:
		card.add_theme_stylebox_override(state, AgentTheme.panel(bg, border, 10, 0))
	card.add_theme_stylebox_override(&"hover", AgentTheme.panel(Color(1, 1, 1, 0.08), border, 10, 0))
	var radio := card.find_child("Radio", true, false) as TextureRect
	radio.texture = _radio_icon(on)


## El círculo de la opción: lleno de acento si está elegida, un aro gris si no.
func _radio_icon(on: bool) -> Texture2D:
	var side := AgentTheme.px(16)
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2(side, side) / 2.0
	var outer := side / 2.0
	for y in side:
		for x in side:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var color := Color.TRANSPARENT
			if on:
				color = _accent if d <= outer and (d >= outer - side * 0.3 or d <= outer * 0.35) else Color.TRANSPARENT
			elif d <= outer and d >= outer - maxf(1.5, side * 0.12):
				color = Color(1, 1, 1, 0.45)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
