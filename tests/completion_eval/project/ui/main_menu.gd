extends Control

@export var menu_music: AudioStream

@onready var main_panel: VBoxContainer = %MainPanel
@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel
@onready var settings_menu: SettingsMenu = $SettingsMenu


func _ready() -> void:
	continue_button.visible = SaveService.has_save()
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.1")
	settings_menu.closed.connect(_on_settings_menu_closed)
	if menu_music:
		AudioService.play_music(menu_music)
	if continue_button.visible:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()


func _on_continue_button_pressed() -> void:
	if SaveService.load_game():
		SceneRouter.start_level(GameState.current_level)


func _on_new_game_button_pressed() -> void:
	GameState.reset()
	SaveService.delete_save()
	SceneRouter.start_level(0)


func _on_settings_button_pressed() -> void:
	main_panel.hide()
	settings_menu.open()


func _on_settings_menu_closed() -> void:
	main_panel.show()
	settings_button.grab_focus()


func _on_quit_button_pressed() -> void:
	get_tree().quit()
