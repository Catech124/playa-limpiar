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
        "pose": "t",          # t = hoja de referencia · down = pose de juego
        "head_z": 0.882,
        "head_r": 0.290,
        "head_top": 1.320,
        "lean_deg": 0.0,
    },
    "hat": {
        "tipo": "paja",       # toque | paja | gorra
        "copa_h": 0.115,        # altura de la copa sobre la banda
        "lobulos": 4,
        "ala": 0.192,           # ala corta: con 0.18 el ala tapa la cara a 68°
        "banda": "fina",
        "color": "#DDBE86",    # paja: ΔE ≈ 27 contra la arena (la paja daba 8)
        "tilt_deg": 0.0,
        "brim_front_short": 0.0,
        "hat_drop": 0.070,
    },
    "palette": {
        "skin": "#E39F7C",
        "shirt": "#F2D14F",
        "pants": "#3B4166",
        "white": "#F2F2EE",
        "shoes": "#F2F2EE",
        "sole": "#F2F2EE",
        "boots": "#F2F2EE",
        "gloves": "#EDEFEC",
        "eyes": "#15181D",
        "mouth": "#A85A4E",
        "band": "#B98683",
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


def lathe(part, profile, loc, mat, segments=28, smooth=True):
    """Superficie de revolución alrededor de Z desde un perfil [(r, z), ...].

    Es lo que convierte un gorro de "cono + bola" en un fedora: la copa, la
    cinta y el ala salen de UN solo perfil continuo, como en la lámina.
    """
    import bmesh
    bm = bmesh.new()
    rings = []
    for (r, z) in profile:
        ring = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    bm.verts.ensure_lookup_table()
    for j in range(len(rings) - 1):
        r0, r1 = profile[j][0], profile[j + 1][0]
        for i in range(segments):
            a = rings[j][i]
            b = rings[j][(i + 1) % segments]
            c = rings[j + 1][(i + 1) % segments]
            d = rings[j + 1][i]
            if r0 < 1e-6 and r1 < 1e-6:
                continue
            if r0 < 1e-6:
                face = (a, b, c)
            elif r1 < 1e-6:
                face = (a, b, d)
            else:
                face = (a, b, c, d)
            try:
                bm.faces.new(face)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    me = bpy.data.meshes.new("lathe")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("lathe", me)
    bpy.context.scene.collection.objects.link(o)
    o.location = loc
    o.data.materials.append(mat)
    for poly in o.data.polygons:
        poly.use_smooth = smooth
    return part.add(o)


def arc(part, radius, thickness, loc, mat, rotation=(0, 0, 0), segments=20):
    """Media luna: un toro al que se le borra la mitad de arriba. Sirve para la
    sonrisa, que con cajas sueltas se leía como puntos suspensivos."""
    import bmesh
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thickness,
                                     major_segments=segments, minor_segments=6,
                                     location=loc)
    o = bpy.context.object
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = [v for v in bm.verts if v.co.y > 0.002]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.rotation_euler = rotation
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
# cuerpo
# --------------------------------------------------------------------------- #
def head_point(P, direction, t=1.0):
    """Punto del elipsoide craneal en una dirección (t=1 superficie, t<1 dentro).

    Colocar los ojos/nariz/boca a mano en coordenadas planas es lo que dejaba
    los detalles FLOTANDO fuera de la cara: la superficie de un elipsoide no
    está a un y constante. Aquí cada detalle se ancla a la superficie real.
    """
    from mathutils import Vector
    hr = P["body"]["head_r"]
    hz = P["body"]["head_z"]
    d = Vector(direction).normalized()
    sx, sy, sz = HEAD_SCALE
    k = 1.0 / math.sqrt((d.x / (hr * sx)) ** 2 + (d.y / (hr * sy)) ** 2 + (d.z / (hr * sz)) ** 2)
    return (d.x * k * t, d.y * k * t, hz + d.z * k * t)


