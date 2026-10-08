"""Manually verify selective caching against real Godot-generated scene data.

Run: python tests/import_cache_godot_test.py PATH_TO_PINNED_GODOT
Kept outside routine CI because each invalidation exercises a cold hull import.
"""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('import_cache', ROOT / 'tools/import-cache.py')
cache_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache_tool)


def run(engine: Path, project: Path, *args: str) -> tuple[str, float]:
    started = time.perf_counter()
    process = subprocess.run([str(engine), '--headless', '--path', str(project), *args],
                             capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
    output = process.stdout + process.stderr
    if process.returncode or 'ERROR:' in output:
        raise AssertionError(output)
    return output, round(time.perf_counter() - started, 3)


def main(engine: Path) -> None:
    results = {}
    with tempfile.TemporaryDirectory(prefix='dorbit-import-cache-') as directory:
        parent = Path(directory)
        project = parent / 'cold'
        (project / 'assets/ships').mkdir(parents=True)
        (project / 'assets/ui').mkdir()
        (project / 'tools').mkdir()
        for name in ('liberator.glb', 'liberator.glb.import'):
            shutil.copyfile(ROOT / 'assets/ships' / name, project / 'assets/ships' / name)
        for name in ('rocket-preview.svg', 'rocket-preview.svg.import'):
            shutil.copyfile(ROOT / 'assets/ui' / name, project / 'assets/ui' / name)
        shutil.copyfile(ROOT / 'tools/import_ship_materials.gd', project / 'tools/import_ship_materials.gd')
        (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/features=PackedStringArray("4.7", "GL Compatibility")\n[editor]\nimport/use_multiple_threads=false\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (project / 'inspect.gd').write_text('extends SceneTree\nfunc _initialize():\n\tvar scene = load("res://assets/ships/liberator.glb").instantiate()\n\tprint("CACHE_SCENE:", JSON.stringify({"scale": scene.scale.x, "hook": scene.has_meta("changed_hook")}))\n\tscene.free()\n\tquit()\n')
        cache = parent / 'cache'
        cache_tool.prepare(project, cache)
        output, duration = run(engine, project, '--editor', '--import')
        assert 'Ship import:' in output, output
        cache_tool.capture(project, cache)
        results['cold'] = {'seconds': duration, 'hook_ran': True}
        for case in ('same_inputs', 'runtime_script', 'svg', 'import_settings', 'import_hook', 'source'):
            restored = parent / case
            shutil.copytree(project, restored, ignore=shutil.ignore_patterns('.godot'))
            # Hash exactly the checked-out metadata, before Godot updates it.
            for name in ('liberator.glb.import',):
                shutil.copyfile(ROOT / 'assets/ships' / name, restored / 'assets/ships' / name)
            shutil.copyfile(ROOT / 'assets/ui/rocket-preview.svg.import', restored / 'assets/ui/rocket-preview.svg.import')
            if case == 'runtime_script':
                (restored / 'game.gd').write_text('extends Node\n# unrelated runtime change\n')
            elif case == 'svg':
                path = restored / 'assets/ui/rocket-preview.svg'
                path.write_text(path.read_text().replace('</svg>', '<!-- changed -->\n</svg>'))
            elif case == 'import_settings':
                path = restored / 'assets/ships/liberator.glb.import'
                path.write_text(path.read_text().replace('nodes/root_scale=1.0', 'nodes/root_scale=2.0'))
            elif case == 'import_hook':
                path = restored / 'tools/import_ship_materials.gd'
                path.write_text(path.read_text().replace('\treturn scene', '\tscene.set_meta("changed_hook", true)\n\treturn scene'))
            elif case == 'source':
                path = restored / 'assets/ships/liberator.glb'
                data = path.read_bytes()
                assert b'Khronos glTF Blender' in data
                path.write_bytes(data.replace(b'Khronos glTF Blender', b'Khronos glTF BLENDER', 1))
            cache_tool.prepare(restored, cache)
            reused = len(list((restored / '.godot/imported').glob('*.md5')))
            output, duration = run(engine, restored, '--editor', '--import')
            hook_ran = 'Ship import:' in output
            assert hook_ran == (case in {'import_settings', 'import_hook', 'source'}), (case, output)
            output, _ = run(engine, restored, '--script', 'res://inspect.gd')
            scene = json.loads(next(line.split('CACHE_SCENE:', 1)[1] for line in output.splitlines() if line.startswith('CACHE_SCENE:')))
            assert scene['scale'] == (2.0 if case == 'import_settings' else 1.0), (case, scene)
            assert scene['hook'] == (case == 'import_hook'), (case, scene)
            results[case] = {'seconds': duration, 'reused': reused, 'hook_ran': hook_ran, 'scene': scene}
            print(case, json.dumps(results[case]), flush=True)
    target = ROOT / 'build/validation/import-cache-godot.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(results, indent=2) + '\n')
    print('Real Godot cache checks passed.', flush=True)


if __name__ == '__main__':
    main(Path(sys.argv[1]).resolve())
