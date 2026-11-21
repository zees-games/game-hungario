#!/usr/bin/env bash
# The solo-client benchmark (tools/perf_bench.tscn) windowed on a GPU box: dot-game's tool (addons/dot_game/tools/dot_game_perf_bench.sh).
export GPU_XORG=${GPU_XORG:-1}
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_perf_bench.sh" "$@"
