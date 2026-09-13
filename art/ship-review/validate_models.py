"""Reopen and validate the two saved review models using Blender."""
import bpy
import json
import math
import struct
from pathlib import Path

HERE=Path(__file__).resolve().parent
expected={'aegis.blend','goliath.blend'}
assert {p.name for p in (HERE/'models').glob('*.blend')}==expected
report=[]
for name in ['Aegis','Goliath']:
    path=HERE/'models'/(name.lower()+'.blend')
    bpy.ops.wm.open_mainfile(filepath=str(path))
    root=bpy.data.objects.get(name)
    assert root is not None and root.type=='EMPTY',name
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    assert meshes and all(o.parent==root for o in meshes),name
    graph=bpy.context.evaluated_depsgraph_get()
    evaluated_faces=0
    for obj in meshes:
        assert obj.data.vertices and obj.data.polygons,obj.name
        assert obj.data.materials,obj.name
        assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co),obj.name
        assert all(p.area>1e-10 for p in obj.data.polygons),'Degenerate base face: '+obj.name
        evaluated=obj.evaluated_get(graph)
        data=evaluated.to_mesh()
        assert all(math.isfinite(c) for v in data.vertices for c in v.co),obj.name
        evaluated_faces+=len(data.polygons)
        evaluated.to_mesh_clear()
    cameras=[o for o in bpy.context.scene.objects if o.type=='CAMERA']
    assert len(cameras)==5,name
    references=[i for i in bpy.data.images if i.source=='FILE']
    assert references and all(i.packed_file for i in references),name
    for view in ['','-rear','-top','-side','-front']:
        preview=HERE/'previews'/(name.lower()+view+'.png')
        assert preview.exists(),name+view
        assert preview.stat().st_mtime>=path.stat().st_mtime,'Stale render: '+str(preview)
        assert struct.unpack('>II',preview.read_bytes()[16:24])==(1600,1440),'Draft render: '+str(preview)
    report.append({'name':name,'mesh_components':len(meshes),
        'base_faces':sum(len(o.data.polygons) for o in meshes),
        'evaluated_faces':evaluated_faces,'packed_references':len(references),
        'cameras':len(cameras),'bytes':path.stat().st_size})
    print('VERIFIED',report[-1],flush=True)
(HERE/'validation.json').write_text(json.dumps({'ships':2,'checks':[
    'Only Aegis and Goliath models remain',
    'Both saved files reopen in Blender',
    'Mesh components parented to the ship root',
    'Nonempty mesh geometry with materials',
    'Finite base and evaluated vertex coordinates',
    'No zero-area base polygons',
    'Five cameras and five 1600 x 1440 renders per ship, newer than the saved model',
    'All file-based reference images packed into the blend'
], 'models':report},indent=2)+'\n')
