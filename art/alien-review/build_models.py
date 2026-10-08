"""Build the approved Dorbit alien concepts as editable, textured Blender models.

Blender --background --factory-startup --python art/alien-review/build_models.py
Append -- Scout --draft for a quick two-view study. Forward is -Y, up is +Z.
Review GLBs keep those coordinates; runtime conversion/integration is separate.
"""
import json
import hashlib
import math
import struct
import sys
import zlib
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'art/ship-review'))
sys.path.insert(0, str(ROOT / 'tools'))
import build_models as geo
import ship_surface_atlas as surfaces

# These detailed review assets have a larger texture budget than runtime ships.
surfaces.SIZE = 4096

NAMES = ('Scout', 'Sentinel', 'Heavy')
VIEWS = ('perspective', 'top', 'side', 'front', 'rear', 'underside')
# Y, half width, half height, center Z. These are review units, not game stats.
SPECS = {
    'Scout': {
        'color': (.16, .075, .025), 'light': (1.0, .34, .025),
        'body': [(-3.0, .08, .07, 0), (-2.5, .30, .16, .04),
                 (-1.7, .49, .28, .12), (-.65, .64, .35, .19),
                 (.35, .58, .37, .22), (1.30, .44, .30, .20),
                 (2.20, .29, .22, .16)],
        # Y, inner X, outer X, top Z; the crescent tips point forwards.
        'wing': [(-2.80, 2.04, 2.09, -.34), (-2.15, 2.27, 2.58, -.12),
                 (-1.30, 2.14, 2.83, .18), (-.35, 1.76, 2.63, .44),
                 (.65, 1.65, 2.23, .49), (1.70, 1.98, 2.06, .28)],
        'wing_depth': .17, 'engine_x': .55, 'engine_y': 1.05,
        'engine_z': .25, 'engine_radius': .34, 'engine_length': 1.72,
        'barrel_radius': .065,
    },
    'Sentinel': {
        'color': (.12, .022, .019), 'light': (1.0, .018, .008),
        'body': [(-3.12, .13, .09, 0), (-2.45, .43, .24, .06),
                 (-1.55, .73, .43, .16), (-.40, 1.05, .51, .23),
                 (.68, .93, .47, .24), (1.60, .69, .36, .20),
                 (2.36, .38, .29, .15)],
        'wing': [(-2.70, 2.73, 2.82, -.40), (-1.96, 2.63, 3.12, -.06),
                 (-1.02, 2.02, 3.02, .33), (.00, 1.70, 2.70, .59),
                 (.92, 1.67, 2.34, .57), (1.66, 1.93, 2.04, .33)],
        'wing_depth': .24, 'engine_x': .97, 'engine_y': 1.00,
        'engine_z': .33, 'engine_radius': .49, 'engine_length': 2.03,
        'barrel_radius': .095,
    },
    'Heavy': {
        'color': (.060, .035, .10), 'light': (.48, .075, 1.0),
        'body': [(-3.10, .22, .18, -.02), (-2.37, .64, .38, .05),
                 (-1.37, 1.11, .57, .14), (-.23, 1.43, .69, .25),
                 (.82, 1.18, .65, .29), (1.83, .89, .52, .26),
                 (2.52, .54, .36, .18)],
        'wing': [(-1.94, 3.04, 3.15, -.35), (-1.28, 2.94, 3.54, -.05),
                 (-.48, 2.30, 3.57, .48), (.32, 1.94, 3.18, .74),
                 (1.22, 1.88, 2.85, .67), (1.93, 2.34, 2.43, .42)],
        'wing_depth': .35, 'engine_x': 1.40, 'engine_y': 1.04,
        'engine_z': .46, 'engine_radius': .64, 'engine_length': 2.23,
        'barrel_radius': .125,
    },
}


# Shared helper module is loaded first; the alien module uses the same geo state.
sys.path.insert(0, str(HERE))
from alien_geometry import body, wings, engines, weapons_and_sensors


