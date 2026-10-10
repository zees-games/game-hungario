# The netcode

dot-net does the replication; `game/net/` is this game's bridge onto it. Read dot-net's CLAUDE.md for the mechanism; this file is what is specific to a game whose entity count changes every second.

## Ordering: the first behaviour through drives the world

dot-net simulates per entity, but this game's tick order is a whole-world property: everybody moves, then eating is resolved against the world as it is afterwards, then merges, projectiles, the match. `HungryNetBridge.ensure_world_ticked` joins the two: the first `_net_simulate` on a tick runs the whole world and the rest find it done. `HungryModule.server_tick` calls it again afterwards, which covers the tick before the match entity is registered (one integer comparison).

## One entity per piece, and one always-relevant entity for the match

After a burst a player's pieces can be a screen apart, and an entity per *player* would be relevant everywhere any piece was. So each piece is a `DotNetIdentity` + `HungryPieceNet`, replicating what `Dot2DNetSync` describes.

The match clock is its own `always_relevant` entity (`HungryMatchNet`): every client needs the round state, and a dead player has no pieces. It is also what keeps an empty server ticking — with no players it is the only entity calling `ensure_world_ticked`, and without it a booted server's warmup never ends.

## Nothing is sent to a peer before it asks

dot-server's signon finishes and then the client builds its scene; in between, an RPC has no node to land on and is lost ("Node not found", once per call). `HungryEvents.Ask.READY` is the client saying it has somewhere to put them, and `_admit` is where a peer joins the manager and gets the hello, the roster and the field. `_broadcast` sends peer by peer for the same reason: dot-net's broadcast reaches peers that cannot receive yet. `HungryNetBridge.peer_admitted` is the hook for anything that greets a player (`HungryModule._welcome`: chat backlog, join notice, hunters and hazards already present); `client_spawn` is too early, because no peer is ready then.

`HungryNetBridge.remove_peer` asks the manager whether it knows the peer, not the ready set: the disconnect handler takes the peer off the ready set first, and gating on it left a dead peer receiving snapshots for the life of the server.

## A bot has no peer, and peer 0 is not "everybody"

Bots are players with no connection, on peer 0. **`net.add_peer(0)`** makes the server build a snapshot against the bot's interest rectangle and send it to the broadcast address (every client receives a second snapshot computed for somebody else: a monster jumping between two positions). **`net.send(msg, 0)` is a broadcast**, so a `_tell` that fell through would send every bot's private carry list to everybody. Both are guarded on `peer_id > 0`.

## Prediction is the motor, and deliberately not the set

`_net_simulate` on a predicted piece runs the motor for that piece and nothing else, a pure function of (state, command, delta) — the only shape a replay converges for. `DotNetPredictor` reconciles one entity at a time, so anything coupling two entities in a replay is computed against whatever the other held.

The cost is `_separate`, applied live on both ends and not replayed: for the second after a split, while pieces overlap, shown and replayed positions differ by a fraction of the overlap and the correction is eased out. Once apart they agree exactly. The rock push-out (`block_piece`) **is** on the replay path, and `headless_net`'s *a round of warrens* measures it: 0.20 units mean gap pressed against a rock, against 3.72 with the rock removed from the client's world only.

**Rules that keep it right:**

- **`receive_snapshot` must not reconcile.** `DotNetManager.receive_snapshot` already routes a predicted entity's state to the predictor; a second pass replays the same inputs against rewound values (correction rate 0.500 against 0.032).
- **`HungryPieceNet._net_state_applied` skips a predicted entity**, as every game's player net does. Moving the owner's node to the snapshot there makes the predictor capture "before" after the rewind and count the replay itself as a correction.
- **`HungryNetBridge.RECONCILE_EPSILON` (0.5 px) is set on every `DotNetConfig` this game builds.** dot-net's default is 0.01 in metres, a hundredth of a pixel here and under the wire's quantisation.
- **A test client must drive the clock the way `HungryClient._physics_process` does** (`headless_net`'s `_client_step`); stamping ticks by hand over a clock that never advances replays nothing and measures nothing. Compare tick N on both ends, which a client one tick ahead fails and the correction rate cannot see.

## Interest is measured from the centroid

`DotNetManager._observer_for` hands a strategy the first entity a peer owns, which after a burst is an arbitrary fragment. `HungryInterest` measures from the monster's centroid, grows the rectangle linearly in *radius* (a monster that fills the screen otherwise sees nothing it might eat), and scores big-and-near above small-and-far. The voice range is the same number (see [services.md](services.md#voice)).

## Admin state goes through what the client predicts

Noclip, freeze and speed change how a monster moves, so they travel as dot-2d's `Dot2DAdminModifiers`, kept per monster in `HungryMonster.admin` (authority-only) and written into every piece's `Dot2DState.admin` each tick, replicated as `net_admin`. A server that changed movement without the owning client knowing would rubber-band it on every snapshot; `headless_net` keeps that as a negative control. Noclip is the rocks not being there (`block_piece` skips them, inside the replayed function), not the arena's edge; a freeze also refuses split, throw and eject. Blind and beacon are flags on **every piece** (which pieces a client hears about is interest management's choice): `net_blind` owner-only, so an opponent cannot read who is blind; `net_beacon` to everybody, and a beaconed monster's pieces are `always_relevant`. State rather than events, so a joiner, a lost snapshot and a game change are corrected by the next snapshot. The tools themselves are in [services.md](services.md#moderation).

## Game switching: the world is the scene, the manager is not

`changegame` frees the running mode scene and instantiates the next with players connected. So the world lives inside the scene (`HungryMode`), and the `DotNetManager`, the bridge and the loadout manager do not: rebuilding a manager resets message ids, peer records and the clock, which is a disconnect for everybody. `HungryNetBridge.rebind` moves the bridge onto the new world; the match entity survives because every client knows its net id. A game change also clears dot-moderation's return history (`_module_game_changed`), because every stored position belongs to the arena that was freed.

dot-server's `votemap`, `vote` and `vote_status` work against the descriptors with no code here.

**Standalone and delivered.** Built in, `examples/play.gd` is the application and loads `HungryClient` itself, because dot-server refuses an absolute scene path a server names. Delivered as a pack, `game.yml` names `client_scene`, and every path the game makes to its own files goes through `HungryPaths.rebase`, because a mounted pack does not live at the path it was authored at (the mount constraint in the family [CLAUDE.md](../../../CLAUDE.md)).

## Messages

`HungryEvent` and `HungryRequest` are built with `new(kind, body)`, with defaulted `_init` arguments because dot-net's registry decodes with a bare `new()`. **No message script preloads itself**: a `DotNetMessage` script that preloads its own path, loaded by a module inside a running `DotServer`, can leak the whole script graph at exit on Godot 4.7.2 ([gdscript-hazards.md](../../../docs/gdscript-hazards.md#a-script-that-names-itself-can-leak-every-script-at-exit-godot-472)). `dedicated`'s *exiting clean* section reads every message script under `game/` as text and fails on a self-preload. New event kinds are **appended**, so every existing kind keeps its number.
