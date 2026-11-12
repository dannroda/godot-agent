@tool
extends RefCounted
## Comandos de la sesión: conecta el proceso del agente, hace initialize → session/new, manda
## prompts, cancela y cambia opciones. Aplica lo que llega al SessionModel.
## No depende del editor: lo que necesita del editor (contexto, fs, permisos, MCP) se inyecta.

signal connected
signal disconnected
## Terminó la sincronización del modo del agente con el del harness (session/set_mode).
signal agent_mode_synced
## El usuario agregó una regla del modo Auto desde una tarjeta: hay que guardar la config.
signal shell_rules_changed
## El usuario permitió un MCP server de terceros desde una tarjeta, para el modo y el proyecto: hay
## que guardar la matriz de la config (m7-35).
signal permissions_changed
## Un rechazo con algo para el agente (m11-22: el plan editado, «Seguir planeando…», «Denegar con
## motivo»). `text` ya va marcado como prompt del harness: el dock lo pone primero en la cola y lo
## manda al terminar el turno, aunque termine cancelled (el rechazo de ExitPlanMode lo corta).
signal reject_feedback(text: String)

const AgentProcess := preload("../transport/agent_process.gd")
const AddonVersion := preload("../core/addon_version.gd")
const AcpClient := preload("../acp/acp_client.gd")
const SessionModel := preload("session_model.gd")
const PlanStore := preload("plan_store.gd")
const PlanApproval := preload("plan_approval.gd")
const PermissionRequest := preload("permission_request.gd")
const ChatEntry := preload("chat_entry.gd")
const ToolCall := preload("tool_call.gd")
const PlaytestMemory := preload("../review/playtest_memory.gd")
const RunTools := preload("../mcp/tools/run_tools.gd")
const AgentLog := preload("../core/agent_log.gd")
const AgentProfile := preload("../core/agent_profile.gd")
const ModeModels := preload("../core/mode_models.gd")
const ProjectModes := preload("../core/project_modes.gd")
const PermissionPolicy := preload("permission_policy.gd")
const PermissionBroker := preload("permission_broker.gd")
const CsharpBuild := preload("../core/csharp_build.gd")
const NativeBuild := preload("../core/native_build.gd")
const UsageQuery := preload("usage_query.gd")
const SessionCatalog := preload("session_catalog.gd")
const ElicitationRequest := preload("elicitation_request.gd")
const FsHandler := preload("../acp/fs_handler.gd")
const TerminalHandler := preload("../acp/terminal_handler.gd")
const QuotaMonitor := preload("../core/quota_monitor.gd")
const ReviewStore := preload("../review/review_store.gd")
const TurnChecks := preload("../core/turn_checks.gd")
const MachineApproval := preload("../core/machine_approval.gd")
const UntrustedText := preload("../mcp/untrusted_text.gd")
const PathRules := preload("../core/path_rules.gd")
const SessionCoordinator := preload("session_coordinator.gd")
const SessionHistory := preload("session_history.gd")
const AgentLogin := preload("agent_login.gd")
const EditorBinary := preload("../transport/editor_binary.gd")
const CommandResolver := preload("../transport/command_resolver.gd")
const AgentAdapters := preload("agents/agent_adapters.gd")
const AgentAdapter := preload("agents/agent_adapter.gd")
const ClaudeCli := preload("../extensions/claude_cli.gd")
const TurnSnapshots := preload("turn_snapshots.gd")
const TurnReport := preload("turn_report.gd")
const I18n := preload("../core/i18n.gd")
const HarnessPrompts := preload("harness_prompts.gd")

## Turnos seguidos que la verificación al terminar un turno manda para corregir errores (m11-04).
const MAX_FIX_TURNS := 2
## Lo que se espera a que el agente confirme un session/cancel antes de cerrar el turno acá (m17-16).
const CANCEL_TIMEOUT_SEC := 8.0
const PROTOCOL_VERSION := 1
const CLIENT_NAME := "godot-agent-harness"
const CLIENT_TITLE := "Godot Agent Harness"
const SYSTEM_PROMPT_PATH := "res://addons/godot_agent/config/system_prompt.md"
## Guía de Godot por línea de comandos (m14-06): el prompt da su ruta; las sesiones en una copia la
## reciben entera.
const HEADLESS_GUIDE_PATH := "res://addons/godot_agent/config/godot_headless.md"
## Reglas de C# para el prompt, solo si el proyecto tiene un .csproj (m14-07).
const CSHARP_RULES := """
C# in this project (it has a .csproj):
- A script is `public partial class <Name> : <NodeType>` in a file with the same name (`Player.cs` holds `Player`). `godot.attach_script` and `godot.create_scene` create .cs scripts like that.
- Exported values: `[Export] public float Speed = 300.0f;`. Signals: `[Signal] public delegate void HitEventHandler(int damage);`, emitted with `EmitSignal(SignalName.Hit, 5)`.
- Godot's API is PascalCase in C#: `MoveAndSlide()`, `GetNode<Label>("HUD/Score")`, `Input.GetVector(…)`, `GD.Print(…)`.
- After changing C#, run `godot.validate_scripts`: it compiles with dotnet build and returns the errors by file and line. The game runs the new code only after a build."""

const NATIVE_RULES := """
GDExtension in this project (it has a SConstruct, CMakeLists.txt or Cargo.toml):
- Build with `godot.build_extension`: it runs SCons, CMake or Cargo and returns the compiler errors by file and line.
- Test every build with `godot.test_extension`: it runs the extension's tests in a separate headless Godot, so a crash kills only that process, and returns the backtrace.
- Never load a new build into this editor: a crash in the extension takes the editor, and you, down with it, and the editor keeps the library it started with. After the tests pass, load the new build with `godot.restart_editor`: under the crash supervisor, a build that crashes the editor while starting is rolled back, and your session continues with the backtrace.
- When the game uses the extension as an addon (res://addons/<name>/) and it is tested in its own project (project/, demo/), bring it over with `godot.install_extension`, not by copying files: it installs only a build whose tests pass, fixes the res:// paths and stages the files for `godot.restart_editor`."""

## Acciones que ofrecen los avisos de error (spec §15).
const ACTION_RETRY := "retry"
## Reproducir la filmación de un playtest (m15-23); `data`: su carpeta.
const ACTION_PLAY_FILM := "play_film"
## Aviso de lo que cambió un turno (m11-01, m11-02): ver los cambios y volver atrás. Su `data` es
## `{session, start, end, files}`; lo resuelve el plugin.
const ACTION_TURN_CHANGES := "turn_changes"
const ACTION_TURN_RESTORE := "turn_restore"
## Guardar el reporte del turno (m11-06), con la misma `data`.
const ACTION_TURN_REPORT := "turn_report"
const ACTION_SHOW_LOG := "show_log"
## Reinicia el agente y retoma la misma sesión (el agente no respondió a una cancelación, m17-16).
const ACTION_RESTART_AGENT := "restart_agent"
## Errores al lanzar el agente (m12-13): abrir Ajustes › Agentes, o el registro de ACP para
## reinstalar un agente que vino de ahí.
const ACTION_EDIT_AGENT := "edit_agent"
const ACTION_REINSTALL_AGENT := "reinstall_agent"
## Líneas de stderr del agente que muestra el aviso de error.
const STDERR_TAIL := 8
## Largo máximo de cada una en la tarjeta (m13-22): claude-agent-acp vuelca por stderr el prompt
## entero, con el prompt de sistema en JSON, y tapaba la causa. El resto queda en el Agent Log.
## La cola se guarda ya sin los secretos del log (_on_stderr).
const STDERR_LINE_CHARS := 160
## Login con un método de auth del agente (payload: id del método), pegar el código que da la
## página de login y cancelarlo.
const ACTION_LOGIN := "login"
## Las regresiones desde el aviso de un playtest que pasó (m12-48); el dock las reenvía al plugin
## (AgentDock usa estos mismos ids).
const ACTION_RUN_REGRESSIONS := "run_regressions"
## «Verificar el resto» en el aviso final de los criterios de un plan (m11-23): data = los criterios.
const ACTION_VERIFY_REST := "verify_rest_criteria"
## Criterios de un plan que juega una corrida si Settings no dice otra cosa, y sus reintentos.
const DEFAULT_CRITERIA_MAX := 6
const CRITERIA_RETRIES := 2
## «Aprobar…» de lo que trae el proyecto y no está aprobado en esta máquina: un check del fin de
## turno (m11-31) o un MCP server del proyecto (m13-31). `data` es MachineApproval.request; el dock
## muestra los comandos y llama approve_on_machine.
const ACTION_APPROVE_ON_MACHINE := "approve_on_machine"
## «Cambiar» en el aviso del modelo de un modo (m11-38): abre el selector del composer.
const ACTION_CHOOSE_MODEL := "choose_model"
## Segunda opinión (m11-28): pedirla ({session, question?, plan?, diff?}), cortarla, abrir la conversación
## del oráculo ({session, session_id}) y mandarle la respuesta al agente de la pestaña (el texto).
const ACTION_SECOND_OPINION := "second_opinion"
const ACTION_SECOND_OPINION_CANCEL := "second_opinion_cancel"
const ACTION_SECOND_OPINION_OPEN := "second_opinion_open"
const ACTION_SEND_SECOND_OPINION := "send_second_opinion"
const ACTION_REGRESSIONS_WORKFLOW := "regressions_workflow"
const ACTION_LOGIN_CODE := "login_code"
const ACTION_LOGIN_CANCEL := "login_cancel"
## Error de ACP cuando el agente necesita que el usuario inicie sesión (`authRequired`). El mismo
## código es el de transporte del AcpClient: se distingue por el mensaje del SDK de ACP.
const AUTH_REQUIRED_CODE := -32000
const AUTH_REQUIRED_MESSAGE := "authentication required"
## Ventana en la que un permiso de edición ya concedido cubre el fs/write_text_file que le sigue
## (el adapter de Claude pide permiso para Edit y después escribe por fs/*).

const MODE_RULES: Dictionary = {
	SessionModel.HarnessMode.ASK: "Only answer questions: do not modify files, scenes or settings, and do not run commands.",
	SessionModel.HarnessMode.REVIEW: "Read-only review: do not modify anything. Report the findings in a ```json block with {\"findings\":[{\"path\",\"line\",\"severity\":\"bug|order|perf|style\",\"title\",\"body\",\"suggestion\"}]} (path relative to the project, line starting at 1). Each block replaces the previous review: include every finding that still applies. Departures from the Godot conventions below are findings too (severity order for structure, style for typing).",
	SessionModel.HarnessMode.BUILD: "You can edit scenes and scripts; the user approves the changes.",
	SessionModel.HarnessMode.AUTO: "You can edit scenes, scripts and project settings and run the game without asking. Shell commands run without asking only if they are on the user's allowlist (read-only ones like ls, grep, git status); any other command waits for the user's approval, so prefer the godot.* and file tools.",
	SessionModel.HarnessMode.ONESHOT: "Work autonomously until the goal is met; verify with run_scene, capture_game_frame and get_errors after each task.",
}
## Modo del agente (si los publica) que corresponde a cada modo del harness.
## Turnos que mandó el harness para planear (m11-58): al terminar, un bloque ```plan del agente se
## vuelve la tarjeta del plan.
const PLAN_TURN_LABELS: Array[String] = [HarnessPrompts.PLAN_REQUEST, HarnessPrompts.PLAN_EDIT, HarnessPrompts.PLAN_KEEP_PLANNING]
const AGENT_MODE_FOR: Dictionary = {
	SessionModel.HarnessMode.ASK: ["plan"],
	SessionModel.HarnessMode.REVIEW: ["plan"],
	SessionModel.HarnessMode.BUILD: ["default"],
	SessionModel.HarnessMode.ONESHOT: ["default"],
	SessionModel.HarnessMode.AUTO: ["default"],
}

## Lo que vio el detector de loops cuando cortó el playtest de este turno ({} si no cortó, m11-49).
var _playtest_loop: Dictionary = {}
var model: SessionModel
var client: AcpClient
## Los permisos de la sesión (m13-05): política, reglas de shell, tarjetas y autorizadores.
var permissions := PermissionBroker.new()
var policy: PermissionPolicy:
	get: return permissions.policy
	set(value): permissions.policy = value
## Reglas de shell del modo Auto (D57): el array de project_config, que se modifica en el lugar.
var shell_rules: Array:
	get: return permissions.shell_rules
	set(value): permissions.shell_rules = value
## MCP servers de terceros que el addon le pasa al agente (m7-34), para avisar en el One-shot.
var external_mcp_names: PackedStringArray = []
## Servers de terceros cuyas tools pidieron permiso: server -> true (ver PermissionBroker).
var seen_mcp_servers: Dictionary:
	get: return permissions.seen_mcp_servers
## Formularios y enlaces (`elicitation/create`) que esperan respuesta: id del request ACP -> ElicitationRequest.
var _elicitations_by_acp_id: Dictionary = {}
var fs: FsHandler
var terminal: TerminalHandler
var _closing_previous := false
## Cuenta que informó el agente con _auth/status_update, y de qué perfil.
var _agent_account: Dictionary = {}
var _agent_account_profile: AgentProfile
var agent_log: AgentLog
## Cuota del plan (spec §10.1): estado, ventanas y límite; la UI y el One-shot la leen de acá.
var quota: QuotaMonitor
## Hallazgos de la última revisión (modo Revisar, spec §9.4).
var review: ReviewStore = ReviewStore.new()
## Historial en disco (M7). null = no se graba (tests).
var history: SessionHistory
## Las sesiones del proyecto en el agente: `session/list`, `close` y `delete` (m13-05).
var sessions := SessionCatalog.new()
## Sesiones que informó el agente con `session/list` para este proyecto (m11-16).
var agent_sessions: Array[Dictionary]:
	get: return sessions.agent_sessions
## `usage` del último session/prompt (tokens del turno: inputTokens, outputTokens, cachedReadTokens…).
var last_turn_usage: Dictionary = {}
## El snapshot del principio del turno en curso ("" sin turno o sin snapshots) y lo que dejó el último
## turno con cambios ({session, start, end, files}): de ahí sale el diff de la segunda opinión (m11-28).
var current_turn_start: String = ""
var last_turn_changes: Dictionary = {}
## Un turno con cambios dejó su resumen en last_turn_changes (las marcas del Script Editor, m11-66).
signal turn_changes_reported(data: Dictionary)
## Directorio de trabajo para session/new (ruta absoluta del proyecto).
var cwd: String = ""
## Callable() -> Array: entradas `mcpServers` para session/new (el server del addon, M3).
var mcp_servers_provider: Callable
## Callable() -> Dictionary: `_meta` de session/new y session/load (m7-36: las skills del proyecto
## van en `claudeCode.options.skills`). {} = sin `_meta`.
var session_meta_provider: Callable
## Callable() -> Dictionary: variables para el prompt de sistema ({project_name}, …).
var prompt_variables_provider: Callable
## Reglas del modo para el prompt de sistema en lugar de las de MODE_RULES ("" = las del modo).
## Las usa el evaluador del One-shot (D55), que corre en modo One-shot pero solo prueba.
var mode_rules_override: String = ""
## Después de un login exitoso: si devuelve true, ya se ocupó de la sesión (el One-shot retoma la
## suya con la cuenta nueva) y no se abre una sesión nueva.
var after_login: Callable
## Con varias sesiones abiertas (m7-44): `(paths: PackedStringArray) -> String`, "" si esta sesión
## puede escribirlas (y quedan suyas en el turno) o el nombre de la sesión que las está editando.
var file_guard: Callable:
	get: return permissions.file_guard
	set(value): permissions.file_guard = value
## Verificación al terminar un turno de Construir o Auto (m11-04): `(since_unix: int) -> String`,
## los errores de los scripts que cambiaron en el turno o "". Se espera con await. Sin asignar, no
## se verifica.
var turn_verifier: Callable
## Checks del proyecto al terminar el turno (m11-31): `() -> {checks: Array, godot: String,
## project: String}` (project: la carpeta del editor, para la clave). Sin asignar, no corren.
var turn_checks_provider: Callable
## La tienda de aprobaciones por máquina (HarnessSettings): `(key) -> bool` y `(key) -> void`.
var is_command_approved: Callable
## Callable(key: String) -> bool: true si el aviso `key` ya se mostró en este proyecto, y lo marca
## (adapter.notice_after_session). Sin él, una vez por controlador.
var notice_seen: Callable
var _notices_shown: Dictionary = {}
var approve_command: Callable
## El modelo de cada modo del harness, por perfil (m11-38). Sin asignar, cambiar de modo no toca el modelo.
var mode_models: ModeModels
## Ya se avisó en esta pestaña que un cambio de modo cambió el modelo (después, solo el log).
var _mode_model_noticed: bool = false
## Valores recordados que el agente ya no ofrece, ya avisados en esta pestaña.
var _missing_models_noticed: Dictionary = {}
## Snapshots por turno de Construir o Auto (m11-01); compartidos por las sesiones, cada una con su
## `session_key`. Sin asignar o sin git, no se guardan.
var snapshots: TurnSnapshots
var session_key: String = ""

