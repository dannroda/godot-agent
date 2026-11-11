extends "test_case.gd"
## «Preguntar al agente» desde los menús contextuales (m11-54): lo que deja en el composer.

const AskAgentMenu := preload("res://addons/godot_agent/editor/ask_agent_menu.gd")
const Composer := preload("res://addons/godot_agent/ui/dock/composer.gd")


func test_files_and_nodes_as_mentions() -> void:
	assert_eq(AskAgentMenu.files_text(PackedStringArray(["res://player.gd", "res://levels/"])), "@res://player.gd @res://levels/ ", "archivos y carpetas")
	assert_eq(AskAgentMenu.files_text(PackedStringArray()), "", "nada elegido")
	var root := Node2D.new()
	var body := Node2D.new()
	body.name = "Player"
	root.add_child(body)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	body.add_child(sprite)
	var stray := Node.new()
	assert_eq(AskAgentMenu.nodes_text(root, [root, sprite, stray]), "@. @Player/Sprite ", "relativos a la escena; uno de afuera no")
	assert_eq(AskAgentMenu.nodes_text(null, [sprite]), "", "sin escena abierta")
	stray.free()
	root.free()


func test_code_selection_as_block() -> void:
	var code := CodeEdit.new()
	code.text = "extends Node\n\nfunc _ready() -> void:\n\tpass\n"
	assert_eq(AskAgentMenu.selection_text("res://a.gd", code), "", "sin selección, nada")
	code.select(2, 0, 4, 0)
	assert_eq(AskAgentMenu.selection_text("res://a.gd", code), "@res://a.gd (lines 3-4):\n```gdscript\nfunc _ready() -> void:\n\tpass\n```\n", "hasta el principio de la línea siguiente no la cuenta")
	code.select(0, 0, 0, 7)
	assert_eq(AskAgentMenu.selection_text("res://a.gd", code), "@res://a.gd (line 1):\n```gdscript\nextends\n```\n", "una línea")
	code.text = "x".repeat(AskAgentMenu.SELECTION_MAX_CHARS + 10)
	code.select_all()
	var long := AskAgentMenu.selection_text("res://b.gd", code)
	assert_true(long.contains("[cut at %d characters]" % AskAgentMenu.SELECTION_MAX_CHARS) and long.length() < AskAgentMenu.SELECTION_MAX_CHARS + 100, "cortada · %d" % long.length())
	code.free()


## Se escribe en el caret sin mandar; un bloque en medio de una línea empieza en la línea siguiente.
func test_composer_inserts_at_caret() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer := Composer.new()
	composer.call(&"setup", Color.ORANGE)
	tree.root.add_child(composer)
	await tree.process_frame
	var input: TextEdit = composer.get(&"_input")
	input.text = "look at "
	input.set_caret_column(8)
	composer.insert_at_caret("@res://a.gd ")
	assert_eq(input.text, "look at @res://a.gd ", "mención en el caret")
	composer.insert_at_caret("@res://a.gd (line 1):\n```gdscript\nx\n```\n")
	assert_true(input.text.begins_with("look at @res://a.gd \n@res://a.gd (line 1)"), "el bloque en otra línea · %s" % input.text)
	composer.free()
