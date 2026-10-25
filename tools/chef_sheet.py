"""
Métricas + hoja de contacto de un barrido de personajes.

    python3 tools/chef_sheet.py <carpeta_del_barrido> <salida.png> [--ref <id>]

Lee los renders que dejó tools/gen_chef.py (<id>.front.png, .game.png,
.mask.png, .game_mask.png, .json) y calcula:

  head_ratio     altura de cabeza / altura total (sin gorro)
  hat_ratio      altura del gorro / altura total
  face_vis       % del área de cara que sobrevive a la cámara del juego
                 (contra el baseline sin gorro, misma cámara)
  parts_64       componentes conexos de la silueta reducida a 64 px
  profile_min    mínimos locales del perfil de ancho por filas
  dE             ΔE(CIELAB) del gorro y del torso contra la arena

Descarta sin mirar: si no pasa los umbrales, no debería llegar a la hoja.
"""

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SAND = "#DDB97F"
ID_COLORS = {
    "hat": (255, 0, 0),
    "head": (0, 255, 0),
    "face": (0, 0, 255),
    "torso": (255, 255, 0),
    "arms": (255, 0, 255),
    "hands": (0, 255, 255),
    "legs": (255, 128, 0),
    "boots": (128, 0, 255),
    "shorts": (255, 255, 255),
}
TOL = 40


# --------------------------------------------------------------------------- #
# color
# --------------------------------------------------------------------------- #
def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def rgb_to_lab(rgb):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(v) for v in rgb)
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.00000
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(hex_a, hex_b):
    la, aa, ba = rgb_to_lab(hex_to_rgb(hex_a))
    lb, ab, bb = rgb_to_lab(hex_to_rgb(hex_b))
    return math.sqrt((la - lb) ** 2 + (aa - ab) ** 2 + (ba - bb) ** 2)


# --------------------------------------------------------------------------- #
# máscaras
# --------------------------------------------------------------------------- #
def load_mask(path):
    img = Image.open(path).convert("RGB")
    return np.asarray(img).astype(int)


def color_mask(arr, rgb):
    return (np.abs(arr - np.array(rgb)).sum(axis=2) < TOL)


def bbox(mask):
    ys, xs = np.where(mask)
    if len(ys) == 0:
        return None
    return xs.min(), ys.min(), xs.max(), ys.max()


def part_masks(arr):
    return {name: color_mask(arr, rgb) for name, rgb in ID_COLORS.items()}


def silhouette(arr):
    bg = arr[0, 0]
    return np.abs(arr - bg).sum(axis=2) > 30


def components(mask, min_px=6):
    """Componentes conexos 4-vecinos (imagen chica: BFS con pila)."""
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    count = 0
    for y in range(h):
        for x in range(w):
            if not mask[y, x] or seen[y, x]:
                continue
            stack = [(y, x)]
            seen[y, x] = True
            size = 0
            while stack:
                cy, cx = stack.pop()
                size += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
            if size >= min_px:
                count += 1
    return count


