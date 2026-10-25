"""
Caracterización del modelo: mide el GLB con las MISMAS features del corpus y
devuelve su posición (percentil) en cada capa.

    xvfb-run -a blender --background --python tools/characterize.py -- \
        --model assets/chef.glb

No juzga: ubica. Un percentil 5 en "espacio negativo" no es un error, es una
decisión; lo que hace es decir en qué se aparta del corpus y cuánto.
"""

import importlib.util
import json
import glob
import os
import sys

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


F = load_module("corpus_features", os.path.join(ROOT, "tools", "corpus_features.py"))

LAYERS = [
    ("volúmenes", "components", "cap2"),
    ("solapes", "aabb_overlap", "cap2"),
    ("simetría", "symmetry", "cap6"),
    ("silueta", "hull_ratio", "cap3"),
    ("caras duras", "flat_ratio", "cap1"),
    ("ancho/alto", "aspect_wh", "cap1"),
]


def features_of(path):
    F.clear()
    objs = F.import_glb(path)
    verts = F.world_verts(objs)
    lo, hi = F.bbox(verts)
    size = hi - lo
    islands = F.components(objs)
    hues, val_range, sat = F.palette(objs)
    bands = [0] * 10
    for v in verts:
        idx = int((v.z - lo.z) / size.z * 10) if size.z > 0 else 0
        bands[max(0, min(9, idx))] += 1
    tot = max(1, len(verts))
    return {
        "components": len(islands),
        "aabb_overlap": F.aabb_overlaps(islands),
        "symmetry": F.symmetry(verts, size.z),
        "hull_ratio": F.hull_metrics(verts),
        "flat_ratio": F.flat_ratio(objs),
        "aspect_wh": size.x / size.z if size.z else 0,
        "tris": sum((o.data.calc_loop_triangles() or len(o.data.loop_triangles)) for o in objs),
        "mass_bands": [round(b / tot, 3) for b in bands],
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    path = "assets/chef.glb"
    if "--model" in argv:
        path = argv[argv.index("--model") + 1]
    if not os.path.isabs(path):
        path = os.path.join(ROOT, path)

    mine = features_of(path)

    corpus = []
    for f in glob.glob(os.path.join(ROOT, "corpus", "features", "*.json")):
        corpus.append(json.load(open(f)))

    print(f"\nmodelo: {os.path.basename(path)}  ·  tris {mine['tris']}  ·  "
          f"corpus {len(corpus)} modelos\n")
    print(f"{'capa':14s} {'valor':>8s} {'corpus p10':>11s} {'p50':>7s} {'p90':>7s} {'percentil':>10s}")
    for label, key, layer in LAYERS:
        vals = np.array([c[key] for c in corpus], float)
        mine_v = float(mine[key])
        pct = float((vals < mine_v).mean() * 100)
        print(f"{label:14s} {mine_v:8.3f} {np.percentile(vals,10):11.3f} "
              f"{np.percentile(vals,50):7.3f} {np.percentile(vals,90):7.3f} {pct:9.0f}%  {layer}")

    bands = np.array([c["mass_bands"] for c in corpus], float)
    print("\nmasa por franja (0 = pies … 9 = cabeza)")
    print("  mío    " + " ".join(f"{b:.2f}" for b in mine["mass_bands"]))
    print("  corpus " + " ".join(f"{b:.2f}" for b in bands.mean(axis=0)))
    print("  delta  " + " ".join(f"{m - c:+.2f}" for m, c in zip(mine["mass_bands"], bands.mean(axis=0))))


if __name__ == "__main__":
    main()
