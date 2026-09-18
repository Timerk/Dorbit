"""Individually authored DarkOrbit reference studies for Blender 5.2.

blender --background --factory-startup --python build_models.py -- Bigboy Phoenix --gpu
Forward is -Y, up is Z. Dimensions are reconstruction units, not canonical meters.
"""
import bpy
import bmesh
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent
PARTS = []
M = {}
GROUP = None
NAMES = ['Aegis', 'Goliath', 'Bigboy', 'Defcom', 'Leonov', 'Liberator',
         'Nostromo', 'Phoenix', 'Piranha', 'Spearhead', 'Vengeance', 'Yamato']


def material(name, color, metal=.7, rough=.35, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = rough
    if metal > .45 and not emission:
        # Subtle metal grain only. Large panel joints are mesh geometry.
        noise=mat.node_tree.nodes.new('ShaderNodeTexNoise')
        noise.inputs['Scale'].default_value=175
        noise.inputs['Detail'].default_value=2
        bump=mat.node_tree.nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value=.12
        bump.inputs['Distance'].default_value=.008
        mat.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height'])
        mat.node_tree.links.new(bump.outputs['Normal'],bs.inputs['Normal'])
    if emission:
        bs.inputs['Emission Color'].default_value = (*color, 1)
        bs.inputs['Emission Strength'].default_value = emission
    return mat


def group(name):
    global GROUP
    GROUP = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(GROUP)


def finish(obj, name, mat, bevel=.012, smooth=False):
    obj.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    GROUP.objects.link(obj)
    obj.data.materials.append(M[mat])
    if bevel:
        mod = obj.modifiers.new('Edge radius', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    if bevel:
        mod = obj.modifiers.new('Weighted surface normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        mod.weight = 40
    PARTS.append(obj)
    return obj


def mesh(name, verts, faces, mat='steel', bevel=.012, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    GROUP.objects.link(obj)
    return finish(obj, name, mat, bevel, smooth)


def box(name, loc, size, mat='dark', bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)


def tube(name, a, b, radius, mat='dark', r2=None, vertices=32, bevel=.009):
    delta = Vector(b) - Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
        radius2=radius if r2 is None else r2, depth=delta.length,
        location=(Vector(a) + Vector(b)) / 2)
    obj = bpy.context.object
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, mat, bevel, True)


def sphere(name, loc, size, mat='dark'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, location=loc)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, 0, True)


def ring(name, loc, major, minor, mat='steel', axis=(0,0,1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=64, minor_segments=12,
        major_radius=major, minor_radius=minor, location=loc)
    obj = bpy.context.object
    obj.rotation_euler = Vector(axis).to_track_quat('Z','Y').to_euler()
    return finish(obj, name, mat, 0, True)


def pipe(name, points, radius=.018, mat='steel'):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 2
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    curve.use_fill_caps = True
    spline = curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    obj = bpy.data.objects.new(name, curve)
    GROUP.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    return finish(obj, name, mat, 0, True)


def panel(name, points, depth=.04, mat='steel', bevel=.012, normal=(0,0,1)):
    n = len(points)
    delta = Vector(normal).normalized() * depth
    verts = [tuple(Vector(p)-delta/2) for p in points] + [tuple(Vector(p)+delta/2) for p in points]
    faces = [tuple(reversed(range(n))), tuple(range(n,2*n))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name, verts, faces, mat, bevel)


def loft(name, stations, mat='steel', bevel=.025):
    # Stations: center x, y, center z, half width, half height.
    profile = [(-.65,1),(.65,1),(1,.45),(1,-.45),(.65,-1),(-.65,-1),(-1,-.45),(-1,.45)]
    verts = [(x+w*u,y,z+h*v) for x,y,z,w,h in stations for u,v in profile]
    faces = [tuple(reversed(range(8)))]
    for j in range(len(stations)-1):
        faces.extend((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k) for k in range(8))
    faces.append(tuple(range(len(verts)-8,len(verts))))
    return mesh(name, verts, faces, mat, bevel)


def bolt(loc, axis=(0,0,1), radius=.025):
    a = Vector(loc)
    v = Vector(axis).normalized()
    tube('Recessed fastener',a-v*.004,a+v*.012,radius,'recess',vertices=12,bevel=.002)
    tube('Hex socket screw',a+v*.012,a+v*.021,radius*.64,'steel',vertices=6,bevel=.001)


def nozzle(name, center, axis, radius, length, hollow=False):
    c = Vector(center)
    v = Vector(axis).normalized()
    housing=tube(name+' housing',c-v*length,c,radius*1.1,'dark',r2=radius)
    if hollow:
        bm=bmesh.new(); bm.from_mesh(housing.data)
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if len(f.verts)>4],context='FACES')
        bm.to_mesh(housing.data); bm.free()
        solid=housing.modifiers.new('Nozzle wall thickness','SOLIDIFY'); solid.thickness=.018
    ring(name+' machined lip',c,radius,.035,'steel',axis)
    tube(name+' recessed well',c-v*.06,c-v*.045,radius*.83,'recess')
    tube(name+' emitter',c-v*.037,c-v*.028,radius*.57,'light',bevel=0)
    # Vanes remain inside the rim, not a solid luminous disk over the engine.
    u = v.cross(Vector((1,0,0)))
    if u.length < .1:
        u = v.cross(Vector((0,1,0)))
    u.normalize()
    w = v.cross(u)
    for i in range(12):
        r = u*math.cos(i*math.tau/12)+w*math.sin(i*math.tau/12)
        tube(name+' nozzle vane',c+r*radius*.65,c+r*radius*.92,.016,'steel',vertices=8,bevel=0)


def aegis_barrel(name, angles, lower, upper, mat, radius=1.02, wall=.14):
    # Rounded U-shaped engineering shell. Front opening exposes the neck.
    verts=[]
    levels=[(lower,.83),(lower+.14,.98),(upper-.15,1),(upper,.89)]
    for z,scale in levels:
        for inner in [False,True]:
            r=radius*scale-(wall if inner else 0)
            verts += [(math.sin(a)*r,.85+math.cos(a)*r,z) for a in angles]
    n=len(angles)
    faces=[]
    for j in range(3):
        for layer in range(2):
            for k in range(n-1):
                a=j*n*2+layer*n+k
                faces.append((a,a+1,a+n*2+1,a+n*2))
    for j in [0,3]:
        for k in range(n-1):
            a=j*n*2+k
            faces.append((a,a+1,a+n+1,a+n))
    for k in [0,n-1]:
        for j in range(3):
            a=j*n*2+k
            faces.append((a,a+n,a+n*3,a+n*2))
    return mesh(name,verts,faces,mat,.018,True)


