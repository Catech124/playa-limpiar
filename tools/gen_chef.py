"""
Generador paramétrico del personaje (Blender headless).

Cuerpo congelado en el preset `v1_frozen`; el gorro es una función pura de
`params["hat"]` y del anclaje de la cabeza (posición + radio), para poder
barrerlo sin tocar el cuerpo.

Uso:
    # una variante -> GLB + renders
    blender --background --python tools/gen_chef.py -- --out /tmp/chef --export

    # barrido (todo en un solo proceso)
    blender --background --python tools/gen_chef.py -- --sweep tools/sweeps/gorros.json --out /tmp/sweep

Salidas por variante: <id>.front.png, <id>.game.png, <id>.mask.png,
<id>.game_mask.png y <id>.json (parámetros).
"""

import argparse
import json
import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --------------------------------------------------------------------------- #
# parámetros por defecto (el cuerpo NO se barre: está congelado)
# --------------------------------------------------------------------------- #
DEFAULTS = {
    "id": "chef",
    "body": {
        "preset": "v1_frozen",
        "head_z": 0.825,
        "head_r": 0.255,
        "head_top": 1.08,
        "lean_deg": 0.0,
    },
    "hat": {
        "tipo": "paja",       # toque | paja | gorra
        "copa_h": 0.12,        # altura de la copa sobre la banda
        "lobulos": 4,
        "ala": 0.06,           # ala corta: con 0.18 el ala tapa la cara a 68°
        "banda": "fina",
        "color": "#D8B979",    # crema: ΔE ≈ 27 contra la arena (la paja daba 8)
        "tilt_deg": 0.0,
        "brim_front_short": 0.55,
        "hat_drop": 0.07,
    },
    "palette": {
        "skin": "#E8A87C",
        "shirt": "#F2B544",
        "pants": "#2F4A9E",
        "shoes": "#EDEDED",
        "sole": "#C3C3C3",
        "boots": "#EDEDED",
        "gloves": "#EDEFEC",
        "eyes": "#15181D",
        "mouth": "#A85A4E",
        "band": "#8B5A2B",
    },
}

# colores de ID para las máscaras (una parte = un color plano)
ID_COLORS = {
    "hat": (1.0, 0.0, 0.0),
    "head": (0.0, 1.0, 0.0),
    "face": (0.0, 0.0, 1.0),
    "torso": (1.0, 1.0, 0.0),
    "arms": (1.0, 0.0, 1.0),
    "hands": (0.0, 1.0, 1.0),
    "legs": (1.0, 0.5, 0.0),
    "boots": (0.5, 0.0, 1.0),
    "shorts": (1.0, 1.0, 1.0),
}


# --------------------------------------------------------------------------- #
# utilidades
# --------------------------------------------------------------------------- #
def srgb(hex_str):
    """Los materiales son lineales; el hex es sRGB."""
    h = hex_str.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def deep_merge(base, patch):
    out = dict(base)
    for k, v in patch.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


_mats = {}


def material(role, hex_color, rough=0.8):
    key = f"{role}:{hex_color}:{rough}"
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(role)
    m.use_nodes = True
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if out:
            m.node_tree.links.new(bsdf.outputs[0], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = srgb(hex_color)
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = srgb(hex_color)
    _mats[key] = m
    return m


# --------------------------------------------------------------------------- #
# primitivas
# --------------------------------------------------------------------------- #
class Part:
    __slots__ = ("name", "group", "objs")

    def __init__(self, name, group):
        self.name = name
        self.group = group
        self.objs = []

    def add(self, obj):
        self.objs.append(obj)
        return obj


def sphere(part, radius, loc, mat, scale=(1, 1, 1), segments=18, rings=10, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=loc)
    o = bpy.context.object
    o.scale = scale
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = smooth
    return part.add(o)


def cylinder(part, r, depth, loc, mat, rotation=(0, 0, 0), vertices=14, smooth=True, top=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=r, depth=depth, location=loc, rotation=rotation)
    o = bpy.context.object
    if top is not None:
        for v in o.data.vertices:
            if v.co.z > 0:
                v.co.x *= top / r
                v.co.y *= top / r
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = smooth
    return part.add(o)


def limb(part, p0, p1, radius, mat, vertices=10, taper=1.0):
    """Cilindro orientado entre dos puntos: sirve para brazos con codo."""
    from mathutils import Vector
    a, b = Vector(p0), Vector(p1)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                        depth=d.length, location=(a + b) * 0.5)
    o = bpy.context.object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.to_track_quat("Z", "Y")
    if taper != 1.0:
        for v in o.data.vertices:
            if v.co.z > 0:
                v.co.x *= taper
                v.co.y *= taper
    o.data.materials.append(mat)
    for poly in o.data.polygons:
        poly.use_smooth = True
    return part.add(o)


