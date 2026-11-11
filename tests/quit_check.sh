#!/bin/sh
# Cerrar el editor con sesiones del agente abiertas no deja procesos: ni el agente ni sus hijos
# (npx → node). El check del editor (--godot-agent-quit-test) arranca agentes falsos que no salen al
# cerrarse stdin, anota sus pids y los de sus hijos en tests/tmp/quit_pids.txt y cierra el editor.
# Uso: tests/quit_check.sh <binario de godot>
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDS="$ROOT/tests/tmp/quit_pids.txt"
rm -f "$PIDS"
# setsid: lo que quede vivo no pertenece al grupo de procesos de quien llama.
out="$(setsid -w "$ROOT/tests/run_in_xvfb.sh" "$G" --godot-agent-quit-test 2>&1)"
code=$?
echo "$out" | grep "\[quit-check\]"
echo "$out" | grep -E "SCRIPT ERROR|ERROR:.*(null instance|agent_process)" | head -5
if [ ! -s "$PIDS" ]; then
	echo "FALLA: el check no anotó procesos (salida $code)"
	echo "$out" | tail -20
	exit 1
fi
sleep 2
fail=0
for pid in $(cat "$PIDS"); do
	if kill -0 "$pid" 2>/dev/null; then
		echo "FALLA: quedó vivo el proceso $pid ($(ps -o args= -p "$pid" | cut -c1-120))"
		kill -9 "$pid" 2>/dev/null
		fail=1
	fi
done
if echo "$out" | grep -q "null instance"; then
	echo "FALLA: error al liberar un proceso en el cierre"
	fail=1
fi
[ "$fail" = 0 ] && echo "ok: cerrar el editor no dejó procesos ($(wc -w < "$PIDS") vigilados)"
rm -f "$PIDS"
exit $fail
