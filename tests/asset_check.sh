#!/bin/sh
# m7-39 de punta a punta (con red): instala un plugin del Asset Store desde Extensions y prueba las
# tools del agente. Corre sobre una copia del proyecto con Godot en modo self-contained (._sc_),
# así no toca el repo ni los EditorSettings del usuario.
# Uso: tests/asset_check.sh <binario de godot> [prefijo de las capturas]
set -e
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ]; then
	echo "uso: $0 <binario de godot> [prefijo]" >&2
	exit 2
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PREFIX="${2:-$TMP/asset}"
cp "$(command -v "$G")" "$TMP/godot"
touch "$TMP/._sc_"
mkdir -p "$TMP/editor_data" "$TMP/project/tests"
cp "$ROOT/project.godot" "$TMP/project/"
cp -R "$ROOT/addons" "$TMP/project/"
rm -f "$TMP/project/addons/godot_agent/config/project_config.tres"
# El plugin de dev usa scripts de tests/.
cp -R "$ROOT/tests/." "$TMP/project/tests/"
rm -rf "$TMP/project/tests/upstream" "$TMP/project/tests/tmp"
"$TMP/godot" --headless --path "$TMP/project" --import >/dev/null 2>&1 || true
XRUN_PROJECT="$TMP/project" "$ROOT/tests/run_in_xvfb.sh" "$TMP/godot" "--godot-agent-asset-test=$PREFIX"
