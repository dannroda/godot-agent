extends SceneTree
## Editor falso para test_editor_supervisor.gd: lo lanza el supervisor (--launch) con --path en un
## proyecto de prueba (sin el addon, así que no usa supervisor_state.gd). Hace lo que diga plan.json
## para su número de arranque: crashear antes de marcar ready, crashear después, cerrarse bien o
## pedir un reinicio.


func _initialize() -> void:
	var dir := OS.get_environment("GODOT_AGENT_SUPERVISOR")
	var project := ProjectSettings.globalize_path("res://")
	var counter := dir.path_join("launches.txt")
	var launch := int(FileAccess.get_file_as_string(counter)) + 1 if FileAccess.file_exists(counter) else 1
	_write(counter, str(launch))
	var plan: Array = JSON.parse_string(FileAccess.get_file_as_string(project.path_join("plan.json")))
	var action := str(plan[mini(launch, plan.size()) - 1])
	var me := JSON.stringify({"pid": OS.get_process_id()})
	match action:
		"crash_start":
			OS.crash("fake startup crash")
		"ready_crash":
			_write(dir.path_join("ready.json"), me)
			OS.crash("fake crash after start")
		"restart":
			_write(dir.path_join("ready.json"), me)
			_write(dir.path_join("restart.json"), me)
			_write(dir.path_join("closed.json"), me)
		_:
			_write(dir.path_join("ready.json"), me)
			_write(dir.path_join("closed.json"), me)
	quit()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
