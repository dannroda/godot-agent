@tool
extends RefCounted
## Rutas del proyecto que el agente no escribe con las tools de archivos (D48, m4-10) ni con
## install_extension (m19-05): project.godot, el addon del harness y .godot/. Una sola lista para
## las dos. En Windows y macOS el sistema de archivos no distingue mayúsculas: `Addons/Godot_Agent`
## es la misma carpeta, así que la comparación tampoco.

const PROTECTED: PackedStringArray = ["res://project.godot", "res://addons/godot_agent", "res://.godot"]


static func case_insensitive() -> bool:
	return OS.get_name() in ["Windows", "macOS"]


## Si `res_path` (res://, ya normalizada) es una de las protegidas o está adentro.
static func is_protected(res_path: String, ignore_case: bool = case_insensitive()) -> bool:
	var path := res_path.to_lower() if ignore_case else res_path
	for protected: String in PROTECTED:
		var guarded := protected.to_lower() if ignore_case else protected
		if path == guarded or path.begins_with(guarded + "/"):
			return true
	return false


## Una ruta relativa a la raíz del proyecto, como la escribió alguien («res:///addons//x/»,
## «addons\\x», «/x»): sin res://, con barras normales, simplificada y sin barras al principio ni al
## final. Devuelve `{rel, error}`: error si sale del proyecto (`..`, una unidad de Windows, una ruta
## absoluta que no es la del proyecto).
static func normalize_relative(path: String) -> Dictionary:
	var clean := path.strip_edges().replace("\\", "/")
	if clean.begins_with("res://"):
		clean = clean.trim_prefix("res://")
	elif clean.length() >= 2 and clean[1] == ":":
		return {"rel": "", "error": "%s is outside the project." % path}
	while clean.begins_with("/"):
		clean = clean.substr(1)
	clean = clean.simplify_path()
	while clean.begins_with("/"):
		clean = clean.substr(1)
	clean = clean.trim_suffix("/")
	if clean == ".":
		clean = ""
	if clean == ".." or clean.begins_with("../") or clean.contains("/../"):
		return {"rel": "", "error": "%s is outside the project." % path}
	return {"rel": clean, "error": ""}


## Por qué no se puede escribir `rel` (relativa a `root`, ya normalizada), o "": protegida, en una
## carpeta oculta (Godot no la escanea: .godot, .git) o, por un enlace simbólico, fuera del proyecto o
## dentro de una protegida. `root` es la carpeta del proyecto, absoluta.
static func write_error(rel: String, root: String, ignore_case: bool = case_insensitive()) -> String:
	if is_protected("res://" + rel, ignore_case):
		return "res://%s is protected (project.godot, .godot/ and addons/godot_agent/ are never written)" % rel
	if _hidden(rel):
		return "res://%s is in a hidden folder, which Godot doesn't scan" % rel
	var real_root := resolve_links(root)
	var real := resolve_links(root.path_join(rel))
	var inside := real.to_lower().begins_with(real_root.to_lower() + "/") if ignore_case else real.begins_with(real_root + "/")
	if not inside:
		return "res://%s leads outside the project through a symbolic link (%s)" % [rel, real]
	var real_rel := real.substr(real_root.length() + 1)
	if real_rel != rel and (is_protected("res://" + real_rel, ignore_case) or _hidden(real_rel)):
		return "res://%s leads to res://%s through a symbolic link" % [rel, real_rel]
	return ""


## `path` (absoluta) con los enlaces simbólicos resueltos, carpeta por carpeta; lo que no existe queda
## como está. Hasta 16 saltos (un ciclo no cuelga).
static func resolve_links(path: String, depth: int = 0) -> String:
	var clean := path.simplify_path()
	var parts := clean.split("/", false)
	var current := "/" if clean.begins_with("/") else ""
	for i: int in parts.size():
		var next := current.path_join(parts[i]) if not current.is_empty() else parts[i]
		var base := next.get_base_dir()
		var dir := DirAccess.open(base) if not base.is_empty() else null
		if depth < 16 and dir != null and dir.is_link(parts[i]):
			var target := dir.read_link(parts[i])
			var linked := target if target.is_absolute_path() else base.path_join(target)
			var rest := "/".join(parts.slice(i + 1))
			return resolve_links(linked.path_join(rest) if not rest.is_empty() else linked, depth + 1)
		current = next
	return current


static func _hidden(rel: String) -> bool:
	for part: String in rel.split("/", false):
		if part.begins_with("."):
			return true
	return false
