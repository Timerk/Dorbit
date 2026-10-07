"""Editable construction guided by the 2026 Dorbit concept turnarounds.

The concept images are design references, not calibrated geometry. Keep the
catalogue silhouettes and use explicit mesh construction for repeatable views.
"""
import math
from types import ModuleType

import bpy
from mathutils import Vector


def finish_palette(b: ModuleType, name: str) -> None:
    colors = {
        'silver': ((.37, .42, .47), .78, .33),
        'steel': ((.28, .34, .39), .78, .28),
        'pale': ((.65, .69, .72), .70, .26),
        'dark': ((.014, .022, .029), .48, .40),
        'gunmetal': ((.066, .084, .10), .70, .32),
        'graphite': ((.045, .060, .079), .60, .35),
        'bluegrey': ((.052, .125, .27), .65, .33),
        'cobalt': ((.025, .095, .35), .58, .28),
        'forest': ((.040, .16, .075), .53, .30),
        'green': ((.045, .19, .050), .53, .30),
        'sage': ((.15, .29, .23), .58, .31),
        'red': ((.40, .014, .023), .45, .26),
        'glass': ((.008, .023, .032), .38, .17),
        'blueglass': ((.035, .105, .21), .43, .19),
        'oliveglass': ((.085, .105, .035), .40, .19),
        'copper': ((.40, .18, .032), .66, .29),
    }
    if name == 'Goliath':
        colors['glass'] = ((.17, .065, .008), .42, .18)
    if name == 'Nostromo':
        colors['silver'] = ((.20, .25, .30), .74, .30)
        colors['steel'] = ((.14, .18, .23), .72, .30)
    if name == 'Phoenix':
        colors['blueglass'] = ((.18, .28, .34), .44, .18)
    for key, (color, metal, rough) in colors.items():
        mat = b.M[key]
        mat.diffuse_color = (*color, 1)
        bs = mat.node_tree.nodes.get('Principled BSDF')
        bs.inputs['Base Color'].default_value = (*color, 1)
        bs.inputs['Metallic'].default_value = metal
        bs.inputs['Roughness'].default_value = rough
        bs.inputs['Coat Weight'].default_value = .12 if key in {
            'bluegrey', 'cobalt', 'forest', 'green', 'red', 'sage'} else .06
        bs.inputs['Coat Roughness'].default_value = .24
        for node in mat.node_tree.nodes:
            if node.type == 'BUMP':
                node.inputs['Strength'].default_value = .035
                node.inputs['Distance'].default_value = .002


def hatch(b: ModuleType, label: str, corners: list[tuple[float, float, float]],
          paint: str = 'steel', normal: tuple[float, float, float] = (0, 0, 1)) -> None:
    """Fitted access panel with a real dark perimeter gap and flush latch."""
    normal = Vector(normal).normalized()
    center = sum((Vector(p) for p in corners), Vector()) / len(corners)
    b.panel(label + ' recessed seat', corners, .010, 'recess', .002, normal)
    plate = [tuple(center + (Vector(p) - center) * .86 + normal * .011)
             for p in corners]
    b.panel(label + ' removable plate', plate, .012, paint, .003, normal)
    b.tube(label + ' captive latch', center + normal * .018,
           center + normal * .024, .014, 'gunmetal', vertices=8, bevel=0)


def annular_pod(b: ModuleType, side: int) -> None:
    """Liberator's circular machinery well sits inside a segmented armor pod."""
    cx, cy = side * 1.24, -.58
    for k in range(12):
        points = []
        for a in [k * math.tau / 12 + .018,
                  (k + 1) * math.tau / 12 - .018]:
            for rx, ry in [(.245, .245), (.51, .49)]:
                points.append((cx + side * rx * math.cos(a),
                               cy + ry * math.sin(a), .078))
        # Inner-a, outer-a, outer-b, inner-b.
        points = [points[i] for i in [0, 1, 3, 2]]
        b.panel('Concept turbine pod structural sector', points, .12, 'dark', .008)
        raised = [(x, y, z + .073) for x, y, z in points]
        b.panel('Concept turbine pod armor sector', raised, .025,
                'silver' if k % 4 else 'bluegrey', .005)
    b.ring('Concept pod lower bumper', (cx, cy, -.035), .445, .032, 'gunmetal')
    for yy in [-.81, -.39]:
        b.box('Concept pod amber identification',
              (side * 1.65, yy, .225), (.052, .075, .010), 'copper', .002)


