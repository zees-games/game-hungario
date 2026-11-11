#!/usr/bin/env bash
# Renders one of this game's modes to screenshots/ so a person can look at the level.
#
#   tools/screenshot_map.sh warrens
#   tools/screenshot_map.sh reef --at=632,1180 --name=lagoon   # stand somewhere else
#   tools/screenshot_map.sh warrens --admin   # also a beacon and a blind
#   tools/screenshot_map.sh warrens --touch --ballot   # with the touch Menu button; godot --resolution 844x390 for a phone
#
# Uses xvfb-run because this needs a rendering context: --headless gives a null renderer
# and a 64 x 64 viewport, and every frame it saves is empty — which is worse than no
# screenshot because it looks like one.
set -euo pipefail
# A short frame sequence beside each still (DotShotSeq), so Nightly -> Review can play and scrub it.
export DOT_SHOT_FRAMES=${DOT_SHOT_FRAMES:-8} DOT_SHOT_SECS=${DOT_SHOT_SECS:-1}
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution 1280x800 \
    --script tools/screenshot_map.gd -- "${@:-warrens}"
