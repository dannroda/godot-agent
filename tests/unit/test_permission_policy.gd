extends "test_case.gd"
## Matriz de permisos (spec §7).

const PermissionPolicy := preload("res://addons/godot_agent/session/permission_policy.gd")
const SessionModel := preload("res://addons/godot_agent/session/session_model.gd")

const M := SessionModel.HarnessMode


func test_default_matrix() -> void:
	var policy := PermissionPolicy.new()
	var expected := {
		"read": ["allow", "allow", "allow", "allow", "allow"],
		"diagnostics": ["allow", "allow", "allow", "allow", "allow"],
		"edit_scene": ["deny", "deny", "ask", "allow", "allow"],
		"edit_files": ["deny", "deny", "ask", "allow", "allow"],
		"run": ["deny", "ask", "ask", "allow", "allow"],
		"shell": ["deny", "deny", "ask", "ask", "ask"],
		"project": ["deny", "deny", "ask", "allow", "allow"],
	}
	for group: String in expected:
		for mode: int in [M.ASK, M.REVIEW, M.BUILD, M.ONESHOT, M.AUTO]:
			assert_eq(policy.decide(group, mode), expected[group][mode], "%s/%d" % [group, mode])
	assert_eq(policy.decide("other", M.ONESHOT), "ask", "grupo desconocido → ask")


func test_session_grant_only_lifts_ask() -> void:
	var policy := PermissionPolicy.new()
	policy.grant_for_session("edit_files")
	assert_eq(policy.decide("edit_files", M.BUILD), "allow", "ask → allow con permiso de sesión")
	assert_eq(policy.decide("edit_files", M.ASK), "deny", "deny no se levanta")
	policy.clear_session()
	assert_eq(policy.decide("edit_files", M.BUILD), "ask", "se olvida con la sesión")


func test_overrides() -> void:
	var policy := PermissionPolicy.new({"run": {"build": "allow"}, "shell": {"oneshot": "cualquiera"}})
	assert_eq(policy.decide("run", M.BUILD), "allow", "override válido")
	assert_eq(policy.decide("shell", M.ONESHOT), "ask", "override inválido se ignora")
	policy.set_matrix_value("read", M.ASK, "deny")
	assert_eq(policy.decide("read", M.ASK), "deny", "set_matrix_value")


func test_kind_mapping() -> void:
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "read"}), "read", "read")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "search"}), "read", "search")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "edit"}), "edit_files", "edit")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "move"}), "edit_files", "move")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "delete"}), "edit_files", "delete")
	# Antigravity (m18-02): `godot_run_scene` con el server en _meta.mcp. El del addon lo decide el
	# server MCP; uno de terceros va a su grupo.
	var agy_godot := {"title": "godot_run_scene", "kind": "other", "_meta": {"mcp": {"tool": "run_scene", "server": "godot"}, "is_mcp_tool_call": true}}
	assert_true(PermissionPolicy.is_godot_mcp_tool(agy_godot), "Antigravity: una tool del addon")
	assert_eq(PermissionPolicy.mcp_server_of(agy_godot), "", "el addon no es un server de terceros")
	var agy_blender := {"title": "blender_get_scene", "kind": "other", "_meta": {"mcp": {"tool": "get_scene", "server": "blender"}}}
	assert_false(PermissionPolicy.is_godot_mcp_tool(agy_blender), "Antigravity: una de terceros no es del addon")
	assert_eq(PermissionPolicy.group_for_tool_call(agy_blender), PermissionPolicy.mcp_group("blender"), "va al grupo de su server")
	assert_false(PermissionPolicy.is_godot_mcp_tool({"title": "godot_thing", "kind": "other"}), "sin _meta no se adivina por el título")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "execute"}), "shell", "execute")
	assert_eq(PermissionPolicy.group_for_tool_call({"kind": "fetch"}), "other", "fetch → other")
	assert_true(PermissionPolicy.is_godot_mcp_tool({"title": "mcp__godot__scene_tree"}), "tool del server godot")
	assert_false(PermissionPolicy.is_godot_mcp_tool({"title": "Bash"}), "otra tool")


func test_auto_overrides() -> void:
	var policy := PermissionPolicy.new({"shell": {"auto": "deny"}, "run": {"auto": "ask"}})
	assert_eq(policy.decide("shell", M.AUTO), "deny", "override de Auto")
	assert_eq(policy.decide("run", M.AUTO), "ask", "run en Auto con override")
	assert_eq(policy.decide("run", M.ONESHOT), "allow", "no toca One-shot")
	policy.set_matrix_value("edit_files", M.AUTO, "ask")
	assert_eq(policy.overrides.edit_files, {"auto": "ask"}, "se guarda con la clave auto")


## Antigravity (m18-02) titula sus tools MCP `<server>_<tool>`: en la UI se muestran como `server.tool`
## con lo que dice `_meta.mcp`.
func test_antigravity_tool_display_name() -> void:
	var ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")
	var call := ToolCall.new()
	call.apply({"toolCallId": "t1", "title": "godot_run_scene", "_meta": {"mcp": {"tool": "run_scene", "server": "godot"}, "is_mcp_tool_call": true}})
	assert_eq(call.display_name(), "godot.run_scene", "nombre de _meta.mcp")
	var plain := ToolCall.new()
	plain.apply({"toolCallId": "t2", "title": "mcp__blender__get_scene"})
	assert_eq(plain.display_name(), "blender.get_scene", "Claude Code sigue igual")
