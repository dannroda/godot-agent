extends "test_case.gd"
## m11-79: el detector de loops de todas las tools godot.*, en el ToolRegistry (por sesión y por
## turno), y lo que el One-shot hace con lo que avisa.

const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")
const AgentLog := preload("res://addons/godot_agent/core/agent_log.gd")
const ToolLoopGuard := preload("res://addons/godot_agent/mcp/tool_loop_guard.gd")
const LoopDetector := preload("res://addons/godot_agent/oneshot/loop_detector.gd")


func _registry(answers: Dictionary) -> ToolRegistry:
	var registry := ToolRegistry.new()
	registry.agent_log = AgentLog.new()
	registry.register(McpTool.create("read_thing", "read", "Lee", {"path": {"type": "string"}}, [],
		func(args: Dictionary) -> String: return str(answers.get(str(args.get("path", "")), "nothing"))))
	registry.register(McpTool.create("fail_thing", "read", "Falla", {}, [],
		func(_args: Dictionary) -> Dictionary: return McpTool.error("It broke")))
	return registry


static func _warned(result: Dictionary) -> bool:
	return (result.content as Array).any(func(block: Dictionary) -> bool: return str(block.get("text", "")).begins_with("Harness: you made the same godot.* call"))


func test_same_call_same_result_warns_once_per_streak() -> void:
	var registry := _registry({"a": "A"})
	var loops: Array = []
	registry.tool_loop.connect(func(caller: String, seen: Dictionary) -> void: loops.append([caller, seen]))
	assert_false(_warned(await registry.call_tool("read_thing", {"path": "a"})), "1")
	assert_false(_warned(await registry.call_tool("read_thing", {"path": "a"})), "2")
	var third: Dictionary = await registry.call_tool("read_thing", {"path": "a"})
	assert_true(_warned(third), "a la tercera, el resultado avisa")
	assert_eq(str(third.content[0].text), "A", "el resultado de la tool sigue primero")
	assert_true(str(third.content.back().text).contains("read_thing") and str(third.content.back().text).contains("3 times"), "nombra la tool y las vueltas: %s" % third.content.back().text)
	assert_eq(loops.size(), 1, "la señal para el One-shot sale una vez")
	assert_true(_warned(await registry.call_tool("read_thing", {"path": "a"})), "la cuarta también avisa")
	assert_eq(loops.size(), 1, "pero la señal no se repite en la misma racha")
	assert_eq(str(loops[0][0]), "", "con la sesión que llamó")
	assert_eq(str(loops[0][1].tools), "read_thing", "y lo que repetía")


func test_progress_and_other_calls() -> void:
	var answers := {"a": "A"}
	var registry := _registry(answers)
	await registry.call_tool("read_thing", {"path": "a"})
	await registry.call_tool("read_thing", {"path": "a"})
	answers.a = "A2"
	assert_false(_warned(await registry.call_tool("read_thing", {"path": "a"})), "el resultado cambió: hay progreso")
	await registry.call_tool("read_thing", {"path": "a"})
	assert_false(_warned(await registry.call_tool("read_thing", {"path": "b"})), "otra llamada corta la racha")


func test_cycle_and_errors() -> void:
	var registry := _registry({"a": "A", "b": "B"})
	var result: Dictionary = {}
	for i in 3:
		await registry.call_tool("read_thing", {"path": "a"})
		result = await registry.call_tool("read_thing", {"path": "b"})
	assert_true(_warned(result), "A → B tres vueltas: ciclo")
	assert_true(str(result.content.back().text).contains("calls (read_thing → read_thing)"), "en plural, con el ciclo: %s" % result.content.back().text)
	var failing := _registry({})
	await failing.call_tool("fail_thing", {})
	await failing.call_tool("fail_thing", {})
	var third: Dictionary = await failing.call_tool("fail_thing", {})
	assert_true(third.isError and _warned(third), "el mismo error tres veces también")


func test_per_session_and_turn() -> void:
	var registry := _registry({"a": "A"})
	await registry.call_tool("read_thing", {"path": "a"})
	await registry.call_tool("read_thing", {"path": "a"})
	assert_false(_warned(await registry.call_tool("read_thing", {"path": "a"}, "s2")), "otra sesión tiene su propio historial")
	registry.reset_loops("")
	assert_false(_warned(await registry.call_tool("read_thing", {"path": "a"})), "al terminar el turno empieza de cero")
	await registry.call_tool("read_thing", {"path": "a"})
	assert_true(_warned(await registry.call_tool("read_thing", {"path": "a"})), "y vuelve a contar")


func test_volatile_parts_are_not_progress() -> void:
	var entries: Array[Dictionary] = []
	var registry := _registry({"a": "A"})
	registry.error_mark = func() -> int: return entries.size()
	registry.errors_since = func(since: int) -> Array[Dictionary]: return entries.slice(since)
	await registry.call_tool("read_thing", {"path": "a"})
	entries.append({"seq": 1, "kind": "error", "message": "boom", "file": "", "line": 0, "source": "editor"})
	await registry.call_tool("read_thing", {"path": "a"})
	assert_true(_warned(await registry.call_tool("read_thing", {"path": "a"})), "el aviso de errores nuevos no cuenta como otro resultado")
	var guard := ToolLoopGuard.new()
	guard.observe("x", {}, {"content": [{"type": "text", "text": "<untrusted nonce=\"1\">same</untrusted nonce=\"1\">"}]})
	assert_eq(int(guard.observe("x", {}, {"content": [{"type": "text", "text": "<untrusted nonce=\"2\">same</untrusted nonce=\"2\">"}]}).repeats), 2, "el nonce de los sobres tampoco")


func test_exempt_tools() -> void:
	var registry := _registry({"a": "A"})
	registry.loop_exempt = func(tool_name: String) -> bool: return tool_name == "read_thing"
	for i in 4:
		assert_false(_warned(await registry.call_tool("read_thing", {"path": "a"})), "la vigila otro detector (el del playtest)")


func test_oneshot_finding() -> void:
	var loops := LoopDetector.new()
	var guard := ToolLoopGuard.new()
	var seen: Dictionary = {}
	for i in 3:
		seen = guard.observe("get_node", {"path": "Player"}, {"content": [{"type": "text", "text": "no node"}], "isError": true})
	var finding := loops.observe_guard(seen)
	assert_false(finding.is_empty(), "lo que avisa el server es un hallazgo")
	assert_false(finding.repeated, "la primera vez pide otro enfoque")
	assert_true(str(finding.text).contains("get_node") and str(finding.text).contains("3 times"), str(finding.text))
	assert_true(loops.observe_guard(seen).repeated, "la misma huella otra vez: pausa")
	assert_eq(loops.observe_guard({}), {}, "sin ciclo, nada")
