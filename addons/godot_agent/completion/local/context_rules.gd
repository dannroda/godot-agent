@tool
extends RefCounted
## ContextRules (spec §16.2a): reglas deterministas sobre ProjectContext. Cada regla mira lo escrito
## en la línea antes del caret y propone el resto, en orden de preferencia. Si una regla aplica, su
## primer candidato tiene prioridad sobre las demás fuentes (lo decide el Ranker).
## Las reglas que cierran comillas o paréntesis los incluyen: el post-procesado quita lo que ya
## está a la derecha del caret (autocierre del editor).
## Una regla que reconoce su contexto pero no puede elegir (varias opciones y nada escrito) devuelve
## un veto: las demás fuentes tampoco adivinan ahí.

const ProjectContext := preload("../project_context.gd")
const CompletionRequest := preload("../completion_request.gd")

const SCORE_FIRST := 0.95
const SCORE_STEP := 0.01
const SCORE_MIN := 0.8
const MAX_CANDIDATES := 8

## Tipo esperado del lado izquierdo de un preload/load -> extensiones aceptadas.
const TYPE_EXTENSIONS := {
	"PackedScene": ["tscn", "scn"],
	"Texture2D": ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "exr", "hdr", "ktx", "dds"],
	"Texture": ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "exr", "hdr", "ktx", "dds"],
	"CompressedTexture2D": ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga"],
	"AudioStream": ["wav", "ogg", "mp3"],
	"AudioStreamWAV": ["wav"],
	"AudioStreamOggVorbis": ["ogg"],
	"AudioStreamMP3": ["mp3"],
	"Script": ["gd"],
	"GDScript": ["gd"],
	"Shader": ["gdshader"],
	"Font": ["ttf", "otf", "woff", "woff2", "fnt", "tres"],
	"FontFile": ["ttf", "otf", "woff", "woff2", "fnt"],
	"Resource": ["tres", "res"],
}
## Archivos que `load`/`preload` pueden cargar (los demás, como .md o .cfg, no se sugieren).
const RESOURCE_EXTENSIONS: PackedStringArray = [
	"tscn", "scn", "tres", "res", "gd", "gdshader", "gdshaderinc", "png", "jpg", "jpeg", "webp", "svg",
	"bmp", "tga", "exr", "hdr", "ktx", "dds", "wav", "ogg", "mp3", "ttf", "otf", "woff", "woff2", "fnt",
	"glb", "gltf", "obj", "fbx", "blend", "dae", "json", "material", "mesh", "anim", "theme", "cs",
]
## Métodos de Input que reciben una sola acción: la regla cierra también el paréntesis.
const SINGLE_ACTION_METHODS: PackedStringArray = [
	"is_action_pressed", "is_action_just_pressed", "is_action_just_released", "is_action_released",
	"get_action_strength", "get_action_raw_strength", "action_press", "action_release",
]

var _re: Dictionary = {}


func _init() -> void:
	var patterns := {
		"onready": "^@onready\\s+var\\s+(\\w*)$",
		"node_path": "(?:^|[^\\w\"'])([$%])(\"?)([\\w/.%\\- ]*)$",
		"action": "(?:Input\\.(\\w+)|InputMap\\.(\\w+)|\\.(is_action\\w*))\\(\\s*(?:\"[^\"]*\"\\s*,\\s*)*\"(\\w*)$",
		"virtual": "^func\\s+(_\\w*)$",
		"connect": "(?:([$%]\"[^\"]+\"|[$%][\\w/]+|[\\w.]+)\\.)?(\\w+)\\.connect\\($",
		"handler": "^func\\s+(_on_\\w*)$",
		"group": "(?:add_to_group|is_in_group|get_nodes_in_group|call_group|get_first_node_in_group|remove_from_group)\\(\\s*(?:[\\w.|]+\\s*,\\s*)?\"(\\w*)$",
		"load": "(?:^|[^\\w.])(preload|load|ResourceLoader\\.load)\\(\\s*\"([^\"]*)$",
		"load_type": ":\\s*(\\w+)\\s*=\\s*(?:preload|load|ResourceLoader\\.load)\\(",
		"load_name": "(?:var|const)\\s+(\\w+)",
		"extends": "^extends\\s+(\\w*)$",
		"code_connect": "(?:([$%]\"[^\"]+\"|[$%][\\w/]+|[\\w.]+)\\.)?(\\w+)\\.connect\\(\\s*(\\w+)\\s*[,)]",
		"declared_var": "(?m)^\\s*(?:@\\w+(?:\\([^)]*\\))?\\s+)*var\\s+(\\w+)",
		"defined_func": "(?m)^(?:static\\s+)?func\\s+(_\\w+)\\s*\\(",
		"declared_path": "(?m)=\\s*([$%](?:\"[^\"]+\"|[\\w/%]+))",
	}
	for key: String in patterns:
		var re := RegEx.new()
		re.compile(patterns[key])
		_re[key] = re


