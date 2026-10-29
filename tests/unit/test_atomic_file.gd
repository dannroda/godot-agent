extends "test_case.gd"
## Escritura atómica (m13-02): el archivo queda entero y no queda el temporal.

const AtomicFile := preload("res://addons/godot_agent/core/atomic_file.gd")


func test_write_text() -> void:
	var path := "user://test_atomic_file/sub/a.json"
	assert_eq(AtomicFile.write_text(path, "uno"), OK, "crea la carpeta y escribe")
	assert_eq(AtomicFile.write_text(path, "dos"), OK, "reemplaza")
	assert_eq(FileAccess.get_file_as_string(path), "dos", "contenido nuevo")
	assert_false(FileAccess.file_exists(path + ".tmp"), "sin temporal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