def build_aegis():
    group('Aegis | engineering body')
    angles=[math.radians(-148+296*i/64) for i in range(65)]
    aegis_barrel('Continuous engineering chassis',angles,-.45,1.88,'dark')
    # Segmented cast armor with narrow real gaps, including chamfered rims.
    for i in range(8):
        lo=-148+i*37+.8
        hi=lo+35.4
        ang=[math.radians(lo+(hi-lo)*j/10) for j in range(11)]
        aegis_barrel('Green engineering armor %02d'%i,ang,-.32,1.92,'green',1.058)
    # Broad deck closes the space between outer armor and the emitter socket.
    deck_angles=[math.radians(-145+290*i/64) for i in range(65)]
    aegis_barrel('Upper engineering deck',deck_angles,1.71,1.91,'green',1.01,.48)
    ring('Recessed upper socket',(0,.86,1.92),.47,.025,'gunmetal')
    for a in [-115,-55,0,55,115]:
        a=math.radians(a)
        x,y=math.sin(a)*.78,.85+math.cos(a)*.78
        bolt((x,y,1.91),radius=.037)
    for side in [-1,1]:
        def cheek_x(y):
            return side*(math.sqrt(1.058**2-(y-.85)**2)+.014)
        # The broad flat cheeks border the front slot.
        panel('Raised front cheek',[(side*.5,-.02,1.81),(side*.91,.2,1.87),
            (side*1.01,.16,.0),(side*.72,-.18,-.23),(side*.52,-.22,.35)],.11,'green',.035,(side,0,0))
        for z in [.35,.51,1.26,1.42]:
            pipe('Cheek inset channel',[(cheek_x(.2),.2,z),(cheek_x(.57),.57,z),
                 (cheek_x(.72),.72,z+.09)],.016,'recess')
        for y in [.34,.61]:
            for z in [.63,1.15]:
                bolt((cheek_x(y),y,z),(side,0,0))
        # Small identification marks, as opposed to broad luminous armor.
        for z in [.64,.74,.84]:
            box('Service indicator',(cheek_x(.29),.29,z),(.015,.065,.025),'pale',.004)
        pipe('Side coolant return',[(cheek_x(.25),.25,.05),(cheek_x(.48),.48,-.12),
            (cheek_x(1.15),1.15,-.12),(cheek_x(1.34),1.34,.3)],.023,'gunmetal')
    tube('Central reactor column',(0,.86,-.53),(0,.86,2.12),.47,'dark')
    for z in [-.3,.04,.42,1.25,1.72,1.95]:
        ring('Reactor retention ring',(0,.86,z),.48,.026,'gunmetal')
    nozzle('Ventral reactor', (0,.86,-.58),(0,0,-1),.36,.28)
    group('Aegis | exposed upper assembly')
    tube('Turret foundation',(0,.86,1.74),(0,.86,2.07),.43,'dark')
    for i in range(10):
        a=i*math.tau/10
        x,y=math.cos(a)*.37,.86+math.sin(a)*.37
        tube('Exposed vertical actuator',(x,y,1.93),(x,y,2.31),.047,'steel')
    for z,r in [(2.10,.43),(2.27,.46),(2.36,.40)]:
        ring('Upper assembly collar',(0,.86,z),r,.019,'gunmetal')
    tube('Upper assembly drum',(0,.86,2.19),(0,.86,2.37),.43,'dark')
    for i in range(16):
        a=i*math.tau/16
        obj=box('Collar slot',(math.cos(a)*.432,.86+math.sin(a)*.432,2.28),(.052,.025,.037),'pale',.004)
        obj.rotation_euler.z=a-math.pi/2
    sphere('Rounded emitter crown',(0,.86,2.38),(.36,.36,.25),'dark')
    sphere('Green crown lens',(0,.86,2.56),(.13,.13,.06),'green')
    for a in [-math.pi/2,math.pi/6,5*math.pi/6]:
        sphere('Crown sensor housing',(math.cos(a)*.27,.86+math.sin(a)*.27,2.47),(.115,.115,.14),'gunmetal')
        sphere('Crown sensor window',(math.cos(a)*.325,.86+math.sin(a)*.325,2.48),(.065,.065,.075),'glass')
    # The supplied green base render has a whip antenna absent from the blue
    # engineering illustration. Retain this visible base-ship distinction.
    tube('Base ship antenna socket',(0,.94,2.53),(0,.94,2.70),.073,'dark',r2=.045)
    tube('Base ship whip antenna',(0,.94,2.69),(0,.94,3.29),.016,'dark',r2=.007,vertices=16,bevel=.002)
    for z in [2.75,2.93,3.11]:
        tube('Antenna insulator',(0,.94,z),(0,.94,z+.045),.026,'gunmetal',vertices=16,bevel=.002)
    group('Aegis | forward hull and neck')
    loft('Sloping nose chassis',[(0,-2.92,-.06,.29,.16),(0,-2.58,.02,.45,.26),
        (0,-1.84,.32,.59,.31),(0,-1.03,.67,.57,.30),(0,-.68,.73,.34,.22)],'dark')
    loft('Dorsal nose armor',[(0,-2.83,.095,.27,.07),(0,-2.49,.24,.39,.11),
        (0,-1.82,.57,.44,.10),(0,-1.1,.94,.43,.07),(0,-.82,.96,.31,.05)],'graphite')
    for side in [-1,1]:
        panel('Nose flanking armor',[(side*.40,-2.55,.18),(side*.60,-1.85,.46),
            (side*.56,-1.06,.78),(side*.82,-1.39,.04),(side*.62,-2.31,-.13)],.055,'graphite',.025,(side,0,.3))
        pipe('Nose longitudinal seam',[(side*.26,-2.75,.20),(side*.39,-2.15,.49),
            (side*.41,-1.49,.81),(side*.30,-1.05,1.02)],.014,'recess')
        for y,z in [(-2.49,.25),(-1.73,.64),(-1.21,.9)]:
            bolt((side*.28,y,z))
        panel('Forward lateral fin',[(side*.48,-1.22,.12),(side*.99,-.83,.0),
            (side*1.08,-1.31,-.20),(side*.80,-1.67,-.23)],.09,'graphite',.025)
        panel('Forward fin tip marking',[(side*.93,-.92,.015),(side*1.035,-1.02,-.03),
            (side*1.04,-1.24,-.12),(side*.94,-1.23,-.10)],.012,'green')
    loft('Inset dark cockpit',[(0,-2.15,.57,.16,.04),(0,-1.64,.80,.20,.075),
        (0,-1.43,.88,.17,.045)],'glass',.02)
    pipe('Canopy frame left',[(-.17,-2.15,.61),(-.22,-1.65,.84),(-.18,-1.43,.92)],.022,'steel')
    pipe('Canopy frame right',[(.17,-2.15,.61),(.22,-1.65,.84),(.18,-1.43,.92)],.022,'steel')
    for y,z in [(-2.4,.33),(-1.27,.965)]:
        box('Nose transverse panel joint',(0,y,z),(.49,.018,.015),'recess',.003)
    loft('Exposed inclined neck',[(0,-.92,.76,.28,.18),(0,-.26,1.27,.28,.18),(0,.42,1.45,.27,.18)],'dark')
    for x in [-.23,-.08,.08,.23]:
        pipe('Neck piston rail',[(x,-1,.87),(x,-.30,1.44),(x,.33,1.62)],.035,'gunmetal')
        tube('Neck actuator sleeve',(x,-.5,1.24),(x,-.11,1.51),.064,'graphite')
    for y,z in [(-.76,1.1),(-.52,1.29),(-.19,1.5),(.12,1.6)]:
        box('Neck transverse rib',(0,y,z),(.56,.046,.05),'dark',.008)
    group('Aegis | articulated forward tools')
    for side in [-1,1]:
        tube('Tool lateral pivot',(side*.38,-2.45,-.15),(side*.77,-2.45,-.15),.19,'dark')
        ring('Tool pivot collar',(side*.72,-2.45,-.15),.183,.03,'steel',(1,0,0))
        sphere('Tool elbow',(side*.77,-2.75,-.32),(.11,.14,.12),'dark')
        tube('Tool upper arm',(side*.74,-2.46,-.15),(side*.77,-2.82,-.35),.083,'graphite')
        tube('Tool piston',(side*.72,-2.68,-.22),(side*.72,-3.05,-.34),.035,'steel')
        tube('Tool wrist',(side*.77,-2.80,-.35),(side*.81,-3.12,-.38),.066,'dark')
        for finger in [-1,1]:
            pipe('Split manipulator finger',[(side*.81+finger*.035,-3.08,-.38),
                (side*.81+finger*.105,-3.19,-.37),(side*.81+finger*.08,-3.31,-.34),
                (side*.81+finger*.025,-3.35,-.33)],.033,'steel')
    group('Aegis | swept rear fins')
    for side in [-1,1]:
        pts=[(side*.60,1.25,1.37),(side*.77,1.34,1.90),
            (side*1.16,2.43,2.26),(side*1.20,2.42,1.90),(side*.85,1.94,1.32)]
        panel('Tall swept stabilizer',pts,.09,'graphite',.025,(side,0,0))
        pipe('Tall fin leading metal edge',[pts[1],pts[2],pts[3]],.024,'steel')
        panel('Tall fin inset armor',[(side*.795,1.50,1.84),(side*1.10,2.30,2.12),
            (side*1.10,2.24,1.92),(side*.90,1.89,1.57)],.014,'dark',.009,(side,0,0))
        panel('Tall fin green marking',[(side*1.02,2.05,2.10),(side*1.095,2.23,2.17),
            (side*1.11,2.25,1.93),(side*1.035,2.07,1.76)],.018,'green',.007,(side,0,0))
        panel('Lower rear stabilizer',[(side*.75,1.3,.45),(side*1.27,1.98,.13),
            (side*1.22,2.20,-.03),(side*.69,1.78,-.12)],.075,'graphite',.018)
    group('Aegis | service panels')
    for side in [-1,1]:
        # Small cooling banks sit on the shoulder behind the sloped cockpit.
        for i in range(5):
            y=-1.26+i*.075
            z=(.67+(y+1.82)*.34/.72 if y < -1.1 else 1.01)+.003
            obj=box('Nose shoulder cooling slit',(side*.20,y,z),(.075,.029,.015),'recess',.005)
            obj.rotation_euler.z=side*.13
        for y,z in [(-2.68,.23),(-2.30,.44)]:
            tube('Nose service latch',(side*.34,y,z-.02),(side*.34,y,z+.015),.035,'gunmetal',vertices=16)
        pipe('Shoulder recessed perimeter',[(side*.54,-1.37,.54),(side*.73,-1.45,.14),
             (side*.59,-2.21,-.02),(side*.48,-2.36,.14)],.013,'recess')
    for a in [-100,-65,-30,30,65,100]:
        a=math.radians(a)
        # Rear and side armor hatches follow the curved body, not a flat decal.
        def pt(da,z):
            return (math.sin(a+da)*1.064,.85+math.cos(a+da)*1.064,z)
        pipe('Engineering panel engraved outline',[pt(-.12,.10),pt(-.12,1.22),
             pt(.12,1.22),pt(.12,.10),pt(-.12,.10)],.011,'recess')
        for z in [.26,.36,.46]:
            pipe('Engineering lower cooling slit',[pt(-.08,z),pt(.08,z)],.015,'dark')


# The Goliath arm section changes in plan, elevation and width; it is not an
# extruded semicircle. The stations follow the catalogue's silver base hull.
ARM=[(.53,1.10,.03,.24,.20),(1.05,.95,.01,.34,.23),(1.60,.45,-.04,.40,.25),
     (1.96,-.27,-.12,.44,.24),(2.08,-1.10,-.19,.43,.22),
     (1.94,-1.90,-.26,.36,.19),(1.64,-2.61,-.32,.24,.145),
     (1.22,-3.12,-.33,.115,.08),(.87,-3.43,-.28,.018,.016)]


def arm_station(t):
    # Cubic Hermite interpolation keeps broad arms smoothly tapered.
    i=min(int(t),len(ARM)-2)
    f=t-i
    a,b=ARM[i],ARM[i+1]
    p=ARM[max(0,i-1)]
    q=ARM[min(len(ARM)-1,i+2)]
    return tuple((2*f**3-3*f*f+1)*a[j]+(f**3-2*f*f+f)*(b[j]-p[j])*.5+
        (-2*f**3+3*f*f)*b[j]+(f**3-f*f)*(q[j]-a[j])*.5 for j in range(5))


def arm_shape(name,side,start,end,mat,section='full'):
    profile=[(-1,0),(-.85,.68),(-.5,1),(.33,.90),(.78,.55),(1,-.05),
        (.77,-.62),(.18,-1),(-.64,-.82)]
    if section=='armor':
        profile=[(-.97,.08),(-.81,.75),(-.47,1.07),(.35,.98),(.79,.61),(.96,.07),
            (.80,.04),(.28,.83),(-.43,.90),(-.77,.58)]
    count=max(3,int((end-start)*14))
    verts=[]
    for k in range(count+1):
        t=start+(end-start)*k/count
        x,y,z,w,h=arm_station(t)
        prev=arm_station(max(0,t-.001)); nxt=arm_station(min(8,t+.001))
        tangent=Vector((nxt[0]-prev[0],nxt[1]-prev[1],0)).normalized()
        across=Vector((-tangent.y,tangent.x,0))
        for u,v in profile:
            verts.append((side*(x+across.x*w*u),y+across.y*w*u,z+h*v))
    n=len(profile)
    faces=[tuple(reversed(range(n)))]
    for j in range(count):
        faces.extend((j*n+k,j*n+(k+1)%n,(j+1)*n+(k+1)%n,(j+1)*n+k) for k in range(n))
    faces.append(tuple(range(len(verts)-n,len(verts))))
    return mesh(name,verts,faces,mat,.006,True)


