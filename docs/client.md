# The client: rider, sound, settings, presentation and screens

## The rider comes from the cloud, and from the build when it does not

`DotAvatarBuilder.plan` works out which part goes in which slot, in what order and colour, and what fell back — pure logic over ids, the same on a headless server as in a browser. `DotAvatarBuilder.apply` builds a `Node3D` rig, so a 2D game cannot use it: `HungryRider` uses the plan and does its own attaching.

`HungryContentSource` is `DotAvatarCatalogue.resolver`, and the order is the design:

```
1. a mounted dot-cloud pack   <- signed, hash-verified, version-namespaced
2. res://content/avatars/     <- what shipped in the build
3. ""                         <- drawn by HungryRider instead
```

That makes downloadable cosmetics an **upgrade rather than a requirement**. A player you cannot see is a competitive advantage, so step 3 is not optional.

**The pack is data; the code that draws it ships in the build.** A `.tscn` names its script by an absolute `res://` path and a pack's path carries its version (`res://dot_cloud/hungry_avatars/1.0.0/`), so a scene in a pack cannot reference a script in the same pack without being re-authored per version. The parts are scenes with exported properties and `part.gd` stays in the build, so a pack published against a newer game degrades (an unknown `shape` falls through to the default) rather than breaks. The contract is a `Node2D` that answers `hungry_dress`.

**Signing is still required**: the manifest is the trust boundary (its hashes decide what is a valid download, its paths what is mounted), and a Godot pack *can* contain scripts.

The server names the pack in the hello (`hungry_avatar_pack`), so one client build works against a server with cosmetics and one with none. Nothing waits for it; the drawn rider stands in until the parts land. A part's `z_index` must place it over the disc it rides, not relative to a renderer on another canvas; `content` asserts the order. `examples/content.tscn` runs publish, sign, fetch, verify, mount, dress, and four refusals (a tampered manifest, a valid signature from the wrong key, an unsigned pack, a version that climbs out of the mount). `tools/publish_avatars.tscn` publishes the pack.

## Sound is arithmetic

