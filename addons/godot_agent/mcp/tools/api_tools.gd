@tool
extends RefCounted
## Tools de la API del motor (grupo read): class_info y search_api. Responden con lo que tiene el
## binario del editor abierto: miembros y herencia salen de ClassDB, las descripciones del caché
## de documentación que arma el editor (`editor_doc_cache-<versión>.res`). Los tipos built-in
## (Vector2, Array…) y @GlobalScope/@GDScript salen solo del caché; los class_name del proyecto,
## de su script.

const McpTool := preload("../mcp_tool.gd")
const PermissionPolicy := preload("../../session/permission_policy.gd")

const SEARCH_LIMIT := 40
const BRIEF_CHARS := 110
const KINDS: PackedStringArray = ["class", "method", "property", "signal", "constant"]

## Ruta del caché de documentación; vacío = no hay descripciones (solo ClassDB).
var doc_cache_path: String = ""

var _docs: Dictionary = {}  # nombre de clase -> ClassDoc (Dictionary del caché)
var _docs_loaded := false
var _search_index: Array[Dictionary] = []


## Ruta del caché que arma el editor para esta versión.
static func editor_doc_cache_path() -> String:
	var version := Engine.get_version_info()
	return EditorInterface.get_editor_paths().get_cache_dir().path_join("editor_doc_cache-%d.%d.res" % [version.major, version.minor])


func tools() -> Array:
	var read := PermissionPolicy.GROUP_READ
	return [
		McpTool.create("class_info", read,
			"API of a class in THIS editor's Godot version (use it instead of guessing method names or signatures from memory): inheritance, methods with signatures, properties with defaults, signals, constants and enums, each with a one-line description. Works for engine classes, built-in types (Vector2, Array, String…), @GlobalScope, @GDScript and project class_names. Pass `member` for the full documentation of one method, property, signal or constant.",
			{
				"class": {"type": "string", "description": "Class name, e.g. CharacterBody2D, Vector2, @GlobalScope, or a project class_name"},
				"member": {"type": "string", "description": "Only this member, with its full description (searched in the ancestors too)"},
				"inherited": {"type": "boolean", "description": "Also list the members of every ancestor (default false: only the class's own)"},
				"description": {"type": "boolean", "description": "Include the class's full description and tutorials (default false: only the brief one)"},
			}, ["class"], _class_info),
		McpTool.create("search_api", read,
			"Searches THIS editor's Godot API by name or capability: classes, methods, properties, signals and constants whose name (or, for classes, description) contains every word of `query`. E.g. \"raycast\", \"move toward\", \"tween property\", \"screen shake\".",
			{
				"query": {"type": "string"},
				"kind": {"type": "string", "enum": Array(KINDS), "description": "Only results of this kind"},
				"class": {"type": "string", "description": "Only members of this class and its ancestors"},
			}, ["query"], _search_api),
	]


# --- tools ---------------------------------------------------------------------------------------

func _class_info(args: Dictionary) -> Dictionary:
	var name := _resolve_class(str(args["class"]))
	if name.is_empty():
		return McpTool.error(_unknown_class(str(args["class"])))
	var member := McpTool.str_arg(args, "member").strip_edges()
	if not member.is_empty():
		return _member_info(name, member)
	var lines: PackedStringArray = []
	var doc := _doc(name)
	var script_info := _script_class(name)
	var chain := _ancestors(name)
	var header := name
	if not chain.is_empty():
		header += " (extends %s)" % chain[0]
	var brief := _plain(str(doc.get("brief_description", "")))
	lines.append(header + (" — " + brief if not brief.is_empty() else ""))
	if chain.size() > 1:
		lines.append("Inherits: %s" % " < ".join(chain))
	if not script_info.is_empty():
		lines.append("Project class_name, script %s." % script_info.path)
	elif ClassDB.class_exists(name) and not ClassDB.can_instantiate(name) and ClassDB.is_parent_class(name, &"Object"):
		lines.append("Abstract or singleton: it cannot be created with new().")
	lines.append("Godot %s%s" % [Engine.get_version_info().string, "" if _has_docs() else " · no documentation cache: members without descriptions"])
	if args.get("description") == true:
		var full := _plain(str(doc.get("description", "")))
		if not full.is_empty():
			lines.append("")
			lines.append(full)
		for tutorial: Variant in doc.get("tutorials", []):
			if tutorial is Dictionary:
				lines.append("Tutorial: %s %s" % [tutorial.get("title", ""), tutorial.get("link", "")])
	var classes: PackedStringArray = [name]
	if args.get("inherited") == true:
		classes.append_array(chain)
	for class_name_: String in classes:
		var section := _members_text(class_name_)
		if section.is_empty():
			continue
		lines.append("")
		if class_name_ != name:
			lines.append("── from %s ──" % class_name_)
		lines.append(section)
	if args.get("inherited") != true and not chain.is_empty():
		lines.append("")
		lines.append("(Only %s's own members. Inherited ones: inherited=true, or class_info on %s.)" % [name, chain[0]])
	return McpTool.text("\n".join(lines))