def write_review_png(path, pixels):
    """Exact RGB data channels with faster lossless compression for 4K builds."""
    data=np.round(np.clip(pixels[:,:,:3],0,1)*255).astype(np.uint8)
    def chunk(kind,content):
        return (struct.pack('>I',len(content))+kind+content
                +struct.pack('>I',zlib.crc32(kind+content)))
    rows=b''.join(b'\0'+row.tobytes() for row in data[::-1])
    path.write_bytes(b'\x89PNG\r\n\x1a\n'
                     +chunk(b'IHDR',struct.pack('>IIBBBBB',surfaces.SIZE,surfaces.SIZE,8,2,0,0,0))
                     +chunk(b'IDAT',zlib.compress(rows,4))+chunk(b'IEND',b''))


# The shared atlas calls its module-level writer; this override is local to the
# alien build process and leaves the ship generators and their files unchanged.
surfaces.write_png=write_review_png


def surface_wear(atlas: surfaces.SurfaceAtlas) -> None:
    """Author restrained coating wear and brushed grain into portable maps.

    The shared atlas writer emits filter-zero PNGs. Read those exact channel
    values instead of passing data maps through Blender color management.
    Armor retains unique padded tiles; hardware shares finish tiles. No lighting is baked.
    """
    def read_map(name):
        raw = (atlas.directory/(name+'.png')).read_bytes()
        offset, compressed = 8, bytearray()
        while offset < len(raw):
            length = struct.unpack_from('>I',raw,offset)[0]
            kind = raw[offset+4:offset+8]
            if kind == b'IDAT':
                compressed.extend(raw[offset+8:offset+8+length])
            offset += length+12
        rows = np.frombuffer(zlib.decompress(compressed),dtype=np.uint8).reshape(surfaces.SIZE,-1)
        assert np.all(rows[:,0]==0), 'Expected filter-zero atlas PNG'
        return rows[:,1:].reshape(surfaces.SIZE,surfaces.SIZE,3)[::-1].astype(np.float32)/255
    maps = {key:read_map(key) for key in ('albedo','orm','normal')}
    manifest_path = atlas.directory/'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    objects = {obj.name:obj for obj in geo.PARTS}
    for record in manifest['parts']:
        if record['role']=='emissive':
            continue
        seed = int.from_bytes(hashlib.sha256((record['part']+' alien finish').encode()).digest()[:8],'little')
        rng = np.random.default_rng(seed)
        row,col = divmod(record['tile'],atlas.grid)
        region = np.s_[row*atlas.cell:(row+1)*atlas.cell,col*atlas.cell:(col+1)*atlas.cell]
        color,orm,normal = (maps[key][region] for key in ('albedo','orm','normal'))
        grain = rng.random((atlas.cell,atlas.cell),dtype=np.float32)-.5
        brush = np.repeat(rng.uniform(-.5,.5,(atlas.cell,1)),atlas.cell,axis=1)
        yy,xx = np.mgrid[:atlas.cell,:atlas.cell]
        # Several scales of irregular coating and brushed substrate variation.
        coarse = rng.random((12,12))
        coarse = np.repeat(np.repeat(coarse,math.ceil(atlas.cell/12),0),math.ceil(atlas.cell/12),1)
        coarse = coarse[:atlas.cell,:atlas.cell]
        for _ in range(8):
            coarse = (coarse+np.roll(coarse,1,0)+np.roll(coarse,-1,0)
                      +np.roll(coarse,1,1)+np.roll(coarse,-1,1))/5
        color *= (1+grain*.10+brush*.018+(coarse-.5)*.035)[:,:,None]
        orm[:,:,1] = np.clip(orm[:,:,1]+grain*.055+brush*.024+(coarse-.5)*.035,.22,.72)
        obj = objects[record['part']]
        if record['role']=='structure':
            orm[:,:,2] = obj.data.materials[0].node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value
            orm[:,:,1] += .04
        # Wear follows the polygon perimeter in its projected UV tile, rather
        # than unrelated square tile borders. Internal triangulation is ignored.
        distance = np.full((atlas.cell,atlas.cell),atlas.cell,dtype=np.float32)
        if 'wear_outline' in obj:
            outline = np.array(obj['wear_outline']).reshape(-1,3)
            outline = np.array([obj.matrix_world @ Vector(p) for p in outline])
            vertices = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
            axes = [axis for axis in range(3) if axis != obj['wear_axis']]
            low,span=vertices.min(0),np.maximum(vertices.max(0)-vertices.min(0),1e-6)
            uv = 8+(outline[:,axes]-low[axes])/span[axes]*(atlas.cell-16)
            for a,b in zip(uv,np.roll(uv,-1,axis=0)):
                dx,dy=b-a
                t=np.clip(((xx-a[0])*dx+(yy-a[1])*dy)/max(dx*dx+dy*dy,1e-6),0,1)
                distance=np.minimum(distance,np.hypot(xx-a[0]-t*dx,yy-a[1]-t*dy))
            grime=np.exp(-distance/2.2)*(coarse*.35+.12)
            color *= (1-grime)[:,:,None]
            orm[:,:,1] += grime*.16
        # Individual scratches, fine pits and clustered chips reveal substrate.
        scratch = np.zeros((atlas.cell,atlas.cell),dtype=bool)
        for _ in range(9 if record['role']=='paint' else 13):
            x = rng.integers(10,atlas.cell-10)
            y = rng.integers(10,atlas.cell-10)
            length = rng.integers(3,18)
            for step in range(length):
                sx,sy=min(x+step,atlas.cell-9),min(y+step//5,atlas.cell-9)
                if rng.random()>.22:
                    scratch[sy,sx] = True
        if record['role']=='paint':
            scratch |= (distance<1.65) & (grain>.05) & (coarse>.40)
            scratch |= (rng.random(scratch.shape)>.997) & (coarse>.52)
            # Exposed substrate color is material information, not light.
            color[scratch] = (.38,.39,.40)
            orm[:,:,1][scratch] = .46
            orm[:,:,2][scratch] = .94
        else:
            scratch |= (distance<1.2) & (grain>.13) & (coarse>.45)
            color[scratch] = np.clip(color[scratch]*1.35+.045,0,1)
            orm[:,:,1][scratch] = .39
        height = grain*.065+brush*.014-scratch*.06
        dy,dx = np.gradient(height)
        n = np.stack((-dx,-dy,np.ones_like(dx)),axis=2)
        n /= np.linalg.norm(n,axis=2,keepdims=True)
        normal[:,:,:] = n*.5+.5
    for key,pixels in maps.items():
        surfaces.write_png(atlas.directory/(key+'.png'),pixels)
        atlas.images[key].reload()
    manifest['source'] = 'Shared ship_surface_atlas.py + alien-review/build_models.py surface_wear; deterministic component finish'
    manifest['finish'] = 'Polygon-edge coating chips, seam grime, multiscale mottling, directional scratches and brushed micrograin; no baked lighting'
    surfaces.write_manifest(manifest_path,manifest)


def texture_parts(name: str) -> surfaces.SurfaceAtlas:
    """Use the existing deterministic atlas workflow on editable components."""
    surfaces.PAINT_MATERIALS.add(geo.M['paint'].name)
    bpy.context.view_layer.update()
    # Small repeated fittings share finish tiles, preserving texel density for armor.
    representatives, shared = [], {}
    for obj in sorted(geo.PARTS, key=lambda o:o.name):
        extent = sorted(obj.dimensions, reverse=True)
        if 'wear_outline' in obj or extent[0]*extent[1]>.075:
            representatives.append(obj)
        else:
            material = obj.data.materials[0].name
            if material not in shared:
                shared[material] = obj
                representatives.append(obj)
    atlas = surfaces.SurfaceAtlas(representatives, HERE/'materials'/name.lower())
    surface_wear(atlas)
    manifest_path = atlas.directory/'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    records = {r['part']:r for r in manifest['parts']}
    for obj in geo.PARTS:
        if obj.name not in atlas.slots:
            sample = shared[obj.data.materials[0].name]
            atlas.slots[obj.name] = atlas.slots[sample.name]
            record = dict(records[sample.name],part=obj.name,shared_finish=sample.name)
            manifest['parts'].append(record)
    manifest['tile_policy'] = 'Unique fitted armor tiles; repeated small hardware shares material finish tiles'
    surfaces.write_manifest(manifest_path,manifest)
    for obj in geo.PARTS:
        for old in list(obj.data.uv_layers):
            obj.data.uv_layers.remove(old)
        uv = obj.data.uv_layers.new(name='Fitted component atlas')
        # Primitives arrive with UVMap. The atlas must be the render/active UV
        # for both bevel evaluation and GLB export, not just a second layer.
        obj.data.uv_layers.active_index = len(obj.data.uv_layers)-1
        uv.active_render = True
        coordinates = atlas.coordinates(obj, obj.data)
        assert len(coordinates) == len(uv.data)
        for loop, pair in zip(uv.data, coordinates):
            loop.uv = pair
    for mat in geo.M.values():
        atlas.apply_material(mat)
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Coat Weight'].default_value = .12 if mat==geo.M['paint'] else 0
        bsdf.inputs['Coat Roughness'].default_value = .38
    for image in atlas.images.values():
        image.pack()
    return atlas


def studio(name: str, root: bpy.types.Object, draft: bool) -> dict[str, bpy.types.Object]:
    scene = bpy.context.scene
    bounds = [obj.matrix_world @ Vector(p) for obj in geo.PARTS for p in obj.bound_box]
    low = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    center = (low+high)/2
    extent = max(high-low)
    scene.render.engine = 'BLENDER_EEVEE'
    scene.eevee.use_raytracing = True
    scene.eevee.use_fast_gi = True
    scene.eevee.fast_gi_quality = 1
    scene.eevee.fast_gi_ray_count = 8
    scene.eevee.taa_render_samples = 32 if draft else 64
    scene.render.resolution_x = 960 if draft else 1600
    scene.render.resolution_y = 720 if draft else 1200
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = True
    scene.world = bpy.data.worlds.new('Neutral studio')
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value = (.22,.24,.27,1)
    bg.inputs[1].default_value = .38
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    geo.group('Studio | six cameras and neutral lights')
    cameras = {}
    offsets = {'perspective':(9,-12,8),'top':(0,0,16),'side':(16,0,0),
               'front':(0,-16,0),'rear':(0,16,0),'underside':(0,0,-16)}
    for view, offset in offsets.items():
        data = bpy.data.cameras.new(name+' '+view)
        obj = bpy.data.objects.new(name+' '+view,data)
        geo.GROUP.objects.link(obj)
        obj.location = center+Vector(offset)
        geo.point_at(obj, center)
        data.type = 'ORTHO'
        inverse = obj.rotation_euler.to_quaternion().inverted()
        projected = [inverse @ (p-center) for p in bounds]
        aspect = scene.render.resolution_x/scene.render.resolution_y
        data.ortho_scale = max(max(abs(p.x)*2 for p in projected),
                              max(abs(p.y)*2*aspect for p in projected))*1.15
        cameras[view] = obj
    spec = SPECS[name]
    r=spec['engine_radius']
    studies = {
        'armor-detail': ((0,-.85,.55 if name!='Heavy' else 1.0),(3,-4,5),2.45 if name=='Scout' else 3.05),
        'mount-detail': ((1.24 if name!='Heavy' else 1.7,-.40,.02),(5,-4,2),2.15 if name=='Scout' else 2.65),
        'drive-detail': ((spec['engine_x'],spec['engine_y']+spec['engine_length']-.25,
                          spec['engine_z']),(3,5,2),r*5.2)
    }
    for view,(target,offset,scale) in studies.items():
        data=bpy.data.cameras.new(name+' '+view)
        obj=bpy.data.objects.new(name+' '+view,data)
        geo.GROUP.objects.link(obj)
        obj.location=Vector(target)+Vector(offset)
        geo.point_at(obj,Vector(target))
        data.type='ORTHO'
        data.ortho_scale=scale
        cameras[view]=obj
    for label, loc, power, size, color in (
        ('Soft key',(-5,-6,9),1450,6,(.96,.98,1)),
        ('Front fill',(6,-3,5),650,5,(.88,.94,1)),
        ('Aft rim',(2,7,7),1700,4,(1,.95,.88)),
        ('Ventral fill',(-3,-1,-6),750,5,(.82,.88,1))):
        data = bpy.data.lights.new(label,'AREA')
        data.energy, data.size, data.color = power, size, color
        obj = bpy.data.objects.new(label,data)
        geo.GROUP.objects.link(obj)
        obj.location = loc
        geo.point_at(obj, center)
    scene.camera = cameras['perspective']
    geo.group('References | approved concept, hidden')
    image = bpy.data.images.load(str(HERE/'concepts'/(name.lower()+'.png')))
    image.pack()
    obj = bpy.data.objects.new(name+' approved concept',None)
    obj.empty_display_type = 'IMAGE'
    obj.data = image
    obj.empty_display_size = extent
    obj.location = (extent+2,0,0)
    obj.hide_render = True
    geo.GROUP.objects.link(obj)
    geo.GROUP.hide_viewport = True
    notes = bpy.data.texts.new('READ ME - alien model')
    notes.write(name+' alien spacecraft. Forward -Y; up +Z.\n'
                'The approved generated concept is packed under References.\n'
                'Collections separate hull, wings, engines, weapons and sensors.\n'
                'Six full views and three detail cameras render this mesh. F12: hero view.\n'
                'All surface atlases are packed, with editable component UVs.\n'
                'Geometry resolves conflicting generated angles; dimensions are review units.\n'
                'Review GLB has Z up and -Y forward after import into Blender.\n'
                'Runtime orientation/size/collisions and LODs remain separate integration work.\n')
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                space = area.spaces.active
                space.shading.type = 'MATERIAL'
                space.overlay.show_floor = False
                space.overlay.show_axis_x = space.overlay.show_axis_y = False
                space.region_3d.view_location = center
                space.region_3d.view_distance = extent*1.55
                space.region_3d.view_rotation = cameras['perspective'].rotation_euler.to_quaternion()
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    for obj in scene.objects:
        if obj.type in {'CAMERA','LIGHT'}:
            obj.hide_set(True)
    return cameras


def export_model(name: str, directory: Path | None = None,
                 visual_diameter: float | None = None) -> dict:
    """Reduced bevels; one textured mesh, no lights, cameras or references."""
    for obj in geo.PARTS:
        for modifier in obj.modifiers:
            if modifier.type == 'BEVEL':
                modifier.segments = 1
    graph = bpy.context.evaluated_depsgraph_get()
    vertices, faces, indices, smooth, normals, uvs, materials = [],[],[],[],[],[],[]
    material_ids = {}
    omitted_triangles = 0
    for obj in geo.PARTS:
        evaluated = obj.evaluated_get(graph)
        data = evaluated.to_mesh()
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ v.co for v in data.vertices)
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        mapping = {}
        for i, mat in enumerate(data.materials):
            if mat.name not in material_ids:
                material_ids[mat.name] = len(materials)
                materials.append(mat)
            mapping[i] = material_ids[mat.name]
        # Bevel/NGon triangulation can create slivers even when the evaluated
        # polygons have positive area. Export explicit triangles, carrying
        # each corner's UV/normal, and omit only sub-nanounit surface areas.
        data.calc_loop_triangles()
        for triangle in data.loop_triangles:
            if triangle.area<=1e-9:
                omitted_triangles += 1
                continue
            polygon = data.polygons[triangle.polygon_index]
            faces.append([offset+i for i in triangle.vertices])
            indices.append(mapping[polygon.material_index])
            smooth.append(polygon.use_smooth)
            normals.extend((normal_matrix @ data.corner_normals[i].vector).normalized()
                           for i in triangle.loops)
            uvs.extend(tuple(data.uv_layers.active.data[i].uv) for i in triangle.loops)
        evaluated.to_mesh_clear()
    if visual_diameter is not None:
        low=Vector(tuple(min(v[i] for v in vertices) for i in range(3)))
        high=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
        center=(low+high)/2
        scale=visual_diameter/(high-low).length
        rotation=Matrix.Rotation(math.pi,3,'Z')
        vertices=[rotation @ ((v-center)*scale) for v in vertices]
        normals=[rotation @ n for n in normals]
    mesh = bpy.data.meshes.new(name+' export')
    mesh.from_pydata(vertices,[],faces)
    mesh.update()
    for mat in materials:
        mesh.materials.append(mat)
    for polygon, material, is_smooth in zip(mesh.polygons,indices,smooth):
        polygon.material_index = material
        polygon.use_smooth = is_smooth
    mesh.normals_split_custom_set(normals)
    layer = mesh.uv_layers.new(name='Fitted component atlas')
    assert len(uvs) == len(layer.data)
    for loop, uv in zip(layer.data,uvs):
        loop.uv = uv
    bpy.ops.object.select_all(action='DESELECT')
    hull = bpy.data.objects.new(name,mesh)
    bpy.context.scene.collection.objects.link(hull)
    hull.select_set(True)
    bpy.context.view_layer.objects.active = hull
    path = (directory or HERE/'exports')/(name.lower()+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
                              export_yup=True,export_cameras=False,export_lights=False,
                              export_animations=False)
    surfaces.deduplicate_textures(path)
    mesh.calc_loop_triangles()
    result={'triangles':len(mesh.loop_triangles),'materials':len(materials),
            'bytes':path.stat().st_size,'omitted_degenerate_triangles':omitted_triangles}
    if visual_diameter is not None:
        bounds=Vector(tuple(max(v[i] for v in vertices)-min(v[i] for v in vertices) for i in range(3)))
        result.update({'visual_diameter':visual_diameter,
                       'bounds_godot':[round(bounds.x,6),round(bounds.z,6),round(bounds.y,6)],
                       'forward':'-Z','up':'+Y','atlas_size':surfaces.SIZE})
    return result


