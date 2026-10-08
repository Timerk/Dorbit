#!/usr/bin/env python3
"""Skip game validation only for known documentation inputs in pull requests."""
import os
import subprocess


def documentation_only(paths: list[str]) -> bool:
    def documentation(path: str) -> bool:
        if path.endswith('/.gdignore'):
            return False  # Removing an import boundary can expose runtime assets.
        if path.endswith('.md'):
            return True
        if path.startswith(('art/', 'docs/hud-design/', 'docs/menu-design/', 'docs/feedback/')):
            return True  # These trees have tracked .gdignore boundaries.
        return '/' not in path and path.endswith('-results.json')
    return bool(paths) and all(documentation(path) for path in paths)


def main():
    event = os.environ['GITHUB_EVENT_NAME']
    if event == 'pull_request':
        base = os.environ['PR_BASE_SHA']
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', base], check=True)
        changed = subprocess.check_output(['git', 'diff', '--name-only', '--no-renames', '-z', base, 'HEAD'])
        paths = [path.decode('utf-8') for path in changed.split(b'\0') if path]
        build = not documentation_only(paths)
    else:
        build = True  # Preserve every main revision's paired release/provenance.
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        output.write(f'build={str(build).lower()}\n')
    print('Game validation required' if build else 'Documentation-only PR: game builds skipped')


if __name__ == '__main__':
    main()