def liberator(b: ModuleType) -> None:
    b.remove_parts(('Needle fuselage', 'Sculpted broad outer pod',
                    'Outer pod split shell', 'Outer pod recessed perimeter',
                    'Pod dark radial armor break', 'Long channel actuator',
                    'Actuator dark sleeve', 'Exposed channel crossmember',
                    'Channel recessed equipment cell', 'Channel cell inset face',
                    'Narrow channel drive', 'Pod rear cooling'))
    b.rounded_hull('Concept streamlined needle fuselage', [
        (0, -2.70, -.11, .014, .014), (0, -1.75, -.02, .15, .08),
        (0, -.77, .10, .29, .18), (0, .19, .22, .36, .25),
        (0, 1.03, .20, .31, .20), (0, 1.62, .12, .18, .11)], 'bluegrey')
    # Turbine assembly stays mechanically attached to the low swept carrier.
    b.reshape(('Pod circular', 'Pod inner', 'Pod hub', 'Pod radial'),
              lambda p: (p.x, p.y, p.z + .098))
    for s in [-1, 1]:
        annular_pod(b, s)
        b.tube('Concept channel drive backbone', (s * .86, -.49, .125),
               (s * .86, 1.59, .275), .082, 'steel', bevel=.003)
        b.tube('Concept drive dark sleeve', (s * .86, .77, .216),
               (s * .86, 1.38, .260), .12, 'gunmetal', bevel=.005)
        for j in range(4):
            y = .78 + j * .145
            z = .125 + (y + .49) * .15 / 2.08
            b.tube('Concept segmented blue drive cowl', (s * .86, y, z),
                   (s * .86, y + .115, z + .0083), .129, 'bluegrey', bevel=.004)
            b.ring('Concept drive cowl silver joint', (s * .86, y + .123, z + .009),
                   .126, .008, 'steel', (0, 1, .072))
        for j in range(7):
            y = .32 + j * .06
            z = .125 + (y + .49) * .15 / 2.08
            b.ring('Concept exposed drive cooling fin', (s * .86, y, z),
                   .099, .005, 'gunmetal', (0, 1, .072))
        for y in [-.31, -.12, .10, 1.39]:
            z = .125 + (y + .49) * .15 / 2.08
            b.ring('Concept drive copper collar', (s * .86, y, z),
                   .09, .016, 'copper', (0, 1, .072))
        b.nozzle('Concept aft circular drive', (s * .86, 1.94, .285),
                 (0, 1, 0), .205, .44, True)
        hatch(b, 'Concept blue fuselage shoulder hatch', [
            (s * .20, .49, .432), (s * .29, .52, .403),
            (s * .23, .86, .392), (s * .17, .82, .417)], 'bluegrey')
        b.pipe('Concept nose fine copper coachline', [
            (s * .040, -2.34, -.050), (s * .104, -1.57, .083),
            (s * .205, -.84, .251)], .005, 'copper')


