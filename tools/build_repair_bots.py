"""Build editable, picture-guided REP-1/REP-2 models and portable flight GLBs.

Blender --background --python tools/build_repair_bots.py
Coordinates below use Godot metres, +Y up and the sensor facing -Z.
"""
import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/extras'
SOURCE = ROOT / 'art/repair-bots'
MATERIALS = {}


def point(p):
    return Vector((p[0], -p[2], p[1]))


def materials():
    rng = np.random.default_rng(165120)
    grain = rng.normal(0, .018, (256, 256))
    grain += rng.normal(0, .008, (256, 1))
    for name, color, metal, rough, emission in [
        ('Brushed silver', (.72, .75, .79), .58, .36, 0),
        ('Graphite mechanisms', (.035, .05, .065), .65, .38, 0),
        ('Copper fittings', (.48, .22, .065), .8, .27, 0),
        ('Cyan optics', (.005, .45, .65), .05, .18, .8),
        ('Amber power', (1, .25, .005), .1, .25, .8),
        ('Optical glass', (.012, .12, .17), .7, .12, 0),
    ]:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        mat.diffuse_color = (*color, 1)
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (*color, 1)
        shader.inputs['Metallic'].default_value = metal
        shader.inputs['Roughness'].default_value = rough
        if emission:
            shader.inputs['Emission Color'].default_value = (*color, 1)
            shader.inputs['Emission Strength'].default_value = emission
        elif name == 'Brushed silver':
            pixels = np.ones((256, 256, 4), dtype=np.float32)
            pixels[:, :, :3] = np.clip(np.array(color)[None, None, :] + grain[:, :, None], 0, 1)
            image = bpy.data.images.new('Brushed metal grain', width=256, height=256)
            image.pixels.foreach_set(pixels.ravel())
            image.pack()
            tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
            tex.image = image
            mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
        MATERIALS[name] = mat


def finish(obj, name, material, bevel=0):
    obj.name = name
    obj.data.materials.append(MATERIALS[material])
    if bevel:
        modifier = obj.modifiers.new('Machined edges', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj


def box(name, at, size, material='Brushed silver', bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(at))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material, bevel)


def sphere(name, at, size, material, segments=32, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=point(at))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material)


def cylinder(name, a, b, radius, material, end_radius=None, vertices=24):
    delta = point(b) - point(a)
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius,
                                    radius2=radius if end_radius is None else end_radius,
                                    depth=delta.length, location=(point(a) + point(b)) / 2)
    obj = bpy.context.object
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, material, min(.012, radius / 5))


def ring(name, at, major, minor, material, axis=(0, 0, -1)):
    bpy.ops.mesh.primitive_torus_add(major_segments=40, minor_segments=8,
                                   major_radius=major, minor_radius=minor, location=point(at))
    obj = bpy.context.object
    obj.rotation_euler = point(axis).to_track_quat('Z', 'Y').to_euler()
    return finish(obj, name, material)


def hose(name, points, radius=.025):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 8
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points) - 1)
    for node, at in zip(spline.bezier_points, points):
        node.co = point(at)
        node.handle_left_type = node.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target='MESH')
    obj.select_set(False)
    return finish(obj, name, 'Graphite mechanisms')


def shell_point(theta, phi, scale):
    return (scale[0] * math.sin(theta) * math.sin(phi),
            scale[1] * math.cos(theta) * math.sin(phi), -scale[2] * math.cos(phi))


