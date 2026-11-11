@tool
extends RefCounted
## Avisos fuera del editor (m11-40): con la ventana del editor sin foco, un turno que termina o un
## agente que espera un permiso o una respuesta pide atención a la ventana (parpadea en la barra de
## tareas) y manda una notificación del sistema donde hay una sin dependencias: notify-send en Linux
## (si está instalado) y osascript en macOS. En Windows queda solo la atención de la ventana.
## Apagable en Ajustes (HarnessSettings.KEY_NOTIFY_UNFOCUSED).

## Para los tests: reemplaza la consulta del foco (Callable() -> bool) y el lanzamiento del proceso
## (Callable(program: String, args: PackedStringArray)).
static var focus_override: Callable
static var launch_override: Callable

static var _notify_send: String = "?"


## true si mandó el aviso (la ventana del editor no tenía el foco).
static func notify(title: String, body: String) -> bool:
	if _editor_focused():
		return false
	if not launch_override.is_valid():
		DisplayServer.window_request_attention()
	var command := command_for(OS.get_name(), title, body)
	if not command.is_empty():
		var program: String = command[0]
		var args := PackedStringArray(command.slice(1))
		if launch_override.is_valid():
			launch_override.call(program, args)
		else:
			OS.create_process(program, args)
	return true


## El programa y sus argumentos para la notificación en `os` ([] = no hay).
static func command_for(os: String, title: String, body: String) -> Array:
	match os:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var program := _find_notify_send()
			return [program, "--app-name=Godot", title, body] if not program.is_empty() else []
		"macOS":
			return ["osascript", "-e", "display notification %s with title %s" % [_apple_string(body), _apple_string(title)]]
	return []


static func _editor_focused() -> bool:
	if focus_override.is_valid():
		return bool(focus_override.call())
	return DisplayServer.window_is_focused(DisplayServer.MAIN_WINDOW_ID)


static func _find_notify_send() -> String:
	if launch_override.is_valid():
		return "notify-send"
	if _notify_send == "?":
		_notify_send = ""
		for dir in OS.get_environment("PATH").split(":", false):
			if FileAccess.file_exists(dir.path_join("notify-send")):
				_notify_send = dir.path_join("notify-send")
				break
	return _notify_send


## Un string de AppleScript: entre comillas, con \ y " escapados.
static func _apple_string(text: String) -> String:
	return "\"%s\"" % text.replace("\\", "\\\\").replace("\"", "\\\"")
