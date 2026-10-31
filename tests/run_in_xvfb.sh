#!/bin/sh
# Abre el editor en un Xvfb con OpenGL por software y le pasa los flags del plugin de dev.
# Las pruebas que lanzan el juego corren acá para no robarle el foco al escritorio
# (una vez quedó texto tipeado en un fixture).
# Uso: tests/run_in_xvfb.sh <binario de godot> --godot-agent-run-test
# XRUN_PROJECT=<carpeta> abre otro proyecto (p. ej. el sandbox de tests/make_sandbox.sh).
set -e
G="$1"; shift
ROOT="${XRUN_PROJECT:-$(cd "$(dirname "$0")/.." && pwd)}"
exec timeout "${XRUN_TIMEOUT:-300}" env -u WAYLAND_DISPLAY \
	GODOT_AGENT_LANGUAGE="${GODOT_AGENT_LANGUAGE:-en}" \
	GODOT_AGENT_TEST_RUN_ARGS="--rendering-driver opengl3 --display-driver x11 --audio-driver Dummy" \
	xvfb-run -a -s "-screen 0 1920x1200x24" \
	"$G" --display-driver x11 --rendering-driver opengl3 --path "$ROOT" -e -- "$@"
