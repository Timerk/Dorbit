"""Cache invalidation, test isolation/coverage, and documentation gating checks."""
import importlib.util
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'tools' / f'{name}.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


cache_tool = module('import-cache')
runner = module('check-game')
changes = module('ci-changes')


class CacheTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project'
        self.root.mkdir()
        self.cache = Path(self.temp.name) / 'cache'
        (self.root / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Fixture"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        (self.root / 'assets').mkdir()
        (self.root / 'tools').mkdir()
        (self.root / 'tools/import.gd').write_text('print("hook")\n')
        for name in ('a.glb', 'b.svg'):
            (self.root / 'assets' / name).write_bytes(b'source')
            hook = '\nimport_script/path="res://tools/import.gd"' if name.endswith('glb') else ''
            (self.root / 'assets' / (name + '.import')).write_text('[params]\nroot_scale=1.0' + hook)
        cache_tool.prepare(self.root, self.cache)
        for source in ('a.glb', 'b.svg'):
            prefix = source + '-' + hashlib.md5(('res://assets/' + source).encode()).hexdigest()
            for extension in ('.scn', '.md5'):
                (self.root / '.godot/imported' / (prefix + extension)).write_bytes(b'derived')
        cache_tool.capture(self.root, self.cache)

    def restored(self):
        cache_tool.prepare(self.root, self.cache)
        return sorted(p.name.split('-')[0] for p in (self.root / '.godot/imported').glob('*.scn'))

    def test_same_inputs_and_runtime_only_changes_reuse(self):
        project = self.root / 'project.godot'
        project.write_text(project.read_text().replace('config/name="Fixture"', 'config/name="Fixture"\nrun/flush_stdout_on_print=true'))
        (self.root / 'assets/README.md').write_text('New documentation')
        (self.root / 'game.gd').write_text('Changed runtime script')
        self.assertEqual(self.restored(), ['a.glb', 'b.svg'])

    def test_source_and_settings_invalidate_only_affected_asset(self):
        for filename in ('b.svg', 'b.svg.import'):
            with self.subTest(filename=filename):
                path = self.root / 'assets' / filename
                original = path.read_bytes()
                path.write_bytes(original + b' changed')
                self.assertEqual(self.restored(), ['a.glb'])
                path.write_bytes(original)

    def test_hook_and_its_dependencies_invalidate_scenes(self):
        (self.root / 'tools/import.gd').write_text("preload('res://tools/helper.gd')\n")
        helper = self.root / 'tools/helper.gd'
        helper.write_text('initial dependency')
        self.assertEqual(self.restored(), ['b.svg'])
        initial = cache_tool.inputs(self.root)['resources']['assets/a.glb']
        helper.write_text('changed dependency')
        self.assertNotEqual(cache_tool.inputs(self.root)['resources']['assets/a.glb'], initial)

    def test_external_gltf_images_and_their_import_settings(self):
        source = self.root / 'assets/external.gltf'
        source.write_text(json.dumps({'images': [{'uri': 'b.svg'}]}))
        initial = cache_tool.inputs(self.root)['resources']['assets/external.gltf']
        (self.root / 'assets/b.svg.import').write_text('[params]\nchanged=true')
        self.assertNotEqual(cache_tool.inputs(self.root)['resources']['assets/external.gltf'], initial)

    def test_renderer_change_invalidates_all(self):
        (self.root / 'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="forward_plus"')
        self.assertEqual(self.restored(), [])

    def test_corruption_and_unsafe_paths_are_not_restored(self):
        manifest = json.loads((self.cache / 'manifest.json').read_text())
        entry = manifest['entries']['assets/a.glb']
        output = next(iter(entry['outputs']))
        (self.cache / 'imported' / output).write_bytes(b'corrupted')
        self.assertEqual(self.restored(), ['b.svg'])
        entry['outputs'] = {'../escape': 'bad'}
        (self.cache / 'manifest.json').write_text(json.dumps(manifest))
        self.assertEqual(self.restored(), ['b.svg'])

    def test_missing_manifest_is_a_cold_cache(self):
        (self.cache / 'manifest.json').write_text('{invalid')
        self.assertEqual(self.restored(), [])

    def test_removed_asset_is_not_restored(self):
        (self.root / 'assets/b.svg').unlink()
        self.assertEqual(self.restored(), ['a.glb'])


class ValidationTest(unittest.TestCase):
    def test_real_git_diff_gates_docs_and_preserves_main_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.PIPE).decode().strip()
            git('init', '-q')
            git('config', 'user.name', 'CI fixture')
            git('config', 'user.email', 'ci-fixture@example.invalid')
            (root / 'README.md').write_text('initial docs')
            (root / 'assets').mkdir()
            (root / 'assets/runtime.svg').write_text('runtime source')
            git('add', '.')
            git('commit', '-qm', 'fixture base')
            base = git('rev-parse', 'HEAD')
            git('remote', 'add', 'origin', str(root))
            (root / 'README.md').write_text('updated docs')
            git('commit', '-qam', 'fixture docs')
            output = root / 'output'
            env = dict(os.environ, GITHUB_EVENT_NAME='pull_request', PR_BASE_SHA=base, GITHUB_OUTPUT=str(output))
            def classify():
                output.write_text('')
                subprocess.run([sys.executable, str(ROOT / 'tools/ci-changes.py')], cwd=root, env=env,
                               check=True, capture_output=True)
                return output.read_text().strip()
            self.assertEqual(classify(), 'build=false')
            env['GITHUB_EVENT_NAME'] = 'push'
            self.assertEqual(classify(), 'build=true')
            env['GITHUB_EVENT_NAME'] = 'pull_request'
            # Both sides of a rename must be classified, even into an ignored tree.
            (root / 'art').mkdir()
            git('mv', 'assets/runtime.svg', 'art/reference.svg')
            git('commit', '-qm', 'fixture rename')
            self.assertEqual(classify(), 'build=true')

    def test_documentation_allowlist_requires_runtime_changes(self):
        self.assertTrue(changes.documentation_only(['README.md', 'docs/ci-performance.md', 'art/ship-review/reference.png']))
        self.assertTrue(changes.documentation_only(['docs/ammo-art/laser-x1.png', 'docs/sector-art/asteroid-detail.png']))
        for path in ('assets/ui/new.svg', 'project.godot', 'tools/server.sh', 'tests/network_test.gd',
                     '.github/workflows/validate.yml', 'art/.gdignore', 'docs/sector-art/.gdignore', 'docs/ammo-art/.gdignore'):
            self.assertFalse(changes.documentation_only(['README.md', path]), path)
        self.assertFalse(changes.documentation_only([]))

    def test_restart_sequences_keep_their_order(self):
        plan = json.loads((ROOT / 'tools/check-suites.json').read_text())
        windows = plan['windows']
        settings = next(group for group in windows if group['name'] == 'settings')['checks']
        for script in ('connection_menu_test.gd', 'display_test.gd', 'graphics_test.gd'):
            checks = [check for check in settings if check[0] == script]
            self.assertEqual(checks[:2], [[script], [script, '--', '--restart']])
        self.assertEqual([check[-1] for check in settings if '--filter-restart' in check], ['2', '3', '4'])
        for suite in plan.values():
            names = [group['name'] for group in suite]
            self.assertEqual(len(names), len(set(names)), 'Suite groups must be unique')
            checks = [check for group in suite for check in group['checks']]
            commands = [tuple(check) for check in checks]
            self.assertEqual(len(commands), len(set(commands)), 'Suite commands must be unique')
            self.assertEqual(checks.count(['alien_assets_test.gd']), 1)
            self.assertEqual(checks.count(['hud_customization_test.gd']), 1)
            self.assertEqual(checks.count(['station_assets_test.gd']), 1)
            for script in ('skylab_test.gd', 'skylab_persistence_test.gd', 'skylab_ui_test.gd', 'extras_test.gd'):
                self.assertEqual(checks.count([script]), 1)
            self.assertEqual(checks.count(['rocket_test.gd']), 1)
            self.assertEqual(checks.count(['quickslots_test.gd']), 1)

    def test_network_fixtures_map_explicit_connection_ports(self):
        plan = json.loads((ROOT / 'tools/check-suites.json').read_text())
        pending = {check[0] for groups in plan.values() for group in groups
                   for check in group['checks'] if check[0].endswith('.gd')}
        seen = set()
        while pending:
            script = pending.pop()
            if script in seen:
                continue
            seen.add(script)
            text = (ROOT / 'tests' / script).read_text(encoding='utf-8')
            parent = re.search(r'^extends "res://tests/(.+?)"', text)
            if parent:
                pending.add(parent[1])
            # Factory ports are deliberately unshifted; connection ports are shifted once.
            raw = re.findall(r'session\.(?:join\([^,]+,|host\()\s*(\d{4,5})', text)
            self.assertEqual(raw, [], script)

    def test_process_profiles_ports_and_zero_exit_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            code = 'import os; print(os.environ["APPDATA"], os.environ["DORBIT_TEST_PORT_OFFSET"]); print("SCRIPT ERROR: fixture")'
            results = runner.run_group('fixture', [[sys.executable, '-c', code]], root / 'profile', 1500)
            self.assertTrue(results[0]['failed'])
            self.assertIn(str(root / 'profile'), results[0]['output'])
            self.assertIn('1500', results[0]['output'])


if __name__ == '__main__':
    unittest.main()
