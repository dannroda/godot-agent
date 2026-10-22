@tool
extends RefCounted
## Runs del One-shot en disco (D37): `<dir>/<id>.json` con el estado y `<id>.png` con la última
## captura. Se escriben con un archivo temporal y rename, así un crash a mitad de escritura no deja
## un JSON roto. Si el editor se cae con un run en curso, al volver se lo ofrece para retomar.

const VERSION := 1
## Runs que se guardan; los más viejos se borran.
const KEEP := 20

var dir: String = ""


func _init(store_dir: String = "") -> void:
	dir = store_dir


func is_enabled() -> bool:
	return not dir.is_empty()


func save(data: Dictionary, capture: Image = null) -> bool:
	if not is_enabled() or str(data.get("id", "")).is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	data["version"] = VERSION
	data["updated_at"] = int(Time.get_unix_time_from_system())
	var path := dir.path_join("%s.json" % data.id)
	if not _write_atomic(path, JSON.stringify(data, "\t")):
		return false
	if capture:
		capture.save_png(dir.path_join("%s.png" % data.id))
	return true


func load_run(id: String) -> Dictionary:
	var path := dir.path_join("%s.json" % id)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()  # parse_string escribe el error en Output; un archivo roto se ignora
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or int(parsed.get("version", 0)) != VERSION or str(parsed.get("id", "")) != id:
		return {}
	return parsed


func load_capture(id: String) -> Image:
	var path := dir.path_join("%s.png" % id)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	return image if image and not image.is_empty() else null


## Ids guardados, del más nuevo al más viejo (el id empieza con la fecha).
func ids() -> PackedStringArray:
	var result: PackedStringArray = []
	if not is_enabled() or not DirAccess.dir_exists_absolute(dir):
		return result
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json") and not file.ends_with(".report.json"):
			result.append(file.get_basename())
	result.sort()
	result.reverse()
	return result


## El run más nuevo si quedó a medias (el editor se cerró o se cayó con el run en curso), o {}.
func load_interrupted() -> Dictionary:
	var all := ids()
	if all.is_empty():
		return {}
	var data := load_run(all[0])
	return data if bool(data.get("active", false)) else {}


## Borra los runs más viejos que KEEP (con su captura y su informe).
func prune() -> void:
	var all := ids()
	for i in range(KEEP, all.size()):
		for suffix: String in [".json", ".png", ".report.json"]:
			DirAccess.remove_absolute(dir.path_join(all[i] + suffix))


## Id nuevo: fecha y hora local, ordenable.
static func new_id() -> String:
	return Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")


static func _write_atomic(path: String, text: String) -> bool:
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return DirAccess.rename_absolute(temp, path) == OK
