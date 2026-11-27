#!/bin/sh
# m20-07: la app aparte exportada con una plantilla, sin las clases del editor. Arma un proyecto
# temporal con solo el addon y la app como escena principal, exporta el .pck con <godot>, lo pone al
# lado de la plantilla linux_debug de esa versión (las plantillas no aceptan --path ni --main-pack) y lo
# corre headless unos segundos. Falla con cualquier SCRIPT ERROR. Las plantillas tienen que ser de la
# misma versión que <godot>.
# Uso: tests/standalone_export_check.sh <binario de godot> [carpeta de salida]
G="${1:?uso: $0 <binario de godot> [carpeta de salida]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
OUT="${2:-$WORK/out}"
trap 'rm -rf "$WORK"' EXIT
VERSION="$("$G" --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z0-9]+)\..*/\1.\3/')"
TEMPLATE="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION/linux_debug.x86_64"
if [ ! -f "$TEMPLATE" ]; then
	echo "standalone_export_check: no hay plantillas de $VERSION ($TEMPLATE)"
	exit 2
fi
mkdir -p "$WORK/project/addons" "$OUT"
cp -r "$ROOT/addons/godot_agent" "$WORK/project/addons/"
cat > "$WORK/project/project.godot" <<'EOF'
config_version=5
[application]
config/name="Godot Agent"
run/main_scene="res://addons/godot_agent/standalone/main.tscn"
EOF
cat > "$WORK/project/export_presets.cfg" <<'EOF'
[preset.0]
name="Linux"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter="*.md,*.po,*.json,*.txt"
exclude_filter=""
export_path=""
[preset.0.options]
binary_format/embed_pck=false
EOF
"$G" --headless --path "$WORK/project" --import > "$WORK/import.log" 2>&1
if ! "$G" --headless --path "$WORK/project" --export-pack Linux "$OUT/godot_agent.pck" > "$WORK/export.log" 2>&1; then
	tail -5 "$WORK/export.log"
	echo "standalone_export_check: FALLA (no exportó)"
	exit 1
fi
cp "$TEMPLATE" "$OUT/godot_agent"
chmod +x "$OUT/godot_agent"
# Sus ajustes en una carpeta temporal, no en los del usuario.
(cd "$OUT" && XDG_DATA_HOME="$WORK/data" timeout 15 ./godot_agent --headless > "$WORK/run.log" 2>&1)
if grep -q "SCRIPT ERROR" "$WORK/run.log"; then
	grep -A1 "SCRIPT ERROR" "$WORK/run.log" | head -20
	echo "standalone_export_check: FALLA ($VERSION)"
	exit 1
fi
echo "standalone_export_check: PASS ($VERSION)${2:+ → $OUT/godot_agent}"
