"""Author and render the six approved outer-sector references with Blender 5.2.

Run from the repository root with --background --python-exit-code 1 --python
art/alien-review/outer-sectors/build_models.py -- [names] [--draft].
Review coordinates are -Y forward, +Z up. No generated images are used as skins.
"""
import importlib.util
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
REVIEW = HERE.parent
ROOT = REVIEW.parents[1]
spec = importlib.util.spec_from_file_location('alien_review', REVIEW/'build_models.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)
geo = review.geo
from alien_geometry import shell, joint, fitted_hull, hull_point, wing_shell, wing_point, interpolate

NAMES = ('Skirmisher', 'Raider', 'Marauder', 'Warden', 'Ravager', 'Overlord')
VIEWS = ('perspective', 'top', 'side', 'front', 'rear', 'underside')
DETAILS = ('armor-detail', 'mount-detail', 'drive-detail')

# Stations: Y, half-width, half-height, center Z. Outrigger stations:
# Y, inner X, outer X, top Z. These dimensions describe artwork, not colliders.
SPECS = {
    'Skirmisher': dict(color=(.13,.47,.29), light=(.19,1,.60),
        body=[(-5.0,.045,.035,0),(-3.8,.23,.12,.04),(-2.2,.46,.25,.10),
              (-.6,.66,.35,.15),(.6,.68,.37,.16),(1.7,.53,.31,.15),(2.7,.36,.21,.10)],
        wings=[[(-3.9,2.17,2.22,.0),(-2.7,2.36,2.62,.10),(-1.0,2.04,2.65,.28),
                (.3,1.68,2.37,.35),(1.4,1.82,2.07,.26),(2.3,2.11,2.15,.10)]],
        depth=.16, drives=[(-.56,1.35,.12,.43,1.7),(.56,1.35,.12,.43,1.7)],
        mounts=[(-.7,.0,1.94),(.6,.15,1.82)], gun=(1.98,-2.4,-.08,.065)),
    'Raider': dict(color=(.025,.26,.27), light=(.03,.95,1),
        body=[(-1.5,.38,.18,.08),(-1.1,.66,.30,.11),(-.4,.85,.34,.15),
              (.3,.90,.35,.16),(1.2,.85,.32,.15),(2.1,.66,.28,.14),(2.9,.46,.22,.10)],
        wings=[[(-4.05,1.83,2.02,.02),(-3.2,1.65,2.51,.15),(-1.7,1.63,2.85,.32),
                (-.25,1.95,2.91,.43),(1.3,1.54,2.40,.43),(2.6,1.47,2.04,.30)]],
        depth=.40, drives=[(-1.8,1.20,.13,.60,1.9),(1.8,1.20,.13,.60,1.9)],
        mounts=[(-.45,.03,2.03),(.8,.08,1.80)], gun=(1.82,-3.3,-.11,.085), rectangular=True),
    'Marauder': dict(color=(.65,.30,.035), light=(1,.40,.025),
        body=[(-5.1,.075,.07,-.02),(-3.9,.28,.16,.04),(-2.6,.53,.32,.12),
              (-1.0,.85,.43,.19),(.4,.85,.43,.20),(1.6,.69,.36,.20),(2.7,.42,.26,.16)],
        wings=[[(-4.25,1.85,1.92,.17),(-3.2,1.46,2.11,.30),(-2.1,1.34,2.36,.36),
                (-1.25,1.63,2.13,.31),(-.85,1.94,2.01,.20)],
               [(-.10,2.59,2.67,.20),(.55,2.10,2.75,.29),(1.5,1.67,2.60,.42),
                (2.4,1.46,2.15,.60),(3.05,1.69,1.78,.76)]],
        depth=.24, drives=[(-.54,1.25,-.16,.44,1.95),(.54,1.25,-.16,.44,1.95),
                           (0,1.25,.67,.44,1.95)],
        mounts=[(-2.0,.04,1.52),(1.05,.14,1.85)], gun=(1.00,-1.7,-.13,.09)),
    'Warden': dict(color=(.58,.18,.065), light=(1,.13,.015),
        body=[(-2.7,.85,.37,.02),(-2.25,1.20,.46,.13),(-1.35,1.55,.60,.24),
              (-.15,1.65,.69,.28),(.9,1.48,.63,.28),(1.9,1.16,.49,.23),(2.75,.76,.34,.16)],
        wings=[[(-2.1,2.03,2.22,-.05),(-1.45,1.93,2.66,.26),(-.5,2.05,2.85,.49),
                (.6,2.06,2.82,.54),(1.6,2.0,2.52,.39),(2.05,2.10,2.22,.05)]],
        depth=.62, drives=[(-.95,1.25,.10,.69,2.00),(.95,1.25,.10,.69,2.00)],
        mounts=[(-1.1,-.05,2.17),(.8,.10,2.19)], gun=(.91,-2.45,-.52,.105), heavy=True),
    'Ravager': dict(color=(.22,.085,.43), light=(.46,.055,1),
        body=[(-5.25,.095,.07,-.04),(-4.1,.25,.16,.02),(-2.6,.46,.29,.08),
              (-1.0,.64,.37,.13),(.4,.74,.40,.16),(1.7,.61,.36,.18),(2.9,.32,.24,.18)],
        wings=[[(-5.10,3.06,3.10,-.24),(-3.75,2.68,3.04,-.10),(-2.2,2.13,2.85,.14),
                (-.55,1.71,2.48,.41),(.8,1.66,2.35,.50),(2.2,2.03,2.10,.54)]],
        depth=.25, drives=[(-.99,1.15,.21,.58,2.25),(.99,1.15,.21,.58,2.25),
                           (0,1.8,-.31,.30,1.65)],
        mounts=[(-.6,.10,1.89),(.6,.20,1.83)], gun=(.22,-5.3,-.04,.055)),
    'Overlord': dict(color=(.47,.085,.25), light=(1,.025,.48),
        body=[(-3.95,.15,.15,-.05),(-3.1,.75,.35,.05),(-1.8,1.64,.56,.16),
              (-.15,2.22,.70,.24),(1.0,1.92,.67,.27),(2.2,1.45,.55,.25),(3.2,1.00,.42,.18)],
        wings=[[(-1.8,1.71,1.94,.37),(-.9,1.92,2.60,.58),(.2,2.03,2.85,.64),
                (1.3,1.91,2.54,.52),(2.3,1.70,2.03,.30)]],
        depth=.52, drives=[(-1.40,1.55,-.47,.54,2.0),(1.40,1.55,-.47,.54,2.0),
                           (-1.40,1.55,.72,.54,2.0),(1.40,1.55,.72,.54,2.0)],
        mounts=[(-.6,.12,2.01),(.7,.20,2.10)], gun=(1.78,-2.65,-.15,.105), heavy=True),
}


def armor(spec, name):
    geo.group('Hull | fitted armor, keel and cooling bays')
    stations = spec['body']
    geo.loft('Continuous load-bearing keel',[(0,y,z,w,h) for y,w,h,z in stations],'dark',.022)
    # Every plate follows the underlying section breaks instead of floating
    # above a generic hull. Two staggered bands expose the underlying frame.
    for side in (-1,1):
        spans=[(0,2),(2,3),(3,4),(4,5),(5,6)] if name in ('Skirmisher','Marauder','Ravager') else [(i,i+1) for i in range(6)]
        for i,(ia,ib) in enumerate(spans):
            a,b=stations[ia],stations[ib]
            ya,yb=a[0]+.025,b[0]-.025
            for lane,(lo,hi) in enumerate(((.10,.61),(.64,1.02))):
                outline=([(.10,.07),(.48,.015),(.61,.24),(.57,.71),(.40,.97),(.10,.85)]
                         if lane==0 else [(.65,.10),(.91,.015),(1.025,.32),(.97,.82),
                                          (.76,.97),(.62,.71),(.70,.50)])
                fitted_hull(f'{side} coat panel {i} band {lane}',spec,side,ya,yb,
                            outline,'paint',.065,.065 if spec.get('heavy') else .045)
                if i>0:
                    for u,t in ((lo+.06,.25),(hi-.08,.75)):
                        geo.bolt(hull_point(spec,side,u,ya+(yb-ya)*t,.11),radius=.018)
            fitted_hull(f'{side} exposed chine {i}',spec,side,ya,yb,
                        [(1.025,.05),(1.10,.18),(1.10,.80),(1.02,.94)],'steel',.015,.032)
            fitted_hull(f'{side} ventral armor {i}',spec,side,ya,yb,
                        [(.12,.09),(.81,.03),(1.0,.29),(.94,.82),(.40,.97),(.12,.80)],
                        'graphite',.06,.065,True)
            # A narrow exposed dorsal backbone and ribbed inset service bay.
            if i in (2,4):
                y=(ya+yb)/2
                p=hull_point(spec,side,.72,y,.10)
                geo.box('Recessed heat exchanger',p,(.16,.45,.045),'recess',.008)
                for k in range(5):
                    geo.box('Machined radiator slat',(p[0],y-.17+k*.08,p[2]+.035),
                            (.14,.028,.035),'gunmetal',.004)
        for i in range(1,6):
            y,w,h,z=stations[i]
            geo.box('Dorsal bridge',(side*.07,y,z+h+.055),(.11,.22,.065),'graphite',.012)
        # Aft return pipes remain exposed under the armor skirt.
        path=[hull_point(spec,side,1.03,y,-.14) for y in (-.5,.25,1.0,1.7)]
        geo.pipe('External armored coolant conduit',path,.029,'gunmetal')
    if name in ('Warden','Overlord'):
        command=dict(body=[(y*.69+.35,w*.62,h*.56,z+h*.72+.16) for y,w,h,z in stations])
        geo.group('Command | overlapping raised carapace')
        geo.loft('Raised command pressure shell',[(0,y,z,w,h) for y,w,h,z in command['body']],
                 'graphite',.026)
        for side in (-1,1):
            for i in range(1,5):
                ya,yb=command['body'][i][0]+.025,command['body'][i+1][0]-.025
                fitted_hull('Tiered command coat',command,side,ya,yb,
                            [(.12,.04),(.83,.025),(1.02,.32),(.93,.85),(.39,.97),(.12,.78)],
                            'paint',.06,.075)
        if name=='Overlord':
            geo.loft('Dorsal command crown',[(0,.25,1.12,.40,.16),(0,1.3,1.42,.32,.21),
                                           (0,2.12,1.30,.20,.13)],'graphite',.035)
            shell('Crown armor', [(-.24,.36,1.32),(.24,.36,1.32),(.30,1.25,1.65),
                                  (.16,1.97,1.49),(-.16,1.97,1.49),(-.30,1.25,1.65)],.06)
        geo.loft('Deep ventral armored block',[(0,-2,-.48,.69,.26),(0,-.2,-.65,1.1,.35),
                                              (0,1.8,-.44,.76,.22)],'graphite',.04)


def outriggers(spec, name):
    geo.group('Outriggers | scythes, pincers and shield assemblies')
    for side in (-1,1):
        for blade,stations in enumerate(spec['wings']):
            prefix=f'{side} blade {blade}'
            wing_shell(prefix,side,stations,spec['depth'])
            for i,(a,b) in enumerate(zip(stations,stations[1:])):
                ya,yb=a[0]+.02,b[0]-.02
                outline=[(.10,.08),(.70,.02),(.95,.26),(.91,.76),(.65,.97),(.11,.88),(.16,.51)]
                shell(prefix+f' contoured coat {i}',
                      [wing_point(stations,side,u,ya+(yb-ya)*t,.055) for u,t in outline],
                      .065 if spec.get('heavy') else .045)
                edge=[(.88,.08),(1.035,.03),(1.035,.88),(.90,.95)]
                shell(prefix+f' machined outer rim {i}',
                      [wing_point(stations,side,u,ya+(yb-ya)*t,.008) for u,t in edge],.04,'steel')
                shell(prefix+f' underside shield {i}',
                      [wing_point(stations,side,u,ya+(yb-ya)*t,-spec['depth']-.025)
                       for u,t in outline],.04,'graphite',(0,0,-1))
                if i and i<len(stations)-2:
                    for u,t in ((.24,.26),(.69,.74)):
                        geo.bolt(wing_point(stations,side,u,ya+(yb-ya)*t,.10),radius=.016)
        geo.group(f'Articulation | {side} exposed pivots and hydraulic forks')
        for index,(y,z,outer) in enumerate(spec['mounts']):
            inner=Vector((side*.65,y,z))
            # Body size determines the inboard pivot, so wide hulls have short,
            # powerful actuators and needle hulls expose long polished pistons.
            width=interpolate(spec['body'],y)[0]
            inner.x=side*width*.88
            end=Vector((side*outer,y+.13,z))
            for dz in (-.12,.10):
                joint(f'{side} fork {index}',inner+Vector((0,0,dz)),end+Vector((0,0,dz)),
                      .075 if spec.get('heavy') else .050)
            for p in (inner,end):
                geo.tube('Pivot socket',p-Vector((0,0,.17)),p+Vector((0,0,.17)),.16,
                         'graphite',vertices=16,bevel=.009)
                geo.tube('Machined pivot boss',p+Vector((0,0,.17)),p+Vector((0,0,.22)),
                         .12,'steel',vertices=16,bevel=.005)
                geo.bolt(p+Vector((0,0,.225)),radius=.055)
            for edge in (-1,1):
                # An open fork exposes the polished piston and bypass cable.
                shell('Open articulated mounting fork',
                      [inner+Vector((0,edge*.21,.18)),
                       end+Vector((0,edge*.21,.16)),end+Vector((0,edge*.14,.16)),
                       inner+Vector((0,edge*.14,.18))],.055,'gunmetal')
        geo.group('Outriggers | scythes, pincers and shield assemblies')


def rectangular_drive(label,x,y,z,r,length):
    tail=y+length
    geo.loft(label+' faceted drive casing',[(x,y,z,r*.83,r*.83),
             (x,y+.25,z,r,r),(x,tail-.17,z,r,r)],'dark',.025)
    # Open aft face: the casing stops in front of the recessed luminous bars.
    for side in (-1,1):
        shell(label+' upper coat',[(x+side*.06,y+.12,z+r*1.03),
              (x+side*r*.63,y+.12,z+r*1.03),(x+side*r*.91,y+.36,z+r*.65),
              (x+side*r*.91,tail-.29,z+r*.65),(x+side*r*.55,tail-.20,z+r*1.03),
              (x+side*.06,tail-.20,z+r*1.03)],.06)
        geo.box(label+' vertical nozzle surround',(x+side*r*.91,tail,z),(.095,.25,r*1.5),'steel',.025)
    for dz in (-1,1):
        geo.box(label+' horizontal nozzle surround',(x,tail,z+dz*r*.77),
                (r*1.74,.25,.095),'steel',.025)
    geo.box(label+' deep black exhaust well',(x,tail-.10,z),(r*1.6,.04,r*1.35),'recess',.015)
    for dz in (-.40,0,.40):
        geo.box(label+' recessed exhaust bar',(x,tail-.055,z+dz*r),(r*1.06,.025,.050),'light',.01)
    for i in range(6):
        geo.box(label+' inlet louver',(x,y+.23+i*.075,z+r*1.09),(r*.73,.035,.03),'gunmetal',.004)


def drives(spec,name):
    geo.group('Propulsion | rear drive clusters and recessed turbines')
    for index,(x,y,z,r,length) in enumerate(spec['drives']):
        label=f'Drive {index+1}'
        if spec.get('rectangular'):
            rectangular_drive(label,x,y,z,r,length)
            continue
        # Reuse the detailed M1 paired-drive tooling with a translated half.
        # Removing the opposite half avoids a second overlapping center drive.
        start=len(geo.PARTS)
        review.engines(dict(engine_radius=r,engine_length=length,engine_y=y,engine_z=z,engine_x=abs(x)))
        created=geo.PARTS[start:]
        keep_prefix='Port' if x<0 else 'Starboard'
        for obj in created:
            if not obj.name.startswith(keep_prefix):
                geo.PARTS.remove(obj)
                bpy.data.objects.remove(obj,do_unlink=True)
            else:
                obj.name=label+' '+obj.name
        # Reference exhaust identity: mint circular, amber triad, orange rings,
        # violet turbine and magenta stacked drives. Keep centers unobstructed.
        tail=y+length+.04
        if name in ('Warden','Ravager','Overlord'):
            geo.ring(label+' recessed luminous annulus',(x,tail-.19,z),r*.61,r*.028,'light',(0,1,0))
        geo.group('Propulsion | rear drive clusters and recessed turbines')


def weapons(spec,name):
    geo.group('Weapons | ribbed barrels and inset sensor slits')
    x,y,z,r=spec['gun']
    for side in (-1,1):
        geo.loft('Armored weapon receiver',[(side*x,y-.12,z,.17,.14),
                 (side*x,y+.65,z,.23,.19),(side*x,y+1.2,z,.16,.13)],'graphite',.018)
        for offset in ((-.075,.075) if name in ('Raider','Warden','Overlord') else (0,)):
            gx=side*x+offset
            tip=y-.87
            geo.tube('Ribbed cannon barrel',(gx,y+.2,z),(gx,tip,z),r,'gunmetal',vertices=16,bevel=.004)
            for i in range(5):
                cy=y-.12-i*.13
                geo.tube('Barrel retention collar',(gx,cy+.045,z),(gx,cy,z),r*1.22,'steel',vertices=12,bevel=.003)
            geo.tube('Black muzzle bore',(gx,tip-.007,z),(gx,tip-.014,z),r*.78,'recess',vertices=16,bevel=0)
            geo.tube('Recessed cannon optic',(gx,tip-.016,z),(gx,tip-.020,z),r*.35,'light',vertices=12,bevel=0)
        # The sensor sits on the actual leading hull edge, independent of guns.
        ny,w,h,nz=spec['body'][0]
        sx=side*w*.5
        geo.box('Armored forward sensor socket',(sx,ny-.025,nz),(.11,.07,.06),'graphite',.009)
        geo.box('Forward sensor emission',(sx,ny-.066,nz),(.075,.015,.025),'light',.003)
        if name in ('Warden','Overlord'):
            geo.box('Recessed prow sensor',(side*.65,-2.61 if name=='Warden' else -2.95,.02),
                    (.43,.045,.075),'light',.012)


def fittings(spec,name):
    """Small built parts follow the armor rather than covering it in tiles."""
    geo.group('Service | recessed flank bays, seam locks and command optics')
    for side in (-1,1):
        for y in (-1.25,-.25,.75):
            w,h,z=interpolate(spec['body'],y)
            # Inset flank machinery beneath the overhanging upper coat.
            x=side*(w+.015)
            geo.box('Deep side service bay',(x,y,z-.04),(.035,.53,.18),'recess',.008)
            for k in range(5):
                geo.box('Flank cooling louver',(x+side*.025,y-.20+k*.10,z-.04),
                        (.045,.035,.15),'gunmetal',.003)
            if y<0:
                geo.box('Armored sensor eyebrow',(x+side*.035,y,z+.13),(.07,.55,.065),'graphite',.01)
                geo.box('Inset side sensor slit',(x+side*.046,y,z+.065),(.018,.36,.029),'light',.003)
        # Raised elongated central sensor cover and exposed dark dorsal slots.
        for y in (-1.8,-.60,.55):
            w,h,z=interpolate(spec['body'],y)
            sx=side*w*.32
            shell('Angular dorsal service cover',[(sx,y-.25,z+h+.12),
                  (sx+side*.11,y-.18,z+h+.14),(sx+side*.13,y+.18,z+h+.14),
                  (sx,y+.27,z+h+.12)],.04,'graphite')
        for blade,stations in enumerate(spec['wings']):
            for i in range(1,len(stations)-2):
                a,b=stations[i],stations[i+1]
                ya,yb=a[0]+.02,b[0]-.02
                # Armor seam staples, dark triangular inset patches and screws.
                tab=[(.14,.74),(.32,.72),(.45,.91),(.20,.97)]
                shell('Lapped wing seam lock',
                      [wing_point(stations,side,u,ya+(yb-ya)*t,.095) for u,t in tab],.021,'gunmetal')
                inset=[(.57,.21),(.72,.27),(.76,.51),(.57,.44)]
                shell('Recessed outrigger maintenance hatch',
                      [wing_point(stations,side,u,ya+(yb-ya)*t,.087) for u,t in inset],.015,'graphite')
        # Short overlapping shoulder plates sit behind, not over, the pistons.
        y=.95
        w,h,z=interpolate(spec['body'],y)
        inner=w*.84
        outer=min(spec['mounts'][-1][2],inner+.65)
        shell('Swept aft shoulder guard',[(side*inner,y-.16,z+h+.05),
              (side*(outer-.10),y-.12,z+h-.04),(side*outer,y+.15,z+h-.15),
              (side*(outer-.10),y+.43,z+h-.15),(side*inner,y+.39,z+h+.025)],.075)
    if name=='Ravager':
        # Resolve the generated front exhausts as armored pivots. Real drives
        # are at the rear. Long paired needle tips retain the split spear nose.
        for side in (-1,1):
            geo.loft('Split spear tip',[(side*.14,-6.22,-.08,.022,.025),
                     (side*.21,-5.15,-.02,.085,.065),(side*.22,-4.45,.03,.10,.09)],'gunmetal',.006)
    if name=='Overlord':
        for side in (-1,1):
            geo.loft('Heavy armored weapon sponson',[(side*1.78,-2.85,-.16,.29,.27),
                     (side*1.78,-2.15,-.10,.41,.35),(side*1.78,-1.35,.02,.37,.31)],'dark',.03)
            shell('Magenta sponson upper shield',[(side*1.50,-2.63,.16),
                  (side*1.99,-2.52,.18),(side*2.10,-1.73,.32),
                  (side*1.59,-1.39,.34)],.065)
            geo.box('Command sensor band',(side*.38,.19,1.03),(.49,.055,.045),'light',.008)


def studio(name,draft):
    scene=bpy.context.scene
    bpy.context.view_layer.update()
    bounds=[o.matrix_world@Vector(p) for o in geo.PARTS for p in o.bound_box]
    low=Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high=Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    center=(low+high)/2
    extent=max(high-low)
    scene.render.engine='BLENDER_EEVEE'
    scene.eevee.use_raytracing=True
    scene.eevee.use_fast_gi=True
    scene.eevee.fast_gi_quality=1
    scene.eevee.taa_render_samples=24 if draft else 64
    scene.render.resolution_x=960 if draft else 1600
    scene.render.resolution_y=720 if draft else 1200
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.render.film_transparent=True
    scene.world=bpy.data.worlds.new('Neutral modeling studio')
    scene.world.use_nodes=True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.23,.25,.28,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'
    geo.group('Studio | six construction views and three details')
    cameras={}
    for view,offset in dict(perspective=(9,-12,9),top=(0,0,16),side=(16,0,0),
                            front=(0,-16,0),rear=(0,16,0),underside=(0,0,-16)).items():
        data=bpy.data.cameras.new(name+' '+view)
        camera=bpy.data.objects.new(name+' '+view,data)
        geo.GROUP.objects.link(camera)
        camera.location=center+Vector(offset)
        geo.point_at(camera,center)
        data.type='ORTHO'
        inverse=camera.rotation_euler.to_quaternion().inverted()
        projected=[inverse@(p-center) for p in bounds]
        data.ortho_scale=max(max(abs(p.x)*2 for p in projected),
                             max(abs(p.y)*8/3 for p in projected))*1.14
        cameras[view]=camera
    s=SPECS[name]
    dx,dy,dz,dr,dl=s['drives'][-1]
    my,mz,mx=s['mounts'][0]
    # Full-resolution macro cameras use the same geometry and surface maps.
    for view,target,offset,scale in (
        ('armor-detail',hull_point(s,1,.50,-.45,.10),(2,-3,4),3.0),
        ('mount-detail',(mx-.40,my,mz),(2,-3,3),2.2),
        ('drive-detail',(dx,dy+dl-.30,dz),(2,4,2),dr*5.5)):
        data=bpy.data.cameras.new(name+' '+view)
        camera=bpy.data.objects.new(name+' '+view,data)
        geo.GROUP.objects.link(camera)
        camera.location=Vector(target)+Vector(offset)
        geo.point_at(camera,Vector(target))
        data.type='ORTHO'
        data.ortho_scale=scale
        cameras[view]=camera
    for label,offset,power,size in (
        ('Broad key',(-5,-5,10),2100,7),('Front fill',(7,-3,5),1100,6),
        ('Aft rim',(1,7,6),1900,5),('Ventral fill',(-2,-1,-7),1100,6)):
        data=bpy.data.lights.new(label,'AREA')
        data.energy,data.size=power,size
        obj=bpy.data.objects.new(label,data)
        geo.GROUP.objects.link(obj)
        obj.location=center+Vector(offset)
        geo.point_at(obj,center)
    scene.camera=cameras['perspective']
    geo.group('Reference | packed approved sheet, hidden')
    image=bpy.data.images.load(str(REVIEW/'concepts/outer-sectors'/(name.lower()+'.png')))
    image.pack()
    obj=bpy.data.objects.new(name+' reference',None)
    obj.empty_display_type='IMAGE'
    obj.data=image
    obj.empty_display_size=extent
    obj.location=(extent+2,0,0)
    obj.hide_render=True
    geo.GROUP.objects.link(obj)
    geo.GROUP.hide_viewport=True
    notes=bpy.data.texts.new('READ ME')
    notes.write(f'{name}: -Y forward, +Z up. Modeling units.\n'
                'Approved reference and PBR maps are packed. F12 renders the hero camera.\n'
                'Hull, outriggers, pivots, drives and weapons are editable components.\n'
                'Secondary generated views are reconciled into a symmetric model.\n'
                'All propulsion faces aft. Overlord has exactly four drives.\n')
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.shading.type='MATERIAL'
                space.overlay.show_floor=False
                space.region_3d.view_location=center
                space.region_3d.view_distance=extent*1.5
                space.region_3d.view_rotation=cameras['perspective'].rotation_euler.to_quaternion()
    return cameras


def build(name,draft):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    geo.PARTS=[]
    s=SPECS[name]
    geo.M={key:geo.material(label,color,metal,rough,emission) for key,label,color,metal,rough,emission in (
        ('paint',name+' coated armor',s['color'],.24,.38,0),
        ('dark','Dark mechanical structure',(.019,.023,.025),.55,.46,0),
        ('graphite','Graphite armor',(.052,.058,.064),.68,.40,0),
        ('gunmetal','Gunmetal',(.12,.14,.16),.90,.31,0),
        ('steel','Brushed titanium',(.26,.29,.32),.92,.30,0),
        ('recess','Deep panel recess',(.006,.009,.012),0,.56,0),
        ('light',name+' sensor emission',s['light'],0,.35,2.0))}
    armor(s,name)
    outriggers(s,name)
    drives(s,name)
    weapons(s,name)
    fittings(s,name)
    root=bpy.data.objects.new(name,None)
    bpy.context.scene.collection.objects.link(root)
    for obj in geo.PARTS:
        obj.parent=root
    root['forward_axis']='-Y, Z up'
    root['reference']='Approved outer-sector concept packed in References'
    root['drive_count']=len(s['drives'])
    review.HERE=HERE
    review.surfaces.SIZE=1024 if draft else 4096
    review.texture_parts(name)
    cameras=studio(name,draft)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.render.filepath=str(HERE/'previews'/(name.lower()+'.png'))
    if not draft:
        bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'models'/(name.lower()+'.blend')),compress=True)
    stats=dict(mesh_components=len(geo.PARTS),base_faces=sum(len(o.data.polygons) for o in geo.PARTS),
               atlas_size=review.surfaces.SIZE,drive_count=len(s['drives']),draft=draft)
    for view,camera in cameras.items():
        if draft and view not in ('perspective','top'):
            continue
        bpy.context.scene.camera=camera
        suffix='' if view=='perspective' else '-'+view
        bpy.context.scene.render.filepath=str(HERE/'previews'/(name.lower()+suffix+'.png'))
        bpy.ops.render.render(write_still=True)
        print('RENDERED',name,view,flush=True)
    if not draft:
        stats['export']=review.export_model(name)
    path=HERE/('draft-stats.json' if draft else 'build-stats.json')
    report=json.loads(path.read_text()) if path.exists() else {}
    report[name]=stats
    path.write_text(json.dumps(report,indent=2)+'\n')
    print('COMPLETE',name,stats,flush=True)


if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    names=[a for a in args if not a.startswith('--')] or list(NAMES)
    if set(names)-set(NAMES) or set(a for a in args if a.startswith('--'))-{'--draft'}:
        raise ValueError('Use roster names and optional --draft')
    for folder in ('models','materials','previews','exports'):
        (HERE/folder).mkdir(parents=True,exist_ok=True)
    for name in names:
        build(name,'--draft' in args)
