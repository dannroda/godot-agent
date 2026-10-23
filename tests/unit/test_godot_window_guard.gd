extends "test_case.gd"
## Godot lanzado desde la shell con ventana (m7-30).

const GodotWindowGuard := preload("res://addons/godot_agent/session/godot_window_guard.gd")
const BIN := "/opt/godot/versions/4.8-beta1/godot"


func _launch(command: String) -> String:
	return GodotWindowGuard.windowed_launch(command, BIN)


## El comando de la captura del usuario (little-villages).
func test_command_from_the_report() -> void:
	var command := "cd /home/drod/Proyectos/Godot/little-villages; timeout 90 \"$GODOT\" --path . --script /tmp/shoot_seeds.gd 2>&1 | grep -E \"saved|ERROR|SCRIPT\" | head -20"
	assert_eq(_launch(command), "timeout 90 $GODOT --path . --script /tmp/shoot_seeds.gd 2>", "timeout + $GODOT sin --headless")


func test_windowed() -> void:
	assert_eq(_launch("godot --path ."), "godot --path .", "godot del PATH")
	assert_eq(_launch(BIN + " res://main.tscn"), BIN + " res://main.tscn", "el binario del editor")
	assert_eq(_launch("${GODOT} -e"), "${GODOT} -e", "${GODOT} con el editor")
	assert_eq(_launch("cd x && GODOT_X=1 env A=b timeout -k 5 10s ./Godot_v4.6.3-stable_linux.x86_64 --path ."), "GODOT_X=1 env A=b timeout -k 5 10s ./Godot_v4.6.3-stable_linux.x86_64 --path .", "prefijos y binario descargado")
	assert_eq(_launch("\"$GODOT\" --headless --import; \"$GODOT\" --path . --script t.gd"), "$GODOT --path . --script t.gd", "el segundo tramo")


func test_windowless_pass() -> void:
	assert_eq(_launch("\"$GODOT\" --headless --path . --script res://tests/run_all.gd"), "", "--headless")
	assert_eq(_launch("timeout 60 $GODOT --display-driver headless --path ."), "", "--display-driver headless")
	assert_eq(_launch("godot --version"), "", "--version")
	assert_eq(_launch("$GODOT --path . --export-release Linux build/game.x86_64"), "", "export")
	assert_eq(_launch("xvfb-run -a $GODOT --path ."), "", "en un X virtual")
	assert_eq(_launch("grep -rn godot project.godot"), "", "godot como argumento")
	assert_eq(_launch("ls ~/godot-projects && cat godot.log"), "", "nombres parecidos")
	assert_eq(_launch("echo \"godot --path .\""), "", "dentro de un string de echo")
