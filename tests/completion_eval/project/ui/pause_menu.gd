extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var resume_button: Button = %ResumeButton
@onready var restart_button: Button = %RestartButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: SettingsMenu = $SettingsMenu


func _ready() -> void:
	hide()
	resume_button.pressed.connect(_on_resume_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	quit_button.pressed.connect(_on_quit_button_pressed)
	settings_menu.closed.connect(_on_settings_menu_closed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if settings_menu.visible:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	visible = paused
	EventBus.game_paused.emit(paused)
	if paused:
		resume_button.grab_focus()
		AudioService.play_sfx(&"ui_open", 0.0)


func _on_resume_button_pressed() -> void:
	toggle_pause()


func _on_restart_button_pressed() -> void:
	SceneRouter.restart_level()


func _on_settings_button_pressed() -> void:
	panel.hide()
	settings_menu.open()


func _on_settings_menu_closed() -> void:
	panel.show()
	settings_button.grab_focus()


func _on_quit_button_pressed() -> void:
	SaveService.save_game()
	SceneRouter.go_to_main_menu()
