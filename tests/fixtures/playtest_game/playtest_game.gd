extends Node3D
## Un nivel de prueba chico.

var basket: int = 0
var ticks: int = 0
var last_text: String = ""
var start_presses: int = 0

@onready var _lamp: Node3D = $Lamp
@onready var _gate: Node3D = $Gate
@onready var _floor: Node3D = $Floor
@onready var _basket: Label = $HUD/Basket
@onready var _flash: Label = $HUD/Flash
@onready var _name: LineEdit = $HUD/Menu/Name


func _ready() -> void:
	$HUD/Menu/Start.pressed.connect(func() -> void: start_presses += 1)
	$HUD/Menu/Mailbox.pressed.connect(open_mailbox)
	_name.text_changed.connect(func(text: String) -> void: last_text = text)
	_refresh()


func _physics_process(_delta: float) -> void:
	ticks += 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_flash.hide()
		await get_tree().create_timer(0.2, true).timeout
		_flash.show()


func collect(amount: int) -> int:
	basket += amount
	_refresh()
	return basket


func _refresh() -> void:
	_basket.text = "Basket %d / 10" % basket


func open_mailbox() -> void:
	var letter: Node = get_node_or_null("NoLetter")
	letter.queue_free()


func pull_lever() -> void:
	_gate.position.y = -500.0


func break_lamp() -> void:
	_lamp.position = Vector3(NAN, 0.0, 0.0)


func stutter() -> void:
	OS.delay_msec(900)


func stop_here() -> void:
	breakpoint


func drop_floor() -> void:
	_floor.queue_free()
