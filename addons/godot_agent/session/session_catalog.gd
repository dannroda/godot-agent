@tool
extends RefCounted
## Las sesiones del proyecto en el agente (m11-16, m13-05): `session/list`, `session/close` y
## `session/delete`, y cómo se juntan con el historial local para el menú. Lo usa SessionController,
## que le dice si el agente está corriendo y con qué perfil.

const AcpClient := preload("../acp/acp_client.gd")
const SessionModel := preload("session_model.gd")
const ChatEntry := preload("chat_entry.gd")
const AgentLog := preload("../core/agent_log.gd")
const AgentProfile := preload("../core/agent_profile.gd")
const SessionHistory := preload("session_history.gd")
const I18n := preload("../core/i18n.gd")

const CLOSE_TIMEOUT_S := 10
## Páginas de `session/list` que se piden como máximo.
const LIST_PAGES := 3

## Sesiones que informó el agente con `session/list` para este proyecto.
var agent_sessions: Array[Dictionary] = []
var _model: SessionModel
var _client: AcpClient
var _agent_log: AgentLog


func setup(model: SessionModel, client: AcpClient, agent_log: AgentLog) -> void:
	_model = model
	_client = client
	_agent_log = agent_log


## Pide al agente sus sesiones de `filter_cwd` con `session/list`.
func list(filter_cwd: String, agent_running: bool, agent_profile: AgentProfile) -> Array[Dictionary]:
	if not agent_running or not _model.supports_list_sessions():
		agent_sessions = []  # las del agente anterior no son de este
		return []
	var collected: Array[Dictionary] = []
	var cursor := ""
	for _page in LIST_PAGES:
		var params: Dictionary = {}
		if not filter_cwd.is_empty():
			params["cwd"] = filter_cwd
		if not cursor.is_empty():
			params["cursor"] = cursor
		var result := await _client.request("session/list", params)
		if not result.ok or not result.result is Dictionary:
			break
		var raw_list: Variant = result.result.get("sessions")
		if raw_list is Array:
			for item: Variant in raw_list:
				if not item is Dictionary or not item.get("sessionId") is String:
					continue
				collected.append(normalize_agent_session(item, agent_profile))
		var next_cursor: Variant = result.result.get("nextCursor")
		if not next_cursor is String or str(next_cursor).is_empty():
			break
		cursor = str(next_cursor)
	agent_sessions = collected
	return collected


## Cierra `session_id` en el agente con `session/close` si lo soporta.
func close(session_id: String, agent_running: bool) -> bool:
	if session_id.is_empty() or not agent_running or not _model.supports_close_session():
		return false
	# Sin respuesta a tiempo se cancela: mientras tanto «Nueva sesión» no hace nada.
	var req_id := _client.next_request_id()
	(Engine.get_main_loop() as SceneTree).create_timer(CLOSE_TIMEOUT_S).timeout.connect(func() -> void:
		if _client.cancel_request(req_id):
			_agent_log.add(AgentLog.CH_ACP, "session/close got no answer in %d s, cancelled" % CLOSE_TIMEOUT_S)
	)
	var result := await _client.request("session/close", {"sessionId": session_id})
	return result.ok


## Borra `session_id` del historial local y, con `in_agent` (perfil conectado y corriendo), también en
## el agente si soporta `session/delete`. Si el agente no la borra, la local queda.
func delete(session_id: String, in_agent: bool, history: SessionHistory) -> bool:
	if session_id.is_empty():
		return false
	if in_agent and _model.supports_delete_session():
		var result := await _client.request("session/delete", {"sessionId": session_id})
		if not result.ok:
			_model.add_notice(I18n.t("Could not delete the session in the agent: %s") % result.error_message(), ChatEntry.NoticeLevel.WARNING)
			return false
	if history:
		history.remove(session_id)
	agent_sessions = agent_sessions.filter(func(item: Dictionary) -> bool: return str(item.get("id", "")) != session_id)
	return true


## Convierte un `SessionInfo` de `session/list` al formato de resumen que usa el menú de historial.
static func normalize_agent_session(item: Dictionary, agent_profile: AgentProfile = null) -> Dictionary:
	var updated := 0
	if item.get("updatedAt") is String and not str(item.updatedAt).is_empty():
		updated = int(Time.get_unix_time_from_datetime_string(str(item.updatedAt)))
	return {
		"id": str(item.get("sessionId", "")),
		"title": str(item.get("title", "")) if item.get("title") is String else "",
		"cwd": str(item.get("cwd", "")),
		"updated": updated,
		"turns": 0,
		"profile_id": agent_profile.id if agent_profile else "",
		"agent": agent_profile.display_name if agent_profile else "",
		"from_agent": true,
	}


## Une las sesiones del historial local con las de `session/list` sin duplicar `id`, más recientes primero.
static func merge_session_lists(local_list: Array[Dictionary], remote_list: Array[Dictionary], max_items: int = 20) -> Array[Dictionary]:
	var by_id: Dictionary = {}
	var combined: Array[Dictionary] = []
	for item: Dictionary in local_list:
		var id := str(item.get("id", ""))
		if id.is_empty() or by_id.has(id):
			continue
		var copy := item.duplicate()
		by_id[id] = copy
		combined.append(copy)
	for item: Dictionary in remote_list:
		var id := str(item.get("id", ""))
		if id.is_empty():
			continue
		if by_id.has(id):
			var existing: Dictionary = by_id[id]
			if str(existing.get("title", "")).is_empty() and not str(item.get("title", "")).is_empty():
				existing["title"] = item.title
			if int(item.get("updated", 0)) > int(existing.get("updated", 0)):
				existing["updated"] = item.updated
		else:
			var copy := item.duplicate()
			by_id[id] = copy
			combined.append(copy)
	combined.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("updated", 0)) > int(b.get("updated", 0)))
	return combined.slice(0, max_items) if max_items > 0 else combined
