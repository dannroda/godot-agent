@tool
extends RefCounted
## Busca el ejecutable de un perfil. El editor lanzado desde el escritorio no hereda el PATH de
## la shell (fnm, nvm, volta…), así que además del PATH se miran carpetas habituales.

const _EXTRA_DIRS_UNIX: PackedStringArray = [
	"~/.local/bin",
	"~/.local/share/fnm/aliases/default/bin",
	"~/.volta/bin",
	"~/.bun/bin",
	"~/.npm-global/bin",
	"/usr/local/bin",
	"/opt/homebrew/bin",
	"/usr/bin",
]
const _WINDOWS_EXTENSIONS: PackedStringArray = [".exe", ".cmd", ".bat", ""]


## Ruta absoluta del ejecutable, o "" si no se encuentra. Las rutas absolutas se validan tal cual.
static func resolve(command: String) -> String:
	if command.is_empty():
		return ""
	if command.is_absolute_path():
		return command if FileAccess.file_exists(command) else ""
	for dir: String in search_dirs():
		for ext: String in _extensions():
			var candidate := dir.path_join(command + ext)
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


static func search_dirs() -> PackedStringArray:
	var separator := ";" if OS.get_name() == "Windows" else ":"
	var dirs: PackedStringArray = OS.get_environment("PATH").split(separator, false)
	if OS.get_name() != "Windows":
		var home := OS.get_environment("HOME")
		for dir: String in _EXTRA_DIRS_UNIX:
			dirs.append(dir.replace("~", home))
		dirs.append_array(_nvm_dirs(home))
	else:
		var appdata := OS.get_environment("APPDATA")
		if not appdata.is_empty():
			dirs.append(appdata.path_join("npm"))
	return dirs


## PATH para el proceso hijo: el actual más la carpeta del ejecutable resuelto (npx necesita node al lado).
static func child_path_for(executable: String) -> String:
	var separator := ";" if OS.get_name() == "Windows" else ":"
	var path := OS.get_environment("PATH")
	var dir := executable.get_base_dir()
	if dir.is_empty() or dir in path.split(separator, false):
		return path
	return dir + separator + path


static func _extensions() -> PackedStringArray:
	return _WINDOWS_EXTENSIONS if OS.get_name() == "Windows" else PackedStringArray([""])


static func _nvm_dirs(home: String) -> PackedStringArray:
	var dirs: PackedStringArray = []
	var base := home.path_join(".nvm/versions/node")
	if not DirAccess.dir_exists_absolute(base):
		return dirs
	var versions := DirAccess.get_directories_at(base)
	versions.reverse()
	for version: String in versions:
		dirs.append(base.path_join(version).path_join("bin"))
	return dirs