def build_goliath():
    group('Goliath | tapered assault arms')
    for side in [-1,1]:
        arm_shape('Continuous curved arm chassis',side,0,8,'dark')
        for i,(a,b) in enumerate([(0,.97),(1.02,2.12),(2.17,3.35),(3.40,4.60),(4.65,5.85),(5.90,6.95),(7,8)]):
            arm_shape('Sculpted silver arm shell %02d'%i,side,a,b,'steel' if i%3 else 'silver','armor')
        # Narrow underside strip makes the darker structural core visible.
        points=[]
        for k in range(46):
            x,y,z,w,h=arm_station(.7+6.9*k/45)
            points.append((side*(x-w*.5),y,z-h*.5))
        pipe('Inner arm conduit',points,.026,'gunmetal')
        for t in [1.35,2.5,3.0,3.7,4.2,4.95,5.45,6.15]:
            x,y,z,w,h=arm_station(t)
            bolt((side*x,y,z+h*1.02),radius=.025)
        for t in [2.6,3.9,5.15,6.2]:
            x,y,z,w,h=arm_station(t)
            box('Arm side recessed port',(side*(x+w*.92),y,z),(.022,.15,.076),'recess',.012)
            box('Arm side port insert',(side*(x+w*.935),y,z),(.012,.08,.031),'pale',.003)
        for start,end in [(1.35,2.04),(2.42,3.12),(3.68,4.35),(4.91,5.55),(6.08,6.73)]:
            for offset in [-.42,.30]:
                pts=[]
                for k in range(12):
                    t=start+(end-start)*k/11
                    x,y,z,w,h=arm_station(t)
                    p=arm_station(t-.001);q=arm_station(t+.001)
                    tangent=Vector((q[0]-p[0],q[1]-p[1],0)).normalized()
                    across=Vector((-tangent.y,tangent.x,0))
                    # Armor crown slopes gently between its two ridge points.
                    crown=1.07-(offset+.47)*.09/.82
                    pts.append((side*(x+across.x*w*offset),y+across.y*w*offset,z+h*crown+.004))
                pipe('Fine arm armor channel',pts,.008,'gunmetal')
        # Broad swept winglets are part of the reference silhouette.
        def wing_point(x,y,offset=0):
            return (side*x,y,.08+.12*(y+.6)+offset)
        pts=[wing_point(1.92,-1.66),wing_point(2.83,-1.00),
             wing_point(2.92,-.62),wing_point(2.47,-.50),wing_point(1.97,-.62)]
        panel('Outer swept arm winglet',pts,.09,'steel',.024)
        panel('Winglet inset armor',[wing_point(2.03,-1.48,.067),wing_point(2.65,-1.06,.067),
             wing_point(2.77,-.70,.067),wing_point(2.40,-.65,.067),wing_point(2.04,-.76,.067)],.022,'silver',.012)
        pipe('Winglet panel channel',[wing_point(2.09,-1.37,.081),wing_point(2.40,-1.13,.081),
             wing_point(2.61,-.75,.081)],.009,'dark')
        for x,y,z in [(2.38,-1.12,.025),(2.68,-.76,.13)]:
            bolt(wing_point(x,y,.086),radius=.022)
    group('Goliath | central fuselage')
    loft('Lower mechanical hull',[(0,-.65,-.13,.18,.18),(0,-.30,-.05,.45,.27),
        (0,.55,.06,.68,.30),(0,1.38,.13,.58,.27),(0,2.20,.13,.28,.21),
        (0,2.58,.10,.15,.12)],'dark')
    loft('Upper silver fuselage',[(0,-.35,.10,.18,.10),(0,.05,.32,.35,.18),
        (0,.68,.43,.47,.22),(0,1.29,.44,.39,.23),(0,1.92,.38,.24,.18),
        (0,2.37,.30,.11,.08)],'steel')
    for side in [-1,1]:
        loft('Fuselage shoulder shell',[(side*.40,.10,.16,.14,.12),
            (side*.67,.47,.29,.20,.16),(side*.57,1.05,.34,.18,.14),
            (side*.36,1.60,.32,.13,.09)],'silver')
        pipe('Shoulder armor channel',[(side*.46,.19,.37),(side*.62,.54,.49),
            (side*.48,1.14,.49),(side*.29,1.66,.47)],.013,'dark')
        for y,z in [(.42,.47),(.96,.50),(1.38,.48)]:
            bolt((side*.29,y,z))
        tube('Arm shoulder joint',(side*.43,.86,-.04),(side*.83,.72,-.08),.21,'gunmetal')
    group('Goliath | dorsal paneling')
    for side in [-1,1]:
        panel('Spine armor panel',[(side*.055,.29,.576),(side*.21,.34,.588),
            (side*.28,.69,.68),(side*.235,1.21,.696),(side*.055,1.23,.698)],.022,'silver',.009)
        pipe('Spine panel engraved border',[(side*.09,.37,.607),(side*.18,.40,.614),
            (side*.235,.71,.703),(side*.20,1.13,.715)],.008,'gunmetal')
        panel('Aft spine armor panel',[(side*.05,1.34,.702),(side*.21,1.36,.69),
            (side*.15,1.81,.614),(side*.05,1.89,.598)],.02,'steel',.008)
        for i in range(4):
            obj=box('Aft spine radiator',(side*.14,1.44+i*.075,.695-i*.014),(.11,.028,.022),'recess',.004)
            obj.rotation_euler.x=-.18
        for y,z in [(.46,.645),(1.07,.73)]:
            bolt((side*.14,y,z),radius=.019)
    # Narrow forward beak hangs inside the open arms, below the rear fuselage.
    loft('Central forward beak',[(0,-2.16,-.26,.075,.065),(0,-1.68,-.23,.17,.10),
        (0,-.91,-.13,.25,.16),(0,-.30,.015,.31,.20),(0,.16,.11,.30,.16)],'gunmetal')
    loft('Inset bronze bridge',[(0,-1.13,.045,.12,.035),(0,-.66,.18,.21,.05),
        (0,-.32,.25,.18,.055),(0,-.16,.26,.13,.03)],'glass')
    for side in [-1,1]:
        pipe('Bridge canopy rim',[(side*.12,-1.12,.095),(side*.23,-.65,.235),
            (side*.18,-.29,.30)],.018,'steel')
        panel('Beak shoulder cheek',[(side*.13,-1.66,-.20),(side*.30,-.65,.03),
            (side*.45,-.21,.07),(side*.32,-.43,-.14)],.04,'steel',.012)
    tube('Forward beak aperture',(0,-2.155,-.26),(0,-2.18,-.26),.044,'recess')
    for y,z in [(-1.57,-.12),(-1.31,-.06),(-1.06,.02)]:
        box('Beak spine rib',(0,y,z),(.20,.035,.033),'dark',.008)
    group('Goliath | raised dorsal fins')
    for side in [-1,1]:
        # These lean outward; they must read tall in profile rather than flat.
        def fin_point(y,z,inset=0):
            height=(z-.36)*.65
            return (side*(.36+1.60*height+inset),y,.36+height)
        pts=[fin_point(.43,.36),fin_point(.30,1.40),fin_point(.97,1.53),
            fin_point(1.23,.83),fin_point(1.61,.40)]
        panel('Raised swept dorsal fin',pts,.085,'steel',.035,(side,0,0))
        panel('Dorsal fin inset',[fin_point(.57,.56,.058),fin_point(.48,1.31,.058),
            fin_point(.91,1.38,.058),fin_point(1.15,.79,.058),fin_point(1.39,.52,.058)],
            .018,'silver',.017,(side,0,0))
        pipe('Dorsal fin leading edge',[pts[0],pts[1],pts[2]],.019,'pale')
    loft('Tail dorsal ridge',[(0,1.56,.48,.10,.05),(0,2.09,.63,.13,.06),
        (0,2.45,.86,.08,.10),(0,2.69,.86,.025,.025)],'silver')
    panel('Small tail crest',[(-.19,2.30,.81),(-.10,2.66,.92),(0,2.51,.96),
        (.10,2.66,.92),(.19,2.30,.81),(0,2.38,.77)],.055,'steel')
    group('Goliath | engines and mechanical bays')
    for side in [-1,1]:
        nozzle('Aft ion engine',(side*.285,2.16,-.07),(0,1,0),.18,.58)
        loft('Engine dorsal cover',[(side*.32,1.20,-.05,.17,.15),
            (side*.36,1.72,.025,.21,.18),(side*.29,2.07,-.015,.19,.13)],'gunmetal')
        for i in range(6):
            box('Engine cooling louver',(side*.50,1.27+i*.10,.15),(.16,.044,.026),'recess',.006)
        pipe('Ventral hydraulic line',[(side*.30,-.22,-.25),(side*.56,.31,-.25),
             (side*.52,.98,-.19),(side*.23,1.58,-.15)],.027,'steel')
        for i in range(4):
            box('Ventral mechanical rib',(side*.39,.05+i*.18,-.24),(.16,.06,.09),'gunmetal',.012)
    panel('Ventral access cover',[(-.26,.29,-.29),(.26,.29,-.29),(.33,.94,-.22),
        (.18,1.40,-.17),(-.18,1.40,-.17),(-.33,.94,-.22)],.045,'graphite')
    # The reference's central beak is short and dark, recessed between the arms.
    beak_names=('Central forward beak','Inset bronze bridge','Bridge canopy rim',
                'Beak shoulder cheek','Forward beak aperture','Beak spine rib')
    bpy.context.view_layer.update()
    for obj in PARTS:
        if obj.name.startswith(beak_names):
            for v in obj.data.vertices:
                world=obj.matrix_world @ v.co
                world.y=world.y*.70
                v.co=obj.matrix_world.inverted() @ world
    for collection_name in ['Goliath | central fuselage','Goliath | dorsal paneling',
                            'Goliath | engines and mechanical bays']:
        for obj in bpy.data.collections[collection_name].objects:
            for v in obj.data.vertices:
                world=obj.matrix_world @ v.co
                world.x*=.80
                v.co=obj.matrix_world.inverted() @ world


def armored_hull(label, stations, paint='silver'):
    """Octagonal chassis with separated, fitted upper armor and inset seams."""
    loft(label+' inner hull',stations,'dark')
    for a,b in zip(stations,stations[1:]):
        # Stop each shell short of its neighbor to expose the dark chassis joint.
        ends=[tuple(a[j]+(b[j]-a[j])*t for j in range(5)) for t in [.025,.975]]
        for side in [-1,1]:
            points=[]
            for row,u in [(ends[0],.055),(ends[0],.65),(ends[1],.65),(ends[1],.055)]:
                x,y,z,w,h=row
                points.append((x+side*w*u,y,z+h+.016))
            panel(label+' dorsal armor',points,.026,paint,.008)
            points=[]
            for row,u,v in [(ends[0],.68,.97),(ends[0],1.012,.43),
                            (ends[1],1.012,.43),(ends[1],.68,.97)]:
                x,y,z,w,h=row
                points.append((x+side*w*u,y,z+h*v+.01))
            panel(label+' shoulder bevel armor',points,.025,paint,.008)
            x,y,z,w,h=ends[0]
            if w>.22:
                bolt((x+side*w*.46,y+.025,z+h+.031),radius=.018)


def wing(label, outline, paint='silver', thickness=.07):
    """Thick wing with inset armor following its own outline, not a flat decal."""
    panel(label+' structure',outline,thickness,'dark',.02)
    center=sum((Vector(p) for p in outline),Vector())/len(outline)
    inset=[tuple(center+(Vector(p)-center)*.87+Vector((0,0,thickness*.6))) for p in outline]
    panel(label+' inset armor',inset,.03,paint,.012)
    pipe(label+' leading edge',outline[:3],.018,'steel')
    for p in inset[1:-1]:
        bolt(Vector(p)+Vector((0,0,.022)),radius=.018)


def vents(label, x,y,z, count=6, width=.26, step=.075, slope=0):
    center=(count-1)*step/2
    plate=box(label+' inset',(x,y+center,z+center*slope),(width+.07,count*step+.05,.025),'recess',.012)
    plate.rotation_euler.x=math.atan(slope)
    for i in range(count):
        slat=box(label+' louver',(x,y+i*step,z+i*step*slope+.018),(width,.025,.025),'gunmetal',.004)
        slat.rotation_euler.x=math.atan(slope)


