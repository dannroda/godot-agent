extends "test_case.gd"
## m21-02: los modos `pinned` como botones a la vista y «⋯» con los demás; con poco ancho, el desplegable.

const Composer := preload("res://addons/godot_agent/ui/dock/composer.gd")

const MODES: Array[Dictionary] = [
	{"id": 0, "label": "Ask", "tooltip": "a"},
	{"id": 5, "label": "Plan", "tooltip": "p", "pinned": true},
	{"id": 2, "label": "Build", "tooltip": "b", "pinned": true},
	{"id": 4, "label": "Auto", "tooltip": "u", "pinned": true},
	{"separator": "Project modes"},
	{"id": 100, "label": "Levels (Build)", "tooltip": "l"},
]


func test_pinned_modes_as_buttons_and_the_rest_in_more() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var composer: VBoxContainer = Composer.new()
	composer.call(&"setup", Color.ORANGE)
	composer.custom_minimum_size.x = 900
	tree.root.add_child(composer)
	composer.call(&"set_modes", MODES)
	composer.call(&"set_current_mode", 2)
	for i in 4:
		await tree.process_frame
	var strip: Control = composer.get(&"_mode_strip")
	var dropdown: OptionButton = composer.get(&"_mode_button")
	var more: MenuButton = composer.get(&"_mode_more")
	assert_true(strip.visible and not dropdown.visible, "con ancho, botones en vez del desplegable")
	var buttons: Array = (composer.get(&"_mode_segments") as Node).get_children().filter(func(node: Node) -> bool: return node != more)
	assert_eq(buttons.map(func(button: Button) -> String: return button.text), ["Plan", "Build", "Auto"], "los pinned, en orden")
	assert_eq(more.get_popup().item_count, 3, "«⋯» con Ask, el separador y el modo del proyecto")
	var chosen: Array = []
	composer.connect(&"mode_selected", func(mode: int) -> void: chosen.append(mode))
	(buttons[2] as Button).pressed.emit()
	assert_eq(chosen, [4], "un botón elige su modo")
	assert_eq(dropdown.get_selected_id(), 4, "y el desplegable lo sigue")
	more.get_popup().id_pressed.emit(100)
	assert_eq(chosen, [4, 100], "«⋯» elige los demás")
	assert_eq(more.text, "Levels (Build) ▾", "un modo que no está a la vista se ve en «⋯»")
	composer.set(&"_compact_level", 1)
	composer.call(&"_refresh_mode_strip")
	assert_true(dropdown.visible and not strip.visible, "compactado, vuelve el desplegable")
	composer.queue_free()
	await tree.process_frame
