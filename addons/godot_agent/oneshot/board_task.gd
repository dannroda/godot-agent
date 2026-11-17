@tool
extends RefCounted
## One-shot desde una tarea o un hito del tablero de Scope Compass (m7-56). El objetivo sale de su
## título y su descripción, y el agente lleva el run a la tarea con el MCP scompass: la pasa a doing,
## suma el plan como pasos y los tilda, vincula el spec y al terminar completa test y notas y la pasa
## a review. Lo hace el agente y no el harness: el tablero tiene etags y reglas propias
## (compass/AGENTS.md), y el agente ya las sigue.

const ScopeCompass := preload("../mcp/scope_compass.gd")

## Tope de la descripción en el objetivo: el agente lee la tarea entera con show_task.
const MAX_DESCRIPTION := 4000


## El objetivo del formulario para una tarea o un hito leído con ScopeCompass.read_item.
static func goal_text(item: Dictionary) -> String:
	var title := str(item.get("title", "")).strip_edges()
	var head := ("Milestone %s: %s" if item.get("kind") == "milestone" else "Task %s: %s") % [item.get("id", ""), title]
	var description := str(item.get("description", "")).strip_edges()
	if description.length() > MAX_DESCRIPTION:
		description = description.left(MAX_DESCRIPTION) + "…"
	return head if description.is_empty() else "%s\n\n%s" % [head, description]


## Líneas del prompt inicial del run, después del objetivo. `kind`: "task" o "milestone".
static func prompt_lines(id: String, kind: String, spec_path: String) -> PackedStringArray:
	if id.is_empty():
		return PackedStringArray()
	if kind == "milestone":
		return PackedStringArray([
			"",
			"This run works on milestone %s of the project's Scope Compass board (compass/; its rules are in compass/AGENTS.md). Use the tools of the `scompass` MCP server:" % id,
			"- Before writing the spec, read the milestone with `show_milestone` and its open tasks with `list_tasks` (and `show_task` for each one you take on), and the documents they reference with `show_doc`: they are part of the goal.",
			"- Work through its open tasks: move each one to doing when you start it, add your plan for it as steps (`add_step`) and check them as you finish them (`check_step`); at the end, fill in its `test` and `notes` with `update_task` and move it to review. New work that comes up goes in as a task of the milestone (`add_task`).",
			"- Link the spec (%s) to the tasks you work on with `add_file`." % spec_path,
		])
	return PackedStringArray([
		"",
		"This run works on task %s of the project's Scope Compass board (compass/; its rules are in compass/AGENTS.md). Use the tools of the `scompass` MCP server:" % id,
		"- Before writing the spec, read the task with `show_task` (description, steps, decisions and notes) and the documents it references with `show_doc`: they are part of the goal, and its open decisions are questions you can't ask now, so pick the safest option and note it.",
		"- Move it to doing now. Add your plan as its steps (`add_step`; keep the ones it already has) and check each one when you finish it (`check_step`), so the board shows the progress.",
		"- Link the spec (%s) to the task with `add_file`." % spec_path,
		"- When you finish, fill in `test` (how to check it) and `notes` (what was done, decisions, what is missing) with `update_task` and move it to review. New work that comes up goes in as a new task (`add_task`), and a choice between reasonable alternatives as a decision (`add_decision`).",
	])


## La frase del traspaso al retomar con una sesión nueva.
static func handoff_line(id: String, kind: String) -> String:
	if id.is_empty():
		return ""
	return " The run works on %s %s of the Scope Compass board: read it with `%s` and keep it up to date." % [kind, id, "show_milestone" if kind == "milestone" else "show_task"]
