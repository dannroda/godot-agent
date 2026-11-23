extends "test_case.gd"
## m11-83: GdscriptOutline arma las declaraciones de un GDScript con sus líneas, y read_function lee
## una función por nombre o por una línea, del disco o del texto sin guardar del Script Editor.

const GdscriptOutline := preload("res://addons/godot_agent/mcp/gdscript_outline.gd")
const CodeTools := preload("res://addons/godot_agent/mcp/tools/code_tools.gd")

const SAMPLE := """extends Node
class_name Sample

signal hit(amount: int)
const SPEED := 10
enum State { IDLE, RUN }
enum { LOOSE }
@export var health: int = 3
@onready var label := $Label
static var count := 0
var callback := func(x: int) -> int:
	var inner_local := x
	return inner_local


## Jumps.
## Twice if asked.
@rpc("any_peer")
func jump(height: float,
		twice: bool = false) -> void:
	var local := height
	var text := \"\"\"
func not_a_function():
\"\"\"
	if twice:
		jump(height)
	# a comment inside

	print(local, \"func fake(): # not code\")


# trailing comment, not part of jump

static func make() -> Sample: return Sample.new()


class Inner extends RefCounted:
	var value := 1

	func jump() -> void:
		value += 1


	class Deeper:
		func jump() -> void:
			pass

	func after_deeper() -> int:
		return value


func last() -> void:
	pass
"""


func _decl(declarations: Array[Dictionary], qualified: String) -> Dictionary:
	for decl: Dictionary in declarations:
		if decl.qualified == qualified:
			return decl
	return {}


func test_outline_declarations() -> void:
	var declarations := GdscriptOutline.parse(SAMPLE)
	var names: PackedStringArray = []
	for decl: Dictionary in declarations:
		names.append("%s %s" % [decl.kind, decl.qualified])
	assert_eq(names, PackedStringArray([
		"class_name Sample", "signal hit", "const SPEED", "enum State", "enum ", "var health", "var label",
		"var count", "var callback", "func jump", "func make", "class Inner", "var Inner.value",
		"func Inner.jump", "class Inner.Deeper", "func Inner.Deeper.jump", "func Inner.after_deeper", "func last",
	]), "declaraciones, sin locales, ni la lambda, ni lo que está dentro de un string")
	assert_true(_decl(declarations, "count").static, "static var")
	assert_true(_decl(declarations, "make").static, "static func")


func test_outline_function_range() -> void:
	var declarations := GdscriptOutline.parse(SAMPLE)
	var lines := SAMPLE.split("\n")
	var jump := _decl(declarations, "jump")
	assert_eq(lines[jump.start - 1], "## Jumps.", "empieza en los comentarios ## de arriba")
	assert_eq(lines[jump.line - 1], "func jump(height: float,", "la línea del func")
	assert_eq(lines[jump.end - 1], "\tprint(local, \"func fake(): # not code\")", "termina en la última línea de código, sin el comentario de afuera")
	var make := _decl(declarations, "make")
	assert_eq(make.end, make.line, "una función de una línea")
	var inner_jump := _decl(declarations, "Inner.jump")
	assert_eq(lines[inner_jump.end - 1], "\t\tvalue += 1", "la función de la clase interna termina antes de la siguiente clase")
	var inner := _decl(declarations, "Inner")
	assert_eq(lines[inner.end - 1], "\t\treturn value", "la clase interna llega hasta su último miembro")


func test_outline_find_and_function_at() -> void:
	var declarations := GdscriptOutline.parse(SAMPLE)
	assert_eq(GdscriptOutline.find_functions(declarations, "jump").size(), 1, "jump: la de arriba, por nombre exacto")
	assert_eq(GdscriptOutline.find_functions(declarations, "Inner.jump").size(), 1, "con la clase, una")
	assert_eq(GdscriptOutline.find_functions(declarations, "nope").size(), 0, "ninguna")
	var jump := _decl(declarations, "jump")
	assert_eq(GdscriptOutline.function_at(declarations, jump.line + 4).qualified, "jump", "una línea del cuerpo")
	assert_eq(GdscriptOutline.function_at(declarations, jump.start).qualified, "jump", "la línea del comentario ##")
	var deeper := _decl(declarations, "Inner.Deeper.jump")
	assert_eq(GdscriptOutline.function_at(declarations, deeper.end).qualified, "Inner.Deeper.jump", "la más interna")
	assert_true(GdscriptOutline.function_at(declarations, 4).is_empty(), "la línea de una señal no es de una función")


func _tools(buffers: Dictionary) -> CodeTools:
	var tools := CodeTools.new()
	tools.unsaved_buffer = func(abs_path: String) -> Variant: return buffers.get(ProjectSettings.localize_path(abs_path))
	return tools


func _call(tools: CodeTools, args: Dictionary) -> Dictionary:
	var tool: RefCounted = tools.tools()[0]
	return tool.handler.call(args)


func _text(result: Dictionary) -> String:
	return str(result.content[0].text)


func test_read_function_by_name_from_unsaved_buffer() -> void:
	var tools := _tools({"res://tests/tmp/sample.gd": SAMPLE})
	var result := _call(tools, {"script": "res://tests/tmp/sample.gd", "name": "jump"})
	assert_false(result.get("isError", false), "no es error")
	var text := _text(result)
	assert_true(text.begins_with("res://tests/tmp/sample.gd · func jump · lines 16-"), "encabezado · %s" % text.left(120))
	assert_true(text.contains("unsaved text"), "dice que es el texto sin guardar")
	assert_true(text.contains("   16  ## Jumps.") and text.contains("@rpc(\"any_peer\")") and text.contains("jump(height)"), "con sus líneas")
	assert_false(text.contains("trailing comment"), "sin el comentario de afuera")


