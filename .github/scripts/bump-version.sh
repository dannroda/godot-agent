#!/bin/sh
# Sube la versión del addon en plugin.cfg (la única fuente: ACP y MCP la leen de ahí) e imprime
# la nueva. Uso: bump-version.sh patch|minor|major|X.Y.Z
set -eu
CFG=addons/godot_agent/plugin.cfg
CURRENT=$(sed -n 's/^version="\([0-9]*\.[0-9]*\.[0-9]*\)"$/\1/p' "$CFG")
if [ -z "$CURRENT" ]; then
	echo "no version=\"X.Y.Z\" in $CFG" >&2
	exit 1
fi
MAJOR=${CURRENT%%.*}
REST=${CURRENT#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}
case "$1" in
	patch) NEXT="$MAJOR.$MINOR.$((PATCH + 1))" ;;
	minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
	major) NEXT="$((MAJOR + 1)).0.0" ;;
	*)
		if ! echo "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
			echo "expected patch, minor, major or X.Y.Z, got '$1'" >&2
			exit 1
		fi
		NEXT="$1"
		;;
esac
sed -i "s/^version=\"$CURRENT\"$/version=\"$NEXT\"/" "$CFG"
echo "$NEXT"