func _search_api(args: Dictionary) -> Dictionary:
	var words := str(args.query).to_lower().replace("_", " ").split(" ", false)
	if words.is_empty():
		return McpTool.error("`query` is empty.")
	var kind := McpTool.str_arg(args, "kind")
	var only_classes: PackedStringArray = []
	var within := McpTool.str_arg(args, "class")
	if not within.is_empty():
		var resolved := _resolve_class(within)
		if resolved.is_empty():
			return McpTool.error(_unknown_class(within))
		only_classes.append(resolved)
		only_classes.append_array(_ancestors(resolved))
	var hits: Array[Dictionary] = []
	for entry: Dictionary in _index():
		if not kind.is_empty() and entry.kind != kind:
			continue
		if not only_classes.is_empty() and not entry.owner in only_classes:
			continue
		var score := _score(entry, words)
		if score > 0:
			hits.append({"entry": entry, "score": score})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.score != b.score:
			return a.score > b.score
		return str(a.entry.key).length() < str(b.entry.key).length())
	if hits.is_empty():
		return McpTool.text("Nothing in the Godot %s API matches \"%s\". Try fewer or different words (a name fragment like \"collide\" or \"tween\")." % [Engine.get_version_info().string, args.query])
	var lines: PackedStringArray = ["%d result(s) for \"%s\" in Godot %s%s:" % [hits.size(), args.query, Engine.get_version_info().string, " (first %d)" % SEARCH_LIMIT if hits.size() > SEARCH_LIMIT else ""]]
	for hit: Dictionary in hits.slice(0, SEARCH_LIMIT):
		var entry: Dictionary = hit.entry
		var brief := _brief_of(entry)
		lines.append("- %s %s%s" % [entry.kind, entry.key, " — " + brief if not brief.is_empty() else ""])
	lines.append("Details: class_info with `class` (and `member`).")
	return McpTool.text("\n".join(lines))


# --- clases --------------------------------------------------------------------------------------

## Nombre canónico de la clase (ClassDB, docs o class_name; sin distinguir mayúsculas), o "".
func _resolve_class(text: String) -> String:
	var name := text.strip_edges()
	if ClassDB.class_exists(name) or _docs_index().has(name) or not _script_class(name).is_empty():
		return name
	var lower := name.to_lower()
	for candidate: String in _all_class_names():
		if candidate.to_lower() == lower:
			return candidate
	return ""


func _unknown_class(text: String) -> String:
	var lower := text.strip_edges().to_lower()
	var scored: Array = []
	for candidate: String in _all_class_names():
		var similarity := candidate.to_lower().similarity(lower)
		if similarity > 0.45 or candidate.to_lower().contains(lower):
			scored.append([similarity, candidate])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var names: PackedStringArray = []
	for item: Array in scored.slice(0, 8):
		names.append(item[1])
	var message := "There is no class '%s' in Godot %s (neither engine, built-in type nor project class_name)." % [text, Engine.get_version_info().string]
	if not names.is_empty():
		message += " Similar: %s." % ", ".join(names)
	return message + " Use search_api to find it by capability."


func _all_class_names() -> PackedStringArray:
	var names := ClassDB.get_class_list()
	for name: String in _docs_index():
		if not ClassDB.class_exists(name):
			names.append(name)
	for info: Dictionary in ProjectSettings.get_global_class_list():
		names.append(str(info["class"]))
	return names


