#!/bin/sh
# La suite de checks en un solo lugar (m16-12): lo que corre el CI y todo lo que no gasta tokens ni red.
#   tests/suite.sh ci|full [godot]   corre el perfil entero, sigue aunque falle uno, imprime una tabla
#                                    PASS/FAIL con los segundos y sale con 1 si algo falló.
#   tests/suite.sh run <check> [godot]   uno solo (los steps de .github/workflows/ci.yml).
#   tests/suite.sh list ci|full      los nombres del perfil.
#   tests/suite.sh check-ci          ci.yml tiene un step `suite.sh run <check>` por cada check de ci.
# ci: antes de mergear a sm/next2. full: antes de un release, en 4.7.2 y en la beta.
# Los checks del editor van por tests/run_in_xvfb.sh (Xvfb, OpenGL por software): hace falta xvfb-run.
# SUITE_LOGS=<carpeta> guarda la salida de cada check (por defecto, una carpeta temporal).
# Afuera a propósito: los que gastan tokens (claude-*, *_session_check, claude_smoke_check,
# stream_json_probe), los que usan red o el CLI real (asset_check.sh, first_run_check.sh,
# extensions_cli_check.gd, skills_check.sh) y los que solo sacan capturas (*-shots, ux_tour.sh).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

# nombre:perfil:tope en segundos (de los Xvfb; ~3 veces lo que tardan en 4.7.2)
CHECKS="
run_all:ci:600
acp:ci:300
oneshot_loop:ci:300
regressions:ci:300
export:ci:300
plugin_cycle:ci:300
run:ci:280
review:ci:200
run-error:ci:150
debug:ci:150
external:ci:120
edit:ci:150
mcp:ci:120
sync:full:120
oneshot:full:150
long:full:120
completion:full:120
login:full:120
queue:full:120
auto:full:120
remote:full:120
pending:full:120
profile:full:120
cycle:full:120
i18n:full:120
history:full:120
sessions:full:120
ui-basic:full:120
ui-crash:full:120
ui-markdown:full:120
ui-long-permission:full:120
ui-quota:full:120
ui-quota-busy:full:120
ui-harness-prompt:full:120
crash:full:400
"

usage() {
	echo "uso: $0 ci|full [godot] · run <check> [godot] · list ci|full · check-ci" >&2
	exit 2
}

# Los nombres de un perfil: ci son los de ci; full, todos.
names() {
	echo "$CHECKS" | while IFS=: read -r name profile _; do
		[ -n "$name" ] || continue
		if [ "$1" = full ] || [ "$profile" = "$1" ]; then echo "$name"; fi
	done
}

timeout_of() {
	echo "$CHECKS" | while IFS=: read -r name _ seconds; do
		if [ "$name" = "$1" ]; then echo "$seconds"; fi
	done
}

# Corre un check con el binario $G; el código de salida es el del check.
run_check() {
	name="$1"
	limit="$(timeout_of "$name")"
	if [ -z "$limit" ]; then
		echo "suite: no hay un check \"$name\" (tests/suite.sh list full)" >&2
		return 2
	fi
	xvfb() { XRUN_TIMEOUT="$limit" tests/run_in_xvfb.sh "$G" "$@"; }
	headless() { timeout "$limit" "$G" --headless --path . --script "$@"; }
	shots="${SUITE_LOGS:-${TMPDIR:-/tmp}}"
	case "$name" in
		run_all) headless tests/run_all.gd ;;
		acp) headless tests/acp_session_check.gd ;;
		oneshot_loop) headless tests/oneshot_check.gd ;;
		regressions) timeout "$limit" sh tests/regressions_cli_check.sh "$G" ;;
		export) headless tests/export_check.gd ;;
		plugin_cycle) headless tests/plugin_cycle_check.gd ;;
		i18n) GODOT_AGENT_LANGUAGE=es xvfb --godot-agent-i18n-test ;;
		history) xvfb "--godot-agent-history-test=$shots/history.png" ;;
		sessions) xvfb "--godot-agent-sessions-test=$shots/sessions" ;;
		ui-*)
			scenario="$(echo "${name#ui-}" | tr - _)"
			case "$scenario" in basic|crash) ;; *) scenario="ui_$scenario" ;; esac
			xvfb "--godot-agent-ui-test=$scenario" ;;
		crash) timeout "$limit" sh tests/crash_check.sh "$G" ;;
		*) xvfb "--godot-agent-$name-test" ;;
	esac
}

G="godot"
case "$1" in
	list)
		[ "$2" = ci ] || [ "$2" = full ] || usage
		names "$2"
		;;
	check-ci)
		missing=0
		for name in $(names ci); do
			if ! grep -Eq "tests/suite\.sh run $name( |\$)" .github/workflows/ci.yml; then
				echo "suite: ci.yml no corre \"$name\" (falta un step con tests/suite.sh run $name)"
				missing=1
			fi
		done
		[ "$missing" = 0 ] && echo "suite: ci.yml corre los $(names ci | wc -l) checks de ci"
		exit "$missing"
		;;
	run)
		[ -n "$2" ] || usage
		G="${3:-godot}"
		run_check "$2"
		;;
	ci|full)
		G="${2:-godot}"
		LOGS="${SUITE_LOGS:-$(mktemp -d "${TMPDIR:-/tmp}/suite.XXXXXX")}"
		mkdir -p "$LOGS"
		export SUITE_LOGS="$LOGS"
		failed=""
		table=""
		for name in $(names "$1"); do
			start=$(date +%s)
			run_check "$name" > "$LOGS/$name.log" 2>&1
			code=$?
			seconds=$(( $(date +%s) - start ))
			if [ "$code" = 0 ]; then result=PASS; else result="FAIL ($code)"; failed="$failed $name"; fi
			line="$(printf '%-20s %-9s %4ss' "$name" "$result" "$seconds")"
			echo "$line"
			table="$table$line
"
		done
		echo
		echo "suite $1 ($("$G" --version | head -1)), salida en $LOGS:"
		printf '%s' "$table"
		if [ -n "$failed" ]; then
			echo "FALLARON:$failed"
			exit 1
		fi
		echo "todo PASS"
		;;
	*) usage ;;
esac
