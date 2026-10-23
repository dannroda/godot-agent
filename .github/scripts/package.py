"""Arma el zip del release: todo dentro de addons/godot_agent/.

Toma lo que está en git de addons/godot_agent/ (nada de la config local ni del plugin de dev) y le
suma README.md, README.es.md, CHANGELOG.md y LICENSE dentro de la carpeta del addon. Los links
relativos de los READMEs (wiki, capturas, CONTRIBUTING…) apuntan a archivos que no viajan en el zip:
pasan a URLs de GitHub fijadas al tag (las imágenes, a raw.githubusercontent.com).

Uso: python3 .github/scripts/package.py <versión> <zip de salida>
"""

import io
import re
import subprocess
import sys
import tarfile
import zipfile

REPO = "dannroda/godot-agent"
ADDON = "addons/godot_agent/"
EXTRA = ["README.md", "README.es.md", "CHANGELOG.md", "LICENSE"]
IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp")
# Markdown [texto](destino) y HTML src="destino".
LINK = re.compile(r'(\]\(|src=")([^)"#][^)"]*)')


def absolute_links(text: str, tag: str) -> str:
    def fix(match: re.Match) -> str:
        prefix, target = match.group(1), match.group(2)
        path = target.split("#")[0]
        if re.match(r"^[a-z]+:", target) or path in EXTRA:
            return match.group(0)
        if path.lower().endswith(IMAGE_EXTENSIONS):
            return f"{prefix}https://raw.githubusercontent.com/{REPO}/{tag}/{target}"
        return f"{prefix}https://github.com/{REPO}/blob/{tag}/{target}"

    return LINK.sub(fix, text)


def tracked_addon_files() -> dict[str, bytes]:
    archive = subprocess.run(["git", "archive", "--format=tar", "HEAD", ADDON], check=True, capture_output=True).stdout
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if member.isfile():
                files[member.name] = tar.extractfile(member).read()
    return files


def main() -> None:
    version, out = sys.argv[1], sys.argv[2]
    tag = f"v{version}"
    files = tracked_addon_files()
    for name in EXTRA:
        data = open(name, "rb").read()
        if name.startswith("README"):
            data = absolute_links(data.decode("utf-8"), tag).encode("utf-8")
        files[ADDON + name] = data
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            archive.writestr(name, files[name])
    outside = [name for name in files if not name.startswith(ADDON)]
    if outside:
        sys.exit(f"archivos fuera de {ADDON}: {outside}")
    print(f"{out}: {len(files)} archivos, todos en {ADDON}")


if __name__ == "__main__":
    main()