def box(part, size, loc, mat, rotation=(0, 0, 0), bevel=0.012, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rotation)
    o = bpy.context.object
    o.scale = size
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = smooth
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        with bpy.context.temp_override(object=o):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    return part.add(o)


# --------------------------------------------------------------------------- #
# cuerpo (CONGELADO: mismos números que v1)
# --------------------------------------------------------------------------- #
def build_body(P):
    """Cuerpo según la referencia: cabeza grande y ANCHA, orejas, nariz en cuña,
    ojos chicos, brazos en A, pantalón recto y zapatillas blancas."""
    pal = P["palette"]
    skin = material("skin", pal["skin"], 0.72)
    shirt = material("shirt", pal["shirt"], 0.85)
    pants = material("pants", pal["pants"], 0.85)
    shoes = material("shoes", pal["shoes"], 0.75)
    sole = material("sole", pal["sole"], 0.80)
    gloves = material("gloves", pal["gloves"], 0.90)
    eyes = material("eyes", pal["eyes"], 0.55)
    mouth = material("mouth", pal["mouth"], 0.80)

    parts = {}

    # --- piernas rectas + zapatillas --------------------------------------
    legs = Part("legs", "legs")
    feet = Part("boots", "boots")
    for side in (-1, 1):
        cylinder(legs, 0.072, 0.26, (side * 0.098, 0, 0.24), pants, vertices=8)
        box(feet, (0.17, 0.30, 0.10), (side * 0.098, -0.035, 0.055), shoes, bevel=0.02)
        box(feet, (0.175, 0.30, 0.035), (side * 0.098, -0.035, 0.017), sole, bevel=0.012)

    # --- torso: remera corta, más ancha arriba ----------------------------
    torso = Part("torso", "torso")
    body = cylinder(torso, 0.185, 0.30, (0, 0, 0.475), shirt, vertices=10, top=0.205)
    body.scale = (1.06, 0.88, 1.0)
    sphere(torso, 0.205, (0, 0, 0.625), shirt, scale=(1.06, 0.88, 0.55), segments=12, rings=6)

    # --- brazos en A con manga corta y guante segmentado -------------------
    arms = Part("arms", "arms")
    hands = Part("hands", "hands")
    for side in (-1, 1):
        shoulder = (side * 0.195, 0.0, 0.585)
        elbow = (side * 0.315, -0.005, 0.455)
        wrist = (side * 0.360, -0.010, 0.330)
        limb(arms, shoulder, elbow, 0.072, shirt, vertices=8)      # manga
        limb(arms, elbow, wrist, 0.052, skin, vertices=8)            # antebrazo
        # guante: tres bloques, como la referencia
        sphere(hands, 0.080, wrist, gloves, scale=(1.0, 1.05, 1.0), segments=9, rings=6)
        sphere(hands, 0.058, (side * 0.375, -0.055, 0.292), gloves, segments=8, rings=5)
        sphere(hands, 0.052, (side * 0.352, 0.045, 0.300), gloves, segments=8, rings=5)

    # --- cabeza ancha, sin cuello, con orejas -----------------------------
    head = Part("head", "head")
    hz = P["body"]["head_z"]
    hr = P["body"]["head_r"]
    sphere(head, hr, (0, 0, hz), skin, scale=(1.16, 0.96, 0.94), segments=16, rings=10)
    for side in (-1, 1):
        sphere(head, 0.082, (side * hr * 1.12, 0.0, hz - 0.01), skin,
               scale=(0.45, 1.0, 1.15), segments=8, rings=6)
        sphere(head, 0.045, (side * hr * 1.16, 0.0, hz - 0.01), skin, segments=6, rings=4)

    # --- cara: ojos chicos, cejas finas, nariz en cuña, sonrisa -----------
    face = Part("face", "face")
    for side in (-1, 1):
        sphere(face, 0.030, (side * 0.098, -0.268, hz + 0.055), eyes, segments=8, rings=6)
        box(face, (0.058, 0.012, 0.010), (side * 0.100, -0.272, hz + 0.118),
            eyes, rotation=(0, 0, side * math.radians(-8)), bevel=0.004)
    # nariz: cono corto apuntando al frente (-Y)
    nose = cylinder(face, 0.050, 0.085, (0, -0.285, hz - 0.020), skin,
                    vertices=6, smooth=False, top=0.030)
    nose.rotation_euler = (math.radians(90), 0, 0)
    # sonrisa: tres segmentos formando una curva suave
    for i, (dx, dz, ang) in enumerate([(-0.040, 0.004, 12), (0.0, -0.006, 0), (0.040, 0.004, -12)]):
        box(face, (0.048, 0.014, 0.016), (dx, -0.272, hz - 0.118 + dz),
            mouth, rotation=(0, 0, math.radians(ang)), bevel=0.005, smooth=False)

    parts.update({"legs": legs, "boots": feet, "torso": torso,
                  "arms": arms, "hands": hands, "head": head, "face": face})
    return parts