## [{text, score, source, rule}] con `text` = lo que falta después del caret.
func candidates(request: CompletionRequest, context: ProjectContext) -> Array[Dictionary]:
	var prefix := request.line_prefix.strip_edges(true, false)
	var names: Array[Dictionary] = []
	if prefix.is_empty():
		return names
	if prefix.begins_with("@onready"):
		names = _onready(prefix, request, context)
	elif prefix.begins_with("func"):
		if prefix.contains("_on_"):
			names = _handlers(prefix, request, context)
		if names.is_empty():
			names = _virtuals(prefix, request, context)
	elif prefix.begins_with("extends"):
		names = _extends(prefix, context)
	if names.is_empty() and prefix.ends_with(".connect("):
		names = _connect(prefix, context)
	if names.is_empty() and (prefix.contains("$") or prefix.contains("%")):
		names = _node_paths(prefix, request, context)
	if names.is_empty() and prefix.contains("\""):
		if prefix.contains("load("):
			names = _load_paths(prefix, request, context)
		if names.is_empty() and prefix.contains("group"):
			names = _groups(prefix, context)
		if names.is_empty() and (prefix.contains("action") or prefix.contains("Input")):
			names = _actions(prefix, context)
	return names


## Sin nada escrito y con varias opciones no se adivina (una sugerencia equivocada molesta más que
## ninguna): veto. `@onready var ` y `func _` sí proponen la primera: su orden es el de la spec.
static func _choose(typed: String, texts: PackedStringArray, rule: String) -> Array[Dictionary]:
	if typed.is_empty() and texts.size() > 1:
		return [veto(rule)]
	return _ranked(texts, rule)


static func veto(rule: String) -> Dictionary:
	return {"text": "", "score": 0.0, "source": "rule", "rule": rule, "veto": true}


static func is_veto(candidates: Array[Dictionary]) -> bool:
	return candidates.size() == 1 and candidates[0].get("veto", false)


