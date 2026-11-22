#!/usr/bin/env bash
# The avatar shot: the player's rider close up on its monster, in a round with other monsters,
# saved as screenshots/<mode>_avatar.png. Routed to a real GPU by gpu.sh (`*_shot.sh`).
#
#   tools/avatar_shot.sh              # warrens
#   tools/avatar_shot.sh classic
set -euo pipefail
cd "$(dirname "$0")/.."
exec tools/screenshot_map.sh "${1:-warrens}" --avatar
