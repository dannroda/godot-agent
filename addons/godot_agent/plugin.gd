@tool
extends EditorPlugin
## Punto de entrada del plugin (plugin.cfg). Al habilitarlo, el editor vuelve a compilar este script sin
## caché, y eso cuesta en proporción a los scripts que nombra: ~1,8 ms por cada uno, que el plugin entero
## llevaba a ~180 ms (heredar de otro script cuesta lo mismo que nombrar lo suyo). Por eso este no nombra
## ninguno: la raíz de composición es agent_plugin.gd, un Node hijo que se carga con load() (ya compilado
## desde el primer enable) y hace todo lo del plugin a través de este EditorPlugin (m16-15).

const AGENT_PLUGIN_PATH := "res://addons/godot_agent/agent_plugin.gd"

## agent_plugin.gd. Sin tipo a propósito: con tipo, el editor compilaría su interfaz al habilitar.
var agent: Node


func _enter_tree() -> void:
	agent = _agent_script().new(self)
	add_child(agent)


## agent_plugin.gd ya pasó por su _exit_tree (los hijos salen antes que el padre).
func _exit_tree() -> void:
	if is_instance_valid(agent):
		agent.queue_free()
	agent = null


## Justo antes de correr el juego.
func _build() -> bool:
	return agent.build() if is_instance_valid(agent) else true


func _has_main_screen() -> bool:
	return _agent_script().has_main_screen()


func _make_visible(visible: bool) -> void:
	if is_instance_valid(agent):
		agent.make_visible(visible)


func _get_plugin_name() -> String:
	return _agent_script().plugin_name()


func _get_plugin_icon() -> Texture2D:
	return _agent_script().plugin_icon()


static func _agent_script() -> Script:
	return load(AGENT_PLUGIN_PATH)
