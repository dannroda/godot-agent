@tool
extends RefCounted
## Lado editor del autoload de playtest: alta, baja y limpieza.
## El autoload solo existe mientras corre un playtest pedido por el harness (spec §6).

const NAME := "GodotAgentPlaytest"
const SETTING := "autoload/" + NAME
const SCRIPT_PATH := "res://addons/godot_agent/playtest/runtime/playtest_probe.gd"

## Solo para tests: deja vivo un autoload huérfano al arrancar, para probar el guard de export.
const KEEP_ORPHAN_ENV := "GODOT_AGENT_TEST_KEEP_ORPHAN_AUTOLOAD"


static func is_registered() -> bool:
	return ProjectSettings.has_setting(SETTING)


## Alta, justo antes de correr (EditorPlugin._build). El juego es otro proceso que lee
## project.godot del disco: alcanza con el setting guardado. No pasa por add_autoload_singleton, que
## arma una acción de deshacer y actualiza la lista de autoloads del editor en medio del play; en 4.7
## eso corrompía una lista del editor (`List::erase`, «p_I->data != this») y después de varios runs el
## editor se caía (m16-08).
static func register(_plugin: EditorPlugin) -> void:
	if not is_registered():
		ProjectSettings.set_setting(SETTING, "*" + SCRIPT_PATH)
	ProjectSettings.save()


## Quita el autoload si está registrado. Devuelve true si había algo que quitar.
static func unregister(_plugin: EditorPlugin) -> bool:
	if not is_registered():
		return false
	ProjectSettings.set_setting(SETTING, null)
	ProjectSettings.save()
	return true


## Limpieza al arrancar el plugin: si quedó registrado (editor crasheado a mitad de un playtest), se quita.
static func remove_orphan(plugin: EditorPlugin) -> void:
	if OS.get_environment(KEEP_ORPHAN_ENV) == "1":
		return
	if unregister(plugin):
		push_warning("Godot Agent: removed the leftover playtest autoload '%s'." % NAME)
