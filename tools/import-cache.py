#!/usr/bin/env python3
"""Reuse only imports whose source, settings, dependencies and context match."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import sys
from urllib.parse import unquote

VERSION = 2
EXTENSIONS = {'.png', '.jpg', '.jpeg', '.svg', '.webp', '.glb', '.gltf', '.ogg', '.wav', '.mp3', '.ttf', '.otf', '.hdr', '.exr'}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def context(project: Path) -> str:
    # Only discard a known runtime-only setting; unknown settings invalidate.
    settings = '\n'.join(line.strip() for line in (project / 'project.godot').read_text().splitlines()
                         if line.strip() and not line.lstrip().startswith(';')
                         and not line.strip().startswith('run/flush_stdout_on_print='))
    return digest(f'{VERSION}\n{sys.platform}\nGodot-4.7.2\n{settings}'.encode())


def dependencies(project: Path, path: Path, seen: set[Path]) -> list[tuple[str, str]]:
    path = path.resolve()
    if not path.is_relative_to(project) or path in seen:
        return []
    seen.add(path)
    if not path.is_file() or path.is_symlink():
        return [(path.relative_to(project).as_posix(), 'missing')]
    data = path.read_bytes()
    result = [(path.relative_to(project).as_posix(), digest(data))]
    if path.suffix in {'.gd', '.import', '.gltf', '.tscn', '.tres'}:
        text = data.decode('utf-8')
        for reference in re.findall(r"res://([^\"'\n]+)", text):
            if not reference.startswith('.godot/'):
                result += dependencies(project, project / reference, seen)
    if path.suffix in {'.gltf', '.glb'}:
        try:
            if path.suffix == '.glb':
                length = struct.unpack_from('<I', data, 12)[0]
                document = json.loads(data[20:20 + length])
            else:
                document = json.loads(data)
            for reference in document.get('buffers', []) + document.get('images', []):
                uri = reference.get('uri', '')
                if uri and not uri.startswith('data:'):
                    dependency = path.parent / unquote(uri)
                    result += dependencies(project, dependency, seen)
                    metadata = Path(str(dependency) + '.import')
                    if metadata.is_file():
                        result += dependencies(project, metadata, seen)
        except (ValueError, struct.error):
            pass  # Godot reports malformed assets during the mandatory import.
    return result


def inputs(project: Path) -> dict:
    resources = {}
    for path in sorted((project / 'assets').rglob('*')):
        if not path.is_file() or path.is_symlink() or path.suffix == '.import':
            continue
        metadata = Path(str(path) + '.import')
        if path.suffix not in EXTENSIONS and not metadata.is_file():
            continue
        values = dependencies(project, path, set())
        if metadata.is_file():
            # Preserve every import parameter; each OS uses its own cache.
            values += dependencies(project, metadata, set())
        else:
            values.append((metadata.relative_to(project).as_posix(), 'missing'))
        resources[path.relative_to(project).as_posix()] = digest(json.dumps(sorted(values)).encode())
    return {'version': VERSION, 'context': context(project), 'resources': resources}


def read_manifest(cache: Path) -> dict:
    try:
        manifest = json.loads((cache / 'manifest.json').read_text())
        return manifest if isinstance(manifest, dict) and manifest.get('version') == VERSION and isinstance(manifest.get('entries'), dict) else {}
    except (OSError, ValueError):
        return {}


def safe_output(name: str) -> bool:
    return isinstance(name, str) and bool(name) and Path(name).name == name and '/' not in name and '\\' not in name and name not in {'.', '..'}


def prepare(project: Path, cache: Path) -> dict:
    current = inputs(project)
    old = read_manifest(cache)
    imported = project / '.godot/imported'
    imported.mkdir(parents=True, exist_ok=True)
    # This derived directory is the only deletion target; never touch sources.
    if imported.is_symlink() or imported.resolve() != project / '.godot/imported':
        raise ValueError('Imported resources must be inside the project')
    for path in imported.iterdir():
        if path.is_file() or path.is_symlink():
            path.unlink()
    reused = 0
    entries = old.get('entries', {}) if old.get('context') == current['context'] else {}
    for source, fingerprint in current['resources'].items():
        entry = entries.get(source, {})
        if not isinstance(entry, dict):
            continue
        outputs = entry.get('outputs', {})
        if entry.get('fingerprint') != fingerprint or not isinstance(outputs, dict) or not outputs:
            continue
        if not all(safe_output(name) and (cache / 'imported' / name).is_file()
                   and not (cache / 'imported' / name).is_symlink()
                   and digest((cache / 'imported' / name).read_bytes()) == expected
                   for name, expected in outputs.items()):
            continue
        for name in outputs:
            shutil.copyfile(cache / 'imported' / name, imported / name)
        reused += 1
    (project / '.godot/ci-import-inputs.json').write_text(json.dumps(current), encoding='utf-8')
    print(f'IMPORT CACHE: reused {reused}/{len(current["resources"])} resources', flush=True)
    return current


def capture(project: Path, cache: Path) -> dict:
    snapshot = json.loads((project / '.godot/ci-import-inputs.json').read_text())
    target = cache / 'imported'
    target.mkdir(parents=True, exist_ok=True)
    if target.is_symlink() or target.resolve() != cache / 'imported':
        raise ValueError('Cache outputs must be inside the cache directory')
    # Drop old outputs, including removed resources; cache keys remain immutable.
    for path in target.iterdir():
        if path.is_file() or path.is_symlink():
            path.unlink()
    entries = {}
    for source, fingerprint in snapshot['resources'].items():
        resource = 'res://' + source
        prefix = Path(source).name + '-' + hashlib.md5(resource.encode()).hexdigest() + '.'
        outputs = {}
        for path in (project / '.godot/imported').glob(prefix + '*'):
            if path.is_file() and not path.is_symlink():
                shutil.copyfile(path, target / path.name)
                outputs[path.name] = digest(path.read_bytes())
        if outputs:
            entries[source] = {'fingerprint': fingerprint, 'outputs': outputs}
    result = {'version': VERSION, 'context': snapshot['context'], 'entries': entries}
    # The manifest is written last; a failed build never calls capture.
    (cache / 'manifest.json').write_text(json.dumps(result, sort_keys=True), encoding='utf-8')
    print(f'IMPORT CACHE: captured {len(entries)} resources', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('task', choices=['prepare', 'capture', 'key'])
    parser.add_argument('--project', type=Path, default=Path.cwd())
    parser.add_argument('--cache', type=Path, default=Path('.ci/import-cache'))
    args = parser.parse_args()
    project, cache = args.project.resolve(), args.cache.resolve()
    if args.task == 'key':
        print(digest(json.dumps(inputs(project), sort_keys=True).encode()))
    else:
        globals()[args.task](project, cache)


if __name__ == '__main__':
    main()
