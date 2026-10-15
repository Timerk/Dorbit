"""Author the approved Dorbit transit gate. Blender --background --python tools/build_gate.py.

Godot coordinates: aperture in XY, axis Z, 12.6 m clear opening radius.
The model is decorative: travel/protection radii remain in SectorMaps.
"""
from pathlib import Path
import math
import json
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/sector'
REVIEW = ROOT / 'art/gate-review'
MATS = {}
PARTS = []

def point(p):
    return Vector((p[0], -p[2], p[1]))

def material(name, color, metal, roughness, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = roughness
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    else:
        t = m.node_tree.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(str(REVIEW / 'gate-metal.png'), check_existing=True)
        m.node_tree.links.new(t.outputs['Color'], p.inputs['Base Color'])
        t = m.node_tree.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(str(REVIEW / 'gate-normal.png'), check_existing=True)
        t.image.colorspace_settings.name = 'Non-Color'
        n = m.node_tree.nodes.new('ShaderNodeNormalMap')
        n.inputs['Strength'].default_value = .5
        m.node_tree.links.new(t.outputs['Color'], n.inputs['Color'])
        m.node_tree.links.new(n.outputs['Normal'], p.inputs['Normal'])
    MATS[name] = m

def mesh(name, vertices, faces, mat, bevel=0):
    d = bpy.data.meshes.new(name)
    d.from_pydata([point(v) for v in vertices], [], faces)
    d.materials.append(MATS[mat])
    d.update()
    o = bpy.data.objects.new(name, d)
    bpy.context.scene.collection.objects.link(o)
    uv = d.uv_layers.new(name='Metric surface')
    for f in d.polygons:
        axis = max(range(3), key=lambda a: abs(f.normal[a]))
        axes = [a for a in range(3) if a != axis]
        for li in f.loop_indices:
            v = d.vertices[d.loops[li].vertex_index].co
            uv.data[li].uv = (v[axes[0]]/12.0, v[axes[1]]/12.0)
    if bevel:
        bpy.context.view_layer.objects.active = o
        b = o.modifiers.new('Machined armor edges', 'BEVEL')
        b.width = bevel
        b.segments = 2
        bpy.ops.object.modifier_apply(modifier=b.name)
        n = o.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=n.name)
    PARTS.append(o)
    return o

def arc(name, inner, outer, start, finish, z, depth, mat, steps=8, bevel=.035):
    vertices = [(r*math.cos(a),r*math.sin(a),dz)
                for dz in [z-depth/2,z+depth/2]
                for r in [inner,outer]
                for a in np.linspace(start,finish,steps+1)]
    n = steps+1
    faces = []
    for i in range(steps):
        faces.extend([(i,i+1,n+i+1,n+i),
                      (2*n+i,3*n+i,3*n+i+1,2*n+i+1),
                      (i,2*n+i,2*n+i+1,i+1),
                      (n+i,n+i+1,3*n+i+1,3*n+i)])
    faces.extend([(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)])
    return mesh(name,vertices,faces,mat,bevel)

def box(name, center, size, mat, angle=0, bevel=.06):
    c, s = Vector(center), Vector(size)/2
    vertices = []
    for z in [-1,1]:
        for y in [-1,1]:
            for x in [-1,1]:
                dx,dy = x*s.x,y*s.y
                vertices.append(tuple(c+Vector((dx*math.cos(angle)-dy*math.sin(angle),dx*math.sin(angle)+dy*math.cos(angle),z*s.z))))
    return mesh(name,vertices,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,bevel)

def tube(name, path, radius, mat, sides=8):
    vertices = []
    for i,p in enumerate(path):
        tangent = (Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])).normalized()
        axis = tangent.cross(Vector((0,0,1))).normalized()
        if axis.length < .1:
            axis = tangent.cross(Vector((0,1,0))).normalized()
        other = tangent.cross(axis).normalized()
        for j in range(sides):
            vertices.append(tuple(Vector(p)+radius*(axis*math.cos(j*math.tau/sides)+other*math.sin(j*math.tau/sides))))
    faces = [(i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j)
             for i in range(len(path)-1) for j in range(sides)]
    return mesh(name,vertices,faces,mat)

