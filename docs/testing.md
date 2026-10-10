# The suites, and what each one can see

`./game.sh test` parses every script and runs all seven suites with a timeout and the stderr check; `./game.sh test NAME` runs one. Every suite counts sections entered against sections that ran to their last line **and** has a `CHECKS` total; why both is in the family's [testing.md](../../../docs/testing.md#two-guards-every-suite-written-since-has-and-why-the-first-one-is-not-enough). Anything that returns early from a section has to call `_done()` first. Add `-- --verbose` to `dedicated`, `sandbox` or `content` when the reason is in a log line rather than an assertion.

| Suite | What it is for |
| --- | --- |
| `headless_round` | The game, offline: the motor, the field, eating, splitting and merging, every mode and level section, the reach sweeps, bots' travel, hunters on the navigation, the sound bank, the screens. **Run it after any change to dot-2d.** |
| `headless_stack` | `HungryPlayerStack` against a real 2D arena: the roster, the traits, the collision layout, the spawns. |
| `headless_net` | The netcode over a loopback: two worlds replaying the same commands are bit-identical, a client and server stay within a few units under 25% packet loss, prediction against a rock, the admin flags' audiences. **Run it after any change to dot-net.** |
| `dedicated` | A real `DotServer`: the console, the vote, achievements against declared stats, hunters hunting, `changelevel`, and *exiting clean* (no message script preloads itself; the suite re-run in a second process exits with no leak). |
| `sandbox` | Two real clients over a real socket. |
| `content` | The cloud path for the rider: publish, sign, fetch, verify, mount, dress, and four refusals. |
| `headless_presentation` | The client half: settings, audio catalogue, effects, the chat box, the blind overlay, the party over a real HTTP rendezvous, and its own exit probe. |

## `sandbox` is the one that matters most

It is the only place the RPC node paths, dot-platform's admission, chat, and a game change with a player attached all run at once, and several bugs here were found by it alone. It runs **two** clients, each in its own subtree with its own `MultiplayerAPI`, because everything that decides what one player is told about another (interest, the roster, the join broadcast, spawn events) is per observer and trivially correct with one. Its game change goes to the reef and asserts a connected client builds every rock from the name in the hello.

## Traps the suites have hit

- **Settle with the player already in.** dot-match waits in warmup until somebody joins and the first tick after a join resets and respawns everybody. A section (or a tool) that ticks to live and then adds its player is measuring wherever the reset put it. [levels.md](levels.md#how-the-suites-measure-a-level) has the level-section rules.
- **Do not build the world in `SceneTree._initialize`.** `HungryWorld.setup()` adds its `DotMatch` as a child, and a node added there has no `_ready` until the first frame: no scoreboard, and `add_player` dies on a `Nil` with "Nonexistent function 'join' in base 'Nil'", which reads like a missing method. Both screenshot tools seed on the first frame (`_boot()`).
- **A suite that writes to `user://` depends on the last run.** `dedicated`'s achievements use a player key unique per run (a fixed key failed on the ninth run); see the family [testing.md](../../../docs/testing.md#a-suite-that-writes-to-user-is-a-suite-whose-result-depends-on-the-last-run). Never clear the directory instead: that is a suite deleting a player's progress.
- **Time a chase from when it starts.** How long a hunter wanders before its senses settle depends on the instance id, which differs between processes. `dedicated`'s *hunters hunt* times from the tick the brain enters `chase`.
- **`godot --check-only --script res://game/hungry_party.gd` prints 11 ObjectDB instances and 6 resources.** It is not a leak in any script here: it is the Godot 4.7.2 exit-walk bug reached by load order in a parse-only process (bisected to `var _h: DotHttp`, a method typed `-> DotP2PSignaller`, and a `DotP2PSignallerLoopback.new(...)` in one script). game-playground's `playground_party.gd` prints the same. Nothing to change until the engine moves past 4.7.2. Running scenes exit clean.

## Pictures

Every check asserts a simulated value, so placement, scale and drawing are only checked by looking. `tools/screenshot_map.sh` renders the modes ([levels.md](levels.md#looking-at-a-level)); `tools/screenshot_menus.sh` renders the pause menu, loadout picker, scoreboard, rebinder and settings screen. A column width, a missing scroll container, a rider under its disc and a renderer culling most of the screen were all found by a frame and by nothing else.
