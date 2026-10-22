@tool
extends Resource
## Configuración por proyecto (D5): matriz de permisos y presupuestos de One-shot.
## Vive en res://addons/godot_agent/config/project_config.tres (excluido del export con el addon).

const PATH := "res://addons/godot_agent/config/project_config.tres"
const ShellRules := preload("../session/shell_rules.gd")

## grupo (String) -> { modo (String) -> "allow" | "ask" | "deny" }. Vacío = defaults de la spec.
@export var permissions: Dictionary = {}
## Segundos que una tool MCP espera la respuesta de la UI en "ask" antes de denegar.
@export_range(10, 3600, 1, "suffix:s") var permission_timeout_s: int = 300
## Modo Auto (D57): reglas de shell `{pattern, list: "allow"|"ask", origin, added}`.
@export var auto_shell_rules: Array = ShellRules.default_rules()
@export_group("One-shot")
@export_range(1, 600, 1, "suffix:min") var budget_minutes: int = 45
@export_range(10000, 20000000, 1000) var budget_tokens: int = 1500000
@export_range(1, 100) var budget_playtests: int = 8
@export var checkpoints_enabled: bool = true
## Default del formulario: el agente escribe el spec y espera «Aprobar spec» antes de construir (D41).
@export var spec_review: bool = false
## Repeticiones iguales (check que falla, tool call que falla o cambio repetido) que el One-shot
## toma como loop (D38): la primera vez pide otro enfoque, la segunda pausa.
@export_range(2, 20) var loop_repeats: int = 3
## Vueltas de QA del One-shot (D55): cuántas veces evalúa un agente aparte, con una vuelta de
## corrección entre una y otra. 0 = sin evaluador (valen los checks que reporta el agente).
@export_range(0, 5) var qa_rounds: int = 2
## Criterios de evaluación del juego (D40): id -> {weight, threshold}. Vacío = defaults de
## oneshot/game_criteria.gd.
@export var criteria: Dictionary = {}
@export_group("Tools")
## Directorios fuera del proyecto que fs/* puede leer y escribir (rutas absolutas).
@export var extra_fs_roots: PackedStringArray = []
@export_range(1000, 200000, 1000) var max_output_chars: int = 20000
@export_range(256, 4096, 16, "suffix:px") var max_image_side: int = 1280
## Correr el autoload de playtest también en los runs manuales del usuario.
@export var playtest_on_manual_runs: bool = false
## tools/list compacto (D56): el núcleo tipado más godot.methods y godot.run para el resto, para
## que las descripciones de ~55 tools no ocupen contexto en cada turno. Vale desde la próxima sesión.
@export var compact_tools: bool = true
@export_group("Completion")
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
