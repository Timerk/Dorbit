"""Export PR 14's saved studies without modifying the review .blend files.

Run Blender in background mode with --python tools/export_ships.py.
One mesh per hull, material surfaces, reduced bevel tessellation, no studio or
references. glTF converts Z-up to Y-up; rotate the Blender -Y nose to +Y first
so the imported Godot nose points -Z. All hulls fit a 7 m bounding diameter.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from ship_surface_atlas import SurfaceAtlas, deduplicate_textures
REVIEW = ROOT / "art/ship-review"
OUTPUT = ROOT / "assets/ships"
OUTPUT.mkdir(parents=True, exist_ok=True)
(ROOT / "assets/ui/ships").mkdir(parents=True, exist_ok=True)
requested = set(sys.argv[sys.argv.index('--') + 1:]) if '--' in sys.argv else set()
sources = sorted((REVIEW / 'models').glob('*.blend'))
unknown = requested - {source.stem for source in sources}
if unknown:
    raise ValueError('Unknown ships: ' + ', '.join(sorted(unknown)))
report_path = OUTPUT / 'export-stats.json'
report = json.loads(report_path.read_text()) if requested and report_path.exists() else {}
for source in sources:
    if requested and source.stem not in requested:
        continue
    bpy.ops.wm.open_mainfile(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        obj.hide_set(False)
        for modifier in obj.modifiers:
            if modifier.type == "BEVEL":
                modifier.segments = 1
    graph = bpy.context.evaluated_depsgraph_get()
    atlas = SurfaceAtlas(meshes, REVIEW / 'materials' / source.stem)
    vertices, faces, materials, indices, smooth, normals = [], [], [], [], [], []
    uvs = []
    material_names = {}
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        uvs.extend(atlas.coordinates(obj, mesh))
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in mesh.vertices)
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        normals.extend(Matrix.Rotation(math.pi, 3, "Z") @ (normal_matrix @ normal.vector).normalized()
                       for normal in mesh.corner_normals)
        mapping = {}
        for index, material in enumerate(mesh.materials):
            if material.name not in material_names:
                material_names[material.name] = len(materials)
                materials.append(material)
            mapping[index] = material_names[material.name]
        for polygon in mesh.polygons:
            faces.append([offset + index for index in polygon.vertices])
            indices.append(mapping[polygon.material_index])
            smooth.append(polygon.use_smooth)
        evaluated.to_mesh_clear()
    low = Vector(tuple(min(vertex[axis] for vertex in vertices) for axis in range(3)))
    high = Vector(tuple(max(vertex[axis] for vertex in vertices) for axis in range(3)))
    center = (low + high) / 2
    scale = 7 / (high - low).length
    rotation = Matrix.Rotation(math.pi, 3, "Z")
    data = bpy.data.meshes.new(source.stem)
    data.from_pydata([rotation @ ((vertex - center) * scale) for vertex in vertices], [], faces)
    data.update()
    for material in materials:
        # Replace studio-only procedural detail with portable surface maps.
        atlas.apply_material(material)
        data.materials.append(material)
    for polygon, index, is_smooth in zip(data.polygons, indices, smooth):
        polygon.material_index = index
        polygon.use_smooth = is_smooth
    data.normals_split_custom_set(normals)
    uv_layer = data.uv_layers.new(name='Fitted component atlas')
    assert len(uvs) == len(data.loops)
    for loop, uv in zip(uv_layer.data, uvs):
        loop.uv = uv
    bpy.ops.object.select_all(action="DESELECT")
    hull = bpy.data.objects.new(source.stem, data)
    bpy.context.scene.collection.objects.link(hull)
    hull.select_set(True)
    bpy.context.view_layer.objects.active = hull
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{source.stem}.glb"),
        export_format="GLB", use_selection=True, export_yup=True,
        export_cameras=False, export_lights=False, export_animations=False)
    deduplicate_textures(OUTPUT / f'{source.stem}.glb')
    # Thumbnails use the same Godot finish as flight; rebuild with
    # tools/render_ship_preview.gd after importing its new GLB.
    data.calc_loop_triangles()
    report[source.stem] = {"triangles": len(data.loop_triangles), "materials": len(materials),
                          "bytes": (OUTPUT / f"{source.stem}.glb").stat().st_size}
    print("EXPORTED", source.stem, report[source.stem], flush=True)
report_path.write_text(json.dumps(report, indent=2) + "\n")
