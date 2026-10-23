#!/bin/sh
# Regenera las capturas de la guía (docs/images/<idioma>/) con el agente falso y tests/docs_demo/.
# Corre sobre una copia limpia del proyecto (sin .godot: sin scripts abiertos de otras pruebas) y
# con Godot copiado en modo self-contained (._sc_), con el editor en el idioma pedido y un layout
# limpio: no toca los EditorSettings del usuario ni el .godot del repo.
# Uso: tests/docs_shots.sh <binario de godot> [en|es]
set -e
G="$1"
LANG_CODE="${2:-en}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ]; then
	echo "uso: $0 <binario de godot> [en|es]" >&2
	exit 2
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$(command -v "$G")" "$TMP/godot"
touch "$TMP/._sc_"
mkdir -p "$TMP/editor_data" "$TMP/project/tests"
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
OUT="$ROOT/docs/images/$LANG_CODE"
mkdir -p "$OUT"
case "$LANG_CODE" in es) LOCALE=es_AR.UTF-8 ;; *) LOCALE=en_US.UTF-8 ;; esac
LANG="$LOCALE" LC_ALL="$LOCALE" GODOT_AGENT_LANGUAGE="$LANG_CODE" XRUN_PROJECT="$TMP/project" \
	"$ROOT/tests/run_in_xvfb.sh" "$TMP/godot" "--godot-agent-docs-shots=$OUT"