# --------------------------------------------------------------------------- #
# gorro (paramétrico: es lo único que se barre)
# --------------------------------------------------------------------------- #
def build_hat(P):
    """Fedora de paja como la referencia: copa troncocónica, cinta marrón y ala
    que nace de la copa (un disco apoyado en la coronilla deja hueco)."""
    h = P["hat"]
    pal = P["palette"]
    head_r = P["body"]["head_r"]
    support = head_r * 0.80
    # altura de apoyo: superficie del cráneo en el radio interior del ala
    surface_z = P["body"]["head_z"] + (head_r * 0.94) * math.sqrt(
        max(0.0, 1.0 - (support / (head_r * 1.16)) ** 2))
    base_z = surface_z - float(h.get("hat_drop", 0.01))

    hat_mat = material("hat", h["color"], 0.80)
    band_mat = material("band", pal["band"], 0.85)
    part = Part("hat", "hat")

    ala = float(h["ala"])
    copa = float(h["copa_h"])

    # copa troncocónica
    crown = cylinder(part, support + 0.035, 0.06 + copa, (0, 0, base_z + (0.06 + copa) * 0.5),
                     hat_mat, vertices=12, top=(support + 0.035) * 0.86)
    # cinta marrón
    cylinder(part, support + 0.045, 0.045, (0, 0, base_z + 0.075), band_mat, vertices=12)
    # ala cónica que nace de la copa
    brim = cylinder(part, support + 0.075 + ala, 0.045, (0, 0, base_z - 0.020),
                    hat_mat, vertices=16, top=support + 0.055)
    short = float(h.get("brim_front_short", 0.0))
    if short > 0:
        for v in brim.data.vertices:
            if v.co.z > 0:
                continue
            x, y, z = v.co
            rr = math.hypot(x, y)
            if rr < 1e-5:
                continue
            front = max(0.0, -y / rr)
            k = 1.0 - short * front
            v.co.x *= k
            v.co.y *= k

    return part


# --------------------------------------------------------------------------- #
# escena y render
# --------------------------------------------------------------------------- #
def setup_world():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.60, 0.68, 1)
    bg.inputs[1].default_value = 0.55
    scene.world = world
    scene.render.film_transparent = False


def setup_camera():
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    aim = bpy.data.objects.new("aim", None)
    bpy.context.scene.collection.objects.link(aim)
    aim.location = (0, 0, 0.62)
    con = cam.constraints.new("TRACK_TO")
    con.target = aim
    con.track_axis = "TRACK_NEGATIVE_Z"
    con.up_axis = "UP_Y"
    return cam


VIEWS = {
    # nombre: (posición cámara, fov vertical, resolución)
    "front": ((2.35, -3.05, 1.95), 26.0, (420, 540)),
    "game": ((0.0, -9.50, 24.00), 34.0, (1280, 800)),
}


