"""Export PR 14's saved studies without modifying the review .blend files.

Run Blender in background mode with --python tools/export_ships.py.
One mesh per hull, material surfaces, reduced bevel tessellation, no studio or
references. glTF converts Z-up to Y-up; rotate the Blender -Y nose to +Y first
so the imported Godot nose points -Z. All hulls fit a 7 m bounding diameter.
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "art/ship-review"
OUTPUT = ROOT / "assets/ships"
OUTPUT.mkdir(parents=True, exist_ok=True)
(ROOT / "assets/ui/ships").mkdir(parents=True, exist_ok=True)
report = {}
for source in sorted((REVIEW / "models").glob("*.blend")):
    bpy.ops.wm.open_mainfile(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    for obj in meshes:
        obj.hide_set(False)
        for modifier in obj.modifiers:
            if modifier.type == "BEVEL":
                modifier.segments = 1
    graph = bpy.context.evaluated_depsgraph_get()
    vertices, faces, materials, indices, smooth, normals = [], [], [], [], [], []
    material_names = {}
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
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
        # Procedural grain is a studio detail unsupported by glTF. Preserve PBR
        # paint, metal, roughness and emission; remove the unsupported bump link.
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            for link in list(bsdf.inputs["Normal"].links):
                material.node_tree.links.remove(link)
        data.materials.append(material)
    for polygon, index, is_smooth in zip(data.polygons, indices, smooth):
        polygon.material_index = index
        polygon.use_smooth = is_smooth
    data.normals_split_custom_set(normals)
    bpy.ops.object.select_all(action="DESELECT")
    hull = bpy.data.objects.new(source.stem, data)
    bpy.context.scene.collection.objects.link(hull)
    hull.select_set(True)
    bpy.context.view_layer.objects.active = hull
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / f"{source.stem}.glb"),
        export_format="GLB", use_selection=True, export_yup=True,
        export_cameras=False, export_lights=False, export_animations=False)
    preview = bpy.data.images.load(str(REVIEW / "previews" / f"{source.stem}.png"))
    preview.scale(400, 360)
    preview.filepath_raw = str(ROOT / "assets/ui/ships" / f"{source.stem}.png")
    preview.file_format = "PNG"
    preview.save()
    data.calc_loop_triangles()
    report[source.stem] = {"triangles": len(data.loop_triangles), "materials": len(materials),
                          "bytes": (OUTPUT / f"{source.stem}.glb").stat().st_size}
    print("EXPORTED", source.stem, report[source.stem], flush=True)
(OUTPUT / "export-stats.json").write_text(json.dumps(report, indent=2) + "\n")
