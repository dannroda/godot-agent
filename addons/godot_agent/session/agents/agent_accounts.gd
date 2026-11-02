@tool
extends RefCounted
## Cuentas de un agente, una por pestaña del dock: cada cuenta es una carpeta de configuración (donde
## el agente guarda su login) que se le pasa en una variable del entorno. El adaptador dice cuál
## (CLAUDE_CONFIG_DIR, GEMINI_HOME, CODEX_HOME…) y su carpeta por defecto; para otro agente, el perfil.
## Se leen del disco al abrir el menú del agente, sin lanzar nada.

const AgentAdapter := preload("agent_adapter.gd")
const AgentProfile := preload("../../core/agent_profile.gd")


## La variable de las cuentas del perfil: la que puso el usuario o la que conoce el adaptador.
static func variable_for(profile: AgentProfile, adapter: AgentAdapter) -> String:
	return profile.account_variable if not profile.account_variable.is_empty() else adapter.account_variable()


## La carpeta que usa el perfil sin cuenta elegida: la de su entorno, la del editor o la por defecto
## del agente ("" si no hay ninguna: el agente decide).
static func base_dir(profile: AgentProfile, adapter: AgentAdapter, variable: String) -> String:
	var own := str(profile.with_account("", "").resolved_env().get(variable, ""))
	if own.is_empty():
		own = OS.get_environment(variable)
	if own.is_empty():
		own = adapter.default_account_dir()
	return normalize(own) if not own.is_empty() else ""


static func home() -> String:
	var dir := OS.get_environment("HOME")
	return dir if not dir.is_empty() else OS.get_environment("USERPROFILE")


## Ruta absoluta sin barra final, con `~/` expandido.
static func normalize(dir: String) -> String:
	var path := dir.strip_edges()
	if path.is_empty():
		return ""
	if path == "~" or path.begins_with("~/"):
		path = home() + path.substr(1)
	path = path.simplify_path()
	return path.trim_suffix("/") if path.length() > 1 else path


## Dónde se buscan más cuentas: al lado de `~/.claude`, `~/.claude-profiles/<cuenta>` (lo mismo para
## `~/.gemini`, `~/.codex`…). "" si la carpeta por defecto no está en la del usuario.
static func profiles_root(default_dir: String) -> String:
	var dir := normalize(default_dir)
	if dir.is_empty() or dir.get_base_dir() != normalize(home()):
		return ""
	return dir + "-profiles"


## Las cuentas a elegir: [{dir, name, email}], la del perfil primero y sin repetir. `default_dir` es
## la carpeta por defecto del agente; `extra`, las que agregó el usuario.
static func list(base: String, default_dir: String, extra: PackedStringArray, adapter: AgentAdapter) -> Array[Dictionary]:
	var dirs: PackedStringArray = [normalize(base)]
	var plain := normalize(default_dir)
	if not plain.is_empty() and DirAccess.dir_exists_absolute(plain):
		dirs.append(plain)
	var root := profiles_root(default_dir)
	var access := DirAccess.open(root) if not root.is_empty() else null
	if access:
		var names := access.get_directories()
		names.sort()
		for name: String in names:
			dirs.append(normalize(root.path_join(name)))
	for dir: String in extra:
		if not dir.strip_edges().is_empty():
			dirs.append(normalize(dir))
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for dir: String in dirs:
		if seen.has(dir):
			continue
		seen[dir] = true
		result.append({"dir": dir, "name": name_of(dir), "email": adapter.account_email(dir) if not dir.is_empty() else ""})
	return result


## Nombre corto: `~/.claude` para una carpeta de la del usuario, si no la última parte (`trabajo`).
static func name_of(dir: String) -> String:
	var path := normalize(dir)
	if path.is_empty():
		return ""
	return "~/" + path.get_file() if path.get_base_dir() == normalize(home()) else path.get_file()


## Texto del menú: «trabajo · ana@empresa.com».
static func label_of(account: Dictionary) -> String:
	var email := str(account.get("email", ""))
	return str(account.name) if email.is_empty() else "%s · %s" % [account.name, email]
