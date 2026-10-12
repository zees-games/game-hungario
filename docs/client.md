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

## Settings are dot-menu's document

`HungrySettings` is dot-menu's `DotMenuSettings`, as in every game of the family: one dot-settings document (`user://hungry_settings`, namespace `game_hungario`, the account keys under `tmc_account`), dot-menu's applier for the stock keys, and the Escape menu over it.

- **This game's own keys are still declared by `HungryConfig`** (`@export`s for the camera and the interface) and read out of it with `DotSettingsSchema.from_config`, so a range tightened there tightens the slider and the console at once. The presentation layer writes each change back into the config, and `HungryClient._apply_settings` pushes it at the camera, renderer and HUD. The config is never saved itself.
- **The volume is the stock audio page** (`master_volume`, `sfx_volume`, `ui_volume`), set on dot-audio's mixer by the applier. The bank's own level stays at `HungrySound`'s default. The old `volume_db` was applied twice (each voice and the Master bus), so this game's master starts at 0.4, about the old loudness, not the family's 0.8.
- **Stock keys nothing here applies are left out** (`HungrySettings.NOT_APPLIED`): render scale and field of view (2D), and sensitivity and invert (the mouse is a pointer). The voice mode, microphone and voice volume are on the Audio page: `HungryVoice` publishes its manager as `dot_voice_client`, so dot-menu's applier binds them and dot-chat's `sm` list mutes a player's voice, not only their lines (`sandbox` checks both, armed). The talk key is a table row.
- **Pushed, not polled.** The camera, sound and renderer hold the value they were given; no dictionary lookups in the draw path.

### The migration from dot-ui's files

Until 2026-10-12 the settings screen saved `HungryConfig` to `user://cfg/hungry.json` and the Controls screen saved the `hungry_*` actions to `user://cfg/bindings.json`, beside the document (which already held net_stat, the chat keys and anything set at the console). `HungrySettings.setup` brings a version-1 document (or none) to version 2 once, before dot-menu loads it:

- **The document wins over the files**, because that is what the old client showed: it loaded `hungry.json` and laid the document over it.
- The camera and interface keys come over by name. The volume becomes `master_volume` at the loudness it had (`2 * volume_db + 8` dB, capped at full; muted is 0).
- Split and throw were a key and a mouse button on one action; each becomes its own row (`bind_split` and `bind_split_click`), because a table row puts one input on its action.
- The document is saved at version 2, so a player who later changes a value back is never overruled by the old file. The files are read, never written or deleted. A first run with nothing to bring writes nothing.

`headless_presentation`'s migration section covers all four.

## The presentation layer, and what it deliberately does not duplicate

`HungryPresentation` holds dot-settings, dot-audio, dot-fx and dot-console, and the point is what it **refuses to replace**. Two copies of one list is this family's most repeated bug ([detectors.md](../../../docs/detectors.md#two-copies-of-one-list)).

- **dot-audio does not replace `HungrySound`.** `HungrySoundSink` is dot-audio's sink and the generation stays; the addon adds the catalogue, concurrency caps, cooldowns, distance cull, priorities, a `linear_to_db` curve and a reason for every refusal. `DotAudioDef.generated` exists because of this game.
- **dot-settings does not replace `HungryConfig`.** `DotSettingsSchema.from_config` reads it, so ranges come from the `@export_range` hints and the only addition is **scope** (which keys follow a person between games). `apply_to_config` is the way back.
- **`apply_all()` runs once after the layer is built**, this game's keys and then the applier's. Everything reacts to `changed`, and a value loaded from disk has not changed, so without it a saved value never reached what reads it.

**Effects** are dot-fx: `fx_catalogue()` names `eat_pop` and `burst` under `scenes/fx/`, script-free `CPUParticles2D` scenes at `z_index` 5 over the renderer's -1. `FX_DIR` goes through `HungryPaths.rebase` so a delivered pack finds them; `_build_fx` warns when a scene is missing (dot-fx refuses a missing scene only at DEBUG). `headless_presentation` asserts `missing_scenes()` is empty and that each effect puts particles where it happened.

## Screens

