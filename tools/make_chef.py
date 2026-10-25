"""
Genera el personaje low-poly (estilo Overcooked) y lo exporta como asset GLB.

    xvfb-run -a blender --background --python tools/make_chef.py

Salida:
    assets/chef.glb            modelo para el juego
    docs/modelo-preview.png    hoja de vistas (Cycles, 3 rotaciones + primer plano)

Proporciones: cabeza grande, cuerpo chico y sombrero ancho, para que se lea
desde la cámara fija en ángulo del juego (altura total ~1.15 unidades).
"""

import math
import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLB = os.path.join(ROOT, "assets", "chef.glb")
PREVIEW = os.path.join(ROOT, "docs", "modelo-preview.png")

# --------------------------------------------------------------------------- #
# materiales
# --------------------------------------------------------------------------- #
def srgb(hex_str):
    """Blender/glTF trabajan en lineal: el hex es sRGB y hay que convertirlo."""
    h = hex_str.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


MATERIALS = {
    "skin":   (srgb("#E9B78E"), 0.72),
    "shirt":  (srgb("#F2B544"), 0.85),   # lo pisa el color de cada jugador
    "shorts": (srgb("#3E4C60"), 0.85),
    "hat":    (srgb("#D9B36A"), 0.78),
    "band":   (srgb("#A9713F"), 0.85),
    "gloves": (srgb("#EDEFEC"), 0.90),
    "boots":  (srgb("#2A313A"), 0.68),
    "eyes":   (srgb("#1A1D22"), 0.55),
    "mouth":  (srgb("#B4695C"), 0.80),
}

_mats = {}


def mat(name):
    if name in _mats:
        return _mats[name]
    color, rough = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    # Blender 5 renombra nodos: se busca por tipo, no por nombre
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = m.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in m.node_tree.nodes if n.type == "OUTPUT_MATERIAL"), None)
        if out is not None:
            m.node_tree.links.new(bsdf.outputs[0], out.inputs["Surface"])
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = color
    _mats[name] = m
    return m


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


# --------------------------------------------------------------------------- #
# primitivas
# --------------------------------------------------------------------------- #
PARTS = []


def add(obj, material, smooth=True):
    obj.data.materials.append(mat(material))
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    PARTS.append(obj)
    return obj


