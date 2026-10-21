#!/bin/sh
# Arma un proyecto sandbox para correr One-shots fuera del repo del addon (M6):
# copia tests/sandbox_project/ y el addon a <destino>, hace git init y el primer commit.
# Nunca corras un One-shot sobre el proyecto del addon: los checkpoints crean ramas y "Volver acá"
# resetea la carpeta del proyecto.
# Uso: tests/make_sandbox.sh <destino> [--dev]   (--dev copia también addons/godot_agent_dev)
set -e
DEST="$1"
DEV="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$DEST" ]; then
	echo "uso: $0 <destino> [--dev]" >&2
	exit 2
fi
case "$(realpath -m "$DEST")/" in
	"$ROOT"/*) echo "el destino tiene que estar fuera del repo del addon: $DEST" >&2; exit 2 ;;
esac
if [ -e "$DEST" ]; then
	if [ ! -f "$DEST/.sandbox_one_shot" ]; then
		echo "$DEST ya existe y no es un sandbox: no se toca" >&2
		exit 2
	fi
	rm -rf "$DEST"
fi
mkdir -p "$DEST/addons"
cp -R "$ROOT/tests/sandbox_project/." "$DEST/"
rm -f "$DEST/.gdignore"
touch "$DEST/.sandbox_one_shot"
cp -R "$ROOT/addons/godot_agent" "$DEST/addons/"
if [ "$DEV" = "--dev" ]; then
	cp -R "$ROOT/addons/godot_agent_dev" "$DEST/addons/"
	sed -i 's#enabled=PackedStringArray("res://addons/godot_agent/plugin.cfg")#enabled=PackedStringArray("res://addons/godot_agent/plugin.cfg", "res://addons/godot_agent_dev/plugin.cfg")#' "$DEST/project.godot"
fi
git -c init.defaultBranch=main init -q "$DEST"
git -C "$DEST" add -A
git -C "$DEST" -c user.name="Sandbox" -c user.email="sandbox@localhost" commit -q -m "Sandbox inicial"
echo "$DEST"
