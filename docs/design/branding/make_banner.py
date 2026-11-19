"""Banner del README: logo + nombre + bajada, con el texto pasado a trazos (Sora, OFL).

Uso: python make_banner.py <Sora[wght].ttf> <carpeta de salida>
  Necesita fonttools (pip install fonttools). La fuente: github.com/google/fonts/tree/main/ofl/sora.
  Escribe banner-en.svg y banner-es.svg; los PNG salen de esos SVG con Image.load_svg_from_string.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

W, H = 1280, 640
BG, GRID, AXIS = "#1d212b", "#252a36", "#2c3242"
TILE, AMBER, TEXT, MUTED = "#262b38", "#f0a85a", "#f1f2f5", "#a3aab8"
SUBTITLES = {
    "en": "A coding agent inside the Godot editor",
    "es": "Un agente de código dentro del editor de Godot",
}


def instance(path: str, weight: int) -> TTFont:
    return instantiateVariableFont(TTFont(path), {"wght": weight})


def kerning(font: TTFont) -> dict:
    """Pares de kerning simples de GPOS (PairPos formato 1 y 2)."""
    pairs: dict = {}
    if "GPOS" not in font:
        return pairs
    for lookup in font["GPOS"].table.LookupList.Lookup:
        for sub in lookup.SubTable:
            if lookup.LookupType == 9:
                sub = sub.ExtSubTable
            if getattr(sub, "LookupType", lookup.LookupType) != 2:
                continue
            if sub.Format == 1:
                for i, first in enumerate(sub.Coverage.glyphs):
                    for record in sub.PairSet[i].PairValueRecord:
                        value = record.Value1
                        if value is not None and getattr(value, "XAdvance", 0):
                            pairs.setdefault((first, record.SecondGlyph), value.XAdvance)
            elif sub.Format == 2:
                class1 = sub.ClassDef1.classDefs
                class2 = sub.ClassDef2.classDefs
                for first in sub.Coverage.glyphs:
                    record1 = sub.Class1Record[class1.get(first, 0)]
                    for second, c2 in list(class2.items()):
                        value = record1.Class2Record[c2].Value1
                        if value is not None and getattr(value, "XAdvance", 0):
                            pairs.setdefault((first, second), value.XAdvance)
    return pairs


def text_path(font: TTFont, text: str, size: float, x: float, baseline: float) -> tuple[str, float]:
    """(d de SVG, ancho) del texto con su esquina izquierda en x."""
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    hmtx = font["hmtx"]
    kern = kerning(font)
    scale = size / font["head"].unitsPerEm
    names = [cmap[ord(ch)] for ch in text]
    pen = SVGPathPen(glyphs)
    cursor = 0.0
    for i, name in enumerate(names):
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x + cursor * scale, baseline)))
        cursor += hmtx[name][0]
        if i + 1 < len(names):
            cursor += kern.get((name, names[i + 1]), 0)
    return pen.getCommands(), cursor * scale


def measure(font: TTFont, text: str, size: float) -> float:
    return text_path(font, text, size, 0, 0)[1]


def logo(x: float, y: float, size: float) -> str:
    s = size / 128
    return f'''<g transform="translate({x:.1f} {y:.1f}) scale({s:.4f})">
  <rect x="4" y="4" width="120" height="120" rx="28" fill="{TILE}" stroke="#343b4c" stroke-width="1.5"/>
  <path d="M38 22 H90 A18 18 0 0 1 108 40 V74 A18 18 0 0 1 90 92 H62 L40 108 L44 92 H38 A18 18 0 0 1 20 74 V40 A18 18 0 0 1 38 22Z" fill="{AMBER}"/>
  <path d="M42 44 L58 57 L42 70" fill="none" stroke="{TILE}" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M68 70 H88" fill="none" stroke="{TILE}" stroke-width="9" stroke-linecap="round"/>
</g>'''


def grid() -> str:
    """La grilla del viewport 2D de Godot, tenue, con sus dos ejes."""
    lines = []
    for gx in range(0, W + 1, 32):
        lines.append(f"M{gx} 0V{H}")
    for gy in range(0, H + 1, 32):
        lines.append(f"M0 {gy}H{W}")
    return (f'<path d="{"".join(lines)}" stroke="{GRID}" stroke-width="1" fill="none"/>'
            f'<path d="M0 {H - 96}H{W}" stroke="{AXIS}" stroke-width="2" fill="none"/>'
            f'<path d="M96 0V{H}" stroke="{AXIS}" stroke-width="2" fill="none"/>')


def banner(bold: TTFont, regular: TTFont, subtitle: str) -> str:
    title = "Godot Agent Harness"
    title_size, sub_size = 92, 34
    logo_size = 176
    tw = measure(bold, title, title_size)
    sw = measure(regular, subtitle, sub_size)
    top = 142
    title_base = top + logo_size + 44 + title_size * 0.74
    sub_base = title_base + 36 + sub_size * 0.74
    title_d, _ = text_path(bold, title, title_size, (W - tw) / 2, title_base)
    sub_d, _ = text_path(regular, subtitle, sub_size, (W - sw) / 2, sub_base)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
<title>Godot Agent Harness</title>
<rect width="{W}" height="{H}" fill="{BG}"/>
{grid()}
<radialGradient id="glow" cx="50%" cy="38%" r="55%"><stop offset="0" stop-color="{BG}" stop-opacity="0"/><stop offset="1" stop-color="{BG}" stop-opacity=".85"/></radialGradient>
<rect width="{W}" height="{H}" fill="url(#glow)"/>
{logo((W - logo_size) / 2, top, logo_size)}
<path d="{title_d}" fill="{TEXT}"/>
<path d="{sub_d}" fill="{MUTED}"/>
</svg>
'''


def main() -> None:
    font_path, out = sys.argv[1], sys.argv[2]
    bold, regular = instance(font_path, 650), instance(font_path, 400)
    for lang, subtitle in SUBTITLES.items():
        path = f"{out}/banner-{lang}.svg"
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(banner(bold, regular, subtitle))
        print(path)


if __name__ == "__main__":
    main()
