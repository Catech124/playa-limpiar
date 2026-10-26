"""Renderiza las vistas de control del personaje (4 ortográficas + 3/4).

Se usa para comparar contra la lámina de referencia con los mismos encuadres.

    xvfb-run -a blender --background --python tools/render_views.py -- \
        --glb assets/chef.glb --out /tmp/vistas

Salidas: frente.png, derecha.png, atras.png, izquierda.png, tres_cuartos.png,
y lamina.png (las cuatro juntas).
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", default="assets/chef.glb")
    ap.add_argument("--out", default="/tmp/vistas")
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    clear()
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(args.glb))

    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"          # color real, sin sombras
    sc.display.shading.color_type = "MATERIAL"
    sc.display.render_aa = "8"
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.color = (0.62, 0.64, 0.68)
    sc.world = w
    sc.render.resolution_x = 420
    sc.render.resolution_y = 640

    cam_data = bpy.data.cameras.new("c")
    cam = bpy.data.objects.new("c", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.62

    aim = Vector((0, 0, 0.66))
    views = {
        "frente": Vector((0, -5, 0.66)),
        "derecha": Vector((5, 0, 0.66)),
        "atras": Vector((0, 5, 0.66)),
        "izquierda": Vector((-5, 0, 0.66)),
    }
    for name, pos in views.items():
        cam.location = pos
        cam.rotation_euler = (aim - pos).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(args.out, f"{name}.png")
        bpy.ops.render.render(write_still=True)

    # 3/4 en perspectiva, como se ve en el visor y en el juego
    cam_data.type = "PERSP"
    cam_data.lens = 70
    pos = Vector((1.9, -2.9, 1.45))
    cam.location = pos
    cam.rotation_euler = (Vector((0, 0, 0.62)) - pos).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x = 520
    sc.render.resolution_y = 640
    sc.render.filepath = os.path.join(args.out, "tres_cuartos.png")
    bpy.ops.render.render(write_still=True)

    print(f"OK vistas -> {args.out}")


if __name__ == "__main__":
    main()
