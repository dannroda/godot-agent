extends "test_case.gd"
## Diálogo de Settings (M7): carga, validación, overrides de la matriz y destino de cada valor.

const SettingsDialog := preload("res://addons/godot_agent/ui/settings/settings_dialog.gd")
const HarnessSettings := preload("res://addons/godot_agent/core/harness_settings.gd")
const ProjectConfig := preload("res://addons/godot_agent/config/project_config.gd")
const AgentProfile := preload("res://addons/godot_agent/core/agent_profile.gd")
const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")


func _dialog(config: ProjectConfig = ProjectConfig.new()) -> SettingsDialog:
	var dialog := SettingsDialog.new()
	dialog.setup(HarnessSettings.new(), config)
	(Engine.get_main_loop() as SceneTree).root.add_child(dialog)
	dialog.call(&"_load")
	return dialog


func test_loads_and_validates() -> void:
	var dialog := _dialog()
	assert_true(dialog.validate().is_empty(), "los defaults validan")
	assert_true(dialog.matrix_overrides().is_empty(), "matriz de la spec: sin overrides")
	var profiles: Array = dialog.get(&"_profiles")
	assert_true(profiles.size() >= 1, "carga los perfiles default")

	(profiles[0] as AgentProfile).env = {"ANTHROPIC_API_KEY": "sk-ant-123"}
	var error := dialog.validate()
	assert_eq(error.get("section"), SettingsDialog.Section.AGENTS, "un secreto literal en env no valida")
	assert_true(str(error.get("message")).contains("ANTHROPIC_API_KEY"), "el mensaje nombra la variable")
	(profiles[0] as AgentProfile).env = {"ANTHROPIC_API_KEY": "$ANTHROPIC_API_KEY", "DEBUG": "1"}
	assert_true(dialog.validate().is_empty(), "$VAR sí valida")

	var copy: AgentProfile = AgentProfile.from_dict((profiles[0] as AgentProfile).to_dict())
	profiles.append(copy)
	assert_true(str(dialog.validate().get("message")).contains("dos agentes"), "ids repetidos")
	copy.id = "otro"
	copy.is_default = true
	(profiles[0] as AgentProfile).is_default = true
	assert_true(str(dialog.validate().get("message")).contains("predeterminado"), "un solo predeterminado")
	dialog.call(&"_make_default", 1)
	assert_true(dialog.validate().is_empty(), "_make_default deja uno solo")

	(dialog.get(&"_pause_spin") as SpinBox).value = 50
	(dialog.get(&"_warn_spin") as SpinBox).value = 80
	assert_eq(dialog.validate().get("section"), SettingsDialog.Section.ONESHOT, "pausa por debajo del aviso")
	(dialog.get(&"_pause_check") as CheckBox).button_pressed = false
	assert_true(dialog.validate().is_empty(), "sin pausa no importa el umbral")

	(dialog.get(&"_roots_edit") as TextEdit).text = "/tmp/assets\nrelativa/no"
	assert_eq(dialog.validate().get("section"), SettingsDialog.Section.MCP, "carpetas extra: solo rutas absolutas")
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