def engine_pod(label,x,y,z,radius=.3,length=1.05,paint='steel',front=False):
    """Longitudinal turbine with separate casings, recessed inlet and aft nozzle."""
    tube(label+' core',(x,y-length/2,z),(x,y+length/2,z),radius*.96,'dark')
    for i in range(3):
        lo=y-length/2+i*length/3+.018
        hi=lo+length/3-.036
        tube(label+' armor band',(x,lo,z),(x,hi,z),radius,paint,r2=radius*.98)
        ring(label+' joint',(x,hi,z),radius*.96,.016,'recess',(0,1,0))
    nozzle(label+' aft',(x,y+length/2+.13,z),(0,1,0),radius*.84,.20,True)
    nozzle(label+' intake',(x,y-length/2-.13,z),(0,-1,0),radius*.78,.12,True)
    # The base Yamato/Nostromo pictures show luminous forward-facing apertures.
    if not front:
        tube(label+' inlet shadow',(x,y-length/2-.104,z),(x,y-length/2-.102,z),radius*.45,'recess',bevel=0)
    for side in [-1,1]:
        box(label+' casing rail',(x+side*radius*.68,y,z+radius*.69),(.055,length*.71,.05),'gunmetal',.009)
        for dy in [-length*.27,length*.27]:
            bolt((x+side*radius*.4,y+dy,z+radius*.92),radius=.02)
    # Interrupted curved cowl tiles and exposed seams replace a plain cylinder.
    for j in range(3):
        lo=y-length*.43+j*length*.29
        hi=lo+length*.23
        for k in range(6):
            a=k*math.tau/6+.065
            b=(k+1)*math.tau/6-.065
            points=[(x+(radius+.014)*math.cos(t),yy,z+(radius+.014)*math.sin(t))
                    for yy in [lo,hi] for t in [a+(b-a)*i/8 for i in range(9)]]
            faces=[(i,i+1,i+10,i+9) for i in range(8)]
            obj=mesh(label+' fitted cowl tile',points,faces,paint,0,True)
            mod=obj.modifiers.new('Cowl thickness','SOLIDIFY'); mod.thickness=.018
    for k in range(8):
        a=k*math.tau/8
        xx=x+radius*.97*math.cos(a); zz=z+radius*.97*math.sin(a)
        tube(label+' rear casing tie',(xx,y+length*.40,zz),(xx,y+length*.56,zz),
             radius*.052,'steel',vertices=8,bevel=.003)
    box(label+' top service recess',(x,y,z+radius+.025),(radius*.62,length*.39,.025),'recess',.009)
    for j in range(4):
        box(label+' top radiator rib',(x,y-length*.13+j*length*.085,z+radius+.043),
            (radius*.52,length*.026,.028),'steel',.004)


def rounded_hull(label, stations, paint='silver', canopy=False):
    """Elliptical longitudinal sections, split into fitted curved armor strips."""
    def sample(j,t):
        neighbors=[stations[min(max(k,0),len(stations)-1)] for k in [j-1,j,j+1,j+2]]
        return tuple(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
                     for a,b,c,d in zip(*neighbors))
    sections=[sample(j,t/6) for j in range(len(stations)-1) for t in range(6)]+[stations[-1]]
    segments=64
    verts=[(x+w*math.cos(i*math.tau/segments),y,z+h*math.sin(i*math.tau/segments))
           for x,y,z,w,h in sections for i in range(segments)]
    faces=[tuple(reversed(range(segments)))]
    for j in range(len(sections)-1):
        faces.extend((j*segments+i,j*segments+(i+1)%segments,
                      (j+1)*segments+(i+1)%segments,(j+1)*segments+i) for i in range(segments))
    faces.append(tuple(range(len(verts)-segments,len(verts))))
    mesh(label+' curved chassis',verts,faces,'dark',.008,True)
    for j in range(len(stations)-1):
        for k in range(8):
            patch=[]
            for row in range(7):
                t=.016+row/6*.968
                x,y,z,w,h=sample(j,t)
                for q in range(9):
                    angle=(k+(q/8)*.97+.015)*math.tau/8
                    if label=='Heavy bulbous fuselage' and j in [1,2,3] and k in [0,3]:
                        # Preserve the upper shoulder shell above a narrow open bay.
                        angle=(.40+q/8*.37) if k==0 else (math.pi-.77+q/8*.37)
                    patch.append((x+(w+.018)*math.cos(angle),y,z+(h+.018)*math.sin(angle)))
            glass=canopy and j in [1,2,3] and k in [1,2]
            faces=[(r*9+i,r*9+i+1,(r+1)*9+i+1,(r+1)*9+i) for r in range(6) for i in range(8)]
            obj=mesh(label+(' canopy glazing' if glass else ' curved armor'),patch,faces,
                     'blueglass' if glass else paint,0,True)
            solid=obj.modifiers.new('Armor thickness','SOLIDIFY'); solid.thickness=.025


def build_bigboy():
    group('Bigboy | rounded armored body')
    rounded_hull('Heavy bulbous fuselage',[(0,-2.45,-.08,.10,.12),(0,-2.05,.0,.65,.35),
        (0,-1.25,.12,1.12,.58),(0,-.2,.19,1.22,.64),(0,.8,.21,.89,.50),
        (0,1.43,.19,.49,.32)],'bluegrey')
    group('Bigboy | bridge and dorsal machinery')
    armored_hull('Raised bridge',[(0,-1.0,.65,.30,.10),(0,-.58,.78,.35,.16),
        (0,.1,.85,.32,.22),(0,.6,.71,.26,.13)],'gunmetal')
    loft('Olive cockpit glazing',[(0,-.88,.80,.19,.04),(0,-.43,1.0,.23,.05),
        (0,.04,1.105,.19,.03)],'oliveglass',.015)
    for s in [-1,1]:
        pipe('Bridge metal rim',[(s*.21,-.9,.86),(s*.26,-.43,1.065),(s*.20,.07,1.16)],.026,'steel')
        pipe('Long nose rail',[(s*.25,-2.23,.20),(s*.56,-1.45,.64),(s*.51,-.66,.76)],.035,'silver')
        vents('Dorsal nose ventilation',s*.31,-1.35,.70,5,.17,slope=.15)
        tube('Nose sensor barrel',(s*.22,-2.36,.04),(s*.22,-2.65,.04),.065,'gunmetal')
        wing('Outrigger swept strut',[(s*.75,.18,.0),(s*1.65,.54,-.12),
            (s*2.12,1.11,-.13),(s*1.83,1.24,-.11),(s*.72,.68,.02)],'gunmetal',.14)
        armored_hull('Outrigger foot',[(s*1.9,.59,-.12,.20,.09),
            (s*1.96,1.1,-.12,.31,.13),(s*1.98,1.39,-.12,.25,.09)],'bluegrey')
        ring('Outrigger socket',(s*1.96,1.05,.025),.14,.045,'steel')
        tube('Socket recess',(s*1.96,1.05,.02),(s*1.96,1.05,.03),.105,'recess')
        engine_pod('Upper rear engine',s*.42,1.3,.66,.27,.9,'gunmetal')
        for y in [-.85,-.5,-.15]:
            bolt((s*.80,y,.65),radius=.029)
    armored_hull('Rear raised equipment deck',[(0,.65,.91,.51,.08),(0,1.34,1.03,.61,.10),
        (0,1.62,1.0,.52,.09)],'bluegrey')
    vents('Aft deck grille',0,.88,1.06,7,.45,slope=.20)


def build_defcom():
    group('Defcom | compact green fuselage')
    armored_hull('Central carapace',[(0,-.78,.06,.23,.12),(0,-.24,.23,.49,.27),
        (0,.65,.25,.51,.26),(0,1.16,.13,.30,.14)],'forest')
    loft('Long dark canopy',[(0,-.66,.25,.14,.025),(0,-.11,.52,.28,.035),
        (0,.50,.55,.25,.028),(0,.79,.43,.17,.025)],'glass')
    for s in [-1,1]:
        pipe('Canopy frame',[(s*.16,-.69,.29),(s*.30,-.1,.57),(s*.27,.5,.59),(s*.18,.82,.45)],.025,'sage')
    group('Defcom | curved scythe wings')
    for s in [-1,1]:
        stations=[(s*.48,.63,.15,.16,.16),(s*.90,.44,.13,.28,.18),
            (s*1.25,.10,.04,.30,.15),(s*1.53,-.37,-.06,.22,.11),
            (s*1.64,-.91,-.17,.12,.07),(s*1.54,-1.40,-.25,.025,.025)]
        armored_hull('Scythe wing',stations,'forest')
        pipe('Scythe leading polished rim',[(s*.80,.44,.29),(s*1.15,.1,.20),
            (s*1.44,-.37,.07),(s*1.59,-.91,-.1),(s*1.54,-1.40,-.22)],.022,'sage')
        for i in range(4):
            y=.47-i*.14
            box('Wing root radiator',(s*.66,y,.33),(.21,.035,.025),'gunmetal',.005)
        wing('Rear shoulder fin',[(s*.31,.60,.40),(s*.62,1.32,.43),
            (s*.93,1.08,.15),(s*.69,.40,.21)],'forest')
        engine_pod('Rear turbine',s*.31,.97,-.08,.16,.55,'gunmetal')
        tube('Wing tip aperture',(s*1.54,-1.4,-.25),(s*1.54,-1.47,-.25),.025,'recess')
    vents('Belly cooling',0,.1,-.05,6,.27)


def build_leonov():
    group('Leonov | split arrow hull')
    armored_hull('Central spine',[(0,-2.0,0,.07,.06),(0,-1.12,.08,.24,.16),
        (0,-.20,.16,.37,.21),(0,.71,.17,.40,.23),(0,1.20,.08,.24,.12)],'silver')
    for s in [-1,1]:
        armored_hull('Long forward fork',[(s*.28,-2.27,-.10,.025,.035),
            (s*.49,-1.49,-.025,.11,.08),(s*.69,-.70,.0,.19,.12),
            (s*.67,.28,.03,.23,.15),(s*.50,.82,.07,.20,.12)],'silver')
        pipe('Fork dark channel',[(s*.29,-2.18,-.056),(s*.50,-1.45,.07),
            (s*.69,-.68,.14),(s*.67,.20,.195)],.019,'gunmetal')
        wing('Outer fork shoulder',[(s*.60,-.83,.09),(s*1.05,-.27,.06),
            (s*.95,.65,.08),(s*.55,.9,.12)],'steel',.12)
        armored_hull('Rear open outrigger',[(s*.62,.45,.08,.16,.09),
            (s*.82,1.12,.14,.15,.10),(s*.87,1.64,.18,.11,.09)],'silver')
        vents('Rear outrigger slots',s*.84,1.10,.258,5,.14,.09)
        engine_pod('Compact aft drive',s*.35,1.06,-.07,.15,.52,'gunmetal')
        for y in [-.50,-.30,-.10]:
            box('Fork segmented plate',(s*.69,y,.19),(.18,.07,.025),'pale',.006)
    armored_hull('Bridge plinth',[(0,-.30,.38,.21,.08),(0,.11,.52,.25,.12),
        (0,.52,.48,.21,.10)],'steel')
    loft('Blue black cockpit',[(0,-.29,.475,.14,.02),(0,.09,.66,.16,.025),
        (0,.38,.625,.15,.025)],'glass')
    for s in [-1,1]:
        tube('Bridge antenna',(s*.20,.44,.56),(s*.27,.61,.91),.014,'steel')