def build(name: str, draft: bool) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    geo.PARTS = []
    spec = SPECS[name]
    geo.M = {key:geo.material(label,color,metal,rough,emission)
             for key,label,color,metal,rough,emission in (
                 ('paint',name+' coated armor',spec['color'],.18,.34,0),
                 ('dark','Dark mechanical structure',(.016,.019,.021),.55,.47,0),
                 ('graphite','Graphite armor',(.039,.043,.046),.65,.40,0),
                 ('gunmetal','Gunmetal',(.11,.13,.14),.95,.29,0),
                 ('steel','Brushed titanium',(.15,.17,.19),.95,.27,0),
                 ('recess','Deep panel recess',(.006,.009,.011),.0,.55,0),
                 ('light',name+' sensor emission',spec['light'],.0,.35,1.3))}
    body(spec,name=='Heavy')
    wings(spec,name)
    engines(spec)
    weapons_and_sensors(spec,name)
    root = bpy.data.objects.new(name,None)
    bpy.context.scene.collection.objects.link(root)
    root['forward_axis'] = '-Y, Z up'
    root['reference_status'] = 'Approved Dorbit generated alien concept; packed in References.'
    root['review_scale'] = 'Modeling units; game size and collisions are not assigned.'
    for obj in geo.PARTS:
        obj.parent = root
    # Catch collapsed bevel faces before creating textures or review renders.
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in geo.PARTS:
        evaluated = obj.evaluated_get(graph)
        data = evaluated.to_mesh()
        assert all(p.area>1e-10 for p in data.polygons), 'Degenerate evaluated face: '+obj.name
        evaluated.to_mesh_clear()
    texture_parts(name)
    cameras = studio(name,root,draft)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.context.scene.render.filepath = str(HERE/'previews'/(name.lower()+'.png'))
    path = HERE/'models'/(name.lower()+'.blend')
    bpy.ops.wm.save_as_mainfile(filepath=str(path),compress=True)
    stats = {'mesh_components':len(geo.PARTS),
             'base_faces':sum(len(o.data.polygons) for o in geo.PARTS),
             'draft':draft, 'views':list(cameras), 'atlas_size':surfaces.SIZE}
    for view, camera in cameras.items():
        if draft and view not in {'perspective','top'}:
            continue
        bpy.context.scene.camera = camera
        suffix = '' if view=='perspective' else '-'+view
        bpy.context.scene.render.filepath = str(HERE/'previews'/(name.lower()+suffix+'.png'))
        bpy.ops.render.render(write_still=True)
        print('RENDERED',name,view,flush=True)
    if not draft:
        stats['export'] = export_model(name)
    report_path = HERE/'build-stats.json'
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    report[name] = stats
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    print('COMPLETE',name,stats,flush=True)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    names = [arg for arg in args if not arg.startswith('--')] or list(NAMES)
    if set(names)-set(NAMES):
        raise ValueError('Unknown alien: '+', '.join(sorted(set(names)-set(NAMES))))
    if set(arg for arg in args if arg.startswith('--'))-{'--draft'}:
        raise ValueError('Only --draft is supported as a build option')
    for folder in ('models','previews','materials','exports'):
        (HERE/folder).mkdir(exist_ok=True)
    for name in names:
        build(name,'--draft' in args)