def sphere(name, radius, location, material, scale=(1, 1, 1), segments=18, rings=10, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=radius, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    return add(obj, material, smooth)


def cylinder(name, radius, depth, location, material, rotation=(0, 0, 0),
             vertices=14, smooth=True, top=None):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    if top is not None:                       # cono truncado
        for v in obj.data.vertices:
            if v.co.z > 0:
                v.co.x *= top / radius
                v.co.y *= top / radius
    return add(obj, material, smooth)


def box(name, size, location, material, rotation=(0, 0, 0), bevel=0.012, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    add(obj, material, smooth)
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        with bpy.context.temp_override(object=obj):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


# --------------------------------------------------------------------------- #
# personaje  (Z arriba; el frente mira a -Y, que en glTF pasa a -Z)
# --------------------------------------------------------------------------- #
def build_chef():
    # --- piernas y botas ---------------------------------------------------
    for side in (-1, 1):
        cylinder(f"leg_{side}", 0.064, 0.19, (side * 0.088, 0, 0.195), "skin", vertices=10)
        box(f"boot_{side}", (0.19, 0.29, 0.15), (side * 0.088, -0.032, 0.075), "boots", bevel=0.032)

    # --- cadera / pantalón corto ------------------------------------------
    cylinder("shorts", 0.172, 0.17, (0, 0, 0.30), "shorts", vertices=16)
    sphere("hips", 0.170, (0, 0, 0.265), "shorts", scale=(1, 0.95, 0.7), segments=16, rings=8)

    # --- torso: barril ancho y bajo ---------------------------------------
    body = cylinder("torso", 0.186, 0.245, (0, 0, 0.505), "shirt", vertices=18, top=0.205)
    body.scale = (1.05, 0.90, 1.0)
    sphere("shoulders", 0.205, (0, 0, 0.615), "shirt", scale=(1.05, 0.90, 0.60), segments=18, rings=8)
    sphere("belly", 0.168, (0, 0, 0.408), "shirt", scale=(1.04, 0.94, 0.55), segments=16, rings=8)

    # --- brazos y guantes --------------------------------------------------
    for side in (-1, 1):
        # hombro (0.20, 0.57) -> mano (0.31, 0.40): largo 0.20, inclinado 34°
        cylinder(
            f"arm_{side}", 0.056, 0.20,
            (side * 0.255, -0.006, 0.485), "skin",
            rotation=(0, -side * math.radians(34), 0), vertices=10,
        )
        sphere(f"hand_{side}", 0.073, (side * 0.305, -0.008, 0.398), "gloves", segments=12, rings=8)

    # --- cabeza ------------------------------------------------------------
    sphere("head", 0.255, (0, 0, 0.825), "skin", scale=(1.02, 0.96, 0.99), segments=22, rings=14)
    sphere("nose", 0.038, (0, -0.245, 0.785), "skin", scale=(1, 1.2, 0.9), segments=10, rings=6)

    for side in (-1, 1):
        sphere(f"eye_{side}", 0.036, (side * 0.088, -0.222, 0.845), "eyes", segments=10, rings=8)
    # boca: barra fina curvada hacia arriba (sonrisa simple)
    box("mouth", (0.085, 0.018, 0.02), (0, -0.238, 0.733), "mouth", bevel=0.009, smooth=True)

    # --- sombrero de sol (ala más chica: no debe tapar la cara) -----------
    cylinder("hat_brim", 0.262, 0.026, (0, 0, 1.005), "hat", vertices=22)
    cylinder("hat_band", 0.196, 0.055, (0, 0, 1.024), "band", vertices=20)
    cylinder("hat_crown", 0.19, 0.10, (0, 0, 1.08), "hat", vertices=20, top=0.158)
    sphere("hat_top", 0.158, (0, 0, 1.128), "hat", scale=(1, 1, 0.5), segments=18, rings=8)

    # --- unir todo en un solo objeto con varias surfaces -------------------
    bpy.ops.object.select_all(action="DESELECT")
    for obj in PARTS:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    chef = bpy.context.object
    chef.name = "Chef"
    chef.location = (0, 0, 0)
    bpy.ops.object.shade_smooth()
    return chef


# --------------------------------------------------------------------------- #
# preview + export
# --------------------------------------------------------------------------- #
def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1260
    scene.render.resolution_y = 700
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.80, 0.82, 0.86, 1)
    bg.inputs[1].default_value = 0.35
    scene.world = world

    # suelo para que haya contacto
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    floor = bpy.context.object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    bsdf = next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.80, 0.80, 0.82, 1)
    bsdf.inputs["Roughness"].default_value = 0.95
    floor.data.materials.append(fm)

    # punto al que miran luces y cámara
    aim = bpy.data.objects.new("aim", None)
    scene.collection.objects.link(aim)
    aim.location = (0, 0, 0.60)

    def track(obj):
        con = obj.constraints.new("TRACK_TO")
        con.target = aim
        con.track_axis = "TRACK_NEGATIVE_Z"
        con.up_axis = "UP_Y"

    bpy.ops.object.light_add(type="AREA", location=(2.6, -2.8, 3.4))
    key = bpy.context.object
    key.data.energy = 260
    key.data.size = 4.0
    track(key)

    bpy.ops.object.light_add(type="AREA", location=(-3.0, -2.0, 1.6))
    fill = bpy.context.object
    fill.data.energy = 70
    fill.data.size = 5.0
    track(fill)

    bpy.ops.object.camera_add(location=(0.0, -8.2, 1.95))
    cam = bpy.context.object
    cam.data.lens = 80
    track(cam)
    scene.camera = cam


def add_turnaround(chef):
    """Tres copias rotadas al lado para leer la silueta de un vistazo."""
    scene = bpy.context.scene
    spacing = 1.05
    for i, angle in enumerate((0, 120, 240)):
        dup = chef.copy()
        dup.data = chef.data.copy()
        scene.collection.objects.link(dup)
        dup.location = ((i - 1) * spacing, 0, 0)
        dup.rotation_euler = (0, 0, math.radians(angle))


def main():
    clear_scene()
    chef = build_chef()

    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)

    bpy.ops.export_scene.gltf(
        filepath=GLB,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
    )

    tris = sum(len(p.vertices) - 2 for p in chef.data.polygons)
    add_turnaround(chef)
    setup_render()
    bpy.context.scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)

    print(f"OK glb={GLB} tris={tris} preview={PREVIEW}")


main()