def build_liberator():
    group('Liberator | narrow pointed central hull')
    armored_hull('Needle fuselage',[(0,-2.63,-.11,.018,.018),(0,-1.72,-.02,.13,.07),
        (0,-.77,.10,.25,.16),(0,.19,.22,.31,.23),(0,1.03,.20,.27,.18),
        (0,1.62,.12,.16,.10)],'bluegrey')
    loft('Inset central glazing',[(0,-1.13,.13,.055,.02),(0,-.39,.35,.12,.033),
        (0,.40,.48,.14,.036),(0,1.08,.34,.08,.026)],'blueglass',.009)
    group('Liberator | forward sculpted lateral pods')
    for s in [-1,1]:
        pipe('Glazing fitted rim',[(s*.063,-1.14,.16),(s*.13,-.39,.39),
            (s*.15,.4,.52),(s*.09,1.08,.37)],.015,'silver')
        pipe('Needle inset stripe',[(s*.03,-2.47,-.08),(s*.075,-1.72,.07),
            (s*.17,-.81,.27)],.011,'steel')
        wing('Low swept pod attachment',[(s*.20,-.58,-.06),(s*.91,-1.0,-.18),
            (s*1.54,-.57,-.23),(s*1.25,.23,-.18),(s*.24,.20,.01)],'gunmetal',.08)
        armored_hull('Sculpted broad outer pod',[(s*1.21,-1.12,-.14,.27,.065),
            (s*1.39,-.94,-.11,.43,.13),(s*1.43,-.55,-.12,.48,.17),
            (s*1.32,-.13,-.09,.37,.13),(s*1.08,.14,-.05,.16,.075)],'bluegrey')
        panel('Outer pod split shell',[(s*1.18,-1.13,.0),(s*1.57,-.98,.025),
            (s*1.78,-.60,.005),(s*1.66,-.27,.035),(s*1.40,-.35,.105),
            (s*1.41,-.72,.115)],.025,'silver',.016)
        tube('Pod circular machinery well',(s*1.24,-.58,.065),(s*1.24,-.58,.091),.21,'recess')
        ring('Pod circular machined rim',(s*1.24,-.58,.102),.205,.025,'pale')
        ring('Pod inner bearing',(s*1.24,-.58,.106),.128,.018,'gunmetal')
        tube('Pod hub',(s*1.24,-.58,.09),(s*1.24,-.58,.153),.062,'steel',vertices=12)
        for i in range(8):
            a=i*math.tau/8
            tube('Pod radial mechanism',(s*1.24+.083*math.cos(a),-.58+.083*math.sin(a),.11),
                (s*1.24+.18*math.cos(a),-.58+.18*math.sin(a),.11),.018,'steel',vertices=8)
        pipe('Outer pod recessed perimeter',[(s*1.60,-.97,.035),(s*1.80,-.58,.018),
            (s*1.65,-.24,.036),(s*1.42,-.29,.10)],.013,'recess')
        vents('Pod rear cooling',s*1.22,-.17,.073,4,.16,.053,slope=-.10)
    group('Liberator | open longitudinal engine channels')
    for s in [-1,1]:
        # Separate parallel beams leave the reference's deep open channel visible.
        for x in [.67,1.05]:
            armored_hull('Channel raised edge',[(s*x,-.62,.0,.048,.065),
                (s*x,.28,.15,.055,.095),(s*x,1.39,.25,.065,.105),
                (s*x,1.72,.16,.048,.065)],'bluegrey')
            pipe('Channel silver guide',[(s*x,-.60,.083),(s*x,.30,.258),
                (s*x,1.39,.37),(s*x,1.67,.245)],.017,'silver')
        loft('Deep channel bed',[(s*.86,-.48,-.02,.18,.035),
            (s*.86,.30,.05,.18,.035),(s*.86,1.53,.15,.18,.035)],'recess',.008)
        for j in range(9):
            y=-.32+j*.205; z=.042+(y+.32)*.081
            box('Exposed channel crossmember',(s*.86,y,z+.045),(.29,.043,.042),'gunmetal',.006)
        for dx in [-.067,.067]:
            tube('Long channel actuator',(s*.86+dx,-.32,.11),(s*.86+dx,1.40,.25),.029,'steel')
            tube('Actuator dark sleeve',(s*.86+dx,.73,.195),(s*.86+dx,1.20,.232),.044,'graphite')
        box('Channel aft bridge',(s*.86,1.48,.29),(.49,.10,.11),'steel',.016)
        nozzle('Narrow channel drive',(s*.86,1.84,.15),(0,1,0),.145,.24,True)
        panel('Small outboard rear stabilizer',[(s*1.04,.99,.19),(s*1.29,1.40,.60),
            (s*1.31,1.66,.63),(s*1.06,1.65,.17)],.045,'gunmetal',.014,(s,0,0))
        pipe('Outboard fin edge',[(s*1.04,.99,.19),(s*1.29,1.40,.60),
            (s*1.31,1.66,.63)],.015,'bluegrey')
        vents('Central aft cooling',s*.14,1.10,.377,4,.08,.09,slope=-.24)


def build_nostromo():
    group('Nostromo | broad angular body')
    armored_hull('Broad forward hull',[(0,-2.05,-.10,.22,.10),(0,-1.54,.0,.73,.23),
        (0,-.55,.08,.91,.31),(0,.48,.12,.85,.30),(0,1.21,.08,.53,.19)],'graphite')
    armored_hull('Dorsal central ridge',[(0,-1.8,.20,.17,.04),(0,-.81,.39,.26,.08),
        (0,.14,.48,.22,.09),(0,.77,.36,.21,.08)],'steel')
    loft('Long smoked cockpit',[(0,-1.43,.285,.105,.023),(0,-.74,.49,.17,.03),
        (0,-.10,.57,.15,.025)],'glass')
    group('Nostromo | twin high turbines')
    for s in [-1,1]:
        armored_hull('Engine support shoulder',[(s*.60,-.06,.35,.22,.09),
            (s*.73,.39,.65,.25,.24),(s*.74,1.10,.56,.25,.22)],'gunmetal')
        engine_pod('Large upper turbine',s*.77,.72,.94,.42,1.20,'gunmetal',True)
        wing('Low swept outer wing',[(s*.70,-.32,.03),(s*1.17,.47,-.05),
            (s*1.94,1.36,-.20),(s*1.43,1.27,-.20),(s*.66,.66,-.10)],'graphite',.12)
        panel('Wing root blue panel',[(s*.80,.09,.06),(s*1.09,.46,.015),
            (s*1.28,.84,-.04),(s*.91,.69,.015)],.025,'bluegrey')
        vents('Nose cooling slots',s*.51,-1.01,.387,6,.23,slope=.12)
        pipe('Nose shoulder seam',[(s*.24,-1.86,.075),(s*.60,-1.37,.26),
            (s*.71,-.76,.39)],.018,'silver')
        tube('Nose sensor',(s*.23,-2.03,-.05),(s*.23,-2.14,-.05),.049,'gunmetal')
        for y in [-1.19,-.74,-.29]:
            bolt((s*.39,y,.40 if y<-.9 else .43),radius=.023)


def build_phoenix():
    group('Phoenix | upright capsule')
    # Upright egg profile is deliberately taller than it is wide.
    rounded_hull('Red capsule',[(0,-.91,-.32,.15,.22),(0,-.69,-.08,.38,.53),
        (0,-.18,.21,.52,.83),(0,.36,.30,.48,.99),(0,.69,.21,.27,.72),
        (0,.82,.05,.08,.23)],'red',canopy=True)
    group('Phoenix | large wraparound canopy')
    # Glazing replaces shell panels, so red armor cannot intersect the canopy.
    for s in [-1,1]:
        pipe('Thick canopy frame',[(s*.28,-.69,.31),(s*.38,-.18,.815),
            (s*.36,.36,1.02),(s*.21,.69,.74)],.027,'steel')
        pipe('Lower curved bumper',[(s*.13,-.94,-.29),(s*.34,-.76,-.22),
            (s*.50,-.26,-.23),(s*.47,.24,-.24)],.038,'gunmetal')
        wing('Small lateral paddle',[(s*.34,.26,-.25),(s*.79,.53,-.36),
            (s*.86,.75,-.36),(s*.45,.62,-.22)],'steel',.045)
        panel('Paddle red tip',[(s*.65,.50,-.325),(s*.79,.56,-.325),
            (s*.83,.70,-.325),(s*.69,.65,-.325)],.025,'red')
        engine_pod('Small rear thruster',s*.26,.72,-.30,.13,.37,'gunmetal')
        for y,z in [(-.65,-.13),(-.34,-.11),(.1,-.12),(.40,-.10)]:
            bolt((s*.40,y,z),(s,0,0),.026)
    nozzle('Circular forward sensor',(0,-.955,-.34),(0,-1,0),.18,.16)
    tube('Dark forward lens',(0,-.971,-.34),(0,-.975,-.34),.11,'glass',bevel=0)
    pipe('Canopy central crown seam',[(0,.41,1.26),(0,.65,1.08),(0,.79,.69)],.025,'steel')
    ring('Crown service port',(0,.56,1.12),.075,.016,'gunmetal')


def build_piranha():
    group('Piranha | long needle hull')
    armored_hull('Slender arrow',[(0,-3.1,-.04,.025,.025),(0,-2.26,.015,.20,.065),
        (0,-1.23,.055,.31,.12),(0,-.12,.13,.42,.19),(0,.84,.12,.36,.19),
        (0,1.70,.04,.20,.10)],'silver')
    loft('Dark inset canopy',[(0,-.60,.30,.19,.024),(0,.09,.36,.25,.045),
        (0,.72,.31,.17,.03)],'glass')
    for s in [-1,1]:
        pipe('Long recessed nose channel',[(s*.05,-2.84,.015),(s*.14,-2.18,.085),
            (s*.20,-1.24,.20),(s*.28,-.40,.30)],.018,'gunmetal')
        wing('Swept main wing',[(s*.29,-.42,.0),(s*1.21,.38,-.07),
            (s*1.42,1.05,-.09),(s*.72,.92,-.025),(s*.32,.50,.04)],'bluegrey',.075)
        panel('Wing outer silver strip',[(s*.83,.31,-.01),(s*1.14,.47,-.015),
            (s*1.31,.91,-.025),(s*1.10,.86,-.02)],.028,'silver')
        wing('Aft horizontal stabilizer',[(s*.24,1.0,.11),(s*.79,1.30,.10),
            (s*.96,1.65,.05),(s*.26,1.50,.12)],'steel',.055)
        engine_pod('Slender side engine',s*.43,.80,.08,.14,1.03,'gunmetal')
        vents('Nose radiator',s*.15,-1.83,.16,7,.10,.075,slope=.065)
        panel('Raised tail fin',[(s*.13,.48,.25),(s*.20,1.04,.59),
            (s*.22,1.48,.51),(s*.18,1.34,.22)],.035,'gunmetal',.01,(s,0,0))
        pipe('Canopy edging',[(s*.19,-.59,.34),(s*.26,.09,.42),(s*.17,.72,.36)],.016,'steel')