def textures():
    rng = np.random.default_rng(8502)
    n = 512
    y,x = np.indices((n,n))
    height = .5+rng.normal(0,.007,(n,n))
    shade = .86+rng.normal(0,.018,(n,n))+np.sin(y*.72)*.012
    seams = (x%512<2)|(y%256<2)
    shade[seams] = .32
    height[seams] = .25
    for px in [12,500]:
        for py in [12,244,268,500]:
            screw = (x-px)**2+(y-py)**2<8
            shade[screw] = .23
            height[screw] = .2
    for i in range(70):
        px,py = rng.integers(0,n,2)
        length = rng.integers(3,24)
        shade[py:min(n,py+1),px:min(n,px+length)] *= .65
    rgba = np.ones((n,n,4),dtype=np.float32)
    rgba[:,:,:3] = shade[:,:,None]
    for name,data,color in [('gate-metal',rgba.copy(),True)]:
        save_texture(name,data,color)
    dx = (np.roll(height,-1,1)-np.roll(height,1,1))*.9
    dy = (np.roll(height,-1,0)-np.roll(height,1,0))*.9
    normal = np.stack((-dx,-dy,np.ones_like(dx)),axis=-1)
    normal /= np.linalg.norm(normal,axis=-1)[:,:,None]
    rgba[:,:,:3] = normal*.5+.5
    save_texture('gate-normal',rgba,False)

