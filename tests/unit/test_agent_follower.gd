extends "test_case.gd"
## Seguir al agente (m11-33): a dónde salta por cada tool call y cuándo espera al usuario.

const AgentFollower := preload("res://addons/godot_agent/editor/agent_follower.gd")
const ToolCall := preload("res://addons/godot_agent/session/tool_call.gd")


func _call(title: String, input: Variant, kind := "other", status := ToolCall.STATUS_COMPLETED) -> ToolCall:
	var call := ToolCall.new()
	call.title = title
	call.kind = kind
	call.status = status
	call.raw_input = input
	return call


func test_only_completed_calls() -> void:
	var call := _call("mcp__godot__add_node", {"scene": "res://main.tscn", "parent": ".", "name": "Enemy"}, "other", ToolCall.STATUS_IN_PROGRESS)
	assert_eq(AgentFollower.target_of(call), {}, "en curso no salta")
	call.status = ToolCall.STATUS_FAILED
	assert_eq(AgentFollower.target_of(call), {}, "fallida no salta")
	assert_eq(AgentFollower.target_of(null), {})


func test_godot_scene_tools() -> void:
	var scene := "res://main.tscn"
	assert_eq(AgentFollower.target_of(_call("mcp__godot__add_node", {"scene": scene, "parent": ".", "name": "Enemy"})),
		{"scene": scene, "node": "Enemy"}, "add_node en la raíz")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__add_node", {"scene": scene, "parent": "World/", "name": "Enemy"})),
		{"scene": scene, "node": "World/Enemy"}, "add_node bajo un nodo")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__set_properties", {"scene": scene, "node_path": "Player"})),
		{"scene": scene, "node": "Player"})
	assert_eq(AgentFollower.target_of(_call("mcp__godot__connect_signal", {"scene": scene, "from": "Button", "to": "."})),
		{"scene": scene, "node": "Button"})
	assert_eq(AgentFollower.target_of(_call("mcp__godot__rename_node", {"scene": scene, "node_path": "World/Old", "new_name": "New"})),
		{"scene": scene, "node": "World/New"}, "rename: el nombre nuevo")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__reparent_node", {"scene": scene, "node_path": "A/B", "new_parent": "C"})),
		{"scene": scene, "node": "C/B"}, "reparent: donde quedó")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__remove_node", {"scene": scene, "node_path": "World/Gone"})),
		{"scene": scene, "node": "World"}, "remove: el padre")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__remove_node", {"scene": scene, "node_path": "Gone"})),
		{"scene": scene, "node": "."}, "remove de un hijo de la raíz: la raíz")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__duplicate_node", {"scene": scene, "node_path": "World/Enemy", "new_name": "Enemy2"})),
		{"scene": scene, "node": "World/Enemy2"}, "duplicate: la copia, junto al original")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__create_scene", {"path": "res://level.tscn"})),
		{"scene": "res://level.tscn", "node": "."})


func test_godot_run_uses_params() -> void:
	var call := _call("mcp__godot__run", {"method": "add_node", "params": {"scene": "res://a.tscn", "parent": ".", "name": "X"}})
	assert_eq(AgentFollower.target_of(call), {"scene": "res://a.tscn", "node": "X"}, "godot.run: los params del método")


func test_godot_file_tools_and_reads() -> void:
	assert_eq(AgentFollower.target_of(_call("mcp__godot__create_resource", {"path": "res://stats.tres", "type": "Resource"})),
		{"path": "res://stats.tres", "line": 0})
	assert_eq(AgentFollower.target_of(_call("mcp__godot__move_file", {"from": "res://a.gd", "to": "res://b.gd"})),
		{"path": "res://b.gd", "line": 0}, "move_file: el destino")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__delete_file", {"path": "res://a.gd"})), {}, "delete_file no abre nada")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__get_scene_tree", {"scene": "res://main.tscn"})), {},
		"una lectura sin path de archivo no salta")
	assert_eq(AgentFollower.target_of(_call("mcp__godot__screenshot", {"path": "res://shot.png"})), {},
		"un path que no es script ni escena no salta")


func test_agent_edits_jump_to_changed_line() -> void:
	var call := _call("Edit", {}, "edit")
	call.content = [{"type": "diff", "path": "/p/player.gd", "oldText": "a\nb\nc", "newText": "a\nB\nc"}]
	assert_eq(AgentFollower.target_of(call), {"path": "/p/player.gd", "line": 2}, "la primera línea distinta")
	call.locations = [{"path": "/p/player.gd", "line": 7}]
	assert_eq(AgentFollower.target_of(call), {"path": "/p/player.gd", "line": 7}, "la línea que trae la location")
	var read := _call("Read", {}, "read")
	read.locations = [{"path": "/p/player.gd", "line": 3}]
	assert_eq(AgentFollower.target_of(read), {}, "leer no salta")
	var removed := _call("rm", {}, "delete")
	removed.locations = [{"path": "/p/old.gd"}]
	assert_eq(AgentFollower.target_of(removed), {}, "un archivo borrado no se abre")


## Un follower con el foco en un texto fuera del dock.
class TypingFollower extends AgentFollower:
	var field := TextEdit.new()
	func _focus_owner() -> Control:
		return field


func test_waits_while_user_busy() -> void:
	var follower := AgentFollower.new()
	var clock := [10000]
	follower.now_ms = func() -> int: return clock[0]
	assert_false(follower.user_busy(), "sin input reciente no está ocupado")
	var key := InputEventKey.new()
	key.pressed = true
	follower._input(key)
	assert_true(follower.user_busy(), "acaba de tocar una tecla fuera del dock")
	follower.follow(_call("mcp__godot__set_properties", {"scene": "res://main.tscn", "node_path": "Player"}))
	assert_eq(follower.get(&"_pending"), {"scene": "res://main.tscn", "node": "Player"}, "el salto queda pendiente")
	follower.follow(_call("mcp__godot__set_properties", {"scene": "res://main.tscn", "node_path": "Enemy"}))
	assert_eq(follower.get(&"_pending"), {"scene": "res://main.tscn", "node": "Enemy"}, "queda el último")
	clock[0] += int(AgentFollower.IDLE_S * 1000.0) + 1
	assert_false(follower.user_busy(), "pasado IDLE_S ya no")
	follower.cancel()
	assert_eq(follower.get(&"_pending"), {}, "cancel descarta lo pendiente")
	follower.free()
	# Con el foco en un texto fuera del dock: espera hasta WRITING_IDLE_S, no para siempre.
	var writing := TypingFollower.new()
	writing.now_ms = func() -> int: return clock[0]
	writing._input(key)
	clock[0] += int(AgentFollower.IDLE_S * 1000.0) + 1
	assert_true(writing.user_busy(), "parado a mitad de escribir: espera")
	clock[0] = writing.get(&"_last_outside_input_ms") + int(AgentFollower.WRITING_IDLE_S * 1000.0)
	assert_false(writing.user_busy(), "un foco que quedó en un texto sin que nadie lo toque no frena para siempre")
	writing.field.free()
	writing.free()
