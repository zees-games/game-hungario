#!/bin/bash
# Publishes this game's pack. Host addons come from the server (--host-addons); web/ is a gitignored
# wasm build (42 MiB), images/ and screenshots/ are README art: none belongs in the pack.
#   tools/publish.sh VERSION [extra publish_pack.sh flags, e.g. --site URL --token-file F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [flags]}; shift
exec "$HERE/../dot-cloud/tools/publish_pack.sh" publish --source "$HERE" --id gamemann/game-hungario --version "$V" \
    --host-addons "$HERE/../dot-server-deploy/addons.lock" --exclude-dir web --exclude-dir images --exclude-dir screenshots \
    --lock "$HERE/content.lock.json" "$@"
