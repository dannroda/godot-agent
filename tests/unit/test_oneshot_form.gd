extends "test_case.gd"
## Formulario de la pantalla One-shot: qué falta para iniciar (m12-33).

const AgentMainScreen := preload("res://addons/godot_agent/ui/main_screen/agent_main_screen.gd")
const AgentMainScreenScene := preload("res://addons/godot_agent/ui/main_screen/agent_main_screen.tscn")
const OneShotRun := preload("res://addons/godot_agent/oneshot/oneshot_run.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const ModeModels := preload("res://addons/godot_agent/core/mode_models.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")


func test_start_blocker() -> void:
	assert_eq(AgentMainScreen.start_blocker("Claude Code", "Pong", false), "", "con agente y objetivo, nada")
	assert_eq(AgentMainScreen.start_blocker("Claude Code", "  \n", false), "Write the goal first.", "sin objetivo")
	assert_eq(AgentMainScreen.start_blocker("", "Pong", false), "Set up an agent first.", "sin agente")
	assert_eq(AgentMainScreen.start_blocker("", "", true), "A One-shot is already running.", "en curso gana")


## m6-19: el modelo antes de abrir sesión. La primera opción deja el recordado (o el del agente); las
## demás, los de una sesión abierta con ese agente o, sin ella, los recordados en cualquier modo.
func test_model_choices() -> void:
	var none := AgentMainScreen.model_choices({}, {}, {})
	assert_eq(none.size(), 1, "sin nada, solo el del agente")
	assert_eq([none[0].value, none[0].label], ["", "Whatever the agent picks"], "y no cambia nada")
	var by_mode := {"ask": {"value": "opus", "name": "Opus"}, "build": {"value": "sonnet", "name": "Sonnet"}, "oneshot": {"value": "opus", "name": "Opus"}}
	var remembered := AgentMainScreen.model_choices({"value": "opus", "name": "Opus"}, {}, by_mode)
	assert_eq(remembered.map(func(item: Dictionary) -> String: return str(item.label)), ["Opus", "Sonnet"], "el recordado primero, sin repetir")
	assert_eq(remembered[0].value, "", "el primero deja el recordado como está")
	var option := {"id": "model", "category": "model", "currentValue": "sonnet", "options": [{"value": "opus", "name": "Opus"}, {"value": "sonnet", "name": "Sonnet"}, {"value": "haiku", "name": "Haiku"}]}
	var live := AgentMainScreen.model_choices({"value": "opus", "name": "Opus"}, option, by_mode)
	assert_eq(live.map(func(item: Dictionary) -> String: return str(item.value)), ["", "sonnet", "haiku"], "con una sesión abierta, los que ofrece")


func test_saved_agent() -> void:
	assert_eq(OneShotRun.saved_agent({"profile": "claude-code", "account": "/c/trabajo"}), {"profile": "claude-code", "account": "/c/trabajo"}, "vuelve tal cual")
	assert_eq(OneShotRun.saved_agent(JSON.parse_string(JSON.stringify({"profile": "x"}))), {"profile": "x", "account": ""}, "sin cuenta, la del perfil")
	assert_eq(OneShotRun.saved_agent(null), {}, "un run viejo: el de la pestaña")
	assert_eq(OneShotRun.saved_agent({"account": "/a"}), {}, "sin perfil, nada")
	var run := OneShotRun.new()
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp")
	run.setup(controller, "/tmp")
	run.agent = {"profile": "codex", "account": ""}
	assert_eq(run.to_dict().get("agent"), {"profile": "codex", "account": ""}, "se guarda con el run")
	run.free()


## El formulario montado: sigue a la pestaña activa hasta que se elige otro agente, lista las cuentas
## del elegido y, al iniciar, pasa la elección al run y recuerda el modelo para el One-shot.
func test_form_agent_choice() -> void:
	var home := ProjectSettings.globalize_path("user://test_oneshot_form_%d" % Time.get_ticks_usec())
	for name: String in ["base", "trabajo"]:
		DirAccess.make_dir_recursive_absolute(home.path_join(name))
	var settings := HarnessSettings.new()
	var claude: AgentProfile = AgentProfile.from_dict(AgentProfile.CLAUDE_CODE.merged({"env": {"CLAUDE_CONFIG_DIR": home.path_join("base")}}))
	var other: AgentProfile = AgentProfile.from_dict({"id": "mio", "display_name": "Mío", "command": "mi-agente"})
	settings.save_profiles([claude, other] as Array[AgentProfile])
	settings.add_account("CLAUDE_CONFIG_DIR", home.path_join("trabajo"))
	ModeModels.new(settings).remember_for("mio", "build", "m-2", "Modelo 2")
	var tab_profile: Array[AgentProfile] = [claude.with_account(home.path_join("trabajo"), "CLAUDE_CONFIG_DIR")]  # el lambda copia los locales
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), home)
	var run := OneShotRun.new()
	run.setup(controller, home)
	var screen: Control = AgentMainScreenScene.instantiate()
	screen.setup(run, Color.WHITE, {})
	screen.agent_settings = settings
	screen.default_profile = func() -> AgentProfile: return tab_profile[0]
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(run)
	tree.root.add_child(screen)
	await tree.process_frame
	var agent_button := screen.find_child("AgentButton", true, false) as OptionButton
	var account_button := screen.find_child("AccountButton", true, false) as OptionButton
	var model_button := screen.find_child("ModelButton", true, false) as OptionButton
	assert_eq(agent_button.get_item_text(agent_button.selected), "Claude Code", "por defecto, el de la pestaña activa")
	assert_true(account_button.visible and account_button.get_item_text(account_button.selected) == "trabajo", "con su cuenta · %s" % account_button.get_item_text(account_button.selected))
	assert_eq(screen.chosen_agent().account, home.path_join("trabajo"), "la cuenta va al run")
	assert_eq([model_button.item_count, model_button.disabled], [1, true], "sin modelos conocidos: el del agente")
	tab_profile[0] = other
	screen.refresh_agent()
	assert_eq(agent_button.get_item_text(agent_button.selected), "Mío", "sin tocarlo, sigue a la pestaña")
	assert_false(account_button.visible, "un agente sin variable de cuentas no muestra la cuenta")
	agent_button.select(0)
	agent_button.item_selected.emit(0)
	account_button.select(0)
	account_button.item_selected.emit(0)
	tab_profile[0] = other
	screen.refresh_agent()
	assert_eq(screen.chosen_agent().profile, "claude-code", "elegido a mano, ya no sigue a la pestaña")
	assert_eq(screen.chosen_agent().account, "", "la cuenta base es la del perfil, sin override")
	agent_button.select(1)
	agent_button.item_selected.emit(1)
	assert_eq(model_button.item_count, 2, "con Mío, el que ya usó en Construir · %d" % model_button.item_count)
	model_button.select(1)
	screen.call(&"_apply_agent_choice")
	assert_eq(run.agent, {"profile": "mio", "account": ""}, "el run se lleva el agente")
	assert_eq(ModeModels.new(settings).get_model("mio", SessionModel.HarnessMode.ONESHOT).get("value"), "m-2", "y el modelo queda recordado para el One-shot")
	screen.free()
	run.free()