def profile_minima(sil):
    """Cuenta mínimos locales del ancho por fila (gorro-cuello-cintura)."""
    widths = sil.sum(axis=1).astype(float)
    rows = np.where(widths > 0)[0]
    if len(rows) < 12:
        return 0
    w = widths[rows[0]:rows[-1] + 1]
    k = max(1, len(w) // 24)
    smooth = np.convolve(w, np.ones(k) / k, mode="same")
    mins = 0
    for i in range(2, len(smooth) - 2):
        if smooth[i] < smooth[i - 1] and smooth[i] <= smooth[i + 1]:
            if smooth[i] < 0.92 * max(smooth[max(0, i - 6):i + 6]):
                mins += 1
    return mins


# --------------------------------------------------------------------------- #
# métricas por variante
# --------------------------------------------------------------------------- #
def analyse(folder, vid, base):
    with open(os.path.join(folder, f"{vid}.json")) as fh:
        meta = json.load(fh)
    P = meta["params"]

    front = load_mask(os.path.join(folder, f"{vid}.mask.png"))
    game = load_mask(os.path.join(folder, f"{vid}.game_mask.png"))

    pm = part_masks(front)
    sil = silhouette(front)
    sb = bbox(sil)
    total_h = (sb[3] - sb[1] + 1) if sb else 0

    hat_bb = bbox(pm["hat"])
    hat_h = (hat_bb[3] - hat_bb[1] + 1) if hat_bb else 0

    # la cabeza se mide en el baseline (sin gorro): el gorro la tapa en las
    # variantes y medirla ahí subestimaría el cuerpo, que está congelado
    head_h = base["head_h"]
    body_h = max(total_h - hat_h, 1)
    head_ratio = float(head_h) / float(body_h)

    face_px_game = int(color_mask(game, ID_COLORS["face"]).sum())
    face_vis = (face_px_game / base["face_px"] * 100.0) if base["face_px"] else 0.0

    small = np.asarray(Image.fromarray((sil * 255).astype(np.uint8)).resize((64, 64), Image.BILINEAR)) > 96
    comps = components(small)

    torso_hex = P["palette"]["shirt"]
    hat_hex = P.get("hat", {}).get("color", "#D9B36A")

    return {
        "id": vid,
        "tipo": P["hat"]["tipo"],
        "copa": P["hat"]["copa_h"],
        "ala": P["hat"].get("ala", 0),
        "tris": meta["tris"],
        "head_ratio": round(head_ratio, 3),
        "hat_ratio": round(hat_h / max(total_h, 1), 3),
        "face_vis": round(face_vis, 1),
        "parts_64": comps,
        "profile_min": profile_minima(sil),
        "dE_torso": round(delta_e(torso_hex, SAND), 1),
        "dE_hat": round(delta_e(hat_hex, SAND), 1),
    }


# --------------------------------------------------------------------------- #
# hoja de contacto
# --------------------------------------------------------------------------- #
def crop_game(folder, vid):
    """Recorta la vista del juego alrededor del personaje y la agranda x3."""
    arr = load_mask(os.path.join(folder, f"{vid}.game_mask.png"))
    sil = silhouette(arr)
    bb = bbox(sil)
    if bb is None:
        return Image.new("RGB", (180, 200), (30, 30, 30))
    x0, y0, x1, y1 = bb
    pad = 12
    img = Image.open(os.path.join(folder, f"{vid}.game.png")).convert("RGB")
    box = (max(0, x0 - pad), max(0, y0 - pad), min(img.width, x1 + pad), min(img.height, y1 + pad))
    crop = img.crop(box)
    scale = 190 / max(crop.width, crop.height)
    return crop.resize((max(1, int(crop.width * scale)), max(1, int(crop.height * scale))), Image.NEAREST)


def sheet(folder, out_path, ids, rows, cols):
    cell_w, cell_h = 320, 512
    W, H = cols * cell_w, rows * cell_h + 96
    canvas = Image.new("RGB", (W, H), (18, 21, 26))
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 17)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
        title_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
    except Exception:
        font = small = title_font = ImageFont.load_default()

    draw.text((20, 22), "Barrido de gorro — cámara real del juego", font=title_font, fill=(240, 244, 250))
    draw.text((20, 58), "cada celda: vista 3/4 + recorte de la cámara del juego (upx3) + métricas",
              font=small, fill=(150, 160, 175))

    for i, (vid, m) in enumerate(ids):
        cx = (i % cols) * cell_w
        cy = (i // cols) * cell_h + 90
        front = Image.open(os.path.join(folder, f"{vid}.front.png")).convert("RGB")
        front.thumbnail((cell_w - 30, 268), Image.LANCZOS)
        canvas.paste(front, (cx + (cell_w - front.width) // 2, cy + 6))

        g = crop_game(folder, vid)
        if g.height > 140:
            g = g.resize((int(g.width * 140 / g.height), 140), Image.NEAREST)
        canvas.paste(g, (cx + (cell_w - g.width) // 2, cy + 280))
        draw.text((cx + cell_w // 2 - 62, cy + 424), "cámara del juego", font=small, fill=(130, 140, 155))

        flag_head = "ok" if 0.44 <= m["head_ratio"] <= 0.50 else "!"
        flag_hat = "ok" if 0.20 <= m["hat_ratio"] <= 0.28 else "!"
        draw.text((cx + 12, cy + 446), f"{vid}  ·  {m['tipo']} {m['copa']} ala {m['ala']}",
                  font=font, fill=(235, 240, 250))
        draw.text((cx + 12, cy + 468),
                  f"cabeza {m['head_ratio']:.2f} [{flag_head}]   gorro {m['hat_ratio']:.2f} [{flag_hat}]",
                  font=small, fill=(180, 195, 210))
        face_col = (120, 230, 150) if m["face_vis"] >= 85 else (240, 130, 120)
        draw.text((cx + 12, cy + 486),
                  f"cara {m['face_vis']:.0f}%   comps64 {m['parts_64']}   ΔE gorro {m['dE_hat']:.0f}   {m['tris']} tris",
                  font=small, fill=face_col)
    canvas.save(out_path)


# --------------------------------------------------------------------------- #
def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    folder = sys.argv[1]
    out = sys.argv[2]

    base = {"face_px": 0, "head_h": 1}
    bp = os.path.join(folder, "baseline_nohat")
    if os.path.exists(f"{bp}.mask.png"):
        bmask = load_mask(f"{bp}.mask.png")
        bsil = silhouette(bmask)
        bparts = part_masks(bmask)
        bbb = bbox(bparts["head"])
        base["head_h"] = int(bbb[3] - bbb[1] + 1) if bbb else 1
        if os.path.exists(f"{bp}.game_mask.png"):
            base["face_px"] = int(color_mask(load_mask(f"{bp}.game_mask.png"), ID_COLORS["face"]).sum())
        print(f"baseline: cabeza={base['head_h']}px cara={base['face_px']}px")
    else:
        print("AVISO: falta baseline_nohat, head_ratio y face_vis no son fiables")

    ids = sorted(f[:-5] for f in os.listdir(folder)
                 if f.endswith(".json") and not f.startswith(("baseline", "metrics")))
    if os.path.exists(f"{bp}.json"):
        ids = ["baseline_nohat"] + ids
    metrics = []
    for vid in ids:
        if vid == "baseline_nohat":
            bsil = silhouette(load_mask(os.path.join(folder, f"{vid}.mask.png")))
            bb = bbox(bsil)
            total = bb[3] - bb[1] + 1
            m = {"id": vid, "tipo": "sin gorro", "copa": 0, "ala": 0, "tris": 0,
                 "head_ratio": round(base["head_h"] / total, 3), "hat_ratio": 0.0,
                 "face_vis": 100.0, "parts_64": components(
                     np.asarray(Image.fromarray((bsil * 255).astype(np.uint8)).resize((64, 64), Image.BILINEAR)) > 96),
                 "profile_min": 0, "dE_torso": 30.0, "dE_hat": 0.0}
            metrics.append(m)
            print(f"{vid}: referencia sin gorro")
            continue
        m = analyse(folder, vid, base)
        metrics.append(m)
        print(f"{vid}: cabeza={m['head_ratio']:.2f} gorro={m['hat_ratio']:.2f} "
              f"cara={m['face_vis']:.0f}% comps64={m['parts_64']} mins={m['profile_min']} tris={m['tris']}")

    with open(os.path.join(folder, "metrics.json"), "w") as fh:
        json.dump({"baseline": base, "variants": metrics}, fh, indent=2)

    cols = 4
    rows = math.ceil(len(ids) / cols)
    sheet(folder, out, [(m["id"], m) for m in metrics], rows, cols)
    print(f"hoja -> {out}")

    # ranking simple: pasa umbrales y maximiza cara visible
    def score(m):
        ok = (0.36 <= m["head_ratio"] <= 0.49 and 0.17 <= m["hat_ratio"] <= 0.31
              and m["parts_64"] == 1 and m["face_vis"] >= 85)
        return (0 if ok else 1, -m["face_vis"], abs(m["hat_ratio"] - 0.24))

    ranked = sorted(metrics, key=score)
    print("\nTOP 5:")
    for m in ranked[:5]:
        print(f"  {m['id']} {m['tipo']} copa={m['copa']} ala={m['ala']} "
              f"cara={m['face_vis']:.0f}% gorro={m['hat_ratio']:.2f}")


main()
