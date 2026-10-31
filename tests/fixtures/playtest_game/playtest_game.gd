extends Node3D
## Juego de prueba de M13, con bugs plantados que se disparan a pedido: los detectores tienen que
## encontrarlos y el agente tiene que poder operar su UI y jugarlo. Lo usan run_check y la suite
## tests/playtest_suite.json. Como Orchard Walk de Autopilot.

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


## Una ventana corta: se oculta 0,2 s, menos que un tool call (m15-20).
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
	# Bug plantado: el HUD no corta en el máximo.
	_basket.text = "Basket %d / 10" % basket


## Bug plantado: llama un método sobre null.
func open_mailbox() -> void:
	var letter: Node = get_node_or_null("NoLetter")
	letter.queue_free()


## Bug plantado: la palanca hunde la puerta a través del piso.
func pull_lever() -> void:
	_gate.position.y = -500.0


## Bug plantado: un transform con NaN.
func break_lamp() -> void:
	_lamp.position = Vector3(NAN, 0.0, 0.0)


## Bug plantado: un frame larguísimo.
func stutter() -> void:
	OS.delay_msec(900)


## No es un bug: un breakpoint puesto a propósito (m16-05).
func stop_here() -> void:
	breakpoint


## Bug plantado: el piso desaparece y el jugador cae sin fin.
func drop_floor() -> void:
	_floor.queue_free()