func test_read_function_ambiguous_and_qualified() -> void:
	var tools := _tools({"res://tests/tmp/sample.gd": SAMPLE})
	var top := _text(_call(tools, {"script": "tests/tmp/sample.gd", "name": "jump"}))
	assert_true(top.contains("func jump ·"), "jump: la de arriba, por nombre calificado exacto · %s" % top.left(120))
	var deeper := _text(_call(tools, {"script": "tests/tmp/sample.gd", "name": "Deeper.jump"}))
	assert_true(deeper.contains("func Inner.Deeper.jump") and deeper.contains("pass"), "Deeper.jump por el final del nombre · %s" % deeper.left(160))
	var ambiguous := _call(tools, {"script": "res://tests/tmp/sample.gd", "name": "after"})
	assert_true(ambiguous.get("isError", false) and _text(ambiguous).contains("There is no function"), "por prefijo no")
	var twice := "func a():\n\tpass\nclass X:\n\tfunc go():\n\t\tpass\nclass Y:\n\tfunc go():\n\t\tpass\n"
	var both := _call(_tools({"res://tests/tmp/twice.gd": twice}), {"script": "res://tests/tmp/twice.gd", "name": "go"})
	assert_true(both.get("isError", false) and _text(both).contains("2 functions") and _text(both).contains("X.go (line 4)"), "ambigua: lista las dos · %s" % _text(both))
	var inner := _text(_call(tools, {"script": "res://tests/tmp/sample.gd", "name": "Inner.jump"}))
	assert_true(inner.contains("func Inner.jump") and inner.contains("value += 1") and not inner.contains("Deeper"), "Inner.jump · %s" % inner.left(160))


func test_read_function_by_line_and_errors() -> void:
	var tools := _tools({"res://tests/tmp/sample.gd": SAMPLE})
	var by_line := _text(_call(tools, {"script": "res://tests/tmp/sample.gd", "line": 49}))
	assert_true(by_line.contains("func Inner.after_deeper"), "la línea 49 · %s" % by_line.left(120))
	var outside := _call(tools, {"script": "res://tests/tmp/sample.gd", "line": 5})
	assert_true(outside.get("isError", false) and _text(outside).contains("not inside a function") and _text(outside).contains("Inner.after_deeper"), "fuera de una función: lista las que hay")
	var missing := _call(tools, {"script": "res://tests/tmp/sample.gd", "name": "nope"})
	assert_true(missing.get("isError", false) and _text(missing).contains("There is no function"), "no existe")
	var nothing := _call(tools, {"script": "res://tests/tmp/sample.gd"})
	assert_true(nothing.get("isError", false), "sin name ni line")
	var cs := _call(tools, {"script": "res://Player.cs", "name": "Jump"})
	assert_true(cs.get("isError", false) and _text(cs).contains("C#"), "C#")
	var outside_project := _call(tools, {"script": "/etc/passwd.gd", "name": "x"})
	assert_true(outside_project.get("isError", false) and _text(outside_project).contains("outside the project"), "fuera del proyecto")
	var unknown := _call(tools, {"script": "NoSuchClassAnywhere", "name": "x"})
	assert_true(unknown.get("isError", false) and _text(unknown).contains("class_name NoSuchClassAnywhere"), "class_name que no existe · %s" % _text(unknown))
	var dotdot := _call(tools, {"script": "res://../secret.gd", "name": "x"})
	assert_true(dotdot.get("isError", false) and _text(dotdot).contains("outside the project"), "con ..")


func test_read_function_from_disk() -> void:
	var tools := _tools({})
	var text := _text(_call(tools, {"script": "res://tests/unit/test_case.gd", "name": "assert_eq"}))
	assert_true(text.begins_with("res://tests/unit/test_case.gd · func assert_eq") and not text.contains("unsaved"), "del disco · %s" % text.left(120))
	assert_true(text.contains("checks += 1"), "con el cuerpo")


func test_read_function_by_class_name_on_disk() -> void:
	# Fuera del editor y sin la lista global: el class_name se busca en el texto de los .gd del disco.
	var dir := "res://tests/tmp/unit_code_tools"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open(dir + "/fresh.gd", FileAccess.WRITE)
	file.store_string("extends Node\nclass_name UnitCodeToolsFresh\n\nfunc ping() -> int:\n\treturn 1\n")
	file.close()
	var text := _text(_call(_tools({}), {"script": "UnitCodeToolsFresh", "name": "ping"}))
	assert_true(text.begins_with(dir + "/fresh.gd · func ping"), "class_name recién escrito · %s" % text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/fresh.gd"))


func test_read_function_too_long() -> void:
	var source := "func long() -> void:\n" + "\tpass\n".repeat(CodeTools.MAX_LINES + 50) + "\nfunc other() -> void:\n\tpass\n"
	var tools := _tools({"res://tests/tmp/long.gd": source})
	var first := _text(_call(tools, {"script": "res://tests/tmp/long.gd", "name": "long"}))
	assert_true(first.contains("showing 1-%d" % CodeTools.MAX_LINES) and first.contains("from=%d" % (CodeTools.MAX_LINES + 1)), "dice cómo seguir · %s" % first.left(200))
	var rest := _text(_call(tools, {"script": "res://tests/tmp/long.gd", "name": "long", "from": CodeTools.MAX_LINES + 1}))
	assert_false(rest.contains("showing"), "el resto entra · %s" % rest.left(200))
	assert_true(rest.contains("%5d  \tpass" % (CodeTools.MAX_LINES + 51)), "hasta la última línea")
