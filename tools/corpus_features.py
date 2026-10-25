"""
Extrae features geométricas de cada modelo del corpus (GLB) — sin renderizar.

    xvfb-run -a blender --background --python tools/corpus_features.py

Salida: corpus/features/<pack>__<modelo>.json  (un dict de números por modelo)

Qué mide y por qué:
  bbox_*        proporciones y punto más ancho
  mass_bands    dónde se concentra la masa (10 franjas verticales)
  components    en cuántos volúmenes se descompone (islas de malla)
  aabb_overlap  cuántos pares de volúmenes se solapan en AABB  → "encimado"
  symmetry      error medio al reflejar en X, normalizado por altura
  hull_ratio    perímetro²/área del casco convexo  → complejidad de silueta
  flat_ratio    fracción de aristas con diedro > 40°  → facetado vs suave
  hues, val_range, sat_mean  → paleta y contraste
"""

import json
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "corpus")
OUT = os.path.join(CORPUS, "features")


# --------------------------------------------------------------------------- #
def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def import_glb(path):
    import bmesh
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    # Kenney exporta sin soldar: sin esto, cada cara es una "isla" y toda
    # métrica de descomposición y de diedros sale sin sentido.
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
        bm.to_mesh(o.data)
        bm.free()
    return objs


def world_verts(objs):
    out = []
    for o in objs:
        mw = o.matrix_world
        out.extend(mw @ v.co for v in o.data.vertices)
    return out


def bbox(verts):
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    return lo, hi


def components(objs):
    """Islas de malla por unión de vértices conectados por aristas."""
    islands = []
    for o in objs:
        n = len(o.data.vertices)
        parent = list(range(n))

        def find(a):
            while parent[a] != a:
                parent[a] = parent[parent[a]]
                a = parent[a]
            return a

        def union(a, b):
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[rb] = ra

        for e in o.data.edges:
            union(e.vertices[0], e.vertices[1])

        groups = {}
        mw = o.matrix_world
        for i in range(n):
            groups.setdefault(find(i), []).append(mw @ o.data.vertices[i].co)
        islands.extend(groups.values())
    return islands


def aabb_overlaps(islands):
    boxes = [bbox(v) for v in islands if v]
    n = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a0, a1 = boxes[i]
            b0, b1 = boxes[j]
            if all(a0[k] <= b1[k] and b0[k] <= a1[k] for k in range(3)):
                n += 1
    return n


