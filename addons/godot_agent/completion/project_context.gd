@tool
extends RefCounted
## Contexto del proyecto para el completado (spec §16.4). El índice de archivos (ProjectIndex) se
## arma en WorkerThreadPool y se publica entero al terminar; ClassDB, ProjectSettings y la escena
## abierta se leen acá, en el hilo principal, con caché. `poll()` se llama una vez por frame.

signal indexed(build_usec: int)

const ProjectIndex := preload("project_index.gd")
const LineIndex := preload("local/line_index.gd")

## Espera tras un cambio de archivos o del buffer antes de reindexar (se juntan los cambios).
const REFRESH_DELAY_MS := 400
const LIVE_CACHE_MS := 1000
const MAX_LIVE_NODES := 2000
## Virtuales más usados primero; el resto en el orden de ClassDB.
const COMMON_VIRTUALS: PackedStringArray = [
	"_ready", "_process", "_physics_process", "_input", "_unhandled_input", "_enter_tree",
	"_exit_tree", "_draw", "_gui_input", "_notification", "_unhandled_key_input", "_init",
]
## Virtuales que no tiene sentido sugerir (los maneja el lenguaje o son internos).
const HIDDEN_VIRTUALS: PackedStringArray = ["_get", "_set", "_get_property_list", "_property_can_revert", "_property_get_revert", "_validate_property", "_to_string", "_iter_init", "_iter_next", "_iter_get"]
const COMMON_CLASSES: PackedStringArray = [
	"Node", "Node2D", "Node3D", "Control", "CharacterBody2D", "CharacterBody3D", "Area2D", "Area3D",
	"RigidBody2D", "RigidBody3D", "Sprite2D", "Resource", "RefCounted", "Object", "Camera2D",
	"Camera3D", "StaticBody2D", "AnimatableBody2D", "CanvasLayer", "EditorPlugin", "Label", "Button",
]

var root: String = "res://"
## Prefijos (relativos a `root`) fuera del corpus de líneas, p. ej. "addons/".
var exclude: PackedStringArray = []
## Devuelve la raíz de la escena abierta en el editor, o null (en tests no hay editor).
var live_scene_provider: Callable
## Archivo con formato project.godot de donde leer input map y autoloads en lugar de
## ProjectSettings (el fixture de tests). Vacío = el proyecto abierto.
var settings_file: String = ""

var index: ProjectIndex = ProjectIndex.new()
var _task_id: int = -1
var _task_result: Array = []
## Índices reemplazados: se sueltan dentro del próximo build, en el worker (liberar decenas de miles
## de entradas en el hilo principal es un tirón).
var _retired: Array = []
## [bool] compartido con el build en curso: true lo corta (al deshabilitar el plugin).
var _cancel: Array = [false]
var _built: bool = false
var _dirty: bool = false
var _dirty_since: int = 0
var _buffers: Dictionary = {}  # ruta -> {text, skip_line}
var _virtuals_cache: Dictionary = {}
var _signal_cache: Dictionary = {}
var _engine_classes: PackedStringArray = []
var _settings_cache: Dictionary = {}
var _live_cache: Dictionary = {}  # script -> {time, nodes}
var _extends_re: RegEx


func _init() -> void:
	_extends_re = RegEx.new()
	_extends_re.compile("(?m)^(?:class_name\\s+\\w+\\s+)?extends\\s+(\"[^\"]+\"|'[^']+'|[\\w.]+)")


## Pide un reindexado (cambió algo en disco). Se agrupa con otros pedidos cercanos.
func request_refresh() -> void:
	if not _dirty:
		_dirty_since = Time.get_ticks_msec()
	_dirty = true


## El buffer sin guardar de un script reemplaza a su versión en disco en el próximo build.
## `skip_line` es la línea del caret (a medio escribir, no entra al corpus).
func update_buffer(path: String, text: String, skip_line: int) -> void:
	_buffers[path] = {"text": text, "skip_line": skip_line}
	request_refresh()


