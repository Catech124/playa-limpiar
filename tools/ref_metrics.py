"""Mide una lámina de referencia (o un render propio) y saca las proporciones
que importan, normalizadas por la altura total del personaje.

No mide "a ojo": clasifica por color (piel / paja / camiseta / pantalón /
blanco) y por silueta, y devuelve fracciones de la altura total. Así se puede
comparar la referencia con el render del modelo con los MISMOS números.

Uso:
    python3 tools/ref_metrics.py --img ref.png --crop 20,60,330,470 --label REF
    python3 tools/ref_metrics.py --img /tmp/opencode/views/frente.png --label MIO
"""

import argparse
import json
import sys

import numpy as np
from PIL import Image

# ventanas HSV (grados, 0-1, 0-1) para cada parte del personaje
CLASSES = {
    "piel":     dict(h=(8, 32), s=(0.18, 0.62), v=(0.45, 1.0)),
    "paja":     dict(h=(35, 58), s=(0.22, 0.62), v=(0.62, 1.0)),
    "camiseta": dict(h=(42, 62), s=(0.62, 1.0), v=(0.60, 1.0)),
    "pantalon": dict(h=(195, 255), s=(0.18, 0.75), v=(0.15, 0.62)),
    "blanco":   dict(h=(0, 360), s=(0.0, 0.14), v=(0.80, 1.0)),
}


def load(path, crop=None):
    a = np.asarray(Image.open(path).convert("RGB")).astype(float) / 255.0
    if crop:
        a = a[crop[1]:crop[3], crop[0]:crop[2]]
    mx, mn = a.max(2), a.min(2)
    v = mx
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    d = mx - mn + 1e-9
    h = np.where(mx == r, ((g - b) / d) % 6,
                 np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return a, h, s, v


def klass(h, s, v, spec):
    return (h >= spec["h"][0]) & (h <= spec["h"][1]) & \
           (s >= spec["s"][0]) & (s <= spec["s"][1]) & \
           (v >= spec["v"][0]) & (v <= spec["v"][1])


def silhouette(masks, h, s, v):
    """Silueta = unión de las clases + el trazo oscuro (ojos/cejas/contorno).
    El fondo gris del render y de la lámina se descarta aparte."""
    m = np.zeros_like(next(iter(masks.values())))
    for k in masks:
        m |= masks[k]
    m |= (v < 0.30)                      # ojos, cejas, boca, contorno
    bg = (s < 0.06) & (v > 0.30) & (v < 0.80)   # gris del fondo (degradado)
    m &= ~bg
    # la base/escalón se come si la última fila tiene mucha más anchura que la
    # mediana de las piernas: recortamos filas finales cuyo ancho > 1.6x mediana
    widths = np.array([(np.where(row)[0].max() - np.where(row)[0].min() + 1) if row.any() else 0
                       for row in m])
    rows = np.where(widths > 0)[0]
    if len(rows) == 0:
        return m, widths
    tail = rows[-int(len(rows) * 0.12):]
    med = np.median(widths[tail])
    for r in rows[::-1]:
        if widths[r] > 1.6 * max(med, 1):
            m[r] = False
        else:
            break
    return m, widths


def measure(path, crop=None):
    a, h, s, v = load(path, crop)
    masks = {k: klass(h, s, v, spec) for k, spec in CLASSES.items()}
    sil, widths = silhouette(masks, h, s, v)
    ys, xs = np.where(sil)
    if len(ys) == 0:
        raise SystemExit("silueta vacía: revisá el recorte")
    top, bot = ys.min(), ys.max()
    H = bot - top + 1
    frac = lambda r: (r - top) / H

    out = {"H_px": int(H), "ancho_total": float((xs.max() - xs.min() + 1) / H)}

    def band(name):
        yy, xx = np.where(masks[name])
        if len(yy) == 0:
            return None
        return {"y0": round(float(frac(yy.min())), 3), "y1": round(float(frac(yy.max())), 3),
                "alto": round(float((yy.max() - yy.min()) / H), 3),
                "ancho": round(float((xx.max() - xx.min() + 1) / H), 3)}

    for k in CLASSES:
        out[f"banda_{k}"] = band(k)

    # ancho en fracciones clave
    at = lambda p: float(widths[min(top + int(p * H), len(widths) - 1)] / H)
    out["ala"] = round(max(widths[top:top + max(1, int(H * 0.32))]) / H, 3)
    out["cabeza_40"] = round(at(0.40), 3)
    out["brazos_55"] = round(at(0.55), 3)
    out["torso_66"] = round(at(0.66), 3)
    out["piernas_85"] = round(at(0.85), 3)
    out["_widths"] = widths.tolist()
    out["_top"] = int(top)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--img", required=True)
    ap.add_argument("--crop", default=None, help="x0,y0,x1,y1")
    ap.add_argument("--label", default="")
    ap.add_argument("--json", default=None)
    args = ap.parse_args()

    crop = tuple(int(v) for v in args.crop.split(",")) if args.crop else None
    m = measure(args.img, crop)
    print(f"== {args.label or args.img}  (H={m['H_px']}px)")
    for k in ("piel", "paja", "camiseta", "pantalon", "blanco"):
        b = m[f"banda_{k}"]
        if b:
            print(f"   {k:9s} {b['y0']*100:5.1f}%..{b['y1']*100:5.1f}%  alto {b['alto']*100:4.1f}%  ancho {b['ancho']:.3f}")
        else:
            print(f"   {k:9s} (no detectado)")
    print(f"   ala (máx)      {m['ala']:.3f}   cabeza@40% {m['cabeza_40']:.3f}   brazos@55% {m['brazos_55']:.3f}")
    print(f"   torso@66%      {m['torso_66']:.3f}   piernas@85% {m['piernas_85']:.3f}   ancho total {m['ancho_total']:.3f}")
    if args.json:
        json.dump(m, open(args.json, "w"), indent=1)


if __name__ == "__main__":
    main()
