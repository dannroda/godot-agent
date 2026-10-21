extends CanvasLayer

signal transition_started
signal transition_finished

const MAIN_MENU_PATH: String = "res://tests/completion_eval/project/ui/main_menu.tscn"
const SHOP_PATH: String = "res://tests/completion_eval/project/ui/upgrade_shop.tscn"
const FADE_TIME: float = 0.35

var is_transitioning: bool = false

var _fade_rect: ColorRect


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)


func change_scene(path: String) -> void:
	if is_transitioning:
		return
	is_transitioning = true
	transition_started.emit()
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_TIME)
	await tween.finished
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
	await tween.finished
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	transition_finished.emit()


func go_to_main_menu() -> void:
	change_scene(MAIN_MENU_PATH)


func go_to_shop() -> void:
	change_scene(SHOP_PATH)


func start_level(index: int) -> void:
	GameState.current_level = index
	change_scene(GameState.get_level_path(index))


func restart_level() -> void:
	start_level(GameState.current_level)
