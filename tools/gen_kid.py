"""
Generador del personaje (Blender headless) — chico de playa.

Uso:
    blender --background --python tools/gen_kid.py -- --out /tmp/kid --render

Salidas:
    <out>/kid.glb      modelo para el juego (con bisagras arm_l/arm_r/leg_l/leg_r/head/hat)
    <out>/kid.png      render de referencia para mirar a ojo
"""

import argparse
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------- #
# materiales
# --------------------------------------------------------------------------- #
PALETTE = {
    "skin": (0.96, 0.75, 0.60),
    "skin_dark": (0.90, 0.63, 0.50),
    "white": (0.97, 0.97, 0.95),
    "stripe": (0.33, 0.50, 0.78),
    "shorts": (0.13, 0.19, 0.38),
    "straw": (0.80, 0.66, 0.42),
    "straw_light": (0.87, 0.74, 0.50),
    "straw_dark": (0.63, 0.48, 0.29),
    "hair": (0.38, 0.23, 0.13),
    "hair_dark": (0.28, 0.16, 0.09),
    "dark": (0.08, 0.07, 0.09),
    "iris": (0.42, 0.27, 0.16),
    "mouth": (0.42, 0.18, 0.16),
    "blush": (0.97, 0.62, 0.58),
    "sandal": (0.30, 0.50, 0.80),
    "glove": (0.55, 0.38, 0.24),
}

MATS = {}


