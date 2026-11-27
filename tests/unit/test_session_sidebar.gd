extends "test_case.gd"
## m21-20: el estado de cada sesión dice hace cuánto.

const SessionSidebar := preload("res://addons/godot_agent/standalone/session_sidebar.gd")
const I18n := preload("res://addons/godot_agent/core/i18n.gd")


func test_elapsed() -> void:
	var sidebar := SessionSidebar.new()
	assert_eq(sidebar._elapsed("s1", I18n.t("Ready")), "", "recién cambiado, nada")
	sidebar._since["s1"].at -= 5 * 60
	assert_eq(sidebar._elapsed("s1", I18n.t("Ready")), " · " + I18n.t("%s ago") % (I18n.t("%d min") % 5), "listo hace 5 min")
	sidebar._since["s1"] = {"status": I18n.t("Working…"), "at": Time.get_unix_time_from_system() - 2 * 3600}
	assert_eq(sidebar._elapsed("s1", I18n.t("Working…")), " · " + I18n.t("%d h") % 2, "trabajando: cuánto lleva")
	assert_eq(sidebar._elapsed("s1", I18n.t("Not started")), "", "sin arrancar, nada")
	sidebar.free()


## Las sesiones cerradas no quedan en _since.
func test_forgets_closed_sessions() -> void:
	const SessionTabs := preload("res://addons/godot_agent/ui/dock/session_tabs.gd")
	var tabs := SessionTabs.new()
	var sidebar := SessionSidebar.new()
	sidebar.setup(tabs)
	sidebar._since["cerrada"] = {"status": "x", "at": 0.0}
	sidebar._rebuild()
	assert_false(sidebar._since.has("cerrada"), "una sesión que ya no está se olvida")
	sidebar.free()
	tabs.free()


## Los íconos de trazo se guardan y respetan la transparencia del color.
func test_stroke_icon_cache_and_alpha() -> void:
	const AgentTheme := preload("res://addons/godot_agent/ui/agent_theme.gd")
	const LOCK := '<rect x="5" y="11" width="14" height="9" rx="2"/>'
	var solid := AgentTheme.stroke_icon(LOCK, Color.WHITE, 24.0)
	assert_true(solid == AgentTheme.stroke_icon(LOCK, Color.WHITE, 24.0), "el mismo ícono no se rasteriza dos veces")
	var faint := AgentTheme.stroke_icon(LOCK, Color(1, 1, 1, 0.5), 24.0)
	var alpha := func(texture: Texture2D) -> float:
		var image := texture.get_image()
		var best := 0.0
		for y in image.get_height():
			for x in image.get_width():
				best = maxf(best, image.get_pixel(x, y).a)
		return best
	assert_true(alpha.call(faint) < alpha.call(solid) - 0.3, "un color translúcido da un ícono translúcido")
