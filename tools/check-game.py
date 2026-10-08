#!/usr/bin/env python3
"""Run all existing checks with bounded concurrency and isolated test resources."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ERROR = re.compile(r'SCRIPT ERROR:|Parse Error:|ERROR:')


def commands(suite: str, engine: str) -> list[tuple[str, list[list[str]]]]:
    plan = json.loads((ROOT / 'tools/check-suites.json').read_text())[suite]
    result = []
    for group in plan:
        checks = []
        for check in group['checks']:
            if check[0].endswith('.py'):
                checks.append([sys.executable, *check, engine] if check[0].endswith('server_shutdown_test.py')
                              else [sys.executable, *check])
            else:
                checks.append([engine, '--headless', '--max-fps', '60', '--path', str(ROOT), '--script', 'res://tests/' + check[0], *check[1:]])
        result.append((group['name'], checks))
    return result


def run_group(name: str, checks: list[list[str]], profile: Path, offset: int) -> list[dict]:
    profile.mkdir(parents=True)
    env = dict(os.environ, APPDATA=str(profile), XDG_DATA_HOME=str(profile),
               XDG_CONFIG_HOME=str(profile / 'config'), DORBIT_TEST_PORT_OFFSET=str(offset))
    # Never inherit an operator's pilot ledger into a validation process.
    for variable in ('DORBIT_DATA_DIR', 'DORBIT_PILOT_FILE'):
        env.pop(variable, None)
    results = []
    for command in checks:
        started = time.perf_counter()
        try:
            process = subprocess.run(command, cwd=ROOT, env=env, capture_output=True,
                                     text=True, encoding='utf-8', errors='replace', timeout=180)
            output = process.stdout + process.stderr
            failed = process.returncode != 0 or ERROR.search(output) is not None
        except subprocess.TimeoutExpired as error:
            output = f'Check timed out after 180 seconds: {error}'
            failed = True
        results.append({'group': name, 'command': subprocess.list2cmdline(command),
                        'seconds': round(time.perf_counter() - started, 2), 'failed': failed, 'output': output})
        if failed:
            break
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine', type=Path)
    parser.add_argument('--suite', choices=['windows', 'linux'], required=True)
    parser.add_argument('--workers', type=int, default=int(os.environ.get('DORBIT_TEST_WORKERS', '1')))
    args = parser.parse_args()
    if not 1 <= args.workers <= 4:
        parser.error('workers must be between 1 and 4')
    groups = commands(args.suite, str(args.engine.resolve()))
    started = time.perf_counter()
    results = []
    output_dir = ROOT / 'build/validation'
    output_dir.mkdir(parents=True, exist_ok=True)
    # Keep intentional restart sequences together, with a fresh profile per group.
    with tempfile.TemporaryDirectory(prefix='dorbit-checks-') as directory, ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(run_group, name, checks, Path(directory) / name, (index + 1) * 500)
                   for index, (name, checks) in enumerate(groups)]
        for future in as_completed(futures):
            group_results = future.result()
            results.extend(group_results)
            for result in group_results:
                print(result['output'], end='' if result['output'].endswith('\n') else '\n', flush=True)
                print(f'TIMING: {result["command"]}: {result["seconds"]:.2f}s (exit {int(result["failed"])})', flush=True)
    duration = round(time.perf_counter() - started, 2)
    (output_dir / f'checks-{args.suite}.json').write_text(json.dumps({'workers': args.workers, 'seconds': duration,
                                                                'results': results}, indent=2), encoding='utf-8')
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as target:
            target.write(f'\n### {args.suite} tests ({args.workers} workers, {duration} s elapsed)\n\n| Group | Command | Seconds | Result |\n| --- | --- | ---: | --- |\n')
            for result in results:
                target.write(f'| {result["group"]} | `{result["command"]}` | {result["seconds"]} | {"FAILED" if result["failed"] else "OK"} |\n')
    print(f'TIMING: {args.suite} suite ({args.workers} workers): {duration}s', flush=True)
    return int(any(result['failed'] for result in results))


if __name__ == '__main__':
    raise SystemExit(main())