`HungrySound` bakes fifteen voices at startup (`HungrySound.Cue`, new cues appended so every cue keeps its number): a sine sweep with a hash-derived noise component under an attack-decay envelope. It ships no audio files. The noise comes from `Dot2DScatter._hash` rather than `randf()`, so the bank is byte-identical everywhere and `headless_round` can assert a voice is the right length, not silence, and ends at zero rather than clicking. (dot-audio's `DotAudioSynth` was extracted from this.)

**Eating is watched, not listened for.** `HungryWorld.food_eaten` fires on the authority, which on a netted client is somewhere else: a client that hooked it would be silent online and noisy offline. `HungryClient._watch_mass` turns the change in the player's own mass into a blip, and plays split and eject only after the player pressed the key (a netted split's new piece arrives before its parent's halving, which otherwise reads as eating).

**Under the `Dummy` audio driver `HungrySound.play` does not start the voice.** Every headless run gets that driver, which never mixes or retires a started playback, so the playbacks leaked at exit. The voice is still chosen and loaded, so the round-robin is unchanged.

## Settings are a `DotConfig`

`HungryConfig` is a set of `@export`s. `DotSettingsPanel` reads the annotations (type, range, group, hint) and builds the editors, so adding a setting adds a row and the screen cannot drift from the settings.

- **Applied, then announced.** The panel holds edits until Apply because a config is legitimately invalid on its way to valid, and `validate()` runs on the whole thing. `DotSettingsScreen.applied` fires only after `apply()` succeeded.
- **Pushed, not polled.** The camera, sound and renderer hold the value they were given; no dictionary lookups in the draw path.
- A missing settings file is a first run. A malformed one falls back to defaults with a warning rather than refusing to start.

## The presentation layer, and what it deliberately does not duplicate

`HungryPresentation` holds dot-settings, dot-audio, dot-fx and dot-console, and the point is what it **refuses to replace**. Two copies of one list is this family's most repeated bug ([detectors.md](../../../docs/detectors.md#two-copies-of-one-list)).

- **dot-audio does not replace `HungrySound`.** `HungrySoundSink` is dot-audio's sink and the generation stays; the addon adds the catalogue, concurrency caps, cooldowns, distance cull, priorities, a `linear_to_db` curve and a reason for every refusal. `DotAudioDef.generated` exists because of this game.
- **dot-settings does not replace `HungryConfig`.** `DotSettingsSchema.from_config` reads it, so ranges come from the `@export_range` hints and the only addition is **scope** (which keys follow a person between games). `apply_to_config` is the way back.
- **`apply_all()` runs once after the layer is built.** Everything reacts to `changed`, and a value loaded from disk has not changed, so without it a saved volume never reached the bank.

**Effects** are dot-fx: `fx_catalogue()` names `eat_pop` and `burst` under `scenes/fx/`, script-free `CPUParticles2D` scenes at `z_index` 5 over the renderer's -1. `FX_DIR` goes through `HungryPaths.rebase` so a delivered pack finds them; `_build_fx` warns when a scene is missing (dot-fx refuses a missing scene only at DEBUG). `headless_presentation` asserts `missing_scenes()` is empty and that each effect puts particles where it happened.

## Screens

Five screens on the stack: pause, settings, controls, scoreboard, loadout.

- **Pause and settings are dot-ui's** (`DotPauseScreen`, `DotSettingsScreen`). What is this game's is `HungryMenus.PAUSE_BUTTONS` and what a press does; ids are derived from labels, and for the buttons that open a screen **the button id IS the screen id**, so `install` looks it up rather than keeping a second table. The settings screen scrolls: a `DotSettingsPanel` is as tall as its document, and without a `ScrollContainer` Apply, Revert and Back fall off the window, which only a picture shows.
- **Controls, scoreboard and loadout are this game's own**, deliberately: a key map, a scoreboard and a loadout schema are things dot-ui has no opinion about.
- **The scoreboard draws dot-menu's `DotMenuScoreboard`**: every monster, bots included, in the world's rank order, with the server's roster merged in by id for people (time on, ping). Tab is held. Sort by the world's rank, not by mass then name, or a draw reads 2, 3, 1.
- **The rest of dot-menu is not used** — not converted, on purpose for now: dot-menu's menu is a view of dot-settings and this game's settings are a `DotConfig`, so moving would change how settings are stored, not just the screens.
- **The rank column width is `0.4`.** An omitted width is an equal share, so a one-digit `#` would otherwise take as much room as the mass.

## Chat box

There is no chat screen; `HungryPresentation` builds dot-ui's `DotChatWindow`. When it opens (`opened`, however it was opened) it releases the voice gate (or the talk key's key-up lands in the box and the player broadcasts while typing) and sets `HungryInput.suspended` (split, throw, boost and eject are keys, and "gg boost" would split twice).

The console is dot-console's `DotConsoleKit` (plus `quit` and `audio`, ahead of the server's console). The kit registers its panel with a `DotMenu`, which this game does not have, so `HungryClient._wire_console` suspends `HungryInput` on the console's `visibility_changed`, through the same `_refresh_suspended` as the chat box; `headless_presentation` holds the keys down to prove it.

**The three chat settings are added beside the config, not read out of it** — the one deliberate departure from `from_config`. A `DotConfig` is layered from JSON, environment and argv, and a key binding has no business arriving from a server's argv (`HUNGRY_CHAT_OPEN_KEY=Q` in a container would rebind every player). `headless_presentation` asserts the key is not a config value.

| | |
| --- | --- |
| `chat_window` | `auto` / `on` / `off`. `auto` hides the box on a server already carrying chat somewhere the player can see it. |
| `chat_open_key` | `Y` by default. |
| `chat_near_key` | `U` by default; opens the proximity channel. |

## Rendering

`HungryRenderer._view` computes the visible rectangle as the viewport **divided** by the zoom: `Camera2D.zoom` is a magnification. Multiplying culls most of the screen once the player has grown, on a black background that reads as an empty arena.

**The look is a bright pastel sky**, the family's sunny look (game-arena's built-in maps) in 2D: a pale sky-blue floor one clear step lighter than a periwinkle void, a faint blue grid, a periwinkle wall, lavender rocks rimmed darker, and soft clouds parallaxed under everything (`_draw_clouds`, hashed per cell the way `DotStarfield` is, opaque and drawn only where a whole cloud fits in the arena, because translucent discs showed every overlap as a seam). It was deep space (near-black floor, starfield, nebulae), which read dark and heavy beside every other game. Food, fruit, items and monsters are the saturated things on screen; the food tiers and the prey and threat rings were made deeper so they stand off the pale floor, and names are dark with a white lift (white names vanished). The palette is the renderer's colour fields; the menus' starfield backdrop is not part of it. 2D draws the same under both renderers.
