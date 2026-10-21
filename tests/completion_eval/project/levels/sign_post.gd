extends Area2D

@export_multiline var message: String = ""

var _player_inside: bool = false

@onready var prompt: Label = $Prompt
@onready var dialog: PanelContainer = %Dialog
@onready var dialog_label: Label = %DialogLabel


func _ready() -> void:
	prompt.hide()
	dialog.hide()
	dialog_label.text = message
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if _player_inside and event.is_action_pressed("interact"):
		dialog.visible = not dialog.visible
		prompt.visible = not dialog.visible
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		prompt.show()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		prompt.hide()
		dialog.hide()
