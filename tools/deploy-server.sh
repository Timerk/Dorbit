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
bash "$staging/tools/server.sh" setup
bash "$staging/tools/server.sh" check
printf '%s\n' "$revision" > "$staging/REVISION"
mv -- "$staging" "$release"
printf 'Prepared release: %s\n' "$release"
