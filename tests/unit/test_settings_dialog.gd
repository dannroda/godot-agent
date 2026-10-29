extends "test_case.gd"
## Diálogo de Settings (M7): carga, validación, overrides de la matriz y destino de cada valor.

const SettingsDialog := preload("res://addons/godot_agent/ui/settings/settings_dialog.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const ProjectConfig := preload("res://addons/godot_agent/config/project_config.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")


## Sin agentes preseteados: los tests cargan tres a mano.
func _dialog(config: ProjectConfig = ProjectConfig.new(), with_agents := true) -> SettingsDialog:
	var settings := HarnessSettings.new()
	if with_agents:
		var list: Array[AgentProfile] = []
		for id: String in ["claude-code", "gemini", "codex"]:
			list.append(AgentProfile.from_dict(AgentProfile.CLAUDE_CODE.merged({"id": id, "default": id == "claude-code"}, true)))
		settings.save_profiles(list)
	var dialog := SettingsDialog.new()
	dialog.setup(settings, config)
	(Engine.get_main_loop() as SceneTree).root.add_child(dialog)
	dialog.call(&"_load")
	return dialog


func test_no_agents_preset() -> void:
	var dialog := _dialog(ProjectConfig.new(), false)
	assert_true((dialog.get(&"_profiles") as Array).is_empty(), "primer arranque: sin agentes")
	assert_true(dialog.validate().is_empty(), "sin agentes se puede guardar el resto")
	dialog.free()


func test_loads_and_validates() -> void:
	var dialog := _dialog()
	assert_true(dialog.validate().is_empty(), "los defaults validan")
	assert_true(dialog.matrix_overrides().is_empty(), "matriz de la spec: sin overrides")
	var profiles: Array = dialog.get(&"_profiles")
	assert_true(profiles.size() >= 1, "carga los perfiles guardados")

	(profiles[0] as AgentProfile).env = {"ANTHROPIC_API_KEY": "sk-ant-123"}
	var error := dialog.validate()
	assert_eq(error.get("section"), SettingsDialog.SettingsSection.AGENTS, "un secreto literal en env no valida")
	assert_true(str(error.get("message")).contains("ANTHROPIC_API_KEY"), "el mensaje nombra la variable")
	(profiles[0] as AgentProfile).env = {"ANTHROPIC_API_KEY": "$ANTHROPIC_API_KEY", "DEBUG": "1"}
	assert_true(dialog.validate().is_empty(), "$VAR sí valida")

	var copy: AgentProfile = AgentProfile.from_dict((profiles[0] as AgentProfile).to_dict())
	profiles.append(copy)
	assert_true(str(dialog.validate().get("message")).contains("Two agents"), "ids repetidos")
	copy.id = "otro"
	copy.is_default = true
	(profiles[0] as AgentProfile).is_default = true
	assert_true(str(dialog.validate().get("message")).contains("default"), "un solo predeterminado")
	dialog.call(&"_make_default", 1)
	assert_true(dialog.validate().is_empty(), "_make_default deja uno solo")

	(dialog.get(&"_pause_spin") as SpinBox).value = 50
	(dialog.get(&"_warn_spin") as SpinBox).value = 80
	assert_eq(dialog.validate().get("section"), SettingsDialog.SettingsSection.ONESHOT, "pausa por debajo del aviso")
	(dialog.get(&"_pause_check") as CheckBox).button_pressed = false
	assert_true(dialog.validate().is_empty(), "sin pausa no importa el umbral")

	(dialog.get(&"_roots_edit") as TextEdit).text = "/tmp/assets\nrelativa/no"
	assert_eq(dialog.validate().get("section"), SettingsDialog.SettingsSection.MCP, "carpetas extra: solo rutas absolutas")
	dialog.free()


func test_matrix_overrides() -> void:
	var config := ProjectConfig.new()
	config.permissions = {PermissionPolicy.GROUP_SHELL: {"build": PermissionPolicy.ALLOW}}
	var dialog := _dialog(config)
	var matrix: Dictionary = dialog.get(&"_matrix")
	var shell_build: OptionButton = matrix[PermissionPolicy.GROUP_SHELL][SessionModel.HarnessMode.BUILD]
	assert_eq(SettingsDialog.DECISIONS[shell_build.selected], PermissionPolicy.ALLOW, "carga el override del proyecto")
	assert_eq(dialog.matrix_overrides(), {PermissionPolicy.GROUP_SHELL: {"build": PermissionPolicy.ALLOW}}, "lo devuelve igual")

	var read_ask: OptionButton = matrix[PermissionPolicy.GROUP_READ][SessionModel.HarnessMode.ASK]
	read_ask.select(SettingsDialog.DECISIONS.find(PermissionPolicy.DENY))
	var overrides := dialog.matrix_overrides()
	assert_eq(overrides.get(PermissionPolicy.GROUP_READ), {"ask": PermissionPolicy.DENY}, "solo guarda lo que difiere")
	var policy := PermissionPolicy.new(overrides)
	assert_eq(policy.matrix_value(PermissionPolicy.GROUP_READ, SessionModel.HarnessMode.ASK), PermissionPolicy.DENY, "la política lee el override")

	dialog.call(&"_load_matrix", {})
	assert_true(dialog.matrix_overrides().is_empty(), "volver a la spec limpia los overrides")
	dialog.free()


func test_profile_form_round_trip() -> void:
	var dialog := _dialog()
	dialog.call(&"_edit_profile", 0)
	var fields: Dictionary = dialog.get(&"_form_fields")
	(fields.command as LineEdit).text = "  npx  "
	(fields.args as TextEdit).text = "-y\n\n  @agentclientprotocol/claude-agent-acp  \n"
	(fields.env as TextEdit).text = "ANTHROPIC_API_KEY=$MI_CLAVE\nsin_igual\nDEBUG = 1"
	dialog.call(&"_apply_profile_form")
	var profile: AgentProfile = (dialog.get(&"_profiles") as Array)[0]
	assert_eq(profile.command, "npx", "recorta el comando")
	assert_eq(profile.args, PackedStringArray(["-y", "@agentclientprotocol/claude-agent-acp"]), "args: uno por línea, sin vacías")
	assert_eq(profile.env, {"ANTHROPIC_API_KEY": "$MI_CLAVE", "DEBUG": "1"}, "env: CLAVE=valor, ignora líneas sin =")
	assert_false((dialog.get(&"_profile_form") as Control).visible, "cierra el formulario")

	# Quitar un perfil de más arriba mientras se edita otro: el formulario sigue apuntando al mismo.
	var profiles: Array = dialog.get(&"_profiles")
	var target: AgentProfile = profiles[2]
	dialog.call(&"_edit_profile", 2)
	(fields.display_name as LineEdit).text = "Renombrado"
	dialog.call(&"_remove_profile", 0)
	dialog.call(&"_apply_profile_form")
	assert_eq(target.display_name, "Renombrado", "editar sobrevive a quitar uno de arriba")
	dialog.free()


func test_completion_section() -> void:
	var dialog := _dialog()
	var page: Node = dialog.get(&"_completion_page")
	var profiles: Array = page.call(&"profiles")
	assert_eq(profiles.size(), 1, "carga el perfil LLM default (Ollama)")
	assert_true(dialog.validate().is_empty(), "los defaults del completado validan")

	# Una key pegada en el campo de la variable no se acepta: el harness no guarda claves.
	page.call(&"_edit_profile", 0)
	var fields: Dictionary = page.get(&"_form_fields")
	(fields.api_key_env as LineEdit).text = "sk-abc123-pegada"
	var error := dialog.validate()
	assert_eq(error.get("section"), SettingsDialog.SettingsSection.COMPLETION, "valida la sección Completado")
	assert_true(str(error.get("message")).contains("environment variable"), "explica qué va en el campo")
	page.call(&"_edit_profile", 0)
	(fields.api_key_env as LineEdit).text = "AIzaSyD4x9Qw2LmB7kTr0pZ3vN8cYh1Ue6sJfGo"
	assert_eq(dialog.validate().get("section"), SettingsDialog.SettingsSection.COMPLETION, "una key sin guiones tampoco")
	page.call(&"_edit_profile", 0)
	(fields.api_key_env as LineEdit).text = "$MISTRAL_API_KEY"
	(fields.stops as TextEdit).text = "\\n\\n\nfunc "
	(fields.url as LineEdit).text = "https://api.mistral.ai"
	page.call(&"apply_form")
	var profile: RefCounted = profiles[0]
	assert_eq(profile.get(&"api_key_env"), "MISTRAL_API_KEY", "acepta el nombre con o sin $")
	assert_eq(profile.get(&"stops"), PackedStringArray(["\n\n", "func "]), "stops con escapes, uno por línea")
	assert_true(dialog.validate().is_empty(), "un nombre de variable valida")
	var codestral: RefCounted = preload("res://addons/godot_agent/completion/llm/llm_profile.gd").make("codestral")
	codestral.set(&"api_key_env", "")
	profiles.append(codestral)
	assert_true(str(dialog.validate().get("message")).contains("needs the name"), "codestral sin variable no valida")
	profiles.pop_back()
	assert_true(_has_text(page.get(&"_profile_list") as Node, "api.mistral.ai"), "avisa que un perfil remoto envía código")

	# CRUD: agregar otro del mismo tipo le da un id libre; quitar el activo pasa al siguiente.
	(page.get(&"_kind_option") as OptionButton).select(0)
	for button: Node in page.find_children("*", "Button", true, false):
		if (button as Button).text == "+ Add profile":
			(button as Button).pressed.emit()
	page.call(&"apply_form")
	assert_eq(profiles.size(), 2, "agrega un perfil")
	assert_eq(profiles[1].get(&"id"), "ollama-2", "id libre")
	page.call(&"_make_active", 1)
	page.call(&"_remove_profile", 1)
	assert_eq(page.get(&"_active_id"), profiles[0].get(&"id"), "quitar el activo activa otro")
	page.call(&"_remove_profile", 0)
	(page.get(&"_mode_option") as OptionButton).select(1)
	assert_true(str(dialog.validate().get("message")).contains("need an LLM profile"), "híbrido sin perfiles no valida")
	(page.get(&"_mode_option") as OptionButton).select(0)
	(page.get(&"_corpus_edit") as TextEdit).text = "relativa/no"
	assert_eq(dialog.validate().get("section"), SettingsDialog.SettingsSection.COMPLETION, "corpus extra: rutas absolutas")
	dialog.free()


func test_completion_save() -> void:
	var settings := HarnessSettings.new()
	var config := ProjectConfig.new()
	var page: Node = preload("res://addons/godot_agent/ui/settings/completion_settings_page.gd").new()
	page.set(&"metrics_provider", func() -> Array[Dictionary]:
		return [{"source": "llm", "p50": 210.0, "p95": 480.0, "shown": 4, "accepted": 1, "acceptance": 0.25, "errors": 2}] as Array[Dictionary])
	page.call(&"load_from", settings, config)
	assert_true(_has_text(page.get(&"_metrics_grid") as Node, "1 (25 %)"), "tabla de contadores por fuente")
	(page.get(&"_mode_option") as OptionButton).select(1)
	(page.get(&"_project_check") as CheckBox).button_pressed = false
	(page.get(&"_exclude_edit") as TextEdit).text = "addons/\n  vendor/  \n"
	(page.get(&"_llm_debounce_spin") as SpinBox).value = 350
	(page.get(&"_raw_check") as CheckBox).button_pressed = true
	(page.get(&"_source_checks") as Dictionary)["ngram"].button_pressed = false
	page.call(&"save_to", settings, config)
	assert_eq(settings.completion_mode(), "hybrid", "modo híbrido")
	assert_eq(settings.llm_debounce_ms(), 350, "debounce del LLM")
	assert_true(settings.completion_log_raw(), "log raw")
	assert_false(bool(settings.completion_sources().ngram), "fuente apagada")
	assert_eq(settings.active_llm_profile().id, "ollama", "perfil activo")
	assert_false(config.completion_enabled, "on/off del proyecto va a la config")
	assert_eq(config.completion_exclude, PackedStringArray(["addons/", "vendor/"]), "exclusiones del proyecto")
	page.free()


func _has_text(root: Node, needle: String) -> bool:
	for label: Node in root.find_children("*", "Label", true, false):
		if (label as Label).text.contains(needle):
			return true
	return false


## m12-37: Gemini CLI y el Codex sin comando de 0.1.7 se quitan una vez; uno editado se queda.
func test_retire_old_presets() -> void:
	var settings := HarnessSettings.new()
	var list: Array[AgentProfile] = []
	list.append(AgentProfile.from_dict(AgentProfile.CLAUDE_CODE.merged({"env": {}, "default": true})))
	list.append(AgentProfile.from_dict({"id": "gemini-cli", "display_name": "Gemini CLI", "command": "gemini", "args": [], "env": {}, "default": false}))
	list.append(AgentProfile.from_dict({"id": "codex", "display_name": "Codex", "command": "codex-acp", "args": [], "env": {}, "default": false}))
	settings.save_profiles(list)
	settings.set_active_profile("gemini-cli")
	assert_eq(Array(settings.retire_old_presets()), ["Gemini CLI"], "quita solo el preset sin editar")
	var ids: Array = []
	for profile: AgentProfile in settings.profiles():
		ids.append(profile.id)
	assert_eq(ids, ["claude-code", "codex"], "el Codex con comando se queda")
	assert_eq(settings.active_profile().id, "claude-code", "el activo quitado vuelve al default")
	list.append(AgentProfile.from_dict({"id": "gemini-cli", "display_name": "Gemini CLI", "command": "gemini"}))
	settings.save_profiles(list)
	assert_true(settings.retire_old_presets().is_empty(), "una sola vez")
