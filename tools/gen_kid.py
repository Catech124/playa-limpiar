"""
Generador del personaje (Blender headless) — chico de playa.

Proporciones tomadas del feedback de Claude sobre el render (torso corto y
ancho, cabeza baja, ala grande con pitch para que la cámara alta no tape los
ojos, brazos con codo y guantes que rompen la silueta).

Uso:
    blender --background --python tools/gen_kid.py -- --out /tmp/kid --render --vista tres

Salidas: <out>/kid.glb (con bisagras arm_l/arm_r/leg_l/leg_r/head/hat) y
<out>/kid_<vista>.png.  KID_SUELO=1 agrega piso y sombra para las capturas.
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------- #
# paleta (sRGB; se convierte a lineal al asignar)
# --------------------------------------------------------------------------- #
PALETTE = {
    "skin": (0.90, 0.65, 0.45),        # #E5A673
    "skin_dark": (0.84, 0.57, 0.40),
    "white": (0.96, 0.95, 0.92),       # #F6F2EA
    "stripe": (0.31, 0.49, 0.73),      # #4F7DBB
    "shorts": (0.12, 0.17, 0.37),      # #1E2B5E
    "straw": (0.82, 0.66, 0.40),       # #D2A866
    "straw_light": (0.88, 0.74, 0.48),
    "straw_dark": (0.68, 0.53, 0.30),
    "band": (0.93, 0.89, 0.80),        # #EDE3CC
    "hair": (0.42, 0.23, 0.12),        # #6B3B1F
    "hair_dark": (0.33, 0.17, 0.08),
    "dark": (0.10, 0.08, 0.06),        # #1A1410
    "eyewhite": (0.98, 0.97, 0.95),
    "mouth": (0.44, 0.19, 0.16),
    "blush": (0.91, 0.54, 0.45),       # #E88A74
    "sandal": (0.94, 0.90, 0.82),      # suela #EFE6D2
    "strap": (0.31, 0.49, 0.73),
    "glove": (0.66, 0.44, 0.23),       # #A8713A
}

MATS = {}


def srgb_to_linear(c):
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
    bsdf.inputs["Roughness"].default_value = 0.7
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
def lathe(name, profile, segments=40, mats=None, smooth=True):
    """Superficie de revolución. `profile` = [(radio, z), ...] de abajo a arriba."""
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
        a_ring, b_ring = rings[k], rings[k + 1]
        for i in range(segments):
            j = (i + 1) % segments
            f = bm.faces.new((a_ring[i], a_ring[j], b_ring[j], b_ring[i]))
            f.material_index = k if mats else 0
            f.smooth = smooth
    bm.to_mesh(me)
    bm.free()
    for m in (mats or ["skin"]):
        me.materials.append(material(m))
    return ob


def sphere(name, radius, loc, mat, scale=(1, 1, 1), segments=32, rings=16, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=radius, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    ob.data.materials.append(material(mat))
    if smooth:
        bpy.ops.object.shade_smooth()
    return ob


def cylinder(name, r1, r2, height, loc, mat, rot=(0, 0, 0), verts=32, smooth=True):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2,
                                    depth=height, location=loc, rotation=rot)
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(material(mat))
    if smooth:
        bpy.ops.object.shade_smooth()
    return ob


def limb(name, p0, p1, r0, r1, mat, verts=16):
    """Cilindro cónico que une dos puntos (para brazos y piernas sin huecos)."""
    a, b = Vector(p0), Vector(p1)
    d = b - a
    h = max(d.length, 0.001)
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1,
                                    depth=h, location=(a + b) * 0.5)
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
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
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = Vector(pivot)
    e.empty_display_size = 0.04
    if parent is not None:
        e.parent = parent
    for o in objs:
        o.parent = e
        o.matrix_parent_inverse = Matrix.Translation(-Vector(pivot))
    return e


# --------------------------------------------------------------------------- #
# layout (suela en Z=0; el personaje mira a +Y en el build, se gira 180° al exportar)
# --------------------------------------------------------------------------- #
HEAD_R = 0.160
HEAD_Z = 0.590            # centro del cráneo (mentón 0.43)
HINGE_Z = 0.455           # bisagra del cuello
SHOULDER_X = 0.190
SHOULDER_Z = 0.385
ARM_SPLAY = 30.0          # apertura del brazo superior
ELBOW = (0.235, 0.0, 0.307)
GLOVE_C = (0.255, 0.140, 0.240)   # adelante del torso (Y+ = frente)
HAT_Z = 0.690
HAT_PITCH = 14.0          # ala delantera arriba (la cámara mira desde arriba)
HAT_ROLL = 5.0


def build_legs(root):
    for side, tag in ((-1, "l"), (1, "r")):
        parts = []
        x = side * 0.080
        parts.append(cylinder(f"leg_{tag}", 0.040, 0.044, 0.10, (x, 0, 0.095), "skin"))
        # pie de piel + suela ovalada + tira
        parts.append(sphere(f"foot_{tag}", 0.055, (x, 0.035, 0.048), "skin",
                            scale=(0.80, 1.35, 0.55), segments=18, rings=10))
        parts.append(sphere(f"sole_{tag}", 0.075, (x, 0.030, 0.012), "sandal",
                            scale=(0.62, 1.10, 0.20), segments=20, rings=10))
        for i in (-1, 1):
            parts.append(cube(f"strap_{tag}{i}", (0.020, 0.085, 0.016),
                              (x + i * 0.030, 0.060, 0.040), "strap",
                              rot=(0, 0, math.radians(i * 28)), bevel=0.006))
        leg = join(parts, f"leg_{tag}_mesh")
        hinge(f"leg_{tag}", (x, 0, 0.130), [leg], root)


def build_torso(root):
    # short: leve campana
    shorts = lathe("shorts", [
        (0.185, 0.130), (0.192, 0.170), (0.195, 0.230),
    ], mats=["shorts", "shorts"])
    shorts.parent = root

    # camiseta: cintura 0.18 → pecho 0.19 → hombro 0.16, elíptica (Y ×0.84)
    bands = 7
    z0, z1 = 0.240, 0.440
    profile = []
    for i in range(bands + 1):
        t = i / bands
        r = 0.172 + 0.026 * math.sin(math.pi * min(1.0, t * 1.6)) - 0.018 * max(0.0, t - 0.6) / 0.4
        profile.append((r, z0 + (z1 - z0) * t))
    mats = ["white" if i % 2 == 0 else "stripe" for i in range(bands)]
    shirt = lathe("shirt", profile, segments=40, mats=mats)
    shirt.scale = (1.0, 0.84, 1.0)
    shirt.parent = root

    collar = torus("collar", 0.150, 0.012, (0, 0, 0.438), "white")
    collar.scale = (1.0, 0.84, 1.0)
    collar.parent = root

    neck = cylinder("neck", 0.062, 0.070, 0.06, (0, 0, 0.452), "skin")
    neck.parent = root


def build_arms(root):
    for side, tag in ((-1, "l"), (1, "r")):
        parts = []
        drop = 0.025 if side < 0 else 0.0
        sx = side * SHOULDER_X
        sz = SHOULDER_Z - drop
        elbow = (side * 0.225, 0.010, 0.300 - drop)
        glove = (side * 0.245, 0.150, 0.250 - drop)

        parts.append(sphere(f"shoulder_{tag}", 0.062, (sx, 0, sz), "stripe",
                            scale=(1.05, 1.0, 1.0)))
        # manga corta
        parts.append(limb(f"sleeve_{tag}", (sx, 0, sz - 0.010),
                          (side * 0.205, 0.004, 0.330 - drop), 0.056, 0.048, "stripe"))
        parts.append(torus(f"cuff_{tag}", 0.050, 0.009,
                           (side * 0.205, 0.004, 0.330 - drop), "white",
                           rot=(math.radians(90), 0, 0)))
        # brazo y antebrazo de piel
        parts.append(limb(f"upper_{tag}", (side * 0.205, 0.004, 0.330 - drop),
                          elbow, 0.036, 0.032, "skin"))
        parts.append(limb(f"forearm_{tag}", elbow, glove, 0.032, 0.030, "skin"))
        parts.append(sphere(f"glove_{tag}", 0.060, glove, "glove",
                            scale=(0.95, 1.05, 1.20), segments=20, rings=12))
        parts.append(sphere(f"thumb_{tag}", 0.026, (glove[0] - side * 0.018,
                                                    glove[1] - 0.035, glove[2] + 0.015), "glove"))
        arm = join(parts, f"arm_{tag}_mesh")
        hinge(f"arm_{tag}", (sx, 0, sz), [arm], root)


def build_head(root):
    parts = []
    parts.append(sphere("skull", HEAD_R, (0, 0, HEAD_Z), "skin",
                        scale=(1.05, 0.98, 1.0), segments=40, rings=24))
    for side in (-1, 1):
        parts.append(sphere(f"ear_{side}", 0.042, (side * HEAD_R * 0.97, 0.005, HEAD_Z - 0.02),
                            "skin_dark", scale=(0.45, 0.75, 1.0), segments=16, rings=10))

    # pelo: masa + rizos
    parts.append(sphere("hair_mass", HEAD_R * 1.04, (0, -0.010, HEAD_Z + 0.020), "hair",
                        scale=(1.05, 1.0, 0.95), segments=32, rings=16))
    curls = [
        (0.000, 0.020, 0.115, 0.070), (-0.095, 0.010, 0.108, 0.066),
        (0.095, 0.010, 0.108, 0.066), (-0.150, 0.000, 0.070, 0.058),
        (0.150, 0.000, 0.070, 0.058), (-0.060, 0.115, 0.090, 0.058),
        (0.060, 0.115, 0.090, 0.058), (0.000, -0.130, 0.075, 0.066),
        (-0.100, -0.115, 0.068, 0.058), (0.100, -0.115, 0.068, 0.058),
    ]
    for i, (x, y, z, r) in enumerate(curls):
        parts.append(sphere(f"curl_{i}", r, (x, y, HEAD_Z + z), "hair",
                            scale=(1.0, 0.95, 0.95), segments=16, rings=10))

    # ojos: esclerótica 0.036, pupila 0.019, brillo 0.007 (medidas de Claude)
    eye_z = HEAD_Z - 0.050
    for side in (-1, 1):
        ex = side * 0.075
        ey = 0.130
        parts.append(sphere(f"eye_{side}", 0.040, (ex, ey, eye_z), "eyewhite",
                            scale=(1.0, 0.45, 1.05), segments=18, rings=10))
        parts.append(sphere(f"pupil_{side}", 0.021, (ex, ey + 0.016, eye_z), "dark",
                            scale=(1.0, 0.40, 1.05), segments=14, rings=8))
        parts.append(sphere(f"glint_{side}", 0.008, (ex - 0.010, ey + 0.024, eye_z + 0.012),
                            "eyewhite", segments=10, rings=6))
        parts.append(cube(f"brow_{side}", (0.070, 0.026, 0.022), (ex, ey - 0.006, eye_z + 0.062),
                          "hair_dark", rot=(0, math.radians(side * 8), 0), bevel=0.007))
        parts.append(sphere(f"cheek_{side}", 0.024, (side * 0.105, ey - 0.050, eye_z - 0.045),
                            "blush", scale=(1.0, 0.45, 0.70), segments=14, rings=9))

    parts.append(sphere("nose", 0.024, (0, ey - 0.010, eye_z - 0.040), "skin_dark",
                        scale=(1.0, 0.85, 0.80), segments=14, rings=9))
    parts.append(cube("mouth", (0.040, 0.012, 0.011), (0, ey - 0.020, eye_z - 0.080),
                      "mouth", bevel=0.004))
    for i in (-1, 1):
        parts.append(cube(f"mouth_corner_{i}", (0.018, 0.011, 0.011),
                          (i * 0.026, ey - 0.020, eye_z - 0.074), "mouth",
                          rot=(0, 0, math.radians(-i * 26)), bevel=0.004))

    head = join(parts, "head_mesh")
    hinge("head", (0, 0, HINGE_Z), [head], root)


def build_hat(root):
    # ala: radio 0.24 → 0.35 con caída de 0.025, grosor 0.03
    brim = lathe("brim", [
        (0.230, 0.0000), (0.290, -0.012), (0.330, -0.020), (0.340, -0.024),
        (0.340, -0.052), (0.310, -0.049), (0.250, -0.042), (0.230, -0.030),
    ], segments=56, mats=["straw", "straw_light", "straw_dark", "straw_dark",
                          "straw_dark", "straw_light", "straw"])
    # borde redondeado
    rim = torus("rim", 0.335, 0.013, (0, 0, -0.038), "straw_dark")
    # copa: media elipsoide
    crown = sphere("crown", 0.185, (0, 0, 0.012), "straw_light",
                   scale=(1.0, 0.98, 0.55), segments=32, rings=16)
    band = torus("band", 0.186, 0.012, (0, 0, -0.012), "band")
    band.scale = (1.0, 0.98, 1.0)
    band.scale = (1.0, 0.92, 1.0)

    hat = join([brim, rim, crown, band], "hat_mesh")
    # las piezas se arman alrededor del origen: se suben al pivote del sombrero
    hat.location = (0, 0, HAT_Z)
    hat.rotation_euler = (math.radians(HAT_PITCH), 0.0, math.radians(HAT_ROLL))
    hinge("hat", (0, 0, HAT_Z), [hat], root)


# --------------------------------------------------------------------------- #
# render
# --------------------------------------------------------------------------- #
VISTAS = {
    "frente": (0.0, -2.60, 0.55),
    "tres": (1.75, -1.95, 0.62),
    "lado": (2.60, 0.0, 0.55),
    "atras": (0.0, 2.60, 0.55),
}


def setup_render(path, cam_pos=(0.55, -2.75, 0.78), look_at=(0.0, 0.0, 0.45)):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.film_transparent = True

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    for node in world.node_tree.nodes:
        if node.type == "BACKGROUND":
            node.inputs[0].default_value = (0.38, 0.52, 0.68, 1)
            node.inputs[1].default_value = 0.55
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

    if os.environ.get("KID_SUELO", "0") == "1":
        bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.002))
        bpy.context.object.data.materials.append(material("straw_light"))

    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("render ->", path, os.path.exists(path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="/tmp/kid")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--vista", default="tres")
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
        setup_render(os.path.join(args.out, f"kid_{args.vista}.png"),
                     cam_pos=VISTAS.get(args.vista, VISTAS["tres"]))


if __name__ == "__main__":
    main()