## Ancestros, del padre a Object. Los class_name siguen por su base.
func _ancestors(name: String) -> PackedStringArray:
	var chain: PackedStringArray = []
	var current := name
	for _guard: int in 64:
		var parent := ""
		var script_info := _script_class(current)
		if not script_info.is_empty():
			parent = str(script_info.base)
		elif ClassDB.class_exists(current):
			parent = String(ClassDB.get_parent_class(current))
		else:
			parent = str(_doc(current).get("inherits", ""))
		if parent.is_empty():
			break
		chain.append(parent)
		current = parent
	return chain


func _script_class(name: String) -> Dictionary:
	for info: Dictionary in ProjectSettings.get_global_class_list():
		if str(info["class"]) == name:
			return {"path": str(info.path), "base": str(info.base)}
	return {}


# --- miembros ------------------------------------------------------------------------------------

## Métodos, propiedades, señales y constantes propios de la clase, una línea cada uno.
func _members_text(name: String) -> String:
	var members := _members(name)
	var lines: PackedStringArray = []
	for section: Array in [["Methods", members.methods], ["Properties", members.properties], ["Signals", members.signals], ["Constants and enums", members.constants]]:
		var items: Array = section[1]
		if items.is_empty():
			continue
		lines.append("%s (%d):" % [section[0], items.size()])
		for item: Dictionary in items:
			var brief := _brief(str(item.get("description", "")))
			lines.append("  %s%s" % [item.signature, " — " + brief if not brief.is_empty() else ""])
	return "\n".join(lines)


## {methods, properties, signals, constants}: cada uno [{name, signature, description}].
## `defaults` = false no pide los valores por defecto (ClassDB instancia la clase para eso).
func _members(name: String, defaults: bool = true) -> Dictionary:
	var script_info := _script_class(name)
	if not script_info.is_empty():
		return _script_members(script_info.path)
	if ClassDB.class_exists(name):
		return _classdb_members(name, defaults)
	return _doc_members(_doc(name))


func _classdb_members(name: String, defaults: bool) -> Dictionary:
	var doc := _doc(name)
	var method_docs := _by_name(doc.get("methods", []))
	var property_docs := _by_name(doc.get("properties", []))
	var signal_docs := _by_name(doc.get("signals", []))
	var constant_docs := _by_name(doc.get("constants", []))
	var accessors := {}
	var properties: Array[Dictionary] = []
	for info: Dictionary in ClassDB.class_get_property_list(name, true):
		if int(info.usage) & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_INTERNAL):
			continue
		var property := str(info.name)
		if property.contains("/") and not property_docs.has(property):
			continue
		accessors[String(ClassDB.class_get_property_setter(name, property))] = true
		accessors[String(ClassDB.class_get_property_getter(name, property))] = true
		var signature := "%s: %s" % [property, _type_text(info, false)]
		var default_value: Variant = ClassDB.class_get_property_default_value(name, property) if defaults else null
		if default_value != null:
			signature += " = %s" % _value_text(default_value)
		elif property_docs.has(property) and not str(property_docs[property].get("default_value", "")).is_empty():
			signature += " = %s" % property_docs[property].default_value
		properties.append({"name": property, "signature": signature, "description": property_docs.get(property, {}).get("description", "")})
	var methods: Array[Dictionary] = []
	for info: Dictionary in ClassDB.class_get_method_list(name, true):
		var method := str(info.name)
		if accessors.has(method) and not method_docs.has(method):
			continue
		if method.begins_with("_") and not int(info.flags) & METHOD_FLAG_VIRTUAL:
			continue
		methods.append({"name": method, "signature": _method_signature(info), "description": method_docs.get(method, {}).get("description", "")})
	methods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	var signals: Array[Dictionary] = []
	for info: Dictionary in ClassDB.class_get_signal_list(name, true):
		signals.append({"name": str(info.name), "signature": "%s(%s)" % [info.name, _args_text(info.get("args", []), [])], "description": signal_docs.get(str(info.name), {}).get("description", "")})
	var constants: Array[Dictionary] = []
	var in_enum := {}
	for enum_name: String in ClassDB.class_get_enum_list(name, true):
		var values: PackedStringArray = []
		for constant: String in ClassDB.class_get_enum_constants(name, enum_name, true):
			values.append("%s = %d" % [constant, ClassDB.class_get_integer_constant(name, constant)])
			in_enum[constant] = true
		constants.append({"name": enum_name, "signature": "enum %s { %s }" % [enum_name, ", ".join(values)], "description": ""})
	for constant: String in ClassDB.class_get_integer_constant_list(name, true):
		if not in_enum.has(constant):
			constants.append({"name": constant, "signature": "%s = %d" % [constant, ClassDB.class_get_integer_constant(name, constant)], "description": constant_docs.get(constant, {}).get("description", "")})
	return {"methods": methods, "properties": properties, "signals": signals, "constants": constants}