def goliath(b: ModuleType) -> None:
    # The new study has a substantial split crown, open inner channels and
    # stronger arm roots. Keep the planform while giving the arms real depth.
    b.reshape(('Continuous curved arm', 'Sculpted silver arm', 'Inner arm conduit',
               'Arm ', 'Fine arm armor', 'Layered arm edge', 'Fitted dark arm'),
              lambda p: (p.x, p.y, p.z * 1.28))
    b.remove_parts(('Fitted dark arm crown inset', 'Layered arm edge bead',
                    'Outer swept arm winglet', 'Winglet inset armor',
                    'Winglet panel channel', 'Arm flank dark port', 'Arm inset pale insert',
                    'Small tail crest', 'Tail dorsal ridge'))
    # Winglet fasteners were unnamed in the old builder; remove them with the
    # deleted plates so they cannot remain suspended outside the new silhouette.
    for obj in list(b.PARTS):
        if obj.name.startswith(('Recessed fastener', 'Hex socket screw')) and any(
            abs(abs(obj.location.x) - x) < .001 and abs(obj.location.y - y) < .001
            for x, y in [(2.38, -1.12), (2.68, -.76)]):
            b.PARTS.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
    b.reshape(('Raised swept dorsal fin', 'Dorsal fin inset', 'Dorsal fin leading'),
              lambda p: ((1 if p.x > 0 else -1) * (.36 + (abs(p.x) - .36) * .26),
                         p.y, .36 + (p.z - .36) * 1.45))
    for s in [-1, 1]:
        for j in range(6):
            lo = .95 + j * .97
            verts = []
            for row in range(13):
                t = lo + row * .84 / 12
                x, y, z, w, h = b.arm_station(t)
                p, q = b.arm_station(t - .002), b.arm_station(t + .002)
                tangent = Vector((q[0] - p[0], q[1] - p[1], 0)).normalized()
                across = Vector((-tangent.y, tangent.x, 0))
                for u in [-.43, .22]:
                    verts.append((s * (x + across.x * w * u),
                                  y + across.y * w * u,
                                  (z + h * (1.07 - (u + .47) * .09 / .82)) * .9984 + .015))
            obj = b.mesh('Concept split silver arm crown', verts,
                         [(r * 2, r * 2 + 1, r * 2 + 3, r * 2 + 2)
                          for r in range(12)], 'silver', 0, True)
            obj.modifiers.new('Crown wall thickness', 'SOLIDIFY').thickness = .015
            t = lo + .42
            x, y, z, w, h = b.arm_station(t)
            b.box('Concept arm amber service marker', (s * x, y, z + h + .04),
                  (.058, .070, .008), 'copper', .002)
            # Curved rectangular bays are fitted to the inner arm wall.
            bay = []
            for t, level in [(lo + .13, -.35), (lo + .74, -.35),
                             (lo + .74, .28), (lo + .13, .28)]:
                x, y, z, w, h = b.arm_station(t)
                p, q = b.arm_station(t - .002), b.arm_station(t + .002)
                tangent = Vector((q[0] - p[0], q[1] - p[1], 0)).normalized()
                across = Vector((-tangent.y, tangent.x, 0))
                bay.append((s * (x - across.x * w * .99),
                            y - across.y * w * .99, z + h * level))
            outward = Vector((-s * across.x, -across.y, 0)).normalized()
            b.panel('Concept inner arm recessed service bay', bay,
                    .022, 'recess', .003, outward)
            rim = [tuple(Vector(p) + outward * .014) for p in bay]
            b.pipe('Concept inner arm machined bay frame', rim + [rim[0]], .010, 'steel')
            for fraction in [.28, .62]:
                a = Vector(bay[0]).lerp(Vector(bay[1]), fraction) + outward * .018
                c = Vector(bay[3]).lerp(Vector(bay[2]), fraction) + outward * .018
                b.tube('Concept arm exposed transverse brace', a, c, .013,
                       'gunmetal', vertices=8, bevel=.002)
        hatch(b, 'Concept assault shoulder cover', [
            (s * .35, .33, .45), (s * .54, .37, .45),
            (s * .50, .80, .48), (s * .32, .75, .49)], 'silver')
    b.remove_parts(('Inset bronze bridge', 'Bridge canopy rim'))
    b.arched_canopy('Concept amber assault bridge', [
        (-.79, .078, .088, .045), (-.45, .205, .16, .09),
        (-.21, .28, .14, .072), (-.13, .28, .082, .036)], 'glass', 'silver')


def nostromo_profile(p: Vector) -> tuple[float, float, float]:
    """Lengthen the forebody and narrow its blunt bow into a tapered point."""
    taper = min(1.0, max(0.0, (-p.y - .55) / 1.50)) ** 2
    return (p.x * (1.0 - .86 * taper),
            .05 + (p.y - .05) * 1.55 if p.y < .05 else p.y,
            -.10 + (p.z + .10) * (1.0 - .35 * taper))


