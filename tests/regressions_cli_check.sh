#!/bin/sh
# Regresiones sin el editor (m16-09): las de tests/fixtures/regressions por regression_cli.gd, con el
# código de salida que espera CI. pass: pasan y fallan con su sabotaje; fail: una que no pasa;
# vacuous: pasa también con el sabotaje, así que no detecta nada y cuenta como falla; blocked: usa una API prohibida.
# Uso: tests/regressions_cli_check.sh <binario de godot>
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ]; then
	echo "uso: $0 <binario de godot>" >&2
	exit 2
fi
FAILED=0
for CASE in pass:0 fail:1 vacuous:1 blocked:1; do
	NAME="${CASE%%:*}"
	WANT="${CASE##*:}"
	OUT="$("$G" --headless --path "$ROOT" --script res://addons/godot_agent/playtest/regression_cli.gd -- "res://tests/fixtures/regressions/$NAME" 2>&1)"
	GOT=$?
	printf '%s\n' "$OUT" | grep '^regressions\|^  '
	if [ "$GOT" != "$WANT" ]; then
		echo "FALLA $NAME: salió con $GOT, se esperaba $WANT"
		FAILED=1
	fi
done
[ "$FAILED" = 0 ] && echo "regressions-cli: bien"
exit "$FAILED"
