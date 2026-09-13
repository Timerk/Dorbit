"""Build the review collection with Blender 5.2. Run from any directory.

blender --background --factory-startup --python build_models.py -- [ship names]
Geometry is authored from the linked reference images, with inferred undersides.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, Quaternion

HERE = Path(__file__).resolve().parent
ROSTER = json.loads((HERE / 'roster.json').read_text(encoding='utf-8'))
MODELS = HERE / 'models'
PREVIEWS = HERE / 'previews'
MODELS.mkdir(exist_ok=True)
PREVIEWS.mkdir(exist_ok=True)
PARTS = []
M = {}

def material(name, color, metal=0.65, rough=0.32, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = rough
    if emission:
        bs.inputs['Emission Color'].default_value = (*color, 1)
        bs.inputs['Emission Strength'].default_value = emission
    return mat

def finish(obj, name, mat='hull', bevel=0):
    obj.name = name
    obj.data.materials.append(M[mat])
    PARTS.append(obj)
    if bevel:
        mod = obj.modifiers.new('Machined edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
    return obj

def mesh(name, verts, faces, mat='hull', bevel=0.025):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    # Recalculate normals for manually authored mirrored components.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    return finish(obj, name, mat, bevel)

def box(name, loc, size, mat='hull', bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)

def loft(name, sections, mat='hull', x=0):
    # Each station describes y, half-width, center-height, half-height.
    verts=[]
    for y,w,z,h in sections:
        for a,b in [(-.65,1),(.65,1),(1,.4),(1,-.4),(.65,-1),(-.65,-1),(-1,-.4),(-1,.4)]:
            verts.append((x+a*w,y,z+b*h))
    faces=[tuple(range(7,-1,-1))]
    for j in range(len(sections)-1):
        for k in range(8):
            faces.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
    faces.append(tuple(range(len(verts)-8,len(verts))))
    return mesh(name,verts,faces,mat)

def body(length=5, width=.7, height=.4, y=0, z=0, mat='hull', x=0):
    obj=loft('Armored fuselage',[(y-length*.52,width*.18,z-.05,height*.3),(y-length*.27,width*.82,z,height*.8),(y+length*.12,width,z,height),(y+length*.43,width*.7,z,height*.75),(y+length*.5,width*.5,z,height*.55)],mat,x)
    for side in [-1,1]:
        pts=[(x+side*width*.68,y-length*.22),(x+side*width*.87,y+length*.08),(x+side*width*.62,y+length*.32),(x+side*width*.48,y+length*.28)]
        plate('Shoulder armor seam',pts,z+height*.62,.035,'dark')
        if length>3:
            for i in range(3):
                box('Aft armor louver',(x+side*width*.43,y+length*(.19+i*.045),z+height*.93),(.18*width,.045,.04),'dark',.009)
    return obj

def plate(name, points, z=0, thick=.15, mat='hull'):
    n=len(points)
    verts=[(x,y,z-thick/2) for x,y in points]+[(x,y,z+thick/2) for x,y in points]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,verts,faces,mat)

def wings(points,z=0,thick=.18,mat='hull', inset=True):
    for side in [-1,1]:
        pts=[(x*side,y) for x,y in points]
        plate('Port wing' if side<0 else 'Starboard wing',pts,z,thick,mat)
        if inset:
            cx=sum(x for x,y in pts)/len(pts)
            cy=sum(y for x,y in pts)/len(pts)
            plate('Inset wing armor',[(cx+(x-cx)*.77,cy+(y-cy)*.84) for x,y in pts],z+thick/2+.018,.035,'panel')

def tube(name,a,b,r,mat='dark',r2=None,vertices=12):
    delta=Vector(b)-Vector(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=delta.length, location=(Vector(a)+Vector(b))/2)
    obj=bpy.context.object
    obj.rotation_euler=delta.to_track_quat('Z','Y').to_euler()
    return finish(obj,name,mat,.015)

def ball(name,loc,scale,mat='hull'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=loc)
    obj=bpy.context.object
    obj.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for p in obj.data.polygons: p.use_smooth=True
    return finish(obj,name,mat)

def ring(name,loc,major,minor,mat='trim',rotation=(math.pi/2,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=32,minor_segments=8,location=loc,major_radius=major,minor_radius=minor,rotation=rotation)
    return finish(bpy.context.object,name,mat)

def engine(x,y,z=.05,r=.34,length=.85):
    tube('Engine casing',(x,y-length/2,z),(x,y+length/2,z),r*1.2,'dark',r2=r)
    tube('Engine armor sleeve',(x,y-length*.35,z),(x,y+length*.15,z),r*1.24,'panel')
    ring('Exhaust rim',(x,y+length*.51,z),r*.9,r*.12)
    tube('Recessed exhaust',(x,y+length*.49,z),(x,y+length*.51,z),r*.72,'dark')
    tube('Ion emitter',(x,y+length*.515,z),(x,y+length*.52,z),r*.46,'glow')
    for i in range(6):
        a=i*math.tau/6
        tube('Nozzle vane',(x+math.cos(a)*r*.55,y+length*.53,z+math.sin(a)*r*.55),(x+math.cos(a)*r*.78,y+length*.53,z+math.sin(a)*r*.78),r*.045,'trim')

def engines(xs,y,z=0,r=.32,length=.85):
    for x in xs: engine(x,y,z,r,length)

def cockpit(y=-.35,z=.52,width=.36,length=1.45):
    loft('Canopy frame',[(y-length*.6,width*.12,z-.08,.08),(y-length*.18,width,z,.16),(y+length*.32,width*.8,z+.06,.24),(y+length*.5,width*.5,z,.13)],'trim')
    loft('Tinted cockpit glass',[(y-length*.52,width*.12,z+.03,.03),(y-length*.14,width*.85,z+.09,.13),(y+length*.28,width*.65,z+.13,.18),(y+length*.43,width*.36,z+.08,.09)],'glass')

def guns(xs,y=-1.8,z=.08,length=1):
    for x in xs:
        tube('Weapon shroud',(x,y+.3,z),(x,y-.15,z),.11,'panel',r2=.075)
        tube('Laser barrel',(x,y-.1,z),(x,y-length,z),.045,'dark')
        tube('Laser aperture',(x,y-length,z),(x,y-length-.012,z),.027,'glow')

def fin(x,y,z=.1,height=1,length=1.1):
    verts=[(x-.04,y,z),(x-.04,y+length,z),(x-.04,y+length*.8,z+height),(x-.04,y+length*.3,z+height*.65)]
    verts += [(a+.08,b,c) for a,b,c in verts]
    return mesh('Vertical stabilizer',verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'panel')

def vents(x,y,z,count=5,span=.5):
    for i in range(count):
        box('Cooling louver',(x,y+i*.14,z),(span,.055,.045),'dark',.01)

def curved_arms(scale=1,z=0,mat='hull',wide=.6):
    # Open crescent, connected to the rear fuselage.
    for side in [-1,1]:
        pts=[]
        for i in range(13):
            a=-1.15+i*2.35/12
            pts.append((side*(.5+2.05*math.cos(a))*scale,(.1+2.65*math.sin(a))*scale))
        pts += [(x-side*wide*scale*(.15+.85*math.sin(math.pi*i/12)**.5),y+.04*scale) for i,(x,y) in reversed(list(enumerate(pts)))]
        plate('Curved assault arm',pts,z,.24,mat)
        cx=sum(x for x,y in pts)/len(pts)
        cy=sum(y for x,y in pts)/len(pts)
        plate('Crescent armor',[(cx+(x-cx)*.92,cy+(y-cy)*.95) for x,y in pts],z+.14,.06,'panel')
        for i in range(1,12,2):
            a=-1.15+i*2.35/12
            x=side*(.5+2.05*math.cos(a)-wide*.48)*scale
            y=(.1+2.65*math.sin(a))*scale
            box('Arm running light',(x,y,z+.19),(.09,.20,.035),'glow',.01)
            tube('Arm panel joint',(x-side*wide*.23,y-.09,z+.19),(x+side*wide*.27,y+.09,z+.19),.016,'dark',vertices=6)

def arch(radius=2,y=.65,z=.05,vertical=True):
    # Structural loop, not a flat texture. Tempest is upright; Solaris has two planes.
    pts=[]
    for i in range(41):
        a=i*math.tau/40
        p=(math.cos(a)*radius,y, z+radius+math.sin(a)*radius) if vertical else (math.cos(a)*radius,y+math.sin(a)*radius,z)
        pts.append(p)
    for i in range(40):
        tube('Field ring segment',pts[i],pts[i+1],.085,'panel',vertices=6)
    for i in range(0,40,5):
        tube('Field ring light',pts[i],pts[i+1],.09,'glow',vertices=6)

# Base hull color, armor color, cockpit/emitter color, visible trim.
PALETTES={
 'Phoenix':('681d26','aeb4b8','56c8ec','d6dfe4'),
 'Yamato':('3d5158','8eabae','56cef5','bfcacf'),
 'Defcom':('203b25','6b875e','74e767','a4af9b'),
 'Liberator':('253e62','7c9abe','42c9fd','cbdde9'),
 'Piranha':('343f4d','8794a4','75d9ff','d1d9df'),
 'Nostromo':('252c2d','4e6468','5ebbe6','b3c4c4'),
 'Vengeance':('283c3b','567371','6fece0','aabcc0'),
 'Bigboy':('29364a','7d899b','83c3ff','c5cdd4'),
 'Leonov':('454c53','929e9e','83dada','d5dadd'),
 'Goliath':('30343c','99a6ad','63d6f6','e4ebed'),
 'Aegis':('162c20','43832e','52ff94','aeb8ab'),
 'Citadel':('201e23','712a2c','ff923c','b8b4b1'),
 'Spearhead':('172635','285eaf','3ee5fc','bcc9d8'),
 'Diminisher':('332f37','c8c6c8','fb3253','e5e4df'),
 'Sentinel':('263c40','77958e','60eed5','c9ddd5'),
 'Solace':('343f3b','a6b8ad','b5ffba','d5e5d9'),
 'Spectrum':('465663','acc6d0','5dc8f6','dcecf0'),
 'Venom':('4b3519','d99919','ffde65','eccb79'),
 'Pusat':('243e40','38aca9','65f1ef','bcd2d0'),
 'Tartarus':('562129','bd3234','3dc7ff','d3b2a1'),
 'Mimesis':('233c45','c87d2b','35d6e3','d8c5a7'),
 'Cyborg':('352b37','605168','ce77ff','bf9161'),
 'Hammerclaw':('24383c','987842','20e5e7','b2b5ac'),
 'Centurion':('35433e','797b58','76d9f3','bfccb9'),
 'Hecate':('3a3039','b8353e','42f4da','c3cad1'),
 'Disruptor':('356997','dadde2','40b9ff','e5eff4'),
 'Berserker':('2e3033','6d6c68','ffaa54','b9b4a9'),
 'Zephyr':('202833','31414d','37ecff','b9cbd5'),
 'Solaris':('505c68','b1bdcb','31eafb','e8eef3'),
 'Keres':('343a46','626c79','ff941b','b7c0c6'),
 'Retiarus':('252a33','465363','ffc627','99afbd'),
 'Orcus':('333747','a9b4c4','25e8ff','d5a45d'),
 'Holo':('25262b','4a4d56','ff3263','dadce2'),
 'Basilisk':('2e2343','b44152','31f5ed','b99cbb'),
 'Tempest':('58586a','d4dde7','f8479a','edf5ff'),
 'Paladin':('605026','c59c38','fff0a3','e4d3a3'),
 'Hyperion':('466a99','d8dfef','29deff','edf4ff'),
}
VARIANT_COLORS={
 'A-Elite':'ae2330','A-Veteran':'4b75b3','C-Elite':'285faf','C-Veteran':'4e872c',
 'S-Elite':'64c92c','S-Veteran':'9e3b37','Solemn':'e0e5e9','D-Raven':'b59a39',
 'N-Ambassador':'dadbd8','N-Diplomat':'c1c3c2','N-Envoy':'e7a337','Y-Ronin':'5c512c',
 'G-Surgeon':'6aa828','G-Saturn':'d2b532','G-Centaur':'8ab8d1','G-Referee':'d8862e',
 'G-Goal':'cdd3d8','G-Vanquisher':'b84840','G-Sovereign':'4977b5','G-Peacemaker':'578b43',
 'G-Exalted':'c53836','G-Veteran':'d9e1e3','G-Enforcer':'bd4833','G-Bastion':'9ec1b3',
 'G-Kick':'35bc28','G-Ignite':'e7e2c5','G-Champion':'7c858c',
 'V-Lightning':'c59924','V-Revenge':'be353c','V-Avenger':'87bbc3','V-Corsair':'8a262a','V-Adept':'d0d5d8',
}

def rgb(code):
    # Convert sRGB swatches to linear values for Blender materials.
    values=[int(code[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values)

def make_ship(ship):
    global PARTS,M
    PARTS=[]
    name=ship['name']
    family=ship['family'].replace(' Plus','')
    family={'D-Raven':'Defcom','Goliath-X':'Goliath','N-Ambassador':'Nostromo','N-Diplomat':'Nostromo','N-Envoy':'Nostromo','Y-Ronin':'Yamato'}.get(family,family)
    plus=ship['kind']=='plus'
    h,p,g,t=PALETTES[family]
    p=VARIANT_COLORS.get(name,p)
    if name=='V-Lightning': h='54451c'
    if name=='G-Surgeon': h='284715'
    if name=='Goliath-X': p='aab0a2'
    M={k:material(name+' / '+k,rgb(c),metal,rough,emit) for k,c,metal,rough,emit in [('hull',h,.72,.32,0),('panel',p,.58,.3,0),('trim',t,.8,.24,0),('glass',g,.6,.16,.08),('glow',g,.2,.24,3),('dark','111922',.6,.4,0)]}
    if family=='Phoenix':
        body(2.6,.61,.48,mat='panel')
        cockpit(-.1,.55,.4,1.4)
        wings([(.45,.25),(1,.8),(.95,1),(.4,.75)],-.1,.12)
        engine(0,1.23,0,.32)
        guns([0],-1.25,-.05,.35)
    elif family in ['Yamato','Vengeance','Nostromo']:
        l=4.2 if family=='Yamato' else 5
        body(l,.65,.38)
        cockpit(-.6,.45,.38,1.8)
        if family=='Nostromo':
            wings([(.5,-.3),(2,1.3),(2.05,2),(.55,1.2)],-.18,.18)
            engines([-1,1],1.65,.65,.53,1.4)
            guns([-.48,.48],-1.65,.02,.6)
        elif family=='Yamato':
            wings([(.4,.2),(1.8,.65),(1.8,1.4),(.35,1.3)],0,.23)
            engines([-1.65,1.65],1,.3,.49,1.2)
            engines([-.48,.48],-.45,-.3,.22,.7)
        else:
            wings([(.4,-.7),(1.75,.2),(2,1.65),(.8,2),(.5,.8)],-.18,.3)
            engines([-1.3,1.3],1.25,.4,.43,1.5)
            engines([-1.6,1.6],1.2,-.35,.33,1.2)
            engines([-.5,.5],1.85,.05,.23,.7)
            for x in [-.8,.8]: vents(x,.1,.38,4,.3)
            guns([-.45,.45],-1.8,.1,.65)
    elif family in ['Defcom','Goliath']:
        scale=.7 if family=='Defcom' else 1
        body(2.7*scale,.58*scale,.38,y=1.0*scale)
        cockpit(.7*scale,.46,.34*scale,1.4*scale)
        curved_arms(scale,0,wide=.58)
        wings([(.35,.7*scale),(2*scale,1.2*scale),(1.7*scale,1.75*scale),(.4,1.7*scale)],0,.25)
        engines([-.5*scale,.5*scale],2.35*scale,0,.26*scale)
        if family=='Goliath':
            loop=[(0,1.25,.35),(0,1.7,1.48),(0,2.55,1.48),(0,2.35,.35)]
            for i in range(4): tube('Open dorsal stabilizer',loop[i],loop[(i+1)%4],.065,'panel',vertices=6)
            wings([(.5,1.8),(1.1,2.5),(.9,2.65),(.35,2.2)],.3,.12)
            guns([-1.58,1.58],-1.2,.1,.9)
    elif family in ['Liberator','Leonov','Piranha']:
        l={'Liberator':4.8,'Leonov':4.1,'Piranha':6.5}[family]
        body(l,.48,.28)
        cockpit(-.25,.4,.28,1.45)
        if family=='Piranha':
            wings([(.35,-.7),(1.5,1.1),(1.7,2),(.6,1.55)],-.05,.12)
            for x in [-.52,.52]: body(4.5,.16,.14,y=-.7,x=x,mat='panel')
            guns([-.42,.42],-2.4,.02,.85)
        else:
            wings([(.35,-1.5),(1.9,.75),(1.45,1.6),(.65,1.1)],0,.16)
            if family=='Leonov':
                for x in [-.85,.85]: body(3.5,.25,.22,x=x,mat='panel')
                guns([-1,1],-1.5,.05,.7)
            else:
                fin(-.9,1,.1,.65,.9); fin(.9,1,.1,.65,.9)
                guns([-1.2,1.2],-.8,.08,.8)
        engines([-.55,.55],l*.38,0,.29)
    elif family=='Bigboy':
        body(4.4,1.05,.5)
        cockpit(-.65,.59,.62,2)
        wings([(.7,-.55),(1.7,-.25),(2.2,1.25),(1.35,1.5),(.65,.7)],-.1,.26)
        engines([-1.2,1.2],1.5,.3,.4,1.2)
        ball('Dorsal turret',(0,.8,.66),(.4,.5,.27),'panel')
        guns([-.17,.17],.6,.83,.75)
        guns([-1.6,1.6],.4,0,.6)
    elif family in ['Aegis','Spearhead']:
        l=5.8 if family=='Spearhead' else 5
        body(l,.48,.35)
        cockpit(-.5,.45,.29,1.45)
        wings([(.3,-.25),(2,1.5),(1.7,1.9),(.3,.7)],-.1,.17)
        box('Dorsal support',(0,1.3,.75),(.5,.8,.9),'dark')
        tube('Dorsal equipment module',(-.85,1.25,1.15),(.85,1.25,1.15),.36,'panel',vertices=12)
        for x in [-.65,0,.65]: ring('Dorsal module rib',(x,1.25,1.15),.37,.04,'trim',(0,math.pi/2,0))
        engines([-.48,.48],2,.0,.28)
        guns([-.25,.25],-2.2,.0,.8)
        if family=='Aegis':
            ball('Repair emitter',(0,.25,.52),(.39,.5,.25),'panel')
            box('Repair light cross',(0,.25,.79),(.32,.075,.04),'glow',.01)
            box('Repair light cross',(0,.25,.79),(.075,.32,.04),'glow',.01)
    elif family in ['Citadel','Centurion','Berserker','Tartarus','Spectrum']:
        if family=='Citadel':
            body(5.5,1.05,.6)
            cockpit(-.7,.65,.45,1.5)
            wings([(.65,-1.8),(1.6,-.9),(1.65,.6),(.65,1.2)],-.12,.55)
            tube('Shield outrigger',(-2,1.6,.5),(2,1.6,.5),.2,'dark')
            for x in [-2,2]:
                box('Upright shield bastion',(x,1.6,.8),(.4,1.25,2.5),'panel',.17)
                box('Bastion inset',(x-.22 if x<0 else x+.22,1.6,.85),(.05,.8,1.7),'dark')
                for z in [.2,.6,1,1.4]: box('Bastion light',(x, .96,z),(.22,.03,.08),'glow',.01)
            engines([-.7,.7],2.5,.0,.42,1.2)
            guns([-.9,.9],-1.8,.1,.7)
        elif family=='Spectrum':
            for x in [-.85,.85]: body(5.4,.5,.4,x=x,mat='panel')
            box('Central reactor',(0,.9,.0),(1.3,1.6,.55),'hull')
            cockpit(.1,.6,.35,1.1)
            engines([-.85,.85],1.1,.87,.36,1.7)
            wings([(.9,.5),(2.45,1.35),(2.3,2.2),(1.1,1.3)],-.2,.18)
            guns([-.85,.85],-2.5,0,.25)
        elif family=='Tartarus':
            body(5.1,.88,.5,mat='panel')
            cockpit(-.6,.57,.4,1.5)
            wings([(.55,-1),(2.5,-.4),(2.65,1.8),(1,2.2)],-.1,.5)
            engines([-1.5,1.5],1.2,0,.53,1.6)
            for x in [-1.6,1.6]:
                vents(x,.3,.55,7,.7)
                fin(x,1.15,.3,.8,.85)
            guns([-.6,.6],-1.9,.1,.5)
        elif family=='Centurion':
            body(5, .7,.5)
            cockpit(-.65,.65,.33,1.2)
            for x in [-1.2,1.2]:
                body(3.5,.48,.43,x=x,y=.3,mat='panel')
                engine(x,1.9,.2,.44,1.25)
                box('Siege armor block',(x,-.2,.6),(.55,1.2,.35),'panel')
            wings([(.4,-.5),(1.7,.1),(1.7,.6),(.4,.6)],-.1,.25)
            guns([-.45,.45],-2,.2,.9)
            fin(0,1.5,.5,.65,.9)
        else:
            body(4.4,1,.35)
            wings([(.4,-2.25),(1.7,-1.65),(2,1),(1.2,1.5),(.7,.3)],.12,.36)
            cockpit(-.2,.47,.35,1.4)
            engines([-.8,.8],1.8,0,.4,1)
            guns([-1.15,1.15],-1.65,-.05,.8)
            for x in [-1.15,1.15]: vents(x,-.2,.36,6,.38)
    elif family in ['Diminisher','Sentinel','Solace','Venom','Cyborg']:
        body(4.5,.5,.35)
        cockpit(-.6,.45,.32,1.4)
        if family=='Diminisher':
            wings([(.35,-.6),(2.2,.9),(1.95,1.55),(.4,.35)],.1,.22)
            for x in [-1.2,1.2]: fin(x,.5,.15,1.4,1.3)
        elif family=='Sentinel':
            wings([(.35,.4),(1.4,-1.2),(2.6,-2.5),(1.7,1.55),(.45,1.1)],-.1,.2)
            wings([(.25,1.2),(1.35,2),(1.1,2.35),(.3,1.8)],.2,.14)
            fin(0,1,.45,1.2,1)
        elif family=='Solace':
            wings([(.25,1),(1.8,.7),(2.1,1.35),(.3,1.7)],0,.22)
            for x in [-1.65,1.65]:
                body(4.6,.28,.18,x=x,y=-.65,mat='panel')
                vents(x,-1.3,.22,8,.4)
            fin(0,1.25,.3,.65,1)
        elif family=='Venom':
            wings([(.35,-.6),(1.4,-1.1),(2.35,.5),(2.2,1.9),(1.5,1.45),(.5,.1)],.1,.25)
            for x in [-1.75,1.75]: body(2.5,.35,.2,x=x,y=.4,mat='panel')
            fin(0,1,.3,1.1,1.2)
        else:
            wings([(.3,0),(1.4,.1),(2.55,1.65),(2.65,2.25),(1.9,2),(.6,.65)],0,.2)
            for x in [-1.9,1.9]:
                tube('Exposed cybernetic spar',(x*.5,0,.2),(x,1.2,.25),.085,'trim')
                body(2.4,.26,.15,x=x,y=.9,mat='panel')
            fin(0,1.2,.35,.8,.95)
        engines([-.6,.6],1.9,0,.29)
        guns([-.6,.6],-1.65,.05,1.2)
    elif family in ['Hammerclaw','Mimesis','Pusat']:
        body(4.7,.55,.36)
        cockpit(-.45,.51,.36,1.4)
        if family=='Hammerclaw':
            wings([(.45,1.2),(1,-1.8),(1.7,-2.35),(1.65,1.6)],-.1,.28)
            for x in [-1.1,1.1]:
                body(4.2,.34,.25,x=x,y=-.1,mat='panel')
                ball('Repair reservoir',(x,.5,.38),(.3,.65,.3),'glass')
            ball('Dorsal reservoir',(0,.4,.68),(.3,.55,.3),'glass')
        elif family=='Mimesis':
            wings([(.4,-.8),(1.9,-1.3),(2.3,-.7),(1.1,.5),(2.2,1.8),(1.1,1.65),(.4,.6)],0,.23)
            for x in [-1,1]: ring('Phase drive',(x,.6,.25),.38,.1,'panel',(0,0,0))
        else:
            wings([(.45,-.5),(1.7,.1),(2,1.7),(1.2,1.55),(.6,.6)],-.2,.28)
            for x in [-1.1,1.1]:
                body(3.4,.47,.38,x=x,y=.35,mat='panel')
                fin(x,1.25,.2,1.1,1)
            guns([-1.15,1.15],-1.3,.1,1)
        engines([-1.1,1.1],1.9,.0,.38,1)
        guns([-.4,.4],-1.8,.05,1)
    elif family in ['Hecate','Orcus','Paladin','Retiarus']:
        body(5,.6,.37)
        cockpit(-.5,.53,.38,1.7)
        if family=='Hecate':
            wings([(.4,.6),(1,-1.1),(2.5,-1.65),(1.9,-.4),(2.8,1.7),(1.6,1.25),(.55,.9)],0,.18)
            for x in [-.8,.8]: fin(x,.6,.2,1.3,1.1)
            wings([(.4,1.5),(1.9,2.25),(1.2,2.45),(.4,2)],.1,.12)
        elif family=='Orcus':
            wings([(.45,-.6),(2.35,.75),(1.1,.95),(.5,.4)],0,.16)
            wings([(.5,1),(1.1,1.7),(1.3,2.1),(.35,1.8)],0,.2)
            for x in [-.75,.75]: fin(x,.55,.1,1.2,1.3)
        elif family=='Paladin':
            wings([(.4,-1.8),(1.15,-1.35),(1.8,.25),(1.2,1.7),(.45,.7)],.0,.3)
            for x in [-.9,.9]:
                for y in [-.3,.6,1.5]:
                    wings([(abs(x),y),(abs(x)+.85,y+.55),(abs(x)+.35,y+.7)],.1,.1)
                fin(x,.7,.3,1,1.1)
            for y in [-.7,-.25,.2]: box('Command armor rib',(0,y,.45),(1.15,.13,.12),'panel')
        else:
            wings([(.4,.6),(1.4,-1.9),(2.7,-2.6),(2.1,-.7),(2.8,1.8),(1.4,.75)],-.05,.18)
            wings([(.45,1),(1.1,1.6),(.9,2.2),(.3,1.6)],.1,.15)
        engines([-.55,.55],2.1,.05,.3)
        guns([-.6,.6],-1.8,0,.7)
    elif family in ['Solaris','Tempest']:
        body(5.3,.78,.4,mat='panel')
        cockpit(-.65,.58,.44,1.7)
        wings([(.5,-1.2),(1.7,.2),(1.55,1.45),(.7,1.8)],-.08,.14)
        arch(1.72,.7,.15,True)
        if family=='Solaris': arch(2.05,.3,-.15,False)
        else:
            curved_arms(.78,-.2,wide=.2)
            guns([-.3,.3],-2,.05,.95)
        engines([-.7,.7],2.0,-.05,.3)
    elif family=='Basilisk':
        ball('Rounded command hull',(0,.2,0),(1.3,1.65,.5),'panel')
        ball('Observation canopy',(0,-.15,.55),(.72,.85,.53),'glass')
        ring('Canopy seal',(0,-.15,.3),.73,.09,'trim',(0,0,0))
        wings([(.9,1),(1.7,.4),(2.25,-1.75),(2.05,-2.5),(1.6,-.7),(.85,.3)],-.12,.22)
        for x in [-1,1]:
            ball('Toxic dispersal port',(x,-.45,.1),(.18,.23,.18),'glow')
            engine(x*.7,1.6,-.1,.29)
    elif family=='Disruptor':
        body(4.5,.7,.45,mat='panel')
        cockpit(-.6,.58,.45,1.7)
        for x in [-1.15,1.15]:
            body(3.1,.47,.32,x=x,y=.2,mat='panel')
            ball('Shield array',(x,.0,.3),(.38,.83,.33),'panel')
            box('Shield array light',(x,-.1,.65),(.14,.75,.035),'glow')
        wings([(.5,0),(1.3,.65),(2.1,1.7),(1.4,1.25)],-.2,.16)
        engines([-1.05,1.05],1.5,.0,.32)
        fin(0,1.1,.4,.9,1)
    elif family=='Hyperion':
        body(5.3,.7,.35,mat='panel')
        cockpit(-.4,.5,.37,1.6)
        wings([(.45,-1.7),(1.1,-.85),(1.6,.65),(1.25,1.8),(.45,.8)],-.07,.2)
        engines([-1.4,1.4],1,.15,.49,2.3)
        fin(0,1.3,.2,.85,1)
    elif family in ['Keres','Holo','Zephyr']:
        l={'Keres':4.6,'Holo':6.2,'Zephyr':7.4}[family]
        body(l,.65,.4)
        cockpit(-.25,.57,.39,1.8)
        wings([(.5,.4),(1.9,1.75),(1.2,1.55),(.5,1)],-.05,.12)
        if family=='Keres':
            for x in [-.8,.8]:
                tube('Forward intake',(x,-1.6,0),(x,-.6,0),.4,'dark',r2=.27)
                ring('Intake rim',(x,-1.62,0),.34,.05)
            ball('Plasma core',(0,-1.5,.0),(.3,.4,.31),'glow')
            fin(0,1.2,.35,1.1,1.5)
        elif family=='Holo':
            fin(0,1.1,.4,1.8,1.7)
            for x in [-.4,.4]: body(3,.16,.15,x=x,y=-1.4,mat='panel')
        else:
            wings([(.4,1.1),(1.75,2.4),(1.1,2.5),(.4,1.8)],.1,.16)
            for x in [-.6,.6]: fin(x,1.4,.2,.8,1.5)
        engines([-.65,.65],l*.36,.02,.32)
        guns([-.42,.42],-l*.4,.05,.7)
    else:
        raise ValueError(f'No authored hull for {name}: {family}')

    if plus:
        # Plus references retain the parent silhouette with heavier attachments.
        if family=='Goliath':
            wings([(1.45,-1.8),(2.45,-1.75),(2.9,-.6),(2.55,-.3),(1.95,-1)],.12,.2)
            engines([-.65,0,.65],2.65,.15,.25)
            wings([(.4,2),(1.35,3.1),(.8,2.8),(.3,2.4)],.15,.16)
        elif family=='Retiarus':
            curved_arms(1.05,-.12,wide=.38)
            guns([0],-2.1,.08,1.3)
        elif family=='Tartarus':
            wings([(.55,-1.3),(3.2,-.55),(3.05,1.4),(1.4,1.6)],.15,.33)
        elif family=='Citadel':
            wings([(.7,-1.7),(1.95,-.95),(1.95,.55),(.75,1.1)],.3,.32)
        elif family=='Hecate':
            for x in [-1.25,1.25]: fin(x,.75,.15,1.65,1.15)
        elif family=='Solace':
            for x in [-1.65,1.65]: box('Plus forward armor',(x,-2.35,.18),(.55,1.1,.3),'panel')
        elif family=='Spectrum':
            engines([-.85,.85],.8,1.5,.26,1.4)
            fin(0,1.35,.3,1.6,1.2)
        else:
            wings([(.5,-1),(1.4,-.45),(2.1,1.3),(1.3,.95),(.5,.1)],.3,.13)
        for x in [-.45,.45]:
            box('Plus reactor rail',(x,.8,.65),(.14,1.1,.15),'glow',.03)

    # A few variants have actual additional silhouette changes in their references.
    if name=='G-Bastion':
        for x in [-.95,.95]:
            for y in [1.15,1.8]: ball('Shield emitter',(x,y,.4),(.27,.3,.25),'glass')
    if name=='G-Champion':
        wings([(.45,1.4),(1.75,2.5),(1,2.4),(.3,1.9)],.4,.15)
    if name=='Goliath-X':
        wings([(.5,.7),(1.3,1.5),(1.15,1.95),(.45,1.1)],.5,.16)
    # Belly service plate and navigation lights make the models usable from below.
    box('Ventral service hatch',(0,.35,-.39),(.55,.85,.1),'dark',.05)
    for x in [-.3,.3]: box('Ventral fastener',(x,.35,-.45),(.05,.5,.04),'trim',.01)
    root=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(root)
    root['ship']=name
    root['reference']=ship['source']
    root['review_status']='Reference-based interpretation; underside and depth inferred.'
    root['forward_axis']='-Y; Z up'
    for obj in PARTS: obj.parent=root
    return root

def point_at(obj,point): obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()

def studio(root):
    scene=bpy.context.scene
    scene.render.engine='CYCLES'
    scene.cycles.samples=24
    scene.cycles.use_denoising=True
    scene.render.resolution_x=800
    scene.render.resolution_y=720
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='JPEG'
    scene.render.image_settings.quality=93
    scene.world.color=(.13,.13,.13)
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value=(.16,.21,.3,1)
    bg.inputs[1].default_value=.5
    scene.view_settings.view_transform='AgX'
    bounds=[o.matrix_world @ Vector(p) for o in PARTS for p in o.bound_box]
    # Update transforms before framing.
    bpy.context.view_layer.update()
    bounds=[o.matrix_world @ Vector(p) for o in PARTS for p in o.bound_box]
    low=Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    center=(low+high)*.5
    extent=max(high.x-low.x,high.y-low.y,high.z-low.z)
    bpy.ops.object.camera_add(location=center+Vector((8,-11,10)))
    camera=bpy.context.object
    camera.name='Review camera'
    point_at(camera,center)
    camera.data.type='ORTHO'
    camera.data.ortho_scale=extent*1.35
    scene.camera=camera
    for name,loc,power,size,color in [('Key',(-4,-6,9),1900,7,(.79,.88,1)),('Rim',(5,4,6),2300,5,(.4,.73,1)),('Fill',(6,-4,3),1300,6,(1,.8,.59))]:
        data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
        obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj); obj.location=loc; point_at(obj,center)
    # Clean studio background with a contact shadow.
    mat=material('Studio floor',(.017,.025,.04),.15,.48)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,low.z-.5))
    floor=bpy.context.object; floor.name='Studio floor'; floor.data.materials.append(mat)
    # Open directly in a useful material-colored, solid viewport.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.shading.type='SOLID'; space.shading.color_type='MATERIAL'; space.shading.light='STUDIO'
                space.shading.show_cavity=True; space.shading.cavity_type='BOTH'
                space.overlay.show_floor=False; space.overlay.show_axis_x=False; space.overlay.show_axis_y=False
                space.region_3d.view_distance=extent*1.8
                space.region_3d.view_location=center
                space.region_3d.view_rotation=camera.rotation_euler.to_quaternion()
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True); bpy.context.view_layer.objects.active=root
    floor.hide_set(True)
    for obj in scene.objects:
        if obj.type in {'LIGHT','CAMERA'}: obj.hide_set(True)
    return len(PARTS),sum(len(o.data.polygons) for o in PARTS)

def run():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    wanted=[s for s in ROSTER if not args or s['name'] in args or s['slug'] in args]
    if not wanted: raise ValueError(f'Unknown ships: {args}')
    stats=[]
    for ship in wanted:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.world=bpy.data.worlds.new('Review world')
        root=make_ship(ship)
        count,faces=studio(root)
        bpy.context.preferences.filepaths.save_version=0
        path=MODELS/(ship['slug']+'.blend')
        bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
        bpy.context.scene.render.filepath=str(PREVIEWS/(ship['slug']+'.jpg'))
        bpy.ops.render.render(write_still=True)
        stats.append(dict(name=ship['name'],objects=count,faces=faces))
        print('SHIP COMPLETE',ship['name'],count,faces,flush=True)
    (HERE/'build-stats.json').write_text(json.dumps(stats,indent=2)+'\n')

if __name__=='__main__': run()
