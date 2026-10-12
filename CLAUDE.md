# game-hungario

A 2D grow-by-eating arena game in the cell-eating genre: the thing you steer is a monster that splits into pieces, and the thing riding it is your avatar. Six modes, bots, optional hunters and hazards, networked over dot-net and published as a signed dot-cloud pack. It is the family's first game with a client a person can sit down at, and the place the gameplay addons and the identity addons (dot-auth, dot-user, dot-user-avatar, dot-platform) run together.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to this game. **The detail is in [docs/](docs/README.md)**: open the file for what you are touching.

**The identifiers did not follow the rename from `dot-2d-hungry`, on purpose.** The class prefix is `Hungry`, the module is `hungry`, the game ids are `hungry_classic`, `hungry_frenzy` and so on, and the RPC node is named `Hungry`. `content_id` is what a client keys built-in games on, `game_id` is what an operator types, and in Godot a node's name **is** its RPC routing. Renaming any of them breaks a wire contract.

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/gameplay.md](docs/gameplay.md) | the monster, steering, the field, effects, loadout, death, throwables, touch, the party |
| [docs/levels.md](docs/levels.md) | any mode, preset, layout or food target |
| [docs/netcode.md](docs/netcode.md) | `game/net/`, prediction, interest, bots, admin modifiers, game change, messages |
| [docs/npc-and-hazards.md](docs/npc-and-hazards.md) | hunters, their navigation and spawn points, the director, hazards |
| [docs/services.md](docs/services.md) | chat, voice, moderation, stats, the vote, the browser, the backbone |
| [docs/client.md](docs/client.md) | the rider, sound, settings, presentation, effects, screens, chat box, renderer |
| [docs/testing.md](docs/testing.md) | adding a check, or believing a green run |
| [docs/history.md](docs/history.md) | a bug that "cannot be happening"; what this game found and how it looked |

## Layout

| Path | What |
| --- | --- |
| `game/hungry_world.gd`, `hungry_monster.gd`, `hungry_piece.gd`, `hungry_field.gd` | the simulation: world tick, the monster as a set of pieces, the food field |
| `game/hungry_layout.gd`, `hungry_preset.gd`, `game/modes/` | level geometry, per-mode tuning, and the six mode scenes (`HungryMode`) |
| `game/hungry_module.gd`, `hungry_services.gd`, `hungry_mod_tools.gd`, `hungry_maps.gd` | the server: dot-server module, chat/voice/moderation, admin tools, the vote |
| `game/hungry_hunters.gd`, `hungry_hunter_brain.gd`, `hungry_hazards.gd`, `hungry_combat.gd` | NPCs, hazards, throwable damage |
| `game/hungry_content.gd`, `hungry_config.gd`, `hungry_paths.gd` | items and loadout schema, client config, pack-safe paths |
| `game/net/` | the dot-net bridge, piece and match entities, interest, events and requests |
| `game/client/` | client scene, camera, renderer, HUD, input, touch, menus, sound, rider, browser, presentation |
| `examples/` | the seven test suites, `play.tscn` (the standalone application) |
| `tools/` | `screenshot_map.sh`, `screenshot_menus.sh`, `publish_avatars.tscn` |
| `content/avatars/`, `scenes/fx/` | built-in rider parts, effect scenes |
| `game.yml` | the descriptor that travels inside the published pack (Classic); the other modes' descriptors are in dot-server-deploy's `content/hungry_*` |

## Running and testing