def build_spearhead():
    group('Spearhead | pointed lower fuselage')
    armored_hull('Recon spear hull',[(0,-2.49,-.20,.025,.025),(0,-1.69,-.055,.27,.13),
        (0,-.77,.09,.44,.19),(0,.02,.17,.41,.23),(0,.58,.16,.23,.18),
        (0,1.08,.13,.12,.10)],'gunmetal')
    loft('Black forward canopy',[(0,-1.95,-.04,.07,.025),(0,-1.16,.23,.22,.035),
        (0,-.39,.37,.25,.035),(0,-.06,.40,.15,.02)],'glass')
    for s in [-1,1]:
        pipe('Spear bright edge',[(s*.04,-2.45,-.16),(s*.29,-1.64,.05),
            (s*.45,-.72,.24),(s*.33,-.18,.38)],.023,'silver')
        panel('Forward cobalt armor',[(s*.06,-1.46,.14),(s*.14,-1.05,.26),
            (s*.12,-.31,.39),(s*.03,-.09,.405)],.025,'cobalt')
        wing('Long fine outrigger',[(s*.30,-.14,.04),(s*.64,.14,.02),
            (s*2.08,1.09,-.13),(s*1.39,.93,-.13),(s*.32,.41,.01)],'gunmetal',.045)
        wing('Lower shoulder plate',[(s*.32,-.65,-.03),(s*.74,-.29,-.09),
            (s*.58,.12,-.04),(s*.28,.27,.04)],'steel',.065)
    group('Spearhead | tall aft engineering tower')
    loft('Inclined tower',[(0,.09,.36,.20,.16),(0,.35,.90,.25,.35),
        (0,.64,1.20,.27,.47),(0,1.10,1.18,.26,.45)],'gunmetal')
    tube('Tower sensor mounting neck',(0,.36,.84),(0,.025,.84),.153,'dark',r2=.173)
    tube('Tower front circular sensor',(0,.025,.84),(0,-.015,.84),.19,'blueglass')
    ring('Sensor dark bezel',(0,-.02,.84),.20,.028,'dark',(0,1,0))
    armored_hull('Cobalt upper horizontal pod',[(0,.06,1.59,.21,.17),
        (0,.43,1.74,.34,.22),(0,1.34,1.74,.32,.22),(0,1.59,1.61,.25,.17)],'cobalt')
    nozzle('High aft exhaust',(0,1.73,1.67),(0,1,0),.24,.30,True)
    for s in [-1,1]:
        pipe('Upper pod polished trim',[(s*.23,.15,1.79),(s*.34,.47,1.96),(s*.30,1.39,1.94)],.022,'steel')
        for y in [.44,.68,.92,1.16]:
            box('Upper pod side vent',(s*.344,y,1.69),(.025,.10,.13),'recess',.008)
        tube('Tower hydraulic linkage',(s*.25,.31,.29),(s*.30,.72,1.37),.04,'steel')
        for y in [.39,.59,.79]:
            bolt((s*.28,y,1.27),(s,0,0),.028)
    engine_pod('Lower aft drive',0,.98,.0,.16,.48,'gunmetal')


def build_vengeance():
    group('Vengeance | forward wedge and layered cheeks')
    armored_hull('Forward wedge',[(0,-2.20,-.20,.12,.09),(0,-1.60,-.04,.34,.17),
        (0,-.79,.14,.56,.31),(0,.08,.31,.57,.38),(0,.90,.27,.44,.28)],'sage')
    loft('Faceted teal cockpit',[(0,-1.16,.26,.23,.04),(0,-.46,.58,.34,.07),
        (0,.04,.74,.28,.07),(0,.40,.64,.20,.035)],'glass')
    for s in [-1,1]:
        pipe('Heavy cockpit frame',[(s*.24,-1.15,.32),(s*.36,-.45,.67),
            (s*.30,.04,.82),(s*.21,.43,.69)],.032,'steel')
        pipe('Canopy crossbar',[(0,-.51,.69),(s*.36,-.45,.67)],.022,'steel')
        armored_hull('Forward cheek',[(s*.27,-1.73,-.10,.09,.07),
            (s*.50,-1.03,.01,.14,.12),(s*.72,-.29,.17,.19,.19),
            (s*.69,.58,.23,.18,.18)],'sage')
        tube('Cheek recessed bore',(s*.35,-1.68,-.11),(s*.35,-1.81,-.11),.066,'recess')
    group('Vengeance | four outboard turbine blocks')
    for s in [-1,1]:
        armored_hull('Tall engine shoulder',[(s*.78,-.22,.31,.25,.31),
            (s*.88,.34,.40,.32,.45),(s*.86,.93,.36,.28,.37)],'gunmetal')
        engine_pod('Upper outboard turbine',s*1.00,.47,.77,.32,1.06,'sage')
        engine_pod('Lower outboard turbine',s*1.05,.67,-.13,.28,.93,'sage')
        panel('Vertical turbine brace',[(s*1.27,.0,-.10),(s*1.32,.0,.71),
            (s*1.30,.77,.82),(s*1.28,1.08,-.09)],.07,'steel',.02,(s,0,0))
        for z in [.07,.21,.35,.49]:
            box('Outer brace cooling gap',(s*1.326,.42,z),(.024,.33,.055),'recess',.008)
        pipe('Shoulder curved supply line',[(s*.54,.33,.53),(s*.72,.82,.91),(s*.96,.94,1.03)],.037,'gunmetal')
        vents('Dorsal aft slits',s*.25,.47,.665,5,.14,slope=-.17)
    tube('Forward nose aperture',(0,-2.21,-.19),(0,-2.26,-.19),.07,'recess')


def build_yamato():
    group('Yamato | short stepped transport hull')
    armored_hull('Blunt nose and long chassis',[(0,-1.53,-.10,.26,.21),(0,-1.12,.0,.34,.28),
        (0,-.51,.21,.37,.34),(0,.17,.37,.34,.29),(0,.94,.34,.27,.20),
        (0,1.38,.29,.21,.14)],'sage')
    panel('Blunt front inset',[(-.17,-1.555,-.23),(.17,-1.555,-.23),
        (.19,-1.555,.035),(-.19,-1.555,.035)],.025,'gunmetal',.015,(0,-1,0))
    loft('Stepped dark cockpit',[(0,-1.01,.31,.22,.028),(0,-.50,.59,.25,.04),
        (0,-.13,.69,.23,.035)],'glass')
    for s in [-1,1]:
        pipe('Stepped cockpit rim',[(s*.23,-1.02,.36),(s*.27,-.49,.65),(s*.24,-.12,.74)],.028,'steel')
        wing('Upper engine mounting yoke',[(s*.26,.04,.39),(s*.91,.30,.50),
            (s*1.10,.78,.48),(s*.32,.98,.39)],'gunmetal',.17)
        engine_pod('Large upper drive pod',s*.92,.58,.70,.35,1.04,'sage',True)
        ring('Blue upper drive band',(s*.92,.62,.70),.354,.028,'cobalt',(0,1,0))
        tube('Lower pod support',(s*.21,-.41,-.14),(s*.60,-.28,-.32),.095,'gunmetal')
        engine_pod('Small low drive pod',s*.62,-.08,-.35,.19,.51,'sage',True)
        ring('Small drive blue band',(s*.62,-.01,-.35),.194,.016,'cobalt',(0,1,0))
        vents('Long aft radiator',s*.13,.43,.63,7,.12,.10,slope=-.16)
        for y,z in [(-1.20,.22),(-.67,.48),(.18,.70)]:
            bolt((s*.21,y,z),radius=.022)
    pipe('Rear dorsal rail',[(0,.23,.71),(0,.87,.59),(0,1.38,.45)],.031,'steel')


def service_bay(label, side, x, y, z, length, height):
    """Open side equipment rack, with a dark backing and separate fitted ribs."""
    box(label+' shadow',(side*x,y,z),(.026,length,height),'recess',.012)
    for dz in [-height*.5,height*.5]:
        tube(label+' edge rail',(side*(x+.023),y-length*.5,z+dz),
            (side*(x+.023),y+length*.5,z+dz),.016,'steel',vertices=12)
    for i in range(5):
        yy=y-length*.42+i*length*.21
        box(label+' rib',(side*(x+.029),yy,z),(.045,.026,height*.90),'gunmetal',.004)
        box(label+' inset unit',(side*(x+.025),yy+length*.065,z),
            (.027,length*.105,height*.45),'steel',.005)
    pipe(label+' coolant line',[(side*(x+.055),y-length*.42,z-height*.27),
        (side*(x+.055),y+length*.35,z-height*.27),
        (side*(x+.055),y+length*.43,z)],.012,'copper')


