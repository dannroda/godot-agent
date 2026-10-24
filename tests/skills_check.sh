#!/bin/sh
# m7-36 de punta a punta: la pestaña Skills de Extensions sobre una copia del proyecto, con Godot en
# modo self-contained (._sc_) y un CLAUDE_CONFIG_DIR de prueba con una skill de usuario y un plugin
# instalado, así no toca el repo, los EditorSettings ni la configuración de Claude del usuario.
# Uso: tests/skills_check.sh <binario de godot> [prefijo de las capturas]
set -e
G="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$G" ]; then
	echo "uso: $0 <binario de godot> [prefijo]" >&2
	exit 2
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PREFIX="${2:-$TMP/skills}"
cp "$(command -v "$G")" "$TMP/godot"
touch "$TMP/._sc_"
mkdir -p "$TMP/editor_data" "$TMP/project/tests"
cp "$ROOT/project.godot" "$TMP/project/"
cp -R "$ROOT/addons" "$TMP/project/"
rm -f "$TMP/project/addons/godot_agent/config/project_config.tres"
cp -R "$ROOT/tests/." "$TMP/project/tests/"
rm -rf "$TMP/project/tests/upstream" "$TMP/project/tests/tmp"
mkdir -p "$TMP/project/tests/tmp"

CONFIG="$TMP/claude"
mkdir -p "$CONFIG/skills/fake-user/references" "$CONFIG/plugins/cache/fake/fakeplug/1.0.0/.claude-plugin" "$CONFIG/plugins/cache/fake/fakeplug/1.0.0/skills/plug-skill"
printf -- '---\nname: fake-user\ndescription: "A user skill for the check"\n---\n\nBody\n' > "$CONFIG/skills/fake-user/SKILL.md"
printf 'notes\n' > "$CONFIG/skills/fake-user/references/notes.md"
printf '{"name": "fakeplug"}\n' > "$CONFIG/plugins/cache/fake/fakeplug/1.0.0/.claude-plugin/plugin.json"
printf -- '---\nname: plug-skill\ndescription: A plugin skill\n---\n' > "$CONFIG/plugins/cache/fake/fakeplug/1.0.0/skills/plug-skill/SKILL.md"
printf '{"version": 2, "plugins": {"fakeplug@fake": [{"scope": "user", "installPath": "%s"}]}}\n' "$CONFIG/plugins/cache/fake/fakeplug/1.0.0" > "$CONFIG/plugins/installed_plugins.json"

"$TMP/godot" --headless --path "$TMP/project" --import >/dev/null 2>&1 || true
CLAUDE_CONFIG_DIR="$CONFIG" XRUN_PROJECT="$TMP/project" "$ROOT/tests/run_in_xvfb.sh" "$TMP/godot" "--godot-agent-skills-test=$PREFIX"
