"""Build the concept-guided Outpost 01 study and its portable Godot export.

Blender --background --python tools/build_station.py
Author in Godot metres (Y up, docking approach from +Z). The origin is the
lowest hangar's service point, not the visual bounding-box centre.
"""
import json
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/sector'
REVIEW = ROOT / 'art/station-review'
COLLISIONS = []
MATERIALS = {}
PARTS = []


def point(p):
    return Vector((p[0], -p[2], p[1]))


def image(name, pixels, color=True):
    height, width, _ = pixels.shape
    result = bpy.data.images.new(name, width=width, height=height, alpha=True)
    result.colorspace_settings.name = 'sRGB' if color else 'Non-Color'
    result.pixels.foreach_set(pixels.astype(np.float32).ravel())
    result.filepath_raw = str(REVIEW / 'textures' / (name + '.png'))
    result.file_format = 'PNG'
    result.save()
    return result


def surfaces():
    rng = np.random.default_rng(831)
    size = 512
    y, x = np.indices((size, size))
    grain = rng.normal(0, .008, (size, size))
    seams = (x % 256 < 2) | (y % 256 < 2)
    height = np.ones((size, size)) * .5 + grain
    height[seams] = .25
    variation = .94 + grain + ((x // 256 + y // 256) % 3) * .025
    variation[seams] = .44
    for px in (12, 244, 268, 500):
        for py in (12, 244, 268, 500):
            screw = (x - px) ** 2 + (y - py) ** 2 < 5
            variation[screw] = .4
            height[screw] = .33
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * .65
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * .65
    normals = np.stack((-dx, -dy, np.ones_like(dx)), axis=-1)
    normals /= np.linalg.norm(normals, axis=-1)[:, :, None]
    pixels = np.ones((size, size, 4))
    pixels[:, :, :3] = normals * .5 + .5
    normal = image('normal', pixels, False)
    palette = {
        'Cobalt armor': ((.095, .19, .38), .7, .2, 0),
        'Blue secondary': ((.17, .28, .43), .65, .24, 0),
        'Titanium trim': ((.52, .58, .65), .85, .2, 0),
        'Graphite machinery': ((.055, .07, .085), .55, .59, 0),
        'Copper markings': ((.53, .24, .08), .5, .5, 0),
        'Cyan guidance': ((.06, .8, 1), .15, .35, 3),
        'Hangar lamps': ((.88, .93, 1), 0, .5, 1.4),
        'Amber beacons': ((1, .35, .04), 0, .4, 2),
    }
    for name, (color, metallic, roughness, glow) in palette.items():
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        mat.diffuse_color = (*color, 1)
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (*color, 1)
        shader.inputs['Metallic'].default_value = metallic
        shader.inputs['Roughness'].default_value = roughness
        if name in ('Cobalt armor', 'Blue secondary'):
            shader.inputs['Coat Weight'].default_value = .8
            shader.inputs['Coat Roughness'].default_value = .12
        if glow:
            shader.inputs['Emission Color'].default_value = (*color, 1)
            shader.inputs['Emission Strength'].default_value = glow
        elif name not in ('Copper markings',):
            pixels[:, :, :3] = np.clip(variation[:, :, None] * color, 0, 1)
            tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
            tex.image = image(name.split()[0].lower(), pixels)
            mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
            tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
            tex.image = normal
            mapping = mat.node_tree.nodes.new('ShaderNodeNormalMap')
            mapping.inputs['Strength'].default_value = .32
            mat.node_tree.links.new(tex.outputs['Color'], mapping.inputs['Color'])
            mat.node_tree.links.new(mapping.outputs['Normal'], shader.inputs['Normal'])
        MATERIALS[name] = mat


def mesh(name, vertices, faces, material):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(v) for v in vertices], [], faces)
    data.update()
    data.materials.append(MATERIALS[material])
    # Per-face metric mapping keeps panel grain the same scale on large/small parts.
    uv = data.uv_layers.new(name='Metric panel mapping')
    for poly in data.polygons:
        axis = max(range(3), key=lambda a: abs(poly.normal[a]))
        axes = [a for a in range(3) if a != axis]
        for loop_index in poly.loop_indices:
            co = data.vertices[data.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (co[axes[0]] / 8, co[axes[1]] / 8)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    PARTS.append(obj)
    return obj


def box(name, center, size, material='Graphite machinery', bevel=0):
    x, y, z = center
    sx, sy, sz = (d / 2 for d in size)
    b = min(bevel, sx * .35, sy * .35, sz * .35)
    if b:
        outline = [(-sx+b, -sy), (sx-b, -sy), (sx, -sy+b), (sx, sy-b),
                   (sx-b, sy), (-sx+b, sy), (-sx, sy-b), (-sx, -sy+b)]
        vertices = []
        for depth, inset in [(-sz, b), (-sz+b, 0), (sz-b, 0), (sz, b)]:
            vertices.extend((x + px * (1-inset/sx), y + py * (1-inset/sy), z + depth)
                            for px, py in outline)
        faces = [tuple(reversed(range(8))), tuple(range(24, 32))]
        for ring in range(3):
            for i in range(8):
                j = (i + 1) % 8
                faces.append((ring*8+i, ring*8+j, (ring+1)*8+j, (ring+1)*8+i))
    else:
        vertices = [(x+px*sx, y+py*sy, z+pz*sz)
                    for pz in (-1, 1) for py in (-1, 1) for px in (-1, 1)]
        faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4),
                 (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return mesh(name, vertices, faces, material)


def beam(name, start, finish, width=.35, material='Titanium trim'):
    a, b = Vector(start), Vector(finish)
    direction = (b-a).normalized()
    side = direction.cross(Vector((0, 0, 1)))
    if side.length < .1:
        side = direction.cross(Vector((0, 1, 0)))
    side.normalize()
    up = direction.cross(side).normalized()
    vertices = [tuple(p + (side*math.cos(i*math.tau/6) + up*math.sin(i*math.tau/6))*width/2)
                for p in (a, b) for i in range(6)]
    faces = [tuple(reversed(range(6))), tuple(range(6, 12))]
    faces.extend((i, (i+1)%6, (i+1)%6+6, i+6) for i in range(6))
    return mesh(name, vertices, faces, material)


def cylinder(name, center, radius, height, material, segments=12, top=None):
    top = radius if top is None else top
    x, y, z = center
    vertices = [(x+r*math.sin(i*math.tau/segments), y+dy, z+r*math.cos(i*math.tau/segments))
                for r, dy in [(radius, -height/2), (top, height/2)] for i in range(segments)]
    # Angles advance clockwise viewed from above.
    faces = [tuple(range(segments)), tuple(reversed(range(segments, 2*segments)))]
    faces.extend((i, i+segments, (i+1)%segments+segments, (i+1)%segments) for i in range(segments))
    return mesh(name, vertices, faces, material)


def collider(center, size):
    COLLISIONS.append({'position': list(center), 'size': list(size)})


def hangar(y, index):
    width = 26 if index < 3 else 24
    h = 18 if index == 0 else 16
    # Real recessed spaces, not luminous rectangles painted on the tower.
    box('Hangar %d floor' % index, (0, y-h/2-1, 0), (width+5, 2, 29), 'Titanium trim', .25)
    collider((0, y-h/2-1, 0), (width+5, 2, 29))
    box('Hangar %d ceiling' % index, (0, y+h/2+1, 0), (width+5, 2, 29), 'Blue secondary', .25)
    collider((0, y+h/2+1, 0), (width+5, 2, 29))
    box('Hangar %d rear bulkhead' % index, (0, y, -12.5), (width, h, 3), 'Graphite machinery')
    collider((0, y, -12.5), (width, h, 3))
    for side in (-1, 1):
        x = side * (width/2+1)
        box('Hangar %d jamb' % index, (x, y, 0), (2, h+4, 29), 'Blue secondary', .3)
        collider((x, y, 0), (2, h+4, 29))
        box('Hangar armored entrance', (x, y, 14.5), (2.5, h+2, 1.6), 'Titanium trim', .45)
        box('Recessed vertical light', (x-side*.5, y, 15.35), (.15, h-2, .08), 'Hangar lamps')
        for depth in (-8, -2, 5, 11):
            box('Interior pilaster', (side*(width/2-.3), y, depth), (.4, h-1, .5), 'Titanium trim')
            box('Overhead strip', (side*7.7, y+h/2-.15, depth), (2.8, .12, .5), 'Hangar lamps')
            box('Dock floor guidance', (side*6.7, y-h/2+.05, depth), (.15, .12, 3), 'Cyan guidance')
        # Faceted blue strips beside each aperture.
        for offset in (-h/2-2.6, h/2+2.6):
            box('Fitted bay eyebrow', (side*7, y+offset, 15), (13.8, 2.8, 2), 'Cobalt armor', .6)
            box('Machined brow seam', (side*7, y+offset+.85, 16.05), (11.8, .18, .13), 'Titanium trim')
        for k in range(4):
            box('Dock warning dash', (side*(width/2-2), y-h/2+.1, 8+k*1.2), (.6, .1, .55), 'Copper markings')
    # Equipment lockers, gantries and exposed piping remain behind the entry throat.
    for x in (-9, -5, 5, 9):
        box('Rear equipment cabinet', (x, y-h/2+2, -9), (2, 4, 2), 'Blue secondary', .2)
        box('Rear cabinet grille', (x, y-h/2+2, -7.9), (1.5, 2, .1), 'Titanium trim')
    for x in (-9, -3, 3, 9):
        box('Bulkhead lamp', (x, y+4, -10.9), (1.1, .25, .08), 'Hangar lamps')
    beam('Hangar overhead conduit', (-10, y+h/2-1, -8), (10, y+h/2-1, -8), .5)
    for depth in (-7, 0, 7):
        box('Ceiling light diffuser', (0, y+h/2-.3, depth), (18, .15, .28), 'Hangar lamps')
    for side in (-1, 1):
        for height in (y-h/2-1, y+h/2+1):
            box('Heavy aperture border', (side*6, height, 15.4), (11.8, .65, .55), 'Titanium trim', .15)
            for k in range(7):
                x = side*(1.7+k*1.5)
                box('Recessed aperture lamp', (x, height+.3, 15.75), (.55, .14, .08), 'Hangar lamps')
                box('Aperture latch', (x, height-.5, 16), (.8, .6, .4), 'Graphite machinery', .1)
        for depth in (-6, -1, 4, 9):
            box('Interior upper gantry', (side*10.7, y+4, depth), (2, .8, 4.8), 'Graphite machinery')
            box('Gantry deck trim', (side*10.7, y+4.5, depth), (2, .2, 4.8), 'Titanium trim')
            beam('Gantry support', (side*12, y+1, depth), (side*9.7, y+4, depth), .25)
        for k in range(5):
            box('Service console', (side*(1.8+k*1.4), y-h/2+1, -7), (1, 2, 1.6), 'Titanium trim', .18)
        # A parked maintenance cradle adds meter-scale cues without fake pilots.
        box('Parked service pallet', (side*4.6, y-h/2+.6, -2), (3.4, .8, 5), 'Graphite machinery', .3)
        box('Service pallet hull', (side*4.6, y-h/2+1.3, -2), (2, .8, 3.6), 'Blue secondary', .4)
        for offset in (-1.2, 1.2):
            box('Pallet side pod', (side*4.6+offset, y-h/2+1, -1), (.6, .9, 2.7), 'Titanium trim', .2)


def tower():
    for index, y in enumerate((0, 28, 54, 80, 106, 132)):
        hangar(y, index)
        # Layered flanks and rear panels, with open truss strips between armor.
        for side in (-1, 1):
            box('Tower rear fitted panel', (side*7, y, -14.4), (13, 21, 1.5), 'Cobalt armor', .6)
            for depth in (-7, 4):
                box('Tower flank plating', (side*16.1, y+1, depth), (1.8, 17, 9), 'Cobalt armor', .5)
                box('Flank silver inset', (side*17.05, y-4, depth), (.16, 4, 7), 'Titanium trim')
            for height in (y-8, y+8):
                beam('Exposed structural tie', (side*16, height, 10), (side*23, height, 10), .5)
            for z in (-8, 10):
                beam('Diagonal lattice', (side*17, y-8, z), (side*23, y+9, z), .65, 'Graphite machinery')
                beam('Diagonal lattice trim', (side*17, y+9, z), (side*23, y-8, z), .28)
            for row in range(3):
                for col in range(5):
                    box('Window row', (side*17.12, y+row*.7, -5+col*.7), (.12, .28, .43), 'Hangar lamps')
            # Tiny greebles read as maintenance decks at this scale.
            for k in range(5):
                box('Utility block', (side*18, y-6+k*2.4, -11), (2.4, 1.5, 2.1), 'Titanium trim', .15)
            for k in range(8):
                height = y-9+k*2.5
                # Layered flank frames break up the large blue surfaces.
                beam('Exposed flank rib', (side*18, height, -12), (side*18, height, 11), .3)
                box('Rear machinery housing', (side*17.8, height, -14), (2.5, 1.6, 3), 'Graphite machinery', .18)
                for depth in (-7, 0, 7):
                    box('Flank access latch', (side*17.2, height, depth), (.5, .7, 1), 'Titanium trim', .1)
            for x in (side*4, side*10):
                box('Rear panel lower relief', (x, y-6, -15.3), (4.5, 6, .7), 'Blue secondary', .3)
                for row in range(4):
                    box('Rear cooling louver', (x, y-7+row*1.3, -15.8), (4, .4, .35), 'Graphite machinery')
    # Two long armored buttresses are a defining feature of the reference.
    for side in (-1, 1):
        for y in (-10, 17, 44, 71, 98):
            box('Buttress core', (side*23.5, y, 1), (5, 26, 17), 'Graphite machinery', .5)
            box('Buttress cobalt shield', (side*24, y+1, 9.8), (5.8, 24, 1.6), 'Cobalt armor', .7)
            box('Buttress alloy spine', (side*26.7, y, 10.2), (.9, 24.5, .8), 'Titanium trim', .2)
            box('Buttress pale inlay', (side*23.1, y+1, 10.7), (2.2, 18, .18), 'Blue secondary', .2)
            for k in range(3):
                box('Buttress access hatch', (side*23.3, y-7+k*6, 10.86), (1.4, 2, .1), 'Titanium trim', .1)
            for height in (y-9, y+9):
                box('Buttress silver coupling', (side*24, height, 10.8), (5.3, .8, .6), 'Titanium trim', .15)
            box('Buttress bevel accent', (side*21.5, y, 10.65), (.5, 22, .6), 'Titanium trim', .15)
            for k in range(5):
                box('Buttress recessed radiator', (side*27, y-8+k*3.6, 1), (.3, 2.2, 10), 'Graphite machinery')
                for depth in (-2, 2, 6):
                    box('Radiator machined rung', (side*27.2, y-8+k*3.6, depth), (.25, .3, 2.3), 'Titanium trim')
        collider((side*23.5, 43, 1), (6.5, 133, 18))
        for z in (-9, 7):
            beam('Longitudinal pipe', (side*19, -23, z), (side*19, 142, z), .65)
        # Small projecting service piers, above the main cross-shaped base.
        for y, length in ((44, 20), (96, 12)):
            box('Side maintenance pier', (side*(24+length/2), y, -2), (length, 2.2, 7), 'Graphite machinery', .25)
            collider((side*(24+length/2), y, -2), (length, 2.2, 7))
            box('Pier deck panel', (side*(24+length/2), y+1.2, -2), (length-2, .25, 5), 'Titanium trim', .2)
            for depth in (-5, 1):
                beam('Pier handrail', (side*25, y+2, depth), (side*(24+length), y+2, depth), .15)
            box('Pier tip lamp', (side*(24+length), y, 1.5), (.6, .3, .1), 'Cyan guidance')
    # Sloping armored command crown, taller and wider than the bay modules.
    vertices = [(-16, 145, -14), (16, 145, -14), (16, 145, 14), (-16, 145, 14),
                (-13, 183, -10), (13, 183, -10), (13, 170, 10), (-13, 170, 10)]
    mesh('Sloped command crown', vertices,
         [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (0, 4, 7, 3), (1, 2, 6, 5)], 'Cobalt armor')
    collider((0, 162, 0), (32, 36, 28))
    # Individual sloped roof panels sit above a dark channelled command hull.
    PARTS[-1].data.materials[0] = MATERIALS['Graphite machinery']
    for side in (-1, 1):
        # The front crown slopes inward, so these fitted plates follow its skin.
        for row in range(2):
            y1, y2 = 160+row*5, 164.6+row*5
            z1, z2 = 14-(y1-145)*4/25, 14-(y2-145)*4/25
            mesh('Crown forward shield', [(side*.4, y1, z1+.25), (side*14, y1, z1+.25),
                 (side*13.2, y2, z2+.25), (side*.4, y2, z2+.25)],
                 [(0, 1, 2, 3)] if side == 1 else [(3, 2, 1, 0)], 'Cobalt armor')
        box('Command cheek armor', (side*13.8, 151, 14.3), (3.3, 10, 1.7), 'Blue secondary', .6)
        for lane in range(3):
            x1 = side*(.45+lane*4.1)
            x2 = side*(4.1+lane*4.1)
            for row in range(3):
                z1 = -10+row*6.6
                z2 = z1+6.2
                def roof_y(z):
                    return 176.5-z*.65
                # Independent overlapping plates with clearly machined leading lips.
                mesh('Command roof fitted plate', [(x1, roof_y(z1)+.4, z1), (x2, roof_y(z1)+.4, z1),
                     (x2, roof_y(z2)+.4, z2), (x1, roof_y(z2)+.4, z2)],
                     [(3, 2, 1, 0)] if side == 1 else [(0, 1, 2, 3)], 'Cobalt armor')
                beam('Command roof edge trim', (x1, roof_y(z2)+.6, z2), (x2, roof_y(z2)+.6, z2), .2)
        box('Bridge framed alloy lip', (side*7, 149.7, 14.5), (12.6, .65, .7), 'Titanium trim', .2)
        box('Bridge blue canopy', (side*7, 158.5, 14.9), (13.5, 3.2, 2.2), 'Cobalt armor', .6)
        for row in range(4):
            box('Command flank armor', (side*16.1, 149+row*4.8, -2), (1.7, 4.4, 19), 'Cobalt armor', .4)
            box('Command cooling slot', (side*17, 150+row*4.8, -2), (.15, .5, 11), 'Graphite machinery')
    for side in (-1, 1):
        beam('Crown fitted armor seam', (side*5, 169, 10.2), (side*5, 182.8, -9.8), .4)
        box('Bridge observation glazing', (side*7, 153, 14.12), (12, 5, .2), 'Graphite machinery', .3)
        box('Bridge window inset', (side*7, 153, 14.25), (11.3, 4.3, .12), 'Hangar lamps', .25)
        for x in (side*2, side*5, side*9, side*12):
            box('Bridge glazing mullion', (x, 153, 14.4), (.26, 4.8, .22), 'Titanium trim')
        box('Command side fin', (side*20, 161, -2), (11, 6, 23), 'Blue secondary', 1)
        box('Crown cyan inset', (side*20, 160, 9.6), (9, .65, .15), 'Cyan guidance')
        for row in range(3):
            box('Crown fin luminous rib', (side*20, 159+row*.8, 9.7), (8-row*.8, .3, .25), 'Cyan guidance')
        for k in range(6):
            box('Crown fin dark machinery', (side*20, 164.1, -10+k*3), (7, .3, 1.7), 'Graphite machinery')
        beam('Crown antenna', (side*9, 177, -10), (side*9, 195, -10), .3)
        box('Antenna beacon', (side*9, 195, -10), (.25, .5, .25), 'Amber beacons')
    cylinder('Crown sensor turret', (0, 184, -7), 5, 2.2, 'Titanium trim')
    for y, size in ((189, (4, 2, 4)), (199, (1, 16, 1))):
        box('Communications mast', (4, y, -10), size, 'Graphite machinery', .15)
    box('Highest navigation lamp', (4, 208, -10), (.35, .65, .35), 'Amber beacons')
    collider((4, 195, -10), (2, 26, 2))


def base():
    cylinder('Lower hub', (0, -27, 0), 19, 28, 'Graphite machinery', top=16)
    collider((0, -27, 0), (34, 28, 34))
    for y in (-40, -32, -23, -15):
        cylinder('Hub alloy collar', (0, y, 0), 18.8, 1.4, 'Titanium trim')
    for side in (-1, 1):
        box('Lower hub forward armor', (side*7.5, -27, 16.1), (13.7, 21, 2), 'Cobalt armor', 1.2)
        box('Hub silver relief', (side*6, -26, 17.15), (2.1, 14, .25), 'Titanium trim', .5)
        for z in (-11, 11):
            box('Hub side shield', (side*17, -28, z), (2.8, 18, 7), 'Blue secondary', .7)
    # Four broad tapering blades; cardinal orientation lets navigation use simple boxes.
    for arm in range(4):
        angle = arm*math.pi/2
        def arm_point(p):
            x, y, z = p
            return (x*math.cos(angle)-z*math.sin(angle), y,
                    x*math.sin(angle)+z*math.cos(angle))
        start = len(PARTS)
        vertices = [(14, -36, -8), (14, -36, 8), (85, -30, 3.2), (85, -30, -3.2),
                    (14, -24, -8), (14, -24, 8), (85, -24.5, 3.2), (85, -24.5, -3.2)]
        mesh('Docking blade %d' % arm, vertices,
             [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], 'Blue secondary')
        for i in range(8):
            x = 20+i*8
            width = 14-(x-14)*.125
            box('Blade fitted deck', (x, -23.9, 0), (7.3, .65, width-1), 'Cobalt armor', .35)
            for side in (-1, 1):
                box('Blade alloy edge', (x, -24, side*width/2), (7.5, .7, .35), 'Titanium trim', .1)
                box('Blade machinery slot', (x, -23.45, side*2), (5.8, .3, .65), 'Graphite machinery')
                box('Blade ventilator', (x, -23.2, side*2), (3.7, .25, .42), 'Titanium trim')
                beam('Blade underside rib', (x-3, -34+(x-14)*.08, side*width/2), (x+3, -25, side*width/2), .55)
                for k in range(3):
                    box('Ventilation louver', (x-2+k*1.5, -23.15, side*2), (.25, .4, 1), 'Graphite machinery')
                # An exposed lower trench and alternating alloy plates give the
                # blade a layered hull rather than a single solid wedge.
                box('Blade side dark trench', (x, -28.1, side*(width/2+.08)), (6.8, 2.7, .22), 'Graphite machinery', .25)
                box('Blade side fitted plate', (x, -25.4, side*(width/2+.16)), (6.6, 1.2, .3), 'Titanium trim', .25)
                box('Blade side lower shield', (x, -31+(x-14)*.065, side*(width/2+.13)), (6.6, 1.2, .25), 'Cobalt armor', .25)
                for k in range(3):
                    box('Blade trench equipment', (x-2+k*2, -28.1, side*(width/2+.25)), (.8, 1.2, .35), 'Titanium trim', .1)
        box('Blade luminous tip', (85.05, -26.6, 0), (.22, .8, 6.2), 'Cyan guidance')
        for side in (-1, 1):
            beam('Tip cyan edge', (72, -24.7, side*4.2), (84.5, -24.7, side*3.1), .25, 'Cyan guidance')
            box('Blade root equipment', (22, -21.5, side*4.7), (9, 3.5, 1.4), 'Titanium trim', .3)
            for x in (24, 48, 67):
                beam('Blade antenna', (x, -24, side*4), (x, -21, side*4), .15)
                box('Blade amber beacon', (x, -20.8, side*4), (.22, .3, .22), 'Amber beacons')
        # Rotate geometry/UVs together; Blender authoring remains split by named part.
        for obj in PARTS[start:]:
            for vertex in obj.data.vertices:
                co = vertex.co
                vertex.co = point(arm_point((co.x, co.z, -co.y)))
            obj.data.update()
        for x, length, width, y, height in ((32, 36, 14, -29.5, 12), (61, 22, 10, -28, 9), (79, 14, 7, -27.2, 6.5)):
            size = (length, height, width) if arm%2 == 0 else (width, height, length)
            collider(arm_point((x, y, 0)), size)
    # Tapered underside reactor and instrumentation spire, visible in full 3D flight.
    cylinder('Lower reactor housing', (0, -47, 0), 10, 14, 'Blue secondary', top=15)
    collider((0, -48, 0), (20, 16, 20))
    for y in (-42, -48, -54):
        cylinder('Reactor service collar', (0, y, 0), 11, 1, 'Titanium trim')
    cylinder('Underside spire', (0, -63, 0), 3, 24, 'Titanium trim', top=7)
    collider((0, -65, 0), (9, 24, 9))
    for side in (-1, 1):
        beam('Lower conduit', (side*5, -53, 1), (side*5, -69, 1), .4)
        beam('Base sensor mast', (side*12, -40, 4), (side*12, -56, 4), .35)
        box('Base cyan lamp', (side*5, -54, 6), (.6, .3, .3), 'Cyan guidance')
    beam('Terminal antenna', (0, -74, 0), (0, -85, 0), .25)
    box('Underside beacon', (0, -85, 0), (.25, .6, .25), 'Amber beacons')


def export():
    # Save all editable named parts BEFORE merging into a single 8-surface runtime mesh.
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.scene.unit_settings.system = 'METRIC'
    bpy.context.scene.world.color = (.18, .18, .18)
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_distance = 350
            area.spaces.active.region_3d.view_location = point((0, 60, 0))
    for img in bpy.data.images:
        if img.source == 'FILE':
            img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(REVIEW / 'outpost-01.blend'))
    vertices, faces, indices, uvs = [], [], [], []
    materials = list(MATERIALS.values())
    for obj in PARTS:
        offset = len(vertices)
        data = obj.data
        vertices.extend(v.co[:] for v in data.vertices)
        uvs.extend(loop.uv[:] for loop in data.uv_layers.active.data)
        material_index = materials.index(data.materials[0])
        for poly in data.polygons:
            faces.append([offset+i for i in poly.vertices])
            indices.append(material_index)
    data = bpy.data.meshes.new('Outpost 01 export')
    data.from_pydata(vertices, [], faces)
    data.update()
    for mat in materials:
        data.materials.append(mat.copy())
    for poly, index in zip(data.polygons, indices):
        poly.material_index = index
    layer = data.uv_layers.new(name='Metric panel mapping')
    for loop, uv in zip(layer.data, uvs):
        loop.uv = uv
    obj = bpy.data.objects.new('Outpost01', data)
    bpy.context.scene.collection.objects.link(obj)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bake_occlusion(obj)
    bpy.ops.export_scene.gltf(filepath=str(OUT / 'outpost-01.glb'), export_format='GLB',
                             use_selection=True, export_yup=True,
                             export_cameras=False, export_lights=False, export_animations=False)
    (OUT / 'outpost-01-collision.json').write_text(json.dumps(COLLISIONS, indent=2)+'\n')
    data.calc_loop_triangles()
    low = [min(v[a] for v in vertices) for a in range(3)]
    high = [max(v[a] for v in vertices) for a in range(3)]
    report = {'triangles': len(data.loop_triangles), 'materials': len(materials),
              'editable_parts': len(PARTS), 'collision_boxes': len(COLLISIONS),
              'godot_dimensions_m': [high[0]-low[0], high[2]-low[2], high[1]-low[1]],
              'glb_bytes': (OUT / 'outpost-01.glb').stat().st_size,
              'service_origin': 'Lowest main hangar; approach from +Z',
              'source': 'art/station-review/concept.png'}
    (REVIEW / 'model-stats.json').write_text(json.dumps(report, indent=2)+'\n')
    print('STATION EXPORTED', report, flush=True)