def reference_details(name):
    """Ship-specific visible assemblies. Unresolved small construction is inferred."""
    group(name+' | reference detail assemblies')
    if name=='Aegis':
        for s in [-1,1]:
            for y,z in [(-.68,1.17),(-.36,1.40),(-.02,1.56)]:
                box('Neck exposed control block',(s*.30,y,z),(.10,.16,.10),'gunmetal',.012)
                for dy in [-.043,0,.043]:
                    box('Neck cooling rib',(s*.355,y+dy,z),(.017,.013,.10),'steel',.003)
            pipe('Neck bundled return',[(s*.32,-.87,.89),(s*.36,-.63,1.16),
                (s*.35,-.19,1.51),(s*.32,.35,1.62)],.025,'dark')
            pipe('Neck copper hydraulic line',[(s*.27,-.85,.91),(s*.29,-.58,1.23),
                (s*.29,-.16,1.54),(s*.26,.33,1.65)],.012,'copper')
            engine_pod('Lower engineering service pod',s*.74,.31,-.31,.18,.47,'graphite')
            for finger in [-1,1]:
                tube('Green manipulator tip',(s*.81+finger*.08,-3.31,-.34),
                    (s*.81+finger*.025,-3.35,-.33),.036,'green')
            for z in [.67,.93,1.19]:
                tube('Front cheek hinge',(s*.57,-.14,z),(s*.57,-.14,z+.14),.044,'gunmetal')
            vents('Nose broad cooling bank',s*.31,-2.25,.472,6,.10,.060,slope=.45)
        for a in [-130,-90,-50,0,50,90,130]:
            angle=math.radians(a)
            def shell(da,z):
                return (math.sin(angle+da)*1.078,.85+math.cos(angle+da)*1.078,z)
            pipe('Engineering double seam',[shell(-.19,.15),shell(-.19,1.65),
                shell(.19,1.65)],.009,'gunmetal')
            for z in [.12,1.61]:
                p=Vector(shell(0,z)); n=Vector((math.sin(angle),math.cos(angle),0))
                tube('Engineering access cap',p,p+n*.026,.055,'graphite',vertices=12)
        for i in range(12):
            a=i*math.tau/12
            x,y=math.cos(a)*.40,.86+math.sin(a)*.40
            tube('Emitter ring recessed pin',(x,y,2.32),(x,y,2.39),.018,'steel',vertices=10)
    elif name=='Goliath':
        for s in [-1,1]:
            # Follow the changing arm tangent so ports stay fitted to the skin.
            for i in range(23):
                t=1.15+i*.235
                x,y,z,w,h=arm_station(t)
                p=arm_station(t-.005);q=arm_station(t+.005)
                tangent=Vector((q[0]-p[0],q[1]-p[1],0)).normalized()
                across=Vector((-tangent.y,tangent.x,0))
                center=Vector((s*(x+across.x*w*.965),y+across.y*w*.965,z))
                normal=Vector((s*across.x,across.y,0))
                tube('Arm flank dark port',center-normal*.018,center+normal*.012,.038,'recess',vertices=12)
                if i%3==0:
                    tube('Arm inset pale insert',center+normal*.012,center+normal*.017,.018,'pale',vertices=8)
            for offset in [-.83,.77]:
                points=[]
                for i in range(75):
                    t=.9+i*6.4/74; x,y,z,w,h=arm_station(t)
                    p=arm_station(t-.005);q=arm_station(t+.005)
                    tangent=Vector((q[0]-p[0],q[1]-p[1],0)).normalized()
                    across=Vector((-tangent.y,tangent.x,0))
                    points.append((s*(x+across.x*w*offset),y+across.y*w*offset,z+h*.63))
                pipe('Layered arm edge bead',points,.012,'pale')
            service_bay('Aft shoulder machinery',s,.50,.81,.24,.61,.19)
            vents('Raised shoulder cooling rack',s*.49,.44,.472,5,.13,.07,slope=.045)
            pipe('Shoulder return pipe',[(s*.38,1.32,.35),(s*.54,1.14,.32),
                (s*.67,.92,.25),(s*.83,.88,.20)],.023,'gunmetal')
            for j in range(4):
                box('Rear spine equipment',(s*.21,1.54+j*.14,.56-j*.025),
                    (.095,.075,.049),'gunmetal',.009)
    elif name=='Bigboy':
        for s in [-1,1]:
            # The catalogue shows a long dark machinery break along each flank.
            for j in range(11):
                y=-1.52+j*.14
                width=1.12+(y+1.25)*.10 if y>=-1.25 else 1.12+(y+1.25)*.55
                z=.22+(y+1.52)*.09
                box('Flank exposed module',(s*(width*.97+.016),y,z),(.095,.09,.17),'gunmetal',.012)
                box('Flank module silver cap',(s*(width*.97+.065),y,z+.05),(.018,.066,.05),'steel',.004)
            pipe('Flank silver armor lip',[(s*.83,-1.64,.39),(s*1.09,-1.19,.39),
                (s*1.22,-.23,.39),(s*.98,.61,.37)],.026,'steel')
            for y,z in [(-1.52,.55),(-1.27,.65),(-1.02,.73)]:
                box('Raised dorsal equipment pod',(s*.46,y,z),(.21,.19,.10),'graphite',.023)
                box('Dorsal pod access plate',(s*.46,y,z+.055),(.13,.12,.019),'steel',.006)
            for j in range(5):
                x=.99+j*.17; y=.59+j*.085
                obj=box('Outrigger articulated clamp',(s*x,y,.014),(.085,.27,.052),'steel',.009)
                obj.rotation_euler.z=-s*.45
            tube('Outrigger piston',(s*.97,.66,-.14),(s*1.71,1.02,-.18),.043,'dark')
            tube('Outrigger piston rod',(s*1.39,.87,-.17),(s*1.81,1.10,-.18),.026,'steel')
            ring('Foot socket inner bearing',(s*1.96,1.05,.038),.088,.018,'gunmetal')
        box('Bridge rear instrument housing',(0,.43,.93),(.32,.24,.20),'graphite',.035)
        vents('Bridge aft instrument radiator',0,.34,1.04,4,.23,.055)
    elif name=='Defcom':
        for s in [-1,1]:
            panel('Overlapping shoulder scute',[(s*.42,.20,.41),(s*.71,.05,.37),
                (s*.92,.29,.32),(s*.69,.72,.34),(s*.47,.71,.44)],.043,'sage',.018)
            vents('Shoulder exposed radiator',s*.72,.19,.376,5,.15,.065,slope=-.10)
            pipe('Scythe internal seam',[(s*.89,.35,.316),(s*1.23,.04,.206),
                (s*1.51,-.43,.056),(s*1.61,-.96,-.088)],.012,'recess')
            pipe('Scythe lower edge',[(s*.91,.43,.01),(s*1.27,.07,-.07),
                (s*1.53,-.40,-.15),(s*1.63,-.94,-.23)],.019,'gunmetal')
            service_bay('Rear fuselage mechanics',s,.50,.57,.17,.48,.12)
            for y in [-.12,.06,.24]:
                box('Green shoulder latch',(s*.40,y,.505),(.07,.073,.026),'steel',.006)
    elif name=='Leonov':
        for s in [-1,1]:
            pipe('Fork second silver rail',[(s*.32,-2.17,-.05),(s*.57,-1.46,.058),
                (s*.81,-.67,.125),(s*.83,.22,.16)],.018,'pale')
            pipe('Fork dark inset edge',[(s*.29,-2.17,-.055),(s*.43,-1.46,.075),
                (s*.55,-.67,.14),(s*.49,.18,.20)],.024,'recess')
            service_bay('Fork flank mechanics',s,.895,-.08,.07,.66,.105)
            for j in range(7):
                box('Open fork channel rung',(s*.47,-.56+j*.115,.06),(.21,.035,.038),'gunmetal',.005)
            panel('Shoulder recessed hatch',[(s*.81,-.36,.165),(s*.98,-.23,.16),
                (s*.87,.37,.17),(s*.75,.29,.18)],.022,'recess',.009)
            tube('Rear outrigger access well',(s*.81,1.13,.251),(s*.81,1.13,.27),.065,'recess',vertices=16)
            ring('Rear access bezel',(s*.81,1.13,.28),.065,.013,'steel')
            box('Bridge instrument pack',(s*.23,.23,.63),(.08,.20,.10),'gunmetal',.012)
    elif name=='Nostromo':
        for s in [-1,1]:
            service_bay('Nose lateral equipment',s,.922,-.47,.09,.52,.21)
            panel('Layered nose cheek',[(s*.27,-1.99,-.09),(s*.64,-1.47,.04),
                (s*.79,-.68,.11),(s*.68,-.83,-.17),(s*.33,-1.81,-.20)],
                .032,'gunmetal',.012,(s,0,.4))
            pipe('Cheek engraved division',[(s*.41,-1.74,.014),(s*.68,-1.26,.17),
                (s*.80,-.77,.22)],.013,'recess')
            for j in range(4):
                y=-1.28+j*.28
                panel('Shoulder segmented access plate',[(s*.30,y,.30+j*.033),
                    (s*.45,y+.03,.32+j*.033),(s*.45,y+.19,.34+j*.033),
                    (s*.30,y+.17,.32+j*.033)],.028,'graphite',.009)
            pipe('Engine support feed',[(s*.75,.18,.41),(s*.98,.32,.52),
                (s*1.05,.54,.67)],.032,'steel')
    elif name=='Phoenix':
        for s in [-1,1]:
            pipe('Capsule silver lower seam',[(s*.21,-.87,-.28),(s*.39,-.63,-.15),
                (s*.50,-.17,.0),(s*.47,.35,.05),(s*.32,.68,.02)],.018,'sage')
            pipe('Capsule side recessed seam',[(s*.38,-.65,.02),(s*.46,-.24,.22),
                (s*.45,.20,.30),(s*.34,.59,.31)],.012,'recess')
            for j in range(5):
                box('Capsule lower side radiator',(s*.486,-.18+j*.085,-.13),
                    (.019,.04,.08),'gunmetal',.006)
            tube('Lower sensor attachment',(s*.16,-.91,-.45),(s*.20,-.77,-.43),.028,'steel')
            panel('Small capsule identity flash',[(s*.327,-.765,-.14),(s*.38,-.68,-.075),
                (s*.40,-.62,-.17),(s*.355,-.71,-.23)],.012,'pale',.004,(s,-1,0))
        ring('Forward sensor concentric bezel',(0,-.985,-.34),.13,.013,'sage',(0,1,0))
        pipe('Canopy upper transverse frame',[(.506*math.cos(a),.36,.30+1.016*math.sin(a))
            for a in [math.pi/4+i*math.pi/64 for i in range(33)]],.017,'sage')
    elif name=='Piranha':
        for s in [-1,1]:
            pipe('Long exposed shoulder rail',[(s*.14,-2.37,.07),(s*.29,-1.36,.20),
                (s*.41,-.26,.30),(s*.39,.74,.33)],.024,'steel')
            for j in range(11):
                y=-2.02+j*.118; x=.205+j*.010; z=.13+j*.010
                tube('Fine nose transverse rib',(s*(x-.038),y,z),(s*(x+.043),y+.015,z-.015),
                    .010,'pale',vertices=8,bevel=.002)
            service_bay('Long cockpit flank channel',s,.421,.18,.13,.86,.12)
            panel('Main wing engraved inset',[(s*.55,.08,.052),(s*1.12,.47,.005),
                (s*1.24,.85,-.01),(s*.78,.64,.042)],.018,'gunmetal',.005)
            for j in range(5):
                obj=box('Wing root cooling vane',(s*(.63+j*.055),.44+j*.032,.065),
                    (.028,.24,.025),'steel',.004)
                obj.rotation_euler.z=s*.4
            pipe('Aft amber supply cable',[(s*.32,.81,.30),(s*.44,1.05,.23),
                (s*.35,1.46,.20)],.012,'copper')
    elif name=='Spearhead':
        for s in [-1,1]:
            service_bay('Tower exposed equipment rack',s,.282,.71,.94,.65,.46)
            pipe('Tower forward edge frame',[(s*.21,.08,.48),(s*.27,.31,1.12),
                (s*.29,.57,1.56)],.021,'steel')
            for j in range(6):
                box('Tower front stepped instruments',(s*.13,.22+j*.04,.78+j*.10),
                    (.09,.065,.055),'dark',.008)
            for j in range(3):
                y=.47+j*.22
                tube('Tower diagonal brace',(s*.34,y,.71),(s*.34,y+.17,1.16),.017,'steel')
            pipe('Tower copper feed',[(s*.32,.34,.40),(s*.37,.49,.62),
                (s*.37,.97,1.37),(s*.29,1.12,1.48)],.022,'copper')
            tube('Tower lower linkage sleeve',(s*.27,.36,.42),(s*.30,.49,.76),.062,'dark')
            panel('Cobalt upper service hatch',[(s*.10,.64,1.992),(s*.20,.66,1.992),
                (s*.20,1.02,1.992),(s*.10,1.04,1.992)],.016,'bluegrey',.006)
            tube('Orange shoulder sensor',(s*.48,-.15,.10),(s*.48,-.22,.10),.047,'copper')
            pipe('Outrigger thin joint line',[(s*.66,.22,.04),(s*1.17,.57,-.04),
                (s*1.78,.96,-.11)],.009,'steel')
        vents('Forward spine small slits',0,-2.0,-.005,6,.075,.07,slope=.35)
    elif name in {'Vengeance','Yamato'}:
        for s in [-1,1]:
            if name=='Vengeance':
                service_bay('Vertical engine shoulder rack',s,1.315,.54,.31,.62,.52)
                pipe('Cheek inset silver contour',[(s*.28,-1.64,-.04),(s*.48,-1.04,.115),
                    (s*.65,-.42,.34),(s*.63,.24,.45)],.017,'steel')
                for j in range(4):
                    box('Forward cheek raised segment',(s*(.46+j*.054),-1.12+j*.19,.135+j*.05),
                        (.10,.11,.033),'gunmetal',.006)
                panel('Cockpit flanking equipment mount',[(s*.31,-.57,.66),(s*.48,-.46,.65),
                    (s*.46,-.14,.76),(s*.30,-.19,.77)],.027,'gunmetal',.012)
                vents('Cockpit flanking slots',s*.40,-.43,.717,4,.075,.06,slope=.24)
                pipe('Lower turbine hardline',[(s*.89,.0,-.34),(s*.87,.51,-.40),
                    (s*.80,.94,-.20)],.019,'copper')
            else:
                service_bay('Long aft chassis flank',s,.29,.69,.34,.68,.20)
                panel('Nose stepped cheek inset',[(s*.28,-1.37,.06),(s*.35,-.94,.23),
                    (s*.38,-.55,.42),(s*.36,-.45,.20),(s*.29,-1.05,-.10)],
                    .022,'gunmetal',.010,(s,0,.2))
                pipe('Nose fine contour',[(s*.22,-1.48,.11),(s*.28,-1.10,.29),
                    (s*.30,-.54,.52)],.014,'steel')
                pipe('Upper drive supply line',[(s*.31,.27,.62),(s*.49,.39,.70),
                    (s*.60,.73,.69)],.026,'gunmetal')
                for j in range(3):
                    box('Engine yoke coupling',(s*(.43+j*.12),.58,.57),(.063,.27,.052),'steel',.008)
                box('Nose corner navigation lens',(s*.22,-1.51,.015),(.052,.020,.035),'blueglass',.005)


