extends "test_case.gd"
## El modelo de cada modo del harness, por perfil (m11-38, absorbe m11-27): la tienda, la opción del
## modelo por category o id, y el controller: cambiar de modo pide el modelo recordado antes que el
## modo del agente, elegir en el selector lo recuerda y el cambio automático no, un valor que el agente
## ya no ofrece no se manda, y «Aprobar y construir» pide el modelo de Construir sin set_mode.

const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const ModeModels := preload("res://addons/godot_agent/core/mode_models.gd")
const SessionController := preload("res://addons/godot_agent/session/session_controller.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")
const ChatEntry := preload("res://addons/godot_agent/session/chat_entry.gd")

const M := SessionModel.HarnessMode
const FIXTURE := "res://tests/fixtures/acp/exit_plan_mode_0105.json"
## Como la configOption de claude-agent-acp 0.106 (session-model.js buildModelConfigOption).
const MODEL_OPTION := {"id": "model", "name": "Model", "category": "model", "type": "select", "currentValue": "default",
	"options": [{"value": "default", "name": "Default (recommended)", "description": "Opus 5.5"}, {"value": "opus", "name": "Opus"},
		{"value": "sonnet", "name": "Sonnet"}, {"value": "haiku", "name": "Haiku"}]}


func _store() -> ModeModels:
	return ModeModels.new(HarnessSettings.new())  # sin EditorSettings: en memoria


func _controller(store: ModeModels, sent: Array, mode: SessionModel.HarnessMode = M.BUILD, options: Array = [MODEL_OPTION]) -> SessionController:
	var controller := SessionController.new()
	controller.setup(SessionModel.new(), AgentLog.new(), "/tmp/project")
	controller.model.set_harness_mode(mode)
	controller.model.session_id = "session-0001"
	controller.model.agent_modes = [{"id": "default"}, {"id": "acceptEdits"}, {"id": "plan"}]
	controller.model.current_agent_mode = SessionController.AGENT_MODE_FOR[mode][0]
	controller.model.config_options = options.duplicate(true)
	var profile := AgentProfile.new()
	profile.id = "claude-code"
	controller.set(&"_profile", profile)
	controller.mode_models = store
	controller.client.setup(func(line: String) -> bool:
		sent.append(JSON.parse_string(line))
		return true, controller.agent_log)
	return controller


## Contesta el último request `method` sin respuesta, con `result`.
func _reply(controller: SessionController, sent: Array, method: String, result: Dictionary = {}) -> void:
	for message: Variant in sent:
		if message is Dictionary and message.get("method") == method and not message.has("_answered"):
			message["_answered"] = true
			controller.client.receive_line(JSON.stringify({"jsonrpc": "2.0", "id": message.id, "result": result}))
			return


static func _methods(sent: Array) -> Array:
	return sent.map(func(message: Variant) -> String: return str(message.get("method", "")) if message is Dictionary else "")


static func _model_requests(sent: Array) -> Array:
	return sent.filter(func(m: Variant) -> bool: return m is Dictionary and m.get("method") == "session/set_config_option").map(func(m: Dictionary) -> String: return str(m.params.value))


func _frames(n: int = 2) -> void:
	for i: int in n:
		await Engine.get_main_loop().process_frame


func _notices(controller: SessionController, text: String) -> Array:
	return controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.NOTICE and e.text.contains(text))


