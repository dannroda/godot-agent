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
## project.godot del disco, y add_autoload_singleton no guarda: se guarda acá.
static func register(plugin: EditorPlugin) -> void:
	if not is_registered():
		plugin.add_autoload_singleton(NAME, SCRIPT_PATH)
	ProjectSettings.save()


## Quita el autoload si está registrado. Devuelve true si había algo que quitar.
static func unregister(plugin: EditorPlugin) -> bool:
	if not is_registered():
		return false
	plugin.remove_autoload_singleton(NAME)
	# Durante un export (y con autoloads que el editor no llegó a cargar) remove_autoload_singleton
	# no borra la entrada en el momento: se borra a mano para que no llegue a project.binary.
	if is_registered():
		ProjectSettings.set_setting(SETTING, null)
	ProjectSettings.save()  # remove_autoload_singleton tampoco guarda
	return true


## Limpieza al arrancar el plugin: si quedó registrado (editor crasheado a mitad de un playtest), se quita.
static func remove_orphan(plugin: EditorPlugin) -> void:
	if OS.get_environment(KEEP_ORPHAN_ENV) == "1":
		return
	if unregister(plugin):
		push_warning("Godot Agent: se quitó el autoload de playtest '%s' que había quedado registrado." % NAME)
