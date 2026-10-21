@tool
extends VBoxContainer
## Base de las vistas de entradas del dock. Cada vista muestra una ChatEntry y se refresca cuando
## el SessionModel avisa que cambió. Las acciones del usuario salen por `action_requested`.

## `action` es un id ("retry", "show_log", "open_location"…); `payload` depende de la acción.
signal action_requested(action: String, payload: Variant)

const ChatEntry := preload("../../../session/chat_entry.gd")
const AgentTheme := preload("../../agent_theme.gd")
const MarkdownBBCode := preload("../../markdown/markdown_bbcode.gd")

var entry: ChatEntry
var accent: Color = AgentTheme.CHANNEL_COLORS[&"perm"]
var markdown: MarkdownBBCode


func setup(chat_entry: ChatEntry, accent_color: Color, converter: MarkdownBBCode) -> void:
	entry = chat_entry
	accent = accent_color
	markdown = converter


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", AgentTheme.px(4))
	_build()
	refresh()


## Arma los nodos (una vez).
func _build() -> void:
	pass


## Vuelve a leer `entry`. Puede llamarse muchas veces seguidas (streaming).
func refresh() -> void:
	pass


static func make_rich_label(selectable: bool = true) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = selectable
	label.context_menu_enabled = selectable
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override(&"mono_font", AgentTheme.mono_font())
	return label