func test_store() -> void:
	var store := _store()
	assert_eq(store.get_model("claude-code", M.ASK), {}, "nada recordado")
	store.remember("claude-code", M.ASK, "opus", "Opus")
	store.remember("claude-code", M.BUILD, "sonnet", "Sonnet")
	store.remember("codex", M.ASK, "gpt-5", "")
	assert_eq(store.get_model("claude-code", M.ASK), {"value": "opus", "name": "Opus"}, "por perfil y modo")
	assert_eq(store.get_model("codex", M.ASK), {"value": "gpt-5", "name": "gpt-5"}, "sin nombre, el valor")
	assert_eq(store.get_model("claude-code", M.ONESHOT), {}, "One-shot es un modo más: vacío hasta elegir")
	store.remember("claude-code", M.ONESHOT, "haiku", "Haiku")
	assert_eq(str(store.get_model("claude-code", M.ONESHOT).value), "haiku", "y se recuerda")
	store.remember("claude-code", M.ASK, "", "")
	assert_eq(str(store.get_model("claude-code", M.ASK).value), "opus", "un valor vacío no pisa")
	store.forget("claude-code", M.ASK)
	assert_eq(store.get_model("claude-code", M.ASK), {}, "olvidado")
	assert_eq(str(store.get_model("claude-code", M.BUILD).value), "sonnet", "los otros modos siguen")
	store.forget("codex", M.ASK)
	assert_false(store.settings.call(&"get_value", ModeModels.KEY, {}).has("codex"), "un perfil sin modos se borra")
	assert_eq(ModeModels.MODE_KEYS.size(), M.size(), "una clave por modo")
	assert_eq(ModeModels.new().get_model("claude-code", M.ASK), {}, "sin tienda, nada")


func test_model_option() -> void:
	assert_eq(ModeModels.model_option([{"id": "mode"}, MODEL_OPTION]).id, "model", "por category")
	var codex := {"id": "model_choice", "category": "model", "options": []}
	assert_eq(ModeModels.model_option([{"id": "model", "options": []}, codex]).id, "model_choice", "category gana sobre el id")
	assert_eq(ModeModels.model_option([{"id": "model", "options": []}]).id, "model", "sin category, por id")
	assert_eq(ModeModels.model_option([{"id": "effort", "category": "thought_level"}]), {}, "sin modelo")
	assert_eq(ModeModels.option_name(MODEL_OPTION, "sonnet"), "Sonnet", "nombre")
	assert_true(ModeModels.offers(MODEL_OPTION, "haiku") and not ModeModels.offers(MODEL_OPTION, "gpt-5"), "lo ofrece o no")


func test_mode_change_sends_the_model_before_the_mode() -> void:
	var store := _store()
	store.remember("claude-code", M.ASK, "opus", "Opus")
	var sent: Array = []
	var controller := _controller(store, sent, M.BUILD)
	controller.model.set_harness_mode(M.ASK)
	assert_eq(_methods(sent), ["session/set_config_option", "session/set_mode"], "primero el modelo, después el modo")
	assert_eq(sent[0].params, {"sessionId": "session-0001", "configId": "model", "value": "opus"}, "el recordado para Preguntar")
	assert_true(controller.get(&"_mode_syncs_running") > 0, "el próximo prompt espera")
	_reply(controller, sent, "session/set_config_option")
	_reply(controller, sent, "session/set_mode")
	await _frames()
	assert_eq(str(controller.model.model_option().currentValue), "opus", "el chip lo muestra")
	assert_eq(controller.get(&"_mode_syncs_running"), 0, "terminó")
	assert_eq(_notices(controller, "Ask uses Opus").size(), 1, "aviso de una línea")
	var notice: ChatEntry = _notices(controller, "Ask uses Opus")[0]
	assert_eq(notice.actions[0].id, SessionController.ACTION_CHOOSE_MODEL, "con «Cambiar»")
	assert_eq(str(store.get_model("claude-code", M.BUILD).get("value", "")), "", "el cambio automático no se recuerda como elección")
	# Volver a Construir sin nada recordado ahí: no toca el modelo.
	sent.clear()
	controller.model.set_harness_mode(M.BUILD)
	assert_eq(_model_requests(sent), [], "Construir sin modelo recordado no lo cambia")
	assert_true(controller.model_tooltip().contains("remembered for Build"), "el tooltip dice para qué modo se recuerda: %s" % controller.model_tooltip())


