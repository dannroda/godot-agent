#!/bin/sh
# m12-49: el primer uso en vivo, sin gastar tokens. Copia limpia del proyecto y Godot self-contained
# (sin agentes configurados, como un editor recién instalado), con un CLAUDE_CONFIG_DIR vacío y sin
# API key en el entorno: «Agregar» en Claude Code tiene que arrancar la sesión sola (npx baja el
# adaptador la primera vez: necesita red) y, sin credenciales, terminar en la tarjeta de login.
# No se manda ningún prompt. No toca el repo, los EditorSettings ni la configuración de Claude.
# Uso: tests/first_run_check.sh <binario de godot> [prefijo de las capturas] [en|es]
set -e
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ]; then
	echo "uso: $0 <binario de godot> [prefijo] [en|es]" >&2
	exit 2
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PREFIX="${2:-$TMP/first_run}"
LANG_CODE="${3:-en}"
BIN="$(command -v "$G")"
if head -c 2 "$BIN" | grep -q '#!' && command -v godot-manager >/dev/null; then BIN="$(godot-manager which)"; fi
cp -L "$BIN" "$TMP/godot"
touch "$TMP/._sc_"
mkdir -p "$TMP/editor_data" "$TMP/project/tests" "$TMP/claude"
SERIES="$("$TMP/godot" --version | cut -d. -f1-2)"
cat > "$TMP/editor_data/editor_settings-$SERIES.tres" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
interface/editor/editor_language = "$LANG_CODE"
interface/editor/localization/editor_language = "$LANG_CODE"
EOF
cp "$ROOT/project.godot" "$TMP/project/"
cp -R "$ROOT/addons" "$TMP/project/"
rm -f "$TMP/project/addons/godot_agent/config/project_config.tres"
cp -R "$ROOT/tests/." "$TMP/project/tests/"
rm -rf "$TMP/project/tests/upstream" "$TMP/project/tests/tmp"
"$TMP/godot" --headless --path "$TMP/project" --import >/dev/null 2>&1 || true
# Sin credenciales: un HOME vacío (ni ~/.claude ni ~/.claude.json), sin las variables de Claude Code
# que pudiera tener el shell (una sesión de Claude Code exporta varias) y sin API key. npx guarda su
# caché en ese HOME: la descarga es la de un primer uso de verdad.
HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR"
UNSET=""
for name in $(env | cut -d= -f1 | grep -E '^(CLAUDE|ANTHROPIC)'); do UNSET="$UNSET -u $name"; done
# shellcheck disable=SC2086
env $UNSET -u CLAUDECODE HOME="$HOME_DIR" CLAUDE_CONFIG_DIR="$TMP/claude" \
	GODOT_AGENT_LANGUAGE="$LANG_CODE" XRUN_PROJECT="$TMP/project" XRUN_TIMEOUT="${XRUN_TIMEOUT:-420}" \
	"$ROOT/tests/run_in_xvfb.sh" "$TMP/godot" "--godot-agent-first-run-test=$PREFIX"