# --------------------------------------------------------------------------- #
# forma del cráneo: la cara se apoya sobre ESTE elipsoide, no sobre un plano.
# La lámina tiene la cabeza MÁS ANCHA QUE ALTA (0.74 de ancho x 0.57 de alto).
# --------------------------------------------------------------------------- #
HEAD_SCALE = (1.13, 1.07, 0.99)

# Medidas tomadas de la lámina de referencia (tools/ref_metrics.py), en
# fracciones de la altura total H del personaje:
#   ala del sombrero 0.59 H · cabeza 0.45 H de ancho y 0.41 de alto
#   camiseta 0.17 H de alto y 0.25 de ancho · pantalón 0.23 H
#   brazos en T-pose, envergadura 0.75 H
H_TOTAL = 1.45


def head_point(P, direction, t=1.0):
    """Punto del elipsoide craneal en una dirección (t=1 superficie, t<1 dentro).

    Colocar los detalles de la cara a mano en coordenadas planas es lo que los
    dejaba FLOTANDO fuera de la cara: la superficie de un elipsoide no está a
    un y constante. Aquí cada detalle se ancla a la superficie real.
    """
    from mathutils import Vector
    hr = P["body"]["head_r"]
    hz = P["body"]["head_z"]
    d = Vector(direction).normalized()
    sx, sy, sz = HEAD_SCALE
    k = 1.0 / math.sqrt((d.x / (hr * sx)) ** 2 + (d.y / (hr * sy)) ** 2 + (d.z / (hr * sz)) ** 2)
    return (d.x * k * t, d.y * k * t, hz + d.z * k * t)


# --------------------------------------------------------------------------- #
# forma del cráneo: la cara se apoya sobre ESTE elipsoide, no sobre un plano
# --------------------------------------------------------------------------- #
HEAD_SCALE = (1.13, 1.07, 0.99)

# Medidas tomadas de la lámina (tools/ref_metrics.py), en fracciones de la
# altura total H del personaje:
#   ala 0.61 H · cabeza 0.51 H de ancho (con orejas) y 0.47 de alto
#   camiseta 0.17 H de alto y 0.25 de ancho · piernas+calzado 0.26 H
#   brazos en T-pose, envergadura 0.78 H
H_TOTAL = 1.45


def head_point(P, direction, t=1.0):
    """Punto del elipsoide craneal en una dirección (t=1 superficie, t<1 dentro).

    Poner los detalles de la cara a mano en coordenadas planas es lo que los
    dejaba FLOTANDO: la superficie de un elipsoide no está a un y constante.
    """
    from mathutils import Vector
    hr = P["body"]["head_r"]
    hz = P["body"]["head_z"]
    d = Vector(direction).normalized()
    sx, sy, sz = HEAD_SCALE
    k = 1.0 / math.sqrt((d.x / (hr * sx)) ** 2 + (d.y / (hr * sy)) ** 2 + (d.z / (hr * sz)) ** 2)
    return (d.x * k * t, d.y * k * t, hz + d.z * k * t)