- `./game.sh` plays offline; `./game.sh online` runs a local server plus the browser client; `./game.sh test` parses everything and runs all seven suites. `./game.sh help` lists the rest.
- `godot --path . -- --offline | --connect HOST:PORT | --touch` for the standalone client.
- An empty server keeps six players in the arena with bots (dot-server's `DotBotQuota`, `bot_quota` in fill mode); each person who joins takes a bot's place. `bot_quota_mode fixed` keeps that many bots beside everybody; `hungry_bots N` is a deprecated alias for it.
- **Run `headless_round` after any change to dot-2d, and `headless_net` after any change to dot-net.** They are the only places that see replay determinism and client/server agreement under loss.
- **`sandbox` is the suite that matters most**: two real clients on a real socket. See [docs/testing.md](docs/testing.md).
- **Look at it.** No check reaches placement, scale or drawing: `tools/screenshot_map.sh <mode>` for levels (`--ballot` for the HUD under a ballot), `tools/screenshot_menus.sh` for screens ([docs/levels.md](docs/levels.md#looking-at-a-level)).
- `docs/` and the `.md` files are never loaded. A Godot export leaves them out (`all_resources`, `exclude_filter` `web/*, tools/*`), but dot-ci's `package.sh --pack` zip is the tracked tree minus addons, examples, tools, screenshots and images, so it carries them as inert text.

## Rules that bite

Short forms; the reasoning is in the linked file.

**Simulation**

- Every piece steers toward the pointer's **world point** (`HungryWorld.pointer_of`), never along one shared direction, or split pieces can never merge. [gameplay](docs/gameplay.md#a-player-is-a-set-and-the-pointer-is-a-point)
- The arena size is part of every food position: `adopt_world_size` before `adopt_field_seed`. Slot indexes are never reused. [gameplay](docs/gameplay.md#four-fields-one-id-space-and-only-membership-travels)
- Anything that changes speed must be readable on both ends: effects travel as piece flags, the trait in the join. [gameplay](docs/gameplay.md#effects-are-replicated-as-flags)
- Eating is not dot-combat; throwables are, through `HungryCombat`, and `damage_gate` stays optional. [gameplay](docs/gameplay.md#throwables-are-dot-combat-eating-is-not)
- Loadouts: entitlements default to nothing; refuse an illegal loadout on the way in; takes effect next spawn. [gameplay](docs/gameplay.md#what-a-player-brings-in)
- A hunter brain seeds from `npc.seed` (per spawn), never `npc.instance_id` (an identity whose value moves with every allocation). dot-npc `docs/runtime.md`

**Levels**

- Geometry is derived from the layout id on both ends; never replicate it. Append new blocks; never reorder. [levels](docs/levels.md#the-rules-every-layout-follows)
- `block_piece` stays inside `simulate_piece` (the replay path). [levels](docs/levels.md#the-rules-every-layout-follows)
- A food target is the density times the floor left; the cull is not a loss. [levels](docs/levels.md#the-rules-every-layout-follows)
- Ask `narrowest_gate(bounds)`, not `narrowest_gap`; iterate `HungryLayout.ids()`. [levels](docs/levels.md#the-rules-every-layout-follows)
- A level is checked by **driving** monsters through it, with the player added before settling and steered with `aim`/`reach`. [levels](docs/levels.md#how-the-suites-measure-a-level)
- Refuges: two doors or more, a room bigger than its doors, hunters refused in `spawnable`. Outgrowing one is `hungry_outgrown` (default accept). [levels](docs/levels.md#the-rules-every-layout-follows)
- The gauntlet, warrens and reef have been measured full; growing them means moving existing geometry, which is a design decision. [levels](docs/levels.md#reef-barriers-whose-channels-differ)

**Netcode**

- The first `_net_simulate` on a tick runs the whole world (`ensure_world_ticked`). [netcode](docs/netcode.md#ordering-the-first-behaviour-through-drives-the-world)
- Nothing is sent before `Ask.READY`; greet players from `peer_admitted`, not `client_spawn`; `_broadcast` goes peer by peer. [netcode](docs/netcode.md#nothing-is-sent-to-a-peer-before-it-asks)
- Bots are peer 0: never `add_peer(0)`, never `send(msg, 0)`. [netcode](docs/netcode.md#a-bot-has-no-peer-and-peer-0-is-not-everybody)
- Prediction replays the motor only; `receive_snapshot` must not reconcile; `_net_state_applied` skips predicted entities; `RECONCILE_EPSILON` on every `DotNetConfig`. [netcode](docs/netcode.md#prediction-is-the-motor-and-deliberately-not-the-set)
- Anything that changes how a monster moves goes through replicated admin state, or the owner rubber-bands. [netcode](docs/netcode.md#admin-state-goes-through-what-the-client-predicts)
- The manager, bridge and loadout manager outlive a game change; the world does not. `rebind`, never rebuild. [netcode](docs/netcode.md#game-switching-the-world-is-the-scene-the-manager-is-not)
- Paths to this game's own files go through `HungryPaths.rebase` (pack delivery). No message script preloads itself. New event kinds and sound cues are appended. [netcode](docs/netcode.md#messages)

**Hunters**

- Off by default (`hungry_hunters_on`). Not dot-net entities. A 2D world is dot-npc's XZ plane. [npc](docs/npc-and-hazards.md#hunters-dot-npc-dot-npc-ai-and-the-director)
- Navigation units are world units, not dot-npc's metres; the brain reads its link on first use. [npc](docs/npc-and-hazards.md#navigation)
- **Open design question:** every hunter fits through every refuge door (hunters are on a different size curve). Not decided. [npc](docs/npc-and-hazards.md#a-hunters-size-and-the-open-question)

**Services and client**

- One chat path: dot-server's chat is cancelled in `hook_pre`. The chat key is the player id, not the uid. [services](docs/services.md#chat)
- Voice is proximity, with the interest range. [services](docs/services.md#voice)
- Stats have one source: `DotStatsSchema`; every achievement stat must be declared. Boards are per mode. [services](docs/services.md#stats-boards-and-achievements)
- The vote's director is advanced once a tick by the module; the swap is dot-server's `change_game`, not `DotMapSyncHost`. [services](docs/services.md#the-vote-and-dot-map)
- The vote knows a mode by its game id (`HungryModule.game_id_of`), never the preset id, and its source is narrowed to the modes (`HungryMaps.ModeSource`): a server runs other games too. [services](docs/services.md#the-vote-and-dot-map)
- Chat lines go to the chat box, and to the feed only when there is no box; the box sits above the mass bar.
- The leaderboard shrinks above any visible `dot_hud_cover` Control over its corner (the shell's ballots), read through `DotHudPiece.covered_rect`. [client](docs/client.md#the-leaderboard-makes-room-for-a-ballot) [client](docs/client.md#chat-box)
- dot-audio does not replace `HungrySound` and dot-settings does not replace `HungryConfig`; `apply_all()` after building the layer. [client](docs/client.md#the-presentation-layer-and-what-it-deliberately-does-not-duplicate)
- Chat key settings sit beside the config, never in it (argv must not rebind players). [client](docs/client.md#chat-box)
- Do not build the world in `SceneTree._initialize`; tools seed on the first frame. [testing](docs/testing.md#traps-the-suites-have-hit)
- The round clock is dot-ui's `DotScoreStrip` (`HungryHud.strip`, colours from `HungryHud.piece_theme()`), so the pack needs a client shell with dot-ui API level 4; `headless_presentation` checks the derived requires.json and that the clock, the ballot and the full chat log do not meet. [client](docs/client.md#the-round-clock)
- The arena is a pale pastel sky (`HungryRenderer`'s colour fields, opaque clouds); anything drawn on it is saturated or dark, never white. [client](docs/client.md#rendering)
- `project.godot` carries no comments: the editor drops them, and any key left at its default, the first time it saves the file, so the reasons for its settings live here. The renderer is `gl_compatibility`, not Forward+, because Forward+ does not run in a browser and the point of this game is that a stranger can click a link and play it. Texture imports keep `detect_3d/compress_to=0` (`[importer_defaults]`) so the editor never re-imports one VRAM-compressed on a first open.

## Not converted yet

- **dot-game**: the module extends `DotModule` and `HungryServices` is its own, not `DotGameModule`/`DotGameServices`. Not yet converted; dot-game's CLAUDE.md says to convert game-arena first.
- **dot-menu**: only the Tab scoreboard uses it. The settings, pause, controls and loadout screens stay because this game's settings are a `DotConfig` and dot-menu's menu is a view of dot-settings; moving them changes how settings are stored. Deliberate for now. [client](docs/client.md#screens)