func drop_buffer(path: String) -> void:
	if _buffers.erase(path):
		request_refresh()


## Invalida lo que se lee de ProjectSettings (input map, autoloads, clases globales).
func settings_changed() -> void:
	_settings_cache.clear()


func is_building() -> bool:
	return _task_id >= 0


## Lanza un build si hace falta y publica el que terminó. Llamar una vez por frame.
func poll() -> void:
	if _task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		if not _task_result.is_empty():
			_retired.append(index)
			_publish(_task_result[0])
			_task_result = []
	if _dirty and Time.get_ticks_msec() - _dirty_since >= REFRESH_DELAY_MS:
		start_build()


## Arranca un build ya (si no hay uno en curso).
func start_build() -> void:
	if _task_id >= 0:
		return
	_dirty = false
	_cancel = [false]
	var options := {
		"root": root, "exclude": exclude, "buffers": _buffers.duplicate(true), "previous": index,
		"now": Time.get_unix_time_from_system(), "cancel": _cancel, "retired": _retired,
	}
	_retired = []
	var result := _task_result
	_task_id = WorkerThreadPool.add_task(func() -> void:
		result.append(ProjectIndex.build(options))
		options.erase("retired"), false, "godot_agent completion index")


## Build sincrónico (tests y benchmark).
func build_now() -> void:
	wait()
	_publish(ProjectIndex.build({"root": root, "exclude": exclude, "buffers": _buffers.duplicate(true), "previous": index, "now": Time.get_unix_time_from_system()}))
	_dirty = false


func has_built() -> bool:
	return _built


## Corta y espera el build en curso (al deshabilitar el plugin).
func wait() -> void:
	if _task_id >= 0:
		_cancel[0] = true
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_task_result.clear()


## Índice nuevo: lo derivado del anterior (escena abierta, señales, clases) se vuelve a calcular.
func _publish(new_index: ProjectIndex) -> void:
	index = new_index
	_built = true
	_live_cache.clear()
	_signal_cache.clear()
	_settings_cache.erase("classes")
	indexed.emit(index.build_usec)


func lines() -> LineIndex:
	return index.lines


# --- Escenas y nodos ------------------------------------------------------------------------------

## Nodos alcanzables desde el script con `$` (hijos del nodo que lo tiene) y `%` (únicos de la
## escena): [{path, name, type, unique}] en orden del árbol. Usa la escena abierta si el script
## está ahí (refleja cambios sin guardar); si no, las escenas indexadas.
func child_nodes(script_path: String) -> Array[Dictionary]:
	var live := _live_child_nodes(script_path)
	if not live.is_empty():
		return live
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for usage: Dictionary in index.script_nodes.get(script_path, []):
		var base: String = usage.node
		for pair: Array in _nodes_with_inherited(str(usage.scene), base == ProjectIndex.ROOT):
			var node: Dictionary = pair[1]
			var path: String = node.path
			if path == base:
				continue
			var relative := ""
			if base == ProjectIndex.ROOT:
				relative = path
			elif path.begins_with(base + "/"):
				relative = path.substr(base.length() + 1)
			elif not node.unique:
				continue
			var key: String = relative if not relative.is_empty() else "%" + str(node.name)
			var entry := {"path": relative, "name": node.name, "type": _type_name(str(pair[0]), node), "unique": node.unique}
			if seen.has(key):
				# Mismo nodo en otra escena que usa el script: gana la que conoce el tipo.
				var previous: Dictionary = out[seen[key]]
				if str(previous.type).is_empty() and not str(entry.type).is_empty():
					previous.type = entry.type
				continue
			seen[key] = out.size()
			out.append(entry)
	return out


