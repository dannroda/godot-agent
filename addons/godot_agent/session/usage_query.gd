@tool
extends RefCounted
## El comando de cuota del agente (m13-05, A2 paso 2): Antigravity (`/usage`) y Codex (`/status`)
## no mandan la cuota en usage_update, la dice su comando local, que no gasta tokens. Corre el
## comando del adaptador como un turno sin que la pregunta ni la respuesta aparezcan en el chat;
## un prompt del usuario que llega en el medio espera a `done`.

signal done

const AcpClient := preload("../acp/acp_client.gd")
const AgentLog := preload("../core/agent_log.gd")

const TIMEOUT_S := 20
## Lo que manda el agente mientras corre el comando y no va al chat.
const SWALLOWED_UPDATES: PackedStringArray = ["agent_message_chunk", "agent_thought_chunk", "user_message_chunk"]

var running: bool = false
var _client: AcpClient
var _agent_log: AgentLog
var _request_id: int = 0
var _text: String = ""


func setup(client: AcpClient, agent_log: AgentLog) -> void:
	_client = client
	_agent_log = agent_log


## Corre `command` en la sesión y devuelve lo que contestó el agente (String), o null si falló o se
## canceló. `alive` dice si el proceso sigue (sin proceso, el timeout no cancela nada).
func run(command: String, session_id: String, alive: Callable) -> Variant:
	running = true
	_text = ""
	var req_id := _client.next_request_id()
	_request_id = req_id
	# Sin respuesta a tiempo se cancela: un prompt del usuario espera a que termine.
	(Engine.get_main_loop() as SceneTree).create_timer(TIMEOUT_S).timeout.connect(func() -> void:
		if _request_id == req_id and alive.call():
			_agent_log.add(AgentLog.CH_QUOTA, "%s got no answer in %d s, cancelled" % [command, TIMEOUT_S])
			_request_id = 0
			_client.notify("session/cancel", {"sessionId": session_id})
			_client.cancel_request(req_id)
	)
	var result := await _client.request("session/prompt", {"sessionId": session_id, "prompt": [{"type": "text", "text": command}]})
	if _request_id == req_id:
		_request_id = 0
	running = false
	done.emit()
	if not result.ok:
		if result.error.get("code") != AcpClient.ERR_REQUEST_CANCELLED:
			_agent_log.add(AgentLog.CH_QUOTA, "%s failed: %s" % [command, result.error_message()])
		return null
	return _text


## true si el update es parte de la respuesta al comando: se guarda y no va al chat.
func capture(update: Dictionary) -> bool:
	if not running or not update.get("sessionUpdate") in SWALLOWED_UPDATES:
		return false
	var content: Variant = update.get("content")
	if update.sessionUpdate == "agent_message_chunk" and content is Dictionary:
		_text += str(content.get("text", ""))
	return true


## Cancela con `$/cancel_request` el comando que ya no se espera (m11-18).
func cancel_abandoned() -> void:
	if _request_id > 0:
		var uid := _request_id
		_request_id = 0
		_client.cancel_request(uid)
