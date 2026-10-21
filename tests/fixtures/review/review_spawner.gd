extends Node2D
## Genera enemigos cada cierto tiempo (revisión de prueba, M5).

signal enemy_spawned(enemy: Node2D)

@export var enemy_scene: PackedScene
@export var interval: float = 1.5:
	set(value):
		interval = value
		_timer.wait_time = value

@onready var _timer: Timer = $SpawnTimer


func _ready() -> void:
	_timer.timeout.connect(_spawn)
	_timer.start()


func _spawn() -> void:
	var enemy := enemy_scene.instantiate() as Node2D
	add_child(enemy)
	enemy_spawned.emit(enemy)