BUILDERS = dict(zip(NAMES,[build_aegis,build_goliath,build_bigboy,build_defcom,
    build_leonov,build_liberator,build_nostromo,build_phoenix,build_piranha,
    build_spearhead,build_vengeance,build_yamato]))


def point_at(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def setup(name, draft=False):
    global PARTS, M
    PARTS=[]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.world=bpy.data.worlds.new('Neutral studio environment')
    M={key:material(label,color,metal,rough,emission) for key,label,color,metal,rough,emission in [
        ('steel','Brushed titanium',(.18,.21,.23),.76,.32,0),
        ('silver','Satin silver armor',(.30,.33,.35),.72,.37,0),
        ('pale','Pale metal details',(.36,.39,.40),.65,.3,0),
        ('dark','Dark mechanical structure',(.024,.033,.039),.7,.40,0),
        ('graphite','Graphite nose armor',(.045,.057,.065),.75,.36,0),
        ('gunmetal','Gunmetal',(.11,.13,.14),.8,.34,0),
        ('recess','Deep panel recess',(.006,.009,.011),.25,.48,0),
        ('green','Aegis green enamel',(.024,.085,.022),.53,.35,0),
        ('bluegrey','Blue grey armor',(.12,.18,.29),.67,.34,0),
        ('forest','Defcom green enamel',(.027,.095,.033),.60,.33,0),
        ('sage','Muted green grey armor',(.12,.21,.18),.70,.34,0),
        ('cobalt','Cobalt enamel',(.015,.075,.31),.55,.33,0),
        ('copper','Muted copper fittings',(.22,.095,.035),.75,.36,0),
        ('red','Phoenix red enamel',(.28,.017,.021),.50,.33,0),
        ('blueglass','Blue cockpit glazing',(.075,.19,.34),.65,.19,0),
        ('oliveglass','Olive bridge glazing',(.17,.18,.066),.64,.21,0),
        ('glass','Dark sensor glass',(.095,.04,.016) if name=='Goliath' else (.018,.055,.068),.62,.21,0),
        ('light','Green reactor lens' if name=='Aegis' else 'Ion blue',
         (.13,.72,.025) if name=='Aegis' else (.10,.39,.72),.35,.22,1.7) ]}
    BUILDERS[name]()
    reference_details(name)
    if name not in {'Aegis','Goliath','Phoenix'}:
        # Keep glazing and its frame above the fitted metal armor shells.
        canopy_names=('Long dark canopy','Canopy frame','Blue black cockpit',
            'Long blue canopy','Long smoked cockpit','Dark inset canopy','Canopy edging',
            'Black forward canopy','Faceted teal cockpit','Heavy cockpit frame',
            'Canopy crossbar','Stepped dark cockpit','Stepped cockpit rim')
        for obj in list(PARTS):
            if obj.name.startswith(canopy_names):
                obj.location.z+=.07
                if obj.data.materials[0] in [M['glass'],M['blueglass']]:
                    # A fitted dark seat connects the raised glazing to the hull.
                    # Loft vertices repeat the same eight-point section profile.
                    verts=[]
                    for i,v in enumerate(obj.data.vertices):
                        p=v.co+obj.location
                        p.x*=.98
                        p.z-=.023 if i%8 in [0,1,2,7] else .17
                        verts.append(tuple(p))
                    mesh(obj.name+' mounting recess',verts,
                         [tuple(p.vertices) for p in obj.data.polygons],'recess',.006)
    root=bpy.data.objects.new(name,None)
    scene.collection.objects.link(root)
    root['forward_axis']='-Y, Z up'
    root['reference_status']='Base catalogue appearance; engineering references and reconstruction notes in README.'
    root['inferred_geometry']='Underside, hidden joints, exact panel depths and small fasteners.'
    for obj in PARTS:
        obj.parent=root
    bpy.context.view_layer.update()
    bounds=[obj.matrix_world @ Vector(p) for obj in PARTS for p in obj.bound_box]
    low=Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    center=(low+high)/2
    extent=max(high-low)
    scene.render.engine='CYCLES'
    if '--gpu' in sys.argv:
        prefs=bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type='OPTIX'
        prefs.get_devices()
        for device in prefs.devices:
            device.use=device.type=='OPTIX'
        if any(device.use for device in prefs.devices):
            scene.cycles.device='GPU'
    scene.cycles.samples=20 if draft else 64
    scene.cycles.use_denoising=True
    scene.render.resolution_x=1000 if draft else 1600
    scene.render.resolution_y=900 if draft else 1440
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=True
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value=(.24,.28,.34,1)
    bg.inputs[1].default_value=.45
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    group('Studio | cameras and lights')
    cameras={}
    views={'perspective':(7,-10,10) if name=='Aegis' else ((10,-6,7) if name=='Goliath' else (7,-10,7)),
           'rear':(-7,10,5),'top':(0,0,15),'side':(15,0,0),'front':(0,-15,0)}
    for view,offset in views.items():
        data=bpy.data.cameras.new(name+' '+view)
        obj=bpy.data.objects.new(name+' '+view,data)
        GROUP.objects.link(obj)
        obj.location=center+Vector(offset)
        point_at(obj,center)
        data.type='ORTHO'
        data.ortho_scale=extent*(1.15 if name=='Goliath' else 1.28)
        if name not in {'Aegis','Goliath'}:
            # Fit the actual projected corners, including asymmetric long wings.
            inverse=obj.rotation_euler.to_quaternion().inverted()
            projected=[inverse @ (p-center) for p in bounds]
            aspect=scene.render.resolution_x/scene.render.resolution_y
            data.ortho_scale=max(max(abs(p.y)*2*aspect for p in projected),
                                max(abs(p.x)*2 for p in projected))*1.12
        cameras[view]=obj
    for label,loc,power,size,color in [
        ('Large soft key',(-4,-6,9),1500,7,(.92,.96,1)),
        ('Soft fill',(5,-3,4),1150,6,(.82,.90,1)),
        ('Aft rim',(2,6,7),1900,5,(1,.93,.82)),
        ('Lower fill',(-3,0,-5),650,5,(.65,.77,1))]:
        data=bpy.data.lights.new(label,'AREA'); data.energy=power; data.size=size; data.color=color
        obj=bpy.data.objects.new(label,data); GROUP.objects.link(obj); obj.location=loc; point_at(obj,center)
    scene.camera=cameras['perspective']
    # Pack source images into the .blend. Hidden image empties are available
    # from the Outliner for inspection without needing D: on another machine.
    group('References | hidden, enable for comparison')
    for path in sorted((HERE/'references').glob(name.lower()+'*')):
        if path.suffix.lower() not in {'.png','.jpg','.webp'}:
            continue
        img=bpy.data.images.load(str(path)); img.pack()
        obj=bpy.data.objects.new(path.stem,None); obj.empty_display_type='IMAGE'; obj.data=img
        obj.empty_display_size=4; obj.location=(7,0,1); GROUP.objects.link(obj); obj.hide_render=True
    GROUP.hide_viewport=True
    notes=bpy.data.texts.new('READ ME - reference study')
    notes.write(name+' base hull. Forward -Y; Z up.\n'
        'Collections separate the editable ship assemblies, studio and packed references.\n'
        'Five named orthographic cameras are available. F12 renders the current camera.\n'
        'Reference pictures guided the visible forms. Undersides, internal construction,\n'
        'panel depths and fine fasteners are reconstructed; see the accompanying README.\n'
        'These are review models, with no game integration or production optimization.\n')
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                s=area.spaces.active
                s.shading.type='MATERIAL'
                s.overlay.show_floor=False
                s.overlay.show_axis_x=False; s.overlay.show_axis_y=False
                s.region_3d.view_location=center
                s.region_3d.view_distance=extent*1.55
                s.region_3d.view_rotation=cameras['perspective'].rotation_euler.to_quaternion()
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True); bpy.context.view_layer.objects.active=root
    for obj in scene.objects:
        if obj.type in {'LIGHT','CAMERA'}:
            obj.hide_set(True)
    return cameras,root


def run():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    requested={arg for arg in args if not arg.startswith('--')}
    unknown=requested-set(NAMES)
    if unknown:
        raise ValueError('Unknown ships: '+', '.join(sorted(unknown)))
    names=[name for name in NAMES if not requested or name in requested]
    draft='--draft' in args
    for directory in ['models','previews']:
        (HERE/directory).mkdir(exist_ok=True)
    stats={}
    stats_path=HERE/'build-stats.json'
    if stats_path.exists():
        previous=json.loads(stats_path.read_text())
        if isinstance(previous,dict):
            stats=previous
    for name in names:
        cameras,root=setup(name,draft)
        slug=name.lower()
        bpy.context.preferences.filepaths.save_version=0
        bpy.context.scene.render.filepath=str(HERE/'previews'/(slug+'.png'))
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'models'/(slug+'.blend')),compress=True)
        stats[name]={'mesh_components':len(PARTS),'base_faces':sum(len(o.data.polygons) for o in PARTS),
            'draft':draft,'views':list(cameras)}
        for view,camera in cameras.items():
            if draft and view not in ['perspective','top']:
                continue
            bpy.context.scene.camera=camera
            filename=slug+('' if view=='perspective' else '-'+view)+'.png'
            bpy.context.scene.render.filepath=str(HERE/'previews'/filename)
            bpy.ops.render.render(write_still=True)
        # Preserve the other ship's result if separate builds run concurrently.
        current=json.loads(stats_path.read_text()) if stats_path.exists() else {}
        if not isinstance(current,dict):
            current={}
        current[name]=stats[name]
        stats_path.write_text(json.dumps(current,indent=2)+'\n')
        print('COMPLETE',name,stats[name],flush=True)


if __name__=='__main__':
    run()
