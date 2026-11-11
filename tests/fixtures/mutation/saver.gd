extends Node
## m11-41: un juego que guarda un recurso al arrancar. Con un mutante, el SaveGuard del runner tiene
## que negarse y abortar (tests/regressions_cli_check.sh); sin mutante no se corre.

const SPEED := 3


func _ready() -> void:
	ResourceSaver.save(Resource.new(), "res://tests/tmp/mutation_saved.tres")
