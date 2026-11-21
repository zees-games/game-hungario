#!/usr/bin/env bash
# Hungario's on-box visual QA capture: gs-game's shot tool runs tools/visual_qa.gd (gs-game docs/visual-qa.md).
# Normally started by gs-game's driver:
#   bash addons/gs_game/tools/gs_game_visual_qa.sh --shot tools/visual_qa_shot.sh -- [--only rider_guest_odd,hunter_x] [--clips idle,move]
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_visual_qa_shot.sh" --script tools/visual_qa.gd -- "$@"
