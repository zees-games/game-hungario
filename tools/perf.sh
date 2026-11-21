#!/usr/bin/env bash
# The Nightly Performance tab's contract for this game: tools/perf.sh --platform native|web --role client|server [--bots N] [--map M]
# [--duration S] [--out report.json]; one perf report v1 out. See addons/gs_game/tools/gs_game_perf.sh for the modes and exit codes.
export PERF_GAME=hungario
export PERF_SERVER_SCENE=res://tools/soak.tscn
export PERF_SERVER_BOTS_ARG='--bots %d'
export PERF_SERVER_MAP_ARG='--map %s'
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_perf.sh" "$@"
