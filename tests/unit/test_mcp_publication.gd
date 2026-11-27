extends "test_case.gd"
## m20-05: el editor publica su MCP para la app aparte en un archivo 0600 por proyecto.

const McpPublication := preload("res://addons/godot_agent/mcp/mcp_publication.gd")

const PROJECT := "/nonexistent/test_mcp_publication/"


func test_round_trip_private_and_removed() -> void:
	var server := TCPServer.new()
	server.listen(0, "127.0.0.1")
	var url := "http://127.0.0.1:%d/mcp" % server.get_local_port()
	assert_eq(McpPublication.publish(PROJECT, url, "secret"), OK, "se publica")
	var path := McpPublication.path_for(PROJECT)
	assert_eq(FileAccess.get_unix_permissions(path) & 511, McpPublication.PRIVATE_FILE, "solo el usuario lo lee")
	assert_eq(McpPublication.read("/nonexistent/test_mcp_publication"), {"url": url, "token": "secret"}, "con o sin barra final")
	assert_eq(McpPublication.read("/nonexistent/otro"), {}, "otro proyecto no lo ve")
	McpPublication.remove(PROJECT)
	assert_false(FileAccess.file_exists(path), "al cerrar se borra")
	assert_eq(McpPublication.read(PROJECT), {}, "sin archivo, nada")
	McpPublication.publish(PROJECT, url, "secret")
	server.stop()
	assert_eq(McpPublication.read(PROJECT), {}, "un editor caído dejó el archivo: nadie escucha y no se usa")
	McpPublication.remove(PROJECT)


func test_not_removed_by_another_editor() -> void:
	McpPublication.publish(PROJECT, "http://127.0.0.1:1/mcp", "secret")
	var path := McpPublication.path_for(PROJECT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"project": PROJECT.trim_suffix("/"), "url": "http://127.0.0.1:1/mcp", "token": "secret", "pid": 999999999}))
	file.close()
	McpPublication.remove(PROJECT)
	assert_true(FileAccess.file_exists(path), "un editor no borra el de otro")
	DirAccess.remove_absolute(path)