def save_texture(name,data,color):
    image = bpy.data.images.new(name,width=data.shape[1],height=data.shape[0],alpha=True)
    image.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    image.pixels.foreach_set(data.ravel())
    image.filepath_raw = str(REVIEW/(name+'.png'))
    image.file_format = 'PNG'
    image.save()

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    REVIEW.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    textures()
    material('Gate titanium',(.65,.7,.77),.8,.28)
    material('Gate graphite',(.045,.06,.08),.65,.48)
    material('Gate cobalt',(.11,.2,.32),.7,.25)
    material('Gate chrome',(.42,.51,.6),.88,.2)
    material('Gate cyan',(.02,.72,1),0,.35,2)
    # Layered annular spine, segmented armor and recessed service bays.
    arc('Main annular spine',12.6,18.5,0,math.tau,0,5.0,'Gate graphite',128)
    for side in [-1,1]:
        arc('Inner rim rail',12.6,13.1,0,math.tau,side*2.72,.32,'Gate chrome',128)
        arc('Luminous inner lip',12.7,12.95,0,math.tau,side*2.91,.1,'Gate cyan',128,0)
        for index in range(36):
            a = index*math.tau/36
            gap = .012
            b = a+math.tau/36-gap
            arc('Titanium armor segment',13.2,17.4,a+gap,b,side*2.62,.85,'Gate titanium',4,.08)
            # Staggered raised plates and dark recessed vent banks break up
            # the broad annular face, as in the approved machined-metal concept.
            arc('Raised inner armor',13.3,14.4,a+.023,b-.016,side*3.09,.2,'Gate chrome',4,.10)
            arc('Stepped outer armor',16.2,17.25,a+.028,b-.020,side*3.11,.24,'Gate cobalt' if index%5==0 else 'Gate titanium',4,.10)
            arc('Recessed inspection panel',14.7,15.95,a+.040,b-.030,side*3.075,.045,'Gate graphite',3,.015)
            if index%3:
                arc('Inset inspection cover',14.83,15.82,a+.054,b-.045,side*3.12,.06,'Gate cobalt' if index%4==0 else 'Gate chrome',3,.03)
            else:
                for r in [14.85,15.08,15.31,15.54,15.77]:
                    arc('Vent louver',r,r+.065,a+.055,b-.048,side*3.13,.08,'Gate chrome',2,0)
            arc('Outer shoulder',17.5,18.8,a+gap,b,side*1.92,1.65,'Gate titanium' if index%4 else 'Gate cobalt',4,.08)
            arc('Inset service groove',14.0,16.65,a+.027,a+.041,side*3.07,.04,'Gate graphite',1,0)
            arc('Armor trim seam',13.5,17.1,b-.028,b-.014,side*3.07,.045,'Gate chrome',1,0)
            angle = a+.082
            p = (12.45*math.cos(angle),12.45*math.sin(angle),side*2.2)
            box('Aperture emitter',p,(.75,1.55,1.3),'Gate cobalt',angle,.07)
            p = (12.22*math.cos(angle),12.22*math.sin(angle),side*2.89)
            box('Emitter lens',p,(.12,1.05,.08),'Gate cyan',angle,.01)
            for r in [14.1,16.8]:
                for offset in [.048,.125]:
                    angle = a+offset
                    box('Recessed fastener',(r*math.cos(angle),r*math.sin(angle),side*3.08),(.14,.14,.04),'Gate graphite',angle,.02)
    # Four complete outer conduits with machined support clamps and connector bands.
    for z in [-1.65,-.55,.55,1.65]:
        path = [(20.0*math.cos(a),20.0*math.sin(a),z) for a in np.linspace(0,math.tau,193)]
        tube('Heavy outer conduit',path,.28,'Gate graphite',10)
        for index in range(72):
            a = index*math.tau/72
            arc('Conduit coupling',19.64,20.36,a,a+.025,z,.62,'Gate chrome',2,0)
    for index in range(24):
        a = index*math.tau/24
        arc('Outer conduit bracket',18.15,20.7,a-.025,a+.025,0,4.6,'Gate titanium',2,.05)
    # Three power modules are the prominent silhouettes in the approved concept.
    for index in range(3):
        a = index*math.tau/3
        def pod(name, radial, size, mat, z=0, tangent=0):
            return box(name,(radial*math.cos(a)-tangent*math.sin(a),radial*math.sin(a)+tangent*math.cos(a),z),size,mat,a,.13)
        pod('Power module dark chassis',18.1,(5.7,6.6,5.4),'Gate graphite')
        pod('Power module silver casing',18.9,(5.6,5.5,6.2),'Gate titanium')
        pod('Power module cap',21.2,(1.25,5.6,5.9),'Gate cobalt')
        for side in [-1,1]:
            pod('Recessed energy bay',18.9,(3.9,3.4,.18),'Gate graphite',side*3.19)
            pod('Cobalt emitter surround',18.9,(3.1,2.5,.16),'Gate cobalt',side*3.32)
            pod('Bright module aperture',18.9,(2.3,.35,.08),'Gate cyan',side*3.43)
            for radial in [17.45,20.4]:
                pod('Module armor plate',radial,(.72,3.9,.22),'Gate titanium',side*3.38)
                for t in [-1.35,-.9,-.45,0,.45,.9,1.35]:
                    pod('Pod service vent',radial,(.46,.11,.04),'Gate graphite',side*3.52,t)
            pod('Module status light',18.9,(1.1,.10,.09),'Gate cyan',side*3.46,1.02)
            for t in [-1.98,1.98]:
                pod('Power armor lip',18.9,(4.5,.27,.35),'Gate chrome',side*3.26,t)
        for step in range(6):
            pod('Module heat sink',21.85,(.35,4.4,.2),'Gate graphite',-2.0+step*.8)
    # Combine by material: five surfaces, shared by all eight gate instances.
    bpy.ops.object.select_all(action='DESELECT')
    for o in PARTS:
        o.select_set(True)
    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = 'Dorbit transit gate'
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(REVIEW/'transit-gate.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/'transit-gate.glb'),export_format='GLB',export_yup=True,export_cameras=False,export_lights=False)
    # glTF's texture factor preserves the authored metal tints. Blender's
    # exporter drops a constant multiply node, so set the standard PBR factor.
    import struct
    path = OUT/'transit-gate.glb'
    binary = path.read_bytes()
    length = struct.unpack_from('<I', binary, 12)[0]
    document = json.loads(binary[20:20+length])
    for exported in document['materials']:
        exported['pbrMetallicRoughness']['baseColorFactor'] = list(MATS[exported['name']].diffuse_color)
    encoded = json.dumps(document,separators=(',',':')).encode()
    encoded += b' ' * (-len(encoded)%4)
    tail = binary[20+length:]
    path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(tail))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+tail)
    triangles = sum(len(p.vertices)-2 for p in o.data.polygons)
    (REVIEW/'transit-gate-stats.json').write_text(json.dumps({'triangles':triangles,'materials':len(o.data.materials),'aperture_radius_m':12.6,'purpose':'Client-only travel gate presentation; no collision'},indent=2)+'\n')
    print('Gate model:',triangles,'triangles,',len(o.data.materials),'materials')

if __name__ == '__main__':
    build()