var _process: AgentProcess
var _profile: AgentProfile
## Lo propio del agente conectado (cuota, cuenta, `_meta`): sale del perfil al arrancar y del
## `agentInfo` después de initialize (m13-04).
var adapter: AgentAdapter = AgentAdapter.new()
## Últimas líneas de stderr del agente (para el aviso de error, m12-13).
var _stderr_tail: PackedStringArray = []
var _system_prompt_sent: bool = false
## Ya se avisó que el agente trabaja fuera de un turno pedido desde el chat (se rearma con cada prompt).
var _outside_turn_noticed: bool = false
## Turnos seguidos que mandó la verificación para corregir errores (se reinicia con cada prompt del
## usuario); al llegar a MAX_FIX_TURNS solo se avisa.
var _fix_turns: int = 0
var _sending_fix: bool = false
## Corridas de receta armadas (m11-30): el texto del prompt → Recipes.run_spec. Arranca cuando ese
## texto sale (ya o desde la cola del dock), como las etiquetas de label_prompt.
var _recipe_armed: Dictionary = {}
## La corrida en curso: run_spec + {attempts}. Después de cada turno de Construir o Auto corren sus
## checks con los del proyecto; termina cuando pasan, cuando se agotan los reintentos
## (`max_retries` en lugar de MAX_FIX_TURNS) o cuando el usuario manda otro mensaje.
var _recipe_run: Dictionary = {}
## La corrida de una receta con «Planificar primero», hasta «Aprobar y construir».
var _recipe_after_plan: Dictionary = {}
## () -> {on: bool, max: int}: si se verifican jugando los criterios de un plan aprobado y cuántos
## como mucho (m11-23, Settings). Sin provider, sí y DEFAULT_CRITERIA_MAX.
var plan_criteria_settings: Callable
## Dónde se guardan las regresiones de playtest (los tests usan una carpeta temporal).
var regressions_dir: String = ReviewStore.PlaytestRegressions.DIR
## El prompt que falló porque el agente pidió iniciar sesión (m12-49): se vuelve a mandar solo
## después del login, así el primer uso no obliga a escribirlo dos veces. {text, blocks}.
var _prompt_after_login: Dictionary = {}
## Prompts del harness que esperan salir: texto → Array de etiquetas, una por cada vez que se marcó
## (label_prompt, m12-44): el mismo texto encolado dos veces sale dos veces plegado.
var _harness_labels: Dictionary = {}
## Algo que el agente tiene que saber antes de su próximo turno (el usuario volvió archivos atrás).
var _note_for_agent: String = ""
## Reglas por archivo (m11-25): si se aplican, las ya mandadas en esta sesión (file -> hash) y desde qué
## entrada del chat se buscan los archivos que tocó el agente.
## () -> bool: si se aplican (Settings); sin provider, sí.
var path_rules_on: Callable
## () -> PackedStringArray: archivos del editor que acompañan el prompt (el script abierto).
var context_paths_provider: Callable
var _rules_sent: Dictionary = {}
var _rules_scan_from: int = 0
var _connect_generation: int = 0
## Id del session/prompt en vuelo (-1 si no hay): la cancelación sin respuesta lo despierta (m17-16).
var _prompt_request_id: int = -1
var _cancel_generation: int = 0
var _mode_syncs_running: int = 0
## approve_plan pasa el harness a Construir sin session/set_mode: el adapter cambia solo de modo al
## aprobar, y un set_mode con ExitPlanMode pendiente no hace falta (m11-22).
var _skip_mode_sync: bool = false
## La tarjeta de un plan presentado en bloque ```plan, mientras está pendiente (m11-58).
var _block_plan: PermissionRequest
## El último _load_session falló por el agente (sin loadSession o error), no por una cancelación.
var _load_failed: bool = false
var _login: AgentLogin
## Aviso del login en curso (se actualiza con el enlace y el resultado).
var _login_entry: ChatEntry
## El `/usage` o `/status` en curso: sus mensajes no van al chat (m13-05).
var usage_query := UsageQuery.new()
## Request `session/new`, `session/load` o `session/resume` en vuelo (se cancela con `$/cancel_request` si se abre otra).
var _session_request_id: int = 0


func setup(session_model: SessionModel, log_sink: AgentLog, working_dir: String) -> void:
	model = session_model
	agent_log = log_sink
	cwd = working_dir
	model.unexpected_transition.connect(_on_unexpected_transition)
	model.permission_requested.connect(_on_permission_requested)
	client = AcpClient.new()
	client.setup(_send_line, agent_log)
	quota = QuotaMonitor.new()
	quota.setup(agent_log)
	usage_query.setup(client, agent_log)
	sessions.setup(model, client, agent_log)
	client.set_notification_handler("session/update", _on_session_update)
	client.set_notification_handler("_auth/status_update", _on_auth_status_update)
	connected.connect(_query_agent_usage)
	connected.connect(_refresh_agent_sessions)
	permissions.setup(model, client, agent_log, cwd)
	permissions.shell_rules_changed.connect(shell_rules_changed.emit)
	permissions.permissions_changed.connect(permissions_changed.emit)
	permissions.reject_feedback.connect(_on_reject_feedback)  # un método, no un lambda: sin ciclo de referencias
	client.set_request_handler("session/request_permission", permissions.on_request_permission)
	client.set_request_handler("elicitation/create", _on_create_elicitation)
	client.set_notification_handler("elicitation/complete", _on_complete_elicitation)
	client.incoming_cancelled.connect(_on_incoming_cancelled)
	model.harness_mode_changed.connect(_on_harness_mode_changed)
	# Otro modo del proyecto con el mismo base no cambia harness_mode: el system prompt vuelve igual.
	model.project_mode_changed.connect(_on_project_mode_changed)
	model.config_options_changed.connect(_on_config_options_changed)


## fs/read_text_file y fs/write_text_file. Las escrituras pasan por la política (edit_files).
func set_fs_handler(handler: FsHandler) -> void:
	fs = handler
	fs.write_authorizer = permissions.authorize_fs_write
	fs.register(client)


## terminal/* (m11-15). Los comandos pasan por las guardas del proyecto y la política (shell).
func set_terminal_handler(handler: TerminalHandler) -> void:
	terminal = handler
	terminal.command_authorizer = permissions.authorize_terminal_command
	terminal.env_provider = _terminal_base_env
	# Métodos y no lambdas en las señales de lo que es del controller (terminal, model): una lambda
	# lo captura y arma un ciclo que no se libera; en Godot 4.8 terminaba en un double free al salir.
	terminal.output_changed.connect(_on_terminal_output)
	terminal.register(client)

func profile() -> AgentProfile:
	return _profile


func is_connected_to_agent() -> bool:
	return _process != null and _process.is_running() and not model.session_id.is_empty()


## Lanza el agente del perfil y abre una sesión. Devuelve true si quedó lista.
## Con `resume` (un registro de SessionHistory) muestra esa conversación y la reanuda con session/load.
func start(agent_profile: AgentProfile, resume: Dictionary = {}) -> bool:
	stop()
	_connect_generation += 1
	var generation := _connect_generation
	_profile = agent_profile
	adapter = AgentAdapters.for_profile(agent_profile.command, agent_profile.args, agent_profile.id)
	_agent_account = {}  # el proceso nuevo la vuelve a mandar después de initialize
	model.reset()
	model.failure_message = ""
	_stderr_tail.clear()
	for secret: String in AgentProfile.secret_env_values(agent_profile.resolved_env()):
		agent_log.add_secret(secret)  # el agente puede repetirlos (m13-25)
	# La API key exportada en el shell le llega al agente aunque el perfil no la nombre (hereda el
	# entorno del editor, como avisa _warn_api_key): también cuenta como secreto.
	for secret: String in AgentProfile.inherited_secret_values(PackedStringArray([adapter.api_key_variable()])):
		agent_log.add_secret(secret)
	model.set_state(SessionModel.SessionState.STARTING)
	agent_log.add(AgentLog.CH_PROC, "Launching %s: %s" % [agent_profile.display_name, agent_profile.command_line()])

	_process = AgentProcess.new()
	_process.line_received.connect(client.receive_line)
	_process.stderr_received.connect(_on_stderr)
	_process.exited.connect(_on_process_exited.bind(_process))
	var base_path := CommandResolver.child_path_for(CommandResolver.resolve(agent_profile.command))
	var env := EditorBinary.child_env(agent_profile.resolved_env(), base_path)
	if not _process.start(agent_profile.command, agent_profile.args, env):
		var error := _process.last_error()
		_process = null
		_fail_agent(I18n.t("Could not start %s") % _agent_name(),
			I18n.t("The command «%s» didn't run: %s. Check the agent's command in Settings › Agents.") % [agent_profile.command, error],
			"Could not start the agent: %s" % error, [{"id": ACTION_EDIT_AGENT, "label": I18n.t("Edit the agent"), "primary": true}, {"id": ACTION_RETRY, "label": I18n.t("Retry")}])
		return false
	agent_log.add(AgentLog.CH_PROC, "Process started (pid %d)" % _process.pid())

	var init := await client.request("initialize", {
		"protocolVersion": PROTOCOL_VERSION,
		"clientInfo": {"name": CLIENT_NAME, "title": CLIENT_TITLE, "version": AddonVersion.version()},
		"clientCapabilities": client_capabilities(),
	})
	if generation != _connect_generation:
		return false
	if model.has_failed():  # el agente se cayó esperando la respuesta: la tarjeta ya la puso _fail_agent (m13-26)
		return false
	if not init.ok or not init.result is Dictionary:
		_fail_agent(I18n.t("%s didn't start") % _agent_name(),
			I18n.t("It didn't answer the first message (initialize): %s") % init.error_message(),
			"The agent did not respond to initialize: %s" % init.error_message(), _crash_actions())
		return false
	model.apply_initialize(init.result)
	adapter = AgentAdapters.for_session(_profile.command, _profile.args, _profile.id, model.agent_info)
	var protocol := int(init.result.get("protocolVersion", PROTOCOL_VERSION))
	if protocol != PROTOCOL_VERSION:
		agent_log.add(AgentLog.CH_ACP, "The agent uses protocol version %d (the client asked for %d)" % [protocol, PROTOCOL_VERSION])
	if not resume.is_empty():
		return await _load_session(resume, generation)
	return await open_session(generation)


## Reabre una sesión perdida: con session/load si está en el historial y el agente lo soporta;
## si no, abre una nueva.
func reopen(agent_profile: AgentProfile, lost_id: String) -> bool:
	var record: Dictionary = history.load_record(lost_id) if history and not lost_id.is_empty() else {}
	if not record.is_empty():
		_load_failed = false
		if await start(agent_profile, record):
			return true
		if not _load_failed:  # se canceló (stop, nueva sesión, plugin deshabilitado): no relanzar
			return false
	return await start(agent_profile)


## session/new sobre el proceso ya inicializado (también sirve para "Nueva sesión").
func open_session(generation: int = _connect_generation) -> bool:
	return await _open_session(generation, true)


## Nueva sesión sin cerrar la anterior en el agente (el One-shot vuelve a ella con session/load).
func open_session_keeping_previous() -> bool:
	return await _open_session(_connect_generation, false)


func _open_session(generation: int, close_previous: bool) -> bool:
	if _process == null or not _process.is_running():
		return await start(_profile) if _profile else false
	if _closing_previous:  # un segundo «Nueva sesión» mientras se cierra la anterior
		return false
	_cancel_abandoned_requests()
	if terminal:
		terminal.stop_all()
	var previous_id := model.session_id
	# Antes del await del close: así ningún prompt va a la sesión que se cierra.
	if model.state != SessionModel.SessionState.STARTING:
		model.reset()
		model.set_state(SessionModel.SessionState.STARTING)
	if close_previous and not previous_id.is_empty() and model.supports_close_session():
		_closing_previous = true
		await close_session(previous_id)
		_closing_previous = false
		if generation != _connect_generation:
			return false
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	var req_id := client.next_request_id()
	_session_request_id = req_id
	var result := await client.request("session/new", _with_meta({"cwd": cwd, "mcpServers": mcp_servers}))
	if _session_request_id == req_id:
		_session_request_id = 0
	if generation != _connect_generation or result.error.get("code") == AcpClient.ERR_REQUEST_CANCELLED:
		return false
	if model.has_failed():  # el agente se cayó esperando la respuesta: la tarjeta ya la puso _fail_agent (m13-26)
		return false
	if not result.ok or not result.result is Dictionary or not result.result.get("sessionId") is String:
		var detail := result.error_message() if not result.ok else "response without sessionId"
		var login_actions: Array[Dictionary] = []
		var message := I18n.t("Could not open the session: %s") % detail
		if not result.ok and is_auth_required(result.error):
			login_actions = _login_actions()
			if not login_actions.is_empty():
				# Pedir el login no es un error (m12-11): tarjeta neutra, sin código ni «Reintentar».
				agent_log.add(AgentLog.CH_PROC, message)
				_fail(I18n.t("Sign in to %s to continue.") % _agent_name(), login_actions, ChatEntry.NoticeLevel.INFO, false, SessionModel.SessionState.LOGIN_REQUIRED)
				return false
			else:
				message = I18n.t("Could not open the session: %s. The agent asks for authentication: %s") % [detail, _auth_hint()]
		_fail(message, login_actions)
		return false
	model.apply_session(result.result.sessionId, result.result)
	_system_prompt_sent = false
	_reset_path_rules()
	policy.clear_session()
	permissions.reset()
	if history:
		history.begin(model.session_id, _profile.id, _profile.label(), cwd, {}, _profile.account_dir)
	await _sync_mode_model()  # antes del primer prompt (m11-38)
	if generation != _connect_generation:
		return false
	model.set_state(SessionModel.SessionState.READY)
	_notice_after_session()
	_sync_agent_mode()
	_refresh_account()
	connected.emit()
	return true


## Lo que el agente dejó en el proyecto al abrir la sesión (m18-03), una vez por proyecto.
func _notice_after_session() -> void:
	var text := adapter.notice_after_session(cwd)
	if text.is_empty():
		return
	var key := "%s/after_session" % adapter.kind
	var seen: bool = notice_seen.call(key) if notice_seen.is_valid() else _notices_shown.has(key)
	_notices_shown[key] = true
	if not seen:
		model.add_notice(text, ChatEntry.NoticeLevel.WARNING)


