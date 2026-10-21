extends "test_case.gd"
## Completado (M8a): ProjectContext sobre tests/completion_fixture y cada regla de ContextRules.

const ProjectContext := preload("res://addons/godot_agent/completion/project_context.gd")
const ContextRules := preload("res://addons/godot_agent/completion/local/context_rules.gd")
const CompletionRequest := preload("res://addons/godot_agent/completion/completion_request.gd")

const FIXTURE := "res://tests/completion_fixture"
const PLAYER := FIXTURE + "/actors/player.gd"
const ENEMY := FIXTURE + "/actors/enemy.gd"
const TURRET := FIXTURE + "/actors/turret.gd"
const LEVEL := FIXTURE + "/levels/level.gd"
const HUD := FIXTURE + "/ui/hud.gd"
const BOSS := FIXTURE + "/actors/boss.gd"
const CARET := "|"

var _context: ProjectContext
var _rules := ContextRules.new()


func _ctx() -> ProjectContext:
	if _context == null:
		_context = ProjectContext.new()
		_context.root = FIXTURE
		_context.settings_file = FIXTURE + "/project_settings.cfg"
		_context.build_now()
	return _context


## Pedido sobre el archivo `path` con `line` (que lleva `|` en el caret) agregada al final.
static func request_at(path: String, line: String) -> CompletionRequest:
	var base := FileAccess.get_file_as_string(path)
	var text := base + "\n" + line.replace(CARET, "")
	var lines := text.split("\n")
	return CompletionRequest.make(path, text, lines.size() - 1, line.find(CARET))


func _first(path: String, line: String) -> String:
	var found := _rules.candidates(request_at(path, line), _ctx())
	return str(found[0].text) if not found.is_empty() and not ContextRules.is_veto(found) else "<nada>"


func _all(path: String, line: String) -> PackedStringArray:
	var out := PackedStringArray()
	for candidate: Dictionary in _rules.candidates(request_at(path, line), _ctx()):
		out.append(candidate.text)
	return out


func test_context_index() -> void:
	var context := _ctx()
	assert_true(context.index.scripts.has(PLAYER), "indexa scripts")
	assert_eq(context.signal_params("FixtureHealth", "healed"), null, "señal multilínea: desconocida")
	assert_eq(str(context.index.scripts[PLAYER].class_name), "FixturePlayer", "class_name")
	assert_eq(str(context.index.scripts[TURRET].extends), "FixtureEnemy", "extends de un class_name")
	assert_true(context.index.scenes.has(FIXTURE + "/actors/player.tscn"), "indexa escenas")
	assert_eq(context.native_base(FileAccess.get_file_as_string(TURRET)), "Area2D", "clase nativa siguiendo class_name")
	assert_eq(context.native_base("extends \"res://tests/completion_fixture/actors/player.gd\"\n"), "CharacterBody2D", "extends por ruta")
	assert_eq(context.native_base("var x := 1\n"), "RefCounted", "sin extends: RefCounted")
	assert_eq(context.input_actions(), PackedStringArray(["jump", "move_left", "move_right", "shoot", "ui_cancel"]), "input map: las del proyecto y después las ui_*")
	assert_eq(context.autoloads().get("Events"), FIXTURE + "/events.gd", "autoloads")
	assert_eq(context.handler_style(), "emitter", "el fixture usa _on_<emisor>_<señal> en la mayoría")
	assert_eq(context.groups()[0], "enemies", "grupos: el más usado primero")
	assert_true("spawners" in context.groups(), "grupos de las escenas")
	assert_eq(context.signal_params("FixtureHealth", "changed"), "current: int, maximum: int", "señal de un script del proyecto")
	assert_eq(context.signal_params("FixtureEnemy", "body_entered"), "body: Node2D", "señal heredada de la clase nativa")
	assert_eq(context.signal_params("Timer", "timeout"), "", "señal sin parámetros")
	assert_eq(context.signal_params("Timer", "no_existe"), null, "señal desconocida")
	var level_nodes := context.child_nodes(LEVEL)
	var player: Dictionary = level_nodes.filter(func(n: Dictionary) -> bool: return n.name == "Player")[0]
	assert_eq(player.type, "FixturePlayer", "instancia: tipo del class_name de la raíz instanciada")
	var player_nodes := context.child_nodes(PLAYER)
	var bar: Dictionary = player_nodes.filter(func(n: Dictionary) -> bool: return n.name == "HealthBar")[0]
	assert_true(bar.unique, "nodo único")
	assert_eq(bar.path, "UI/Bars/HealthBar", "ruta del único")
	assert_false(level_nodes.any(func(n: Dictionary) -> bool: return n.name == "HealthBar"), "los únicos de una instancia no son de la escena que la usa")
	var health_virtual: Dictionary = context.virtuals("Node")[0]
	assert_eq(health_virtual, {"name": "_ready", "signature": "_ready() -> void:"}, "virtuales: _ready primero")


