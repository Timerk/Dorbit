"""Deterministic ship PBR atlases, authored per editable Blender component.

Run through export_ships.py inside Blender. Box-projected UVs keep every fitted
part in its own padded tile; brush grain and roughness vary between panels.
No lighting or view-dependent highlights are painted into these textures.
"""
import hashlib
import json
import math
import struct
import zlib
from pathlib import Path

import bpy
import numpy as np

SIZE = 2048
PAINT_MATERIALS = {'Blue grey armor', 'Muted green grey armor', 'Cobalt enamel',
                   'Aegis green enamel', 'Defcom green enamel', 'Phoenix red enamel'}


def write_manifest(path: Path, manifest: dict) -> None:
    """Keep each component on one line so surface settings are easy to review."""
    metadata = {key: value for key, value in manifest.items() if key != 'parts'}
    header = json.dumps(metadata, indent=2).removesuffix('\n}')
    parts = ',\n'.join('    ' + json.dumps(part) for part in manifest['parts'])
    path.write_text(header + ',\n  "parts": [\n' + parts + '\n  ]\n}\n',
                    encoding='utf-8', newline='\n')


def write_png(path: Path, pixels: np.ndarray) -> None:
    """Write exact channel values without color transforms on data maps."""
    data = np.round(np.clip(pixels[:, :, :3], 0, 1) * 255).astype(np.uint8)
    def chunk(kind: bytes, content: bytes) -> bytes:
        return struct.pack('>I', len(content)) + kind + content + struct.pack('>I', zlib.crc32(kind + content))
    scanlines = b''.join(b'\0' + row.tobytes() for row in data[::-1])
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(scanlines, 9)) + chunk(b'IEND', b''))


