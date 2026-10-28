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
    "face": {
        # v3 = rasgos en VOLUMEN (esclerótica + iris + pupila + brillo + párpado,
        # cejas arqueadas, nariz de puente y aletas, boca con labios). v1 = las
        # primitivas planas de 2026-09, que se leían como pegatinas.
        "preset": "v3",
    },
    "body": {
        "preset": "v1_frozen",
        "pose": "t",          # t = hoja de referencia · down = pose de juego
        "head_z": 0.882,
        "head_r": 0.278,
        "head_top": 1.320,
        "lean_deg": 0.0,
    },
    "hat": {
        "tipo": "paja",       # toque | paja | gorra
        "copa_h": 0.150,        # altura de la copa sobre la banda
        "lobulos": 4,
        "brim_r": 0.370,           # ala corta: con 0.18 el ala tapa la cara a 68°
        "banda": "fina",
        "color": "#DDBE86",    # paja: ΔE ≈ 27 contra la arena (la paja daba 8)
        "tilt_deg": 0.0,
        "brim_front_short": 0.0,
        "hat_drop": 0.030,
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
        "iris": "#59392B",      # castaño: sin esto el ojo es un botón negro
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
        mod.segments = 1
        with bpy.context.temp_override(object=o):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    return part.add(o)


# --------------------------------------------------------------------------- #
# cuerpo
# --------------------------------------------------------------------------- #
# forma del cráneo: la cara se apoya sobre ESTE elipsoide, no sobre un plano.
# La lámina tiene la cabeza MÁS ANCHA QUE ALTA (0.74 de ancho x 0.57 de alto).
#
# NOTA (2026-10-28): esta función estaba definida TRES veces en el archivo, con
# HEAD_SCALE y H_TOTAL triplicados. Como gana la última, editar la primera no tenía
# ningún efecto (la trampa perfecta para perder una tarde). Ahora hay UNA.
# --------------------------------------------------------------------------- #
HEAD_SCALE = (1.19, 1.08, 1.00)

# Medidas tomadas de la lámina (tools/ref_metrics.py), en fracciones de la altura
# total H del personaje:
#   ala 0.61 H · cabeza 0.51 H de ancho (con orejas) y 0.47 de alto
#   camiseta 0.17 H de alto y 0.25 de ancho · piernas+calzado 0.26 H
#   brazos en T-pose, envergadura 0.78 H
H_TOTAL = 1.45


def head_point(P, direction, t=1.0):
    """Punto del elipsoide craneal en una dirección (t=1 superficie, t<1 dentro).

    Poner los detalles de la cara a mano en coordenadas planas es lo que los
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


def cara_punto(P, direction, fuera=0.0):
    """Punto del elipsoide en una DIRECCIÓN + normal unitaria (para anclar detalles)."""
    from mathutils import Vector
    hz = P["body"]["head_z"]
    S = Vector(head_point(P, direction, 1.0))
    n = (S - Vector((0.0, 0.0, hz))).normalized()
    return S + n * fuera, n


def superficie(P, x, z_rel, fuera=0.0):
    """Punto de la cara con coordenadas de PANTALLA (x, z) + normal.

    `x` es el desplazamiento lateral en unidades y `z_rel` la altura respecto del
    centro de la cabeza. Devuelve (punto, normal).

    Por qué existe: pasar direcciones normalizadas ("x=1.79") parece lo mismo que
    pasar unidades, y no lo es — (1.79, -1, 0.5) normalizado apunta 60° al COSTADO,
    así que los ojos salían pegados al borde de la cabeza. Aquí se resuelve la
    superficie del elipsoide para la x,z pedidas:

        x²/a² + y²/b² + z²/c² = 1   ->   y = -b·sqrt(1 - x²/a² - z²/c²)

    y la normal es (x/a², y/b², z/c²). Con esto "ojo a ±0.10 del centro" es
    literalmente eso, en las mismas unidades que el resto del modelo.
    """
    from mathutils import Vector
    hr = P["body"]["head_r"]
    hz = P["body"]["head_z"]
    a, b, c = hr * HEAD_SCALE[0], hr * HEAD_SCALE[1], hr * HEAD_SCALE[2]
    z = z_rel
    k = max(1e-6, 1.0 - (x * x) / (a * a) - (z * z) / (c * c))
    y = -b * math.sqrt(k)
    n = Vector((x / (a * a), y / (b * b), z / (c * c))).normalized()
    return Vector((x, y, hz + z)) + n * fuera, n


def hinge(objs, pivot, name):
    """Cuelga objetos de un nodo vacío ubicado en la bisagra (hombro, cadera,
    cuello). Rotar ese nodo en Godot mueve la extremidad alrededor del pivote
    correcto, no alrededor del origen del modelo."""
    from mathutils import Matrix, Vector
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = Vector(pivot)
    e.empty_display_size = 0.04
    for o in objs:
        o.parent = e
        o.matrix_parent_inverse = Matrix.Translation(-Vector(pivot))
    return e


# --------------------------------------------------------------------------- #
# caras
# --------------------------------------------------------------------------- #
def build_ears(P, head, skin):
    """Oreja INTEGRADA: no es un disco pegado al costado.

    La versión anterior era una esfera achatada con centro en la superficie y un
    aro (hélix) alrededor: en el render se veía como una rueda pegada al cráneo.
    Una oreja se lee cuando (a) nace de dentro, (b) es más alta que ancha y (c)
    tiene un borde que se pliega hacia adentro. Aquí: pabellón hundido 40 % y
    hélix como casquete del MISMO material, sin aro suelto.
    """
    for side in (-1, 1):
        a, n = superficie(P, side * (P["body"]["head_r"] * HEAD_SCALE[0]), 0.0)
        from mathutils import Vector
        base = Vector(a) + n * 0.004        # apoyada, no flotando ni hundida
        # pabellón: más alto que ancho, ligeramente inclinado hacia atrás
        sphere(head, 0.068, base, skin, scale=(0.40, 0.82, 1.00),
               segments=10, rings=7)
        # hélix: el reborde que se pliega, apoyado en el borde de atrás
        helix = base + Vector((side * 0.004, 0.014, 0.006))
        sphere(head, 0.050, helix, skin, scale=(0.30, 0.66, 0.82),
               segments=9, rings=6)


def build_face_v1(P, face, mats):
    """Cara v1 (2026-09): primitivas planas. Se conserva para el A/B."""
    dark = mats["dark"]
    skin = mats["skin"]
    for side in (-1, 1):
        sphere(face, 0.031, head_point(P, (side * 0.205, -1.0, 0.02), t=0.940),
               dark, segments=10, rings=7)
        box(face, (0.046, 0.012, 0.012), head_point(P, (side * 0.200, -0.95, 0.20), t=0.985),
            dark, rotation=(0, math.radians(side * 4), 0), bevel=0.005, smooth=True)
    nose = cylinder(face, 0.050, 0.068, head_point(P, (0, -1.0, -0.10), t=1.03),
                    skin, vertices=8, top=0.019)
    nose.rotation_euler = (math.radians(90), 0, 0)
    nose.scale = (1.0, 0.72, 1.0)
    for sx_ in (-1, 1):
        arc(face, 0.016, 0.0042, head_point(P, (sx_ * 0.036, -1.0, -0.28), t=0.976),
            dark, rotation=(math.radians(90), 0, 0), segments=10)


# medidas de la cara v3, en unidades del modelo (la cabeza mide 0.66 de ancho).
# Salen de la lámina (docs/referencia.png): ojo ≈0.076 del ancho de cabeza, separación
# entre centros ≈0.32, boca a 0.30 del alto por debajo de los ojos.
F3 = {
    "ojo_r": 0.056,        # esclerótica: casquete visible ≈ 0.078 de diámetro
    "ojo_sep": 0.100,      # x del centro de cada ojo
    "ojo_alto": 0.030,     # dirección (se normaliza con la esfera)
    "hundido": 0.62,       # fracción del radio que va por dentro del cráneo
    "parpado": 0.72,       # cuánto sube el párpado (fracción del radio)
    "ceja_largo": 0.098,
    "boca_r": 0.055,
}


# medidas de la cara v3, en UNIDADES del modelo (la cabeza mide 0.66 de ancho y
# 0.56 de alto). Salen de la lámina docs/referencia.png medida con tools/ref_metrics.py:
# ojo 0.076 del ancho de cabeza · separación entre centros 0.32 · boca 0.30 por
# debajo de los ojos.
F3 = {
    # Objetivos medidos en la lámina (tools/cara_metrics.py sobre docs/referencia.png):
    #   ojo 0.068 del ancho de cabeza · alto/ancho 1.20 · separación 0.309 · 4.5 ojos
    #   entre centros. Con el cráneo de 0.662 de ancho eso es un ojo visible de 0.045
    #   y una separación de 0.205. Un ojo de 0.052 de radio daba 0.095 visibles: el
    #   DOBLE de la referencia, y eso es lo que hacía la cara "de alien".
    "ojo_x": 0.086,        # centro horizontal de cada ojo (= separación 0.172)
    "ojo_z": 0.022,        # altura respecto del centro de la cabeza
    "ojo_r": 0.026,        # radio de la esfera; visible ≈ 0.055 por el hundido
    "hundido": 0.30,       # fracción del radio que entra en el cráneo
    "ceja_z": 0.098,
    "ceja_x0": 0.048,      # arranque (junto a la nariz)
    "ceja_x1": 0.138,      # punta
    "nariz_z": -0.030,
    "boca_z": -0.090,
    "boca_r": 0.058,
}


def build_face_v3(P, head, face, mats):
    """Cara v3: pocas piezas, bien formadas y asimétricas (como la lámina).

    La primera versión de esta cara puso esclerótica blanca + iris + pupila + un
    párpado de bola por ojo: el resultado se leía como "ojos hinchados", no como
    un personaje. La lámina (docs/referencia.png) y Overcooked usan lo contrario:
    OJO NEGRO CON BRILLO, sin blanco. Menos piezas y mejor forma:

      · ojo negro ovalado (más alto que ancho) con DOS brillos: el grande arriba
        a la izquierda y uno chico abajo a la derecha. El brillo es lo que lo hace
        parecer húmedo y vivo; sin él, es una pegatina.
      · ceja de tres segmentos con grosor decreciente y arco: una caja recta se
        lee como pestaña postiza.
      · nariz de botón con dos aletas hundidas, sin puente cilíndrico.
      · boca de arco fino con labio inferior de volumen y sonrisa LEVEMENTE
        torcida: la simetría perfecta es la firma de la máquina.

    Lo que NO lleva (y por qué): pómulos, mentón y rubor como esferas sueltas se
    ven como protuberancias pegadas, que es exactamente el efecto "generado".
    """
    from mathutils import Vector
    dark, white, skin = mats["dark"], mats["white"], mats["skin"]
    mouth = mats["mouth"]

    # ---------------------------------------------------------------- ojos
    for lado in (-1, 1):
        # asimetría de mano: el derecho 2 % más grande y 0.6 mm más bajo
        R = F3["ojo_r"] * (1.02 if lado > 0 else 1.0)
        dz = -0.006 if lado > 0 else 0.0
        S, n = superficie(P, lado * F3["ojo_x"], F3["ojo_z"] + dz)
        # ojo negro: casquete ovalado (más alto que ancho), hundido en el cráneo
        sphere(face, R, S - n * (R * F3["hundido"]), dark,
               scale=(0.98, 0.55, 1.20), segments=10, rings=7)
        # Brillos en unidades ABSOLUTAS, no proporcionales al radio: el reflejo de un
        # ojo no encoge cuando el ojo es más chico.
        b1 = S + n * (R * 0.55) + Vector((-lado * 0.0075, 0.0, 0.010))
        sphere(face, 0.0058, b1, white, segments=8, rings=6)
        b2 = S + n * (R * 0.62) + Vector((lado * 0.0062, 0.0, -0.0078))
        sphere(face, 0.0026, b2, white, segments=6, rings=5)

    # ---------------------------------------------------------------- cejas
    for lado in (-1, 1):
        # arco con el pico al 45 %; la derecha sube 4 mm (cara despierta)
        alza = 0.004 if lado > 0 else 0.0
        xs = (F3["ceja_x0"], (F3["ceja_x0"] + F3["ceja_x1"]) * 0.52, F3["ceja_x1"])
        zs = (F3["ceja_z"], F3["ceja_z"] + 0.013 + alza, F3["ceja_z"] + 0.006 + alza)
        pts = []
        for x_, z_ in zip(xs, zs):
            p_, n_ = superficie(P, lado * x_, z_)
            pts.append(p_ + n_ * 0.005)
        for k in range(len(pts) - 1):
            limb(face, pts[k], pts[k + 1], 0.0068 - 0.0018 * k, dark,
                 vertices=6, taper=0.58)

    # ---------------------------------------------------------------- nariz
    # nariz de botón: una esfera achatada + dos aletas hundidas. Sin puente.
    base, n1 = superficie(P, 0.0, F3["nariz_z"])
    punta = base + n1 * 0.010
    sphere(face, 0.027, punta, skin, scale=(1.02, 0.86, 0.92), segments=10, rings=7)
    for sx_ in (-1, 1):
        al, na = superficie(P, sx_ * 0.026, F3["nariz_z"] - 0.004)
        sphere(face, 0.015, al + na * 0.004, skin,
               scale=(0.95, 0.80, 0.74), segments=8, rings=6)

    # ---------------------------------------------------------------- boca
    Son, nb = superficie(P, 0.0, F3["boca_z"])
    # sonrisa torcida 2°: un lado sube apenas; el ojo humano lo registra
    giro = math.radians(2.0)
    eje = Vector((math.cos(giro), 0.0, math.sin(giro)))
    # Sin labio de color: en la lámina la boca es UNA LÍNEA. Un labio más oscuro
    # dentro del arco se lee como lengua (pasó en la iteración v3h).
    # línea de la boca
    linea = arc(face, F3["boca_r"], 0.0052, Son + nb * 0.005, dark,
                rotation=(math.radians(90), 0, 0), segments=16)
    linea.rotation_euler = (math.radians(90), 0, giro)
    # Sin comisuras: dos bolas negras en los extremos se leen como piercings. El
    # arco ya sugiere la comisura; el labio inferior le da el volumen.


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

    # --- piernas y zapatillas, UNA por lado (se animan por separado) ------
    for side, tag in ((-1, "l"), (1, "r")):
        leg = Part(f"leg_{tag}", "legs")
        foot = Part(f"boot_{tag}", "boots")
        cylinder(leg, 0.052, 0.295, (side * 0.068, 0, 0.228), pants, vertices=10, top=0.060)
        cylinder(leg, 0.068, 0.028, (side * 0.068, 0, 0.096), pants, vertices=10)   # ruedo
        box(foot, (0.124, 0.178, 0.056), (side * 0.068, -0.022, 0.050), white, bevel=0.024)
        sphere(foot, 0.055, (side * 0.068, -0.090, 0.045), white,
               scale=(1.0, 0.92, 0.66), segments=8, rings=5)
        box(foot, (0.132, 0.190, 0.016), (side * 0.068, -0.026, 0.008), white, bevel=0)
        parts[f"leg_{tag}"] = leg
        parts[f"boot_{tag}"] = foot

    # --- torso: camiseta corta, cuello de camiseta y hombros que bajan -----
    torso = Part("torso", "torso")
    tee = lathe(torso, [
        (0.000, 0.002),
        (0.160, 0.000),
        (0.160, 0.030),
        (0.159, 0.090),
        (0.158, 0.150),
        (0.152, 0.190),
        (0.140, 0.214),
        (0.118, 0.232),
        (0.094, 0.242),
        (0.080, 0.249),
        (0.080, 0.256),
    ], (0, 0, 0.318), shirt, segments=12)
    tee.scale = (1.0, 0.88, 1.0)
    # sin aro de cuello: el remate de la camiseta ya lo da el perfil

    # --- cuello de piel: en la lámina se ve entre el mentón y la camiseta --
    neck = Part("neck", "neck")
    cylinder(neck, 0.066, 0.100, (0, 0, 0.570), skin, vertices=12)

    # --- brazos en T: manga corta con puño, brazo de piel y guante de box --
    pose = str(P["body"].get("pose", "t"))
    for side, tag in ((-1, "l"), (1, "r")):
        arms = Part(f"arm_{tag}", "arms")
        hands = Part(f"hand_{tag}", "hands")
        parts[f"arm_{tag}"] = arms
        parts[f"hand_{tag}"] = hands
        if pose == "down":
            # brazos caídos: es la pose del JUEGO (la lámina es una hoja de
            # turnaround, con T-pose; el personaje jugable no va en cruz)
            sh = (side * 0.075, 0.000, 0.505)
            sl = (side * 0.168, 0.000, 0.418)
            wr = (side * 0.188, -0.012, 0.292)
            cuff = (side * 0.190, -0.012, 0.268)
            glove = (side * 0.192, -0.014, 0.222)
            thumb = (side * 0.166, -0.058, 0.238)
            cuff_rot = (0, 0, 0)
        else:
            sh = (side * 0.075, 0.000, 0.487)
            sl = (side * 0.192, 0.000, 0.470)
            wr = (side * 0.288, 0.000, 0.461)
            cuff = (side * 0.296, 0.000, 0.460)
            glove = (side * 0.364, 0.000, 0.457)
            thumb = (side * 0.347, -0.060, 0.483)
            cuff_rot = (0, math.radians(90), 0)
        limb(arms, sh, sl, 0.066, shirt, vertices=10, taper=0.94)          # manga
        limb(arms, sl, wr, 0.050, skin, vertices=9)
        g_scale = (1.00, 1.02, 1.28) if pose == "down" else (1.28, 1.02, 1.00)
        sphere(hands, 0.078, glove, white, scale=g_scale, segments=9, rings=6)

    # --- cabeza enorme, orejas a la altura de los ojos ---------------------
    head = Part("head", "head")
    hz = P["body"]["head_z"]
    hr = P["body"]["head_r"]
    skull = sphere(head, hr, (0, 0, hz), skin, scale=HEAD_SCALE, segments=22, rings=13)
    # mandíbula y frente: sin esto la cabeza es un huevo simétrico; la lámina la
    # tiene ancha en las sienes y más angosta hacia el mentón
    for v in skull.data.vertices:
        k = v.co.z / (hr * 1.05)
        if k < 0:      # mandíbula: se angosta hacia el mentón
            f = 1.0 - 0.18 * (min(-k, 1.0) ** 2.0)
        else:          # frente: se angosta hacia arriba (huevo, no óvalo)
            f = 1.0 - 0.24 * (min(k, 1.0) ** 1.8)
        v.co.x *= f
        v.co.y *= f
    build_ears(P, head, skin)

    # --- cara ---------------------------------------------------------------
    face = Part("face", "face")
    mats = {"skin": skin, "dark": dark, "white": white,
            "iris": material("iris", pal.get("iris", "#59392B"), 0.55),
            "mouth": material("mouth", pal["mouth"], 0.72),
            "blush": material("blush", pal.get("band", "#B98683"), 0.85)}
    if str(P.get("face", {}).get("preset", "v3")) == "v1":
        build_face_v1(P, face, mats)
    else:
        build_face_v3(P, head, face, mats)

    parts.update({"torso": torso, "neck": neck, "head": head, "face": face})
    return parts


# --------------------------------------------------------------------------- # # # #
# gorro (paramétrico: es lo único que se barre)
# --------------------------------------------------------------------------- #
def build_hat(P):
    """Fedora de paja construido con el PERFIL MEDIDO en la lámina.

    Medido con `tools/ref_metrics.py` + conteo de filas sobre docs/referencia.png
    (fracciones de la altura total H del personaje):
      - copa: diámetro 0.45 H, alto 0.10 H, con la pared apenas abombada y la
        cima redondeada (la fila del tope mide 0.17 H: no es un disco plano)
      - ala: diámetro 0.74 H, espesor 0.05 H y el borde 0.03 H MÁS BAJO que la
        base de la copa (por eso no se lee como un plato)
    """
    h = P["hat"]
    pal = P["palette"]
    head_r = P["body"]["head_r"]
    head_top = P["body"]["head_z"] + head_r * HEAD_SCALE[2]

    base_z = head_top - float(h.get("hat_drop", 0.030))

    hat_mat = material("hat", h["color"], 0.80)
    band_mat = material("band", pal["band"], 0.82)
    part = Part("hat", "hat")

    # radios absolutos medidos (H≈1.32): copa 0.222, ala 0.370
    crown_r = head_r * 1.02
    brim_r = float(h.get("brim_r", 0.370))
    copa = float(h.get("copa_h", 0.136))

    # Perfil SIN puntos redundantes: cada punto cuesta segmentos x 2 triángulos.
    # Se conservan los que definen la SILUETA (canto del ala, quiebre copa/ala,
    # cima) y se quitan los intermedios de curvas que el sombreado suave resuelve.
    profile = [
        (0.000, -0.052),
        (crown_r * 0.55, -0.052),
        (brim_r - 0.055, -0.048),
        (brim_r - 0.018, -0.042),   # canto inferior: sin este par el ala se ve
        (brim_r - 0.004, -0.036),   # como un plato plano de dos caras
        (brim_r, -0.026),          # canto redondeado
        (brim_r - 0.020, -0.006),
        (brim_r - 0.060, -0.002),
        (crown_r + 0.055, 0.000),
        (crown_r, 0.004),
        (crown_r + 0.004, 0.030),   # abombamiento de la copa (se ve de perfil)
        (crown_r + 0.006, 0.060),
        (crown_r - 0.012, 0.112),
        (crown_r - 0.045, 0.126),   # cúpula: sin estos dos puntos la copa se ve
        (crown_r - 0.095, 0.133),   # truncada, y es lo más grande de la silueta
        (crown_r - 0.150, copa - 0.002),
        (crown_r - 0.190, copa),
        (0.000, copa),
    ]
    cap = lathe(part, profile, (0, 0, base_z), hat_mat, segments=18)

    # el ala ondula apenas en los costados (la lámina no es un círculo perfecto)
    for v in cap.data.vertices:
        rr = math.hypot(v.co.x, v.co.y)
        if rr > brim_r - 0.06:
            ang = math.atan2(v.co.y, v.co.x)
            k = (rr - (brim_r - 0.06)) / 0.06
            v.co.z -= 0.008 * abs(math.sin(ang)) * k

    # cinta: sigue la pared de la copa, ancha como en la lámina
    # cinta: MISMO número de lados que la copa (18) y un poco por fuera.
    # Bug real (2026-10-28): con 16 lados sobre una copa de 18, las caras de una
    # y otra se cruzan y la cinta aparece llena de PUAS triangulares. Dos
    # superficies concéntricas tienen que compartir el número de lados.
    cylinder(part, crown_r + 0.010, 0.030, (0, 0, base_z + 0.026), band_mat,
             vertices=18, top=crown_r + 0.012, smooth=True)

    return part


# --------------------------------------------------------------------------- # # # # # #
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
    rig_limbs(parts, P)

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


def rig_limbs(parts, P):
    """Cuelga brazos, piernas y cabeza de vacíos en sus bisagras.

    Godot después solo rota esos nodos: `arm_l`, `arm_r`, `leg_l`, `leg_r`,
    `head`. Sin esto las extremidades giran alrededor del origen del modelo y
    la animación se ve como un muñeco desarmándose.
    """
    down = str(P["body"].get("pose", "t")) == "down"
    sh_z = 0.500 if down else 0.487
    for tag, sx in (("l", -1), ("r", 1)):
        hinge([o for p in (parts[f"arm_{tag}"], parts[f"hand_{tag}"]) for o in p.objs],
              (sx * 0.075, 0.0, sh_z), f"arm_{tag}")
        hinge([o for p in (parts[f"leg_{tag}"], parts[f"boot_{tag}"]) for o in p.objs],
              (sx * 0.068, 0.0, 0.375), f"leg_{tag}")
    hinge([o for p in (parts["head"], parts["face"]) for o in p.objs],
          (0.0, 0.0, 0.600), "head")
    # el gorro acompaña a la cabeza
    if "hat" in parts:
        hinge(parts["hat"].objs, (0.0, 0.0, 0.600), "hat")


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
                if o.parent is not None:
                    o.parent.select_set(True)      # los vacíos de bisagra
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
