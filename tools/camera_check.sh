#!/usr/bin/env bash
# The framing camera flown round the real offline game's arena (armed), the spectator view, and the zoom limits.
set -euo pipefail
cd "$(dirname "$0")/.."
exec timeout 300 "${GODOT:-godot}" --headless --path . res://tools/camera_check.tscn
