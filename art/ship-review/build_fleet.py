"""Validate the individual .blend files and assemble an editable fleet overview.

blender --background --factory-startup --python build_fleet.py
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent
roster=json.loads((HERE/'roster.json').read_text(encoding='utf-8'))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.name='All 82 ships - review collection'
label_material=bpy.data.materials.new('Ship labels')
label_material.diffuse_color=(.7,.85,1,1)
report=[]
groups={}
for group in ['Standard hulls','Plus ships','Playable variants']:
    coll=bpy.data.collections.new(group)
    scene.collection.children.link(coll)
    groups[group]=coll

for i,ship in enumerate(roster):
    path=HERE/'models'/(ship['slug']+'.blend')
    assert path.exists(),f'Missing model: {path}'
    assert (HERE/'previews'/(ship['slug']+'.jpg')).exists(),f'Missing preview: {ship["name"]}'
    with bpy.data.libraries.load(str(path),link=False) as (source,dest):
        dest.objects=[name for name in source.objects if name not in ['Studio floor','Key','Fill','Rim','Review camera']]
    objects=dest.objects
    roots=[o for o in objects if o.type=='EMPTY' and o.get('ship')==ship['name']]
    assert len(roots)==1,f'Missing or duplicate ship root: {ship["name"]}'
    root=roots[0]
    root.empty_display_size=3
    meshes=[o for o in objects if o.type=='MESH']
    assert meshes and all(o.parent==root for o in meshes),ship['name']
    for obj in meshes:
        assert obj.data.vertices and obj.data.polygons,obj.name
        assert obj.data.materials,obj.name
        assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co),obj.name
        assert all(p.area>1e-10 for p in obj.data.polygons),f'Degenerate face: {ship["name"]}/{obj.name}'
    group={'base':'Standard hulls','plus':'Plus ships','variant':'Playable variants'}[ship['kind']]
    collection=bpy.data.collections.new(ship['name'])
    groups[group].children.link(collection)
    for obj in objects: collection.objects.link(obj)
    root.location=((i%9)*10,-(i//9)*11,0)
    font=bpy.data.curves.new(ship['name']+' label','FONT')
    font.body=ship['name']; font.size=.48; font.align_x='CENTER'
    font.materials.append(label_material)
    label=bpy.data.objects.new(ship['name']+' label',font)
    collection.objects.link(label)
    label.location=root.location+Vector((0,-4.3,0))
    report.append(dict(name=ship['name'],meshes=len(meshes),faces=sum(len(o.data.polygons) for o in meshes)))
    print('VERIFIED',ship['name'],len(meshes),flush=True)

bpy.context.view_layer.update()
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            space.shading.type='SOLID'; space.shading.color_type='MATERIAL'; space.shading.light='STUDIO'
            space.shading.show_cavity=True; space.shading.cavity_type='BOTH'
            space.overlay.show_floor=False; space.overlay.show_axis_x=False; space.overlay.show_axis_y=False
            space.clip_end=2000
            space.region_3d.view_distance=180
            space.region_3d.view_location=(40,-49.5,0)
            space.region_3d.view_rotation=(1,0,0,0)
            space.region_3d.view_perspective='ORTHO'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'darkorbit-fleet.blend'),compress=True)
(HERE/'validation.json').write_text(json.dumps(dict(ships=len(report),checks=['All roster models reopen in Blender','Every ship has a preview','Named root and editable mesh children','Nonempty meshes with materials','Finite vertex coordinates','No zero-area faces'],models=report),indent=2)+'\n')
print('FLEET VERIFIED',len(report),flush=True)
