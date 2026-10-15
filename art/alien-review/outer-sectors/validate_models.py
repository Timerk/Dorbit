"""Reopen the six authored models and round-trip their portable GLBs."""
import importlib.util
import json
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent
module=importlib.util.spec_from_file_location('m1_validation',HERE.parent/'validate_models.py')
validation=importlib.util.module_from_spec(module)
module.loader.exec_module(validation)
NAMES=('Skirmisher','Raider','Marauder','Warden','Ravager','Overlord')
DRIVES=(2,2,3,2,3,4)
VIEWS=('','-top','-side','-front','-rear','-underside','-armor-detail','-mount-detail','-drive-detail')


def exhausts(name):
    if name=='Raider':
        return [o.matrix_world.translation.copy() for o in bpy.context.scene.objects
                if o.type=='MESH' and 'recessed exhaust bar' in o.name and abs(o.location.z-.13)<.001]
    return [o.matrix_world.translation.copy() for o in bpy.context.scene.objects
            if o.type=='MESH' and 'exhaust emitter' in o.name]


def check_exhausts(centers):
    graph=bpy.context.evaluated_depsgraph_get()
    for center in centers:
        hit=bpy.context.scene.ray_cast(graph,center+Vector((0,6,0)),Vector((0,-1,0)),distance=7)
        assert hit[0] and 'sensor emission' in validation.hit_material(hit,graph).name, 'Blocked rear emitter'


def main():
    names=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(NAMES)
    assert not set(names)-set(NAMES)
    report=[]
    for name in names:
        slug=name.lower()
        path=HERE/'models'/(slug+'.blend')
        bpy.ops.wm.open_mainfile(filepath=str(path))
        root=bpy.data.objects[name]
        assert root['drive_count']==DRIVES[NAMES.index(name)]
        meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
        assert all(o.parent==root for o in meshes)
        triangles,dimensions=validation.validate_geometry(meshes,require_atlas=True)
        assert len([o for o in bpy.context.scene.objects if o.type=='CAMERA'])==9
        assert bpy.context.scene.camera.name==name+' perspective'
        images=[i for i in bpy.data.images if i.source=='FILE']
        assert len(images)==4 and all(i.packed_file for i in images)
        maps={i.name.split('.')[0]:i for i in images if i.name.split('.')[0] in {'albedo','orm','normal'}}
        assert len(maps)==3 and all(tuple(i.size)==(4096,4096) for i in maps.values())
        assert maps['albedo'].colorspace_settings.name=='sRGB'
        assert all(maps[k].colorspace_settings.name=='Non-Color' for k in ('orm','normal'))
        assert any(Path(i.filepath).name==slug+'.png' for i in images)
        centers=exhausts(name)
        assert len(centers)==DRIVES[NAMES.index(name)], (name,len(centers))
        check_exhausts(centers)
        # Bilateral construction bounds include the same attached machinery.
        corners=[o.matrix_world@Vector(p) for o in meshes for p in o.bound_box]
        assert abs(min(p.x for p in corners)+max(p.x for p in corners))<.001
        for suffix in VIEWS:
            render=HERE/'previews'/(slug+suffix+'.png')
            assert render.stat().st_mtime>=path.stat().st_mtime
            assert struct.unpack('>II',render.read_bytes()[16:24])==(1600,1200)
        export=HERE/'exports'/(slug+'.glb')
        raw=export.read_bytes()
        magic,version,total,length,kind=struct.unpack_from('<5I',raw)
        assert magic==0x46546c67 and version==2 and total==len(raw) and kind==0x4e4f534a
        document=json.loads(raw[20:20+length])
        assert len(document['meshes'])==1 and len(document['images'])==3 and len(document['textures'])==3
        assert all('bufferView' in i for i in document['images'])
        assert not document.get('cameras') and not document.get('animations')
        for primitive in document['meshes'][0]['primitives']:
            assert {'POSITION','NORMAL','TEXCOORD_0'}<=primitive['attributes'].keys()
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(export))
        imported=[o for o in bpy.context.scene.objects if o.type=='MESH']
        assert len(imported)==1
        exported_triangles,exported_dimensions=validation.validate_geometry(imported)
        assert all(abs(a-b)<.04 for a,b in zip(dimensions,exported_dimensions))
        check_exhausts(centers)
        record=dict(name=name,components=len(meshes),source_triangles=triangles,
                    exported_triangles=exported_triangles,drive_count=len(centers),packed_images=4,
                    dimensions=[round(v,4) for v in dimensions],blend_bytes=path.stat().st_size,
                    glb_bytes=len(raw),renders=9)
        report.append(record)
        print('VERIFIED',record,flush=True)
    if len(report)==6:
        (HERE/'validation.json').write_text(json.dumps(dict(models=report,checks=[
            'Saved models reopen with editable parented components and nine cameras',
            'Finite nondegenerate evaluated geometry, active atlas UVs and symmetric bounds',
            'Approved reference and three 4K PBR maps are packed with correct color spaces',
            'Nine final 1600 x 1200 renders per model postdate the saved source',
            'Portable GLBs have one mesh, normals, UVs and three embedded maps',
            'GLBs round-trip with matching dimensions and no studio nodes',
            'All 16 rear exhaust centers remain visible in source and exported geometry'
        ]),indent=2)+'\n')


if __name__=='__main__':
    main()