def armor(scale):
    # Separate curved plates leave real recessed seams around the entire shell.
    # Radial petals around the front lens follow the illustrated armor layout.
    for row in range(4):
        low = .45 + row * .65 + .014
        high = low + .622
        for sector in range(8):
            left = sector * math.tau / 8 + .014
            right = left + math.tau / 8 - .028
            vertices = [point(shell_point(left + (right-left)*u/5, low+(high-low)*v/4, scale))
                        for v in range(5) for u in range(6)]
            faces = [(v*6+u, (v+1)*6+u, (v+1)*6+u+1, v*6+u+1)
                     for v in range(4) for u in range(5)]
            data = bpy.data.meshes.new('Curved fitted armor')
            data.from_pydata(vertices, [], faces)
            data.update()
            obj = bpy.data.objects.new('Armor panel %d-%d' % (row, sector), data)
            bpy.context.collection.objects.link(obj)
            finish(obj, obj.name, 'Brushed silver')
            modifier = obj.modifiers.new('Plate thickness', 'SOLIDIFY')
            modifier.thickness = .025
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            for face in obj.data.polygons:
                if face.index >= 40:
                    face.use_smooth = False
            # Small dark fasteners follow the actual curved surface.
            for theta in (left+.06, right-.06):
                at = shell_point(theta, low+.06, tuple(s+.012 for s in scale))
                sphere('Recessed fastener', at, (.013, .013, .013), 'Graphite mechanisms', 8, 4)


def limb(index, side, upper=False, advanced=False):
    y = .18 if upper else -.43
    shoulder = (side*.66, y, -.02)
    elbow = (side*(1.16 if upper else .93), y-.30, -.27)
    wrist = (side*(1.05 if upper else .76), y-.65, -.58)
    tip = (wrist[0], wrist[1]-.19, wrist[2]-.20)
    cylinder('Shoulder socket', (side*.58, y, -.02), (side*.79, y, -.02), .20, 'Graphite mechanisms')
    ring('Shoulder trim', (side*.80, y, -.02), .155, .026, 'Copper fittings', (side, 0, 0))
    for joint in (shoulder, elbow, wrist):
        cylinder('Rotary joint', (joint[0]-.09, joint[1], joint[2]),
                 (joint[0]+.09, joint[1], joint[2]), .115, 'Graphite mechanisms')
        ring('Joint bearing', (joint[0]+side*.095, joint[1], joint[2]), .078, .015,
             'Copper fittings' if not advanced else 'Brushed silver', (side, 0, 0))
    for a, b in ((shoulder, elbow), (elbow, wrist)):
        obj = box('Arm armor', tuple((a[i]+b[i])/2 for i in range(3)),
                  (.18, (point(b)-point(a)).length, .20))
        obj.rotation_euler = (point(b)-point(a)).to_track_quat('Z', 'Y').to_euler()
        cylinder('Exposed hydraulic piston', (a[0], a[1], a[2]+.10),
                 (b[0], b[1], b[2]+.10), .032, 'Copper fittings')
    hose('Flexible arm cable', [(shoulder[0], y+.08, .07),
                               (elbow[0]+side*.10, elbow[1], -.06),
                               (wrist[0]+side*.12, wrist[1], -.43)])
    cylinder('Repair tool housing', wrist, tip, .095, 'Graphite mechanisms', .07)
    for fraction in (.2, .5, .8):
        at = tuple(wrist[i]+(tip[i]-wrist[i])*fraction for i in range(3))
        ring('Tool collar', at, .075, .012, 'Brushed silver', tuple(tip[i]-wrist[i] for i in range(3)))
    end = (tip[0], tip[1]-.14, tip[2]-.12)
    cylinder('Copper precision nozzle', tip, end, .049, 'Copper fittings', .012)
    cylinder('Lit welding tip', end, (end[0], end[1]-.025, end[2]-.022), .014, 'Amber power', .005)
    if advanced:
        for offset in (-.11, .11):
            box('Tool gripper', (wrist[0]+offset, wrist[1]-.08, wrist[2]-.15), (.045, .18, .13), bevel=.01)
    marker = bpy.data.objects.new('ToolTip%d' % index, None)
    marker.location = point((end[0], end[1]-.025, end[2]-.022))
    bpy.context.collection.objects.link(marker)