## Manda un turno. `extra_blocks` son ContentBlocks de contexto (escena, selección, imagen…).
## En modo Revisar, un bloque `findings` en la respuesta reemplaza la revisión, salvo que
## `collect_findings` sea false (preguntas sobre un hallazgo).
func send_prompt(text: String, extra_blocks: Array = [], collect_findings: bool = true) -> String:
	if usage_query.running:
		await usage_query.done
	if model.state != SessionModel.SessionState.READY:
		return ""
	var turn_started := int(Time.get_unix_time_from_system())
	if not _sending_fix:
		_fix_turns = 0
		_start_or_end_recipe_run(text)
	var blocks: Array = []
	# Un comando (`/remote-control`, `/compact`, una skill) va solo, sin el contexto del harness ni
	# los adjuntos: el agente solo lo reconoce si el prompt empieza con él, y el adapter de Claude
	# intercepta `/remote-control` solo si es el único bloque. El contexto viaja con el próximo prompt.
	var is_command := is_slash_command(text)
	var includes_system_prompt := not _system_prompt_sent and not is_command
	if includes_system_prompt:
		blocks.append({"type": "text", "text": system_prompt()})
		_system_prompt_sent = true
	if is_command:
		blocks.append({"type": "text", "text": text.strip_edges()})
	else:
		if not _note_for_agent.is_empty():
			blocks.append({"type": "text", "text": _note_for_agent})
			_note_for_agent = ""
		blocks.append_array(extra_blocks)
		blocks.append({"type": "text", "text": text})
	var rules_block: Dictionary = {} if is_command else path_rules_block(text, extra_blocks)
	if not rules_block.is_empty():
		blocks.insert(blocks.size() - 1, rules_block)
	var attachments: Array[Dictionary] = []
	for block: Variant in extra_blocks:
		if block is Dictionary:
			attachments.append(block)
	if not rules_block.is_empty():
		attachments.append(rules_block)
	var harness_label := _take_label(text)
	# Otro mensaje con la tarjeta de un plan en bloque pendiente: ya no es lo que se aprueba (m11-58).
	_cancel_block_plan()
	var plan_turn := harness_label in PLAN_TURN_LABELS
	model.add_user_message(text, attachments, harness_label)
	_outside_turn_noticed = false
	if history:
		history.record_prompt(text, harness_label)
	model.set_state(SessionModel.SessionState.PROMPTING)
	var first_new_entry := model.entries().size()
	var turn_start := ""
	if not is_command and snapshots and snapshots.available and model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		turn_start = await snapshots.take(session_key)
	current_turn_start = turn_start
	# Un playtest en Revisar tiene que jugar: en plan el agente no corre nada y se queda esperando que
	# aprueben un plan (m16-03). Lo que no puede hacer lo sigue frenando la matriz de permisos de Revisar.
	var playtest_turn: bool = model.harness_mode == SessionModel.HarnessMode.REVIEW and ReviewStore.is_playtest_prompt(text.strip_edges())
	if playtest_turn:
		# Primero lo que esté en camino: el modo actual todavía no dice a qué modo está pasando.
		while _mode_syncs_running > 0:
			await agent_mode_synced
		_sync_agent_mode(AGENT_MODE_FOR[SessionModel.HarnessMode.BUILD])
	# Si se acaba de cambiar de modo, el turno espera a que el agente esté en el modo que corresponde.
	while _mode_syncs_running > 0:
		await agent_mode_synced
	if model.state != SessionModel.SessionState.PROMPTING:  # cancelado mientras esperaba
		_system_prompt_sent = _system_prompt_sent and not includes_system_prompt
		if model.state == SessionModel.SessionState.CANCELLING:
			model.finish_turn("cancelled")
		_record_turn_end("cancelled")
		return "cancelled"

	var playtest_minutes := ReviewStore.playtest_minutes(text.strip_edges())
	if playtest_minutes > 0:
		RunTools.set_playtest_deadline(Time.get_ticks_msec() + playtest_minutes * 60000)
	_playtest_loop = {}
	if playtest_turn:
		RunTools.set_playtest_loop_handler(_on_playtest_loop)
	_prompt_request_id = client.next_request_id()
	var result := await client.request("session/prompt", {"sessionId": model.session_id, "prompt": blocks})
	_prompt_request_id = -1
	if playtest_minutes > 0:
		RunTools.set_playtest_deadline(0)
	if playtest_turn:
		RunTools.set_playtest_loop_handler(Callable())
	if playtest_turn:
		_sync_agent_mode()
	var turn_text := agent_text_since(first_new_entry)
	if is_command and text.strip_edges().begins_with("/remote-control"):
		_observe_remote_control(turn_text)
	quota.observe_agent_text(turn_text)
	if collect_findings and model.harness_mode == SessionModel.HarnessMode.REVIEW:
		if review.ingest_turn_text(turn_text, cwd):
			_fold_findings(first_new_entry)
	if not _playtest_loop.is_empty():
		# El harness cortó el playtest (m11-49): el veredicto es suyo, con lo que repetía el agente.
		_report_playtest(ReviewStore.loop_playtest(_playtest_loop), turn_text, first_new_entry, text)
		_playtest_loop = {}
	elif turn_text.contains("\"playtest\""):
		var playtest: Dictionary = ReviewStore.FindingsParser.parse(turn_text, cwd).playtest
		if not playtest.is_empty():
			_report_playtest(playtest, turn_text, first_new_entry, text)
	if not result.ok and int(result.error.get("code", 0)) == AcpClient.ERR_REQUEST_CANCELLED:
		# Lo cerró _watch_cancel: el agente no confirmó la cancelación.
		if model.state in [SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]:
			model.finish_turn("cancelled")
		_record_turn_end("cancelled")
		return "cancelled"
	if not result.ok:
		quota.observe_prompt_error(result.error)
		if model.has_failed():
			# El agente se cayó en el turno (m13-24): la tarjeta ya la puso _fail_agent, con la causa y el
			# stderr. El turno termina igual (turn_finished) y la sesión queda en FAILED.
			agent_log.add(AgentLog.CH_ACP, "The turn ended because the session failed: %s" % result.error_message())
			model.finish_turn("error")
		elif model.state in [SessionModel.SessionState.PROMPTING, SessionModel.SessionState.CANCELLING]:
			var login_actions: Array[Dictionary] = []
			if is_auth_required(result.error):
				login_actions = _login_actions()
			if not login_actions.is_empty():
				agent_log.add(AgentLog.CH_PROC, "The turn ended with an error: %s" % result.error_message())
				_prompt_after_login = {"text": text, "blocks": extra_blocks}
				model.add_notice(I18n.t("Sign in to %s to continue: your message is sent again afterwards.") % _agent_name(), ChatEntry.NoticeLevel.INFO, login_actions)
			else:
				agent_log.add(AgentLog.CH_ACP, "The turn ended with an error: %s" % result.error_message())
				model.add_notice(I18n.t("The turn ended with an error: %s") % result.error_message(), ChatEntry.NoticeLevel.ERROR, _error_actions())
			model.finish_turn("error")
		_record_turn_end("error")
		return "error"
	var stop_reason := "end_turn"
	if result.result is Dictionary:
		stop_reason = str(result.result.get("stopReason", stop_reason))
		last_turn_usage = result.result.get("usage", {}) if result.result.get("usage") is Dictionary else {}
	agent_log.add(AgentLog.CH_ACP, "Turn ended: %s" % stop_reason)
	if stop_reason == "end_turn" and quota.matching_line(turn_text).is_empty():
		quota.observe_turn_ok()
	if plan_turn and stop_reason == "end_turn":
		_offer_block_plan(first_new_entry)
	current_turn_start = ""
	model.finish_turn(stop_reason)
	_record_turn_end(stop_reason)
	if not is_command and model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		_report_turn_changes.call_deferred(turn_start, first_new_entry)
	if stop_reason == "end_turn" and not is_command:
		_verify_turn.call_deferred(turn_started)
	if not _recipe_run.is_empty() and _recipe_run.get("playtest_pending", false) and not _sending_fix:
		_after_recipe_playtest.call_deferred()
	_query_agent_usage()
	return stop_reason


## Antigravity (`/usage`) y Codex (`/status`) no mandan la cuota en usage_update: la dice su comando
## local, que no gasta tokens. Se le pide al abrir la sesión y después de cada turno, sin que la
## pregunta ni la respuesta aparezcan en el chat; un prompt del usuario que llega en el medio espera.
func _query_agent_usage() -> void:
	var command := adapter.quota_command(model)
	if command.is_empty() or model.state != SessionModel.SessionState.READY or usage_query.running:
		return
	var text: Variant = await usage_query.run(command, model.session_id, func() -> bool: return _process != null)
	if text is String:
		adapter.read_quota(text, quota, model, _current_model_name())


## Cancela con `$/cancel_request` un `/usage`, `/status` o apertura de sesión que ya no se espera (m11-18).
func _cancel_abandoned_requests() -> void:
	usage_query.cancel_abandoned()
	if _session_request_id > 0:
		var sid := _session_request_id
		_session_request_id = 0
		client.cancel_request(sid)
func _current_model_name() -> String:
	var option := model.model_option()
	var value := str(option.get("currentValue", ""))
	for item: Variant in option.get("options", []):
		if item is Dictionary and str(item.get("value", "")) == value:
			return str(item.get("name", value))
	return value


## Cierra la sesión de la cuenta en el agente (ACP `logout`) y lo detiene: la próxima sesión pide
## login. Las credenciales las borra el agente; el addon no las ve.
func logout() -> bool:
	if not model.supports_logout() or not is_connected_to_agent():
		return false
	var result := await client.request("logout", {})
	if not result.ok:
		model.add_notice(I18n.t("Could not sign out: %s") % result.error_message(), ChatEntry.NoticeLevel.ERROR)
		return false
	agent_log.add(AgentLog.CH_PROC, "Signed out")
	var name := _profile.display_name if _profile else str(model.agent_info.get("title", ""))
	quota.forget_account()
	_agent_account = {}
	model.set_account({})
	stop()
	model.add_notice(I18n.t("Signed out of %s. Start a session to sign in with another account.") % name)
	return true


## Al terminar un turno de Construir o Auto, un aviso con lo que dejó: los archivos que cambió (si
## hay snapshot) con las acciones para verlos y volver atrás (m11-02), y «Guardar reporte» con eso y
## las capturas que tomó (m11-06). Sin cambios ni capturas, nada.
func _report_turn_changes(turn_start: String, first_entry: int = -1) -> void:
	var data := {"session": session_key, "start": turn_start, "end": "", "files": [], "first_entry": first_entry}
	var parts: PackedStringArray = []
	var actions: Array[Dictionary] = []
	if not turn_start.is_empty():
		data.end = await snapshots.take(session_key)
		if not str(data.end).is_empty():
			var changes: Dictionary = await snapshots.diff(turn_start, data.end)
			data.files = changes.files
			if not changes.files.is_empty():
				last_turn_changes = data
				turn_changes_reported.emit(data)
				var names := PackedStringArray(changes.files.slice(0, 4).map(func(file: Dictionary) -> String: return str(file.path).get_file()))
				if changes.files.size() > 4:
					names.append("…")
				var summary := I18n.t("This turn changed 1 file (+%d −%d): %s") % [changes.added, changes.removed, ", ".join(names)] if changes.files.size() == 1 else I18n.t("This turn changed %d files (+%d −%d): %s") % [changes.files.size(), changes.added, changes.removed, ", ".join(names)]
				parts.append(summary)
				actions.append({"id": ACTION_TURN_CHANGES, "label": I18n.t("View changes"), "data": data})
				actions.append({"id": ACTION_TURN_RESTORE, "label": I18n.t("Undo turn"), "data": data, "tooltip": I18n.t("Go back to before this turn")})
				actions.append({"id": ACTION_SECOND_OPINION, "label": I18n.t("Second opinion"), "data": {"session": session_key, "diff": true},
					"tooltip": I18n.t("Another agent (Settings › Agents › Second opinion) reviews this turn's changes, read only and without this conversation.")})
	var captures: int = TurnReport.collect(model, first_entry).images.size() if first_entry >= 0 else 0
	if captures > 0:
		parts.append(I18n.t("%d captures of the game or the editor.") % captures)
	if parts.is_empty():
		return
	if first_entry >= 0:
		actions.append({"id": ACTION_TURN_REPORT, "label": I18n.t("Save report"), "data": data})
	var entry := model.add_notice(" ".join(parts), ChatEntry.NoticeLevel.INFO, actions)
	entry.footer = true
	model.notify_entry_changed(entry)


# --- reglas por archivo (m11-25) -------------------------------------------------------------------

func _reset_path_rules() -> void:
	_rules_sent.clear()
	_rules_scan_from = model.entries().size()


## El bloque de reglas del proyecto para este prompt ({} si no hay): las que coinciden con lo que tocó
## el agente desde el prompt anterior o con lo que trae este (rutas en el texto, archivos adjuntos, el
## script abierto), sin las que el agente ya carga solo ni las ya mandadas en la sesión.
func path_rules_block(text: String, extra_blocks: Array = []) -> Dictionary:
	var from := _rules_scan_from
	_rules_scan_from = model.entries().size()
	if (path_rules_on.is_valid() and not path_rules_on.call()) or cwd.is_empty():
		return {}
	var paths := touched_paths(from)
	var candidates: Array = Array(PathRules.paths_in_text(text))
	for block: Variant in extra_blocks:
		if block is Dictionary and str(block.get("uri", "")) != "":
			candidates.append(str(block.uri))
	if context_paths_provider.is_valid():
		candidates.append_array(Array(context_paths_provider.call()))
	for path: Variant in candidates:
		var relative := PathRules.relative(str(path), cwd)
		if not relative.is_empty() and not relative in paths:
			paths.append(relative)
	if paths.is_empty():
		return {}
	var pending := PathRules.pending(PathRules.load_rules(cwd), paths, adapter.kind, _rules_sent)
	if pending.is_empty():
		return {}
	var built := PathRules.block(pending)
	for rule: Dictionary in built.sent:
		_rules_sent[rule.file] = rule.hash
		agent_log.add(AgentLog.CH_PROC, "Project rule %s sent for %s" % [rule.file, ", ".join(rule.paths)])
	return {"type": "text", "text": built.text}


## Las reglas para los archivos que nombra una tool godot.* de esta sesión, para el final de su resultado
## (en el mismo turno). Quedan como mandadas: el próximo prompt no las repite. "" si no hay.
func path_rules_for_tool(args: Dictionary) -> String:
	if (path_rules_on.is_valid() and not path_rules_on.call()) or cwd.is_empty():
		return ""
	var paths: PackedStringArray = []
	for path: String in SessionCoordinator.paths_in_args(args):
		var relative := PathRules.relative(path, cwd)
		if not relative.is_empty():
			paths.append(relative)
	if paths.is_empty():
		return ""
	var pending := PathRules.pending(PathRules.load_rules(cwd), paths, adapter.kind, _rules_sent)
	if pending.is_empty():
		return ""
	var built := PathRules.block(pending)
	for rule: Dictionary in built.sent:
		_rules_sent[rule.file] = rule.hash
		agent_log.add(AgentLog.CH_PROC, "Project rule %s sent in a tool result for %s" % [rule.file, ", ".join(rule.paths)])
	return built.text


## Los archivos (relativos al proyecto) que tocaron las tools del agente desde la entrada `from`: las
## ubicaciones y diffs de cada tool call, y las rutas de sus argumentos (las tools godot.* reciben res://).
func touched_paths(from: int) -> PackedStringArray:
	var result: PackedStringArray = []
	for call: ToolCall in tool_calls_since(from):
		var found: Array = []
		for location: Variant in call.locations:
			if location is Dictionary:
				found.append(str(location.get("path", "")))
		for item: Variant in call.content:
			if item is Dictionary and item.get("type") == "diff":
				found.append(str(item.get("path", "")))
		if call.raw_input is Dictionary:
			for value: Variant in (call.raw_input as Dictionary).values():
				for single: Variant in (value if value is Array else [value]):
					if single is String:
						found.append(single)
		for path: Variant in found:
			var relative := PathRules.relative(str(path), cwd) if str(path).begins_with("res://") or str(path).begins_with("/") or str(path).begins_with("file://") else ""
			if not relative.is_empty() and not relative in result:
				result.append(relative)
	return result


## Para el próximo prompt: el agente se entera de que el usuario volvió archivos atrás.
func note_for_agent(text: String) -> void:
	_note_for_agent = text if _note_for_agent.is_empty() else _note_for_agent + "\n" + text


## Saca una nota que todavía no salió («Deshacer» de /remember, m11-36).
func drop_note_for_agent(text: String) -> void:
	if text.is_empty():
		return
	_note_for_agent = _note_for_agent.replace("\n" + text, "").replace(text + "\n", "").replace(text, "")


## Después de un turno de Construir o Auto, valida los scripts que cambiaron. Si alguno no parsea,
## se lo devuelve al agente en un turno nuevo (hasta MAX_FIX_TURNS seguidos) o, si no se puede
## (tope, cola del usuario esperando, otro turno en curso), lo deja como aviso en el chat.
func _verify_turn(turn_started: int) -> void:
	if not turn_verifier.is_valid() or not model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		return
	var errors: String = await turn_verifier.call(turn_started)
	if errors.is_empty():
		await _run_turn_checks(turn_started)
		return
	agent_log.add(AgentLog.CH_PROC, "Check after the turn: scripts with errors\n%s" % errors)
	if not _recipe_run.is_empty():
		_recipe_run.attempts = int(_recipe_run.attempts) + 1
	if _fix_turns < _fix_limit() and model.state == SessionModel.SessionState.READY:
		_fix_turns += 1
		model.add_notice(I18n.t("Check after the turn: some scripts don't parse. The agent gets the errors to fix them (%d of %d).") % [_fix_turns, _fix_limit()], ChatEntry.NoticeLevel.WARNING)
		_sending_fix = true
		send_prompt(label_prompt("[Automatic check after your turn] These scripts you changed don't parse. Fix them, then check again with godot.validate_scripts:\n" + errors, _fix_label()))
		_sending_fix = false
	else:
		model.add_notice(I18n.t("Check after the turn: some scripts don't parse.") + "\n" + errors, ChatEntry.NoticeLevel.WARNING)
		_finish_recipe_run(false)


