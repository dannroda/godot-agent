@tool
extends RefCounted
## Lo que cambia según el agente (m13-04, A1): cómo pide y lee su cuota, si su cuenta se sabe por un
## CLI, qué `_meta` necesita al abrir la sesión y qué API key del entorno conviene avisar. Este es el
## genérico: no hace nada de eso. Cada agente con algo propio tiene su subclase en esta carpeta, y
## `agent_adapters.gd` elige cuál usar. Sumar un agente = un archivo acá.

const ClaudeExtensions := preload("../../extensions/claude_extensions.gd")

## Familia del agente (`ClaudeExtensions.AGENT_*`): la usan las extensiones por archivos.
var kind: String = ClaudeExtensions.AGENT_OTHER


## Comando local que informa la cuota sin gastar tokens ("" = el agente no tiene, o la manda sola en
## `usage_update`). `model` es el SessionModel: algunos agentes solo lo tienen si lo anuncian.
func quota_command(_model: RefCounted) -> String:
	return ""


## Lee la respuesta de `quota_command` y la pasa a `quota` (QuotaMonitor); puede completar la cuenta
## en `model` si el agente no la informó por otro lado.
func read_quota(_text: String, _quota: RefCounted, _model: RefCounted, _model_name: String) -> void:
	pass


## Se eligió otro modelo: los agentes con cuota por grupo de modelos cambian de grupo.
func model_changed(_quota: RefCounted, _model_name: String) -> void:
	pass


## true si la cuenta del perfil se pregunta a un CLI del agente (ver SessionController._refresh_account).
func reads_account_from_cli() -> bool:
	return false


## `_meta` de session/new y session/load ({} = ninguno).
func session_meta(_disabled_skills: PackedStringArray) -> Dictionary:
	return {}


## Variable del entorno que hace que el agente cobre por API en vez de por la suscripción ("" = no hay).
func api_key_variable() -> String:
	return ""