def build(model, advanced):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    scale = (.66, .80, .53) if advanced else (.70, .70, .64)
    sphere('Recessed mechanical shell', (0, 0, 0), tuple(s-.026 for s in scale), 'Graphite mechanisms')
    armor(scale)
    front = -scale[2]
    cylinder('Recessed optical socket', (0, 0, front+.08), (0, 0, front-.07), .33, 'Graphite mechanisms')
    ring('Machined sensor rim', (0, 0, front-.08), .29, .043, 'Brushed silver')
    ring('Copper optical ring', (0, 0, front-.11), .235, .016, 'Copper fittings')
    sphere('Deep blue lens', (0, 0, front-.095), (.224, .224, .065), 'Optical glass')
    ring('Cyan sensor halo', (0, 0, front-.16), .191, .012, 'Cyan optics')
    sphere('Cyan sensor core', (0, 0, front-.16), (.065, .065, .025), 'Cyan optics')
    for side in (-1, 1):
        box('Sensor light recess', (side*.40, 0, front+.016), (.13, .12, .08), 'Graphite mechanisms')
        box('Status light', (side*.40, 0, front-.03), (.055 if advanced else .09, .075 if advanced else .028, .018),
            'Cyan optics' if advanced else 'Amber power', .006)
        cylinder('Side hub', (side*.60, .06, .08), (side*.77, .06, .08), .28, 'Graphite mechanisms')
        cylinder('Side silver cap', (side*.76, .06, .08), (side*.80, .06, .08), .23, 'Brushed silver')
        ring('Side hub power ring', (side*.82, .06, .08), .16, .015, 'Amber power', (side, 0, 0))
    box('Crown sensor housing', (0, scale[1]-.015, -.09), (.33, .11, .30), 'Graphite mechanisms')
    box('Crown amber slit', (0, scale[1], -.25), (.22, .027, .018), 'Amber power', .006)
    box('Dorsal vent inset', (0, scale[1]-.055, .11), (.29, .07, .33), 'Graphite mechanisms')
    for z in range(6):
        box('Dorsal radiator fin', (0, scale[1]-.01, z*.048-.01), (.23, .018, .016), 'Brushed silver', .004)
    ring('Ventral hover drive', (0, -scale[1]+.02, .03), .16, .034, 'Copper fittings', (0, -1, 0))
    cylinder('Ventral amber drive', (0, -scale[1]+.01, .03), (0, -scale[1]-.04, .03), .13, 'Amber power')
    if advanced:
        for side in (-1, 1):
            x = side*.45
            cylinder('Power canister core', (x, .43, .30), (x, 1.03, .52), .10, 'Graphite mechanisms')
            cylinder('Power canister base', (x, .43, .30), (x, .55, .344), .185, 'Graphite mechanisms')
            cylinder('Power canister cap', (x, .91, .475), (x, 1.03, .52), .185, 'Graphite mechanisms')
            cylinder('Amber power cell', (x, .55, .344), (x, .91, .475), .135, 'Amber power')
            for y, z in ((.49, .322), (.95, .49)):
                ring('Canister copper band', (x, y, z), .155, .023, 'Copper fittings', (0, .6, .22))
            cylinder('Canister silver crown', (x, .99, .506), (x, 1.07, .54), .175, 'Brushed silver', .13)
            for offset in (-.12, .12):
                cylinder('Canister protective rail', (x+offset, .53, .26), (x+offset, .95, .414), .025, 'Brushed silver')
    for side in (-1, 1):
        limb(0 if side == -1 else 1, side, advanced=advanced)
        if advanced:
            limb(2 if side == -1 else 3, side, upper=True, advanced=True)
    # Join to one mesh with six shared material surfaces, rather than hundreds of draw calls.
    bpy.ops.object.select_all(action='DESELECT')
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = model.upper() + ' picture-guided shell and tools'
    # A portable UV layer for the brushed grain on every machined component.
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=.01)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / (model+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (model+'.glb')), export_format='GLB',
                              export_yup=True, export_apply=True, export_cameras=False, export_lights=False)
    print(model, 'vertices=', len(obj.data.vertices), 'polygons=', len(obj.data.polygons))


OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
materials()
build('rep-1', False)
build('rep-2', True)