## Los checks del proyecto que tocan este turno (m11-31), y los de la receta en curso (m11-30), en
## orden: un aviso con ✓/✗ por check y, si alguno falló, su salida vuelve al agente con el mismo tope
## que validate_scripts (el de la receta, si hay una corrida). Un comando sin aprobar en esta máquina
## no corre: el aviso ofrece aprobarlo.
func _run_turn_checks(turn_started: int) -> void:
	if not model.harness_mode in [SessionModel.HarnessMode.BUILD, SessionModel.HarnessMode.AUTO]:
		return
	var info: Dictionary = turn_checks_provider.call() if turn_checks_provider.is_valid() else {}
	var checks: Array = TurnChecks.normalize_list(info.get("checks", [])).filter(func(check: Dictionary) -> bool: return check.enabled)
	if checks.is_empty() and _recipe_run.is_empty():
		return
	if not _recipe_run.is_empty() and _recipe_run.get("playtest_pending", false):
		return
	var changed := TurnChecks.changed_since(cwd, turn_started)
	checks = checks.filter(func(check: Dictionary) -> bool: return TurnChecks.applies(check, changed))
	# Los de la receta corren aunque el turno no haya cambiado nada: dicen si el pedido está hecho.
	var recipe_checks: Array = []
	if not _recipe_run.is_empty():
		recipe_checks = TurnChecks.normalize_list(_recipe_run.checks).filter(func(check: Dictionary) -> bool:
			return check.enabled and ((check.paths as PackedStringArray).is_empty() or TurnChecks.applies(check, changed)))
		for check: Dictionary in recipe_checks:
			check.recipe = true
	checks.append_array(recipe_checks)
	if checks.is_empty():
		if not _recipe_run.is_empty():
			_recipe_run.attempts = int(_recipe_run.attempts) + 1
			_recipe_checks_passed()
		return
	var names := PackedStringArray(checks.map(func(check: Dictionary) -> String: return str(check.name)))
	var notice := model.add_notice(I18n.t("Project checks after the turn: running %s…") % ", ".join(names), ChatEntry.NoticeLevel.INFO)
	notice.footer = true
	model.notify_entry_changed(notice)
	# La aprobación es del proyecto (la carpeta del editor), también en una copia aparte.
	var project := str(info.get("project", cwd))
	var results: Array[Dictionary] = []
	for check: Dictionary in checks:
		var key := TurnChecks.approval_key(project, str(check.command))
		if check.kind == TurnChecks.KIND_COMMAND and not (is_command_approved.is_valid() and is_command_approved.call(key)):
			results.append({"name": check.name, "status": TurnChecks.UNAPPROVED, "command": check.command, "key": key, "recipe": check.get("recipe", false)})
			continue
		agent_log.add(AgentLog.CH_PROC, "%s check «%s»: running" % ["Recipe" if check.get("recipe", false) else "Project", check.name])
		var result: Dictionary = await TurnChecks.run(check, str(info.get("godot", OS.get_executable_path())), cwd)
		result.recipe = check.get("recipe", false)
		agent_log.add(AgentLog.CH_PROC, "%s check «%s»: %s (code %d)\n%s" % ["Recipe" if result.recipe else "Project", check.name, result.status, result.code, result.output])
		results.append(result)
	var report := turn_checks_report(results, str(_recipe_run.get("title", "")))
	notice.text = report.text
	notice.level = ChatEntry.NoticeLevel.WARNING if report.failed > 0 or report.unapproved > 0 else ChatEntry.NoticeLevel.INFO
	notice.actions.assign(report.actions)
	model.notify_entry_changed(notice)
	if not _recipe_run.is_empty():
		_recipe_run.attempts = int(_recipe_run.attempts) + 1
	if report.failed == 0:
		if not _recipe_run.is_empty():
			var held := results.filter(func(result: Dictionary) -> bool: return result.recipe and result.status == TurnChecks.UNAPPROVED)
			if held.is_empty():
				_recipe_checks_passed()
			else:
				model.add_notice(I18n.t("Recipe «%s»: some of its checks aren't approved on this machine, so the result wasn't checked.") % _recipe_run.title, ChatEntry.NoticeLevel.WARNING)
				_recipe_run = {}
		return
	if _fix_turns < _fix_limit() and model.state == SessionModel.SessionState.READY:
		_fix_turns += 1
		model.add_notice(I18n.t("Project checks failed. The agent gets what they reported to fix it (%d of %d).") % [_fix_turns, _fix_limit()], ChatEntry.NoticeLevel.WARNING)
		_sending_fix = true
		send_prompt(label_prompt(turn_checks_prompt(results), _fix_label()))
		_sending_fix = false
	else:
		_finish_recipe_run(false)


## Los checks de la receta pasaron: si tiene playtests, un agente juega (un turno en Revisar, prompt
## del harness); si no, la corrida terminó bien.
func _recipe_checks_passed() -> void:
	if _recipe_run.has("criteria"):
		_play_next_criterion()
		return
	var playtests: Array = _recipe_run.get("playtests", [])
	if playtests.is_empty() or model.state != SessionModel.SessionState.READY:
		_finish_recipe_run(playtests.is_empty())
		return
	var goals := PackedStringArray(playtests.map(func(p: Dictionary) -> String: return str(p.goal)))
	var minutes := 0
	for playtest: Dictionary in playtests:
		minutes += int(playtest.minutes)
	_recipe_run.playtest_pending = true
	_recipe_run.playtest_verdict = {}
	_recipe_run.mode_back = model.harness_mode
	model.add_notice(I18n.t("Recipe «%s»: checks passed. Now an agent plays the game to check it: %s") % [_recipe_run.title, "; ".join(goals)], ChatEntry.NoticeLevel.INFO)
	agent_log.add(AgentLog.CH_PROC, "Recipe «%s»: playtest started (%s)" % [_recipe_run.title, "; ".join(goals)])
	_sending_fix = true
	send_in_mode(SessionModel.HarnessMode.REVIEW, label_prompt(ReviewStore.playtest_prompt("; ".join(goals), false, minutes, PlaytestMemory.new().brief()), HarnessPrompts.RECIPE_PLAYTEST))
	_sending_fix = false


## El turno del playtest de la receta terminó: con «pass» la corrida terminó bien; con «fail», lo que
## vio el agente vuelve como corrección (en el modo de la receta) mientras queden reintentos; sin
## veredicto o «could not test», la corrida termina con un aviso.
func _after_recipe_playtest() -> void:
	if _recipe_run.is_empty() or not _recipe_run.get("playtest_pending", false):
		return
	_recipe_run.playtest_pending = false
	var verdict: Dictionary = _recipe_run.get("playtest_verdict", {})
	if _recipe_run.has("criteria"):
		_record_criterion(verdict)
		_play_next_criterion()
		return
	var back: SessionModel.HarnessMode = _recipe_run.get("mode_back", SessionModel.HarnessMode.BUILD)
	if model.harness_mode != back:
		model.set_harness_mode(back)
	match str(verdict.get("verdict", "")):
		"pass":
			_finish_recipe_run(true)
		"fail":
			if _fix_turns < _fix_limit() and model.state == SessionModel.SessionState.READY:
				_fix_turns += 1
				model.add_notice(I18n.t("Recipe «%s»: the playtest failed. The agent gets what was seen to fix it (%d of %d).") % [_recipe_run.title, _fix_turns, _fix_limit()], ChatEntry.NoticeLevel.WARNING)
				_sending_fix = true
				send_prompt(label_prompt(recipe_playtest_prompt(verdict), HarnessPrompts.RECIPE_CHECK))
				_sending_fix = false
			else:
				_finish_recipe_run(false)
		_:
			model.add_notice(I18n.t("Recipe «%s»: the playtest couldn't check the result, so the run ends here.") % _recipe_run.title, ChatEntry.NoticeLevel.WARNING)
			agent_log.add(AgentLog.CH_PROC, "Recipe «%s»: run ended, playtest verdict «%s»" % [_recipe_run.title, verdict.get("verdict", "none")])
			_recipe_run = {}