static func _ranked(texts: PackedStringArray, rule: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in mini(texts.size(), MAX_CANDIDATES):
		out.append({"text": texts[i], "score": maxf(SCORE_MIN, SCORE_FIRST - SCORE_STEP * i), "source": "rule", "rule": rule})
	return out


## `@onready var ` -> `<nombre>: <Tipo> = $<Ruta>` (o `%Nombre`) por cada nodo todavía no declarado.
func _onready(prefix: String, request: CompletionRequest, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.onready as RegEx).search(prefix)
	if found == null:
		return []
	var typed := found.get_string(1)
	var declared_vars: Dictionary = {}
	for match_var: RegExMatch in (_re.declared_var as RegEx).search_all(request.text):
		declared_vars[match_var.get_string(1)] = true
	var declared_paths: Dictionary = {}
	for match_path: RegExMatch in (_re.declared_path as RegEx).search_all(request.text):
		declared_paths[match_path.get_string(1).replace("\"", "")] = true
	# Lo que ya declara la clase base (un enemigo que hereda de Enemy ya tiene su sprite).
	var inherited := context.inherited_declarations(request.text)
	declared_vars.merge(inherited.vars)
	declared_paths.merge(inherited.references)
	var texts := PackedStringArray()
	var used := declared_vars.duplicate()
	# Hijos directos y nodos únicos primero (lo que un script suele referenciar), después el resto,
	# cada grupo en el orden del árbol.
	var nodes := context.child_nodes(request.path)
	var near: Array[Dictionary] = nodes.filter(func(n: Dictionary) -> bool: return n.unique or not str(n.path).contains("/"))
	near.append_array(nodes.filter(func(n: Dictionary) -> bool: return not (n.unique or not str(n.path).contains("/"))))
	for node: Dictionary in near:
		var reference := _node_reference(node)
		if reference.is_empty() or declared_paths.has(reference.replace("\"", "")) or declared_paths.has("$" + str(node.path)):
			continue
		var name := context.conventional_var_name(str(node.name), reference.replace("\"", ""))
		if name.is_empty() or used.has(name):
			name = _var_name(str(node.name))
		# Mismo nombre en otra rama (dos CollisionShape2D): se antepone el del padre.
		if used.has(name) and str(node.path).contains("/"):
			var parts := str(node.path).split("/")
			name = _var_name(parts[parts.size() - 2]) + "_" + name
		if used.has(name):
			continue
		used[name] = true
		if name.begins_with(typed) and name != typed:
			# Tipo desconocido: sin anotación (un `: Node` equivocado rompe el uso tipado).
			var declaration := "%s: %s = %s" % [name, node.type, reference] if not str(node.type).is_empty() else "%s = %s" % [name, reference]
			texts.append(declaration.substr(typed.length()))
	return _ranked(texts, "onready")


## `HealthBar2D` -> `health_bar_2d`; `Spawn Point` -> `spawn_point`.
static func _var_name(node_name: String) -> String:
	var name := node_name.replace(" ", "_").replace("-", "_").to_snake_case()
	while name.contains("__"):
		name = name.replace("__", "_")
	return name if name.is_valid_identifier() else "node_" + name


static func _node_reference(node: Dictionary) -> String:
	if node.unique:
		return "%" + str(node.name)
	var path := str(node.path)
	if path.is_empty():
		return ""
	return "$" + (path if path.is_valid_identifier() or _plain_path(path) else "\"%s\"" % path)


static func _plain_path(path: String) -> bool:
	for part: String in path.split("/"):
		if not part.is_valid_identifier():
			return false
	return true


## `$Ru` / `%No` -> resto de la ruta del nodo (los únicos primero).
func _node_paths(prefix: String, request: CompletionRequest, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.node_path as RegEx).search(prefix)
	if found == null or _in_string(prefix, found.get_start(1)):
		return []
	var sigil := found.get_string(1)
	var quoted := not found.get_string(2).is_empty()
	var typed := found.get_string(3)
	if not quoted and typed.contains(" "):
		return []
	# `%` también es el operador módulo/formato: como nodo único solo después de `=([{,:` o al inicio.
	if sigil == "%":
		var before := prefix.left(found.get_start(1)).strip_edges(false, true)
		if not before.is_empty() and not before.right(1) in ["=", "(", "[", "{", ",", ":"]:
			return []
	var texts := PackedStringArray()
	var nodes := context.child_nodes(request.path)
	# `%`: solo únicos. `$` sin nada escrito: los únicos primero; con algo escrito, orden del árbol
	# (así `$UI/B` completa el siguiente tramo y no la ruta más profunda).
	var ordered: Array[Dictionary] = nodes.filter(func(n: Dictionary) -> bool: return n.unique)
	if sigil == "$":
		if not typed.is_empty():
			ordered.clear()
		ordered.append_array(nodes.filter(func(n: Dictionary) -> bool: return not str(n.path).is_empty() and (not n.unique or not typed.is_empty())))
	for node: Dictionary in ordered:
		var target := str(node.name) if sigil == "%" or str(node.path).is_empty() else str(node.path)
		if sigil == "$" and node.unique and str(node.path).is_empty():
			continue
		if target.begins_with(typed) and target != typed:
			if not quoted and not _plain_path(target):
				continue
			texts.append(target.substr(typed.length()) + ("\"" if quoted else ""))
	# Lo que cuenta es el tramo que se está escribiendo: `$Props/` todavía no eligió nada.
	return _choose(typed.get_slice("/", typed.get_slice_count("/") - 1), texts, "node_path")


## Dentro de `Input.is_action_*("`, `Input.get_axis("` o `InputMap.*("` -> acciones del input map.
func _actions(prefix: String, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.action as RegEx).search(prefix)
	if found == null:
		return []
	var method := found.get_string(1) + found.get_string(2) + found.get_string(3)
	var typed := found.get_string(4)
	var closing := "\")" if method in SINGLE_ACTION_METHODS else "\""
	var texts := PackedStringArray()
	for action: String in context.input_actions():
		if action.begins_with(typed) and action != typed:
			texts.append(action.substr(typed.length()) + closing)
	return _choose(typed, texts, "action")


## `func _` -> virtuales de la clase base con firma, salvo los ya definidos.
func _virtuals(prefix: String, request: CompletionRequest, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.virtual as RegEx).search(prefix)
	if found == null:
		return []
	var typed := found.get_string(1)
	var texts := PackedStringArray()
	var defined: Dictionary = {}
	for match_func: RegExMatch in (_re.defined_func as RegEx).search_all(request.text):
		defined[match_func.get_string(1)] = true
	for virtual: Dictionary in context.virtuals(context.native_base(request.text)):
		var name: String = virtual.name
		if name.begins_with(typed) and not defined.has(name):
			texts.append(str(virtual.signature).substr(typed.length()))
	return _ranked(texts, "virtual")


## `<emisor>.<señal>.connect(` -> `_on_<señal>)` o `_on_<emisor>_<señal>)` según el proyecto.
func _connect(prefix: String, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.connect as RegEx).search(prefix)
	if found == null:
		return []
	var signal_name := found.get_string(2)
	var emitter := _emitter_name(found.get_string(1))
	var handler := "_on_" + signal_name
	if not emitter.is_empty() and context.handler_style() == "emitter":
		handler = "_on_%s_%s" % [emitter, signal_name]
	return _ranked(PackedStringArray([handler + ")"]), "connect")


## `$Path/Timer` -> `timer`; `self` o vacío -> "".
static func _emitter_name(expression: String) -> String:
	var name := expression.replace("\"", "").trim_prefix("$").trim_prefix("%")
	if name.is_empty() or name == "self":
		return ""
	name = name.get_slice("/", name.get_slice_count("/") - 1)
	name = name.get_slice(".", name.get_slice_count(".") - 1)
	return name.to_snake_case()


## `func _on_` -> handlers conectados (en escenas o en este script) que todavía no tienen función.
func _handlers(prefix: String, request: CompletionRequest, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.handler as RegEx).search(prefix)
	if found == null:
		return []
	var typed := found.get_string(1)
	var texts := PackedStringArray()
	var seen: Dictionary = {}
	for pending: Dictionary in context.pending_scene_handlers(request.path, request.text):
		var params: Variant = context.signal_params(str(pending.emitter_type), str(pending.signal))
		_add_handler(texts, seen, typed, str(pending.method), params)
	var nodes := context.child_nodes(request.path)
	for connect: RegExMatch in (_re.code_connect as RegEx).search_all(request.text):
		var method := connect.get_string(3)
		if ProjectContext._defines(request.text, method) or not method.begins_with("_on_"):
			continue
		var emitter_type := _expression_type(connect.get_string(1), nodes, context, request.text)
		var params: Variant = context.signal_params(emitter_type, connect.get_string(2)) if not emitter_type.is_empty() else null
		_add_handler(texts, seen, typed, method, params)
	return _ranked(texts, "handler")


static func _add_handler(texts: PackedStringArray, seen: Dictionary, typed: String, method: String, params: Variant) -> void:
	# Sin la firma de la señal no se sugiere: un handler con aridad equivocada falla al conectar.
	if params == null or seen.has(method) or not method.begins_with(typed) or method == typed:
		return
	seen[method] = true
	texts.append(("%s(%s) -> void:" % [method, params]).substr(typed.length()))


## Tipo del emisor de un `.connect(` en código: `$Ruta`/`%Unico` por los nodos de la escena, `self`
## o nada por la clase base del script.
func _expression_type(expression: String, nodes: Array[Dictionary], context: ProjectContext, text: String) -> String:
	if expression.is_empty() or expression == "self":
		return context.native_base(text)
	var clean := expression.replace("\"", "")
	for node: Dictionary in nodes:
		if (clean.begins_with("$") and clean.substr(1) == str(node.path)) or (clean.begins_with("%") and node.unique and clean.substr(1) == str(node.name)):
			return node.type
	return ""


## Dentro de `add_to_group("`, `is_in_group("`, ... -> grupos usados en el proyecto.
func _groups(prefix: String, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.group as RegEx).search(prefix)
	if found == null:
		return []
	var typed := found.get_string(1)
	var texts := PackedStringArray()
	for group: String in context.groups():
		if group.begins_with(typed) and group != typed:
			texts.append(group.substr(typed.length()) + "\"")
	return _choose(typed, texts, "group")


## `preload("` / `load("` -> rutas `res://` filtradas por el tipo del lado izquierdo; las de la
## carpeta del script primero. Sin nada escrito solo sugiere si hay una sola opción.
func _load_paths(prefix: String, request: CompletionRequest, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.load as RegEx).search(prefix)
	if found == null:
		return []
	var typed := found.get_string(2)
	var extensions: Array = []
	var typed_found := (_re.load_type as RegEx).search(prefix)
	if typed_found:
		extensions = TYPE_EXTENSIONS.get(typed_found.get_string(1), [])
	var same_dir := PackedStringArray()
	var others := PackedStringArray()
	var folder := request.path.get_base_dir() + "/"
	for path: String in context.index.resources:
		if path == request.path or not path.begins_with(typed) or path == typed:
			continue
		var extension := path.get_extension().to_lower()
		if not extension in RESOURCE_EXTENSIONS or (not extensions.is_empty() and not extension in extensions):
			continue
		if path.begins_with(folder) and not path.substr(folder.length()).contains("/"):
			same_dir.append(path)
		else:
			others.append(path)
	same_dir.append_array(others)
	if same_dir.size() > 1 and typed.trim_prefix("res://").is_empty():
		# Sin ruta escrita, el nombre de la variable puede elegir (`ARROW_SCENE` -> arrow.tscn).
		var named := _by_variable_name(prefix, same_dir)
		if named.is_empty():
			return [veto("load")]
		same_dir = PackedStringArray([named])
	var texts := PackedStringArray()
	for path: String in same_dir:
		texts.append(path.substr(typed.length()) + "\")")
	return _ranked(texts, "load")


## El recurso cuyo nombre de archivo coincide con más palabras del nombre de la variable de la
## izquierda (`const ARROW_SCENE := preload("` -> `arrow.tscn`), si es uno solo; "" si no.
func _by_variable_name(prefix: String, paths: PackedStringArray) -> String:
	var found := (_re.load_name as RegEx).search(prefix)
	if found == null:
		return ""
	var words := found.get_string(1).to_lower().split("_", false)
	var best := ""
	var best_score := 0
	var tied := false
	for path: String in paths:
		var file_words := path.get_file().get_basename().to_snake_case().split("_", false)
		var score := 0
		for word: String in words:
			if word in file_words:
				score += 1
		if score > best_score:
			best = path
			best_score = score
			tied = false
		elif score == best_score and score > 0:
			tied = true
	return best if not tied else ""


## `extends ` -> clases del proyecto (`class_name`) y del motor; hace falta al menos una letra.
func _extends(prefix: String, context: ProjectContext) -> Array[Dictionary]:
	var found := (_re.extends as RegEx).search(prefix)
	if found == null:
		return []
	if found.get_string(1).is_empty():
		return [veto("extends")]
	var typed := found.get_string(1)
	var texts := PackedStringArray()
	var project: Array = context.global_classes().keys()
	project.sort()
	for name: String in project:
		if name.begins_with(typed) and name != typed:
			texts.append(name.substr(typed.length()))
	for name: String in context.engine_classes():
		if texts.size() >= MAX_CANDIDATES:
			break
		if name.begins_with(typed) and name != typed:
			texts.append(name.substr(typed.length()))
	return _ranked(texts, "extends")


## ¿La posición cae dentro de un string? Cuenta comillas sin escapar antes de ella.
static func _in_string(text: String, position: int) -> bool:
	var quote := ""
	var i := 0
	while i < position:
		var c := text[i]
		if c == "\\":
			i += 2
			continue
		if quote.is_empty() and (c == "\"" or c == "'"):
			quote = c
		elif c == quote:
			quote = ""
		elif quote.is_empty() and c == "#":
			return true
		i += 1
	return not quote.is_empty()
