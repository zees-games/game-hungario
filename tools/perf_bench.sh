#!/usr/bin/env bash
# The solo-client benchmark (tools/perf_bench.tscn) windowed on a GPU box: gs-game's tool (addons/gs_game/tools/gs_game_perf_bench.sh).
export GPU_XORG=${GPU_XORG:-1}
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_perf_bench.sh" "$@"
