# Gameplay: the monster, the field, and what a player brings

## A player is a set, and the pointer is a point

`HungryMonster` owns an array of `HungryPiece`. Almost every question about a player is a property of the set: mass is the sum, position is the **mass-weighted** centroid, the camera frames the spread, the rider sits on the biggest piece, and you are dead when the last one is eaten.

**Every piece steers toward the cursor's *point*, not along one shared direction.** `Dot2DCommand` carries `aim` (a unit vector) and `reach` (a distance) because a screen position means nothing on a server. A world position is recoverable: the sampler measures the pointer from the centroid, so the server adds the same offset to the same centroid (`HungryWorld.pointer_of`) and every piece computes its own direction to that point.

Steering every piece along one direction makes a split monster a rigid formation: the pieces move in parallel for ever, never come back within merging distance, and merging is unreachable. Nothing errors. Releasing the mouse puts the pointer at your own centroid, so your pieces gather; that is the same rule, not a special case.

The motor ramps the pointer's push from nothing at `dead_reach` (7) to full at `full_speed_reach` (105). A monster's ground speed is `max_speed × speed_scale(mass) × trait and effects`; what it gets is that times the push. `HungryBot` points at what it wants and slows as it arrives, as a person with a mouse does; `headless_round`'s *what a bot actually travels at* asserts bots average at least 0.85 of ground speed.

## Four fields, one id space, and only membership travels

`HungryField` owns four things in one object because the eat check considers all of them on the same tick against one `Dot2DGrid`:

| | |
| --- | --- |
| **food** | Four sizes. The size is a hash of the slot index, so it is never sent. |
| **fruit** | Rare, worth a lot; each of the three does something for eight seconds. |
| **item drops** | A charge of a throwable. |
| **planted** | What a lure leaves behind and what ejecting spits out. |

The ids are one space split by constants (`FOOD_ID_BASE`, `FRUIT_ID_BASE`, …) rather than four grids, because four grids are four queries and a merge per piece per tick.

**Three of the four are positionless on the wire.** `Dot2DScatter` places a slot from a hash of (seed, index), so a client that knows the seed knows where every crumb is, how big, and which fruit. What travels is which slots *exist*: indices added and taken, a few dozen varints a snapshot, about 3 kB on a join. **Planted is the exception**: a lure drops food where a player chose, which cannot be derived, so planted slots carry their position — and they are a separate field so the cheap case stays cheap. Ejected mass is ordinary planted food.

- **The bounds are part of the position.** A slot is hashed into the arena rectangle, so a client with a different rectangle derives every crumb somewhere else while ids and counts all match. `adopt_world_size` runs before `adopt_field_seed`, and the hello carries the size.
- **A slot index is never reused** (`Dot2DScatter`'s rule). A new round's ids sit beside the old round's, so whatever indexed the old field into a grid must remove it first.

## Effects are replicated as flags

A monster's effects (`rush`, `maw`, `rind`, `frosted`, spawn protection) live on the authority as expiry ticks, and speed depends on two of them. If the client needed the expiry ticks to compute its own speed, every fruit would be an eight-second mispredict. So the effects are written into the replicated piece flags once a tick and `HungryMonster.speed_multiplier` reads the flags: both ends compute speed from the same number. `HungryMonster.flags` is that number; `adopt_flags` takes it off any of a monster's pieces. The loadout trait changes speed too, so it travels in the join and both ends read `HungryMonster.trait_id`.

## What a player brings in

Two slots, and every option is a trade rather than an upgrade:

| | |
| --- | --- |
| **starter** | Which throwable you spawn holding. |
| **trait** | `nimble` (+8% speed, −10% mass), `sturdy` (−5% speed, +15% mass), `greedy` (+15% from food, −10% mass). |

The speeds are `HungryContent.TRAIT_SPEED`, and there is one copy: a class catalogue once carried different numbers from the ones the simulation ran.

**Everything about it is ids.** `HungryContent.loadout_schema()` is a `DotLoadoutSchema` over a `DotItemCatalogue`; a dedicated server decides whether a loadout is legal from the schema and an entitlement set without touching an asset. If a change here needs a `load()`, push back on it.

`greedy` is the one item that is not `free`, so an unwired server has an example of something nobody may take. **Entitlements default to nothing**: a server that granted everything would pass every test and quietly be a game where every unlock is free.

- **Validate on the way in, conform on the way out.** `HungryNetBridge._apply_loadout` refuses an illegal published loadout rather than repairing it (a server that repairs lets a client put anything anywhere and get the nearest legal thing). `DotLoadoutConfig.conform_on_load` is on for stored loadouts, where refusing means a returning player cannot spawn.
- **The screen never decides what is legal.** It offers `DotLoadoutSchema.choices_for(slot, entitlements)` and the server validates anyway.
- **The store is a `Callable`.** `HungryNetBridge.loadout_sink` takes a loadout somewhere; `HungryModule` points it at a memory-backed `DotLoadoutManager`, a community server at its own service. The sink is awaited and the cache is updated only after the write succeeds.

A loadout takes effect on the **next spawn**: a trait changeable mid-fight would change the moment somebody was losing.

## The rings are the rule, drawn

Eating needs a **ratio** (a quarter more mass, about twelve percent more width), which nobody judges by eye while being chased. Every monster is ringed green if you could eat it and red if it could eat you, and **neither inside the ratio** — the case a colour would lie about. A piece that is merely smaller is not food.

## Being eaten means having nothing at all

No pieces, no position. A dead player watches whoever ate them, or the leader if that one was eaten too: `HungryClient._watched`, which both the camera and the **input** measure from (a pointer measured from a monster that does not exist points at nothing on respawn). The HUD says whose eyes they are behind.

`HungrySpectate` moves the camera through dot-spectate. A 2D world is dot-npc's XZ plane, so `DotSpectatorManager.camera_2d_of` gives a position back with no second code path; the suite asserts it is where the watched centroid is, which is the check that fails if the plane convention changes. The policy: `force_camera` 0 (a free-for-all has no sides) and **`allow_while_alive = false`** — knowing where the biggest monster is standing is the skill of this game. Roaming is off for the same reason. `camera_position` returns a `Variant` because "not spectating" and "spectating the origin" differ and this arena is centred on the origin.

## An eaten monster goes down, the way the server picked

dot-player-char's dead bodies are 3D rigid bodies; this arena is seen from above with nothing to fall onto. So the body is 2D (`HungryFall`, built by the renderer's `HungryFalls`) and everything a viewer reads is shared with the 3D games: the reaction ids and the rule that picks them, the seed, the push, the `sv_ragdoll*` cvars and the four sound ids.

