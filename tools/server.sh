#!/usr/bin/env bash
# Linux x86-64 / WSL2 helper; no desktop, GPU or export templates required.
set -euo pipefail
umask 077 # Saves and their backups contain authentication verifiers.
cd "$(dirname "$0")/.."
task="${1:-run}"
if (( $# > 0 )); then shift; fi
engine=".tools/godot-linux/Godot_v4.7.2-stable_linux.x86_64"
archive="${engine}.zip"
checksum="cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"

checked_command() {
  local output status=0 started=$SECONDS label="$*"
  output=$("$@" 2>&1) || status=$?
  printf '%s\n' "$output"
  if [[ "$output" == *"SCRIPT ERROR:"* || "$output" == *"Parse Error:"* || "$output" == *"ERROR:"* ]]; then
    status=1
  fi
  printf 'TIMING: %s: %ss (exit %s)\n' "$label" "$((SECONDS - started))" "$status"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '| `%s` | %s s | %s |\n' "$label" "$((SECONDS - started))" "$status" >> "$GITHUB_STEP_SUMMARY"
  fi
  return "$status"
}

checked() { checked_command "$engine" "$@"; }

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
    if [[ "$task" == check && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
      printf '\n### Linux import and test timings\n\n| Command | Duration | Exit |\n| --- | ---: | ---: |\n' >> "$GITHUB_STEP_SUMMARY"
    fi
    checked --headless --path . --editor --import
    if [[ "$task" == run ]]; then
      exec python3 tools/run_server.py "$engine" --headless --max-fps 60 --path . -- --server "$@"
    fi
    checked --headless --path . --script res://tests/dedicated_server_test.gd
    checked --headless --path . --script res://tests/sector_visuals_test.gd
    checked --headless --path . --script res://tests/combat_effects_test.gd
    checked --headless --path . --script res://tests/pilot_persistence_test.gd
    checked_command python3 tests/server_shutdown_test.py "$engine"
    checked --headless --path . --script res://tests/alien_sector_test.gd
    checked --headless --path . --script res://tests/map_layout_test.gd
    checked --headless --path . --script res://tests/map_layout_playthrough.gd
    checked --headless --path . --script res://tests/hud_playthrough.gd
    checked --headless --path . --script res://tests/autopilot_test.gd
    checked --headless --path . --script res://tests/targeting_test.gd
    checked --headless --path . --script res://tests/rpc_compatibility_test.gd
    checked --headless --path . --script res://tests/hunting_contracts_test.gd
    checked --headless --path . --script res://tests/economy_test.gd
    checked --headless --path . --script res://tests/equipment_test.gd
    checked --headless --path . --script res://tests/shop_test.gd
    checked --headless --path . --script res://tests/ammo_test.gd
    checked --headless --path . --script res://tests/main_menu_test.gd
    checked --headless --path . --script res://tests/offline_main_menu_test.gd -- --offline
    checked --headless --path . --script res://tests/ship_hangar_test.gd
    checked --headless --path . --script res://tests/ships_test.gd
    checked --headless --path . --script res://tests/balance_test.gd
    checked --headless --path . --script res://tests/darkorbit_equipment_test.gd
    checked --headless --path . --script res://tests/preview_credits_test.gd
    checked --headless --path . --script res://tests/resources_test.gd
    checked --headless --path . --script res://tests/resource_upgrades_test.gd
    checked_command python3 tests/pilots_test.py
    ;;
  *)
    echo "Usage: bash tools/server.sh {setup|run|check} [--port=24567]" >&2
    exit 1
    ;;
esac
