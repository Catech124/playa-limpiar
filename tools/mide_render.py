#!/usr/bin/env python3
"""Mide la silueta de un render del personaje para comparar proporciones.

Uso: python3 tools/mide_render.py /tmp/kid/kid.png

Segmenta el personaje por diferencia con el fondo (esquinas), recorta el bbox y
mide el perfil de anchos por franjas para estimar sombrero, cabeza, torso y
piernas. Imprime ratios relativos al alto total (que es comparable entre
renders aunque cambie la escala).
"""
import sys

from PIL import Image


def medidas(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()

    def dist(c):
        # con alfa: el personaje es donde alpha > 0.5
        if len(c) == 4:
            return 255 if c[3] > 128 else 0
        return 0

    minx, maxx, miny, maxy = w, 0, h, 0
    for y in range(h):
        for x in range(w):
            if dist(px[x, y]) > 26:
                minx = min(minx, x)
                maxx = max(maxx, x)
                miny = min(miny, y)
                maxy = max(maxy, y)
    if maxx <= minx:
        print("no se detectó silueta")
        return
    ancho = maxx - minx + 1
    alto = maxy - miny + 1

    # perfil de ancho por filas (5% del alto)
    perfil = []
    paso = max(1, alto // 20)
    for y in range(miny, maxy + 1, paso):
        xs = [x for x in range(minx, maxx + 1) if dist(px[x, y]) > 26]
        perfil.append((round((y - miny) / alto, 2), (len(xs) / ancho) if xs else 0.0))
    ancho_max = max(p[1] for p in perfil)

    print(f"archivo: {path}")
    print(f"bbox {ancho}x{alto} px")
    print("perfil (alto_rel, ancho_rel):")
    for r, a in perfil:
        barra = "#" * int(a * 40)
        print(f"  {r:>4}  {a:>5.2f} {barra}")
    print(f"ancho máximo relativo: {ancho_max:.2f}")


PALETA = {
    "piel": (0.96, 0.75, 0.60),
    "piel_osc": (0.90, 0.63, 0.50),
    "blanco": (0.97, 0.97, 0.95),
    "raya": (0.33, 0.50, 0.78),
    "short": (0.13, 0.19, 0.38),
    "paja": (0.80, 0.66, 0.42),
    "paja_clara": (0.87, 0.74, 0.50),
    "paja_osc": (0.63, 0.48, 0.29),
    "pelo": (0.38, 0.23, 0.13),
    "pelo_osc": (0.28, 0.16, 0.09),
    "negro": (0.08, 0.07, 0.09),
    "iris": (0.56, 0.35, 0.18),
    "boca": (0.42, 0.18, 0.16),
    "rubor": (0.97, 0.62, 0.58),
    "sandalia": (0.30, 0.50, 0.80),
    "guante": (0.55, 0.38, 0.24),
}


def partes(path):
    """Clasifica cada píxel del personaje al color de paleta más cercano y
    reporta bbox y proporciones por parte (sombrero, pelo, cara, torso...)."""
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    px = im.load()
    acc = {}
    minx, maxx, miny, maxy = w, 0, h, 0
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if c[3] < 128:
                continue
            minx, maxx = min(minx, x), max(maxx, x)
            miny, maxy = min(miny, y), max(maxy, y)
            best, bd = None, 9.0
            for name, (r, g, b) in PALETA.items():
                d = (c[0] / 255 - r) ** 2 + (c[1] / 255 - g) ** 2 + (c[2] / 255 - b) ** 2
                if d < bd:
                    bd, best = d, name
            if bd > 0.02:
                best = "otro"
            a = acc.setdefault(best, [0, w, -1, h, -1])
            a[0] += 1
            a[1], a[2] = min(a[1], x), max(a[2], x)
            a[3], a[4] = min(a[3], y), max(a[4], y)

    alto = maxy - miny + 1
    print(f"{path}  alto={alto}px  ancho_total={maxx - minx + 1}px")
    print(f"{'parte':<11}{'ancho':>6}{'alto':>6}{'ancho/Alto':>11}{'y_rel':>8}")
    for name, (n, x0, x1, y0, y1) in sorted(acc.items(), key=lambda kv: -kv[1][0]):
        if n < 60:
            continue
        an, al = x1 - x0 + 1, y1 - y0 + 1
        print(f"{name:<11}{an:>6}{al:>6}{an / alto:>11.2f}{(y0 - miny) / alto:>8.2f}")


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "/tmp/kid/kid.png"
    medidas(arg)
    print()
    partes(arg)
