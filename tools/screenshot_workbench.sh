#!/usr/bin/env bash
# Renders the F9 tuning panel to screenshots/workbench_panel.png, to look at.
#
#   tools/screenshot_workbench.sh
set -euo pipefail
# A short frame sequence beside each still (DotShotSeq), so Nightly -> Review can play and scrub it.
export DOT_SHOT_FRAMES=${DOT_SHOT_FRAMES:-8} DOT_SHOT_SECS=${DOT_SHOT_SECS:-1}
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution 1280x720 --script tools/screenshot_workbench.gd
