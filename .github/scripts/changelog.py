"""Sección Unreleased de CHANGELOG.md para el release.

Uso:
  changelog.py notes              imprime la sección Unreleased (falla si está vacía)
  changelog.py release X.Y.Z      la pasa a "## [X.Y.Z] - fecha" y deja Unreleased vacía
"""
import datetime
import re
import sys

PATH = "CHANGELOG.md"
HEADER = "## [Unreleased]"


def split(text):
    start = text.find(HEADER)
    if start < 0:
        sys.exit(f"{PATH} has no '{HEADER}' section")
    body_start = start + len(HEADER)
    following = re.search(r"^## \[", text[body_start:], re.M)
    end = body_start + following.start() if following else len(text)
    return text[:body_start], text[body_start:end], text[end:]


def main():
    text = open(PATH, encoding="utf-8").read()
    head, body, tail = split(text)
    if not body.strip():
        sys.exit(f"The '{HEADER}' section of {PATH} is empty: add the release's changes there first.")
    if sys.argv[1] == "notes":
        print(body.strip())
    elif sys.argv[1] == "release":
        version = sys.argv[2]
        date = datetime.date.today().isoformat()
        new = f"{head}\n\n## [{version}] - {date}\n\n{body.strip()}\n\n{tail.lstrip()}"
        open(PATH, "w", encoding="utf-8").write(new.rstrip() + "\n")
    else:
        sys.exit(__doc__)


main()