func test_onready_rule() -> void:
	assert_eq(_first(PLAYER, "@onready var |"), "collision_shape_2d: CollisionShape2D = $CollisionShape2D", "primer hijo no declarado (Sprite2D ya está)")
	var all := _all(PLAYER, "@onready var |")
	assert_true("hurt_box_collision_shape_2d: CollisionShape2D = $HurtBox/CollisionShape2D" in all, "nombre repetido: antepone el padre")
	assert_true("health: FixtureHealth = $Health" in all, "tipo del class_name del script del nodo")
	assert_true("health_bar: ProgressBar = %HealthBar" in all, "único: %Nombre")
	assert_false(all.has("sprite_2d: Sprite2D = $Sprite2D"), "no repite lo ya declarado")
	assert_eq(_first(PLAYER, "@onready var coo|"), "ldown_timer: Timer = $CooldownTimer", "filtra por lo escrito")
	assert_eq(_first(LEVEL, "@onready var |"), "spawn_point: Marker2D = $\"Spawn Point\"", "ruta con espacios entre comillas; Player ya declarado")
	assert_eq(_first(FIXTURE + "/events.gd", "@onready var |"), "<nada>", "script sin escena: nada")
	assert_eq(_first(HUD, "@onready var |"), "player: FixturePlayer = $Player", "instancia: tipo del class_name")
	assert_eq(_first(HUD, "@onready var sp|"), "rite_2d: Sprite2D = $Player/Sprite2D", "hijo editable de una instancia: tipo de la escena instanciada")
	var boss := _all(BOSS, "@onready var |")
	assert_false("sprite_2d: Sprite2D = $Sprite2D" in boss, "lo que declara el script base (FixturePlayer) no se repite")
	var redefined := _ctx().child_nodes(BOSS).filter(func(n: Dictionary) -> bool: return n.path == "Sprite2D")
	assert_eq(redefined[0].type if not redefined.is_empty() else "", "Sprite2D", "escena heredada: nodo redefinido sin type toma el de la base")
	assert_true("cooldown_timer: Timer = $CooldownTimer" in boss, "escena heredada: nodos de la base")
	assert_false(boss.has("crown: Sprite2D = $Crown"), "lo declarado no se repite")


func test_node_path_rule() -> void:
	assert_eq(_first(PLAYER, "\tvar box := $Hu|"), "rtBox", "$: resto de la ruta")
	assert_eq(_first(PLAYER, "\t$UI/B|"), "ars", "$: rutas anidadas")
	assert_eq(_first(PLAYER, "\t%He|"), "althBar", "%: únicos")
	assert_eq(_first(PLAYER, "\tvar n := $|"), "<nada>", "sin nada escrito y varias opciones: no adivina")
	assert_eq(_first(PLAYER, "\tvar s := \"Vida: %d\" %|"), "<nada>", "% como operador de formato: nada")
	assert_eq(_first(PLAYER, "\tvar r := a %|"), "<nada>", "% como módulo: nada")
	assert_eq(_first(PLAYER, "\tvar bar := %|"), "HealthBar", "% después de = sí (una sola opción)")
	assert_eq(_first(LEVEL, "\t$\"Sp|"), "awn Point\"", "entre comillas")
	assert_eq(_first(LEVEL, "\t$Sp|"), "<nada>", "una ruta con espacios no se sugiere sin comillas")
	assert_eq(_first(PLAYER, "\tprint(\"cuesta $Hu|"), "<nada>", "dentro de un string no")


func test_action_rule() -> void:
	assert_eq(_first(PLAYER, "\tif Input.is_action_pressed(\"j|"), "ump\")", "is_action_*: cierra comillas y paréntesis")
	assert_eq(_first(PLAYER, "\tvar d := Input.get_axis(\"move_left\", \"move_r|"), "ight\"", "get_axis: segunda acción")
	assert_eq(_first(PLAYER, "\tif event.is_action_released(\"|"), "<nada>", "sin nada escrito: no adivina")
	assert_eq(_first(PLAYER, "\tif event.is_action_released(\"ui_ca|"), "ncel\")", "también las ui_* del motor")
	assert_eq(_first(PLAYER, "\tif is_in_group(\"x\") and Input.is_action_pressed(\"sh|"), "oot\")", "grupo antes en la línea no tapa la regla de acciones")
	assert_eq(_first(PLAYER, "\tif InputMap.has_action(\"sh|"), "oot\"", "InputMap")


