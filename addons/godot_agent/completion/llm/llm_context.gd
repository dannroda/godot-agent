@tool
extends RefCounted
## Contexto del proyecto para el LLM (spec §16.4): comentarios GDScript que van antes del prefix, o
## en `input_extra` de llama.cpp. Se llena por prioridad hasta el presupuesto (tokens estimados a 4
## caracteres por token): rutas de nodos del script, clase base, clases del proyecto que el archivo
## nombra, autoloads, input map y el resto (grupos).

const ProjectContext := preload("../project_context.gd")

const CHARS_PER_TOKEN := 4
const DEFAULT_BUDGET_TOKENS := 2000
## Por sección, para que una escena enorme no se coma todo.
const MAX_ITEMS := 40

static var _WORD: RegEx = RegEx.create_from_string("\\b[A-Z][A-Za-z0-9_]*\\b")


## Las secciones en orden de prioridad: [[título, [líneas]]].
static func sections(context: ProjectContext, path: String, text: String) -> Array:
	var out: Array = []
	var nodes := PackedStringArray()
	for node: Dictionary in context.child_nodes(path):
		if nodes.size() >= MAX_ITEMS:
			break
		var reference := "%" + str(node.name) if node.unique else "$" + str(node.path)
		nodes.append("%s: %s" % [reference, node.type] if not str(node.type).is_empty() else reference)
	out.append(["Nodes in this script's scene", nodes])
	out.append(["Base class", PackedStringArray([context.native_base(text)])])
	var classes := PackedStringArray()
	var global := context.global_classes()
	var seen: Dictionary = {}
	for found: RegExMatch in _WORD.search_all(text):
		var name := found.get_string()
		if seen.has(name) or not global.has(name) or classes.size() >= MAX_ITEMS:
			continue
		seen[name] = true
		var info: Dictionary = global[name]
		var script: Dictionary = context.index.scripts.get(str(info.path), {})
		var line := "%s extends %s" % [name, info.base]
		var funcs: PackedStringArray = script.get("funcs", PackedStringArray())
		if not funcs.is_empty():
			line += "; funcs: " + ", ".join(funcs.slice(0, 12))
		var signals: Dictionary = script.get("signals", {})
		if not signals.is_empty():
			line += "; signals: " + ", ".join(PackedStringArray(signals.keys().slice(0, 8)))
		classes.append(line)
	out.append(["Project classes this file uses", classes])
	var autoloads := PackedStringArray()
	var loads := context.autoloads()
	for name: String in loads:
		autoloads.append("%s (%s)" % [name, loads[name]])
	out.append(["Autoloads", autoloads.slice(0, MAX_ITEMS)])
	var actions := PackedStringArray()
	for action: String in context.input_actions():
		if not action.begins_with("ui_"):
			actions.append(action)
	out.append(["Input map actions", actions.slice(0, MAX_ITEMS)])
	out.append(["Groups", context.groups().slice(0, MAX_ITEMS)])
	return out


## Las secciones como comentarios, cortadas al presupuesto (las primeras tienen prioridad: una
## sección que no entra entera entra hasta donde llega, y las siguientes no).
static func render(context: ProjectContext, path: String, text: String, budget_tokens: int = DEFAULT_BUDGET_TOKENS) -> String:
	var budget := maxi(0, budget_tokens) * CHARS_PER_TOKEN
	# El contexto va como comentarios del lenguaje del archivo (m14-08).
	var comment := "//" if path.get_extension() == "cs" else "#"
	var lines := PackedStringArray()
	var used := 0
	for section: Array in sections(context, path, text):
		var items: PackedStringArray = section[1]
		if items.is_empty():
			continue
		var title := "%s %s:" % [comment, section[0]]
		if used + title.length() + 1 > budget:
			break
		lines.append(title)
		used += title.length() + 1
		for item: String in items:
			if item.strip_edges().is_empty():
				continue
			var line := comment + "   " + item
			if used + line.length() + 1 > budget:
				return "\n".join(lines) + "\n"
			lines.append(line)
			used += line.length() + 1
	return "\n".join(lines) + "\n" if not lines.is_empty() else ""
