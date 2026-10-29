#!/bin/sh
# Capturas de toda la UI del addon para revisarla contra lo propuesto: dock, Ajustes, registro de ACP,
# Extensiones, One-shot (ancho y angosto), Agent Log y las conversaciones de la guía.
# Corre aislado como tests/docs_shots.sh: copia limpia del proyecto, Godot self-contained y Xvfb
# (nunca un compositor anidado: escribiría la configuración del escritorio del usuario).
# Uso: tests/ux_tour.sh <binario de godot> <carpeta de salida> [en|es]
set -e
G="$1"
OUT="$2"
LANG_CODE="${3:-es}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ] || [ -z "$OUT" ]; then
	echo "uso: $0 <binario de godot> <carpeta de salida> [en|es]" >&2
	exit 2
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$(command -v "$G")"
if head -c 2 "$BIN" | grep -q '#!' && command -v godot-manager >/dev/null; then BIN="$(godot-manager which)"; fi
cp -L "$BIN" "$TMP/godot"
touch "$TMP/._sc_"
mkdir -p "$TMP/editor_data" "$TMP/project/tests" "$TMP/project/addons"
SERIES="$("$TMP/godot" --version | cut -d. -f1-2)"
cat > "$TMP/editor_data/editor_settings-$SERIES.tres" <<EOT
[gd_resource type="EditorSettings" format=3]

[resource]
interface/editor/editor_language = "$LANG_CODE"
interface/editor/localization/editor_language = "$LANG_CODE"
EOT
cp "$ROOT/project.godot" "$TMP/project/"
cp -R "$ROOT/addons/godot_agent" "$ROOT/addons/godot_agent_dev" "$TMP/project/addons/"
rm -f "$TMP/project/addons/godot_agent/config/project_config.tres"
sed -i 's|^enabled=PackedStringArray(.*)|enabled=PackedStringArray("res://addons/godot_agent/plugin.cfg", "res://addons/godot_agent_dev/plugin.cfg")|' "$TMP/project/project.godot"
cp -R "$ROOT/tests/." "$TMP/project/tests/"
rm -rf "$TMP/project/tests/upstream" "$TMP/project/tests/tmp"
"$TMP/godot" --headless --path "$TMP/project" --import >/dev/null 2>&1 || true
case "$LANG_CODE" in es) LOCALE=es_AR.UTF-8 ;; *) LOCALE=en_US.UTF-8 ;; esac
LANG="$LOCALE" LC_ALL="$LOCALE" GODOT_AGENT_LANGUAGE="$LANG_CODE" XRUN_PROJECT="$TMP/project" \
	"$ROOT/tests/run_in_xvfb.sh" "$TMP/godot" "--godot-agent-ux-tour=$OUT"
