extends "test_case.gd"
## Tools de la API del motor (m3-08): class_info y search_api contra el binario que corre el test.

const ApiTools := preload("res://addons/godot_agent/mcp/tools/api_tools.gd")


func _tools() -> ApiTools:
	var tools := ApiTools.new()
	var version := Engine.get_version_info()
	var cache := OS.get_cache_dir().path_join("godot/editor_doc_cache-%d.%d.res" % [version.major, version.minor])
	tools.doc_cache_path = cache if FileAccess.file_exists(cache) else ""
	return tools


func _text(result: Dictionary) -> String:
	return str(result.content[0].text)


func test_class_info_engine_class() -> void:
	var tools := _tools()
	var result: Dictionary = tools._class_info({"class": "Timer"})
	var text := _text(result)
	assert_false(result.isError, "sin error")
	assert_true(text.contains("Timer (extends Node)"), "cabecera")
	assert_true(text.contains("Inherits: Node < Object"), "herencia")
	assert_true(text.contains("start(time_sec: float = -1"), "firma con default")
	assert_true(text.contains("wait_time: float = 1.0"), "propiedad con default")
	assert_true(text.contains("timeout()"), "señal")
	assert_true(text.contains("enum TimerProcessCallback"), "enum")
	assert_false(text.contains("set_wait_time"), "sin setters de propiedades")
	assert_false(text.contains("add_child"), "sin heredados por defecto")
	assert_true(_text(tools._class_info({"class": "Timer", "inherited": true})).contains("add_child("), "heredados con inherited")
	assert_true(_text(tools._class_info({"class": "node"})).begins_with("Node"), "sin distinguir mayúsculas")
	if not tools.doc_cache_path.is_empty():
		assert_true(text.contains("A countdown timer."), "descripción del caché")


func test_member_details() -> void:
	var tools := _tools()
	var text := _text(tools._class_info({"class": "CharacterBody2D", "member": "add_child"}))
	assert_true(text.begins_with("Node.add_child (method, inherited by CharacterBody2D)"), "miembro heredado: " + text.left(80))
	var missing: Dictionary = tools._class_info({"class": "Node", "member": "add_chlid"})
	assert_true(missing.isError and _text(missing).contains("add_child"), "sugiere el parecido")
	if not tools.doc_cache_path.is_empty():
		var detail := _text(tools._class_info({"class": "Node", "member": "_ready"}))
		assert_true(detail.contains("_ready() -> void [virtual]"), "firma virtual")
		assert_false(detail.contains("[method"), "sin BBCode")


func test_builtin_and_global() -> void:
	var tools := _tools()
	if tools.doc_cache_path.is_empty():
		return
	var vector := _text(tools._class_info({"class": "Vector2"}))
	assert_true(vector.contains("move_toward(to: Vector2, delta: float) -> Vector2"), "método de un built-in")
	var global := _text(tools._class_info({"class": "@GlobalScope", "member": "clamp"}))
	assert_true(global.contains("```gdscript") and global.contains("var a = clamp(-10, -1, 5)"), "codeblock en texto plano")


func test_unknown_class_suggests() -> void:
	var result: Dictionary = _tools()._class_info({"class": "KinematicBody2D"})
	assert_true(result.isError, "no existe en 4.x")
	assert_true(_text(result).contains("Similar:"), "sugerencias: " + _text(result))


func test_search() -> void:
	var tools := _tools()
	var text := _text(tools._search_api({"query": "move toward"}))
	assert_true(text.contains("method Vector2.move_toward(") or text.contains("method @GlobalScope.move_toward("), "método por nombre: " + text.left(300))
	var classes := _text(tools._search_api({"query": "raycast", "kind": "class"}))
	assert_true(classes.contains("class RayCast2D"), "clase por nombre")
	assert_false(classes.contains("method "), "filtro por tipo")
	var scoped := _text(tools._search_api({"query": "velocity", "class": "CharacterBody2D"}))
	assert_true(scoped.contains("property CharacterBody2D.velocity: Vector2"), "dentro de una clase: " + scoped.left(300))
	assert_false(scoped.contains("CharacterBody3D"), "solo esa clase y sus ancestros")
	assert_true(_text(tools._search_api({"query": "zzzqqq"})).begins_with("Nothing"), "sin resultados")


func test_plain_bbcode() -> void:
	var plain := ApiTools._plain("Calls [method add_child] on [Node] with [param p] and [code]true[/code].[br][b]Note:[/b] see [member Node.name].")
	assert_eq(plain, "Calls add_child() on Node with p and `true`.\nNote: see Node.name.", "bbcode")


func test_search_index_is_fast() -> void:
	var tools := _tools()
	var started := Time.get_ticks_msec()
	tools._search_api({"query": "tween"})
	var elapsed := Time.get_ticks_msec() - started
	print("search_api: índice en %d ms, %d entradas" % [elapsed, tools._search_index.size()])
	assert_true(elapsed < 3000, "índice en menos de 3 s (%d ms)" % elapsed)
