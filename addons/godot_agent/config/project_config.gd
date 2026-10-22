@tool
extends Resource
## Configuración por proyecto (D5): matriz de permisos y presupuestos de One-shot.
## Vive en res://addons/godot_agent/config/project_config.tres (excluido del export con el addon).

const PATH := "res://addons/godot_agent/config/project_config.tres"

## grupo (String) -> { modo (String) -> "allow" | "ask" | "deny" }. Vacío = defaults de la spec.
@export var permissions: Dictionary = {}
## Segundos que una tool MCP espera la respuesta de la UI en "ask" antes de denegar.
@export_range(10, 3600, 1, "suffix:s") var permission_timeout_s: int = 300
@export_group("One-shot")
@export_range(1, 600, 1, "suffix:min") var budget_minutes: int = 45
@export_range(10000, 20000000, 1000) var budget_tokens: int = 1500000
@export_range(1, 100) var budget_playtests: int = 8
@export var checkpoints_enabled: bool = true
## Repeticiones iguales (check que falla, tool call que falla o cambio repetido) que el One-shot
## toma como loop (D38): la primera vez pide otro enfoque, la segunda pausa.
@export_range(2, 20) var loop_repeats: int = 3
## Criterios de evaluación del juego (D40): id -> {weight, threshold}. Vacío = defaults de
## oneshot/game_criteria.gd.
@export var criteria: Dictionary = {}
@export_group("Herramientas")
## Directorios fuera del proyecto que fs/* puede leer y escribir (rutas absolutas).
@export var extra_fs_roots: PackedStringArray = []
@export_range(1000, 200000, 1000) var max_output_chars: int = 20000
@export_range(256, 4096, 16, "suffix:px") var max_image_side: int = 1280
## Correr el autoload de playtest también en los runs manuales del usuario.
@export var playtest_on_manual_runs: bool = false
@export_group("Completado")
## Completado predictivo en este proyecto (además del on/off global del usuario, spec §16.10).
@export var completion_enabled: bool = true
## Prefijos (relativos a res://) que no entran al corpus de líneas del completado.
@export var completion_exclude: PackedStringArray = ["addons/"]


## Carga el recurso del proyecto o devuelve uno nuevo con los defaults (sin guardarlo).
static func load_or_default() -> Resource:
	if ResourceLoader.exists(PATH):
		var loaded := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded and loaded.get_script() == load("res://addons/godot_agent/config/project_config.gd"):
			return loaded
	return new()


func save_to_project() -> Error:
	return ResourceSaver.save(self, PATH)
