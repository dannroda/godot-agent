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


## CodeTools con `buffers` (ruta res:// → texto) como texto sin guardar y como los archivos del
## proyecto que ven find_symbols y find_references.
func _tools(buffers: Dictionary) -> CodeTools:
	var tools := CodeTools.new()
	tools.unsaved_buffer = func(abs_path: String) -> Variant: return buffers.get(ProjectSettings.localize_path(abs_path))
	tools.list_files = func(folder: String, extensions: PackedStringArray) -> PackedStringArray:
		var out: PackedStringArray = []
		for path: String in buffers:
			if path.begins_with(folder) and path.get_extension() in extensions:
				out.append(path)
		return out
	return tools


func _call(tools: CodeTools, args: Dictionary, tool_name: String = "read_function") -> Dictionary:
	for tool: RefCounted in tools.tools():
		if tool.name == tool_name:
			return tool.handler.call(args)
	return {}


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


# --- find_symbols / find_references (m11-82) ----------------------------------------------------

const PLAYER := """class_name Player
extends CharacterBody2D

signal hit(amount: int)
var jump_height := 3.0


func _ready() -> void:
	hit.connect(_on_hit)
	connect("hit", _on_hit)
	call_deferred("jump")


func jump() -> void:
	# jump() in a comment does not count
	velocity.y = -jump_height
	hit.emit(1)
	print("jump twice")


func _on_hit(amount: int) -> void:
	pass
"""
const ENEMY := """extends Node

func attack(target: Player) -> void:
	target.jump()
	target.hit.emit(2)
"""
const LEVEL := """[gd_scene format=3]

[node name="Level" type="Node"]

[node name="Anim" type="AnimationPlayer" parent="."]

[sub_resource type="Animation" id="a"]
tracks/0/keys = {"times": PackedFloat32Array(0), "values": [{"args": [], "method": &"jump"}]}

[connection signal="hit" from="Player" to="." method="_on_hit"]
"""


func _project() -> CodeTools:
	return _tools({
		"res://player.gd": PLAYER,
		"res://enemies/enemy.gd": ENEMY,
		"res://level.tscn": LEVEL,
		"res://addons/other/jumper.gd": "func jump():\n\tpass\n",
	})


func test_find_symbols() -> void:
	var tools := _project()
	var text := _text(_call(tools, {"query": "jump"}, "find_symbols"))
	assert_true(text.begins_with("2 declarations match \"jump\""), "jump y jump_height, sin addons · %s" % text.left(160))
	assert_true(text.find("res://player.gd:14: func jump") < text.find("res://player.gd:5: var jump_height"), "el nombre exacto primero · %s" % text)
	assert_true(text.contains("(without res://addons/)") and not text.contains("jumper.gd"), "sin res://addons/")
	var only_funcs := _text(_call(tools, {"query": "jump", "kind": "func"}, "find_symbols"))
	assert_true(only_funcs.begins_with("1 declarations") and not only_funcs.contains("jump_height"), "kind func · %s" % only_funcs.left(120))
	var in_addons := _text(_call(tools, {"query": "jump", "path": "res://addons"}, "find_symbols"))
	assert_true(in_addons.contains("res://addons/other/jumper.gd:1: func jump"), "con path en addons · %s" % in_addons)
	var class_hit := _text(_call(tools, {"query": "player", "kind": "class_name"}, "find_symbols"))
	assert_true(class_hit.contains("res://player.gd:1: class_name Player"), "class_name sin distinguir mayúsculas · %s" % class_hit)
	var part := _text(_call(tools, {"query": "_hit"}, "find_symbols"))
	assert_true(part.contains("func _on_hit"), "por una parte del nombre · %s" % part)
	var none := _text(_call(tools, {"query": "nothing_here"}, "find_symbols"))
	assert_true(none.begins_with("No declarations"), "ninguna")
	assert_true(_call(tools, {"query": "jump", "kind": "weird"}, "find_symbols").get("isError", false), "kind inválido")
	assert_true(_call(tools, {"query": "jump", "path": "/etc"}, "find_symbols").get("isError", false), "path fuera del proyecto")


func test_find_references_in_code_and_scenes() -> void:
	var tools := _project()
	var text := _text(_call(tools, {"name": "jump"}, "find_references"))
	assert_true(text.contains("res://player.gd:11 [string] \tcall_deferred(\"jump\")") or text.contains("res://player.gd:11 [string] call_deferred(\"jump\")"), "string con el nombre justo · %s" % text)
	assert_true(text.contains("res://player.gd:14 [declaration]"), "la declaración")
	assert_true(text.contains("res://enemies/enemy.gd:4 [call]"), "una llamada en otro script")
	assert_true(text.contains("res://level.tscn:8 [animation method track]"), "un track de método")
	assert_false(text.contains("player.gd:15"), "un comentario no cuenta")
	assert_false(text.contains("player.gd:18"), "\"jump twice\" no es el nombre justo")
	assert_false(text.contains("player.gd:16"), "jump_height es otra palabra")
	assert_false(text.contains("jumper.gd"), "sin res://addons/")
	var hit := _text(_call(tools, {"name": "hit"}, "find_references"))
	assert_true(hit.contains("player.gd:4 [declaration]") and hit.contains("player.gd:9 [connect]") and hit.contains("player.gd:10 [string]") and hit.contains("player.gd:17 [emit]"), "señal: declaración, connect, string y emit · %s" % hit)
	assert_true(hit.contains("enemy.gd:5 [emit]"), "target.hit.emit: emit, aunque sea de otro objeto · %s" % hit)
	assert_true(hit.contains("level.tscn:10 [scene connection (signal)]"), "conexión guardada en la escena")
	var handler := _text(_call(tools, {"name": "Player._on_hit"}, "find_references"))
	assert_true(handler.contains("level.tscn:10 [scene connection (method)]") and handler.contains("player.gd:9 [use]"), "el método de la conexión, con Clase.nombre · %s" % handler)
	var no_scenes := _text(_call(tools, {"name": "jump", "scenes": false}, "find_references"))
	assert_false(no_scenes.contains("level.tscn"), "scenes=false")
	var member := _text(_call(_tools({"res://b.gd": "func f(p):\n\tprint(p.jump_height)\n"}), {"name": "jump_height"}, "find_references"))
	assert_true(member.contains("res://b.gd:2 [member]"), "acceso a un miembro · %s" % member)
	assert_true(_call(tools, {"name": "not valid"}, "find_references").get("isError", false), "name no es un identificador")
	assert_true(_text(_call(tools, {"name": "nowhere"}, "find_references")).begins_with("No references"), "ninguna")


func test_find_references_reads_unsaved_text() -> void:
	var tools := _tools({"res://a.gd": "func go():\n\tgo_further()\n"})
	var text := _text(_call(tools, {"name": "go_further"}, "find_references"))
	assert_true(text.contains("res://a.gd:2 [call]"), "el texto que da unsaved_buffer · %s" % text)
