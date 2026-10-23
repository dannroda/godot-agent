@tool
extends RefCounted
## Versión del addon: una sola fuente, `version` en plugin.cfg (la actualiza el workflow de
## release). La usan el clientInfo de ACP y el serverInfo del MCP.

const PLUGIN_CFG := "res://addons/godot_agent/plugin.cfg"

static var _version: String = ""


static func version() -> String:
	if _version.is_empty():
		var config := ConfigFile.new()
		_version = str(config.get_value("plugin", "version", "0.0.0")) if config.load(PLUGIN_CFG) == OK else "0.0.0"
	return _version
