#!/usr/bin/env bash
# Renders the F9 tuning panel to screenshots/workbench_panel.png, to look at.
#
#   tools/screenshot_workbench.sh
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution 1280x720 --script tools/screenshot_workbench.gd
