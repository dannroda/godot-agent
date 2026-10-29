@tool
extends VBoxContainer
## Las sesiones anteriores del proyecto en el dock vacío (m12-12): título, «agente · cuándo · N
## turnos» y «Continuar».

signal continue_requested(id: String)

const AgentTheme := preload("../agent_theme.gd")
const I18n := preload("../../core/i18n.gd")

var _signature: String = ""


func _init() -> void:
	name = "RecentSessions"
	add_theme_constant_override(&"separation", AgentTheme.px(6))


## Muestra `items` (resúmenes de SessionHistory.list); vacía, se oculta.
func show_items(items: Array[Dictionary]) -> void:
	var signature := ",".join(items.map(func(item: Dictionary) -> String: return "%s:%s" % [item.get("id", ""), item.get("updated", 0)]))
	visible = not items.is_empty()
	if signature == _signature:
		return
	_signature = signature
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	if items.is_empty():
		return
	var heading := Label.new()
	heading.text = I18n.t("Previous sessions")
	heading.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	add_child(heading)
	for item: Dictionary in items:
		add_child(_row(item))


func _row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", AgentTheme.px(8))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override(&"separation", 0)
	row.add_child(text)
	var title := Label.new()
	title.text = str(item.get("title", "")) if not str(item.get("title", "")).is_empty() else I18n.t("(untitled)")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.tooltip_text = title.text
	text.add_child(title)
	var meta := Label.new()
	meta.text = recent_meta(item, timezone_bias_s())
	meta.add_theme_color_override(&"font_color", AgentTheme.MUTED)
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.clip_text = true
	text.add_child(meta)
	var resume := Button.new()
	resume.text = I18n.t("Continue")
	resume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var id := str(item.get("id", ""))
	resume.pressed.connect(func() -> void: continue_requested.emit(id))
	row.add_child(resume)
	return row


## «Claude Code · 29/10 03:56 · 4 turns».
static func recent_meta(item: Dictionary, bias_s: int = 0) -> String:
	var parts: PackedStringArray = []
	if not str(item.get("agent", "")).is_empty():
		parts.append(str(item.agent))
	var updated := int(item.get("updated", 0))
	if updated > 0:
		var stamp := Time.get_datetime_string_from_unix_time(updated + bias_s, true)
		parts.append("%s/%s %s" % [stamp.substr(8, 2), stamp.substr(5, 2), stamp.substr(11, 5)])
	var turns := int(item.get("turns", 0))
	if turns > 0:
		parts.append((I18n.t("%d turn") if turns == 1 else I18n.t("%d turns")) % turns)
	return " · ".join(parts)


static func timezone_bias_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