**Escape is dot-menu's menu**, the same structure as every other game: Resume, the pages (Loadout, General, Game, Video, Audio, Controls, Advanced), Help & commands and Leave. H opens the help screen (the goal, the rules, and every key as bound now), and the "H Help" plate is in the top-left corner, with the feed moved under it. The only thing left on dot-ui's screen stack is the held Tab scoreboard.

- **Loadout is the first page** (`HungryMenus.LoadoutPage`), live rows rather than settings: a loadout is the server's to accept, so each choice is sent as it is made and takes effect at the next spawn. It offers what `DotLoadoutSchema.choices_for` allows this player and nothing else. Its rows' callables capture a dictionary, never the page object: a row holding a callable bound to the object that holds the row is a cycle of RefCounteds, and the whole page leaked at exit (`sandbox`, 8 resources) until it did not.
- **Game is this game's page** (`HungrySettings.game_page`): camera lag, zoom, threat rings, names, the minimap, message lines.
- **The keys are `HungryBindings`' table**: split, eject, throw, boost, a mouse-button row each for split and throw, chat and nearby chat (still stored as `chat_open_key`/`chat_near_key`, ACCOUNT, so nobody's chat key reset), push to talk, the scoreboard, and dot-menu's help. Nothing may default to H or M; `headless_presentation` checks it.
- **No M yet**: `map_menu` is off until the modes are handed to dot-menu (`use_maps`), queue item `fpt-family-map-menu-1`.
- **Leave is stock**: off the server when connected, "Quit game" solo on a desktop, hidden solo in a browser.
- **The scoreboard draws dot-menu's `DotMenuScoreboard`**: every monster, bots included, in the world's rank order, with the server's roster merged in by id for people (time on, ping). Tab is held (`hungry_scoreboard`, a table row). Sort by the world's rank, not by mass then name, or a draw reads 2, 3, 1.
- **The rank column width is `0.4`.** An omitted width is an equal share, so a one-digit `#` would otherwise take as much room as the mass.

## Chat box

There is no chat screen; `HungryPresentation` builds dot-ui's `DotChatWindow`. When it opens (`opened`, however it was opened) it releases the voice gate (or the talk key's key-up lands in the box and the player broadcasts while typing) and sets `HungryInput.suspended` (split, throw, boost and eject are keys, and "gg boost" would split twice).

**Every chat line goes to the box, and to the HUD feed only when there is no box.** Both drew every line, so a vote's ballot was printed in two corners and the feed's copy ran under the vote countdown at the top. The box is lifted 84 px (`margin_bottom`) to clear the mass bar and the carry line; at the stock 16 the newest lines were drawn over the bar.

The console is dot-console's `DotConsoleKit` (plus `quit` and `audio`, ahead of the server's console), registered as one of the Escape menu's overlays. `HungryClient._wire_console` suspends `HungryInput` on the console's `visibility_changed`, through the same `_refresh_suspended` as the chat box and the menu; `headless_presentation` holds the keys down to prove it. The menu's `busy` is the presentation's `swallows_input`, so Escape and H are the chat line's and the console's while they have the keyboard.

**The chat settings are not config values.** `chat_window` is dot-menu's stock setting and the two keys are rows of the key table. A `DotConfig` is layered from JSON, environment and argv, and a key binding has no business arriving from a server's argv (`HUNGRY_CHAT_OPEN_KEY=Q` in a container would rebind every player). `headless_presentation` asserts the key is not a config value.

| | |
| --- | --- |
| `chat_window` | `auto` / `on` / `off`. `auto` hides the box on a server already carrying chat somewhere the player can see it. |
| `chat_open_key` | `Y` by default. |
| `chat_near_key` | `U` by default; opens the proximity channel. |

## The leaderboard makes room for a ballot

