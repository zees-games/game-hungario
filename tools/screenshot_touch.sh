#!/usr/bin/env bash
# The offline client with the touch layout on an 844x390 phone window: tools/screenshot_touch.sh [WxH]
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a godot --path . --resolution "${1:-844x390}" --script tools/screenshot_touch.gd -- --offline --touch