## [[escena, nodo]] de una escena y, si `with_base` y la escena hereda de otra, los nodos de la base
## que la heredada no redefine (siguen siendo hijos de la raíz).
func _nodes_with_inherited(scene_path: String, with_base: bool) -> Array:
	var out: Array = []
	var paths: Dictionary = {}
	var current := scene_path
	var depth := 0
	while not current.is_empty() and depth < 8:
		var root_instance := ""
		for node: Dictionary in index.scenes.get(current, {}).get("nodes", []):
			if node.path == ProjectIndex.ROOT:
				root_instance = node.instance
			elif not paths.has(node.path):
				paths[node.path] = true
				out.append([current, node])
		current = root_instance if with_base else ""
		depth += 1
	return out


func _type_name(scene_path: String, node: Dictionary) -> String:
	var script_path: String = node.script
	if script_path.is_empty() and not str(node.instance).is_empty():
		script_path = index._root_script(str(node.instance), 0)
	if not script_path.is_empty():
		var class_name_value := str(index.scripts.get(script_path, {}).get("class_name", ""))
		if not class_name_value.is_empty():
			return class_name_value
	return index.node_type(scene_path, node)


func _live_child_nodes(script_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not live_scene_provider.is_valid():
		return out
	var scene_root := live_scene_provider.call() as Node
	if scene_root == null:
		return out
	var cached: Dictionary = _live_cache.get(script_path, {})
	if not cached.is_empty() and Time.get_ticks_msec() - int(cached.time) < LIVE_CACHE_MS and cached.root == scene_root.get_instance_id():
		return cached.nodes
	var holder: Node = null
	var nodes: Array[Node] = []
	_collect_owned(scene_root, scene_root, nodes)
	for node: Node in nodes:
		var script := node.get_script() as Script
		if script and script.resource_path == script_path:
			holder = node
			break
	if holder:
		for node: Node in nodes:
			if node == holder:
				continue
			var unique := node.is_unique_name_in_owner()
			var is_child := holder.is_ancestor_of(node)
			if not is_child and not unique:
				continue
			out.append({
				"path": str(holder.get_path_to(node)) if is_child else "", "name": str(node.name),
				"type": _live_type(node), "unique": unique,
			})
	_live_cache[script_path] = {"time": Time.get_ticks_msec(), "root": scene_root.get_instance_id(), "nodes": out}
	return out


func _collect_owned(node: Node, scene_root: Node, out: Array[Node]) -> void:
	if out.size() >= MAX_LIVE_NODES:
		return
	out.append(node)
	for child: Node in node.get_children():
		if child.owner == scene_root:
			_collect_owned(child, scene_root, out)


func _live_type(node: Node) -> String:
	var script := node.get_script() as Script
	if script:
		var global_name := str(script.get_global_name()) if script.has_method(&"get_global_name") else ""
		if not global_name.is_empty():
			return global_name
	return node.get_class()


## Conexiones de escena hacia el nodo que tiene este script cuyo método no está en `text`:
## [{method, signal, emitter_type}].
func pending_scene_handlers(script_path: String, text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for usage: Dictionary in index.script_nodes.get(script_path, []):
		var scene: Dictionary = index.scenes.get(usage.scene, {})
		var by_path: Dictionary = {}
		for node: Dictionary in scene.get("nodes", []):
			by_path[node.path] = node
		for connection: Dictionary in scene.get("connections", []):
			if str(connection.to) != str(usage.node) or not connection.get("exact", true) or _defines(text, str(connection.method)):
				continue
			var emitter: Dictionary = by_path.get(connection.from, {})
			out.append({
				"method": connection.method, "signal": connection.signal,
				"emitter_type": _type_name(str(usage.scene), emitter) if not emitter.is_empty() else "",
			})
	return out


static func _defines(text: String, method: String) -> bool:
	return text.contains("func " + method + "(") or text.contains("func " + method + " (")


# --- Clases, virtuales y señales -------------------------------------------------------------------

## Clase nativa de la que hereda el texto de un script (siguiendo `class_name` y rutas del proyecto).
func native_base(text: String) -> String:
	var found := _extends_re.search(text)
	var base := "RefCounted"
	if found:
		base = found.get_string(1).trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
	return _resolve_native(base, 0)


func _resolve_native(name: String, depth: int) -> String:
	if depth > 12:
		return "Object"
	if ClassDB.class_exists(name):
		return name
	var path := name if name.begins_with("res://") else str(global_classes().get(name, {}).get("path", ""))
	if path.is_empty():
		for script_path: String in index.scripts:
			if index.scripts[script_path].class_name == name:
				path = script_path
				break
	var info: Dictionary = index.scripts.get(path, {})
	var parent := str(info.get("extends", ""))
	if parent.is_empty():
		var global_base := str(global_classes().get(name, {}).get("base", ""))
		return _resolve_native(global_base, depth + 1) if not global_base.is_empty() else "RefCounted"
	return _resolve_native(parent, depth + 1)


## Virtuales de una clase nativa (con herencia): [{name, signature}] con los comunes primero.
func virtuals(native_class: String) -> Array[Dictionary]:
	if _virtuals_cache.has(native_class):
		return _virtuals_cache[native_class]
	var out: Array[Dictionary] = []
	var by_name: Dictionary = {}
	if ClassDB.class_exists(native_class):
		for method: Dictionary in ClassDB.class_get_method_list(native_class):
			var name: String = method.name
			if int(method.flags) & METHOD_FLAG_VIRTUAL and not name in HIDDEN_VIRTUALS and not by_name.has(name):
				by_name[name] = {"name": name, "signature": _signature(method)}
	for name: String in COMMON_VIRTUALS:
		if by_name.has(name):
			out.append(by_name[name])
			by_name.erase(name)
	if native_class != "Object" and not out.any(func(v: Dictionary) -> bool: return v.name == "_init"):
		out.append({"name": "_init", "signature": "_init() -> void:"})
	for name: String in by_name:
		out.append(by_name[name])
	_virtuals_cache[native_class] = out
	return out


## `nombre(arg: Tipo, ...) -> Retorno:` a partir de la info de ClassDB.
static func _signature(method: Dictionary) -> String:
	var args := PackedStringArray()
	for arg: Dictionary in method.args:
		args.append("%s: %s" % [arg.name, type_name(arg)])
	return "%s(%s) -> %s:" % [method.name, ", ".join(args), type_name(method["return"], true)]


## Nombre GDScript de un tipo de ClassDB (`{type, class_name, hint, hint_string, usage}`).
static func type_name(info: Dictionary, is_return: bool = false) -> String:
	var type := int(info.get("type", TYPE_NIL))
	if type == TYPE_NIL:
		return "Variant" if int(info.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT or not is_return else "void"
	if type == TYPE_OBJECT:
		var name := str(info.get("class_name", ""))
		return name if not name.is_empty() else "Object"
	if type == TYPE_ARRAY and int(info.get("hint", 0)) == PROPERTY_HINT_ARRAY_TYPE and not str(info.hint_string).is_empty():
		return "Array[%s]" % info.hint_string
	return type_string(type)


## Parámetros tipados de una señal (`body: Node2D`) en una clase nativa o un script del proyecto.
## null si no se conoce la señal.
func signal_params(owner_type: String, signal_name: String) -> Variant:
	var key := owner_type + "." + signal_name
	if _signal_cache.has(key):
		return _signal_cache[key]
	var result: Variant = null
	var path := str(global_classes().get(owner_type, {}).get("path", ""))
	var depth := 0
	var found := false
	while not found and not path.is_empty() and depth < 12:
		var info: Dictionary = index.scripts.get(path, {})
		if not info.is_empty() and (info.signals as Dictionary).has(signal_name):
			found = true
			var params: Variant = info.signals[signal_name]
			result = str(params) if params != null else null  # null: firma partida, desconocida
		else:
			var parent := str(info.get("extends", ""))
			owner_type = parent if not parent.is_empty() else str(global_classes().get(owner_type, {}).get("base", ""))
			path = parent if parent.begins_with("res://") else str(global_classes().get(parent, {}).get("path", ""))
		depth += 1
	if not found and ClassDB.class_exists(owner_type) and ClassDB.class_has_signal(owner_type, signal_name):
		var args := PackedStringArray()
		for arg: Dictionary in ClassDB.class_get_signal(owner_type, signal_name).args:
			args.append("%s: %s" % [arg.name, type_name(arg)])
		result = ", ".join(args)
	_signal_cache[key] = result
	return result


## Clases nativas, las más comunes primero y el resto de la más corta a la más larga.
func engine_classes() -> PackedStringArray:
	if _engine_classes.is_empty():
		var rest: Array = []
		for name: String in ClassDB.get_class_list():
			if not name.begins_with("_") and not name in COMMON_CLASSES:
				rest.append(name)
		rest.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length() if a.length() != b.length() else a < b)
		_engine_classes = COMMON_CLASSES.duplicate()
		_engine_classes.append_array(PackedStringArray(rest))
	return _engine_classes


# --- ProjectSettings -------------------------------------------------------------------------------

## `class_name` globales: nombre -> {path, base}.
func global_classes() -> Dictionary:
	if not _settings_cache.has("classes"):
		var classes: Dictionary = {}
		if settings_file.is_empty():
			for entry: Dictionary in ProjectSettings.get_global_class_list():
				classes[str(entry["class"])] = {"path": str(entry.path), "base": str(entry.base)}
		for path: String in index.scripts:
			var name := str(index.scripts[path].class_name)
			if not name.is_empty() and not classes.has(name):
				classes[name] = {"path": path, "base": str(index.scripts[path].extends)}
		_settings_cache.classes = classes
	return _settings_cache.classes


## Acciones del input map: las del proyecto primero y después las `ui_*` del motor.
func input_actions() -> PackedStringArray:
	if not _settings_cache.has("actions"):
		var own := PackedStringArray()
		var builtin := PackedStringArray()
		for name: String in _setting_names("input"):
			var action := name.substr(6)
			if action.begins_with("ui_"):
				builtin.append(action)
			else:
				own.append(action)
		own.append_array(builtin)
		_settings_cache.actions = own
	return _settings_cache.actions


## Autoloads: nombre -> ruta.
func autoloads() -> Dictionary:
	if not _settings_cache.has("autoloads"):
		var out: Dictionary = {}
		for name: String in _setting_names("autoload"):
			out[name.substr(9)] = str(_setting(name)).trim_prefix("*")
		_settings_cache.autoloads = out
	return _settings_cache.autoloads


## Grupos del proyecto, los más usados primero.
func groups() -> PackedStringArray:
	var names: Array = index.groups.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return index.groups[a] > index.groups[b] if index.groups[a] != index.groups[b] else a < b)
	return PackedStringArray(names)


## "emitter" (`_on_timer_timeout`) o "signal" (`_on_timeout`) según lo que más se usa en el proyecto.
func handler_style() -> String:
	return "signal" if int(index.handler_style.signal) > int(index.handler_style.emitter) else "emitter"


## Nombres `<sección>/<clave>` de ProjectSettings (o de `settings_file`).
func _setting_names(section: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not settings_file.is_empty():
		var config := _settings_config()
		if config.has_section(section):
			for key: String in config.get_section_keys(section):
				out.append(section + "/" + key)
		return out
	for property: Dictionary in ProjectSettings.get_property_list():
		var name := str(property.name)
		if name.begins_with(section + "/"):
			out.append(name)
	return out


func _setting(name: String) -> Variant:
	if settings_file.is_empty():
		return ProjectSettings.get_setting(name)
	return _settings_config().get_value(name.get_slice("/", 0), name.substr(name.find("/") + 1), null)


func _settings_config() -> ConfigFile:
	if not _settings_cache.has("config"):
		var config := ConfigFile.new()
		config.load(settings_file)
		_settings_cache.config = config
	return _settings_cache.config