The client shell draws every ballot (the server's game vote and this game's mode vote) as a `DotBallotPanel` in a column down the right-hand side from about 110 px down, over whatever the game drew. The board's corner is 16 to 280 px down, so rows 3 to 10 sat under the panel, unread, for the whole vote. The shell cannot reach into a delivered game, so the game looks: `HungryHud.make_room()` runs every frame, reads every visible Control in dot-ui's `dot_hud_cover` group (through `DotHudPiece.covered_rect`, dot-ui's reading of the group since API level 4, which this HUD had done by hand), converts their rects into the HUD's own space (the HUD is inset by the safe area and scaled), and when one overlaps the board's corner the board keeps the corner but shrinks to the rows that fit above it, without its header: the leader first, and this player's own row last, with their real rank, when they are not in the top few. Two rows at 1280 x 720 under the stand-in, three under the real shell. No room for one row hides it. It gets its corner, header and ten rows back the frame the panel goes.

- **Not moved left of the column**: beside a 360 px column it runs into the round clock at the top centre.
- **Not faded out**: who is winning is what a player is deciding a mode vote with.
- **Looked at with** `tools/screenshot_map.sh <mode> --ballot`, which draws a stand-in panel where the shell does; `headless_presentation` checks the arithmetic and the player's row.

## The round clock

The clock is a `DotScoreStrip` with no scores (this is a free-for-all and the standings are the leaderboard): the time on the menu theme's plate (dark by default), top centre, red in the last ten seconds, and the match's state as the line under it while there is no time to count. It was a centred `Label` writing `"%d:%02d"` with the floor, so a round with half a second left said 0:00; the strip rounds up. The plate, the words and the outline (`ink`) are the theme the player picked in the menu, which the menu sets on the whole HUD (dot-menu's `follow_hud`, with `HungryHud.accent_theme()` laid over it: this game's gold and the Labels' outline width), so every Label here is outlined in the same ink and a theme change restyles the HUD live. Until the first play test (2026-10-11) it was a fixed navy plate with a navy outline; a HUD built with no menu still draws that outline (`hud_theme()`). The mode-vote countdown sits under the plate (`HungryHud.VOTE_TOP`). Look at it with `tools/screenshot_map.sh classic --ballot` (the `vote` and `ballot` frames).

## Rendering

`HungryRenderer._view` computes the visible rectangle as the viewport **divided** by the zoom: `Camera2D.zoom` is a magnification. Multiplying culls most of the screen once the player has grown, on a black background that reads as an empty arena.

**The look is a bright pastel sky**, the family's sunny look (game-arena's built-in maps) in 2D: a pale sky-blue floor one clear step lighter than a periwinkle void, a faint blue grid, a periwinkle wall, lavender rocks rimmed darker, and soft clouds parallaxed under everything (`_draw_clouds`, hashed per cell the way `DotStarfield` is, opaque and drawn only where a whole cloud fits in the arena, because translucent discs showed every overlap as a seam). It was deep space (near-black floor, starfield, nebulae), which read dark and heavy beside every other game. Food, fruit, items and monsters are the saturated things on screen; the food tiers and the prey and threat rings were made deeper so they stand off the pale floor, and names are dark with a white lift (white names vanished). HUD text is light with a dark outline (`HungryHud.TEXT_OUTLINE`, through the HUD's theme for every Label and `outline_size` for the feed), because plain white HUD text vanished the same way; the mass number is a Label over the bar rather than `DotStatBar`'s own text, which has no outline. The palette is the renderer's colour fields; the menus' starfield backdrop is not part of it. 2D draws the same under both renderers.

**A monster this machine simulates is drawn between its ticks** (2026-10-11): your own, and offline every bot too (`HungryRenderer.all_simulated_here`). `HungryWorld` records where each piece started its last two ticks (`HungryPiece.drawn_from`, `drawn_two_back`; in `simulate_piece` for a client's prediction and replays, in `_simulate_monsters` for the authority), and the renderer, the rider, the name and the threat ring draw `HungryPiece.drawn_position(alpha)`; the camera follows `HungryMonster.drawn_centre`. Drawn where the tick left it, a monster stood still on more than half the frames at 144 Hz against 60 ticks and jumped on the rest. Connected, the alpha is dot-net's `DotNetClock.render_alpha` (`render_clock` on the renderer and the camera, by name): the clock stretches its ticks while it settles on the server, so a physics frame now and then runs no tick or two, and at the engine's fraction alone that frame stalls or doubles. `headless_net`'s *drawn through a frame with no tick, or two* forces one of each beside that control. A remote monster is still where dot-net's interpolator put it this frame. A tick that moves a piece more than twice its radius is drawn as the jump it is.
