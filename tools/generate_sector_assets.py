"""Original sector art. Run with Blender --background --python tools/generate_sector_assets.py.

No downloaded artwork is used. GLBs are committed so players/CI do not need Blender.
The concept-guided station exports a shared manifest of simple physics envelopes.
"""
from pathlib import Path
import math
import random

import bpy
import numpy as np
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "sector"
OUT.mkdir(parents=True, exist_ok=True)


def texture(name, pixels):
    h, w, _ = pixels.shape
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(pixels.astype(np.float32).ravel())
    img.filepath_raw = str(OUT / (name + ".png"))
    img.file_format = "PNG"
    img.save()
    return img


def stone_textures():
    rng = np.random.default_rng(7301)
    n = 512
    field = np.zeros((n, n), dtype=float)
    # Periodic bilinear noise makes seamless triplanar textures.
    for cells, strength in [(4, .28), (8, .20), (16, .13), (32, .08), (64, .05)]:
        grid = rng.random((cells, cells))
        coord = np.arange(n) * cells / n
        cell = coord.astype(int)
        frac = coord - cell
        frac = frac * frac * (3 - 2 * frac)
        a = grid[cell[:, None], cell[None, :]]
        b = grid[cell[:, None], (cell[None, :] + 1) % cells]
        c = grid[(cell[:, None] + 1) % cells, cell[None, :]]
        d = grid[(cell[:, None] + 1) % cells, (cell[None, :] + 1) % cells]
        field += ((a * (1-frac[None, :]) + b * frac[None, :]) * (1-frac[:, None])
                  + (c * (1-frac[None, :]) + d * frac[None, :]) * frac[:, None]) * strength
    field += rng.random((n, n)) * .07
    cracks = np.maximum(0, .026 - np.abs(field - .43)) / .026
    brightness = np.clip(.21 + field * .65 - cracks * .16, 0, 1)
    rgba = np.ones((n, n, 4))
    rgba[:, :, :3] = brightness[:, :, None] * np.array([.78, .73, .67])
    texture("rock-albedo", rgba)
    height = field - cracks * .05
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 3
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 3
    normal = np.stack((-dx, -dy, np.ones_like(dx)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1)[:, :, None]
    rgba[:, :, :3] = normal * .5 + .5
    texture("rock-normal", rgba)


def metal_texture():
    rng = np.random.default_rng(81)
    n = 512
    y, x = np.indices((n, n))
    grain = rng.random((n, n)) * .06
    seam = ((x % 128 < 3) | (y % 256 < 3))
    screws = np.zeros((n, n), dtype=bool)
    for px in range(10, n, 128):
        for py in range(10, n, 256):
            screws |= ((x-px)**2+(y-py)**2 < 8)
            screws |= ((x-(px+108))**2+(y-(py+236))**2 < 8)
    shade = .64 + grain + np.sin(y * .31) * .015
    shade[seam] = .23
    shade[screws] = .30
    rgba = np.ones((n, n, 4))
    rgba[:, :, :3] = shade[:, :, None]
    return texture("station-panels", rgba)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def material(name, color, metallic=0, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = .64
    if emission:
        p.inputs["Emission Color"].default_value = (*color, 1)
        p.inputs["Emission Strength"].default_value = emission
    return mat


def export(name):
    # One mesh per material keeps the detailed station cheap to draw.
    objects = list(bpy.context.scene.objects)
    groups = {}
    for obj in objects:
        if obj.type == "MESH":
            groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for group in groups.values():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in group:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.join()
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + ".glb")), export_format="GLB",
                              export_yup=True, export_cameras=False, export_lights=False)


def box(name, position, size, mat, bevel=.08):
    # Author in Godot coordinates, converting Y-up to Blender Z-up.
    x, y, z = position
    sx, sy, sz = size
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, -z, y))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (sx, sz, sy)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Machined edges", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.modifiers.new("Weighted panel normals", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=obj.modifiers[-1].name)
    return obj


def station():
    # The concept study is the single source of the runtime station and collision.
    import sys
    sys.path.insert(0, str(ROOT / 'tools'))
    from build_station import build
    build()


def rocks():
    mat = material("Rock", (.34, .31, .27))
    for variant in range(3):
        clear()
        rng = random.Random(7301 + variant)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4, radius=1)
        obj = bpy.context.object
        obj.name = "Asteroid"
        craters = [(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized(),
                    rng.uniform(.16, .40)) for _ in range(14)]
        for vertex in obj.data.vertices:
            d = vertex.co.normalized()
            rough = noise.fractal(d * 3.3 + Vector((variant*7, 2, 8)), 1, 2, 4)
            r = .80 + rough * .13
            for center, width in craters:
                dist = (d - center).length / width
                r -= .08 * math.exp(-dist**4 * 3)
                r += .028 * math.exp(-((dist-.95)/.16)**2)
            vertex.co = Vector((d.x, d.y*.88, d.z*.82)) * r
        maximum = max(v.co.length for v in obj.data.vertices)
        for v in obj.data.vertices:
            v.co *= .98 / maximum
        for p in obj.data.polygons:
            p.use_smooth = True
        obj.data.materials.append(mat)
        export("asteroid-%d" % variant)


def derelict():
    clear()
    hull = material("Derelict hull", (.13, .17, .21), .45)
    metal = material("Exposed frame", (.30, .31, .29), .6)
    dark = material("Scorched machinery", (.035, .045, .05), .2)
    ember = material("Emergency lights", (.7, .24, .06), emission=.7)
    box("Freighter keel", (0, -4, 4), (11, 6, 80), hull)
    for z in range(-30, 35, 12):
        box("Cargo rib", (0, 3, z), (22, 3, 2), metal)
        for side in (-1, 1):
            box("Cargo strut", (side*10, 0, z), (2, 15, 2), metal)
            # The upper forward hull is stripped back to its supporting frame.
            if z > -10:
                box("Cargo plating", (side*11, 0, z+5), (1, 15, 9), hull)
    box("Aft bulkhead", (0, 1, 36), (23, 18, 6), hull, .3)
    bridge = box("Damaged bridge", (0, 12, 25), (14, 8, 15), hull, .2)
    bridge.rotation_euler.y = .12
    box("Unpowered bridge glazing", (0, 13, 16.8), (10, 3, .3), dark)
    for side in (-1, 1):
        box("Drive pylon", (side*15, -3, 22), (12, 4, 6), metal)
        box("Drive housing", (side*19, -3, 24), (9, 11, 25), hull, .3)
        box("Dead drive nozzle", (side*19, -3, 37), (7, 9, 1), dark)
        wing = box("Broken radiator", (side*27, 0, 3), (28, 1, 16), metal)
        wing.rotation_euler.y = side * .28
        for z in range(-3, 10, 3):
            box("Radiator fins", (side*28, .6, z), (21, .4, .6), dark, 0)
    for x in (-7, 7):
        box("Sparse emergency lamp", (x, 9.3, 36), (.7, .2, .8), ember, 0)
    export("derelict")


stone_textures()
rocks()
station()
derelict()
print("Original sector assets generated in", OUT)