def bake_occlusion(obj):
    """Portable geometry-derived recess shading, independent of runtime shadows.

    A separate UV set preserves metric surface mapping. Only ambient occlusion
    is baked: no sun direction, highlights, cyan glow or environment lighting.
    """
    print('Baking station recess occlusion', flush=True)
    obj.data.uv_layers.new(name='Occlusion')
    obj.data.uv_layers.active_index = 1
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.002)
    bpy.ops.object.mode_set(mode='OBJECT')
    ao = bpy.data.images.new('occlusion', width=2048, height=2048, alpha=False)
    ao.colorspace_settings.name = 'Non-Color'
    saved = []
    for mat in obj.data.materials:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        target = nodes.new('ShaderNodeTexImage')
        target.image = ao
        nodes.active = target
        ambient = nodes.new('ShaderNodeAmbientOcclusion')
        ambient.inputs['Distance'].default_value = 6
        ambient.samples = 16
        emit = nodes.new('ShaderNodeEmission')
        links.new(ambient.outputs['Color'], emit.inputs['Color'])
        output = nodes.get('Material Output')
        original = output.inputs['Surface'].links[0].from_socket
        links.new(emit.outputs[0], output.inputs['Surface'])
        saved.append((mat, original, ambient, emit, target))
    for part in PARTS:
        part.hide_render = True
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.render.bake.margin = 5
    bpy.ops.object.bake(type='EMIT')
    ao.filepath_raw = str(REVIEW / 'textures/occlusion.png')
    ao.file_format = 'PNG'
    ao.save()
    group = bpy.data.node_groups.new('glTF Material Output', 'ShaderNodeTree')
    group.interface.new_socket(name='Occlusion', in_out='INPUT', socket_type='NodeSocketFloat')
    for mat, original, ambient, emit, target in saved:
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        links.new(original, nodes.get('Material Output').inputs['Surface'])
        nodes.remove(ambient)
        nodes.remove(emit)
        uv = nodes.new('ShaderNodeUVMap')
        uv.uv_map = 'Occlusion'
        links.new(uv.outputs['UV'], target.inputs['Vector'])
        export_group = nodes.new('ShaderNodeGroup')
        export_group.node_tree = group
        links.new(target.outputs['Color'], export_group.inputs['Occlusion'])
    obj.data.uv_layers.active_index = 0
    for part in PARTS:
        part.hide_render = False


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)
    (REVIEW / 'textures').mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    surfaces()
    tower()
    base()
    export()


if __name__ == '__main__':
    build()
