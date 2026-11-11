@tool
extends RefCounted
## El modelo de cada modo del harness, por perfil de agente (m11-38, absorbe m11-27): planificar en
## Preguntar con un modelo y construir con otro. Sticky como los modos de Roo: lo que el usuario elige
## en el selector del composer queda para el modo en que estaba esa pestaña, y volver a ese modo vuelve
## a ese modelo. Es un ajuste del usuario (HarnessSettings), no del proyecto: los modelos dependen de la
## cuenta, y un proyecto compartido no puede imponer uno que tu cuenta quizás no tiene.
##
## En HarnessSettings, KEY: `{profile_id: {mode_key: {"value": String, "name": String}}}`; `name` es el
## nombre que mostraba el agente al elegirlo, para Settings (sin sesión no se sabe qué ofrece).

const KEY := "agents/models_by_mode"  # HarnessSettings.KEY_MODE_MODELS
## Las claves de modo: las de PermissionPolicy.MODE_KEYS, en el orden de SessionModel.HarnessMode.
const MODE_KEYS: PackedStringArray = ["ask", "review", "build", "oneshot", "auto"]

## Un objeto con get_value(key, default) y set_value(key, value): HarnessSettings.
var settings: Object


func _init(store: Object = null) -> void:
	settings = store


static func mode_key(mode: int) -> String:
	return MODE_KEYS[mode] if mode >= 0 and mode < MODE_KEYS.size() else ""


## El modelo recordado para `mode` con ese perfil: `{value, name}` o {}.
func get_model(profile_id: String, mode: int) -> Dictionary:
	var entry: Variant = by_mode(profile_id).get(mode_key(mode))
	return entry if entry is Dictionary and not str(entry.get("value", "")).is_empty() else {}


## `{mode_key: {value, name}}` del perfil.
func by_mode(profile_id: String) -> Dictionary:
	var all := _all()
	var entry: Variant = all.get(profile_id, {})
	return entry if entry is Dictionary else {}


func remember(profile_id: String, mode: int, value: String, name: String = "") -> void:
	if settings == null or profile_id.is_empty() or mode_key(mode).is_empty() or value.is_empty():
		return
	var all := _all()
	var entry: Dictionary = (all.get(profile_id, {}) as Dictionary).duplicate() if all.get(profile_id) is Dictionary else {}
	if entry.get(mode_key(mode)) is Dictionary and entry[mode_key(mode)].get("value") == value and entry[mode_key(mode)].get("name") == name:
		return
	entry[mode_key(mode)] = {"value": value, "name": name if not name.is_empty() else value}
	all[profile_id] = entry
	settings.call(&"set_value", KEY, all)


func forget(profile_id: String, mode: int) -> void:
	if settings == null:
		return
	var all := _all()
	if not all.get(profile_id) is Dictionary or not (all[profile_id] as Dictionary).has(mode_key(mode)):
		return
	var entry: Dictionary = (all[profile_id] as Dictionary).duplicate()
	entry.erase(mode_key(mode))
	if entry.is_empty():
		all.erase(profile_id)
	else:
		all[profile_id] = entry
	settings.call(&"set_value", KEY, all)


func _all() -> Dictionary:
	if settings == null:
		return {}
	var value: Variant = settings.call(&"get_value", KEY, {})
	return (value as Dictionary).duplicate() if value is Dictionary else {}


## La configOption del modelo entre las del agente: la de category "model" o, si no hay, la de id
## "model" ({} si el agente no deja elegir).
static func model_option(options: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for option: Variant in options:
		if not option is Dictionary:
			continue
		if option.get("category") == "model":
			return option
		if option.get("id") == "model" and by_id.is_empty():
			by_id = option
	return by_id


## El nombre de `value` entre las opciones (o el valor).
static func option_name(option: Dictionary, value: String) -> String:
	for item: Variant in option.get("options", []):
		if item is Dictionary and str(item.get("value", "")) == value:
			return str(item.get("name", value))
	return value


static func offers(option: Dictionary, value: String) -> bool:
	for item: Variant in option.get("options", []):
		if item is Dictionary and str(item.get("value", "")) == value:
			return true
	return false
