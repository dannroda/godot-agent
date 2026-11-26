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
