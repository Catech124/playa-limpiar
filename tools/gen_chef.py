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
        "color": "#F2EDE2",    # crema: ΔE ≈ 27 contra la arena (la paja daba 8)
        "tilt_deg": 0.0,
        "brim_front_short": 0.55,
        "hat_drop": 0.07,
    },
    "palette": {
        "skin": "#E8B48A",
        "shirt": "#F2B544",
        "shorts": "#2F3B52",
        "boots": "#232A33",
        "gloves": "#EDEFEC",
        "eyes": "#15181D",
        "mouth": "#A85A4E",
        "band": "#D94F3D",
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
    pal = P["palette"]
    skin = material("skin", pal["skin"], 0.72)
    shirt = material("shirt", pal["shirt"], 0.85)
    shorts = material("shorts", pal["shorts"], 0.85)
    boots = material("boots", pal["boots"], 0.68)
    gloves = material("gloves", pal["gloves"], 0.90)
    eyes = material("eyes", pal["eyes"], 0.55)
    mouth = material("mouth", pal["mouth"], 0.80)

    parts = {}

    legs = Part("legs", "legs")
    feet = Part("boots", "boots")
    for side in (-1, 1):
        cylinder(legs, 0.064, 0.21, (side * 0.095, 0, 0.205), skin, vertices=8)
        box(feet, (0.21, 0.32, 0.17), (side * 0.095, -0.035, 0.082), boots, bevel=0.038)

    hip = Part("shorts", "shorts")
    cylinder(hip, 0.158, 0.17, (0, 0, 0.30), shorts, vertices=12)
    sphere(hip, 0.156, (0, 0, 0.265), shorts, scale=(1, 0.95, 0.7), segments=12, rings=6)

    torso = Part("torso", "torso")
    body = cylinder(torso, 0.176, 0.255, (0, 0, 0.510), shirt, vertices=12, top=0.222)
    body.scale = (1.05, 0.90, 1.0)
    sphere(torso, 0.222, (0, 0, 0.625), shirt, scale=(1.05, 0.90, 0.58), segments=12, rings=6)
    sphere(torso, 0.158, (0, 0, 0.410), shirt, scale=(1.04, 0.94, 0.55), segments=12, rings=6)

    arms = Part("arms", "arms")
    hands = Part("hands", "hands")
    # pose asimétrica: la derecha va a la cadera, la izquierda cuelga.
    # El corpus es 100% simétrico; la asimetría deliberada es lo que lo hace
    # recordable (y es la única licencia que se toma contra la norma).
    POSE = {
        -1: {"shoulder": (-0.205, 0.0, 0.600), "elbow": (-0.300, -0.010, 0.450),
             "wrist": (-0.330, -0.030, 0.310)},
        1: {"shoulder": (0.205, 0.0, 0.600), "elbow": (0.310, -0.020, 0.460),
            "wrist": (0.170, -0.150, 0.400)},
    }
    for side in (-1, 1):
        pose = POSE[side]
        limb(arms, pose["shoulder"], pose["elbow"], 0.056, skin, vertices=8, taper=0.92)
        limb(arms, pose["elbow"], pose["wrist"], 0.048, skin, vertices=8, taper=0.95)
        sphere(hands, 0.070, pose["wrist"], gloves, segments=9, rings=6)

    head = Part("head", "head")
    hz = P["body"]["head_z"]
    hr = P["body"]["head_r"]
    sphere(head, hr, (0, 0, hz), skin, scale=(1.02, 0.96, 0.99), segments=18, rings=11)
    sphere(head, 0.038, (0, -0.245, hz - 0.04), skin, scale=(1, 1.2, 0.9), segments=10, rings=6)

    face = Part("face", "face")
    for side in (-1, 1):
        sphere(face, 0.046, (side * 0.090, -0.238, hz + 0.010), eyes, segments=9, rings=6)
        box(face, (0.062, 0.014, 0.013), (side * 0.090, -0.246, hz + 0.085),
            eyes, rotation=(0, 0, side * math.radians(-12)), bevel=0.005, smooth=True)
    box(face, (0.105, 0.020, 0.024), (0, -0.245, hz - 0.098), mouth, bevel=0.010, smooth=True)

    parts.update({"legs": legs, "boots": feet, "shorts": hip, "torso": torso,
                  "arms": arms, "hands": hands, "head": head, "face": face})
    return parts


# --------------------------------------------------------------------------- #
# gorro (paramétrico: es lo único que se barre)
# --------------------------------------------------------------------------- #
def build_hat(P):
    h = P["hat"]
    pal = P["palette"]
    # el sombrero se hunde en el cráneo: apoyado en la coronilla "flota",
    # porque a su radio el cráneo ya está más abajo
    hr0 = P["body"]["head_r"]
    support0 = hr0 * 0.76
    # z de la superficie del cráneo en el radio de apoyo
    surface_z = P["body"]["head_z"] + (hr0 * 0.99) * math.sqrt(max(0.0, 1.0 - (support0 / (hr0 * 1.02)) ** 2))
    head_top = surface_z - float(h.get("hat_drop", 0.02))
    head_r = P["body"]["head_r"]

    hat_mat = material("hat", h["color"], 0.78)
    band_mat = material("band", pal["band"], 0.85)
    part = Part("hat", "hat")

    tipo = h["tipo"]
    copa = float(h["copa_h"])
    ala = float(h["ala"])
    support_r = head_r * 0.76            # radio de apoyo sobre la coronilla

    # banda: común a todos, es lo que da identidad de color
    band_h = 0.05 if h.get("banda", "fina") == "fina" else 0.075
    cylinder(part, support_r + 0.012, band_h, (0, 0, head_top + band_h * 0.5 - 0.012),
             band_mat, vertices=14)
    base_z = head_top + band_h - 0.012

    if tipo == "toque":
        # copa de chef: lóbulos inflados alrededor de un centro
        n = max(3, int(h.get("lobulos", 4)))
        lobe_r = 0.085 + copa * 0.30
        ring_r = support_r * 0.52
        for i in range(n):
            a = (i / n) * math.tau + math.pi / n
            sphere(part, lobe_r,
                   (math.cos(a) * ring_r, math.sin(a) * ring_r, base_z + copa + lobe_r * 0.55),
                   hat_mat, scale=(1.0, 1.0, 0.92), segments=16, rings=10)
        sphere(part, lobe_r * 0.92, (0, 0, base_z + copa + lobe_r * 1.25),
               hat_mat, scale=(1.0, 1.0, 0.85), segments=16, rings=10)

    elif tipo == "paja":
        # copa semiesférica + ala CURVA: el frente sube y deja ver la cara
        sphere(part, support_r * 1.05, (0, 0, base_z), hat_mat,
               scale=(1.0, 1.0, max(0.35, copa / (support_r * 1.05))), segments=14, rings=8)
        brim_r = support_r + 0.06 + ala
        # Ala cónica: nace de la copa y baja hacia el borde. Un disco plano
        # apoyado en la coronilla deja un hueco visible (la cabeza es elipsoidal
        # y a ese radio la superficie está más abajo): el cono queda adjunto.
        brim = cylinder(part, brim_r, 0.055, (0, 0, base_z - 0.026), hat_mat,
                        vertices=20, top=support_r * 0.98)
        short = float(h.get("brim_front_short", 0.55))
        for v in brim.data.vertices:
            if v.co.z > 0:          # el borde exterior es el anillo inferior
                continue
            x, y, z = v.co
            rr = math.hypot(x, y)
            if rr < 1e-5:
                continue
            front = max(0.0, -y / rr)
            k = 1.0 - short * front
            v.co.x *= k
            v.co.y *= k

    else:  # gorra con visera
        sphere(part, support_r * 1.02, (0, 0, base_z), hat_mat,
               scale=(1.0, 1.0, max(0.40, copa / (support_r * 1.02))), segments=20, rings=12)
        visor_len = 0.10 + ala
        box(part, (0.30, visor_len, 0.022), (0, -support_r * 0.85 - visor_len * 0.30, base_z - 0.02),
            hat_mat, rotation=(math.radians(-6), 0, 0), bevel=0.02, smooth=True)

    tilt = float(h.get("tilt_deg", 0.0))
    if tilt:
        pivot = bpy.data.objects.new("hat_pivot", None)
        pivot.location = (0, 0, head_top)
        bpy.context.scene.collection.objects.link(pivot)
        bpy.context.view_layer.update()
        # guardar la matriz mundial, emparentar y RESTAURARLA: si no, el
        # `matrix_parent_inverse` se calcula con el pivote aún en el origen
        world = {o: o.matrix_world.copy() for o in part.objs}
        for o in part.objs:
            o.parent = pivot
        for o in part.objs:
            o.matrix_world = world[o]
        pivot.rotation_euler = (math.radians(tilt), 0, math.radians(tilt * 0.6))

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
