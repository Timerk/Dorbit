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
if [[ ! -f "$staging/tools/check-server-export.py" ]]; then
  echo "Revision predates dedicated-server packaging; rebase the preview branch before building." >&2
  exit 1
fi
# setup verifies the pinned archive and extracts a fresh executable in the release.
# Reuse editor downloads and the separately checksum-verified release template.
tool_cache="${DORBIT_TOOL_CACHE:-.tools/godot-linux}"
for archive in "$tool_cache"/*.zip; do
  [[ -f "$archive" ]] || continue
  mkdir -p "$staging/.tools/godot-linux"
  cp "$archive" "$staging/.tools/godot-linux/"
done
if [[ -f "$tool_cache/linux_release.x86_64" ]]; then
  mkdir -p "$staging/.tools/godot-linux"
  cp "$tool_cache/linux_release.x86_64" "$staging/.tools/godot-linux/"
fi
# CI supplies an exact-input, OS-specific import cache. Keep all scripts and source
# assets from git archive; only Godot's derived imported resources are seeded.
import_cache="${DORBIT_IMPORT_CACHE:-}"
validated_cache="${DORBIT_VALIDATED_IMPORT_CACHE:-}"
if [[ -n "$validated_cache" ]]; then
  python3 "$staging/tools/import-cache.py" prepare --project "$staging" --cache "$validated_cache"
elif [[ -n "$import_cache" && -d "$import_cache" ]]; then
  mkdir -p "$staging/.godot/imported"
  cp -a "$import_cache/." "$staging/.godot/imported/"
fi
bash "$staging/tools/server.sh" setup
bash "$staging/tools/server.sh" check
bash "$staging/tools/server.sh" build
if [[ -n "$validated_cache" ]]; then
  python3 "$staging/tools/import-cache.py" capture --project "$staging" --cache "$validated_cache"
fi
if [[ -n "$import_cache" && -d "$staging/.godot/imported" ]]; then
  mkdir -p "$import_cache"
  cp -a "$staging/.godot/imported/." "$import_cache/"
fi
# Publish only the exported server and existing service/provisioning entry points.
# Keep the checkout/imports exclusively in disposable build staging.
package="$staging/package"
mkdir -p "$package/runtime" "$package/tools" "$package/deploy" "$package/assets/ships" "$package/assets/skylab" "$package/licenses"
cp "$staging/build/linux/DorbitServer.x86_64" "$staging/build/linux/DorbitServer.pck" "$package/runtime/"
cp "$staging/build/linux/THIRD_PARTY_NOTICES.txt" "$package/"
cp "$staging/tools/server.sh" "$staging/tools/run_server.py" "$staging/tools/pilots.py" "$package/tools/"
cp "$staging/deploy/dorbit.service" "$package/deploy/"
cp "$staging/assets/ships/catalog.json" "$package/assets/ships/"
cp "$staging/assets/skylab/balance-v1.json" "$package/assets/skylab/"
cp "$staging/assets/ui/fonts/OFL.txt" "$package/licenses/Rajdhani-OFL.txt"
mkdir -p "$tool_cache"
cp "$staging/.tools/godot-linux/linux_release.x86_64" "$tool_cache/"
printf '%s\n' "$revision" > "$package/REVISION"
mv -- "$package" "$release"
printf 'Prepared release: %s\n' "$release"
