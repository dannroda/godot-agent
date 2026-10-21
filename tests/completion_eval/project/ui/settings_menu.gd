class_name SettingsMenu
extends Control

signal closed

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var fullscreen_check: CheckBox = %FullscreenCheck
@onready var shake_check: CheckBox = %ShakeCheck
@onready var back_button: Button = %BackButton


func _ready() -> void:
	hide()
	master_slider.value_changed.connect(_on_master_slider_value_changed)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_check_toggled)
	shake_check.toggled.connect(_on_shake_check_toggled)
	back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	master_slider.set_value_no_signal(UserSettings.master_volume)
	music_slider.set_value_no_signal(UserSettings.music_volume)
	sfx_slider.set_value_no_signal(UserSettings.sfx_volume)
	fullscreen_check.set_pressed_no_signal(UserSettings.fullscreen)
	shake_check.set_pressed_no_signal(UserSettings.screen_shake)
	show()
	master_slider.grab_focus()


func close() -> void:
	UserSettings.save_settings()
	hide()
	closed.emit()


func _on_master_slider_value_changed(value: float) -> void:
	UserSettings.master_volume = value
	UserSettings.apply()


func _on_music_slider_value_changed(value: float) -> void:
	UserSettings.music_volume = value
	UserSettings.apply()


func _on_sfx_slider_value_changed(value: float) -> void:
	UserSettings.sfx_volume = value
	UserSettings.apply()
	AudioService.play_sfx(&"ui_click", 0.0)


func _on_fullscreen_check_toggled(toggled_on: bool) -> void:
	UserSettings.fullscreen = toggled_on
	UserSettings.apply()


func _on_shake_check_toggled(toggled_on: bool) -> void:
	UserSettings.screen_shake = toggled_on
