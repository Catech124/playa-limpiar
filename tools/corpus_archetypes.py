"""
Arquetipos v2: clustering SOLO con forma (sin paleta, sin artefactos de pack).

    python3 tools/corpus_archetypes.py [--k 4] [--auto]

Cambios respecto de v1, que separaba packs y no formas:
  - fuera `aspect_wd` (era binario: 0.95 vs 2.00, un artefacto del exportador)
  - fuera la paleta hasta arreglar su medición (da 0 en modelos sin textura)
  - entra el perfil de masa (10 franjas, ya normalizado por vértices)
  - se elige k por silhouette score en vez de a ojo
  - se mide PUREZA POR PACK: si un cluster es 100% de un pack, no es un
    arquetipo de forma, es un artefacto de procedencia
"""

import glob
import json
import math
import os
import re
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEAT = os.path.join(ROOT, "corpus", "features")
CHAR_PAT = re.compile(r"(character|human|skater|player|npc|hero|orc|archer|dwarf)", re.I)

# solo forma
SHAPE = ["aspect_wh", "components", "aabb_overlap", "symmetry", "hull_ratio", "flat_ratio"]
LOG = {"components", "aabb_overlap"}


def load():
    rows = []
    for f in glob.glob(os.path.join(FEAT, "*.json")):
        d = json.load(open(f))
        if len(d.get("mass_bands", [])) == 10 and CHAR_PAT.search(d["model"]):
            rows.append(d)
    return rows


def matrix(rows, with_bands=True):
    cols = []
    names = []
    for f in SHAPE:
        col = np.array([r[f] for r in rows], float)
        if f in LOG:
            col = np.log1p(col)
        cols.append(col)
        names.append(f)
    if with_bands:
        bands = np.array([r["mass_bands"] for r in rows], float)
        for i in range(10):
            cols.append(bands[:, i])
            names.append(f"band{i}")
    X = np.column_stack(cols)
    sd = X.std(axis=0)
    sd[sd == 0] = 1
    return (X - X.mean(axis=0)) / sd, names


def kmeans(X, k, iters=80, seed=7):
    rng = np.random.default_rng(seed)
    C = [X[rng.integers(len(X))]]
    for _ in range(k - 1):
        d = np.min([np.linalg.norm(X - c, axis=1) ** 2 for c in C], axis=0)
        p = d / d.sum() if d.sum() > 0 else np.full(len(X), 1 / len(X))
        C.append(X[rng.choice(len(X), p=p)])
    C = np.array(C)
    for _ in range(iters):
        lab = np.linalg.norm(X[:, None] - C[None], axis=2).argmin(1)
        newC = np.array([X[lab == j].mean(0) if (lab == j).any() else C[j] for j in range(k)])
        if np.allclose(newC, C):
            break
        C = newC
    return lab, C


def silhouette(X, lab):
    if len(set(lab)) < 2:
        return -1.0
    n = len(X)
    D = np.linalg.norm(X[:, None] - X[None], axis=2)
    scores = []
    for i in range(n):
        same = (lab == lab[i])
        same[i] = False
        a = D[i, same].mean() if same.any() else 0.0
        b = min(D[i, lab == j].mean() for j in set(lab) if j != lab[i] and (lab == j).any())
        scores.append((b - a) / max(a, b) if max(a, b) > 0 else 0.0)
    return float(np.mean(scores))


def purity(cluster_rows):
    if not cluster_rows:
        return 0.0
    packs = {}
    for r in cluster_rows:
        packs[r["pack"]] = packs.get(r["pack"], 0) + 1
    return max(packs.values()) / len(cluster_rows)


def main():
    k_req = None
    if "--k" in sys.argv:
        k_req = int(sys.argv[sys.argv.index("--k") + 1])
    auto = "--auto" in sys.argv

    rows = load()
    X, names = matrix(rows)
    print(f"personajes: {len(rows)}  ·  features de forma: {len(names)}")

    if auto or k_req is None:
        best = None
        for k in range(2, min(7, len(rows) - 1)):
            lab, C = kmeans(X, k)
            s = silhouette(X, lab)
            print(f"  k={k}  silhouette={s:.3f}")
            if best is None or s > best[1]:
                best = (k, s, lab, C)
        k, _, lab, C = best
    else:
        k = k_req
        lab, C = kmeans(X, k)

    print(f"\n=== k={k} ===")
    order = np.argsort([-np.sum(lab == j) for j in range(k)])
    for j in order:
        idx = np.where(lab == j)[0]
        if len(idx) == 0:
            continue
        crows = [rows[i] for i in idx]
        real = C[j]  # ya está en z-space; se describe con medianas reales
        med = {f: float(np.median([r[f] for r in crows])) for f in SHAPE}
        bands = np.median([r["mass_bands"] for r in crows], axis=0)
        print(f"\n  CLUSTER {j + 1}  n={len(idx)}  pureza_de_pack={purity(crows):.0%}")
        print("    " + ", ".join(r["model"] for r in crows[:8]) + ("…" if len(crows) > 8 else ""))
        print(f"    ancho/alto {med['aspect_wh']:.2f} · volúmenes {med['components']:.0f} · "
              f"solapes {med['aabb_overlap']:.0f} · silueta {med['hull_ratio']:.1f} · "
              f"caras duras {med['flat_ratio']:.2f} · simetría {med['symmetry']:.3f}")
        print("    masa  " + " ".join(f"{b:.2f}" for b in bands))

    print("\n=== diagnóstico ===")
    pur = [purity([rows[i] for i in np.where(lab == j)[0]]) for j in range(k)]
    print(f"  pureza media de pack: {np.mean(pur):.0%}  "
          f"(>80% = el clustering está separando procedencia, no forma)")


if __name__ == "__main__":
    main()