def build_body(P):
    """Cuerpo según la lámina: T-pose, cabeza enorme, cuello corto, torso
    angosto con cuello de camiseta, pantalón holgado con cintura y ruedos, y
    guantes tipo guante de box."""
    pal = P["palette"]
    skin = material("skin", pal["skin"], 0.72)
    shirt = material("shirt", pal["shirt"], 0.88)
    pants = material("pants", pal["pants"], 0.85)
    white = material("white", pal["white"], 0.80)
    dark = material("dark", pal["eyes"], 0.55)
    parts = {}

    # --- zapatillas: bajas, con puntera redondeada y suela -----------------
    legs = Part("legs", "legs")
    feet = Part("boots", "boots")
    for side in (-1, 1):
        cylinder(legs, 0.053, 0.270, (side * 0.077, 0, 0.216), pants, vertices=12, top=0.063)
        cylinder(legs, 0.068, 0.030, (side * 0.077, 0, 0.098), pants, vertices=12)   # ruedo
        box(feet, (0.136, 0.188, 0.060), (side * 0.090, -0.022, 0.054), white, bevel=0.026)
        sphere(feet, 0.059, (side * 0.090, -0.095, 0.048), white,
               scale=(1.0, 0.92, 0.66), segments=10, rings=6)
        box(feet, (0.144, 0.202, 0.018), (side * 0.090, -0.026, 0.009), white, bevel=0.007)
    # cadera: el pantalón es una masa, no dos tubos sueltos

    # --- torso: camiseta corta, cuello de camiseta y hombros que bajan -----
    torso = Part("torso", "torso")
    tee = lathe(torso, [
        (0.000, 0.002),
        (0.166, 0.000),
        (0.165, 0.030),
        (0.162, 0.090),
        (0.159, 0.140),
        (0.153, 0.180),
        (0.140, 0.206),
        (0.122, 0.224),
        (0.100, 0.236),
        (0.084, 0.244),
        (0.081, 0.254),
    ], (0, 0, 0.318), shirt, segments=28)
    tee.scale = (1.0, 0.88, 1.0)
    # sin aro de cuello: el remate de la camiseta ya lo da el perfil

    # --- cuello de piel: en la lámina se ve entre el mentón y la camiseta --
    neck = Part("neck", "neck")
    cylinder(neck, 0.066, 0.100, (0, 0, 0.570), skin, vertices=12)

    # --- brazos en T: manga corta con puño, brazo de piel y guante de box --
    arms = Part("arms", "arms")
    hands = Part("hands", "hands")
    pose = str(P["body"].get("pose", "t"))
    for side in (-1, 1):
        if pose == "down":
            # brazos caídos: es la pose del JUEGO (la lámina es una hoja de
            # turnaround, con T-pose; el personaje jugable no va en cruz)
            sh = (side * 0.112, 0.000, 0.500)
            sl = (side * 0.170, 0.000, 0.416)
            wr = (side * 0.188, -0.012, 0.292)
            cuff = (side * 0.190, -0.012, 0.268)
            glove = (side * 0.192, -0.014, 0.222)
            thumb = (side * 0.166, -0.058, 0.238)
            cuff_rot = (0, 0, 0)
        else:
            sh = (side * 0.110, 0.000, 0.482)
            sl = (side * 0.196, 0.000, 0.467)
            wr = (side * 0.288, 0.000, 0.461)
            cuff = (side * 0.296, 0.000, 0.460)
            glove = (side * 0.364, 0.000, 0.457)
            thumb = (side * 0.347, -0.060, 0.483)
            cuff_rot = (0, math.radians(90), 0)
        limb(arms, sh, sl, 0.060, shirt, vertices=12)
        limb(arms, sh, sl, 0.060, shirt, vertices=12, taper=0.94)          # manga
        limb(arms, sl, wr, 0.044, skin, vertices=10)
        sphere(hands, 0.088, glove, white,
               scale=(1.10, 1.00, 1.04), segments=12, rings=8)

    # --- cabeza enorme, orejas a la altura de los ojos ---------------------
    head = Part("head", "head")
    hz = P["body"]["head_z"]
    hr = P["body"]["head_r"]
    skull = sphere(head, hr, (0, 0, hz), skin, scale=HEAD_SCALE, segments=22, rings=13)
    # mandíbula: sin esto la cabeza es un huevo simétrico; la lámina la tiene
    # ancha en las sienes y más angosta hacia el mentón
    for v in skull.data.vertices:
        k = v.co.z / (hr * 1.05)
        if k < 0:      # mandíbula: se angosta hacia el mentón
            f = 1.0 - 0.22 * (min(-k, 1.0) ** 1.8)
        else:          # frente: se angosta hacia arriba (huevo, no óvalo)
            f = 1.0 - 0.16 * (min(k, 1.0) ** 2.0)
        v.co.x *= f
        v.co.y *= f
    for side in (-1, 1):
        ear = head_point(P, (side * 1.0, -0.01, -0.07), t=0.92)
        sphere(head, 0.078, ear, skin, scale=(0.58, 0.90, 1.00), segments=12, rings=9)

    # --- cara: ojos grandes, cejas gruesas, nariz de cuña y boca de omega ---
    face = Part("face", "face")
    for side in (-1, 1):
        sphere(face, 0.029, head_point(P, (side * 0.190, -1.0, 0.08), t=0.940),
               dark, segments=10, rings=7)
        box(face, (0.042, 0.011, 0.011), head_point(P, (side * 0.195, -0.95, 0.26), t=0.985),
            dark, rotation=(0, math.radians(side * 4), 0), bevel=0.005, smooth=True)
    nose = cylinder(face, 0.056, 0.070, head_point(P, (0, -1.0, -0.06), t=1.05),
                    skin, vertices=8, top=0.019)
    nose.rotation_euler = (math.radians(90), 0, 0)
    nose.scale = (1.0, 0.72, 1.0)
    for sx_ in (-1, 1):
        arc(face, 0.014, 0.0040, head_point(P, (sx_ * 0.036, -1.0, -0.24), t=0.976),
            dark, rotation=(math.radians(90), 0, 0), segments=10)

    parts.update({"legs": legs, "boots": feet, "torso": torso, "neck": neck,
                  "arms": arms, "hands": hands, "head": head, "face": face})
    return parts


