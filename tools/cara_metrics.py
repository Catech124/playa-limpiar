#!/usr/bin/env python3
"""cara_metrics.py — mide una cara frontal en píxeles (sin ojo humano, sin ML).

Para qué: la cara se estaba ajustando "a ojo" contra la lámina, y el ojo miente.
Este script mide lo mismo en la referencia y en el render y devuelve RATIOS
independientes de la escala:

    ojo/ancho_cabeza · separación/ancho · alto/ancho del ojo · boca/ancho
    ojos→boca (fracción del alto de la cabeza)

Uso:
    python3 tools/cara_metrics.py docs/referencia.png --recorte 40,80,230,240
    python3 tools/cara_metrics.py /tmp/opencode/cara-v3c/cara.png
    python3 tools/cara_metrics.py A.png B.png --comparar
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import deque

import numpy as np
from PIL import Image


def carga(path, recorte=None):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(int)
    if recorte:
        x, y, w, h = [int(v) for v in recorte.split(",")]
        a = a[y:y + h, x:x + w]
    return a


def mascaras(a):
    """Piel, ojos (muy oscuro) y boca (oscuro cálido) por color.

    La piel del personaje es un naranja apagado; el fondo de la lámina es gris y el
    de los renders es alfa (convertido a negro al pasar a RGB), así que la piel se
    separa bien exigiendo R dominante sobre B.
    """
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    lum = a.mean(2)
    # La paja del sombrero (#DDBE86) y la piel (#E39F7C) se parecen: las separa la
    # proporción de verde, no el brillo. Piel g/r≈0.70, paja g/r≈0.86.
    piel = (r > 110) & (r - b > 35) & (g / np.maximum(r, 1) < 0.78) & (lum > 55)
    ojos = lum < 55
    return piel, ojos


def componentes(mask, minpx=20):
    """Etiquetado 4-conectado (BFS). Sin scipy: el entorno no lo tiene."""
    h, w = mask.shape
    vistos = np.zeros_like(mask, bool)
    out = []
    for yy in range(h):
        fila = mask[yy]
        for xx in range(w):
            if not fila[xx] or vistos[yy, xx]:
                continue
            cola = deque([(yy, xx)])
            vistos[yy, xx] = True
            pts = []
            while cola:
                cy, cx = cola.popleft()
                pts.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not vistos[ny, nx]:
                        vistos[ny, nx] = True
                        cola.append((ny, nx))
            if len(pts) >= minpx:
                P = np.array(pts)
                out.append({"n": len(pts),
                            "x0": int(P[:, 1].min()), "x1": int(P[:, 1].max()),
                            "y0": int(P[:, 0].min()), "y1": int(P[:, 0].max()),
                            "cx": float(P[:, 1].mean()), "cy": float(P[:, 0].mean())})
    return sorted(out, key=lambda c: -c["n"])


def mide(path, recorte=None):
    a = carga(path, recorte)
    piel, oscuro = mascaras(a)
    cy_piel = componentes(piel, 400)
    if not cy_piel:
        return {"error": "no encontré piel"}
    cabeza = cy_piel[0]
    ancho = cabeza["x1"] - cabeza["x0"]
    alto = cabeza["y1"] - cabeza["y0"]
    # los ojos son los dos oscuros más grandes en el tercio superior de la cabeza
    tercio = cabeza["y0"] + (cabeza["y1"] - cabeza["y0"]) * 0.45
    cand = [c for c in componentes(oscuro, 8) if c["cy"] < tercio
            and cabeza["x0"] <= c["cx"] <= cabeza["x1"]]
    cand.sort(key=lambda c: -c["n"])
    ojos = sorted(cand[:2], key=lambda c: c["cx"])
    boca_c = [c for c in componentes(oscuro, 8)
              if c["cy"] > tercio and cabeza["x0"] <= c["cx"] <= cabeza["x1"]]
    boca_c.sort(key=lambda c: -c["n"])
    boca = boca_c[0] if boca_c else None
    res = {"archivo": path, "cabeza_px": [ancho, alto], "ratio_ancho_alto": round(ancho / alto, 3)}
    if len(ojos) == 2:
        o = ojos
        d_ojos = [((c["x1"] - c["x0"]), (c["y1"] - c["y0"])) for c in o]
        sep = abs(o[1]["cx"] - o[0]["cx"])
        alto_ojo = sum(d[1] for d in d_ojos) / 2
        ancho_ojo = sum(d[0] for d in d_ojos) / 2
        res.update({
            "ojo_ancho_px": round(ancho_ojo, 1),
            "ojo_alto_px": round(alto_ojo, 1),
            "ojo_ancho/ancho_cabeza": round(ancho_ojo / ancho, 3),
            "ojo_alto/ancho_ojo": round(alto_ojo / ancho_ojo, 2),
            "separacion/ancho_cabeza": round(sep / ancho, 3),
            "separacion/diametro_ojo": round(sep / max(ancho_ojo, 1e-6), 2),
        })
    if boca:
        res["boca_ancho/ancho_cabeza"] = round((boca["x1"] - boca["x0"]) / ancho, 3)
        if len(ojos) == 2:
            oy = sum(c["cy"] for c in ojos) / 2
            res["ojos_a_boca/alto_cabeza"] = round((boca["cy"] - oy) / alto, 3)
    return res


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("imagenes", nargs="+")
    ap.add_argument("--recorte", default="", help="x,y,w,h (solo si hay una imagen)")
    ap.add_argument("--comparar", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    res = [mide(p, args.recorte if len(args.imagenes) == 1 else None)
           for p in args.imagenes]
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
        return 0
    claves = ["ojo_ancho/ancho_cabeza", "ojo_alto/ancho_ojo", "separacion/ancho_cabeza",
              "separacion/diametro_ojo", "boca_ancho/ancho_cabeza", "ojos_a_boca/alto_cabeza"]
    print(f"{'métrica':28s}" + "".join(f"{p.split('/')[-1][:18]:>20s}" for p in args.imagenes))
    for k in claves:
        fila = f"{k:28s}"
        for r in res:
            v = r.get(k)
            fila += f"{(f'{v:.3f}' if isinstance(v, (int, float)) else '—'):>20s}"
        print(fila)
    return 0


if __name__ == "__main__":
    sys.exit(main())