def deduplicate_textures(path: Path) -> None:
    """Share identical atlas samplers across material surfaces in the GLB.

    Blender emits one texture entry per material node even for the same image
    and sampler. Godot can otherwise create redundant GPU texture resources.
    """
    original = path.read_bytes()
    magic, version, total, json_size, json_type = struct.unpack_from('<5I', original)
    assert magic == 0x46546C67 and version == 2 and total == len(original) and json_type == 0x4E4F534A
    document = json.loads(original[20:20 + json_size])
    unique, mapping, keys = [], {}, {}
    for index, texture in enumerate(document['textures']):
        key = json.dumps(texture, sort_keys=True)
        if key not in keys:
            keys[key] = len(unique)
            unique.append(texture)
        mapping[index] = keys[key]
    def remap(value: dict) -> None:
        for key, child in value.items():
            if isinstance(child, dict):
                if key.endswith('Texture') and 'index' in child:
                    child['index'] = mapping[child['index']]
                remap(child)
    for material in document['materials']:
        remap(material)
    document['textures'] = unique
    encoded = json.dumps(document, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    remaining = original[20 + json_size:]
    path.write_bytes(struct.pack('<5I', magic, version, 20 + len(encoded) + len(remaining), len(encoded), json_type)
                     + encoded + remaining)


class SurfaceAtlas:
    def __init__(self, objects: list, directory: Path):
        self.directory = directory
        directory.mkdir(parents=True, exist_ok=True)
        objects = sorted(objects, key=lambda obj: obj.name)
        self.grid = math.ceil(math.sqrt(len(objects)))
        self.cell = SIZE // self.grid
        self.slots = {obj.name: index for index, obj in enumerate(objects)}
        albedo = np.ones((SIZE, SIZE, 4), dtype=np.float32)
        orm = np.ones_like(albedo)
        normal = np.ones_like(albedo)
        normal[:, :, :2] = .5
        records = []
        y, x = np.mgrid[0:self.cell, 0:self.cell]
        for obj in objects:
            slot = self.slots[obj.name]
            row, col = divmod(slot, self.grid)
            mat = obj.data.materials[0]
            bsdf = mat.node_tree.nodes.get('Principled BSDF')
            seed = int.from_bytes(hashlib.sha256(obj.name.encode()).digest()[:8], 'little')
            rng = np.random.default_rng(seed)
            painted = mat.name in PAINT_MATERIALS
            metal = mat.name in {'Brushed titanium', 'Satin silver armor',
                                'Pale metal details', 'Gunmetal', 'Muted copper fittings'}
            glass = 'glass' in mat.name.lower() or 'glazing' in mat.name.lower()
            emissive = bsdf.inputs['Emission Strength'].default_value > 0
            metallic = .18 if painted else (.95 if metal else .35)
            roughness = (.29 if painted else .25 if metal else .43) + rng.uniform(-.035, .035)
            if glass or emissive:
                metallic, roughness = .0, .11 if glass else .35
            grain = rng.random((self.cell, self.cell), dtype=np.float32) - .5
            brush = np.repeat(rng.uniform(-1, 1, (self.cell, 1)), self.cell, axis=1)
            streak = np.sin(x * .06 + np.sin(y * .12))
            finish = np.clip(.975 + grain * .015 + brush * .006 + streak * .008, .94, 1)
            finish *= rng.uniform(.97, 1.0)
            r = np.clip(roughness + grain * .012 + brush * (.025 if metal else .008), .16, .62)
            height = grain * .008 + brush * (.02 if metal else .004)
            dy, dx = np.gradient(height)
            n = np.stack((-dx, -dy, np.ones_like(dx)), axis=2)
            n /= np.linalg.norm(n, axis=2, keepdims=True)
            region = np.s_[row * self.cell:(row + 1) * self.cell,
                           col * self.cell:(col + 1) * self.cell]
            color = np.array(bsdf.inputs['Base Color'].default_value[:3])
            if glass:
                # Retain each canopy's tint while separating it from colored armor.
                color *= min(1.0, .020 / max(float(color.max()), 1e-6))
            albedo[region][:, :, :3] = finish[:, :, None] * color
            orm[region][:, :, 0] = 1  # No invented ambient occlusion.
            orm[region][:, :, 1] = r
            orm[region][:, :, 2] = metallic
            normal[region][:, :, :3] = n * .5 + .5
            if glass or emissive:
                albedo[region][:, :, :3] = color
                normal[region][:, :, :3] = (.5, .5, 1)
                if glass:
                    orm[region][:, :, 1] = roughness
            records.append({'part': obj.name, 'tile': slot, 'material': mat.name,
                            'role': 'glass' if glass else 'emissive' if emissive else 'paint' if painted else 'metal' if metal else 'structure',
                            'base_color_linear': [round(float(value), 6) for value in color],
                            'metallic': metallic, 'roughness': round(roughness, 4)})
        self.images = {}
        for name, pixels in [('albedo', albedo), ('orm', orm), ('normal', normal)]:
            if name == 'albedo':
                pixels = np.where(pixels <= .0031308, pixels * 12.92, 1.055 * np.maximum(pixels, 0) ** (1 / 2.4) - .055)
            path = directory / (name + '.png')
            write_png(path, pixels)
            image = bpy.data.images.load(str(path))
            image.colorspace_settings.name = 'sRGB' if name == 'albedo' else 'Non-Color'
            self.images[name] = image
        write_manifest(directory / 'manifest.json', {
            'size': SIZE, 'grid': self.grid, 'padding_pixels': 8,
            'source': 'tools/ship_surface_atlas.py; deterministic per-component finish',
            'channels': {'albedo': 'sRGB hull colors and subtle finish variation',
                         'orm': 'R: 1 (no AO bake), G: roughness, B: metallic',
                         'normal': 'tangent-space +Y micrograin; no baked lighting'},
            'parts': records})

    def coordinates(self, obj, mesh) -> list[tuple[float, float]]:
        points = [obj.matrix_world @ vertex.co for vertex in mesh.vertices]
        low = [min(p[axis] for p in points) for axis in range(3)]
        span = [max(p[axis] for p in points) - low[axis] for axis in range(3)]
        row, col = divmod(self.slots[obj.name], self.grid)
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        uv = []
        for polygon in mesh.polygons:
            normal = normal_matrix @ polygon.normal
            dominant = max(range(3), key=lambda axis: abs(normal[axis]))
            axes = [axis for axis in range(3) if axis != dominant]
            for index in polygon.vertices:
                p = points[index]
                u, v = [(p[axis] - low[axis]) / max(span[axis], 1e-6) for axis in axes]
                uv.append(((col * self.cell + 8 + u * (self.cell - 16)) / SIZE,
                           (row * self.cell + 8 + v * (self.cell - 16)) / SIZE))
        return uv

    def apply_material(self, material) -> None:
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        bsdf = nodes.get('Principled BSDF')
        for link in list(bsdf.inputs['Normal'].links):
            links.remove(link)
        textures = {}
        for name, image in self.images.items():
            node = nodes.new('ShaderNodeTexImage')
            node.image = image
            node.extension = 'EXTEND'
            textures[name] = node
        links.new(textures['albedo'].outputs['Color'], bsdf.inputs['Base Color'])
        channels = nodes.new('ShaderNodeSeparateColor')
        links.new(textures['orm'].outputs['Color'], channels.inputs[0])
        links.new(channels.outputs['Green'], bsdf.inputs['Roughness'])
        links.new(channels.outputs['Blue'], bsdf.inputs['Metallic'])
        normal = nodes.new('ShaderNodeNormalMap')
        links.new(textures['normal'].outputs['Color'], normal.inputs['Color'])
        links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
        bsdf.inputs['Coat Weight'].default_value = .32 if material.name in PAINT_MATERIALS else 0
        bsdf.inputs['Coat Roughness'].default_value = .22