## Tipos built-in, @GlobalScope y @GDScript: todo del caché de docs.
func _doc_members(doc: Dictionary) -> Dictionary:
	var methods: Array[Dictionary] = []
	for key: String in ["constructors", "methods", "operators"]:
		for item: Variant in doc.get(key, []):
			if item is Dictionary:
				var args_text := _doc_args(item.get("arguments", []))
				var qualifiers := str(item.get("qualifiers", ""))
				var signature := "%s(%s)" % [item.name, args_text]
				if key != "constructors":
					signature += " -> %s" % item.get("return_type", "void")
				if not qualifiers.is_empty():
					signature += " [%s]" % qualifiers
				methods.append({"name": str(item.name), "signature": signature, "description": item.get("description", "")})
	var properties: Array[Dictionary] = []
	for item: Variant in doc.get("properties", []):
		if item is Dictionary:
			var default_text := str(item.get("default_value", ""))
			properties.append({"name": str(item.name), "signature": "%s: %s%s" % [item.name, item.get("type", "Variant"), " = " + default_text if not default_text.is_empty() else ""], "description": item.get("description", "")})
	var signals: Array[Dictionary] = []
	for item: Variant in doc.get("signals", []):
		if item is Dictionary:
			signals.append({"name": str(item.name), "signature": "%s(%s)" % [item.name, _doc_args(item.get("arguments", []))], "description": item.get("description", "")})
	var constants: Array[Dictionary] = []
	for item: Variant in doc.get("constants", []):
		if item is Dictionary:
			var enum_name := str(item.get("enumeration", ""))
			constants.append({"name": str(item.name), "signature": "%s%s = %s" % [enum_name + "." if not enum_name.is_empty() else "", item.name, item.get("value", "")], "description": item.get("description", "")})
	return {"methods": methods, "properties": properties, "signals": signals, "constants": constants}


func _script_members(path: String) -> Dictionary:
	var script := load(path) as Script
	var empty := {"methods": [], "properties": [], "signals": [], "constants": []}
	if script == null:
		return empty
	var methods: Array[Dictionary] = []
	for info: Dictionary in script.get_script_method_list():
		if str(info.name).begins_with("@"):
			continue
		methods.append({"name": str(info.name), "signature": _method_signature(info), "description": ""})
	var properties: Array[Dictionary] = []
	for info: Dictionary in script.get_script_property_list():
		if int(info.usage) & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_CATEGORY) or str(info.name).ends_with(".gd"):
			continue
		var exported := int(info.usage) & PROPERTY_USAGE_EDITOR != 0
		properties.append({"name": str(info.name), "signature": "%s%s: %s" % ["@export " if exported else "", info.name, _type_text(info, false)], "description": ""})
	var signals: Array[Dictionary] = []
	for info: Dictionary in script.get_script_signal_list():
		signals.append({"name": str(info.name), "signature": "%s(%s)" % [info.name, _args_text(info.get("args", []), [])], "description": ""})
	var constants: Array[Dictionary] = []
	var constant_map := script.get_script_constant_map()
	for constant: String in constant_map:
		var value: Variant = constant_map[constant]
		if value is Script or value is Resource:
			continue
		constants.append({"name": constant, "signature": "%s = %s" % [constant, _value_text(value)], "description": ""})
	return {"methods": methods, "properties": properties, "signals": signals, "constants": constants}


