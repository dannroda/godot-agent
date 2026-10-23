#!/bin/sh
# Baja el editor de Godot para Linux y deja el binario en $1/godot.
# Uso: install-godot.sh <carpeta> <versión>   (4.6.3-stable, 4.7.2-stable, 4.8-beta1…)
# Las estables salen de godotengine/godot y las demás (beta, rc, dev) de godotengine/godot-builds.
set -eu
DIR="$1"
VERSION="$2"
case "$VERSION" in
	*-stable) REPO=godotengine/godot ;;
	*) REPO=godotengine/godot-builds ;;
esac
NAME="Godot_v${VERSION}_linux.x86_64"
mkdir -p "$DIR"
if [ ! -x "$DIR/godot" ]; then
	curl -fsSL -o "$DIR/godot.zip" "https://github.com/$REPO/releases/download/$VERSION/$NAME.zip"
	unzip -oq "$DIR/godot.zip" -d "$DIR"
	mv "$DIR/$NAME" "$DIR/godot"
	rm "$DIR/godot.zip"
fi
"$DIR/godot" --version
