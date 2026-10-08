"""Export approved Blender aliens for Godot without altering review artifacts.

Blender --background --python-exit-code 1 --python tools/export_aliens.py
Centers each hull, converts the nose to -Z/up +Y and retains the existing
alien size tiers. Runtime 2K atlases retain the authored wear; 4K sources stay
packed in the review files. Godot generates per-surface LODs during import.
"""
import importlib.util
import json
import re
import struct
import zlib
from pathlib import Path

import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
REVIEW=ROOT/'art/alien-review'
OUTPUT=ROOT/'assets/aliens'
module=importlib.util.spec_from_file_location('alien_builder',REVIEW/'build_models.py')
builder=importlib.util.module_from_spec(module)
module.loader.exec_module(builder)
builder.surfaces.SIZE=2048


def runtime_map(path: Path, channel: str, target: Path) -> None:
    raw=path.read_bytes()
    assert struct.unpack('>II',raw[16:24])==(4096,4096)
    offset,compressed=8,bytearray()
    while offset<len(raw):
        length=struct.unpack_from('>I',raw,offset)[0]
        if raw[offset+4:offset+8]==b'IDAT':
            compressed.extend(raw[offset+8:offset+8+length])
        offset+=length+12
    rows=np.frombuffer(zlib.decompress(compressed),dtype=np.uint8).reshape(4096,-1)
    assert np.all(rows[:,0]==0), 'Expected authored filter-zero RGB PNG'
    pixels=rows[:,1:].reshape(4096,4096,3)[::-1].astype(np.float32)/255
    if channel=='albedo':
        pixels=np.where(pixels<=.04045,pixels/12.92,((pixels+.055)/1.055)**2.4)
    if channel=='normal':
        pixels=pixels*2-1
    pixels=pixels.reshape(2048,2,2048,2,3).mean(axis=(1,3))
    if channel=='albedo':
        pixels=np.where(pixels<=.0031308,pixels*12.92,1.055*np.maximum(pixels,0)**(1/2.4)-.055)
    if channel=='normal':
        pixels/=np.maximum(np.linalg.norm(pixels,axis=2,keepdims=True),1e-6)
        pixels=pixels*.5+.5
    builder.write_review_png(target,pixels)


def main() -> None:
    OUTPUT.mkdir(parents=True,exist_ok=True)
    source=(ROOT/'scripts/alien.gd').read_text()
    diameters=dict((name,float(value)) for name,value in
                   re.findall(r'"(Scout|Sentinel|Heavy)": ([0-9.]+),',source))
    assert set(diameters)==set(builder.NAMES), 'Missing runtime visual diameters'
    report={}
    for name in builder.NAMES:
        bpy.ops.wm.open_mainfile(filepath=str(REVIEW/'models'/(name.lower()+'.blend')))
        builder.geo.PARTS=[o for o in bpy.context.scene.objects if o.type=='MESH']
        temporary=ROOT/'build/alien-runtime-textures'/name.lower()
        temporary.mkdir(parents=True,exist_ok=True)
        maps={}
        for channel in ('albedo','orm','normal'):
            target=temporary/(channel+'.png')
            runtime_map(REVIEW/'materials'/name.lower()/(channel+'.png'),channel,target)
            image=bpy.data.images.load(str(target))
            image.colorspace_settings.name='sRGB' if channel=='albedo' else 'Non-Color'
            image.pack()
            maps[channel]=image
        materials={o.data.materials[0] for o in builder.geo.PARTS}
        for material in materials:
            for node in material.node_tree.nodes:
                if node.type=='TEX_IMAGE':
                    channel=node.image.name.split('.')[0]
                    assert channel in maps, node.image.name
                    node.image=maps[channel]
        report[name]=builder.export_model(name,OUTPUT,diameters[name])
        print('EXPORTED',name,report[name],flush=True)
    (OUTPUT/'export-stats.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
