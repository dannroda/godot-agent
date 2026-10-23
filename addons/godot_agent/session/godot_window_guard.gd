@tool
extends RefCounted
## Godot lanzado desde la shell con ventana (m7-30). El agente corre Godot por línea de comandos
## para scripts, tests e imports, siempre con `--headless`; sin eso se abre el juego (o un editor)
## en una ventana aparte en la pantalla del usuario. Para ver el juego está run_scene +
## capture_game_frame desde el editor. Se rechaza solo, sin tarjeta, como las escrituras de D48.

## Cosas que se anteponen a un comando.
const PREFIXES: PackedStringArray = ["sudo", "command", "builtin", "time", "exec", "env", "nohup"]
## Sin ventana aunque no digan --headless (o solo imprimen y salen).
const WINDOWLESS_FLAGS: PackedStringArray = [
	"--headless", "--version", "--help", "-h", "--doctool", "--export-release", "--export-debug", "--export-pack",
	"--export-patch", "--dump-extension-api", "--dump-gdextension-interface",
]
## Correr adentro de un X virtual tampoco abre nada en la pantalla.
const VIRTUAL_DISPLAYS: PackedStringArray = ["xvfb-run", "xvfb-run-safe"]


## El tramo del comando que abre Godot con ventana, o "" si no hay. `godot_bin` es el binario del
## editor (el agente lo recibe también como `$GODOT`).
static func windowed_launch(command: String, godot_bin: String = "") -> String:
	var line := RegEx.create_from_string("'([^']*)'|\"([^\"]*)\"").sub(command, "$1$2", true)
	for segment: String in RegEx.create_from_string("&&|\\|\\||[;|\n&]").sub(line, "\n", true).split("\n", false):
		var words := _command_words(segment)
		if words.is_empty() or words[0].get_file() in VIRTUAL_DISPLAYS or not _is_godot(words[0], godot_bin):
			continue
		var args := words.slice(1)
		var windowless := false
		for i: int in args.size():
			if args[i] in WINDOWLESS_FLAGS or args[i] == "--display-driver=headless" or args[i] == "--display-driver" and i + 1 < args.size() and args[i + 1] == "headless":
				windowless = true
		if not windowless:
			return segment.strip_edges()
	return ""


## Las palabras del tramo sin los prefijos: `timeout [-k 5] 90`, `env A=b`, `nice -n 5`, `time`…
static func _command_words(segment: String) -> PackedStringArray:
	var words := segment.strip_edges().split(" ", false)
	while not words.is_empty():
		var word := words[0]
		if word == "timeout" or word == "nice":
			words.remove_at(0)
			while not words.is_empty() and words[0].begins_with("-"):
				var option := words[0]
				words.remove_at(0)
				if option in ["-k", "-s", "-n"] and not words.is_empty():
					words.remove_at(0)
			if word == "timeout" and not words.is_empty():
				words.remove_at(0)  # la duración
		elif word in PREFIXES or word.contains("=") and not word.begins_with("-"):
			words.remove_at(0)
		else:
			break
	return words


static func _is_godot(word: String, godot_bin: String) -> bool:
	if word in ["$GODOT", "${GODOT}"] or not godot_bin.is_empty() and word == godot_bin:
		return true
	var name := word.get_file().to_lower()
	return RegEx.create_from_string("^godot[0-9.]*(\\.exe|\\.x86_64|\\.arm64)?$|^godot_v[\\w.-]+$").search(name) != null