func test_choose_remembers_for_the_current_mode() -> void:
	var store := _store()
	var sent: Array = []
	var controller := _controller(store, sent, M.BUILD)
	var run := func() -> void: await controller.choose_model("sonnet")
	run.call()
	assert_eq(_model_requests(sent), ["sonnet"], "se manda")
	_reply(controller, sent, "session/set_config_option")
	await _frames()
	assert_eq(store.get_model("claude-code", M.BUILD), {"value": "sonnet", "name": "Sonnet"}, "recordado para Construir con su nombre")
	assert_true(controller.model_tooltip().contains("Remembered for Build"), "tooltip: %s" % controller.model_tooltip())
	# Elegir en Preguntar y volver: cada modo con el suyo, el aviso una sola vez por pestaña.
	controller.model.set_harness_mode(M.ASK)
	assert_eq(_model_requests(sent), ["sonnet"], "Preguntar sin recordado: nada")
	run = func() -> void: await controller.choose_model("opus")
	run.call()
	_reply(controller, sent, "session/set_mode")
	_reply(controller, sent, "session/set_config_option")
	await _frames()
	controller.model.set_harness_mode(M.BUILD)
	assert_eq(_model_requests(sent), ["sonnet", "opus", "sonnet"], "volver a Construir vuelve a Sonnet")
	_reply(controller, sent, "session/set_config_option")
	controller.model.set_harness_mode(M.ASK)
	_reply(controller, sent, "session/set_config_option")
	await _frames()
	assert_eq(_model_requests(sent), ["sonnet", "opus", "sonnet", "opus"], "y a Preguntar, a Opus")
	var uses := controller.model.entries().filter(func(e: ChatEntry) -> bool: return e.kind == ChatEntry.EntryKind.NOTICE and e.text.contains(" uses "))
	assert_eq(uses.size(), 1, "el aviso, una vez por pestaña")


func test_value_the_agent_no_longer_offers() -> void:
	var store := _store()
	store.remember("claude-code", M.ASK, "claude-old-1", "Old")
	var sent: Array = []
	var controller := _controller(store, sent, M.BUILD)
	controller.model.set_harness_mode(M.ASK)
	assert_eq(_model_requests(sent), [], "no se manda")
	assert_eq(_methods(sent), ["session/set_mode"], "el modo sí")
	assert_eq(_notices(controller, "«Old»").size(), 1, "avisa")
	controller.model.set_harness_mode(M.BUILD)
	controller.model.set_harness_mode(M.ASK)
	assert_eq(_notices(controller, "«Old»").size(), 1, "una vez por pestaña")
	assert_eq(str(store.get_model("claude-code", M.ASK).value), "claude-old-1", "queda guardado por si vuelve")


func test_agent_without_a_model_option() -> void:
	var store := _store()
	store.remember("claude-code", M.ASK, "opus", "Opus")
	var sent: Array = []
	var controller := _controller(store, sent, M.BUILD, [{"id": "effort", "category": "thought_level", "options": []}])
	controller.model.set_harness_mode(M.ASK)
	assert_eq(_model_requests(sent), [], "sin la opción no se manda nada")
	assert_false(await controller.choose_model("opus"), "ni se elige")
	assert_eq(controller.model_tooltip(), "", "ni tooltip")
	var none: Array = []
	var bare := _controller(null, none, M.BUILD)
	bare.model.set_harness_mode(M.ASK)
	assert_eq(_model_requests(none), [], "sin tienda (otros usos del controller), tampoco")


func test_approve_and_build_switches_the_model_in_the_turn() -> void:
	var store := _store()
	store.remember("claude-code", M.BUILD, "sonnet", "Sonnet")
	var sent: Array = []
	var controller := _controller(store, sent, M.ASK)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var results: Array = []
	var ask := func() -> void: results.append(await controller.permissions.on_request_permission(fixture.request))
	ask.call()
	var dir := ProjectSettings.globalize_path("user://").path_join("mode_models_%d" % Time.get_ticks_usec())
	controller.cwd = dir
	controller.approve_plan(controller.model.pending_permissions[0])
	assert_eq(controller.model.harness_mode, M.BUILD, "pasa a Construir")
	assert_eq(_model_requests(sent), ["sonnet"], "el modelo de Construir, en medio del turno")
	assert_false("session/set_mode" in _methods(sent), "sin set_mode: el adapter sale solo de plan")
	_reply(controller, sent, "session/set_config_option")
	await _frames()
	assert_eq(str(controller.model.model_option().currentValue), "sonnet", "aplicado")
