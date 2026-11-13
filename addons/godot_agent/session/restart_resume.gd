@tool
extends RefCounted
## Reiniciar el editor y retomar las sesiones (m12-54). Antes de reiniciar, el plugin guarda las
## pestañas abiertas (sesión del agente, perfil, modo, la copia aparte si la hay) y cuál pidió el
## reinicio; al volver, las reabre y le dice a esa que siga. Va en la carpeta del supervisor del
## proyecto (.godot/agent_supervisor/), aparte de sus eventos: un reinicio sin supervisor también
## retoma, y bajo el supervisor los eventos los escribe él.

const FILE := "resume_tabs.json"
## Un archivo más viejo que esto es de un reinicio que no pasó (el editor se cerró de otra forma):
## abrir el editor días después no reabre pestañas viejas.
const MAX_AGE_S := 900


## Una pestaña para guardar. "" si no hay nada que retomar (nunca arrancó una sesión).
## `mode`: SessionModel.HarnessMode; `project_mode`: el slug del modo del proyecto ("" ninguno);
## `copy`: WorktreeSession.info de una copia aparte ({} si no es copia).
static func tab_entry(tab: String, session_id: String, label: String, mode: int, project_mode: String, copy: Dictionary, requester: bool, active: bool) -> Dictionary:
	if session_id.is_empty():
		return {}
	return {"tab": tab, "session_id": session_id, "label": label, "mode": mode, "project_mode": project_mode,
		"copy": copy, "requester": requester, "active": active}


static func save(dir: String, reason: String, tabs: Array, now: int = -1) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join(FILE), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"reason": reason, "time": now if now >= 0 else int(Time.get_unix_time_from_system()), "tabs": tabs}, "\t"))
	file.close()


## Lo guardado (y lo borra), o {} si no hay, está roto o es viejo.
static func take(dir: String, now: int = -1) -> Dictionary:
	var path := dir.path_join(FILE)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	DirAccess.remove_absolute(path)
	if not data is Dictionary or not data.get("tabs") is Array:
		return {}
	var current := now if now >= 0 else int(Time.get_unix_time_from_system())
	if current - int(data.get("time", 0)) > MAX_AGE_S:
		return {}
	return data


static func discard(dir: String) -> void:
	if FileAccess.file_exists(dir.path_join(FILE)):
		DirAccess.remove_absolute(dir.path_join(FILE))


## El orden en que se abren las sesiones: la que pidió el reinicio primero (recibe el mensaje
## enseguida), las demás como estaban. Devuelve índices de `tabs`.
static func open_order(tabs: Array) -> Array[int]:
	var order: Array[int] = []
	for index: int in tabs.size():
		if bool(tabs[index].get("requester", false)):
			order.push_front(index)
		else:
			order.append(index)
	return order


## Qué pestaña va en la primera del dock (que siempre existe): la primera que no es copia aparte
## (una copia necesita su propio controller desde que se crea). -1 si todas son copias.
static func primary_index(tabs: Array) -> int:
	for index: int in tabs.size():
		if (tabs[index].get("copy", {}) as Dictionary).is_empty():
			return index
	return -1


## Lo que recibe la pestaña que pidió el reinicio. `extra`: lo que contó el supervisor (un crash, una
## build vuelta atrás), que va después.
static func agent_message(reason: String, extra: PackedStringArray = []) -> String:
	var lines: PackedStringArray = ["The editor restarted (%s). Continue." % reason if not reason.is_empty() else "The editor restarted. Continue."]
	lines.append_array(extra)
	return "\n\n".join(lines)
