@tool
extends RefCounted
## Base de una tool propia del proyecto (m11-46): un archivo en res://agent_tools/ (o la carpeta de
## Settings → MCP servers → Avanzado) que el agente llama con godot.run. El nombre de la tool es el
## del archivo: res://agent_tools/build_level.gd es godot.build_level.
##
##     @tool
##     extends "res://addons/godot_agent/api/agent_tool.gd"
##
##     func _description() -> String:
##         return "Builds a level from a CSV of tile names."
##
##     func _parameters() -> Dictionary:
##         return {"properties": {"csv": {"type": "string"}}, "required": ["csv"]}
##
##     func _run(args: Dictionary, ctx) -> Variant:
##         ...
##         return "Built 12 rooms."
##
## El script lleva @tool (no se hereda) y no lleva class_name. Corre en el editor, en el hilo
## principal, con todo lo que puede un script @tool: solo se carga en una máquina donde alguien aprobó
## ese código, y cada llamada pide el permiso del grupo «Project tools».


## Lo que hace la tool, para el agente: la primera oración sale en godot.methods.
func _description() -> String:
	return ""


## Los parámetros como JSON schema de un objeto: `{"properties": {...}, "required": [...]}`.
func _parameters() -> Dictionary:
	return {}


## Corre la tool. `args` ya pasó por el schema; `ctx` es un AgentToolContext (api/agent_tool_context.gd)
## con undo_redo, project_dir y note(). Devuelve un String, una Image, un Dictionary o un Array
## (van como JSON) o un resultado MCP `{content, isError}`. Puede usar await.
func _run(_args: Dictionary, _ctx: RefCounted) -> Variant:
	return "This tool doesn't implement _run()."


## Un resultado de error para el agente, con un motivo que pueda corregir.
static func error(message: String) -> Dictionary:
	return {"content": [{"type": "text", "text": message}], "isError": true}
