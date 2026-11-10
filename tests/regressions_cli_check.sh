#!/bin/sh
# Regresiones sin el editor (m16-09): las de tests/fixtures/regressions por regression_cli.gd, con el
# código de salida que espera CI. pass: pasan y fallan con su sabotaje; fail: una que no pasa;
# vacuous: pasa también con el sabotaje, así que no detecta nada y cuenta como falla; blocked: usa una API prohibida.
# Repetir (m11-42): flaky pasa 2 de 3 con --repeat=3 y no rompe la corrida salvo con --fail-on-flaky;
# marked y recovers están marcadas inestables: sin --repeat, la que falla siempre se reintenta 3 veces y
# falla; la que falla una y después pasa queda inestable (1 de 2). Una opción mal es 2.
# Uso: tests/regressions_cli_check.sh <binario de godot>
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ]; then
	echo "uso: $0 <binario de godot>" >&2
	exit 2
fi
FAILED=0
# nombre:salida esperada:texto que tiene que aparecer:opciones (separadas por comas)
for CASE in "pass:0:all 2 pass:" "fail:1:FAIL:" "vacuous:1:does not detect:" "blocked:1:can't use:" \
	"pass:0:PASS The player jumps (passed 3 of 3):--repeat=3" "flaky:0:FLAKY Alternates between passing and failing (passed 2 of 3):--repeat=3" \
	"flaky:1:1 flaky:--repeat=3,--fail-on-flaky" "marked:1:FAIL Fails now, was flaky before (passed 0 of 3):" "recovers:0:FLAKY Marked flaky, fails the first time (passed 1 of 2):" "pass:2:--repeat needs:--repeat=0"; do
	NAME="$(echo "$CASE" | cut -d: -f1)"
	WANT="$(echo "$CASE" | cut -d: -f2)"
	TEXT="$(echo "$CASE" | cut -d: -f3)"
	OPTS="$(echo "$CASE" | cut -d: -f4 | tr ',' ' ')"
	# shellcheck disable=SC2086
	OUT="$("$G" --headless --path "$ROOT" --script res://addons/godot_agent/playtest/regression_cli.gd -- $OPTS "res://tests/fixtures/regressions/$NAME" 2>&1)"
	GOT=$?
	printf '%s\n' "$OUT" | grep '^regressions\|^  '
	if [ "$GOT" != "$WANT" ]; then
		echo "FALLA $NAME $OPTS: salió con $GOT, se esperaba $WANT"
		FAILED=1
	fi
	if ! printf '%s\n' "$OUT" | grep -qF -- "$TEXT"; then
		echo "FALLA $NAME $OPTS: no dice «$TEXT»"
		FAILED=1
	fi
done
[ "$FAILED" = 0 ] && echo "regressions-cli: bien"
exit "$FAILED"
