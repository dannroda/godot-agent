#!/bin/sh
# Baja el editor de Godot para Linux y deja el binario en $1/godot.
# Uso: install-godot.sh <carpeta> <versión> [mono]   (4.7.2-stable, 4.8-beta2…; mono: la versión .NET)
# Las estables salen de godotengine/godot y las demás (beta, rc, dev) de godotengine/godot-builds.
set -eu
DIR="$1"
VERSION="$2"
FLAVOR="${3:-}"
case "$VERSION" in
	*-stable) REPO=godotengine/godot ;;
	*) REPO=godotengine/godot-builds ;;
esac
mkdir -p "$DIR"
if [ ! -x "$DIR/godot" ] && [ "$FLAVOR" = "mono" ]; then
	# La .NET trae el binario y GodotSharp/ en una carpeta: van juntos.
	NAME="Godot_v${VERSION}_mono_linux_x86_64"
	curl -fsSL -o "$DIR/godot.zip" "https://github.com/$REPO/releases/download/$VERSION/$NAME.zip"
	unzip -oq "$DIR/godot.zip" -d "$DIR"
	mv "$DIR/$NAME"/* "$DIR/"
	ln -sf "Godot_v${VERSION}_mono_linux.x86_64" "$DIR/godot"
	rm -r "$DIR/godot.zip" "$DIR/$NAME"
elif [ ! -x "$DIR/godot" ]; then
	NAME="Godot_v${VERSION}_linux.x86_64"
	curl -fsSL -o "$DIR/godot.zip" "https://github.com/$REPO/releases/download/$VERSION/$NAME.zip"
	unzip -oq "$DIR/godot.zip" -d "$DIR"
	mv "$DIR/$NAME" "$DIR/godot"
	rm "$DIR/godot.zip"
fi
"$DIR/godot" --version