## Lo que recibe el agente cuando el playtest de la receta falla: el resumen, los pasos y lo observado,
## en sobres de texto no confiable (lo escribió otro turno mirando el juego).
static func recipe_playtest_prompt(verdict: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append(str(verdict.get("summary", "")))
	for key: String in ["repro", "evidence"]:
		var items: Variant = verdict.get(key, [])
		if items is Array and not (items as Array).is_empty():
			lines.append("%s:\n- %s" % [key.capitalize(), "\n- ".join(PackedStringArray((items as Array).map(func(i: Variant) -> String: return str(i))))])
	var text := "[Automatic check after your turn] A playtest of what you built failed. Fix what it reports (it plays again after your next turn):\n" + UntrustedText.wrap("\n".join(lines).strip_edges())
	return UntrustedText.seal(text, UntrustedText.new_nonce())


## Cuántos turnos seguidos de corrección manda el harness: los reintentos de la receta en curso o
## MAX_FIX_TURNS.
func _fix_limit() -> int:
	return int(_recipe_run.max_retries) if not _recipe_run.is_empty() else MAX_FIX_TURNS


func _fix_label() -> String:
	if _recipe_run.is_empty():
		return HarnessPrompts.TURN_CHECK
	return HarnessPrompts.PLAN_CRITERIA_FIX if _recipe_run.get("origin") == "plan" else HarnessPrompts.RECIPE_CHECK


## Arma una corrida de receta para cuando salga `text` (el prompt expandido; ver Recipes.run_spec).
func arm_recipe_run(text: String, spec: Dictionary) -> void:
	_recipe_armed[text] = spec


## La corrida de receta en curso ({} si no hay).
func recipe_run() -> Dictionary:
	return _recipe_run


## Arma una corrida que arranca recién con «Aprobar y construir» del plan (receta con «Planificar
## primero»): el pedido del plan sale con /plan.
func arm_recipe_after_plan(spec: Dictionary) -> void:
	_recipe_after_plan = spec.duplicate(true)


func _start_or_end_recipe_run(text: String) -> void:
	# Lo que manda el harness (el pedido del plan, «Aprobar y construir», un playtest) no la corta.
	if not prompt_label(text).is_empty():
		return
	if _recipe_armed.has(text):
		_recipe_run = (_recipe_armed[text] as Dictionary).duplicate(true)
		_recipe_run.attempts = 0
		_recipe_armed.erase(text)
		agent_log.add(AgentLog.CH_PROC, "Recipe «%s»: run started (%d checks, up to %d retries)" % [_recipe_run.title, (_recipe_run.checks as Array).size(), _recipe_run.max_retries])
	elif not _recipe_run.is_empty():
		agent_log.add(AgentLog.CH_PROC, "%s: run ended, the user sent another message" % _run_log_name())
		_end_criteria_card()
		_recipe_run = {}
	if not _recipe_after_plan.is_empty():
		agent_log.add(AgentLog.CH_PROC, "Recipe «%s»: dropped before its plan was approved, the user sent another message" % _recipe_after_plan.title)
		_recipe_after_plan = {}


## «Aprobar y construir» con una receta esperando su plan: la corrida arranca con el turno que construye.
func _start_planned_recipe_run() -> void:
	if _recipe_after_plan.is_empty():
		return
	_recipe_run = _recipe_after_plan
	_recipe_run.attempts = 0
	_recipe_after_plan = {}
	_fix_turns = 0
	agent_log.add(AgentLog.CH_PROC, "Recipe «%s»: plan approved, run started (%d checks, %d playtests, up to %d retries)" % [_recipe_run.title, (_recipe_run.checks as Array).size(), (_recipe_run.get("playtests", []) as Array).size(), _recipe_run.max_retries])


## El aviso final de la corrida: ✓ en N intentos o ✗ después de N. Con criterios de un plan, el
## resumen por criterio.
func _finish_recipe_run(passed: bool) -> void:
	if _recipe_run.is_empty():
		return
	if _recipe_run.has("criteria"):
		_finish_criteria_run()
		return
	var attempts := maxi(1, int(_recipe_run.attempts))
	if passed:
		model.add_notice(I18n.t("Recipe «%s»: checks passed (attempt %d).") % [_recipe_run.title, attempts], ChatEntry.NoticeLevel.INFO)
	else:
		model.add_notice(I18n.t("Recipe «%s»: checks still fail after %d attempts.") % [_recipe_run.title, attempts], ChatEntry.NoticeLevel.WARNING)
	agent_log.add(AgentLog.CH_PROC, "Recipe «%s»: run ended, %s after %d attempts" % [_recipe_run.title, "passed" if passed else "failed", attempts])
	_recipe_run = {}


## La tarjeta de un plan arranca con la casilla de los criterios como dice el setting.
func _on_permission_requested(request: PermissionRequest) -> void:
	if not request.is_plan() or request.verify_criteria != -1:
		return
	var settings := criteria_settings()
	request.verify_criteria = 1 if settings.on else 0
	request.criteria_max = int(settings.max)
	request.changed.emit()


## Si se verifican los criterios de los planes y cuántos por corrida (Settings).
func criteria_settings() -> Dictionary:
	var info: Dictionary = plan_criteria_settings.call() if plan_criteria_settings.is_valid() else {}
	return {"on": bool(info.get("on", true)), "max": maxi(1, int(info.get("max", DEFAULT_CRITERIA_MAX)))}


## Los criterios jugables del plan de una tarjeta, como quedó con «Editar».
static func plan_criteria(request: PermissionRequest) -> PackedStringArray:
	return PlanApproval.criteria(request.edited_plan if not request.edited_plan.is_empty() else request.plan_text)


## Si «Aprobar y construir» en esta tarjeta verifica sus criterios: la casilla, o el setting si no se tocó.
func verifies_criteria(request: PermissionRequest) -> bool:
	if plan_criteria(request).is_empty():
		return false
	return request.verify_criteria == 1 if request.verify_criteria != -1 else bool(criteria_settings().on)


## El plan se aprobó con criterios para verificar (m11-23): la corrida arranca con el turno que
## construye. Con una receta esperando su plan, los criterios se suman a su corrida.
func _start_criteria_run(request: PermissionRequest) -> void:
	if not verifies_criteria(request):
		return
	var plan := request.edited_plan if not request.edited_plan.is_empty() else request.plan_text
	var items := criteria_items(plan_criteria(request), int(criteria_settings().max))
	if _recipe_run.is_empty():
		var title := PlanApproval.plan_title(plan)
		_recipe_run = {"title": title if not title.is_empty() else I18n.t("approved plan"), "slug": "", "origin": "plan",
			"checks": [], "playtests": [], "max_retries": CRITERIA_RETRIES, "attempts": 0}
		_fix_turns = 0
	else:
		# Los playtests de la receta van primero, como un criterio más cada uno.
		var recipe_items: Array = []
		for playtest: Dictionary in _recipe_run.get("playtests", []):
			recipe_items.append(_criterion(str(playtest.name), str(playtest.goal), "pending", int(playtest.minutes)))
		recipe_items.append_array(items)
		items = recipe_items
		_recipe_run.playtests = []
	_recipe_run.criteria = items
	_recipe_run.current = -1
	_recipe_run.card = request
	request.criteria_results = items
	request.changed.emit()
	agent_log.add(AgentLog.CH_PROC, "%s: plan approved, %d criteria to check by playing (up to %d retries)" % [_run_log_name(), items.filter(func(i: Dictionary) -> bool: return i.status == "pending").size(), int(_recipe_run.max_retries)])


## Los criterios como los lleva la corrida: los primeros `limit` para jugar, el resto «skipped».
static func criteria_items(criteria: PackedStringArray, limit: int) -> Array:
	var items: Array = []
	for i: int in criteria.size():
		items.append(_criterion("Criterion %d" % (i + 1), criteria[i], "pending" if i < limit else "skipped"))
	return items


static func _criterion(name: String, goal: String, status: String, minutes: int = 0) -> Dictionary:
	return {"name": name, "goal": goal, "status": status, "minutes": minutes, "summary": "", "evidence": [], "repro": [], "tries": 0}


## El próximo criterio por jugar (pendiente o a volver a probar) en un turno de Revisar; si no queda
## ninguno, termina la vuelta.
func _play_next_criterion() -> void:
	var criteria: Array = _recipe_run.criteria
	var next := -1
	for i: int in criteria.size():
		if criteria[i].status in ["pending", "retest"]:
			next = i
			break
	if next < 0 or model.state != SessionModel.SessionState.READY:
		_end_criteria_round()
		return
	var item: Dictionary = criteria[next]
	var playable := criteria.filter(func(i: Dictionary) -> bool: return i.status != "skipped").size()
	_recipe_run.current = next
	_recipe_run.playtest_pending = true
	_recipe_run.playtest_verdict = {}
	if model.harness_mode != SessionModel.HarnessMode.REVIEW:
		_recipe_run.mode_back = model.harness_mode
	model.add_notice(I18n.t("%s: an agent plays the game to check %s of %d: %s") % [_run_name(), I18n.t(item.name) if not item.name.begins_with("Criterion ") else I18n.t("criterion %d") % (next + 1 - _recipe_criteria_offset()), playable, item.goal], ChatEntry.NoticeLevel.INFO)
	agent_log.add(AgentLog.CH_PROC, "%s: playtest of %s (%s)" % [_run_log_name(), item.name, item.goal])
	_sending_fix = true
	send_in_mode(SessionModel.HarnessMode.REVIEW, label_prompt(ReviewStore.playtest_prompt(criterion_goal(item.goal), false, int(item.minutes), PlaytestMemory.new().brief()), HarnessPrompts.PLAN_CRITERION))
	_sending_fix = false


## Cuántos de los criterios de la corrida son playtests de la receta (van antes de los del plan).
func _recipe_criteria_offset() -> int:
	return (_recipe_run.criteria as Array).filter(func(i: Dictionary) -> bool: return not str(i.name).begins_with("Criterion ")).size()


## El objetivo del playtest de un criterio del plan.
static func criterion_goal(criterion: String) -> String:
	return "check this acceptance criterion of the approved plan: %s" % criterion


## El veredicto del playtest en el criterio que se jugó: pass ✓, fail ✗ (se vuelve a probar después
## de corregirlo), sin veredicto o «could not test» ⊘ (no se reintenta).
func _record_criterion(verdict: Dictionary) -> void:
	var index := int(_recipe_run.get("current", -1))
	_recipe_run.current = -1
	if index < 0 or index >= (_recipe_run.criteria as Array).size():
		return
	var item: Dictionary = _recipe_run.criteria[index]
	item.tries = int(item.tries) + 1
	match str(verdict.get("verdict", "")):
		"pass":
			item.status = "pass"
		"fail":
			item.status = "fail"
		_:
			item.status = "blocked"
	item.summary = str(verdict.get("summary", ""))
	for key: String in ["evidence", "repro"]:
		var values: Variant = verdict.get(key, [])
		item[key] = Array(values).map(func(v: Variant) -> String: return str(v)) if values is Array else []
	agent_log.add(AgentLog.CH_PROC, "%s: %s %s" % [_run_log_name(), item.name, item.status])
	_criteria_changed()


## Se jugaron todos: si alguno falló y quedan reintentos, el agente recibe lo que se vio (en el modo de
## la corrida) y después se vuelven a jugar solo los que fallaron.
func _end_criteria_round() -> void:
	var back: SessionModel.HarnessMode = _recipe_run.get("mode_back", model.harness_mode)
	if model.harness_mode != back:
		model.set_harness_mode(back)
	var failed: Array = (_recipe_run.criteria as Array).filter(func(i: Dictionary) -> bool: return i.status == "fail")
	if failed.is_empty() or not _recipe_run.get("build", true):
		_finish_criteria_run()
		return
	if _fix_turns < _fix_limit() and model.state == SessionModel.SessionState.READY:
		_fix_turns += 1
		for item: Dictionary in failed:
			item.status = "retest"
		_criteria_changed()
		model.add_notice(I18n.t("%s: %d of the criteria failed. The agent gets what was seen to fix them, then they're played again (%d of %d).") % [_run_name(), failed.size(), _fix_turns, _fix_limit()], ChatEntry.NoticeLevel.WARNING)
		_sending_fix = true
		send_prompt(label_prompt(criteria_fix_prompt(failed), HarnessPrompts.PLAN_CRITERIA_FIX))
		_sending_fix = false
	else:
		_finish_criteria_run()


## Lo que recibe el agente cuando fallan criterios: cada uno con lo que vio el playtest, en sobres de
## texto no confiable (lo escribió otro turno mirando el juego).
static func criteria_fix_prompt(failed: Array) -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in failed:
		var lines: PackedStringArray = [str(item.summary)]
		for key: String in ["repro", "evidence"]:
			if not (item[key] as Array).is_empty():
				lines.append("%s:\n- %s" % [key.capitalize(), "\n- ".join(PackedStringArray(item[key]))])
		parts.append("Criterion: %s\nWhat the playtest saw:\n%s" % [item.goal, UntrustedText.wrap("\n".join(lines).strip_edges())])
	var text := "[Automatic check after your turn] Playtests of the approved plan's acceptance criteria failed. Fix what they report; those criteria are played again after your next turn.\n\n" + "\n\n".join(parts)
	return UntrustedText.seal(text, UntrustedText.new_nonce())


## El resumen final «4 ✓ · 1 ✗ · 1 ⊘», una línea por criterio y «Verificar el resto» si quedaron
## criterios sin jugar por el tope.
func _finish_criteria_run() -> void:
	var criteria: Array = _recipe_run.criteria
	var summary := criteria_summary(criteria)
	var lines: PackedStringArray = [I18n.t("%s: acceptance criteria checked by playing: %s") % [_run_name(), summary.text]]
	var offset := _recipe_criteria_offset()
	for i: int in criteria.size():
		var item: Dictionary = criteria[i]
		if item.status == "skipped":
			continue
		var name: String = I18n.t("Criterion %d") % (i + 1 - offset) if str(item.name).begins_with("Criterion ") else I18n.t(item.name)
		lines.append("%s %s: %s" % [criterion_mark(item.status), name, item.goal])
	var actions: Array[Dictionary] = []
	var rest: PackedStringArray = PackedStringArray(criteria.filter(func(i: Dictionary) -> bool: return i.status == "skipped").map(func(i: Dictionary) -> String: return str(i.goal)))
	if not rest.is_empty():
		lines.append(I18n.t("%d more criteria weren't played (the limit per run is in Settings).") % rest.size())
		actions.append({"id": ACTION_VERIFY_REST, "label": I18n.t("Verify the rest (%d)") % rest.size(), "data": rest,
			"tooltip": I18n.t("Plays the criteria that were left out, one playtest each, without changing the game.")})
	model.add_notice("\n".join(lines), ChatEntry.NoticeLevel.INFO if summary.failed == 0 and summary.blocked == 0 else ChatEntry.NoticeLevel.WARNING, actions)
	agent_log.add(AgentLog.CH_PROC, "%s: run ended, %s" % [_run_log_name(), summary.text])
	if PlanStore.append_verification(str(_recipe_run.get("plan_path", "")), criteria, summary.text):
		agent_log.add(AgentLog.CH_PROC, "%s: verification written to %s" % [_run_log_name(), _recipe_run.plan_path])
	_end_criteria_card()
	_recipe_run = {}


## Cuántos pasaron, fallaron y no se pudieron probar: {passed, failed, blocked, skipped, text}.
static func criteria_summary(criteria: Array) -> Dictionary:
	var counts := {"pass": 0, "fail": 0, "blocked": 0, "skipped": 0}
	for item: Dictionary in criteria:
		match str(item.status):
			"pass":
				counts.pass += 1
			"fail", "retest":
				counts.fail += 1
			"skipped":
				counts.skipped += 1
			_:
				counts.blocked += 1
	var parts: PackedStringArray = ["%d ✓" % counts.pass, "%d ✗" % counts.fail]
	if counts.blocked > 0:
		parts.append("%d ⊘" % counts.blocked)
	return {"passed": counts.pass, "failed": counts.fail, "blocked": counts.blocked, "skipped": counts.skipped, "text": " · ".join(parts)}


static func criterion_mark(status: String) -> String:
	match status:
		"pass":
			return "✓"
		"fail", "retest":
			return "✗"
		"skipped":
			return "·"
		"pending":
			return "…"
	return "⊘"


## «Verificar el resto»: juega los criterios que quedaron afuera, sin turno de construir antes y sin
## corregir (lo que falla queda ✗ para que el usuario decida).
func verify_rest(criteria: Variant) -> void:
	var goals := PackedStringArray(criteria) if criteria is Array or criteria is PackedStringArray else PackedStringArray()
	if goals.is_empty() or not _recipe_run.is_empty() or model.state != SessionModel.SessionState.READY:
		return
	_recipe_run = {"title": I18n.t("the rest of the criteria"), "slug": "", "origin": "plan", "checks": [], "playtests": [],
		"max_retries": 0, "attempts": 0, "build": false, "current": -1, "criteria": criteria_items(goals, goals.size())}
	agent_log.add(AgentLog.CH_PROC, "%s: %d criteria to check by playing" % [_run_log_name(), goals.size()])
	_play_next_criterion()


## Cómo se nombra la corrida en los avisos: «Receta «x»» o «Plan «x»».
func _run_name() -> String:
	return (I18n.t("Plan «%s»") if _recipe_run.get("origin") == "plan" else I18n.t("Recipe «%s»")) % str(_recipe_run.get("title", ""))


func _run_log_name() -> String:
	return "%s «%s»" % ["Plan" if _recipe_run.get("origin") == "plan" else "Recipe", _recipe_run.get("title", "")]


## La tarjeta del plan muestra el estado de cada criterio.
func _criteria_changed() -> void:
	var card: Variant = _recipe_run.get("card")
	if card is PermissionRequest:
		(card as PermissionRequest).changed.emit()


## La corrida terminó: los criterios que no llegaron a jugarse quedan como no probados en la tarjeta.
func _end_criteria_card() -> void:
	if not _recipe_run.has("criteria"):
		return
	for item: Dictionary in _recipe_run.criteria:
		if item.status == "pending":
			item.status = "blocked"
	_criteria_changed()


## El aviso de los checks: una línea por check y «Aprobar…» por cada comando sin aprobar.
static func turn_checks_report(results: Array[Dictionary], recipe_title: String = "") -> Dictionary:
	var lines: PackedStringArray = [I18n.t("Project checks after the turn:") if recipe_title.is_empty() else I18n.t("Checks after the turn (recipe «%s»):") % recipe_title]
	var actions: Array[Dictionary] = []
	var failed := 0
	var unapproved := 0
	for result: Dictionary in results:
		match str(result.status):
			TurnChecks.PASSED:
				lines.append("✓ " + str(result.name))
			TurnChecks.SKIPPED:
				lines.append("– %s: %s" % [result.name, I18n.t("nothing to run")])
			TurnChecks.UNAPPROVED:
				unapproved += 1
				lines.append("⊘ %s: %s" % [result.name, I18n.t("not approved on this machine, so it didn't run")])
				actions.append({"id": ACTION_APPROVE_ON_MACHINE, "label": I18n.t("Approve «%s»…") % result.name,
					"data": MachineApproval.request(MachineApproval.KIND_CHECK, [{"name": result.name, "command": result.command, "key": result.key}]),
					"tooltip": I18n.t("The check comes with the project. See the command and allow it to run on this machine.")})
			_:
				failed += 1
				var why := I18n.t("stopped after the time limit") if bool(result.get("timed_out", false)) else I18n.t("exit code %d") % int(result.get("code", -1))
				lines.append("✗ %s (%s)" % [result.name, why])
	return {"text": "\n".join(lines), "actions": actions, "failed": failed, "unapproved": unapproved}


## Lo que recibe el agente cuando fallan checks: el nombre, el código y el final de la salida de cada
## uno, en sobres de texto no confiable (la salida puede traer texto del juego o del agente).
static func turn_checks_prompt(results: Array[Dictionary]) -> String:
	var parts: PackedStringArray = ["[Automatic check after your turn] These project checks failed. Fix what they report, then make sure they pass (they run again after your next turn):"]
	for result: Dictionary in results:
		if str(result.status) != TurnChecks.FAILED:
			continue
		var why := "stopped after the time limit" if bool(result.get("timed_out", false)) else "exit code %d" % int(result.get("code", -1))
		parts.append("\n### %s (%s)\n%s" % [result.name, why, UntrustedText.wrap(str(result.output)) if not str(result.output).is_empty() else "(no output)"])
	return UntrustedText.seal("\n".join(parts), UntrustedText.new_nonce())


## «Aprobar…» confirmado en el dock: un check corre desde el próximo turno; un MCP server, desde la
## próxima sesión (mcpServers va en session/new); una tool del proyecto, desde ya (m11-46).
func approve_on_machine(data: Dictionary) -> void:
	if not approve_command.is_valid():
		return
	var names: PackedStringArray = []
	for item: Dictionary in data.get("items", []):
		if str(item.get("key", "")).is_empty():
			continue
		approve_command.call(str(item.key))
		names.append("«%s»" % item.get("name", ""))
		var what: String = {MachineApproval.KIND_MCP: "MCP server", MachineApproval.KIND_TOOL: "Project tool", MachineApproval.KIND_HOOK: "Project hook"}.get(data.get("kind"), "Project check")
		agent_log.add(AgentLog.CH_PERM, "%s «%s» approved on this machine: %s" % [what, item.get("name", ""), str(item.get("command", "")).get_slice("\n", 0)])
	if names.is_empty():
		return
	if data.get("kind") == MachineApproval.KIND_TOOL:
		model.add_notice(I18n.t("Approved on this machine: %s. The agent can use them now, with godot.run.") % ", ".join(names), ChatEntry.NoticeLevel.INFO)
	elif data.get("kind") == MachineApproval.KIND_HOOK:
		model.add_notice(I18n.t("Approved on this machine: %s. It runs the next time its event happens.") % ", ".join(names), ChatEntry.NoticeLevel.INFO)
	elif data.get("kind") == MachineApproval.KIND_MCP:
		model.add_notice(I18n.t("Approved on this machine: %s. The agent gets them from the next session (a new one, or this one reopened from History).") % ", ".join(names), ChatEntry.NoticeLevel.INFO)
	else:
		model.add_notice(I18n.t("Approved on this machine: %s. It runs after the next turn that changes files.") % ", ".join(names), ChatEntry.NoticeLevel.INFO)


## El aviso de los MCP servers del proyecto que no se pasaron porque no están aprobados (m13-31):
## `held` es `[{name, command, key}]`. La primera vez (`explain`) dice por qué cambió; las
## siguientes, una línea. «Aprobar…» por server y, con más de uno, para todos.
static func held_servers_notice(held: Array, explain: bool) -> Dictionary:
	var names := PackedStringArray(held.map(func(item: Dictionary) -> String: return "«%s»" % item.name))
	var text := I18n.t("Project MCP servers not started: %s. They come with the project's settings (addons/godot_agent/config/project_config.tres), and a project server now only starts on a machine where its command was approved, so a cloned project can't launch programs without asking. The agent doesn't get their tools in this session; approve them and they start with the next session.") % ", ".join(names) if explain \
		else I18n.t("Project MCP servers not approved on this machine, left out: %s.") % ", ".join(names)
	var actions: Array[Dictionary] = []
	for item: Dictionary in held:
		actions.append({"id": ACTION_APPROVE_ON_MACHINE, "label": I18n.t("Approve «%s»…") % item.name, "data": MachineApproval.request(MachineApproval.KIND_MCP, [item]),
			"tooltip": I18n.t("See what the server runs and allow it on this machine.")})
	if held.size() > 1:
		actions.append({"id": ACTION_APPROVE_ON_MACHINE, "label": I18n.t("Approve all (%d)…") % held.size(), "data": MachineApproval.request(MachineApproval.KIND_MCP, held),
			"tooltip": I18n.t("See what each server runs and allow them all on this machine.")})
	return {"text": text, "actions": actions}


## El aviso de las tools del proyecto frenadas (m11-46): `held` es `[{name, command, key}]`, con la
## ruta y el código en `command`. «Aprobar…» por tool y, con más de una, para todas.
static func held_tools_notice(held: Array) -> Dictionary:
	var names := PackedStringArray(held.map(func(item: Dictionary) -> String: return "«%s»" % item.name))
	var text := I18n.t("Project tools not approved on this machine: %s. They are GDScript in the project that runs inside the editor when the agent calls it, so each one only loads where someone approved its code; if the code changes (also when the agent writes it), it asks again. Until then the agent can't call them.") % ", ".join(names)
	var actions: Array[Dictionary] = []
	for item: Dictionary in held:
		actions.append({"id": ACTION_APPROVE_ON_MACHINE, "label": I18n.t("Approve «%s»…") % item.name, "data": MachineApproval.request(MachineApproval.KIND_TOOL, [item]),
			"tooltip": I18n.t("See the tool's code and allow it on this machine.")})
	if held.size() > 1:
		actions.append({"id": ACTION_APPROVE_ON_MACHINE, "label": I18n.t("Approve all the tools (%d)…") % held.size(), "data": MachineApproval.request(MachineApproval.KIND_TOOL, held),
			"tooltip": I18n.t("See the code of each tool and allow them all on this machine.")})
	return {"text": text, "actions": actions}


## Lo que contestó el adapter a `/remote-control` (claude-agent-acp 0.94, runRemoteControlCommand):
## «Remote Control is active… <link>» o «Remote Control is off…». Un error deja el estado como estaba.
func _observe_remote_control(turn_text: String) -> void:
	var link := RegEx.create_from_string("https://claude\\.ai/code/\\S+").search(turn_text)
	if turn_text.contains("Remote Control is active") and link:
		model.set_remote_control(link.get_string())
		agent_log.add(AgentLog.CH_ACP, "Remote Control on: %s" % link.get_string())
	elif turn_text.contains("Remote Control is off"):
		model.set_remote_control("")
		agent_log.add(AgentLog.CH_ACP, "Remote Control off")


## Prende o apaga Remote Control. El nombre de la sesión en claude.ai es el del proyecto.
func remote_control_command(enable: bool) -> String:
	if not enable:
		return "/remote-control off"
	var project_name := str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	return "/remote-control %s" % (project_name if not project_name.is_empty() else cwd.get_file())


## true si el texto es un comando del agente: empieza con `/` seguido de un nombre (no una ruta).
static func is_slash_command(text: String) -> bool:
	return RegEx.create_from_string("^/[A-Za-z][\\w:.-]*(\\s|$)").search(text.strip_edges()) != null


## Texto del agente en el turno: ahí llegan los avisos de límite (D22) y los bloques de hallazgos.
func agent_text_since(first_entry: int) -> String:
	var parts: PackedStringArray = []
	var entries := model.entries()
	for i in range(first_entry, entries.size()):
		if entries[i].kind == ChatEntry.EntryKind.AGENT:
			parts.append(entries[i].text)
	return "\n".join(parts)


## Lo que el aviso de un playtest que pasó suma al dejar una regresión (m12-48): la línea y las
## acciones «Run regressions (N)» y «CI workflow…».
static func regression_notice_parts(saved: int) -> Dictionary:
	var actions: Array[Dictionary] = [
		{"id": ACTION_RUN_REGRESSIONS, "label": I18n.t("Run regressions (%d)") % saved, "data": 1, "tooltip": I18n.t("Repeats the playtests that passed, without the agent and without using tokens.")},
		{"id": ACTION_REGRESSIONS_WORKFLOW, "label": I18n.t("CI workflow…"), "tooltip": I18n.t("Writes a GitHub Actions workflow that runs the saved regressions on every push, with this editor's Godot version.")},
	]
	return {"text": I18n.t("Saved as a regression: the harness can replay it without the agent."), "actions": actions}


## El veredicto contrastado con el turno como aviso; los hallazgos y lo detectado van al panel de
## Revisar, y lo aprendido a la memoria del juego (m15-15 a m15-18).
func _report_playtest(playtest: Dictionary, turn_text: String, first_entry: int, prompt: String) -> void:
	var audit := ReviewStore.playtest_audit(tool_calls_since(first_entry), prompt.contains(ReviewStore.RECORD_HINT))
	var audited := ReviewStore.audited_playtest(playtest, audit)
	if not _recipe_run.is_empty() and _recipe_run.get("playtest_pending", false):
		_recipe_run.playtest_verdict = audited
	var notice := ReviewStore.playtest_notice(audited)
	var actions: Array[Dictionary] = []
	var regressions := ReviewStore.PlaytestRegressions.new(regressions_dir)
	var first_regression := false
	if ReviewStore.keep_regression(ReviewStore.playtest_goal(prompt), audited, audit, regressions):
		# El aviso dice que dejó una regresión y ofrece correrlas y el workflow de CI (m12-48).
		var saved := regressions.list().size()
		first_regression = saved == 1
		var parts := regression_notice_parts(saved)
		notice.text += ("\n" if not str(notice.text).is_empty() else "") + str(parts.text)
		actions.append_array(parts.actions)
		review.changed.emit()
	if not str(audited.film).is_empty():
		actions.append({"id": ACTION_PLAY_FILM, "label": I18n.t("Play the recording"), "data": audited.film})
	var entry := model.add_notice(notice.text, notice.level, actions)
	entry.title = notice.title
	entry.sections = notice.sections
	model.notify_entry_changed(entry)
	if first_regression:
		model.add_notice(I18n.t("First regression saved. A playtest that passes leaves a script the harness can replay without the agent and without tokens: «Run regressions» in the findings panel, and «CI workflow…» writes a GitHub Actions workflow that runs them on every push. They live in %s.") % regressions_dir.trim_prefix("res://"), ChatEntry.NoticeLevel.INFO)
	ReviewStore.remember_playtest(playtest, audit, PlaytestMemory.new())
	if model.harness_mode != SessionModel.HarnessMode.REVIEW:
		return
	var findings: Array[Dictionary] = []
	findings.assign(ReviewStore.FindingsParser.parse(turn_text, cwd).findings)
	findings.append_array(audit.detectors)
	if not findings.is_empty():
		for finding: Dictionary in findings:
			finding["playtest"] = true
		review.set_findings(findings)


## Los tool calls del turno, con los de sus subagentes.
func tool_calls_since(first_entry: int) -> Array:
	var calls: Array = []
	var pending: Array = []
	var entries := model.entries()
	for i in range(first_entry, entries.size()):
		if entries[i].kind == ChatEntry.EntryKind.TOOL_GROUP:
			pending.append_array(entries[i].tool_call_ids)
	while not pending.is_empty():
		var call: ToolCall = model.tool_call(pending.pop_back())
		if call:
			calls.append(call)
			pending.append_array(call.child_ids)
	return calls


## Los mensajes del turno con el bloque `findings` ya leído lo muestran plegado (m12-38).
func _fold_findings(first_entry: int) -> void:
	var entries := model.entries()
	for i in range(first_entry, entries.size()):
		var entry: ChatEntry = entries[i]
		if entry.kind == ChatEntry.EntryKind.AGENT and entry.text.contains("\"findings\""):
			entry.findings_count = review.findings.size()
			model.entry_updated.emit(entry)


## Cambia el modo del harness y manda el turno cuando el agente ya está en el modo que corresponde.
## Marca `text` como un prompt del harness (m12-44): cuando salga (ya, o desde la cola del dock), el
## chat lo muestra con la etiqueta `label` (un msgid de HarnessPrompts) en lugar de como mensaje del
## usuario. El agente recibe el texto igual. Devuelve `text`.
func label_prompt(text: String, label: String) -> String:
	if not label.is_empty():
		(_harness_labels.get_or_add(text, []) as Array).append(label)
	return text


## La etiqueta con que va a salir `text` ("" = como mensaje del usuario).
func prompt_label(text: String) -> String:
	var labels: Array = _harness_labels.get(text, [])
	return str(labels[0]) if not labels.is_empty() else ""


## `text` marcado ya no va a salir como prompt del harness: lo quitaron de la cola, lo pasaron al
## composer para editarlo, se lo quedó el One-shot o salió con otro texto (revisión de next2 #26).
## Si no, su etiqueta quedaba y el usuario que mandaba después ese mismo texto lo veía plegado.
func unlabel_prompt(text: String) -> void:
	_take_label(text)


func _take_label(text: String) -> String:
	var labels: Array = _harness_labels.get(text, [])
	if labels.is_empty():
		return ""
	var label := str(labels.pop_front())
	if labels.is_empty():
		_harness_labels.erase(text)
	return label


func send_in_mode(mode: SessionModel.HarnessMode, text: String, extra_blocks: Array = []) -> String:
	if model.harness_mode != mode:
		model.set_harness_mode(mode)
	return await send_prompt(text, extra_blocks)


## El detector de loops cortó el playtest en curso (m11-49): se cancela el turno y, al volver
## session/prompt, el veredicto queda «could not test» con la evidencia.
func _on_playtest_loop(seen: Dictionary) -> void:
	_playtest_loop = seen
	agent_log.add(AgentLog.CH_ACP, "Playtest stopped: the agent repeated %s %d times with the same result" % [seen.get("tools", ""), int(seen.get("repeats", 0))])
	cancel()


func cancel() -> void:
	if model.state != SessionModel.SessionState.PROMPTING:
		return
	model.set_state(SessionModel.SessionState.CANCELLING)
	client.notify("session/cancel", {"sessionId": model.session_id})
	model.cancel_pending_permissions()
	_cancel_generation += 1
	_watch_cancel(_cancel_generation, _connect_generation)


## Si el agente no confirma la cancelación a tiempo (no tenía un turno abierto, o se colgó), el turno
## se cierra acá: el chat no queda en «cancelando» para siempre y la cola sigue (m17-16).
func _watch_cancel(generation: int, connect_generation: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	await tree.create_timer(CANCEL_TIMEOUT_SEC, true, false, true).timeout
	if generation != _cancel_generation or connect_generation != _connect_generation:
		return
	if model.state != SessionModel.SessionState.CANCELLING:
		return
	agent_log.add(AgentLog.CH_ACP, "The agent didn't confirm the cancellation in %d s: the turn is closed here." % int(CANCEL_TIMEOUT_SEC))
	model.add_notice(I18n.t("The agent didn't confirm the cancellation: the turn was closed here. If it doesn't answer the next message, restart it."),
		ChatEntry.NoticeLevel.WARNING, [{"id": ACTION_RESTART_AGENT, "label": I18n.t("Restart the agent")}, {"id": ACTION_SHOW_LOG, "label": I18n.t("Open the log below"), "data": agent_log.last_seq()}])
	# Con el prompt todavía en vuelo, despertarlo cierra el turno en send_prompt; si ya no está (la
	# respuesta llegó y algo cortó antes de cerrar el turno), se cierra acá.
	if _prompt_request_id >= 0 and client.cancel_request(_prompt_request_id):
		return
	model.finish_turn("cancelled")
	_record_turn_end("cancelled")


## El usuario eligió un modelo en el selector (m11-38): se manda y queda recordado para el modo actual
## de esta pestaña, con este perfil.
func choose_model(value: String) -> bool:
	var option := model.model_option()
	if option.is_empty():
		return false
	if not await set_config_option(str(option.get("id", "model")), value):
		return false
	if mode_models and _profile:
		mode_models.remember(_profile.id, model.harness_mode, value, ModeModels.option_name(option, value))
		agent_log.add(AgentLog.CH_ACP, "Model %s remembered for %s" % [value, SessionModel.HARNESS_MODE_LABELS[model.harness_mode]])
	return true


## El tooltip del selector de modelo (m11-38): para qué modo se recuerda lo que se elija, y si el que
## está es el recordado. "" si no hay modelo por modo (sin tienda, sin perfil o sin la opción).
func model_tooltip() -> String:
	var option := model.model_option()
	if mode_models == null or _profile == null or option.is_empty():
		return ""
	var mode_label := I18n.t(SessionModel.HARNESS_MODE_LABELS[model.harness_mode])
	var wanted := mode_models.get_model(_profile.id, model.harness_mode)
	if not wanted.is_empty() and str(wanted.value) == str(option.get("currentValue", "")):
		return I18n.t("Model. Remembered for %s: the one you pick is used every time you switch to %s.") % [mode_label, mode_label]
	return I18n.t("Model. The one you pick is remembered for %s.") % mode_label


## Pide el modelo recordado para el modo actual, si hay uno y no es el que está (m11-38). Cuenta como
## un sync de modo: el próximo prompt lo espera.
func _sync_mode_model() -> void:
	if mode_models == null or _profile == null or model.session_id.is_empty():
		return
	var option := model.model_option()
	var wanted := mode_models.get_model(_profile.id, model.harness_mode)
	if option.is_empty() or wanted.is_empty():
		return
	var value := str(wanted.value)
	if value == str(option.get("currentValue", "")):
		return
	var mode_label := I18n.t(SessionModel.HARNESS_MODE_LABELS[model.harness_mode])
	if not ModeModels.offers(option, value):
		agent_log.add(AgentLog.CH_ACP, "The model remembered for %s (%s) is not offered by the agent: left as is" % [SessionModel.HARNESS_MODE_LABELS[model.harness_mode], value])
		var key := "%s/%s" % [model.harness_mode, value]
		if not _missing_models_noticed.has(key):
			_missing_models_noticed[key] = true
			model.add_notice(I18n.t("%s remembers the model «%s», but %s doesn't offer it now (another account?). The model wasn't changed.") % [mode_label, str(wanted.get("name", value)), _agent_name()], ChatEntry.NoticeLevel.WARNING)
		return
	_mode_syncs_running += 1
	var ok := await set_config_option(str(option.get("id", "model")), value)
	_mode_syncs_running -= 1
	if ok:
		var name := ModeModels.option_name(model.model_option(), value)
		agent_log.add(AgentLog.CH_ACP, "%s uses %s (remembered for this mode)" % [SessionModel.HARNESS_MODE_LABELS[model.harness_mode], value])
		if not _mode_model_noticed:
			_mode_model_noticed = true
			model.add_notice(I18n.t("%s uses %s.") % [mode_label, name], ChatEntry.NoticeLevel.INFO,
				[{"id": ACTION_CHOOSE_MODEL, "label": I18n.t("Change"), "tooltip": I18n.t("Choose another model for %s: the one you pick is remembered for this mode.") % mode_label}])
	agent_mode_synced.emit()


func set_config_option(id: String, value: String) -> bool:
	if model.session_id.is_empty():
		return false
	var result := await client.request("session/set_config_option", {"sessionId": model.session_id, "configId": id, "value": value})
	if not result.ok:
		model.add_notice(I18n.t("Could not change '%s': %s") % [id, result.error_message()], ChatEntry.NoticeLevel.WARNING)
		return false
	if result.result is Dictionary and result.result.get("configOptions") is Array:
		model.config_options = result.result.configOptions
		model.config_options_changed.emit(model.config_options)
	else:
		model.set_config_value(id, value)
	return true


## Mata el proceso y cierra los requests pendientes. Seguro de llamar varias veces.
func stop() -> void:
	_connect_generation += 1
	cancel_login()
	if terminal:
		terminal.stop_all()
	if _process:
		var process := _process
		_process = null
		process.stop()
		agent_log.add(AgentLog.CH_PROC, "Process stopped")
	client.fail_all_pending("Session stopped.")
	model.cancel_pending_permissions()
	if history:
		history.end()
	if model.state != SessionModel.SessionState.DISCONNECTED and not model.has_failed():
		model.set_state(SessionModel.SessionState.DISCONNECTED)
		disconnected.emit()


func client_capabilities() -> Dictionary:
	var capabilities := {
		"fs": {
			"readTextFile": client.has_request_handler("fs/read_text_file"),
			"writeTextFile": client.has_request_handler("fs/write_text_file"),
		},
		"terminal": client.has_request_handler("terminal/create"),
		# Login con el comando del agente (claude-agent-acp ofrece entonces «Claude Subscription» y
		# «Anthropic Console»). El agente guarda sus credenciales; el addon no las ve.
		"auth": {"terminal": true},
		# Subagentes nativos (RFD de ACP, m7-43): el agente anuncia cada subagente con su sesión y su
		# estado, que sigue después del tool call que lo lanzó si corre en segundo plano.
		"subagents": {},
		# La compactación como estado propio (m11-60): claude-agent-acp manda compaction_update con el
		# resumen en lugar de una tool call «Compact conversation».
		"session": {"compaction": {}},
	}
	if client.has_request_handler("elicitation/create"):
		capabilities["elicitation"] = {"form": {}, "url": {}}
	return capabilities


static func is_auth_required(error: Dictionary) -> bool:
	return int(error.get("code", 0)) == AUTH_REQUIRED_CODE and str(error.get("message", "")).to_lower().begins_with(AUTH_REQUIRED_MESSAGE)


# --- login (ACP auth) ----------------------------------------------------------------------------

func is_logging_in() -> bool:
	return _login != null and _login.is_running()


## Inicia sesión con el método `method_id` de `authMethods`. Los `terminal` corren el login del
## agente (navegador); los demás se le piden al agente con `authenticate`. Al terminar bien vuelve
## a lanzar el agente para abrir la sesión con las credenciales nuevas.
func login(method_id: String) -> void:
	var method := {}
	for item: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		if item.id == method_id:
			method = item
	if method.is_empty() or _profile == null:
		model.add_notice(I18n.t("The agent does not offer that sign-in method."), ChatEntry.NoticeLevel.WARNING)
		return
	cancel_login()
	var label := AgentLogin.label_of(method)
	agent_log.add(AgentLog.CH_PROC, "Sign-in: %s" % label)
	if not AgentLogin.is_terminal(method):
		_login_entry = model.add_notice(I18n.t("Signing in with %s…") % label)
		var result := await client.request("authenticate", {"methodId": method_id})
		_on_login_finished(result.ok, result.error_message() if not result.ok else "")
		return
	_login = AgentLogin.new()
	_login.url_found.connect(_on_login_url)
	_login.finished.connect(_on_login_finished)
	_login_entry = model.add_notice(I18n.t("Signing in with %s: finish in the browser that just opened.") % label,
		ChatEntry.NoticeLevel.INFO, [{"id": ACTION_LOGIN_CANCEL, "label": I18n.t("Cancel")}])
	var command := AgentLogin.command_for(method, _profile)
	agent_log.add(AgentLog.CH_PROC, "Login: %s %s" % [command.command, " ".join(command.args)])
	_login.start(method, _profile)


## El código que muestra la página de login si el navegador no volvió solo.
func send_login_code(code: String) -> bool:
	if not is_logging_in():
		return false
	agent_log.add(AgentLog.CH_PROC, "Login: code sent")  # nunca el código
	return _login.send_code(code)


func cancel_login() -> void:
	if _login == null:
		return
	var login_run := _login
	_login = null
	if login_run.is_running():
		login_run.cancel()
		if _login_entry:
			_set_login_notice(I18n.t("Sign-in cancelled."), ChatEntry.NoticeLevel.INFO, [])
	_login_entry = null


func _on_login_url(url: String) -> void:
	_set_login_notice(I18n.t("Signing in with %s: finish in the browser. If it did not open, open the link; if the page gives you a code, paste it here.") % AgentLogin.label_of(_login.method),
		ChatEntry.NoticeLevel.INFO, [
			{"id": "open_link", "label": I18n.t("Open link"), "data": url},
			{"id": ACTION_LOGIN_CODE, "label": I18n.t("Paste code…")},
			{"id": ACTION_LOGIN_CANCEL, "label": I18n.t("Cancel")},
		])


func _on_login_finished(ok: bool, message: String) -> void:
	_login = null
	if not ok:
		agent_log.add(AgentLog.CH_PROC, "Login failed: %s" % message)
		_set_login_notice(I18n.t("Could not sign in: %s") % message, ChatEntry.NoticeLevel.ERROR, _login_actions())
		_login_entry = null
		return
	agent_log.add(AgentLog.CH_PROC, "Login complete")
	_login_entry = null
	if after_login.is_valid() and await after_login.call():
		model.add_notice(I18n.t("Signed in."))
		return
	if _profile and await start(_profile):
		var pending := _prompt_after_login
		_prompt_after_login = {}
		if pending.is_empty():
			model.add_notice(I18n.t("Signed in."))
		else:
			model.add_notice(I18n.t("Signed in. Sending your message again."))
			send_prompt(str(pending.text), pending.blocks)


func _set_login_notice(text: String, level: ChatEntry.NoticeLevel, actions: Array[Dictionary]) -> void:
	if _login_entry == null:
		_login_entry = model.add_notice(text, level, actions)
		return
	_login_entry.text = text
	_login_entry.level = level
	_login_entry.actions = actions
	model.notify_entry_changed(_login_entry)


## Métodos de login que el addon sabe correr: {id, label}. Para «Cambiar de cuenta».
func login_methods() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for method: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		result.append({"id": str(method.id), "label": AgentLogin.label_of(method)})
	return result


## Un botón por método que el addon sabe usar.
## El primer método como botón principal; los demás, en el menú «Otras formas de entrar» (m12-11).
func _login_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	for method: Dictionary in AgentLogin.usable_methods(model.auth_methods):
		var action := {"id": ACTION_LOGIN, "label": AgentLogin.label_of(method), "data": str(method.id)}
		if actions.is_empty():
			action["primary"] = true
		else:
			action["more"] = I18n.t("Other ways to sign in")
		actions.append(action)
	return actions


func _agent_name() -> String:
	return _profile.display_name if _profile else I18n.t("the agent")


func system_prompt() -> String:
	var template := FileAccess.get_file_as_string(SYSTEM_PROMPT_PATH)
	var variables: Dictionary = prompt_variables_provider.call() if prompt_variables_provider.is_valid() else {}
	variables["mode"] = SessionModel.HARNESS_MODE_LABELS[model.harness_mode]
	variables["mode_rules"] = mode_rules_override if not mode_rules_override.is_empty() else MODE_RULES[model.harness_mode]
	if not model.project_mode.is_empty():
		# Un modo del proyecto (m11-39): su nombre, y sus archivos e instrucciones después de las reglas del base.
		variables["mode"] = "%s (a project mode based on %s)" % [model.project_mode.name, variables["mode"]]
		variables["mode_rules"] = ProjectModes.prompt_rules(model.project_mode, str(variables["mode_rules"]))
	variables["project_path"] = variables.get("project_path", cwd)
	variables["project_name"] = variables.get("project_name", cwd.get_file())
	variables["godot_version"] = variables.get("godot_version", Engine.get_version_info().string)
	variables["project_tools_dir"] = variables.get("project_tools_dir", "res://agent_tools")
	variables["godot_bin"] = variables.get("godot_bin", EditorBinary.path())
	variables["headless_guide"] = variables.get("headless_guide", ProjectSettings.globalize_path(HEADLESS_GUIDE_PATH))
	variables["csharp_rules"] = CSHARP_RULES if not CsharpBuild.find_project(cwd).is_empty() else ""
	variables["native_rules"] = NATIVE_RULES if not NativeBuild.find_project(cwd).is_empty() else ""
	return "<harness_context>\n%s\n</harness_context>" % template.format(variables)


## Pide permiso según la política del modo actual (ver PermissionBroker.authorize).
func authorize(group: String, title: String, description: String, diff: Dictionary = {}, timeout_s: int = 0) -> bool:
	return await permissions.authorize(group, title, description, diff, timeout_s)


## MCP servers de terceros (configurados o ya vistos) que en `mode` preguntan o se niegan.
func mcp_servers_not_allowed(mode: SessionModel.HarnessMode) -> PackedStringArray:
	return permissions.mcp_servers_not_allowed(mode, external_mcp_names)


# --- internos ------------------------------------------------------------------------------------

## El agente retiró un pedido de permiso o formulario: lo contestaron desde Remote Control o ya no hace falta.
func _on_incoming_cancelled(id: Variant) -> void:
	permissions.withdraw(id)
	var elicitation: ElicitationRequest = _elicitations_by_acp_id.get(id)
	if elicitation and elicitation.is_pending():
		elicitation.withdrawn = true
		elicitation.cancel()


## Formulario o enlace del agente (`elicitation/create`, m11-17): muestra la tarjeta y devuelve la respuesta.
func _on_create_elicitation(params: Dictionary) -> Variant:
	var acp_id: Variant = client.handling_id
	var request := ElicitationRequest.from_params(params)
	# El formulario se muestra sin los secretos del harness (m13-28), como la tarjeta de permiso: el
	# mensaje y los títulos y descripciones del schema. Los defaults, las opciones y el enlace son lo
	# que vuelve al agente o se abre, y quedan reales: la tarjeta los muestra con `redact` (#18).
	request.message = agent_log.redact(request.message)
	request.redact = agent_log.redact
	request.requested_schema = agent_log.redact_fields(request.requested_schema, ElicitationRequest.SHOWN_SCHEMA_FIELDS)
	var invalid: String = request.invalid_reason()
	if not invalid.is_empty():
		agent_log.add(AgentLog.CH_PERM, "elicitation rejected: %s" % invalid)
		return AcpClient.AcpResponse.failure(AcpClient.ERR_INVALID_PARAMS, invalid)
	if acp_id != null:
		_elicitations_by_acp_id[acp_id] = request
	model.add_elicitation(request)
	var response: Dictionary = request.response
	if request.is_pending():
		response = await request.resolved
		if not request.withdrawn:
			await PermissionBroker.next_frame()  # como en PermissionBroker.ask_user: fuera de quien respondió
	if acp_id != null and _elicitations_by_acp_id.get(acp_id) == request:
		_elicitations_by_acp_id.erase(acp_id)
	return response


## Notificación `elicitation/complete` (m11-17): cierra el formulario/enlace con ese `elicitationId`.
func _on_complete_elicitation(params: Dictionary) -> void:
	model.complete_elicitation(str(params.get("elicitationId", "")))


func _terminal_base_env() -> Dictionary:
	var profile_env: Dictionary = _profile.resolved_env() if _profile else {}
	var base_path := CommandResolver.child_path_for(CommandResolver.resolve(_profile.command)) if _profile else ""
	return EditorBinary.child_env(profile_env, base_path)


## Pide al CLI de Claude Code con qué cuenta está logueado el perfil (su CLAUDE_CONFIG_DIR) y la
## deja en el modelo. Otros agentes no la informan: queda vacía.
func _refresh_account() -> void:
	var profile := _profile
	if profile == null or not adapter.reads_account_from_cli():
		# La que mandó el agente con _auth/status_update (llega una vez, antes de session/new).
		model.set_account(_agent_account if profile == _agent_account_profile else {})
		return
	var cli := ClaudeCli.new(cwd, profile.resolved_env())
	var account := await cli.auth_status() if cli.is_available() else {}
	if profile == _profile:  # no se cambió de agente mientras tanto
		model.set_account(account)
		if not account.is_empty():
			# Sin el email: el log se pega en reportes de bugs.
			agent_log.add(AgentLog.CH_PROC, "Logged in (%s, %s plan)" % [account.method, account.plan])


## Notificación `_auth/status_update` (extensión ACP de `codex-acp`): actualiza la cuenta del modelo.
func _on_auth_status_update(params: Dictionary) -> void:
	var status: Variant = params.get("authStatus")
	if not status is Dictionary:
		return
	var kind := str(status.get("kind", ""))
	_agent_account_profile = _profile
	if kind == "none":
		_agent_account = {}
		model.set_account({})
		return
	var acc: Dictionary = status.get("account") if status.get("account") is Dictionary else {}
	_agent_account = {
		"email": str(acc.get("email", "")),
		"org": str(acc.get("organization", "")),
		"plan": str(acc.get("plan", "")),
		"method": str(status.get("label", kind)),
	}
	model.set_account(_agent_account)


func _send_line(line: String) -> bool:
	return _process != null and _process.send_line(line)


## Durante session/load el agente vuelve a mandar toda la conversación; acá se descarta, porque
## model.session_id recién se asigna con la respuesta y el dock ya la armó desde el historial.
func _on_session_update(params: Dictionary) -> void:
	if not params.get("update") is Dictionary:
		return
	if params.get("sessionId") != model.session_id:
		if params.get("sessionId") is String and not model.session_id.is_empty():
			model.apply_child_update(params.sessionId, params.update)
		return
	if usage_query.capture(params.update):
		return
	if params.update.get("sessionUpdate") == "usage_update":
		quota.observe_update(params.update)
	elif params.update.get("sessionUpdate") == "session_info_update":
		quota.observe_session_info(params.update)
	_notice_outside_turn(params.update)
	if not model.apply_update(params.update):
		agent_log.add(AgentLog.CH_ACP, "Unknown session/update variant, ignored: %s" % str(params.update.get("sessionUpdate", "?")))
	elif history:
		history.record_update(params.update)


## Claude Code arranca un turno solo cuando le llega un mensaje de otra sesión suya (SendMessage) o
## termina una tarea en segundo plano, y claude-agent-acp (0.98) no reenvía ese mensaje: el chat
## vería la respuesta sin la pregunta. Se avisa una vez hasta el próximo prompt. Un mensaje de Remote
## Control sí llega (user_message_chunk) y no lleva aviso.
func _notice_outside_turn(update: Dictionary) -> void:
	if model.state != SessionModel.SessionState.READY or _outside_turn_noticed or not model.parent_tool_call_id(update).is_empty():
		return
	var kind := str(update.get("sessionUpdate", ""))
	if kind == "user_message_chunk":
		_outside_turn_noticed = true
	elif kind in ["agent_message_chunk", "agent_thought_chunk", "tool_call"]:
		_outside_turn_noticed = true
		model.add_notice(I18n.t("The agent is answering something it received outside this chat (a message from another Claude Code session or a background task that finished): the editor only gets its answer. To see the messages between sessions, ask the agents to use godot.session_send."))


func _record_turn_end(stop_reason: String) -> void:
	if history:
		history.record_turn_end(stop_reason)


## Reanuda una sesión del historial o de `session/list` (m11-16): si hay registro local, arma la
## conversación desde el archivo y usa `session/resume` (sin replay) o `session/load`; si viene solo
## del agente, `session/load` reconstruye la conversación o `session/resume` retoma el contexto.
func _load_session(record: Dictionary, generation: int) -> bool:
	var session_id := str(record.get("id", ""))
	var has_local_events := record.get("events") is Array and not (record.events as Array).is_empty()
	if has_local_events:
		# Un historial grabado antes de registrar un secreto (o por una versión que no redactaba) no lo
		# vuelve a mostrar (m13-25).
		SessionHistory.replay(agent_log.redact_data(record), model)
	if not model.can_resume_sessions():
		_load_failed = true
		stop()
		model.add_notice(I18n.t("%s cannot resume sessions (it does not announce session/load): the history stays read-only. Type to start a new session.") % _profile.display_name)
		return false
	var use_resume := (has_local_events and model.supports_resume_session()) or not model.supports_load_session()
	var method := "session/resume" if use_resume else "session/load"
	if not has_local_events and method == "session/load":
		# Sin historial local, dejamos que los updates del replay entren al modelo y al historial.
		model.session_id = session_id
		if history and _profile:
			history.begin(session_id, _profile.id, _profile.label(), cwd, record, _profile.account_dir)
	var mcp_servers: Array = mcp_servers_provider.call() if mcp_servers_provider.is_valid() else []
	_cancel_abandoned_requests()
	var req_id := client.next_request_id()
	_session_request_id = req_id
	var result := await client.request(method, _with_meta({"sessionId": session_id, "cwd": cwd, "mcpServers": mcp_servers}))
	if _session_request_id == req_id:
		_session_request_id = 0
	if generation != _connect_generation or result.error.get("code") == AcpClient.ERR_REQUEST_CANCELLED:
		return false
	if model.has_failed():  # el agente se cayó esperando la respuesta: la tarjeta ya la puso _fail_agent (m13-26)
		return false
	if not result.ok:
		_load_failed = true
		stop()
		model.add_notice(I18n.t("Could not resume the session: %s. The history stays read-only.") % result.error_message(), ChatEntry.NoticeLevel.WARNING)
		return false
	model.apply_session(session_id, result.result if result.result is Dictionary else {})
	_reset_path_rules()  # lo mandado antes quedó en el contexto recuperado, pero no sabemos qué: de nuevo
	var remote_title := str(record.get("title", ""))
	if not remote_title.is_empty() and model.title.is_empty():
		model.apply_update({"sessionUpdate": "session_info_update", "title": remote_title})
	_system_prompt_sent = true  # ya está en el contexto que el agente recuperó
	policy.clear_session()
	permissions.reset()
	if history and _profile and (has_local_events or method == "session/resume"):
		history.begin(session_id, _profile.id, _profile.label(), cwd, record, _profile.account_dir)
	await _sync_mode_model()  # antes del primer prompt (m11-38)
	if generation != _connect_generation:
		return false
	model.set_state(SessionModel.SessionState.READY)
	var resumed_msg := I18n.t("Session resumed: the agent recovered its context with session/resume.") if use_resume else I18n.t("Session resumed: the agent recovered its context with session/load.")
	model.add_notice(resumed_msg)
	_sync_agent_mode()
	_refresh_account()
	connected.emit()
	return true


## Pide al agente sus sesiones de `filter_cwd` con `session/list` (m11-16).
func list_agent_sessions(filter_cwd: String = cwd) -> Array[Dictionary]:
	return await sessions.list(filter_cwd, _agent_running(), _profile)


func _refresh_agent_sessions() -> void:
	if model.supports_list_sessions():
		await list_agent_sessions(cwd)


## Cierra una sesión en el agente con `session/close` (m11-16) si lo soporta.
func close_session(target_session_id: String = "") -> bool:
	return await sessions.close(target_session_id if not target_session_id.is_empty() else model.session_id, _agent_running())


## Elimina una sesión del historial local y, si es del perfil conectado y el agente soporta
## `session/delete`, también en el agente. Si el agente no la borra, la local queda.
## `session_account`: la cuenta con la que se hizo la sesión. Solo se le pide al agente que la borre
## si es el mismo agente con la misma cuenta: otra cuenta guarda sus sesiones en otra carpeta.
func delete_session(target_session_id: String, session_profile_id: String = "", session_account: String = "") -> bool:
	var same_agent := owns_session(_profile, session_profile_id, session_account)
	return await sessions.delete(target_session_id, same_agent and _agent_running(), history)


## true si el agente lanzado con `profile` guarda la sesión de ese perfil y esa cuenta.
static func owns_session(profile: AgentProfile, session_profile_id: String, session_account: String) -> bool:
	return profile != null and (session_profile_id.is_empty() or session_profile_id == profile.id) and session_account == profile.account_dir


func _agent_running() -> bool:
	return _process != null and _process.is_running()


func _with_meta(params: Dictionary) -> Dictionary:
	var meta: Dictionary = session_meta_provider.call() if session_meta_provider.is_valid() else {}
	if not meta.is_empty():
		params._meta = meta
	return params


func _on_stderr(line: String) -> void:
	agent_log.add(AgentLog.CH_PROC, line)
	if line.strip_edges().is_empty():  # no ocupa lugar en la cola: la tarjeta no la mostraría
		return
	# Redactada al guardarla (m13-22): la tarjeta y su «Copy» no pasan por el log, y el recorte podría
	# caer en medio del token y dejar su principio a la vista.
	_stderr_tail.append(agent_log.redact(line))
	if _stderr_tail.size() > STDERR_TAIL:
		_stderr_tail.remove_at(0)


func _on_process_exited(code: int, process: AgentProcess) -> void:
	if process != _process:
		return
	_process = null
	process.stop()
	if terminal:
		terminal.stop_all()
	# Primero la tarjeta y FAILED, después los requests pendientes (m13-24): el turno que la caída corta
	# ve la sesión caída y no suma su propia tarjeta de error.
	_fail_agent(I18n.t("%s stopped") % _agent_name(),
		I18n.t("The agent's process ended unexpectedly (code %d).") % code,
		"The agent exited unexpectedly (code %d)." % code, _crash_actions())
	client.fail_all_pending("The agent exited (code %d)." % code)
	disconnected.emit()


## Un cambio de estado fuera de SessionModel.SESSION_STATE_TRANSITIONS (m13-13): se aplicó igual,
## queda en el log para revisar la tabla o el camino que lo produjo.
func _on_unexpected_transition(from: SessionModel.SessionState, to: SessionModel.SessionState) -> void:
	agent_log.add(AgentLog.CH_STATE, "session: unexpected transition %s -> %s" % [SessionModel.state_name(from), SessionModel.state_name(to)])


func _on_project_mode_changed(_mode: Dictionary) -> void:
	_system_prompt_sent = false


func _on_harness_mode_changed(_mode: SessionModel.HarnessMode) -> void:
	_system_prompt_sent = false
	# El modelo primero (m11-38): cambiarlo puede bajar de modo en el adapter. Con «Aprobar y construir»
	# (_skip_mode_sync) el agente sale solo de plan, pero el modelo de Construir se pide igual: el
	# adapter lo acepta en medio del turno y el resto del turno ya va con ese modelo.
	_sync_mode_model()
	if not _skip_mode_sync:
		_sync_agent_mode()


## «Aprobar y construir» en la tarjeta del plan (m11-22). Orden: el harness pasa a Construir (sin
## set_mode), el plan se guarda en .godot_agent/plans y recién ahí se contesta «aprobar». El agente
## pasa solo a su modo default y sigue en el mismo turno pidiendo editar: esas tarjetas ya caen en la
## matriz de Construir. Si el agente no cambió de modo al terminar el turno, se sincroniza entonces.
## Devuelve la ruta del plan guardado ("" si no se pudo guardar).
func approve_plan(request: PermissionRequest) -> String:
	if not request.is_pending() or not request.is_plan():
		return ""
	var allow := request.option_id_for([PermissionRequest.KIND_ALLOW_ONCE, PermissionRequest.KIND_ALLOW_ALWAYS])
	if allow.is_empty():
		return ""
	_start_planned_recipe_run()
	_start_criteria_run(request)
	if request.from_block:
		var saved := _approve_block_plan(request, allow)
		if _recipe_run.get("card") == request:
			_recipe_run.plan_path = saved
		return saved
	if model.harness_mode != SessionModel.HarnessMode.BUILD:
		_skip_mode_sync = true
		model.set_harness_mode(SessionModel.HarnessMode.BUILD)
		_skip_mode_sync = false
		agent_log.add(AgentLog.CH_PERM, "plan approved: harness mode Build, the agent leaves plan mode by itself")
		if not model.turn_finished.is_connected(_sync_agent_mode_if_off):
			model.turn_finished.connect(_sync_agent_mode_if_off, CONNECT_ONE_SHOT)
	var path := PlanStore.save_approved(cwd, request.edited_plan if not request.edited_plan.is_empty() else request.plan_text)
	if path.is_empty():
		agent_log.add(AgentLog.CH_PERM, "could not save the approved plan in %s" % cwd.path_join(PlanStore.DIR))
	else:
		agent_log.add(AgentLog.CH_PERM, "approved plan saved: %s" % path)
	if _recipe_run.get("card") == request:
		_recipe_run.plan_path = path
	request.plan_approved = true
	request.select(allow)
	return path


## true si el agente tiene un modo plan propio (Claude Code): ahí presenta el plan con ExitPlanMode.
func agent_has_plan_mode() -> bool:
	for mode: Variant in model.agent_modes:
		if mode is Dictionary and str(mode.get("id", "")) in AGENT_MODE_FOR[SessionModel.HarnessMode.ASK]:
			return true
	return false


## «Planificar» / `/plan` (m11-58): pasa a Preguntar y le pide el plan al agente, marcado como prompt
## del harness. Con modo plan propio, el agente lo presenta con ExitPlanMode (tarjeta de m11-22); sin
## él, en un bloque ```plan que se vuelve la misma tarjeta al terminar el turno.
func request_plan(what: String, extra_blocks: Array = []) -> String:
	if what.strip_edges().is_empty() or model.state != SessionModel.SessionState.READY:
		return ""
	var text := label_prompt(PlanApproval.request_prompt(what, agent_has_plan_mode()), HarnessPrompts.PLAN_REQUEST)
	return await send_in_mode(SessionModel.HarnessMode.ASK, text, extra_blocks)


## Al terminar un turno de plan sin tarjeta de ExitPlanMode: el último bloque ```plan del agente se
## muestra en la tarjeta del plan y en el mensaje queda una línea.
func _offer_block_plan(first_entry: int) -> void:
	for call: ToolCall in tool_calls_since(first_entry):
		if call.plan_card:
			return
	var entries := model.entries()
	for i in range(entries.size() - 1, first_entry - 1, -1):
		var entry: ChatEntry = entries[i]
		if entry.kind != ChatEntry.EntryKind.AGENT:
			continue
		var plan := PlanApproval.plan_block(entry.text)
		if plan.is_empty():
			continue
		entry.plan_folded = true
		model.entry_updated.emit(entry)
		_block_plan = PlanApproval.block_request(plan)
		_block_plan.resolved.connect(_on_block_plan_resolved, CONNECT_ONE_SHOT)
		model.add_permission(_block_plan)
		agent_log.add(AgentLog.CH_PERM, "plan presented in a ```plan block (%d lines)" % (plan.count("\n") + 1))
		return
	agent_log.add(AgentLog.CH_PERM, "plan turn ended without a ```plan block or an ExitPlanMode card")


func _cancel_block_plan() -> void:
	if _block_plan != null and _block_plan.is_pending():
		_block_plan.cancel()
	_block_plan = null


## Editar o «Seguir planeando…» en la tarjeta de un plan en bloque: el agente ya terminó su turno,
## así que lo editado o el motivo salen enseguida, pidiendo de nuevo el bloque. Aprobar lo maneja
## approve_plan; cancelada (otro mensaje, sesión nueva), no sale nada.
func _on_block_plan_resolved(_outcome: Dictionary) -> void:
	var request := _block_plan
	_block_plan = null
	if request == null or request.was_allowed():
		return
	if not request.edited_plan.is_empty():
		_on_reject_feedback(PlanApproval.edit_feedback(request.plan_text, request.edited_plan, true), HarnessPrompts.PLAN_EDIT)
	elif not request.deny_reason.is_empty():
		_on_reject_feedback(PlanApproval.keep_planning_feedback(request.deny_reason, true), HarnessPrompts.PLAN_KEEP_PLANNING)


## Un plan en bloque aprobado: se guarda, la tarjeta queda aprobada y el pedido de construirlo sale en
## Construir (con set_mode: este agente no sale solo de ningún modo plan).
func _approve_block_plan(request: PermissionRequest, allow: String) -> String:
	if model.state != SessionModel.SessionState.READY:
		return ""
	var path := PlanStore.save_approved(cwd, request.edited_plan if not request.edited_plan.is_empty() else request.plan_text)
	agent_log.add(AgentLog.CH_PERM, "approved plan saved: %s" % path if not path.is_empty() else "could not save the approved plan in %s" % cwd.path_join(PlanStore.DIR))
	request.plan_approved = true
	request.select(allow)
	var relative := path.trim_prefix(cwd).trim_prefix("/") if not path.is_empty() else ""
	send_in_mode(SessionModel.HarnessMode.BUILD, label_prompt(PlanApproval.approved_prompt(relative), HarnessPrompts.PLAN_APPROVED))
	return path


func _on_reject_feedback(text: String, label: String) -> void:
	reject_feedback.emit(label_prompt(text, label))


## El agente no siguió al harness (otro agente, o 0.105 cambió): se le manda el modo que corresponde.
func _sync_agent_mode_if_off(_stop_reason: String = "") -> void:
	if not model.current_agent_mode in AGENT_MODE_FOR[model.harness_mode]:
		_sync_agent_mode()


## Si el agente publica modos, se elige el que corresponde al modo del harness.
func _sync_agent_mode(candidates: Variant = null) -> void:
	if model.session_id.is_empty() or model.agent_modes.is_empty():
		return
	var available: PackedStringArray = []
	for mode: Variant in model.agent_modes:
		if mode is Dictionary:
			available.append(str(mode.get("id", "")))
	for candidate: String in (candidates if candidates != null else AGENT_MODE_FOR[model.harness_mode]):
		if candidate in available and candidate != model.current_agent_mode:
			_mode_syncs_running += 1
			var result := await client.request("session/set_mode", {"sessionId": model.session_id, "modeId": candidate})
			_mode_syncs_running -= 1
			if result.ok:
				model.apply_update({"sessionUpdate": "current_mode_update", "currentModeId": candidate})
			else:
				agent_log.add(AgentLog.CH_ACP, "Could not switch the agent to mode %s: %s" % [candidate, result.error_message()])
			agent_mode_synced.emit()  # después de anotarlo: quien espera mira el modo actual
			return


## La sesión no quedó abierta: tarjeta con el motivo y `final_state` (FAILED, o LOGIN_REQUIRED cuando
## lo que falta es iniciar sesión, m12-11).
func _fail(message: String, extra_actions: Array[Dictionary] = [], level := ChatEntry.NoticeLevel.ERROR, with_error_actions := true, final_state := SessionModel.SessionState.FAILED) -> void:
	message = agent_log.redact(message)  # va a la tarjeta y al tooltip del estado, no solo al log
	model.failure_message = message
	agent_log.add(AgentLog.CH_PROC, message)
	var actions := extra_actions.duplicate()
	if with_error_actions:
		actions.append_array(_error_actions())
	model.add_notice(message, level, actions)
	model.set_state(final_state)


## Error al lanzar o mantener el agente (m12-13): título y causa para personas, las últimas líneas
## de su stderr y la acción que lo arregla. `log_message` va al log y al tooltip del estado.
func _fail_agent(title: String, cause: String, log_message: String, actions: Array[Dictionary]) -> void:
	cause = agent_log.redact(cause)
	log_message = agent_log.redact(log_message)
	model.failure_message = log_message
	agent_log.add(AgentLog.CH_PROC, log_message)
	for action: Dictionary in actions:
		if action.id == ACTION_SHOW_LOG:
			action["data"] = agent_log.last_seq()
	var entry := model.add_notice(cause, ChatEntry.NoticeLevel.ERROR, actions)
	entry.title = title
	entry.details = stderr_summary(_stderr_tail)
	entry.details_full = "\n".join(_stderr_tail)  # ya redactadas (_on_stderr)
	model.notify_entry_changed(entry)
	model.set_state(SessionModel.SessionState.FAILED)


## Las últimas líneas útiles del stderr para la tarjeta (m13-22): sin las vacías, cada una
## recortada a `max_chars` con cuántos caracteres quedaron afuera (el Agent Log tiene cada línea
## entera, de _on_stderr), y como mucho `max_lines`.
static func stderr_summary(lines: PackedStringArray, max_lines: int = STDERR_TAIL, max_chars: int = STDERR_LINE_CHARS) -> String:
	var kept: PackedStringArray = []
	for line: String in lines:
		var text := line.strip_edges()
		if text.is_empty():
			continue
		if text.length() > max_chars:
			text = text.left(max_chars).strip_edges() + " " + I18n.t("… %d more characters, see the Agent Log") % (text.length() - max_chars)
		kept.append(text)
	if kept.size() > max_lines:
		kept = kept.slice(kept.size() - max_lines)
	return "\n".join(kept)


## Reintentar primero; un agente del registro (binario bajado por el harness) se puede reinstalar.
func _crash_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = [{"id": ACTION_RETRY, "label": I18n.t("Retry"), "primary": true}]
	if _profile and is_registry_binary(_profile.command):
		actions.append({"id": ACTION_REINSTALL_AGENT, "label": I18n.t("Reinstall…")})
	actions.append({"id": ACTION_SHOW_LOG, "label": I18n.t("Open the log below")})
	return actions


## El comando es un binario que bajó el registro de ACP (`<datos del editor>/godot_agent/agents/`).
static func is_registry_binary(command: String) -> bool:
	return command.replace("\\", "/").contains("/godot_agent/agents/")


## «Abrir el log abajo» lleva el `seq` de la última línea del log (la del error): el panel salta ahí (m12-36).
func _error_actions() -> Array[Dictionary]:
	return [{"id": ACTION_RETRY, "label": I18n.t("Retry")}, {"id": ACTION_SHOW_LOG, "label": I18n.t("Open the log below"), "data": agent_log.last_seq()}]


func _auth_hint() -> String:
	var names: PackedStringArray = []
	for method: Variant in model.auth_methods:
		if method is Dictionary:
			names.append("%s (%s)" % [method.get("name", method.get("id", "?")), method.get("description", "")])
	return ", ".join(names)


func _on_terminal_output(terminal_id: String, output: String, exit_code: Variant) -> void:
	model.set_terminal_output(terminal_id, output, exit_code)


func _on_config_options_changed(_options: Array) -> void:
	adapter.model_changed(quota, _current_model_name())
