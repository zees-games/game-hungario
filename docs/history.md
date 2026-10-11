# History: bugs worth recognising again

Every one of these parsed cleanly and produced no error. Each is kept because the shape could come back; where the lesson is still a rule, the rule is also in [CLAUDE.md](../CLAUDE.md) or a topic file. The family-wide list is [bugs-found.md](../../../docs/bugs-found.md).

## In this game

**Split pieces could never rejoin.** One shared aim direction moved every piece in parallel, so splitting was permanent. A design bug, not a coding one; found by a failing merge check. Rule in [gameplay.md](gameplay.md#a-player-is-a-set-and-the-pointer-is-a-point).

**`reset_world` cleared the piece dictionary instead of destroying the pieces**, so `piece_destroyed` never fired, the netcode entities stayed registered, and clients kept the previous round's pieces on screen for ever.

**The round announced itself before it reset.** Clients got the field about to be thrown away, then the new one as a delta on top of it: twice the food, half of it phantoms.

**A rider part that was its own fallback** made the whole rider schema invalid, unnoticed because no suite validated the schema.

**A bot registered as peer 0**: two failure modes from one line ([netcode.md](netcode.md#a-bot-has-no-peer-and-peer-0-is-not-everybody)).

**A section that aborted took eight checks with it**, and the reported total went *up*, because other sections were added in the same change. That is why every suite has a section counter and a CHECKS total.

**A disconnect never left the netcode.** The disconnect handler took the peer off the ready set, and `remove_peer` was gated on that same set, so the manager kept sending a gone peer snapshots ("Attempt to call RPC with unknown peer ID") for the life of the server.

**Nobody was ever welcomed.** `_welcome` was called from `client_spawn` and returned unless the peer was ready, which at `client_spawn` it never is; with dot-server's join line switched off for dot-chat's, nobody's arrival was announced. It runs from `peer_admitted`.

**Every rider built from content was drawn under its own monster.** A part's `z_index` was relative to a renderer drawing the discs on another canvas. The drawn fallback was fine, so real content was the version nobody could see. Found by a rendered frame.

**Split and eject were silent** although both voices were baked and catalogued, and a netted split played an eating blip. A netted client also heard every throw on the map as its own.

**Every snapshot read as a correction (0.968)** (`[hungario-corrections-1]`, 2026-10-04). `_net_state_applied` moved the owner's node too, so the predictor measured the replay as the correction; dot-net's metre-scale epsilon was a hundredth of a pixel here; and `headless_net` stamped ticks over a clock it never advanced, so its earlier "0.032" had measured nothing. Also found: GDScript evaluates `d[f()] = g()` with `g()` first, so `client_at[_client_step(c)] = centre()` recorded the position before the step. Rules in [netcode.md](netcode.md#prediction-is-the-motor-and-deliberately-not-the-set).

**A saved volume never reached the sound bank.** Everything reacted to `changed`, and a value loaded from disk has not changed. `apply_all()`; the same call went into every other game.

**No mouthful ever popped and no monster ever burst** (until 2026-09-27): `fx_catalogue()` named scenes in a `scenes/fx/` directory that did not exist, dot-fx refuses a missing scene at DEBUG only, and the effects section passed on the shake and the tint, which need no scene.

**The renderer culled most of the screen once a player grew.** `_view` and dot-2d's `Dot2DCameraRig` multiplied the viewport by the zoom; `Camera2D.zoom` is a magnification. On a black background that reads as an empty arena. Every suite passed before and after; the third screenshot framing found it the night it was written.

### The vote

The director was advanced by itself *and* by the module, so every vote clock ran double; there was no `rtv` console command, so the wire was the only way to vote; nothing called `note_score` or `note_round_end`; any player could extend the mode from the wire; and a descriptive `DotMapTimeLimit` kept the old limit after an extend. All found finishing the map-chooser work (2026-09-23/24). Current wiring in [services.md](services.md#the-vote-and-dot-map).

### The levels

#### No level section had ever driven what it arranged

`_settle` ticked until the round was live, and dot-match stays in warmup until somebody joins — so every level section, settling *before* adding its player, arranged a monster, ticked, and the first tick was the reset that respawned it at a safe spawn. Three checks passed only because of that: the reef's tight-channel crossing measured a respawned monster; the warrens' gate check had been rewritten to match the teleport (driven for real, dead on a rock's centre, a monster stays against the face; four degrees off it slides in); and the slalom drove with `command.move`, which the motor ignores, so the monster never moved. The gauntlet's crossing had twenty seconds for 6708 units at 130 a second. Found by the lagoon's drive, whose leader came out of a 2-tick settle 1700 units from where it was put. The screenshot tool had the same trap: its `--at` and default frames were the same picture.

#### The food arithmetic was backwards

The slalom treated the rock cull as a permanent loss and raised its target from 700 to 790; a check written with the same backwards arithmetic (multiplying by the walkable fraction rather than dividing by the walkable area) agreed with it exactly. The corridor ran 27% richer than Frenzy from 2026-09-17, and the reef, which copied it, 4.5% richer than Classic. Warrens alone was right. Found when the lagoon doubled the reef's rock. Rule in [levels.md](levels.md#the-rules-every-layout-follows).

#### The wrong gap question

`narrowest_gap` measured rock against rock, which was the whole question for the warrens. A slalom rock stands off a wall, and asked the old question the slalom answered 646 — the distance between two rocks a thousand apart, which is not a gate and not a number anybody would notice was wrong. Hence `narrowest_gate(bounds)`.

### Hunters

#### No hunter had ever chased anybody

`HungryHunterBrain` read its link to `HungryHunters` from `npc.meta` in `_build`, and dot-npc builds the brain inside the spawn and sets `meta` after it. Every hunter held a null, could not weigh anybody as prey or predator, and wandered for its whole life. `dedicated` counted hunters and never watched one hunt. Found writing the navigation check (2026-09-25). Also: until 2026-10-05 no hunter kind had a character, so the reaction time was zero.

**The director's spawn points were seeded once**, from the world the server booted in, so after a game change hunters appeared on the last map's rings (frenzy's handed to the gauntlet left 12 of 36 outside the corridor) and nothing refused a point behind a fence.

**A lurker was believed to be 480 across**, which is a *monster* of 900 mass on the players' curve. It is 135, which is how the refuge question in [npc-and-hazards.md](npc-and-hazards.md#a-hunters-size-and-the-open-question) came up.

### Exit leaks

`dedicated` and `sandbox` once printed hundreds of ObjectDB instances at exit; the engine's script cache, plus the 4.7.2 self-preload walk, and both exit clean now (`[leak-1]`, closed 2026-09-24). `headless_presentation`'s eight were `HungrySound`'s playbacks, held by the dummy audio driver (`[hungario-pres-leak]`, closed 2026-09-25). The first fix, stopping every voice in `_exit_tree`, came out clean two runs in a row by chance and then leaked four in a row: **run a leak fix several times before believing it.**

## Found here, fixed elsewhere

None of these was reachable from the other project's own suite. Details in [bugs-found.md](../../../docs/bugs-found.md).

- game-arena's bridge reconciled twice (correction rate 0.500 against 0.032).
- `client_spawn` carries `userid`, not `peer_id`; a module looking a session up by `peer_id` adds nobody.
- `Dot2DScatter` could not be mirrored until it gained `adopt`: a receiving peer must take the index it was given.
- dot-server could not serve a game shipped inside its own build: the fallback to the server's absolute scene path was refused by `DotClientLink`.
- `DotCloudClient` never registered itself, so four call sites found null and every one treated that as a legitimate configuration.
- dot-net's cached interest answer dropped what the observer owned, so a client did not receive its own newly spawned entity until the cache expired.
- dot-net never pulled back a predicted entity whose server state stood still (fixed in f99fde3): an empty snapshot body was adopted as "you are right".
- dot-ui's `DotTableView` honoured no column width and a column with no `width` collapsed to nothing: the mass, pieces, rank and ping had never been drawn.
- dot-audio refused a sound with no file, until `DotAudioDef.generated`.

## "Mode vote in 1…" under an open ballot

The countdown's every second lingered 1.5 s so a late tick would not blink it off, which left the last one on screen half a second into the ballot it announced (seen in a game_vote_all frame, 2026-10-11). The last second lingers exactly one (`VOTE_LAST_MSEC`); `headless_presentation` checks it.
