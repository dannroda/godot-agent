extends "test_case.gd"
## m16-25: con debugger, los errores de un game_script al correr los avisa el editor con el motivo
## de la pausa («mensaje (0 - archivo:línea - at function: f)»), sin un Logger registrado.

const ScriptKit := preload("res://addons/godot_agent/playtest/runtime/script_kit.gd")


func test_reported_own_error() -> void:
	var errors := ScriptKit.ScriptErrors.new()
	errors.add_reported("Invalid call. Nonexistent function 'boom' in base 'Nil'. (0 - gdscript://-9223371980701432215.gd:4 - at function: run)")
	assert_eq(errors.lines, PackedStringArray(["Script error at line 4: Invalid call. Nonexistent function 'boom' in base 'Nil'."]), "el del script (el debugger lo llama gdscript://<id>.gd), con su línea")
	assert_true(errors.fatal, "corta la corrida")


func test_reported_game_error() -> void:
	var errors := ScriptKit.ScriptErrors.new()
	errors.add_reported("Division by zero error in operator '/'. (0 - res://player.gd:12 - at function: hit)")
	assert_eq(errors.lines, PackedStringArray(["Script error (res://player.gd:12 in hit): Division by zero error in operator '/'."]), "el del juego, con archivo y función")
	assert_false(errors.fatal, "un error del juego no corta el script")


func test_reported_compile_error() -> void:
	var errors := ScriptKit.ScriptErrors.new()
	errors.add_reported("Parser Error: Expected end of statement after expression, found \"Identifier\" instead. (0 - gdscript://-9223371981976500625.gd:3 - at function:)")
	assert_eq(errors.lines, PackedStringArray(["Script error at line 3: Parser Error: Expected end of statement after expression, found \"Identifier\" instead."]), "al compilar no hay función")


func test_reported_without_stack() -> void:
	var errors := ScriptKit.ScriptErrors.new()
	errors.add_reported("Something odd")
	assert_eq(errors.lines, PackedStringArray(["Script error: Something odd"]), "tal cual")
	assert_true(errors.fatal, "sin pila, cuenta como del script: no espera a vencer")