def symmetry(verts, height):
    from mathutils import kdtree
    if len(verts) < 4 or height <= 0:
        return 0.0
    kd = kdtree.KDTree(len(verts))
    for i, v in enumerate(verts):
        kd.insert(v, i)
    kd.balance()
    total = 0.0
    step = max(1, len(verts) // 400)
    for v in verts[::step]:
        mirrored = Vector((-v.x, v.y, v.z))
        _, _, d = kd.find(mirrored)
        total += d
    return total / len(range(0, len(verts), step)) / height


def hull_metrics(verts):
    """Casco convexo en la proyección frontal (x,z): perímetro²/área."""
    pts = sorted({(round(v.x, 4), round(v.z, 4)) for v in verts})
    if len(pts) < 3:
        return 0.0

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    hull = lower[:-1] + upper[:-1]
    if len(hull) < 3:
        return 0.0

    per = sum(math.dist(hull[i], hull[(i + 1) % len(hull)]) for i in range(len(hull)))
    area = 0.0
    for i in range(len(hull)):
        x1, y1 = hull[i]
        x2, y2 = hull[(i + 1) % len(hull)]
        area += x1 * y2 - x2 * y1
    area = abs(area) * 0.5
    return (per * per / area) if area > 1e-9 else 0.0


def flat_ratio(objs):
    import bmesh
    hard = total = 0
    for o in objs:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        for e in bm.edges:
            if len(e.link_faces) == 2:
                a = e.link_faces[0].normal
                b = e.link_faces[1].normal
                ang = a.angle(b, 0.0)
                total += 1
                if ang > math.radians(40):
                    hard += 1
        bm.free()
    return (hard / total) if total else 0.0


def palette(objs):
    """Colores reales: si hay textura, se muestrea la imagen; si no, el material."""
    colors = set()
    sampled = False
    for o in objs:
        for slot in o.material_slots:
            m = slot.material
            if not m or not m.use_nodes:
                continue
            bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if not bsdf:
                continue
            tex = None
            for link in m.node_tree.links:
                if link.to_node == bsdf and link.to_socket.name == "Base Color":
                    if link.from_node.type == "TEX_IMAGE" and link.from_node.image:
                        tex = link.from_node.image
            if tex is not None and tex.pixels and len(tex.pixels) > 16:
                px = tex.pixels[:]
                step = max(4, (len(px) // 4 // 800) * 4)
                for i in range(0, len(px) - 4, step):
                    r, g, b, a = px[i], px[i + 1], px[i + 2], px[i + 3]
                    if a < 0.5:
                        continue
                    colors.add((round(r, 1), round(g, 1), round(b, 1)))
                sampled = True
            else:
                c = bsdf.inputs["Base Color"].default_value
                colors.add((round(c[0], 2), round(c[1], 2), round(c[2], 2)))

    def lum(c):
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

    if not colors:
        return 0, 0.0, 0.0
    lums = [lum(c) for c in colors]
    sats = [max(c) - min(c) for c in colors]
    # "hues" = colores dominantes tras cuantizar (no cada píxel del atlas)
    quant = {(round(c[0] * 5) / 5, round(c[1] * 5) / 5, round(c[2] * 5) / 5) for c in colors}
    return len(quant), (max(lums) - min(lums)), sum(sats) / len(sats)


# --------------------------------------------------------------------------- #
def main():
    os.makedirs(OUT, exist_ok=True)
    glbs = []
    for pack in sorted(os.listdir(CORPUS)):
        d = os.path.join(CORPUS, pack)
        if not os.path.isdir(d):
            continue
        for sub in ("Models/GLB format", "Models/GLTF format", "Models"):
            p = os.path.join(d, sub)
            if os.path.isdir(p):
                glbs += [(pack, os.path.join(p, f)) for f in sorted(os.listdir(p)) if f.endswith(".glb")]
                break

    print(f"modelos: {len(glbs)}")
    done = 0
    for pack, path in glbs:
        name = os.path.splitext(os.path.basename(path))[0]
        try:
            clear()
            objs = import_glb(path)
            if not objs:
                continue
            verts = world_verts(objs)
            if not verts:
                continue
            lo, hi = bbox(verts)
            size = hi - lo
            height = size.z
            islands = components(objs)
            hues, val_range, sat_mean = palette(objs)

            bands = [0] * 10
            for v in verts:
                idx = int((v.z - lo.z) / height * 10) if height > 0 else 0
                bands[max(0, min(9, idx))] += 1
            tot = max(1, len(verts))
            bands = [round(b / tot, 3) for b in bands]

            feat = {
                "pack": pack,
                "model": name,
                "verts": len(verts),
                "tris": sum((o.data.calc_loop_triangles() or len(o.data.loop_triangles)) for o in objs),
                "bbox": [round(size.x, 3), round(size.y, 3), round(size.z, 3)],
                "aspect_wh": round(size.x / height, 3) if height else 0,
                "aspect_wd": round(size.x / size.y, 3) if size.y else 0,
                "mass_bands": bands,
                "components": len(islands),
                "aabb_overlap": aabb_overlaps(islands),
                "symmetry": round(symmetry(verts, height), 4),
                "hull_ratio": round(hull_metrics(verts), 1),
                "flat_ratio": round(flat_ratio(objs), 3),
                "hues": hues,
                "val_range": round(val_range, 3),
                "sat_mean": round(sat_mean, 3),
            }
            with open(os.path.join(OUT, f"{pack}__{name}.json"), "w") as fh:
                json.dump(feat, fh, indent=1)
            done += 1
            if done % 10 == 0:
                print(f"  {done}/{len(glbs)}")
        except Exception as exc:  # noqa: BLE001
            print(f"  FALLO {pack}/{name}: {exc}")

    print(f"OK features={done} en {OUT}")


if __name__ == "__main__":
    main()