- **The server picks.** `HungryWorld.decide_death` runs where a monster's last piece is eaten (`_absorb`) or devoured (a hunter, an admin's slay) and puts a `DotPlayerDeath` on the monster; DIED carries it after the pair, last and optional. A client never picks, and nothing in a fall calls `randf()`.
- **This game's headshot and power.** Swallowed whole (an eater at least `SWALLOWED_WHOLE`, four times your mass) is `needs_headshot`, so it can be the headshot launch; `power_of(ratio)` reaches the power launch's 0.5 at ten times your mass. The push is away from the eater (or the hunter); an admin's slay has none, and the seed picks one.
- **Drawn by pose, from the last piece the client saw leave.** DESPAWN comes before DIED, so the renderer remembers each player's last lost piece for two seconds. LIMP deflates and slides, CRUMPLE folds in, FACE_PLANT slams flat across the push, LAUNCH bursts the cell into pieces and throws the rider toward the viewer (drawn bigger, shadow left behind). STIFF moves it as one disc, TOPPLE (`sv_ragdoll 0`) shrinks it where it was, HIDE hides the rider. The motion is about a second; the remains lie at most four seconds, because this floor is under the next fight at once.
- **The rider is the renderer's own node**, moved by the fall while the player is dead and given back (`_place_rider` resets it) when they are not. Before this a dead player's rider stood where they died until the respawn.
- **The sounds are dot-player-char's ids made by this game's bank** (`HungrySound.Cue.FALL_*`), since this game ships no audio files; `headless_presentation` checks the ids are in both the catalogue and the sink.

## Throwables are dot-combat; eating is not

Being devoured is a mass ratio, not a hit-point total, and forcing it through `DotDamageResolver` would be a worse version of both. A **throwable** is damage, and dot-combat already answers its questions (self damage, falloff, a floor, a hook). `HungryCombat.pieces_for` maps hit points onto "how far this scatters you", so a pepper from across the arena scatters less than one at point blank. **`HungryWorld.damage_gate` is unset by default**: a deployment without dot-combat gets the built-in constants; the suites run it both ways. A world that named the combat layer could not run without it.

Lag compensation is off (`enable_lag_compensation`): nothing here is a hitscan shot; a thrown item is a moving body both ends agree about, and eating is a proximity test resolved after everyone has moved.

## Touch

`HungryTouch` is two buttons, because the game is nearly playable on a phone by accident: a drag is the pointer and near is slow. What a touchscreen cannot express is the two edge-triggered actions. They are `Control`s rather than `TouchScreenButton`s so pressing one consumes the touch before `_unhandled_input` and does not also drag the monster. `--touch` forces them on for a desktop look and for headless runs.

## A private arena whose host may leave

`HungryParty`: **migration is on** (a continuous arena has no round boundary to be in the middle of, so a host leaving should cost a moment, not the session), and **reporting is refused** — this game files to dot-stats and dot-achievements, and a peer-to-peer host can lie about how much they ate. `reporting_allowed()` is the one place asked. `headless_presentation` meets over a real HTTP rendezvous (game-playground's `RendezvousStub` on 38900-38960, answering late) so a missing `await` fails; with migration on, "the joiner does not elect itself" holds only until `host_timeout_sec`, because the stub relays no heartbeats.

## Deliberately not here

- **Teams.** Free-for-all is what the genre is; dot-match would make it about ten lines.
- **Persistence.** Mass is per round and loadouts per session; a loadout that outlives a session is a profile, and profiles are dot-user's. Nothing writes to the resolved profile yet.
