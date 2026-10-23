extends SceneTree
## Ventana Extensions (m7-37) contra el CLI real de Claude Code, con un CLAUDE_CONFIG_DIR temporal y
## un marketplace local: agregar el marketplace, instalar, deshabilitar, desinstalar y quitar. No
## toca la configuración del usuario. Necesita `claude` (o el SDK del adaptador en la cache de npx).
## Uso: godot --headless --path . --script tests/extensions_cli_check.gd

const ClaudeExtensions := preload("res://addons/godot_agent/extensions/claude_extensions.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var base := ProjectSettings.globalize_path("user://extensions_cli_check")
	_remove_dir(base)
	var config := base.path_join("config")
	var market := base.path_join("market")
	DirAccess.make_dir_recursive_absolute(config)
	DirAccess.make_dir_recursive_absolute(market.path_join(".claude-plugin"))
	DirAccess.make_dir_recursive_absolute(market.path_join("hello/.claude-plugin"))
	DirAccess.make_dir_recursive_absolute(market.path_join("hello/skills/hello"))
	_write(market.path_join(".claude-plugin/marketplace.json"), JSON.stringify({
		"name": "harness-test-market", "owner": {"name": "harness"},
		"plugins": [{"name": "hello", "source": "./hello", "description": "Test plugin of the harness"}],
	}))
	_write(market.path_join("hello/.claude-plugin/plugin.json"), JSON.stringify({"name": "hello", "version": "1.0.0", "description": "Test plugin of the harness"}))
	_write(market.path_join("hello/skills/hello/SKILL.md"), "---\nname: hello\ndescription: Says hello.\n---\nSay hello.\n")

	var extensions := ClaudeExtensions.new(base, {"CLAUDE_CONFIG_DIR": config})
	if not extensions.cli.is_available():
		print("extensions_cli_check: no se encontró el CLI de Claude Code; se saltea")
		quit(0)
		return
	print("CLI: ", extensions.cli.path)
	var added: Dictionary = await extensions.add_marketplace(market)
	_check(added.ok, "agrega el marketplace local (%s)" % added.message)
	var markets: Dictionary = await extensions.marketplaces()
	_check(markets.marketplaces.any(func(entry: Dictionary) -> bool: return entry.get("name") == "harness-test-market"), "aparece en la lista (%s)" % [markets])
	var listed: Dictionary = await extensions.plugins(true)
	_check(listed.available.any(func(plugin: Dictionary) -> bool: return plugin.get("pluginId") == "hello@harness-test-market"), "el plugin aparece entre los disponibles")
	var installed: Dictionary = await extensions.install_plugin("hello@harness-test-market", "user")
	_check(installed.ok, "instala (%s)" % installed.message)
	listed = await extensions.plugins(false)
	var plugin := _find(listed.installed, "hello@harness-test-market")
	_check(not plugin.is_empty() and bool(plugin.get("enabled")), "instalado y habilitado (%s)" % [plugin])
	var disabled: Dictionary = await extensions.set_plugin_enabled("hello@harness-test-market", false, "user")
	_check(disabled.ok, "deshabilita (%s)" % disabled.message)
	listed = await extensions.plugins(false)
	_check(not bool(_find(listed.installed, "hello@harness-test-market").get("enabled", true)), "queda deshabilitado")
	var again: Dictionary = await extensions.set_plugin_enabled("hello@harness-test-market", false, "user")
	_check(again.ok, "deshabilitar dos veces no es un error (%s)" % again.message)
	var removed: Dictionary = await extensions.uninstall_plugin("hello@harness-test-market", "user")
	_check(removed.ok, "desinstala (%s)" % removed.message)
	listed = await extensions.plugins(false)
	_check(_find(listed.installed, "hello@harness-test-market").is_empty(), "ya no está instalado")
	var gone: Dictionary = await extensions.remove_marketplace("harness-test-market")
	_check(gone.ok, "quita el marketplace (%s)" % gone.message)
	var mcp: Dictionary = await extensions.mcp_servers()
	_check(mcp.error.is_empty(), "mcp list sin servers no falla (%s)" % mcp.error)
	_remove_dir(base)
	print("extensions_cli_check: %d checks, %d fallos" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _find(list: Array, id: String) -> Dictionary:
	for plugin: Variant in list:
		if plugin is Dictionary and plugin.get("id") == id:
			return plugin
	return {}


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FALLA ", label)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir: String in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(dir))
	DirAccess.remove_absolute(path)
