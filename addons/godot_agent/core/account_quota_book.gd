@tool
extends RefCounted
## La última cuota vista de cada cuenta (m6-22): un perfil del agente con una carpeta de cuenta. La
## cuota que mide QuotaMonitor es la de la cuenta con la que corre el agente; al cambiar de cuenta se
## olvida. Acá queda anotada, para que el menú «Cambiar de cuenta» diga cuál se agotó y cuánto le
## quedaba a cada una, y para que la cadena de reserva (m6-21) saltee las que siguen agotadas.
## Se guarda en un archivo JSON chico, sin estado en memoria entre llamadas.

const I18n := preload("i18n.gd")
const QuotaMonitor := preload("quota_monitor.gd")

const PATH := "user://godot_agent/account_quota.json"

var path: String = PATH
var now_provider: Callable = func() -> int: return int(Time.get_unix_time_from_system())


## Clave de la cuenta: el perfil y su carpeta ("" = la del perfil sin override).
static func key(profile_id: String, account_dir: String) -> String:
	return "%s|%s" % [profile_id, account_dir]


## Anota lo que mide `quota` para la cuenta. Sin datos ni límite, no pisa lo anterior.
func record(profile_id: String, account_dir: String, quota: QuotaMonitor) -> void:
	if profile_id.is_empty() or quota == null or (not quota.has_data() and not quota.is_limited()):
		return
	var until := quota.limited_until if quota.is_limited() else quota.pause_resets_at()
	var entry := {
		"used": quota.max_utilization(),
		"limited": quota.is_limited(),
		"until": until,
		"at": _now(),
	}
	var data := _read()
	data[key(profile_id, account_dir)] = entry
	_write(data)


## Lo último anotado de la cuenta: {used (0..1, -1 sin dato), limited, until, at}, o {} si nada.
## Un límite cuyo reinicio ya pasó se da como no agotado y sin uso conocido.
func lookup(profile_id: String, account_dir: String) -> Dictionary:
	var entry: Variant = _read().get(key(profile_id, account_dir))
	if not entry is Dictionary:
		return {}
	var result := (entry as Dictionary).duplicate()
	var until := int(result.get("until", 0))
	if until > 0 and until <= _now():
		result["limited"] = false
		result["used"] = -1.0
		result["reset"] = true
	return result


## true si la cuenta quedó agotada (o en el umbral de pausa `pause_at`, 0..1) y su ventana todavía
## no se reinició.
func is_exhausted(profile_id: String, account_dir: String, pause_at: float = 2.0) -> bool:
	var entry := lookup(profile_id, account_dir)
	return bool(entry.get("limited", false)) or float(entry.get("used", -1.0)) >= pause_at


## Texto corto para el menú: «agotada, se libera en 2 h», «62 % usado», «» si no se sabe.
func describe(profile_id: String, account_dir: String) -> String:
	var entry := lookup(profile_id, account_dir)
	if entry.is_empty():
		return ""
	if bool(entry.get("limited", false)):
		var until := int(entry.get("until", 0))
		if until > 0:
			return I18n.t("exhausted, resets in %s") % QuotaMonitor.format_duration(until - _now())
		return I18n.t("exhausted")
	var used := float(entry.get("used", -1.0))
	if used < 0.0:
		return I18n.t("quota reset") if bool(entry.get("reset", false)) else ""
	return I18n.t("%d %% used") % roundi(used * 100.0)


func _now() -> int:
	return int(now_provider.call())


func _read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _write(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