def srgb_to_linear(c):
    """Blender espera el Base Color en lineal; la paleta está en sRGB."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(name):
    if name in MATS:
        return MATS[name]
    r, g, b = PALETTE[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = None
    for node in nt.nodes:
        if node.type == "BSDF_PRINCIPLED":
            bsdf = node
            break
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.get("Material Output") or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = (
        srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)
    bsdf.inputs["Roughness"].default_value = 0.65
    bsdf.inputs["Metallic"].default_value = 0.0
    MATS[name] = m
    return m


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


# --------------------------------------------------------------------------- #
# geometría
# --------------------------------------------------------------------------- #
def lathe(name, profile, segments=32, mats=None, smooth=True):
    """Superficie de revolución. `profile` = [(radio, z), ...] de abajo a arriba.
    `mats` = lista de nombres de material, uno por tramo (banda)."""
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)

    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)

    bm.verts.ensure_lookup_table()
    for k in range(len(rings) - 1):
        a_ring = rings[k]
        b_ring = rings[k + 1]
        for i in range(segments):
            j = (i + 1) % segments
            f = bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
            f.material_index = k if mats else 0
            f.smooth = smooth
    bm.to_mesh(me)
    bm.free()

    if mats:
        for m in mats:
            me.materials.append(material(m))
    else:
        me.materials.append(material("skin"))
    return ob


def sphere(name, radius, loc, mat, scale=(1, 1, 1), segments=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=radius, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    ob.data.materials.append(material(mat))
    bpy.ops.object.shade_smooth()
    return ob


def cylinder(name, r1, r2, height, loc, mat, rot=(0, 0, 0), verts=32):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2,
                                    depth=height, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(material(mat))
    bpy.ops.object.shade_smooth()
    return ob


def cube(name, size, loc, mat, rot=(0, 0, 0), bevel=0.01):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(material(mat))
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
    return ob


def torus(name, major, minor, loc, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=48, minor_segments=12,
                                     location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(material(mat))
    bpy.ops.object.shade_smooth()
    return ob


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = name
    return ob


def hinge(name, pivot, objs, parent=None):
    """Nodo vacío en la bisagra: Godot lo rota y mueve la extremidad."""
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = Vector(pivot)
    if parent is not None:
        e.parent = parent
    e.empty_display_size = 0.04
    for o in objs:
        o.parent = e
        o.matrix_parent_inverse = Matrix.Translation(-Vector(pivot))
    return e


# --------------------------------------------------------------------------- #
# piezas
# --------------------------------------------------------------------------- #
HEAD_R = 0.200
HEAD_Z = 0.700
HINGE_Z = 0.520


def build_legs(root):
    for side, tag in ((-1, "l"), (1, "r")):
        parts = []
        x = side * 0.068
        parts.append(cylinder(f"leg_{tag}", 0.050, 0.056, 0.16, (x, 0, 0.120), "skin"))
        # sandalia: suela ovalada + tiras
        sole = sphere(f"sole_{tag}", 0.075, (x, 0.035, 0.018), "sandal",
                      scale=(1.0, 1.55, 0.38))
        parts.append(sole)
        for i in (-1, 1):
            strap = cube(f"strap_{tag}{i}", (0.020, 0.090, 0.016),
                         (x + i * 0.028, 0.060, 0.040), "white",
                         rot=(0, 0, math.radians(i * 26)), bevel=0.006)
            parts.append(strap)
        parts.append(cube(f"strap_back_{tag}", (0.018, 0.060, 0.016),
                          (x, 0.012, 0.040), "white", bevel=0.006))
        leg = join(parts, f"leg_{tag}_mesh")
        hinge(f"leg_{tag}", (x, 0, 0.205), [leg], root)


def build_torso(root):
    # short: volumen redondeado
    shorts = lathe("shorts", [
        (0.150, 0.170), (0.170, 0.195), (0.178, 0.230),
        (0.180, 0.270), (0.178, 0.300),
    ], mats=["shorts", "shorts", "shorts", "shorts"])
    shorts.parent = root

    # camiseta a rayas: 7 bandas
    bands = 7
    z0, z1 = 0.285, 0.520
    r0, r1 = 0.190, 0.125
    profile = []
    mats = []
    for i in range(bands + 1):
        t = i / bands
        profile.append((r0 + (r1 - r0) * t, z0 + (z1 - z0) * t))
    for i in range(bands):
        mats.append("white" if i % 2 == 0 else "stripe")
    shirt = lathe("shirt", profile, segments=40, mats=mats)
    shirt.parent = root

    # cuello de la camiseta
    collar = torus("collar", 0.118, 0.014, (0, 0, 0.520), "white")
    collar.parent = root
    neck = cylinder("neck", 0.070, 0.078, 0.07, (0, 0, 0.545), "skin")
    neck.parent = root


def build_arms(root):
    for side, tag in ((-1, "l"), (1, "r")):
        parts = []
        # hombro y manga (se funden con el torso)
        parts.append(sphere(f"shoulder_{tag}", 0.070, (side * 0.150, 0, 0.455), "stripe",
                            scale=(1.0, 0.95, 1.0)))
        parts.append(cylinder(f"sleeve_{tag}", 0.062, 0.058, 0.085,
                              (side * 0.160, 0, 0.405), "stripe",
                              rot=(0, math.radians(side * 10), 0)))
        parts.append(torus(f"cuff_{tag}", 0.056, 0.010, (side * 0.166, 0, 0.363), "white",
                           rot=(math.radians(90), 0, 0)))
        # antebrazo y guante
        parts.append(cylinder(f"forearm_{tag}", 0.044, 0.040, 0.10,
                              (side * 0.172, 0, 0.318), "skin",
                              rot=(0, math.radians(side * 6), 0)))
        parts.append(sphere(f"glove_{tag}", 0.058, (side * 0.178, 0, 0.250), "glove",
                            scale=(1.0, 1.05, 1.15)))
        parts.append(sphere(f"thumb_{tag}", 0.028, (side * 0.215, 0.030, 0.250), "glove"))
        arm = join(parts, f"arm_{tag}_mesh")
        hinge(f"arm_{tag}", (side * 0.145, 0, 0.455), [arm], root)


def build_head(root):
    head_parts = []
    head_parts.append(sphere("skull", HEAD_R, (0, 0, HEAD_Z), "skin",
                             segments=40, rings=24))
    # orejas
    for side in (-1, 1):
        head_parts.append(sphere(f"ear_{side}", 0.048, (side * HEAD_R * 0.94, 0.010, HEAD_Z - 0.02),
                                 "skin_dark", scale=(0.45, 0.80, 1.0), segments=16, rings=10))

    # pelo: casquete de rizos
    curls = [
        # corona (arriba y atrás)
        (0.000, 0.020, 0.185, 0.110), (-0.100, 0.020, 0.170, 0.100),
        (0.100, 0.020, 0.170, 0.100), (-0.165, 0.000, 0.110, 0.090),
        (0.165, 0.000, 0.110, 0.090),
        # nuca
        (0.000, -0.130, 0.120, 0.105), (-0.105, -0.115, 0.105, 0.095),
        (0.105, -0.115, 0.105, 0.095), (-0.170, -0.060, 0.060, 0.085),
        (0.170, -0.060, 0.060, 0.085),
        # laterales, por detrás de las orejas
        (-0.185, 0.010, 0.030, 0.072), (0.185, 0.010, 0.030, 0.072),
    ]
    for i, (x, y, z, r) in enumerate(curls):
        head_parts.append(sphere(f"curl_{i}", r, (x, y, HEAD_Z + z), "hair",
                                 scale=(1.0, 0.92, 0.95), segments=16, rings=10))
    # flequillo: por encima de las cejas, sin tapar los ojos
    for i in range(3):
        head_parts.append(sphere(f"fringe_{i}", 0.066, (-0.080 + 0.080 * i, 0.115, HEAD_Z + 0.150),
                                 "hair", scale=(1.05, 0.80, 0.75), segments=16, rings=10))

    # cara
    for side in (-1, 1):
        ex = side * 0.080
        ez = HEAD_Z + 0.020
        # esclerótica
        head_parts.append(sphere(f"eye_{side}", 0.058, (ex, 0.170, ez), "white",
                                 scale=(1.0, 0.45, 1.12), segments=20, rings=12))
        head_parts.append(sphere(f"iris_{side}", 0.037, (ex, 0.188, ez - 0.003), "iris",
                                 scale=(1.0, 0.35, 1.02), segments=18, rings=10))
        head_parts.append(sphere(f"pupil_{side}", 0.021, (ex, 0.198, ez - 0.003), "dark",
                                 scale=(1.0, 0.30, 1.02), segments=14, rings=8))
        head_parts.append(sphere(f"glint_{side}", 0.011, (ex - 0.012, 0.204, ez + 0.016), "white",
                                 segments=10, rings=6))
        # ceja
        head_parts.append(cube(f"brow_{side}", (0.085, 0.030, 0.024),
                               (ex, 0.185, ez + 0.098), "hair_dark",
                               rot=(0, math.radians(side * 8), 0), bevel=0.008))
        # cachete
        head_parts.append(sphere(f"cheek_{side}", 0.048, (side * 0.135, 0.150, HEAD_Z - 0.055),
                                 "blush", scale=(1.0, 0.45, 0.70), segments=16, rings=10))

    # nariz
    head_parts.append(sphere("nose", 0.028, (0, 0.192, HEAD_Z - 0.030), "skin_dark",
                             scale=(1.0, 0.85, 0.80), segments=16, rings=10))

    # sonrisa: tres cubos finos
    for i in (-1, 0, 1):
        head_parts.append(cube(f"mouth_{i}", (0.030 if i == 0 else 0.020, 0.014, 0.012),
                               (i * 0.030, 0.186, HEAD_Z - 0.078 + abs(i) * 0.010),
                               "mouth", rot=(0, 0, math.radians(-i * 26)), bevel=0.004))

    head = join(head_parts, "head_mesh")
    hinge("head", (0, 0, HINGE_Z), [head], root)


def build_hat(root):
    # ala: perfil que se abre, con el borde ondulado
    brim = lathe("brim", [
        (0.120, 0.882), (0.200, 0.888), (0.262, 0.892), (0.292, 0.890),
        (0.296, 0.884), (0.268, 0.878), (0.190, 0.874), (0.120, 0.872),
    ], segments=64, mats=["straw", "straw_light", "straw_dark", "straw_dark",
                         "straw_dark", "straw_light", "straw"])

    # onda del borde: desplazar los vértices del borde en Z
    me = brim.data
    for v in me.vertices:
        r = math.hypot(v.co.x, v.co.y)
        if r > 0.255:
            ang = math.atan2(v.co.y, v.co.x)
            v.co.z += 0.012 * math.sin(ang * 5.0) + 0.006 * math.sin(ang * 9.0)

    # copa
    crown = lathe("crown", [
        (0.165, 0.880), (0.172, 0.900), (0.170, 0.945), (0.160, 0.975),
        (0.140, 0.995), (0.100, 1.005), (0.040, 1.010), (0.000, 1.011),
    ], segments=40, mats=["straw_dark", "straw", "straw", "straw_light",
                          "straw_light", "straw", "straw"])

    hat = join([brim, crown], "hat_mesh")
    hinge("hat", (0, 0, HINGE_Z), [hat], root)


# --------------------------------------------------------------------------- #
# escena + render
# --------------------------------------------------------------------------- #
def setup_render(path, cam_pos=(0.55, -2.75, 0.78), look_at=(0.0, 0.0, 0.52)):
    scene = bpy.context.scene
    # Cycles CPU: confiable en headless (Workbench/EEVEE necesitan contexto GL)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = False

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = None
    for node in world.node_tree.nodes:
        if node.type == "BACKGROUND":
            bg = node
            break
    if bg is not None:
        bg.inputs[0].default_value = (0.38, 0.52, 0.68, 1)
        bg.inputs[1].default_value = 0.55
    scene.world = world

    bpy.ops.object.light_add(type="SUN", location=(2, -3, 5))
    sun = bpy.context.object
    sun.data.energy = 2.2
    sun.rotation_euler = (math.radians(55), 0, math.radians(35))

    bpy.ops.object.camera_add(location=cam_pos)
    cam = bpy.context.object
    direction = Vector(look_at) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 70
    scene.camera = cam

    # piso
    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.002))
    floor = bpy.context.object
    floor.data.materials.append(material("straw_light"))

    # color fiel: sin el mapeo AgX los colores no se lavan
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    print("render ->", path, os.path.exists(path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="/tmp/kid")
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])

    clear()
    root = bpy.data.objects.new("kid", None)
    bpy.context.scene.collection.objects.link(root)

    build_legs(root)
    build_torso(root)
    build_arms(root)
    build_head(root)
    build_hat(root)

    # Blender +Y -> glTF -Z; el juego espera que mire a +Z => giro 180°
    root.rotation_euler = (0.0, 0.0, math.pi)

    os.makedirs(args.out, exist_ok=True)
    glb = os.path.join(args.out, "kid.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB",
                              use_selection=False, export_apply=True)
    print("GLB ->", glb)

    if args.render:
        setup_render(os.path.join(args.out, "kid.png"))


import sys  # noqa: E402

if __name__ == "__main__":
    main()