def ship_fittings(b: ModuleType, name: str) -> None:
    """Macro assemblies specific to each concept; never scatter free detail."""
    if name == 'Liberator':
        liberator(b)
    elif name == 'Goliath':
        goliath(b)
    elif name == 'Aegis':
        for s in [-1, 1]:
            b.panel('Concept engineering socket collar cheek', [
                (s * .35, -.72, 1.23), (s * .40, -.41, 1.47),
                (s * .37, -.10, 1.61), (s * .28, -.25, 1.40)],
                .035, 'steel', .007, (s, 0, 0))
            b.tube('Concept neck copper pressure line', (s * .36, -.67, 1.23),
                   (s * .36, -.25, 1.49), .018, 'copper', vertices=12, bevel=.002)
            hatch(b, 'Concept engineering nose access', [
                (s * .11, -2.61, .29), (s * .27, -2.56, .31),
                (s * .32, -2.18, .46), (s * .13, -2.21, .46)], 'graphite')
        b.ring('Concept emitter copper retaining collar', (0, .86, 2.325),
               .335, .012, 'copper')
    elif name == 'Bigboy':
        for s in [-1, 1]:
            hatch(b, 'Concept transport dorsal service door', [
                (s * .50, -.89, .706), (s * .76, -.86, .636),
                (s * .72, -.43, .675), (s * .48, -.46, .751)], 'bluegrey')
            b.panel('Concept reinforced outrigger joint', [
                (s * 1.03, .61, .02), (s * 1.24, .69, .01),
                (s * 1.40, .96, -.03), (s * 1.17, .89, -.01)],
                .07, 'gunmetal', .009)
            b.ring('Concept outrigger copper bearing', (s * 1.96, 1.05, .064),
                   .13, .010, 'copper')
    elif name == 'Defcom':
        for s in [-1, 1]:
            b.panel('Concept scythe root metal socket', [
                (s * .72, .57, .277), (s * .90, .51, .257),
                (s * 1.01, .35, .228), (s * .79, .39, .259)],
                .021, 'steel', .004)
            b.pipe('Concept scythe fine amber inlay', [
                (s * .89, .37, .259), (s * 1.19, .08, .150),
                (s * 1.46, -.39, .016)], .005, 'copper')
            hatch(b, 'Concept green shoulder hatch', [
                (s * .41, .65, .428), (s * .56, .65, .459),
                (s * .57, .86, .385), (s * .40, .86, .373)], 'forest')
    elif name == 'Leonov':
        for s in [-1, 1]:
            b.panel('Concept fork floating silver cheek', [
                (s * .63, -.74, .135), (s * .79, -.71, .118),
                (s * .81, -.25, .179), (s * .64, -.26, .198)],
                .019, 'silver', .004)
            hatch(b, 'Concept split arrow rear access', [
                (s * .68, .54, .20), (s * .79, .54, .22),
                (s * .87, .90, .25), (s * .76, .90, .25)], 'silver')
            b.tube('Concept fork recessed coolant coupling',
                   (s * .49, -.25, .09), (s * .49, .05, .10),
                   .025, 'copper', vertices=12, bevel=.003)
    elif name == 'Nostromo':
        for s in [-1, 1]:
            hatch(b, 'Concept graphite nose service armor', [
                (s * .33, -1.29, .258), (s * .54, -1.23, .267),
                (s * .60, -.81, .333), (s * .33, -.85, .382)], 'graphite')
            b.panel('Concept low turbine mounting saddle', [
                (s * .53, .23, .44), (s * 1.02, .25, .44),
                (s * 1.05, .80, .39), (s * .51, .84, .43)],
                .065, 'gunmetal', .014)
            b.ring('Concept turbine copper service band', (s * .77, .91, .67),
                   .38, .013, 'copper', (0, 1, 0))
        # Transform the fitted plating, glazing and cheek machinery together;
        # the rear turbines keep their round cross-sections and mounting points.
        b.remove_parts(('Nose sensor',))
        b.reshape(None, nostromo_profile)
    elif name == 'Phoenix':
        for s in [-1, 1]:
            b.panel('Concept capsule lower red cheek', [
                (s * .35, -.70, -.26), (s * .50, -.34, -.19),
                (s * .53, .02, -.17), (s * .42, -.12, -.27)],
                .023, 'red', .007, (s, 0, -.2))
            b.pipe('Concept capsule copper belt inset', [
                (s * .33, -.72, -.225), (s * .50, -.28, -.13),
                (s * .51, .22, -.084)], .006, 'copper')
            b.box('Concept capsule tail latch', (s * .35, .66, -.12),
                  (.068, .105, .021), 'gunmetal', .004)
    elif name == 'Piranha':
        for s in [-1, 1]:
            b.panel('Concept spear shoulder blue armor', [
                (s * .28, -.86, .214), (s * .36, -.74, .244),
                (s * .40, -.14, .306), (s * .29, -.24, .320)],
                .018, 'bluegrey', .004)
            hatch(b, 'Concept swept wing silver access', [
                (s * .68, .27, -.003), (s * .89, .39, -.013),
                (s * 1.04, .65, -.035), (s * .81, .57, -.013)], 'silver')
            b.pipe('Concept needle fine copper inlay', [
                (s * .052, -2.73, .023), (s * .128, -2.14, .100),
                (s * .19, -1.28, .190)], .005, 'copper')
    elif name == 'Spearhead':
        for s in [-1, 1]:
            b.panel('Concept recon upper cobalt cheek', [
                (s * .21, .45, 1.907), (s * .31, .48, 1.881),
                (s * .30, 1.16, 1.896), (s * .20, 1.12, 1.956)],
                .021, 'cobalt', .005)
            b.tube('Concept recon hydraulic bright shaft',
                   (s * .31, .39, .61), (s * .31, .72, 1.32),
                   .023, 'silver', vertices=16, bevel=.002)
            b.tube('Concept recon hydraulic dark sleeve',
                   (s * .31, .39, .61), (s * .31, .56, .98),
                   .041, 'gunmetal', vertices=16, bevel=.004)
            hatch(b, 'Concept recon shoulder access', [
                (s * .31, -.66, .236), (s * .43, -.56, .275),
                (s * .38, -.27, .365), (s * .27, -.33, .349)], 'graphite')
    elif name == 'Vengeance':
        for s in [-1, 1]:
            hatch(b, 'Concept interceptor raised cheek armor', [
                (s * .35, -.98, .18), (s * .53, -.86, .20),
                (s * .67, -.40, .35), (s * .49, -.42, .36)], 'sage')
            b.ring('Concept high drive amber collar', (s * 1.00, .54, .77),
                   .239, .011, 'copper', (0, 1, 0))
            b.ring('Concept low drive amber collar', (s * 1.05, .65, -.13),
                   .206, .010, 'copper', (0, 1, 0))
    elif name == 'Yamato':
        for s in [-1, 1]:
            hatch(b, 'Concept stepped transport cheek door', [
                (s * .33, -.91, .19), (s * .38, -.59, .35),
                (s * .38, -.44, .31), (s * .33, -.73, .16)],
                'sage', (s, 0, 0))
            b.tube('Concept transport exposed bright yoke piston',
                   (s * .36, .28, .49), (s * .69, .50, .51),
                   .036, 'silver', vertices=16, bevel=.003)
            b.tube('Concept transport yoke sleeve',
                   (s * .54, .40, .50), (s * .72, .52, .52),
                   .055, 'gunmetal', vertices=16, bevel=.004)