# --------------------------------------------------------------------------- # # # #
# gorro (paramétrico: es lo único que se barre)
# --------------------------------------------------------------------------- #
def build_hat(P):
    """Fedora de paja de la lámina, construido como UNA superficie de revolución:
    copa con la cima redondeada, base de la copa más ancha, ala que sube desde
    el borde y cinta rosa-malva en la base."""
    h = P["hat"]
    pal = P["palette"]
    head_r = P["body"]["head_r"]
    head_top = P["body"]["head_z"] + head_r * HEAD_SCALE[2]

    # el sombrero se hunde en el cráneo (en la lámina el ala corta la cabeza
    # bastante por debajo de la coronilla)
    base_z = head_top - float(h.get("hat_drop", 0.10))

    hat_mat = material("hat", h["color"], 0.80)
    band_mat = material("band", pal["band"], 0.82)
    part = Part("hat", "hat")

    crown_r = head_r * 0.62
    brim_r = crown_r + float(h["ala"])
    copa = float(h["copa_h"])

    # perfil del fedora (r, z relativo al plano del ala)
    profile = [
        (0.000, -0.030),
        (0.200, -0.028),
        (0.330, -0.024),
        (brim_r - 0.026, -0.044),
        (brim_r - 0.010, -0.040),
        (brim_r - 0.002, -0.030),
        (brim_r, -0.016),
        (brim_r - 0.002, -0.002),
        (brim_r - 0.010, 0.008),
        (brim_r - 0.024, 0.011),
        (0.360, 0.006),
        (0.300, 0.010),
        (crown_r, 0.014),
        (crown_r - 0.002, 0.030),
        (crown_r - 0.004, 0.060),
        (crown_r - 0.006, 0.090),
        (crown_r - 0.010, copa),
        (crown_r * 0.90, copa + 0.016),
        (crown_r * 0.74, copa + 0.028),
        (crown_r * 0.50, copa + 0.036),
        (crown_r * 0.22, copa + 0.043),
        (0.000, copa + 0.044),
    ]
    cap = lathe(part, profile, (0, 0, base_z), hat_mat, segments=32)

    # el ala ondula (en la lámina el borde no es un círculo perfecto)
    for v in cap.data.vertices:
        rr = math.hypot(v.co.x, v.co.y)
        if rr > brim_r - 0.05 and v.co.z < 0.02:
            ang = math.atan2(v.co.y, v.co.x)
            k = (rr - (brim_r - 0.05)) / 0.05          # 0 en la copa, 1 en el borde
            v.co.z -= 0.020 * abs(math.sin(ang)) * k    # cae en los costados


    # cinta: sigue la pared de la copa
    cylinder(part, crown_r + 0.004, 0.046, (0, 0, base_z + 0.030), band_mat,
             vertices=32, top=crown_r + 0.001, smooth=True)

    return part


# --------------------------------------------------------------------------- # # # # #
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
