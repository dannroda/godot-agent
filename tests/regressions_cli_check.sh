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
# Mutantes (m11-41). --mutate sobre las que pasan: un puntaje, sobrevivientes, y ni un .gd ni un .tscn
# del proyecto cambia (hash de todos antes y después). --mutant con un juego que guarda un recurso:
# el SaveGuard se niega, el proceso sale con 4 y el archivo no existe.
project_hash() {
	find "$ROOT" -path "$ROOT/.godot" -prune -o -path "$ROOT/.git" -prune -o -path "$ROOT/tests/tmp" -prune -o \( -name '*.gd' -o -name '*.tscn' \) -type f -print | sort | xargs sha256sum | sha256sum
}
BEFORE="$(project_hash)"
OUT="$("$G" --headless --path "$ROOT" --script res://addons/godot_agent/playtest/regression_cli.gd -- --mutate=6 res://tests/fixtures/regressions/pass 2>&1)"
GOT=$?
printf '%s\n' "$OUT" | grep '^regressions: mutation\|^  survived'
if [ "$GOT" != 0 ] || ! printf '%s\n' "$OUT" | grep -q '^regressions: mutation score [1-9][0-9]*/6'; then
	echo "FALLA --mutate=6: salió con $GOT o sin puntaje con alguno detectado"
	FAILED=1
fi
if ! printf '%s\n' "$OUT" | grep -q '^  survived '; then
	echo "FALLA --mutate=6: ningún sobreviviente (el fixture no prueba el mouse: alguno tiene que sobrevivir)"
	FAILED=1
fi
OUT="$("$G" --headless --path "$ROOT" --script res://addons/godot_agent/playtest/regression_cli.gd -- --mutate=6 --min-score=100 res://tests/fixtures/regressions/pass 2>&1)"
if [ $? != 1 ]; then
	echo "FALLA --min-score=100 con sobrevivientes tendría que salir con 1"
	FAILED=1
fi
if [ "$(project_hash)" != "$BEFORE" ]; then
	echo "FALLA: una corrida con mutantes cambió archivos .gd o .tscn del proyecto"
	git -C "$ROOT" status --short -- '*.gd' '*.tscn'
	FAILED=1
fi
rm -f "$ROOT/tests/tmp/mutation_saved.tres"
MUTANT="$(printf '%s' '{"path":"res://tests/fixtures/mutation/saver.gd","line":5,"col":15,"before":"3","after":"0","op":"number"}' | base64 | tr -d '\n')"
OUT="$("$G" --headless --path "$ROOT" --script res://addons/godot_agent/playtest/regression_cli.gd -- "--mutant=$MUTANT" res://tests/fixtures/regressions/mutation_saver 2>&1)"
GOT=$?
if [ "$GOT" != 4 ] || [ -e "$ROOT/tests/tmp/mutation_saved.tres" ] || ! printf '%s\n' "$OUT" | grep -q "tried to save"; then
	echo "FALLA: un mutante que guarda tendría que salir con 4 sin escribir nada (salió con $GOT)"
	FAILED=1
fi
rm -f "$ROOT/tests/tmp/mutation_saved.tres"

# m11-44: el invariante de la regresión atrapa al mutante que saca al mover de la pantalla (run() da
# true igual), y el resultado dice que lo atrapó un invariante.
CLI=res://addons/godot_agent/playtest/regression_cli.gd
if ! "$G" --headless --path "$ROOT" --script "$CLI" -- --no-baselines res://tests/fixtures/regressions/invariants >/dev/null 2>&1; then
	echo "FALLA: la regresión con invariante tendría que pasar sin mutantes"
	FAILED=1
fi
MUTANT="$(printf '%s' '{"path":"res://tests/fixtures/invariants/mover.gd","line":9,"col":29,"before":" + ","after":" - ","op":"arithmetic"}' | base64 | tr -d '\n')"
mkdir -p "$ROOT/tests/tmp"
rm -f "$ROOT/tests/tmp/invariant_mutant.json"
OUT="$("$G" --headless --path "$ROOT" --script "$CLI" -- "--mutant=$MUTANT" --mutant-result=res://tests/tmp/invariant_mutant.json res://tests/fixtures/regressions/invariants 2>&1)"
GOT=$?
if [ "$GOT" != 1 ] || ! grep -q '"invariant"' "$ROOT/tests/tmp/invariant_mutant.json" 2>/dev/null; then
	echo "FALLA: el invariante tendría que matar al mutante (salió con $GOT)"
	printf '%s\n' "$OUT" | tail -5
	FAILED=1
fi

# La base de un presupuesto sin límite se guarda en el primer run verde, y no con --no-baselines.
mkdir -p "$ROOT/tests/tmp/baselines"
sed 's/game.budget(\\"nodes_max\\", 1000)/game.budget(\\"nodes_max\\")/' "$ROOT/tests/fixtures/regressions/invariants/mover.json" > "$ROOT/tests/tmp/baselines/mover.json"
"$G" --headless --path "$ROOT" --script "$CLI" -- --no-baselines res://tests/tmp/baselines/mover.json >/dev/null 2>&1
if grep -q '"baselines"' "$ROOT/tests/tmp/baselines/mover.json"; then
	echo "FALLA: con --no-baselines no se guarda la base"
	FAILED=1
fi
"$G" --headless --path "$ROOT" --script "$CLI" -- res://tests/tmp/baselines/mover.json >/dev/null 2>&1
if ! grep -q '"nodes_max"' "$ROOT/tests/tmp/baselines/mover.json" || ! grep -q '"baselines"' "$ROOT/tests/tmp/baselines/mover.json"; then
	echo "FALLA: el primer run verde tendría que guardar la base de nodes_max"
	FAILED=1
fi
rm -rf "$ROOT/tests/tmp/baselines" "$ROOT/tests/tmp/invariant_mutant.json"
# m11-62: sabotajes de escena. Speed a 0, Panel oculto y la señal del Timer cortada los detecta la
# regresión; la raíz oculta no. max_health a 0 también (m11-63): solo se lee en _ready, así que se ve
# porque el sabotaje se pone antes de que la escena entre al árbol. El .tscn no cambia.
BEFORE="$(project_hash)"
OUT="$("$G" --headless --path "$ROOT" --script "$CLI" -- --mutate=100 res://tests/fixtures/regressions/sabotage 2>&1)"
KILLED="$(printf '%s\n' "$OUT" | grep -c 'door.tscn killed$')"
if [ "$KILLED" != 4 ] || ! printf '%s\n' "$OUT" | grep -q 'survived res://tests/fixtures/sabotage/door.tscn root hidden'; then
	echo "FALLA: los sabotajes de escena tendrían que dar 4 detectados y «root hidden» sin detectar (detectados: $KILLED)"
	printf '%s\n' "$OUT" | grep "door.tscn" | head -8
	FAILED=1
fi
if [ "$(project_hash)" != "$BEFORE" ]; then
	echo "FALLA: los sabotajes de escena cambiaron archivos .gd o .tscn del proyecto"
	FAILED=1
fi
[ "$FAILED" = 0 ] && echo "regressions-cli: bien"
exit "$FAILED"
