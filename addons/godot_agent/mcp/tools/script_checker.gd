extends SceneTree
## Subproceso de `validate_scripts`: carga cada script sin caché y deja marcas en stderr, en el
## mismo flujo que los errores del motor, para asociar cada error a su archivo.
## Uso: godot --headless --no-header --path <proyecto> --script <este> -- <res://a.gd> …
## No referencia nada del addon: corre fuera del editor.

func _initialize() -> void:
	for path: String in OS.get_cmdline_user_args():
		printerr("@@BEGIN " + path)
		var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
		var ok := script != null
		printerr("@@END %s %s" % ["ok" if ok else "fail", path])
	quit(0)