def render(cam, view, path, mode):
    scene = bpy.context.scene
    pos, fov, (w, hgt) = VIEWS[view]
    cam.location = pos
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(fov)
    cam.data.lens = 50

    scene.render.resolution_x = w
    scene.render.resolution_y = hgt
    scene.render.resolution_percentage = 100
    scene.render.filepath = path

    if mode == "mask":
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "FLAT"
        scene.display.shading.color_type = "OBJECT"
        scene.display.shading.show_shadows = False
        scene.display.shading.show_cavity = False
        scene.display.render_aa = "OFF"   # sin AA: colores de ID puros
        scene.view_settings.view_transform = "Standard"
    else:
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.display.shading.light = "STUDIO"
        scene.display.shading.color_type = "MATERIAL"
        scene.display.shading.show_shadows = True
        scene.display.shading.show_cavity = True
        scene.display.shading.cavity_type = "WORLD"
        scene.display.render_aa = "8"
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"

    bpy.ops.render.render(write_still=True)


def set_object_ids(parts):
    for group, part in parts.items():
        col = ID_COLORS.get(group, (0, 0, 0))
        for o in part.objs:
            o.color = (col[0], col[1], col[2], 1.0)


# --------------------------------------------------------------------------- #
# una variante completa
# --------------------------------------------------------------------------- #
def build_only(P, with_hat=True):
    """Construye el personaje y devuelve las partes, sin renderizar."""
    clear_scene()
    _mats.clear()
    setup_world()
    parts = build_body(P)
    if with_hat:
        parts["hat"] = build_hat(P)
    set_object_ids(parts)

    # sombreado por ángulo: el corpus low-poly tiene ~45% de aristas duras y
    # nosotros estábamos en 9% (todo suave = se veía "plastilina")
    objs = [o for part in parts.values() for o in part.objs]
    if objs:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.shade_auto_smooth(angle=math.radians(38))

    return parts


def build_variant(P, out_dir, export=False, with_hat=True, tag=None):
    parts = build_only(P, with_hat=with_hat)   # limpia, construye y cuelga del árbol
    cam = setup_camera()                       # la cámara va DESPUÉS del clear

    vid = tag or P["id"]
    render(cam, "front", os.path.join(out_dir, f"{vid}.front.png"), "beauty")
    render(cam, "game", os.path.join(out_dir, f"{vid}.game.png"), "beauty")
    render(cam, "front", os.path.join(out_dir, f"{vid}.mask.png"), "mask")
    render(cam, "game", os.path.join(out_dir, f"{vid}.game_mask.png"), "mask")

    if export:
        bpy.ops.object.select_all(action="DESELECT")
        for part in parts.values():
            for o in part.objs:
                o.select_set(True)
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(out_dir, f"{vid}.glb"),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
        )

    tris = 0
    for part in parts.values():
        for o in part.objs:
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)

    with open(os.path.join(out_dir, f"{vid}.json"), "w") as fh:
        json.dump({"params": P, "tris": tris, "parts": {k: len(v.objs) for k, v in parts.items()}}, fh, indent=2)
    return tris


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/chef")
    ap.add_argument("--params", default="")
    ap.add_argument("--sweep", default="")
    ap.add_argument("--export", action="store_true")
    args = ap.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)

    if args.sweep:
        with open(args.sweep) as fh:
            sweep = json.load(fh)
        base = deep_merge(DEFAULTS, sweep.get("base", {}))
        count = 0
        for i, patch in enumerate(sweep["variants"]):
            p = deep_merge(base, patch)
            p["id"] = patch.get("id", f"v{i + 1:02d}")
            tris = build_variant(p, args.out, export=args.export, tag=p["id"])
            print(f"VARIANTE {p['id']} tris={tris}")
            count += 1
        # baseline sin gorro: referencia para la métrica de cara visible
        build_variant(base, args.out, export=False, with_hat=False, tag="baseline_nohat")
        print(f"OK sweep={count} out={args.out}")
        return

    p = DEFAULTS
    if args.params:
        with open(args.params) as fh:
            p = deep_merge(DEFAULTS, json.load(fh))
    tris = build_variant(p, args.out, export=args.export)
    print(f"OK tris={tris} out={args.out}")


if __name__ == "__main__":
    main()
