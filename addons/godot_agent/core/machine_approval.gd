@tool
extends RefCounted
## Aprobaciones por máquina de lo que un proyecto trae para ejecutar (m11-31, m13-31): los comandos de
## los checks del fin de turno y los MCP servers del proyecto. project_config.tres viaja con el
## proyecto, así que lo que trae corre solo si quien usa este editor aprobó esa definición exacta.
## La tienda es HarnessSettings (ajustes del usuario, nunca el proyecto); acá se arma la clave.

const KIND_CHECK := "check"
const KIND_MCP := "mcp"


## La clave de `text` (un comando, una definición) en el proyecto `project_dir`.
static func key(project_dir: String, text: String) -> String:
	return (project_dir.simplify_path() + "\n" + text.strip_edges()).sha256_text()


## Los datos de «Aprobar…»: `{kind, items: [{name, command, key}]}`.
static func request(kind: String, items: Array) -> Dictionary:
	return {"kind": kind, "items": items}
