#!/usr/bin/env bash
# Prepare a checked release from tracked files; installation is documented in DEPLOYMENT.md.
set -euo pipefail
cd "$(dirname "$0")/.."
if (( $# < 1 || $# > 2 )); then
  echo "Usage: bash tools/deploy-server.sh REVISION [RELEASE_DIRECTORY]" >&2
  exit 1
fi
if (( EUID == 0 )); then
  echo "Prepare releases as an unprivileged user, not root." >&2
  exit 1
fi
revision=$(git rev-parse --verify "${1}^{commit}")
mkdir -p "${2:-build/server-releases}"
releases=$(realpath "${2:-build/server-releases}")
release="$releases/$revision"
if [[ -e "$release" ]]; then
  echo "Release already exists: $release. Use a different release directory to rebuild." >&2
  exit 1
fi
staging=$(mktemp -d "$releases/.prepare.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
git archive "$revision" | tar -x -C "$staging"
# setup verifies the pinned archive and extracts a fresh executable in the release.
# Reuse downloads, never an executable from the working checkout.
tool_cache="${DORBIT_TOOL_CACHE:-.tools/godot-linux}"
for archive in "$tool_cache"/*.zip; do
  [[ -f "$archive" ]] || continue
  mkdir -p "$staging/.tools/godot-linux"
  cp "$archive" "$staging/.tools/godot-linux/"
done
# CI supplies an exact-input, OS-specific import cache. Keep all scripts and source
# assets from git archive; only Godot's derived imported resources are seeded.
import_cache="${DORBIT_IMPORT_CACHE:-}"
if [[ -n "$import_cache" && -d "$import_cache" ]]; then
  mkdir -p "$staging/.godot/imported"
  cp -a "$import_cache/." "$staging/.godot/imported/"
fi
bash "$staging/tools/server.sh" setup
bash "$staging/tools/server.sh" check
if [[ -n "$import_cache" && -d "$staging/.godot/imported" ]]; then
  mkdir -p "$import_cache"
  cp -a "$staging/.godot/imported/." "$import_cache/"
fi
printf '%s\n' "$revision" > "$staging/REVISION"
mv -- "$staging" "$release"
printf 'Prepared release: %s\n' "$release"
