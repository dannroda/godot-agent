extends RefCounted
## Base de los tests unitarios. Cada test es un método `test_*` sin argumentos.
## Los asserts registran el fallo y siguen (assert() colgaría el runner headless).

var failures: PackedStringArray = []
var checks: int = 0
var _current: String = ""


func begin(test_name: String) -> void:
	_current = test_name


func assert_eq(actual: Variant, expected: Variant, label: String = "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("%s: esperado %s, obtenido %s" % [label, var_to_str(expected), var_to_str(actual)])


func assert_true(value: bool, label: String = "") -> void:
	checks += 1
	if not value:
		_fail("%s: esperado true" % label)


func assert_false(value: bool, label: String = "") -> void:
	checks += 1
	if value:
		_fail("%s: esperado false" % label)


## Carpeta temporal propia del test, vacía.
func temp_dir(name: String) -> String:
	var path := "user://unit_tests/%s" % name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file)
	return path


func _fail(message: String) -> void:
	failures.append("%s › %s" % [_current, message])
