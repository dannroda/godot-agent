extends "test_case.gd"
## fs/read_text_file y fs/write_text_file sin editor.

const FsHandler := preload("res://addons/godot_agent/acp/fs_handler.gd")
const AcpClient := preload("res://addons/godot_agent/acp/acp_client.gd")


func _handler(root: String) -> FsHandler:
	var fs := FsHandler.new()
	fs.setup(root, null)
	return fs


func test_paths() -> void:
	var root := ProjectSettings.globalize_path(temp_dir("fs_paths"))
	var fs := _handler(root)
	var outside: Variant = fs.read_text_file({"path": "/etc/hostname"})
	assert_true(outside is AcpClient.AcpResponse and not outside.ok, "fuera del proyecto")
	var escape: Variant = fs.read_text_file({"path": root + "/../x.txt"})
	assert_true(escape is AcpClient.AcpResponse and not escape.ok, "con .. no escapa")
	var relative: Variant = fs.read_text_file({"path": "x.txt"})
	assert_true(relative is AcpClient.AcpResponse and not relative.ok, "relativa rechazada")
	var missing: Variant = fs.read_text_file({"path": root + "/no.txt"})
	assert_true(missing is AcpClient.AcpResponse and not missing.ok, "no existe")
	var godot_dir: Variant = await fs.write_text_file({"path": root + "/.godot/x.cfg", "content": "x"})
	assert_true(godot_dir is AcpClient.AcpResponse and not godot_dir.ok, "no escribe en .godot/")


func test_write_read_and_buffer() -> void:
	var root := ProjectSettings.globalize_path(temp_dir("fs_rw"))
	var fs := _handler(root)
	var path := root + "/a.gd"
	var written: Array = []
	fs.after_write = func(p: String, old_text: String, new_text: String) -> void: written.append([p, old_text, new_text])
	var result: Variant = await fs.write_text_file({"path": path, "content": "uno\ndos\ntres\n"})
	assert_eq(result, {}, "write ok")
	assert_eq(written.size(), 1, "after_write llamado")
	assert_eq(fs.read_text_file({"path": path}), {"content": "uno\ndos\ntres\n"}, "lee todo")
	assert_eq(fs.read_text_file({"path": path, "line": 2, "limit": 2}), {"content": "dos\ntres"}, "line + limit")
	fs.buffer_reader = func(_p: String) -> Variant: return "buffer sin guardar"
	assert_eq(fs.read_text_file({"path": path}), {"content": "buffer sin guardar"}, "prefiere el buffer")


func test_write_denied() -> void:
	var root := ProjectSettings.globalize_path(temp_dir("fs_denied"))
	var fs := _handler(root)
	fs.write_authorizer = func(_p: String, _o: String, _n: String) -> bool: return false
	var result: Variant = await fs.write_text_file({"path": root + "/b.gd", "content": "x"})
	assert_true(result is AcpClient.AcpResponse and not result.ok, "denegado")
	assert_false(FileAccess.file_exists(root + "/b.gd"), "no se escribió")
