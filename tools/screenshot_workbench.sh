#!/usr/bin/env bash
# Renders the F9 tuning panel to screenshots/workbench_panel.png, to look at.
#
#   tools/screenshot_workbench.sh
set -euo pipefail
# A short frame sequence beside each still (GSShotSeq), so Nightly -> Review can play and scrub it.
export GS_SHOT_FRAMES=${GS_SHOT_FRAMES:-8} GS_SHOT_SECS=${GS_SHOT_SECS:-1}
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution 1280x720 --script tools/screenshot_workbench.gd
