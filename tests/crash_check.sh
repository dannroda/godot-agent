#!/bin/sh
# Verificación de M4: el editor muere a mitad de un playtest y, al reabrirlo, el autoload de
# playtest no queda en project.godot; después el test de export sigue pasando.
# Uso: tests/crash_check.sh <binario de godot>
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="GodotAgentPlaytest"
fail=0
for when in before during; do
	# setsid: la muerte del editor no tiene que arrastrar al grupo de procesos de quien llama.
	out="$(setsid -w "$ROOT/tests/run_in_xvfb.sh" "$G" "--godot-agent-crash-test=$when" 2>&1)"
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
	timeout 120 "$G" --headless --path "$ROOT" -e --quit-after 200 >/dev/null 2>&1
	if grep -q "$NAME" "$ROOT/project.godot"; then
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
