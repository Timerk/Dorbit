#!/usr/bin/env bash
# Linux x86-64 / WSL2 helper; no desktop, GPU or export templates required.
set -euo pipefail
cd "$(dirname "$0")/.."
task="${1:-run}"
if (( $# > 0 )); then shift; fi
engine=".tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64"
archive="${engine}.zip"
checksum="cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"

checked() {
  local output
  if ! output=$("$engine" "$@" 2>&1); then
    printf '%s\n' "$output"
    return 1
  fi
  printf '%s\n' "$output"
  if [[ "$output" == *"SCRIPT ERROR:"* || "$output" == *"Parse Error:"* || "$output" == *"ERROR:"* ]]; then
    return 1
  fi
}

case "$task" in
  setup)
    mkdir -p .tools/godot-linux
    if [[ ! -f "$archive" ]]; then
      curl --fail --location --retry 3 \
        "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$(basename "$archive")" \
        --output "$archive"
    fi
    echo "$checksum  $archive" | sha256sum --check
    python3 - "$archive" <<'PY'
import sys, zipfile
from pathlib import Path
archive = Path(sys.argv[1])
with zipfile.ZipFile(archive) as source:
    name = archive.name.removesuffix('.zip')
    (archive.parent / name).write_bytes(source.read(name))
PY
    chmod +x "$engine"
    "$engine" --headless --version
    ;;
  run|check)
    if [[ ! -x "$engine" ]]; then
      echo "Run: bash tools/server.sh setup" >&2
      exit 1
    fi
    checked --headless --path . --editor --import
    if [[ "$task" == run ]]; then
      exec "$engine" --headless --max-fps 60 --path . -- --server "$@"
    fi
    checked --headless --path . --script res://tests/dedicated_server_test.gd
    ;;
  *)
    echo "Usage: bash tools/server.sh {setup|run|check} [--port=24567]" >&2
    exit 1
    ;;
esac
