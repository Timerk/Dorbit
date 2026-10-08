"""Reference-led armor and machinery for the three alien review meshes.

Large plates follow the hull/wing surfaces; joints expose actual mechanisms.
All small seams, louvers, collars and fasteners are editable mesh components.
"""
import math

import bmesh
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

import build_models as geo


def shell(label, points, depth=.045, material='paint', normal=(0, 0, 1)):
    """Triangulated, contoured armor, including a separate inset gasket seat."""
    points = [Vector(p) for p in points]
    direction = Vector(normal).normalized()
    count = len(points)
    # Tessellate in a stable projection, then restore the authored contour.
    dominant = max(range(3), key=lambda i: abs(direction[i]))
    axes = [i for i in range(3) if i != dominant]
    projected = [Vector((p[axes[0]], p[axes[1]], 0)) for p in points]
    triangles = [tuple(p if isinstance(p,int) else projected.index(p) for p in triangle)
                 for triangle in tessellate_polygon([projected])]
    faces = [tuple(reversed(t)) for t in triangles]
    faces += [tuple(i+count for i in t) for t in triangles]
    faces += [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
    def make(name, outline, thickness, mat, bevel):
        vertices = [tuple(p-direction*thickness/2) for p in outline]
        vertices += [tuple(p+direction*thickness/2) for p in outline]
        obj = geo.mesh(name, vertices, faces, mat, bevel)
        obj['detail_family'] = 'contoured armor'
        obj['wear_outline'] = [float(c) for p in outline for c in p]
        obj['wear_axis'] = dominant
        return obj
    center = sum(points, Vector())/count
    seat = [center+(p-center)*1.035-direction*.020 for p in points]
    make(label+' recessed frame', seat, depth+.016, 'graphite', .004)
    return make(label, points, depth, material, min(.007, depth*.15))


def interpolate(stations, y):
    for a,b in zip(stations,stations[1:]):
        if y <= b[0]:
            t = max(0, min(1, (y-a[0])/(b[0]-a[0])))
            return tuple(a[i]+(b[i]-a[i])*t for i in range(1,len(a)))
    return stations[-1][1:]


def hull_point(spec, side, u, y, lift=.055, bottom=False):
    w,h,z = interpolate(spec['body'], y)
    profile = 1 if u <= .65 else 1-(u-.65)*.55/.35
    return (side*w*u, y, z+(-h*profile-lift if bottom else h*profile+lift))


def fitted_hull(label, spec, side, ya, yb, outline, mat='paint', lift=.055,
                depth=.05, bottom=False):
    # Follow every underlying hull break along long armor edges; a flat bridge
    # across several stations would disappear into the keel at its widest point.
    expanded=[]
    for a,b in zip(outline,outline[1:]+outline[:1]):
        expanded.append(a)
        breaks=[]
        for station in spec['body'][1:-1]:
            t=(station[0]-ya)/(yb-ya)
            if min(a[1],b[1])+1e-5<t<max(a[1],b[1])-1e-5:
                f=(t-a[1])/(b[1]-a[1])
                breaks.append((f,(a[0]+(b[0]-a[0])*f,t)))
        expanded.extend(point for _,point in sorted(breaks))
    outline=expanded
    points = [hull_point(spec,side,u,ya+(yb-ya)*t,lift,bottom) for u,t in outline]
    return shell(label,points,depth,mat,(0,0,-1) if bottom else (0,0,1))


def fastener(loc, radius=.015, axis=(0,0,1)):
    geo.bolt(Vector(loc), axis=axis, radius=radius)


def body(spec: dict, heavy: bool = False) -> None:
    geo.group('Hull | interlocking carapace and recessed spine')
    stations = spec['body']
    geo.loft('Continuous graphite keel',[(0,y,z,w,h) for y,w,h,z in stations], 'dark', .025)
    for side in (-1,1):
        prefix = 'Port' if side<0 else 'Starboard'
        # Long pointed forward plates, angular midbody armor and narrow aft cowl.
        spans = [(0,3),(3,4),(4,5),(5,6)]
        for i,(a,b) in enumerate(spans):
            ya,yb = stations[a][0]+.045,stations[b][0]-.045
            center_outline = [(.045,.03),(.38,.015),(.60,.23),(.57,.68),
                              (.42,.95),(.045,.89)]
            fitted_hull(prefix+f' spearhead coat panel {i+1}',spec,side,ya,yb,
                        center_outline,'paint',.073,.065 if heavy else .045)
            outer_outline = [(.64,.08),(.89,.015),(1.025,.32),(.98,.84),
                             (.75,.97),(.62,.73),(.69,.52)]
            fitted_hull(prefix+f' faceted flank shield {i+1}',spec,side,ya,yb,
                        outer_outline,'paint' if heavy and i in (1,2) else 'graphite',
                        .062,.080 if heavy else .058)
            # Thin lapped strips and sloping secondary cheek armor.
            fitted_hull(prefix+f' outer chine blade {i+1}',spec,side,ya,yb,
                        [(1.04,.14),(1.085,.23),(1.075,.75),(1.015,.90)],
                        'gunmetal',.008,.023)
            fitted_hull(prefix+f' ventral segmented shield {i+1}',spec,side,ya,yb,
                        [(.08,.09),(.58,.025),(.87,.27),(.82,.78),(.49,.96),(.08,.84)],
                        'graphite',.050,.055,True)
            if i:
                for u,t in ((.50,.27),(.82,.70)):
                    fastener(hull_point(spec,side,u,ya+(yb-ya)*t,.125),.016 if heavy else .012)
            # Offset stepped interlock at the rear of each armor segment.
            fitted_hull(prefix+f' armor locking tab {i+1}',spec,side,ya,yb,
                        [(.43,.80),(.60,.73),(.68,.88),(.50,.98)], 'gunmetal',.102,.026)
        # Upper crown is a long narrow beveled ridge, not repeated rectangular hatches.
        for i,(a,b) in enumerate(zip(stations[1:-1],stations[2:])):
            if i<2:
                continue
            ya,yb=a[0]+.08,b[0]-.07
            fitted_hull(prefix+f' central graphite crown {i}',spec,side,ya,yb,
                        [(.03,.06),(.18,.01),(.27,.28),(.22,.80),(.035,.96)],
                        'graphite',.132,.034)
        # Deep visible side bay: backplate, cylinders, stepped rails and armored visor.
        for index,y in enumerate((-.90,.16)):
            w,h,z = interpolate(stations,y)
            x=side*(w+.055)
            geo.box(prefix+f' flank service bay {index}',(x,y,z-.025),
                    (.085,.73,.27),'recess',.012)
            for j in range(4):
                cy=y-.26+j*.17
                geo.tube(prefix+' exposed pressure canister',(x+side*.065,cy,z-.135),
                         (x+side*.065,cy,z+.070),.043,'gunmetal',vertices=12,bevel=.004)
                geo.tube(prefix+' canister retaining ferrule',(x+side*.065,cy,z-.033),
                         (x+side*.065,cy,z+.002),.056,'steel',vertices=12,bevel=.002)
            geo.pipe(prefix+' bay hydraulic return',[(x+side*.12,y-.34,z-.13),
                     (x+side*.12,y-.34,z-.19),(x+side*.12,y+.33,z-.19)],.015,'steel')
            for dz in (-.15,.15):
                geo.box(prefix+' service bay rim',(x+side*.07,y,z+dz),
                        (.055,.78,.043),'graphite',.008)
        # Recessed spine instrumentation and fine split louvers towards the aft hull.
        for j in range(7 if heavy else 5):
            y=.50+j*.13
            w,h,z=interpolate(stations,y)
            geo.box(prefix+' dorsal cooling slit',(side*w*.38,y,z+h+.12),
                    (w*.24,.055,.018),'recess',.003)
            geo.box(prefix+' dorsal louver',(side*w*.38,y+.016,z+h+.14),
                    (w*.24,.018,.024),'gunmetal',.004)
    if heavy:
        geo.group('Hull | Heavy raised command carapace')
        points=[]
        for x,y in ((-.35,-.82),(.35,-.82),(.65,-.43),(.57,.19),
                    (.28,.53),(-.28,.53),(-.57,.19),(-.65,-.43)):
            w,h,z=interpolate(stations,y)
            points.append((x,y,z+h+.23))
        shell('Heavy overlapping dorsal command shield',points,.10,'paint')
        for side in (-1,1):
            for y in (-.45,.05):
                w,h,z=interpolate(stations,y)
                fastener((side*.44,y,z+h+.31),.025)
        geo.group('Hull | Heavy overlapping lower armor')
        geo.loft('Heavy secondary ventral armor block',[(0,-2,-.33,.39,.21),
                 (0,-1.1,-.55,.92,.30),(0,.10,-.62,1.1,.36),
                 (0,1.27,-.48,.79,.30),(0,1.78,-.23,.48,.19)],'dark',.035)
        for side in (-1,1):
            for i,y in enumerate((-.9,-.23,.44)):
                shell(f'Heavy belly overlapping plate {side} {i}',
                      [(side*.15,y-.27,-1.00),(side*.67,y-.30,-.95),
                       (side*.9,y-.09,-.87),(side*.8,y+.23,-.90),
                       (side*.34,y+.31,-.99),(side*.15,y+.16,-1.00)],
                      .085,'paint',(0,0,-1))


def wing_point(stations,side,u,y,lift=.04):
    inner,outer,z=interpolate(stations,y)
    return (side*(inner+(outer-inner)*u),y,z+lift)


def wing_shell(prefix,side,stations,depth):
    vertices=[]
    for y,inner,outer,z in stations:
        vertices += [(side*inner,y,z),(side*outer,y,z),
                     (side*outer,y,z-depth),(side*inner,y,z-depth)]
    faces=[tuple(reversed(range(4)))]
    for j in range(len(stations)-1):
        faces += [(j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k) for k in range(4)]
    faces.append(tuple(range(len(vertices)-4,len(vertices))))
    geo.mesh(prefix+' curved talon subframe',vertices,faces,'dark',.015)


def joint(prefix,a,b,radius):
    a,b=Vector(a),Vector(b)
    delta=b-a
    geo.tube(prefix+' actuator piston',a,b,radius,'steel',vertices=12,bevel=.003)
    geo.tube(prefix+' ribbed actuator sleeve',a,a+delta*.62,radius*1.55,
             'dark',vertices=12,bevel=.005)
    for i in range(5):
        p=a+delta*(.07+i*.11)
        geo.tube(prefix+' hydraulic collar',p,p+delta.normalized()*.036,
                 radius*1.65,'gunmetal',vertices=12,bevel=.002)
    geo.pipe(prefix+' braided bypass cable',[a+Vector((0,0,-radius*1.6)),
             a+delta*.45+Vector((0,0,-radius*2.1)),
             b+Vector((0,0,-radius*1.6))],radius*.22,'dark')


def wings(spec: dict, name: str) -> None:
    geo.group('Wings | layered talon armor and articulated roots')
    stations,depth=spec['wing'],spec['wing_depth']
    heavy=name=='Heavy'
    for side in (-1,1):
        prefix='Port' if side<0 else 'Starboard'
        wing_shell(prefix,side,stations,depth)
        for i,(a,b) in enumerate(zip(stations,stations[1:])):
            ya,yb=a[0]+.025,b[0]-.025
            # Nested angular coat plates expose thick graphite leading edges.
            outlines = [
                [(.10,.11),(.61,.04),(.86,.31),(.77,.78),(.35,.97),(.09,.73)],
                [(.07,.07),(.58,.02),(.83,.22),(.91,.63),(.72,.95),(.18,.86),(.08,.58)],
            ]
            outline=outlines[i%2]
            points=[wing_point(stations,side,u,ya+(yb-ya)*t,.065) for u,t in outline]
            shell(prefix+f' angular talon armor {i}',points,.065 if heavy else .043,
                  'graphite' if i in (0,4) else 'paint')
            # Independently fitted hard leading-edge blade with exposed bevels.
            edge=[(.82,.06),(1.015,.02),(1.015,.94),(.86,.89),(.79,.64)]
            shell(prefix+f' talon machined edge blade {i}',
                  [wing_point(stations,side,u,ya+(yb-ya)*t,.018) for u,t in edge],
                  .056,'gunmetal')
            if i in (1,2,3):
                under=[wing_point(stations,side,u,ya+(yb-ya)*t,-depth-.035) for u,t in outline]
                shell(prefix+f' talon underside panel {i}',under,.038,'graphite',(0,0,-1))
                for u,t in ((.21,.25),(.68,.73)):
                    fastener(wing_point(stations,side,u,ya+(yb-ya)*t,.115),.012)
                # Small stepped seam interrupter, visibly following the bend.
                tab=[(.13,.77),(.31,.73),(.42,.92),(.18,.98)]
                shell(prefix+f' talon seam lock {i}',
                      [wing_point(stations,side,u,ya+(yb-ya)*t,.093) for u,t in tab],.021,'steel')
        inner=.50 if name=='Scout' else .78 if name=='Sentinel' else 1.08
        for index,y in enumerate((-.46,.58)):
            outer=1.92 if name!='Heavy' else 2.31
            z=.07 if index==0 else .30
            if heavy: z+=.12
            # Thick angular fork mounts, with the hydraulic cylinder exposed below.
            outline=[(side*inner,y-.21,z),(side*(inner+.26),y-.27,z+.03),
                     (side*outer,y+.04,z+.035),(side*(outer+.05),y+.20,z),
                     (side*(inner+.13),y+.10,z)]
            shell(prefix+f' articulated wing root fork {index}',outline,.16,'graphite')
            joint(prefix+f' wing root {index}',(side*(inner+.15),y-.05,z-.14),
                  (side*(outer-.14),y+.12,z-.14),.046 if not heavy else .065)
            for x in (inner+.16,outer-.12):
                geo.tube(prefix+' wing pivot socket',(side*x,y+.025,z-.13),
                         (side*x,y+.025,z+.10),.102 if not heavy else .14,
                         'gunmetal',vertices=12,bevel=.006)
                fastener((side*x,y+.025,z+.117),.030 if heavy else .022)
        # Split shoulders: broad swept plates plus a raised, notched rear layer.
        z=.46 if name=='Scout' else .63 if name=='Sentinel' else .88
        outer=1.88 if not heavy else 2.48
        for j in range(2):
            y=.10+j*.64
            shell(prefix+f' swept shoulder carapace {j}',
                  [(side*inner,y,z+.03-j*.07),(side*(outer-.29),y+.09,z+.025-j*.07),
                   (side*outer,y+.35,z-.045-j*.07),(side*(outer-.10),y+.58,z-.11-j*.07),
                   (side*(inner+.28),y+.63,z-.09-j*.07),
                   (side*(inner+.07),y+.41,z+.01-j*.07)],.095 if heavy else .058,'paint')
            for k in range(2):
                fastener((side*(inner+.30+k*.33),y+.22,z+.11-j*.07),.017)
        # A real dark recess between shoulder layers holds five staggered fins.
        for j in range(5):
            geo.box(prefix+' shoulder heat exchanger',(side*(inner+.22+j*.115),.76,z+.06),
                    (.058,.29,.066),'gunmetal',.008)
        if heavy:
            shell(prefix+' overlapping heavy shoulder guard',
                  [(side*1.34,-.13,.96),(side*1.97,-.17,.99),
                   (side*2.50,.17,.89),(side*2.36,.51,.88),
                   (side*1.79,.57,.94),(side*1.48,.33,.99)],.11,'graphite')


def annulus(label,x,y,z,radius,depth,mat='steel',stretch=1):
    vertices=[]
    n=16
    for offset,r in ((0,radius),(-depth,radius*.94),(-depth,radius*.69),(0,radius*.75)):
        vertices += [(x+math.cos(i*math.tau/n)*r,y+offset,
                      z+math.sin(i*math.tau/n)*r*stretch) for i in range(n)]
    faces=[(j*n+i,j*n+(i+1)%n,((j+1)%4)*n+(i+1)%n,((j+1)%4)*n+i)
           for j in range(4) for i in range(n)]
    return geo.mesh(label,vertices,faces,mat,.005)


def engines(spec: dict) -> None:
    geo.group('Engines | armored drives, turbine throats and cooling machinery')
    r,length=spec['engine_radius'],spec['engine_length']
    y0,z=spec['engine_y'],spec['engine_z']
    heavy=r>.6
    sentinel=.4<r<.6
    for side in (-1,1):
        prefix='Port' if side<0 else 'Starboard'
        x=side*spec['engine_x']
        # Ribbed exposed neck in front of the enlarged faceted drive pod.
        joint(prefix+' drive neck',(x,y0-.44,z),(x,y0+.20,z),r*.39)
        housing=geo.loft(prefix+' drive structural casing',
                        [(x,y0+.16,z,r*.79,r*.76),(x,y0+.48,z,r*1.04,r*1.08),
                         (x,y0+length-.30,z,r*1.05,r*1.08),
                         (x,y0+length,z,r*.94,r)],'dark',.018)
        bm=bmesh.new(); bm.from_mesh(housing.data)
        rear=[f for f in bm.faces if all(abs(v.co.y-(y0+length))<1e-6 for v in f.verts)]
        assert len(rear)==1
        bmesh.ops.delete(bm,geom=rear,context='FACES'); bm.to_mesh(housing.data); bm.free()
        # Broad polygonal coat segments wrap around multiple octagonal facets.
        for flank in (-1,1):
            for i in range(2):
                ya=y0+.43+i*(length-.56)/2
                yb=ya+(length-.56)/2-.055
                shell(prefix+f' drive upper angular cowl {flank} {i}',
                      [(x+flank*r*.12,ya,z+r*1.105),(x+flank*r*.52,ya-.04,z+r*1.105),
                       (x+flank*r*.83,ya+.14,z+r*.81),
                       (x+flank*r*.83,yb-.13,z+r*.81),
                       (x+flank*r*.57,yb,z+r*1.105),(x+flank*r*.12,yb-.02,z+r*1.105)],
                      .052,'paint' if i==0 or sentinel else 'graphite')
                points=[(x+flank*r*1.10,ya+.10,z+r*.43),
                        (x+flank*r*1.10,yb-.05,z+r*.43),
                        (x+flank*r*1.10,yb+.04,z-r*.28),
                        (x+flank*r*1.10,ya+.24,z-r*.50)]
                shell(prefix+f' drive side shield {flank} {i}',points,.07,
                      'paint' if i==0 else 'graphite',(flank,0,0))
                for cy in (ya+.19,yb-.13):
                    fastener((x+flank*r*1.15,cy,z+r*.18),.016,(flank,0,0))
        # Raised longitudinal spine, service hatch, finned heat exchanger/intake.
        geo.loft(prefix+' drive crown rail',[(x,y0+.31,z+r*1.16,r*.17,.035),
                 (x,y0+length-.15,z+r*1.16,r*.13,.035)],'gunmetal',.009)
        geo.box(prefix+' recessed drive intake',(x,y0+.53,z+r*1.13),
                (r*.65,.40,.065),'recess',.009)
        for j in range(6):
            geo.box(prefix+' intake louver',(x,y0+.36+j*.063,z+r*1.18),
                    (r*.61,.032,.028),'gunmetal',.005)
        for j in range(7):
            cy=y0+.65+j*.125
            geo.box(prefix+' drive side cooling recess',(x+side*r*1.135,cy,z-.03),
                    (.013,.064,r*.36),'recess',.002)
            geo.box(prefix+' drive cooling lip',(x+side*r*1.148,cy+.028,z-.03),
                    (.018,.013,r*.34),'gunmetal',.002)
        tail=y0+length+.06
        stretch=1.16 if heavy else 1.05 if sentinel else 1
        annulus(prefix+' armored nozzle surround',x,tail,z,r*1.01,.22,'graphite',stretch)
        annulus(prefix+' machined nozzle lip',x,tail+.025,z,r*.89,.11,'steel',stretch)
        annulus(prefix+' deep turbine throat',x,tail-.11,z,r*.66,.25,'gunmetal',stretch)
        geo.tube(prefix+' recessed exhaust well',(x,tail-.37,z),(x,tail-.35,z),
                 r*.56,'recess',vertices=16,bevel=0)
        # A center emitter remains unobstructed for export/source ray validation.
        geo.tube(prefix+' exhaust emitter',(x,tail-.345,z),(x,tail-.335,z),
                 r*(.18 if heavy or sentinel else .27),'light',vertices=16,bevel=0)
        for j in range(12):
            a=j*math.tau/12
            geo.tube(prefix+' turbine stator vane',
                     (x+math.cos(a)*r*.38,tail-.25,z+math.sin(a)*r*.38*stretch),
                     (x+math.cos(a+.09)*r*.70,tail-.08,z+math.sin(a+.09)*r*.70*stretch),
                     r*.031,'steel',vertices=6,bevel=.0015)
            if j%2==0:
                fastener((x+math.cos(a)*r*.945,tail+.04,z+math.sin(a)*r*.945*stretch),
                         r*.035,(0,1,0))
        if heavy or sentinel:
            # Reference identities: vertical Sentinel slit; paired Heavy crossbars.
            if sentinel:
                geo.box(prefix+' vertical exhaust grille',(x,tail-.29,z),
                        (r*.20,.018,r*.91),'light',.004)
                for j in range(9):
                    if j==4:
                        continue
                    geo.box(prefix+' vertical exhaust grille separator',
                            (x,tail-.27,z-r*.39+j*r*.098),(r*.25,.019,.014),'dark',.002)
            else:
                for dz in (-r*.22,r*.22):
                    geo.box(prefix+' heavy exhaust crossbar',(x,tail-.29,z+dz),
                            (r*.68,.023,.048),'light',.004)
        geo.pipe(prefix+' external coolant return',[(x-side*r*.88,y0+.19,z-.15),
                 (x-side*r*1.03,y0+.42,z-.32),
                 (x-side*r*1.03,y0+length-.30,z-.32)],.022,'steel')


def weapons_and_sensors(spec: dict, name: str) -> None:
    geo.group('Weapons | armored forward cannons and cooling jackets')
    radius=spec['barrel_radius']
    x=.20 if name=='Scout' else .32 if name=='Sentinel' else .43
    front=spec['body'][0][0]
    for side in (-1,1):
        prefix='Port' if side<0 else 'Starboard'
        z=-.02 if name=='Scout' else -.06
        geo.loft(prefix+' angled cannon socket',[(side*x,front+.54,z,radius*2.0,radius*1.8),
                 (side*x,front-.08,z,radius*1.5,radius*1.35)],'graphite',.012)
        for index,dz in enumerate((0,-.23) if name=='Heavy' else (0,)):
            zz=z+dz
            geo.tube(prefix+f' cannon barrel {index}',(side*x,front+.04,zz),
                     (side*x,front-.69,zz),radius*.82,'gunmetal',vertices=12,bevel=.004)
            for j in range(4):
                cy=front-.12-j*.13
                geo.tube(prefix+' cannon cooling collar',(side*x,cy,zz),
                         (side*x,cy-.037,zz),radius*1.13,'steel',vertices=12,bevel=.002)
            annulus(prefix+' hollow muzzle collar',side*x,front-.65,zz,radius*1.12,-.09,'graphite')
            geo.tube(prefix+' recessed muzzle well',(side*x,front-.715,zz),
                     (side*x,front-.720,zz),radius*.70,'recess',vertices=12,bevel=0)
            geo.tube(prefix+' recessed laser optic',(side*x,front-.721,zz),
                     (side*x,front-.725,zz),radius*.39,'light',vertices=12,bevel=0)
    geo.group('Sensors | armored inset optics and service connectors')
    y=spec['body'][2][0]+.16
    w,h,z=interpolate(spec['body'],y)
    for side in (-1,1):
        prefix='Port' if side<0 else 'Starboard'
        x=side*(w+.085)
        # Polygonal angled visor around a deep slit, with segmented optical lens.
        shell(prefix+' sensor armored visor',[(x,y-.36,z+.15),(x,y+.30,z+.17),
              (x,y+.40,z+.05),(x,y+.26,z-.12),(x,y-.28,z-.13),(x,y-.40,z-.02)],
              .06,'graphite',(side,0,0))
        geo.box(prefix+' dark optical well',(x+side*.044,y,z+.015),
                (.020,.58,.105),'recess',.006)
        geo.box(prefix+' machined optical lip',(x+side*.051,y,z+.088),
                (.014,.55,.018),'steel',.003)
        geo.box(prefix+' recessed sensor slit',(x+side*.060,y,z+.018),
                (.012,.47,.034),'light',.002)
        for cy in (y-.29,y+.29):
            fastener((x+side*.065,cy,z-.047),.014,(side,0,0))
        # Rear-facing telemetry modules, small connector covers and antenna fins.
        for j in range(3):
            cy=.23+j*.18
            w,h,z=interpolate(spec['body'],cy)
            geo.box(prefix+' telemetry module',(side*w*.79,cy,z+h*.80+.13),
                    (.09,.12,.035),'graphite',.007)
            geo.box(prefix+' telemetry status lens',(side*w*.79,cy-.015,z+h*.80+.152),
                    (.046,.021,.009),'light',.001)
