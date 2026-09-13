"""Individually authored Aegis and Goliath reference studies for Blender 5.2.

blender --background --factory-startup --python build_models.py -- [Aegis|Goliath] [--draft]
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


def nozzle(name, center, axis, radius, length):
    c = Vector(center)
    v = Vector(axis).normalized()
    tube(name+' housing',c-v*length,c,radius*1.1,'dark',r2=radius)
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
        ('glass','Dark sensor glass',(.018,.055,.068) if name=='Aegis' else (.095,.04,.016),.62,.21,0),
        ('light','Green reactor lens' if name=='Aegis' else 'Ion blue',
         (.13,.72,.025) if name=='Aegis' else (.10,.39,.72),.35,.22,1.7) ]}
    (build_aegis if name=='Aegis' else build_goliath)()
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
    views={'perspective':(7,-10,10) if name=='Aegis' else (10,-6,7),
           'rear':(-7,10,5),'top':(0,0,15),'side':(15,0,0),'front':(0,-15,0)}
    for view,offset in views.items():
        data=bpy.data.cameras.new(name+' '+view)
        obj=bpy.data.objects.new(name+' '+view,data)
        GROUP.objects.link(obj)
        obj.location=center+Vector(offset)
        point_at(obj,center)
        data.type='ORTHO'
        data.ortho_scale=extent*(1.28 if name=='Aegis' else 1.15)
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
    names=[name for name in ['Aegis','Goliath'] if not requested or name in requested]
    if not names:
        raise ValueError('Choose Aegis or Goliath')
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
