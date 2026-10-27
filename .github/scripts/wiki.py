"""Copia docs/wiki/ a un checkout de la wiki de GitHub.

La wiki de GitHub es plana y enlaza por nombre de página, sin ".md": las páginas de en/ quedan con su
nombre, las de es/ también salvo las que chocan con una de en/ (One-shot, Settings), que pasan a
"<nombre>-es". Los links entre páginas se reescriben a esos nombres. Borra antes los .md de la wiki,
así una página quitada de docs/wiki/ desaparece también allá.

Uso: python3 .github/scripts/wiki.py <checkout de la wiki>
"""
import pathlib
import re
import sys

SOURCE = pathlib.Path("docs/wiki")
LINK = re.compile(r"\]\((?:\.\./(en|es)/)?([^)#:/]+)\.md(#[^)]*)?\)")


def main() -> None:
    target = pathlib.Path(sys.argv[1])
    english = {page.stem for page in (SOURCE / "en").glob("*.md")}
    names = {("en", stem): stem for stem in english}
    for page in (SOURCE / "es").glob("*.md"):
        names[("es", page.stem)] = page.stem + "-es" if page.stem in english else page.stem

    for old in target.glob("*.md"):
        old.unlink()
    for (lang, stem), name in names.items():
        text = (SOURCE / lang / f"{stem}.md").read_text(encoding="utf-8")

        def fix(match: re.Match) -> str:
            key = (match.group(1) or lang, match.group(2))
            if key not in names:
                sys.exit(f"{lang}/{stem}.md links to a missing page: {match.group(0)}")
            return f"]({names[key]}{match.group(3) or ''})"

        (target / f"{name}.md").write_text(LINK.sub(fix, text), encoding="utf-8")


main()
