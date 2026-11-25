extends "test_case.gd"
## m20-06: lo que la app aparte necesita para autorizar una llamada al editor.

const ToolRegistry := preload("res://addons/godot_agent/mcp/tool_registry.gd")
const McpTool := preload("res://addons/godot_agent/mcp/mcp_tool.gd")


func test_describe_opens_run_into_its_method() -> void:
	var registry := ToolRegistry.new()
	registry.register(McpTool.create("touch", "edit_files", "Escribe", {"name": {"type": "string"}}, ["name"], func(_args: Dictionary) -> String: return ""))
	registry.register(McpTool.create("peek", "read", "Lee", {}, [], func(_args: Dictionary) -> String: return ""))
	registry.mark_extended(PackedStringArray(["touch"]))
	assert_eq(registry.describe("peek", {}).group, "read", "una tool directa")
	var run := registry.describe("run", {"method": "touch", "params": {"name": "x"}})
	assert_eq([run.group, run.title], ["edit_files", "godot.touch"], "godot.run se autoriza como el método que corre")
	assert_eq(registry.describe("methods", {}).group, "read", "godot.methods solo lista")
	assert_eq(registry.describe("nope", {}), {}, "una que no existe")
