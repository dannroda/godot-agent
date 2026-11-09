#!/bin/sh
# Abre el editor en un Xvfb con OpenGL por software y le pasa los flags del plugin de dev.
# Las pruebas que lanzan el juego corren acá para no robarle el foco al escritorio
# (una vez quedó texto tipeado en un fixture).
# Uso: tests/run_in_xvfb.sh <binario de godot> --godot-agent-run-test
# XRUN_PROJECT=<carpeta> abre otro proyecto (p. ej. el sandbox de tests/make_sandbox.sh).
# project.godot vuelve a quedar como estaba al salir (m13-19): el editor lo reescribe al arrancar
# (saca de `enabled` los plugins que el checkout no tiene, pone config/features de su versión) y
# los checks que guardan los ajustes lo dejan en disco. Se restaura también si el check falla o lo
# corta el timeout.
set -e
G="$1"; shift
ROOT="${XRUN_PROJECT:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT="$ROOT/project.godot"
BACKUP="$(mktemp "${TMPDIR:-/tmp}/run_in_xvfb.project.XXXXXX")"
cp "$PROJECT" "$BACKUP"
restore_project() {
	if ! cmp -s "$PROJECT" "$BACKUP"; then
		cp "$BACKUP" "$PROJECT"
		echo "run_in_xvfb: project.godot restaurado (el editor lo había reescrito)" >&2
	fi
	rm -f "$BACKUP"
}
trap restore_project EXIT
status=0
timeout "${XRUN_TIMEOUT:-300}" env -u WAYLAND_DISPLAY \
	GODOT_AGENT_LANGUAGE="${GODOT_AGENT_LANGUAGE:-en}" \
	GODOT_AGENT_TEST_RUN_ARGS="--rendering-driver opengl3 --display-driver x11 --audio-driver Dummy" \
	xvfb-run -a -s "-screen 0 1920x1200x24" \
	"$G" --display-driver x11 --rendering-driver opengl3 --path "$ROOT" -e -- "$@" || status=$?
exit $status