## Un miembro con su documentación completa; se busca en la clase y en sus ancestros.
func _member_info(name: String, member: String) -> Dictionary:
	var classes: PackedStringArray = [name]
	classes.append_array(_ancestors(name))
	for owner: String in classes:
		var members := _members(owner)
		for kind: String in ["methods", "properties", "signals", "constants"]:
			for item: Dictionary in members[kind]:
				if item.name != member and not (kind == "constants" and str(item.signature).begins_with("enum %s " % member)):
					continue
				var lines: PackedStringArray = ["%s.%s (%s%s)" % [owner, member, kind.trim_suffix("s"), ", inherited by %s" % name if owner != name else ""]]
				lines.append(str(item.signature))
				var description := _plain(str(item.get("description", "")))
				lines.append("")
				lines.append(description if not description.is_empty() else "(no description in the documentation)")
				return McpTool.text("\n".join(lines))
	var similar: PackedStringArray = []
	for owner: String in classes:
		var members := _members(owner)
		for kind: String in ["methods", "properties", "signals", "constants"]:
			for item: Dictionary in members[kind]:
				if str(item.name).to_lower().contains(member.to_lower()) or str(item.name).similarity(member) > 0.6:
					similar.append("%s.%s" % [owner, item.name])
	var message := "%s has no member '%s' (searched in %s)." % [name, member, ", ".join(classes)]
	if not similar.is_empty():
		message += " Similar: %s." % ", ".join(similar.slice(0, 10))
	return McpTool.error(message)


# --- búsqueda ------------------------------------------------------------------------------------

func _index() -> Array[Dictionary]:
	if not _search_index.is_empty():
		return _search_index
	for name: String in _all_class_names():
		_search_index.append({"kind": "class", "owner": name, "name": name, "key": name})
		var members := _members(name, false)
		for pair: Array in [["method", members.methods], ["property", members.properties], ["signal", members.signals], ["constant", members.constants]]:
			for item: Dictionary in pair[1]:
				_search_index.append({"kind": pair[0], "owner": name, "name": item.name, "key": "%s.%s" % [name, item.signature], "description": item.description})
	return _search_index


func _score(entry: Dictionary, words: PackedStringArray) -> int:
	var name := str(entry.name).to_lower().replace("_", " ")
	var compact := name.replace(" ", "")
	var query := " ".join(words)
	if compact == query.replace(" ", ""):
		return 100
	var all_in_name := true
	for word: String in words:
		if not compact.contains(word):
			all_in_name = false
			break
	if all_in_name:
		return 60 if entry.kind == "class" else 50
	if entry.kind != "class":
		return 0
	var brief := _brief_of(entry).to_lower()
	for word: String in words:
		if not brief.contains(word):
			return 0
	return 10


func _brief_of(entry: Dictionary) -> String:
	if entry.kind == "class":
		return _plain(str(_doc(entry.name).get("brief_description", ""))).left(BRIEF_CHARS)
	return _brief(str(entry.get("description", "")))


# --- documentación -------------------------------------------------------------------------------

func _has_docs() -> bool:
	return not _docs_index().is_empty()


func _doc(name: String) -> Dictionary:
	return _docs_index().get(name, {})