func test_virtual_rule() -> void:
	assert_eq(_first(PLAYER, "func _|"), "process(delta: float) -> void:", "_ready y _physics_process ya están definidos")
	assert_eq(_first(PLAYER, "func _inp|"), "ut(event: InputEvent) -> void:", "filtra por lo escrito")
	assert_eq(_first(HUD, "func _gui|"), "_input(event: InputEvent) -> void:", "virtuales de Control")
	assert_eq(_first(TURRET, "func _ph|"), "ysics_process(delta: float) -> void:", "base nativa a través de class_name")
	assert_eq(_first(PLAYER, "func _get_configuration_w|"), "arnings() -> PackedStringArray:", "tipo de retorno")


func test_connect_rule() -> void:
	assert_eq(_first(PLAYER, "\t$HurtBox.body_entered.connect(|"), "_on_hurt_box_body_entered)", "estilo del proyecto: _on_<emisor>_<señal>")
	assert_eq(_first(PLAYER, "\ttimer.timeout.connect(|"), "_on_timer_timeout)", "emisor variable")
	assert_eq(_first(PLAYER, "\ttree_exited.connect(|"), "_on_tree_exited)", "sin emisor: _on_<señal>")


func test_handler_rule() -> void:
	var all := _all(PLAYER, "func _on_|")
	assert_eq(all[0], "hurt_box_body_entered(body: Node2D) -> void:", "conexión de escena sin función, con parámetros de la señal")
	assert_true("health_depleted() -> void:" in all, "señal de un script del proyecto")
	assert_false(all.has("cooldown_timer_timeout() -> void:"), "el handler ya definido no se sugiere")
	assert_false(all.has("hurt_box_area_entered(area: Area2D) -> void:"), "conexión con binds: la firma no es la de la señal")
	assert_false(all.has("health_healed() -> void:") or all.has("health_healed(amount: int) -> void:"), "señal partida en varias líneas: firma desconocida, no se sugiere")
	assert_eq(_first(ENEMY, "func _on_b|"), "ody_entered(body: Node2D) -> void:", "connect en código hacia self")


func test_group_rule() -> void:
	assert_eq(_first(PLAYER, "\tadd_to_group(\"|"), "<nada>", "sin nada escrito: no adivina")
	assert_eq(_first(PLAYER, "\tadd_to_group(\"e|"), "nemies\"", "el grupo más usado")
	assert_eq(_first(PLAYER, "\tif body.is_in_group(\"pl|"), "ayers\"", "filtra")
	assert_eq(_first(PLAYER, "\tget_tree().call_group(\"sp|"), "awners\"", "grupos de escenas")


func test_load_rule() -> void:
	assert_eq(_first(PLAYER, "var tex: Texture2D = preload(\"res://tests/completion_fixture/art/p|"), "layer.png\")", "ruta filtrada por lo escrito")
	assert_eq(_first(PLAYER, "var level: PackedScene = load(\"res://tests/completion_fixture/levels/l|"), "evel.tscn\")", "filtra por el tipo del lado izquierdo")
	assert_eq(_first(PLAYER, "var sfx: AudioStream = preload(\"res://|"), "tests/completion_fixture/sounds/jump.wav\")", "una sola opción del tipo: se sugiere sin nada escrito")
	assert_eq(_first(PLAYER, "var x = preload(\"|"), "<nada>", "sin nada escrito y muchas opciones: nada")
	assert_eq(_first(PLAYER, "var x = preload(\"res://tests/completion_fixture/RE|"), "<nada>", "no sugiere archivos que no son recursos (README.md)")


func test_extends_rule() -> void:
	assert_eq(_first(HUD, "extends Fix|"), "tureEnemy", "class_name del proyecto primero")
	assert_eq(_first(HUD, "extends CharacterB|"), "ody2D", "clases del motor")
	assert_eq(_first(HUD, "extends Nod|"), "e", "las comunes primero")
	assert_eq(_first(HUD, "extends |"), "<nada>", "sin letras: nada")
