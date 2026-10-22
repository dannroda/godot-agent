@tool
extends RefCounted
## Matriz modo × grupo de herramienta → allow / ask / deny (spec §7). Los "Siempre en esta
## sesión" quedan en memoria y se pierden con la sesión.

const SessionModel := preload("session_model.gd")

const ALLOW := "allow"
const ASK := "ask"
const DENY := "deny"

const GROUP_READ := "read"
const GROUP_DIAGNOSTICS := "diagnostics"
const GROUP_EDIT_SCENE := "edit_scene"
const GROUP_EDIT_FILES := "edit_files"
const GROUP_RUN := "run"
const GROUP_SHELL := "shell"
const GROUP_PROJECT := "project"
## Sin grupo conocido: siempre se pregunta (spec §7, "el resto → ask").
const GROUP_OTHER := "other"

const GROUPS: PackedStringArray = [
	GROUP_READ, GROUP_DIAGNOSTICS, GROUP_EDIT_SCENE, GROUP_EDIT_FILES, GROUP_RUN, GROUP_SHELL, GROUP_PROJECT,
]
const GROUP_LABELS: Dictionary = {
	GROUP_READ: "Read",  # i18n
	GROUP_DIAGNOSTICS: "Diagnostics",  # i18n
	GROUP_EDIT_SCENE: "Edit scenes",  # i18n
	GROUP_EDIT_FILES: "Edit files",  # i18n
	GROUP_RUN: "Run the game",  # i18n
	GROUP_SHELL: "Shell / commands",  # i18n
	GROUP_PROJECT: "Project settings, export and addons",  # i18n
	GROUP_OTHER: "Other",  # i18n
}
const MODE_KEYS: Dictionary = {
	SessionModel.HarnessMode.ASK: "ask",
	SessionModel.HarnessMode.REVIEW: "review",
	SessionModel.HarnessMode.BUILD: "build",
	SessionModel.HarnessMode.ONESHOT: "oneshot",
}
## Defaults de la spec §7: grupo -> [Preguntar, Revisar, Construir, One-shot].
const DEFAULTS: Dictionary = {
	GROUP_READ: [ALLOW, ALLOW, ALLOW, ALLOW],
	GROUP_DIAGNOSTICS: [ALLOW, ALLOW, ALLOW, ALLOW],
	GROUP_EDIT_SCENE: [DENY, DENY, ASK, ALLOW],
	GROUP_EDIT_FILES: [DENY, DENY, ASK, ALLOW],
	GROUP_RUN: [DENY, ASK, ASK, ALLOW],
	GROUP_SHELL: [DENY, DENY, ASK, ASK],
	GROUP_PROJECT: [DENY, DENY, ASK, ASK],
}
## kind de un tool call de ACP → grupo.
const KIND_GROUPS: Dictionary = {
	"read": GROUP_READ,
	"search": GROUP_READ,
	"edit": GROUP_EDIT_FILES,
	"delete": GROUP_EDIT_FILES,
	"move": GROUP_EDIT_FILES,
	"execute": GROUP_SHELL,
}

## Overrides por proyecto: grupo -> { mode_key -> decisión }.
var overrides: Dictionary = {}
var _session_grants: Dictionary = {}  # grupo -> true


func _init(project_overrides: Dictionary = {}) -> void:
	overrides = project_overrides


## Decisión para un grupo en un modo, sin contar lo concedido en la sesión.
func matrix_value(group: String, mode: SessionModel.HarnessMode) -> String:
	if not DEFAULTS.has(group):
		return ASK
	var key: String = MODE_KEYS[mode]
	var override: Variant = overrides.get(group)
	if override is Dictionary and override.get(key) in [ALLOW, ASK, DENY]:
		return override[key]
	return DEFAULTS[group][int(mode)]


## Decisión efectiva: un "ask" que el usuario concedió para toda la sesión pasa a "allow".
## Un "deny" de la matriz nunca se levanta con un permiso de sesión.
func decide(group: String, mode: SessionModel.HarnessMode) -> String:
	var value := matrix_value(group, mode)
	if value == ASK and _session_grants.has(group):
		return ALLOW
	return value


func grant_for_session(group: String) -> void:
	_session_grants[group] = true


func clear_session() -> void:
	_session_grants.clear()


func set_matrix_value(group: String, mode: SessionModel.HarnessMode, value: String) -> void:
	var entry: Dictionary = overrides.get(group, {})
	entry[MODE_KEYS[mode]] = value
	overrides[group] = entry


## Grupo de un tool call de ACP según su kind (las tools `godot.*` las decide el server MCP).
static func group_for_tool_call(tool_call: Dictionary) -> String:
	return KIND_GROUPS.get(str(tool_call.get("kind", "")), GROUP_OTHER)


## true si el tool call es una tool del server MCP del addon: el permiso lo decide el server.
static func is_godot_mcp_tool(tool_call: Dictionary) -> bool:
	var title := str(tool_call.get("title", ""))
	return title.begins_with("mcp__godot__") or title.begins_with("godot.")
