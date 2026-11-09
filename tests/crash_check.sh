#!/bin/sh
# Verificación de M4: el editor muere a mitad de un playtest y, al reabrirlo, el autoload de
# playtest no queda en project.godot; después el test de export sigue pasando.
# Uso: tests/crash_check.sh <binario de godot>
# project.godot se copia al empezar y se repone al final (m13-19). run_in_xvfb.sh no lo restaura
# acá (XRUN_KEEP_PROJECT=1): el autoload que quedó al morir el editor es justo lo que se mira.
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="GodotAgentPlaytest"
PROJECT="$ROOT/project.godot"
BACKUP="$(mktemp "${TMPDIR:-/tmp}/crash_check.project.XXXXXX")"
cp "$PROJECT" "$BACKUP"
restore_project() {
	if ! cmp -s "$PROJECT" "$BACKUP"; then
		cp "$BACKUP" "$PROJECT"
		echo "crash_check: project.godot restaurado"
	fi
	rm -f "$BACKUP"
}
trap restore_project EXIT
fail=0
for when in before during; do
	# setsid: la muerte del editor no tiene que arrastrar al grupo de procesos de quien llama.
	out="$(XRUN_KEEP_PROJECT=1 setsid -w "$ROOT/tests/run_in_xvfb.sh" "$G" "--godot-agent-crash-test=$when" 2>&1)"
	echo "$out" | grep "\[crash-test\]"
	# El juego huérfano muere solo: xvfb-run cierra el Xvfb cuando muere el editor.
	sleep 2
	for pid in $(pgrep -f "res://tests/fixtures/run_fixture"); do
		case "$(ps -o comm= -p "$pid")" in
			*odot*) echo "aviso: quedó un juego corriendo (pid $pid)" ;;
		esac
	done
	if [ "$when" = before ] && ! echo "$out" | grep -q "al matar: true"; then
		echo "FALLA: el editor no murió con el autoload registrado"; fail=1
	fi
	# Lo que prueba el reabrir (before): el autoload tiene que estar en el archivo cuando el editor
	# murió. En during ya no está: el playtest lo quita apenas arranca el juego.
	if grep -q "$NAME" "$PROJECT"; then
		echo "ok ($when): el autoload quedó en project.godot al morir"
	elif [ "$when" = before ]; then
		echo "FALLA (before): el autoload no está en project.godot después de la muerte, no hay nada que probar"; fail=1
	fi
	timeout 120 "$G" --headless --path "$ROOT" -e --quit-after 200 >/dev/null 2>&1
	if grep -q "$NAME" "$PROJECT"; then
		echo "FALLA ($when): el autoload quedó en project.godot al reabrir"; fail=1
	else
		echo "ok ($when): sin autoload al reabrir"
	fi
done
if timeout 300 "$G" --headless --path "$ROOT" --script res://tests/export_check.gd >/tmp/export_check_$$.log 2>&1; then
	echo "ok: export_check"
else
	tail -20 /tmp/export_check_$$.log; echo "FALLA: export_check"; fail=1
fi
rm -f /tmp/export_check_$$.log
exit $fail
