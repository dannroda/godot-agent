"""Copia docs/wiki/ a un checkout de la wiki de GitHub, o solo revisa sus links.

La wiki de GitHub es plana y enlaza por nombre de página, sin ".md": las páginas de en/ quedan con su
nombre, las de es/ también salvo las que chocan con una de en/ (One-shot, Settings), que pasan a
"<nombre>-es". Una página nueva entra sola con esa misma regla. Los links entre páginas se reescriben
a esos nombres. Borra antes los .md de la wiki, así una página quitada de docs/wiki/ desaparece
también allá.

Antes de escribir nada revisa que cada link entre páginas (y cada #ancla, también las de la misma
página) apunte a algo que existe; si no, sale con error y no toca la wiki.

Uso:
  python3 .github/scripts/wiki.py <checkout de la wiki>   copia (la usa el workflow wiki.yml)
  python3 .github/scripts/wiki.py --check                  solo revisa los links (la usa el CI)
"""
import pathlib
import re
import sys

SOURCE = pathlib.Path("docs/wiki")
# Un link a otra página de la wiki: Page.md, ../en/Page.md, con o sin #ancla.
PAGE_LINK = re.compile(r"\]\((?:\.\./(en|es)/)?([^)#:/]+)\.md(#[^)]*)?\)")
# Un link a un ancla de la misma página.
SELF_LINK = re.compile(r"\]\((#[^)]+)\)")
HEADING = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$")
FENCE = re.compile(r"^\s*(```|~~~)")


def page_names() -> dict:
    english = {page.stem for page in (SOURCE / "en").glob("*.md")}
    names = {("en", stem): stem for stem in english}
    for page in (SOURCE / "es").glob("*.md"):
        names[("es", page.stem)] = page.stem + "-es" if page.stem in english else page.stem
    return names


def anchors(text: str) -> set:
    """Las anclas que GitHub genera para los títulos: minúsculas, sin puntuación, espacios a guiones,
    y "-1", "-2"… para los títulos repetidos."""
    seen: dict = {}
    result = set()
    fenced = False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        match = None if fenced else HEADING.match(line)
        if not match:
            continue
        title = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", match.group(1))
        title = title.replace("`", "").replace("*", "")
        slug = re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        result.add(slug if count == 0 else f"{slug}-{count}")
    return result


def check(names: dict, texts: dict) -> list:
    page_anchors = {key: anchors(text) for key, text in texts.items()}
    errors = []
    for (lang, stem), text in texts.items():
        where = f"docs/wiki/{lang}/{stem}.md"
        for match in PAGE_LINK.finditer(text):
            key = (match.group(1) or lang, match.group(2))
            if key not in names:
                errors.append(f"{where}: links to a missing page: {match.group(0)}")
            elif match.group(3) and match.group(3)[1:] not in page_anchors[key]:
                errors.append(f"{where}: links to a missing heading: {match.group(0)}")
        for match in SELF_LINK.finditer(text):
            if match.group(1)[1:] not in page_anchors[(lang, stem)]:
                errors.append(f"{where}: links to a missing heading: {match.group(0)}")
    return errors


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    names = page_names()
    texts = {key: (SOURCE / key[0] / f"{key[1]}.md").read_text(encoding="utf-8") for key in names}
    errors = check(names, texts)
    if errors:
        sys.exit("\n".join(errors))
    if sys.argv[1] == "--check":
        print(f"docs/wiki: {len(names)} pages, links ok")
        return

    target = pathlib.Path(sys.argv[1])
    for old in target.glob("*.md"):
        old.unlink()
    for (lang, stem), name in names.items():

        def fix(match: re.Match) -> str:
            return f"]({names[(match.group(1) or lang, match.group(2))]}{match.group(3) or ''})"

        (target / f"{name}.md").write_text(PAGE_LINK.sub(fix, texts[(lang, stem)]), encoding="utf-8")


main()