def apply(b: ModuleType, name: str) -> None:
    finish_palette(b, name)
    b.group(name + ' | Dorbit concept construction')
    ship_fittings(b, name)
    # Silver trim frames the fitted armor without competing with its broad
    # panels. Mechanical pipes and structural rails retain their materials.
    for obj in b.PARTS:
        if any(word in obj.name.lower() for word in ['seam', 'edging', 'engraved', 'trim']):
            obj.data.materials[0] = b.M['steel'] if obj.data.materials[0] == b.M['pale'] else obj.data.materials[0]
        for modifier in obj.modifiers:
            if modifier.type == 'BEVEL':
                modifier.segments = 2
                modifier.use_clamp_overlap = True
    # Undersides become inspectable engineering surfaces, using the real hull
    # bounds rather than invented ship dimensions or independent artwork.
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(p) for obj in b.PARTS for p in obj.bound_box]
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    width = min((hi.x - lo.x) * .13, .24)
    center_y = (lo.y + hi.y) / 2
    # This small access assembly is mounted below the narrow central body.
    origin = Vector((0, center_y, lo.z - 1))
    hits = []
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in b.PARTS:
        inverse = obj.matrix_world.inverted()
        hit, location, _, _ = obj.ray_cast(inverse @ origin,
            inverse.to_3x3() @ Vector((0, 0, 1)), depsgraph=graph)
        if hit:
            hits.append((obj.matrix_world @ location).z)
    if not hits:
        return
    bottom = min(hits)
    hatch(b, 'Concept ventral removable service cover', [
        (-width, center_y - .22, bottom - .012),
        (width, center_y - .22, bottom - .012),
        (width, center_y + .22, bottom - .012),
        (-width, center_y + .22, bottom - .012)], 'gunmetal', (0, 0, -1))
