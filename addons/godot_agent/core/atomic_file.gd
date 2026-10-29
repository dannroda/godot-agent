@tool
extends RefCounted
## Escritura atómica: el texto va a un temporal al lado y se renombra encima. Si el editor se cierra
## (o se cae) a mitad de escritura, queda el archivo anterior entero, no uno truncado (m13-02).


## Escribe `text` en `path` (res://, user:// o absoluta) y crea la carpeta si falta. OK o el error.
static func write_text(path: String, text: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temp := absolute + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	var error := DirAccess.rename_absolute(temp, absolute)
	if error != OK:
		DirAccess.remove_absolute(temp)
	return error
