"""Validate saved Blender geometry, packed textures, and GLB round trips."""
import json
import math
import struct
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
NAMES = ('Scout','Sentinel','Heavy')


def hit_material(hit, graph):
    """Scene raycasts return evaluated face indices, including bevel faces."""
    evaluated=hit[4].evaluated_get(graph)
    mesh=evaluated.to_mesh()
    try:
        assert 0<=hit[3]<len(mesh.polygons), 'Invalid evaluated raycast face'
        return mesh.materials[mesh.polygons[hit[3]].material_index]
    finally:
        evaluated.to_mesh_clear()


def validate_geometry(meshes: list[bpy.types.Object], require_atlas: bool = False) -> tuple[int, list[float]]:
    triangles = 0
    bounds = []
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        assert obj.data.vertices and obj.data.polygons, obj.name
        assert obj.data.materials, obj.name
        assert all(math.isfinite(c) for vertex in obj.data.vertices for c in vertex.co), obj.name
        assert all(p.area>1e-10 for p in obj.data.polygons), 'Degenerate face: '+obj.name
        assert obj.data.uv_layers.active, 'Missing UVs: '+obj.name
        if require_atlas:
            assert obj.data.uv_layers.active.name=='Fitted component atlas', 'Wrong active UV: '+obj.name
            assert obj.data.uv_layers.active.active_render, 'Wrong render UV: '+obj.name
        assert all(0<=c<=1 for loop in obj.data.uv_layers.active.data for c in loop.uv), obj.name
        evaluated = obj.evaluated_get(graph)
        data = evaluated.to_mesh()
        assert all(math.isfinite(c) for vertex in data.vertices for c in vertex.co), obj.name
        assert all(p.area>1e-10 for p in data.polygons), 'Degenerate evaluated face: '+obj.name
        data.calc_loop_triangles()
        triangles += len(data.loop_triangles)
        bounds += [obj.matrix_world @ vertex.co for vertex in data.vertices]
        evaluated.to_mesh_clear()
    low = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    return triangles,list(high-low)


def main() -> None:
    report = []
    expected = {name.lower()+'.blend' for name in NAMES}
    assert {p.name for p in (HERE/'models').glob('*.blend')} == expected
    for name in NAMES:
        slug = name.lower()
        path = HERE/'models'/(slug+'.blend')
        bpy.ops.wm.open_mainfile(filepath=str(path))
        root = bpy.data.objects.get(name)
        assert root and root.type=='EMPTY', name
        meshes = [o for o in bpy.context.scene.objects if o.type=='MESH']
        assert meshes and all(o.parent==root for o in meshes), name
        triangles,dimensions = validate_geometry(meshes,require_atlas=True)
        cameras = [o for o in bpy.context.scene.objects if o.type=='CAMERA']
        assert len(cameras)==9 and bpy.context.scene.camera.name==name+' perspective', name
        images = [i for i in bpy.data.images if i.source=='FILE']
        assert len(images)==4 and all(i.packed_file for i in images), name
        assert any(Path(i.filepath).name==slug+'.png' for i in images), name
        maps = {i.name.split('.')[0]:i for i in images if i.name.split('.')[0] in {'albedo','orm','normal'}}
        assert set(maps)=={'albedo','orm','normal'}, name
        assert all(tuple(i.size)==(4096,4096) for i in maps.values()), name
        assert maps['albedo'].colorspace_settings.name=='sRGB', name
        assert all(maps[k].colorspace_settings.name=='Non-Color' for k in ('orm','normal')), name
        for mat in {obj.data.materials[0] for obj in meshes}:
            assert len([node for node in mat.node_tree.nodes if node.type=='TEX_IMAGE'])==3, mat.name
        exhaust_centers = []
        graph = bpy.context.evaluated_depsgraph_get()
        for side in ('Port','Starboard'):
            emitter = bpy.data.objects.get(side+' exhaust emitter')
            assert emitter, name+' missing exhaust emitter'
            center = emitter.matrix_world.translation.copy()
            exhaust_centers.append(center)
            hit = bpy.context.scene.ray_cast(graph,center+Vector((0,5,0)),Vector((0,-1,0)),distance=6)
            assert hit[0] and hit[3]>=0, name+' obstructed rear exhaust: '+side
            material=hit_material(hit,graph)
            assert 'sensor emission' in material.name, name+' blocked exhaust light: '+side
        for view in ('','-top','-side','-front','-rear','-underside',
                     '-armor-detail','-mount-detail','-drive-detail'):
            render = HERE/'previews'/(slug+view+'.png')
            assert render.exists() and render.stat().st_mtime>=path.stat().st_mtime, str(render)
            assert struct.unpack('>II',render.read_bytes()[16:24])==(1600,1200), str(render)
        record = {'name':name,'mesh_components':len(meshes),'studio_triangles':triangles,
                  'dimensions_review_units':[round(c,4) for c in dimensions],
                  'packed_images':len(images),'blend_bytes':path.stat().st_size}
        export = HERE/'exports'/(slug+'.glb')
        raw = export.read_bytes()
        magic,version,total,length,kind = struct.unpack_from('<5I',raw)
        assert magic==0x46546c67 and version==2 and total==len(raw) and kind==0x4e4f534a
        gltf = json.loads(raw[20:20+length])
        assert len(gltf['meshes'])==1 and not gltf.get('cameras') and not gltf.get('animations'), name
        assert all('bufferView' in image for image in gltf['images']), name
        assert len(gltf['images'])==3 and len(gltf['textures'])==3, name
        for primitive in gltf['meshes'][0]['primitives']:
            assert {'POSITION','NORMAL','TEXCOORD_0'} <= primitive['attributes'].keys(), name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(export))
        imported = [o for o in bpy.context.scene.objects if o.type=='MESH']
        assert len(imported)==1, name
        exported_triangles,exported_dimensions = validate_geometry(imported)
        assert all(abs(a-b)<.04 for a,b in zip(dimensions,exported_dimensions)), name
        assert all(obj.type not in {'LIGHT','CAMERA'} for obj in bpy.context.scene.objects), name
        graph = bpy.context.evaluated_depsgraph_get()
        for center in exhaust_centers:
            hit = bpy.context.scene.ray_cast(graph,center+Vector((0,5,0)),Vector((0,-1,0)),distance=6)
            assert hit[0] and hit[3]>=0, name+' missing exported exhaust'
            material = hit_material(hit,graph)
            assert 'sensor emission' in material.name, name+' obstructed exported exhaust'
        record.update({'export_triangles':exported_triangles,'export_bytes':len(raw),
                       'embedded_texture_images':len(gltf['images'])})
        report.append(record)
        print('VERIFIED',record,flush=True)
    (HERE/'validation.json').write_text(json.dumps({'models':report,'checks':[
        'Three saved Blender models reopen with editable components and nine cameras',
        'Finite nondegenerate base and evaluated geometry with UVs and materials',
        'Approved concept and three 4096-square surface maps packed per model',
        'Correct sRGB albedo and Non-Color roughness/metallic and tangent normal maps',
        'Six full views and three detail renders per alien are newer than the saved model',
        'Single-mesh GLB exports have UVs/normals and three unique embedded textures',
        'GLBs round-trip through Blender with dimensions/orientation preserved',
        'Source and round-trip rear raycasts reach both recessed emissive exhaust centers',
        'Exports include no studio cameras, lights or animations'
    ]},indent=2)+'\n')


if __name__=='__main__':
    main()
