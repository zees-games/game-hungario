#!/usr/bin/env bash
# The offline client with the touch layout on an 844x390 phone window: tools/screenshot_touch.sh [WxH]
set -euo pipefail
# A short frame sequence beside each still (DotShotSeq), so Nightly -> Review can play and scrub it.
export DOT_SHOT_FRAMES=${DOT_SHOT_FRAMES:-8} DOT_SHOT_SECS=${DOT_SHOT_SECS:-1}
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution "${1:-844x390}" --script tools/screenshot_touch.gd -- --offline --touch