func _docs_index() -> Dictionary:
	if _docs_loaded:
		return _docs
	_docs_loaded = true
	if doc_cache_path.is_empty() or not FileAccess.file_exists(doc_cache_path):
		return _docs
	var cache := ResourceLoader.load(doc_cache_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if cache == null or not cache.has_meta(&"classes"):
		return _docs
	for item: Variant in cache.get_meta(&"classes"):
		if item is Dictionary and item.get("name") is String:
			_docs[item.name] = item
	return _docs


static func _by_name(items: Variant) -> Dictionary:
	var result := {}
	if items is Array:
		for item: Variant in items:
			if item is Dictionary and item.has("name"):
				result[str(item.name)] = item
	return result


## Primera oración de una descripción, en texto plano y recortada.
static func _brief(description: String) -> String:
	var text := _plain(description).get_slice("\n", 0)
	var end := text.find(". ")
	if end >= 0:
		text = text.left(end + 1)
	return text if text.length() <= BRIEF_CHARS else text.left(BRIEF_CHARS - 1) + "…"


## BBCode de la documentación de Godot → texto plano con `código` y bloques ```gdscript.
static func _plain(bbcode: String) -> String:
	var text := bbcode
	text = RegEx.create_from_string("(?s)\\[csharp\\].*?\\[/csharp\\]").sub(text, "", true)
	text = RegEx.create_from_string("\\[/?(codeblocks|gdscript)\\]").sub(text, "", true)
	text = RegEx.create_from_string("\\[codeblock[^\\]]*\\]").sub(text, "\n```gdscript", true)
	text = text.replace("[/codeblock]", "```\n")
	var lines: PackedStringArray = []
	var in_code := false
	var indent := ""
	for raw_line: String in text.split("\n"):
		var line := raw_line
		if line.strip_edges().begins_with("```"):
			in_code = not in_code
			indent = ""
			lines.append(line.strip_edges())
			continue
		if in_code:
			if indent.is_empty() and not line.strip_edges().is_empty():
				indent = line.substr(0, line.length() - line.strip_edges(true, false).length())
			lines.append(line.trim_prefix(indent).replace("\t", "    "))
		else:
			lines.append(line.strip_edges())
	text = "\n".join(lines)
	text = RegEx.create_from_string("\\[(?:code|kbd)\\](.*?)\\[/(?:code|kbd)\\]").sub(text, "`$1`", true)
	text = RegEx.create_from_string("\\[method ([^\\]]+)\\]").sub(text, "$1()", true)
	text = RegEx.create_from_string("\\[(?:member|constant|signal|param|enum|annotation|theme_item|constructor|operator) ([^\\]]+)\\]").sub(text, "$1", true)
	text = RegEx.create_from_string("\\[url=[^\\]]*\\](.*?)\\[/url\\]").sub(text, "$1", true)
	text = text.replace("[br]", "\n")
	text = RegEx.create_from_string("\\[/?(?:b|i|u|s|center|lb|rb|font[^\\]]*|color[^\\]]*)\\]").sub(text, "", true)
	text = RegEx.create_from_string("\\[([A-Z@][A-Za-z0-9_.]*)\\]").sub(text, "$1", true)
	text = RegEx.create_from_string("\\n{3,}").sub(text, "\n\n", true)
	return text.strip_edges()


# --- formato -------------------------------------------------------------------------------------

static func _method_signature(info: Dictionary) -> String:
	var flags := int(info.get("flags", 0))
	var signature := "%s(%s)" % [info.name, _args_text(info.get("args", []), info.get("default_args", []))]
	if flags & METHOD_FLAG_VARARG:
		signature = signature.trim_suffix(")") + (", ..." if not info.get("args", []).is_empty() else "...") + ")"
	signature += " -> %s" % _type_text(info.get("return", {}), true)
	var qualifiers: PackedStringArray = []
	if flags & METHOD_FLAG_VIRTUAL:
		qualifiers.append("virtual")
	if flags & METHOD_FLAG_CONST:
		qualifiers.append("const")
	if flags & METHOD_FLAG_STATIC:
		qualifiers.append("static")
	if not qualifiers.is_empty():
		signature += " [%s]" % " ".join(qualifiers)
	return signature


static func _args_text(args: Array, defaults: Array) -> String:
	var parts: PackedStringArray = []
	var first_default := args.size() - defaults.size()
	for i: int in args.size():
		var arg: Dictionary = args[i]
		var part := "%s: %s" % [arg.name, _type_text(arg, false)]
		if i >= first_default:
			part += " = %s" % _value_text(defaults[i - first_default])
		parts.append(part)
	return ", ".join(parts)


static func _doc_args(args: Variant) -> String:
	var parts: PackedStringArray = []
	if args is Array:
		for arg: Variant in args:
			if arg is Dictionary:
				var default_text := str(arg.get("default_value", ""))
				parts.append("%s: %s%s" % [arg.get("name", ""), arg.get("type", "Variant"), " = " + default_text if not default_text.is_empty() else ""])
	return ", ".join(parts)


static func _type_text(info: Dictionary, is_return: bool) -> String:
	var type := int(info.get("type", TYPE_NIL))
	var class_text := str(info.get("class_name", ""))
	if type == TYPE_ARRAY and int(info.get("hint", 0)) == PROPERTY_HINT_ARRAY_TYPE:
		return "Array[%s]" % info.get("hint_string", "")
	if type == TYPE_DICTIONARY and int(info.get("hint", 0)) == PROPERTY_HINT_DICTIONARY_TYPE:
		return "Dictionary[%s]" % str(info.get("hint_string", "")).replace(";", ", ")
	if not class_text.is_empty():
		return class_text
	if type == TYPE_NIL:
		return "void" if is_return and not int(info.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT else "Variant"
	return type_string(type)


static func _value_text(value: Variant) -> String:
	if value is String or value is StringName:
		return "\"%s\"" % value
	if value is Object:
		return "<%s>" % value.get_class() if value else "null"
	return var_to_str(value).replace("\n", " ")
