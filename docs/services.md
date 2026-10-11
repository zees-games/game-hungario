# Server services: chat, voice, moderation, stats, the vote, the browser

`HungryServices` wires chat, moderation and voice to this arena's people and wire. It is this game's own copy, not dot-game's `DotGameServices`: hungario has not been converted to dot-game yet (dot-game's CLAUDE.md lists it with arena and g2gfast, and says to convert arena first).

## Chat

**`DotChatRouter` has the rules** (four channels, one of them a radius; a backlog for whoever just joined; `/me`; a gag that survives a reconnect), and `HungryModule` hooks dot-server's `player_chat` with `hook_pre` and **cancels** it, so dot-server's own broadcast never happens. dot-server's join and leave announcements are off (`announce_joins = false`) because dot-chat makes them. There is exactly **one path**: two would be two sets of rules, and the one that skipped the filter would leak admin chat. `sandbox` asserts nothing arrives through dot-server's own signal (it separates the server's "what carries chat" notice by `kind`) and that a line sent the legacy way, from a shell chat box that cannot name a channel, is forwarded onto this game's wire.

**The chat key is the player id, not the account uid.** dot-chat's `key_fn` and dot-moderation's `key_for_peer` answer different questions: a punishment is against a person who will come back (keyed by something that survives a reconnect); a chat line is attributed to somebody in this arena now. Two guests behind one device id share a uid.

## Voice

An arena is bigger than a screen, so `DotVoiceRouter.default_channel` is `PROXIMITY` and the range is the number `HungryInterest` grows a view rectangle by: **being audible from outside your own screen is the same bug as being visible without being audible**. A room you can see all of would want the opposite. The position is the mass-weighted centroid; a dead player has no position and hears only the room channel. One `unreliable` RPC on its own channel serves UDP and TCP clients; push-to-talk closes when a screen takes the keyboard; with no audio device, playback goes into a buffer, which is what makes the receiving half checkable.

## Moderation

dot-moderation's live tools are `HungryModTools`, built in the module because a game change replaces the world under it. **Only what a server can do to a monster on its own is supported**: slay (every piece devoured), respawn (the queue cancelled first), give and strip an item, rename, and bring, goto, send and return, which move every piece by one offset so a split monster arrives in its own shape. Noclip, freeze, speed, blind and beacon go through replicated state ([netcode.md](netcode.md#admin-state-goes-through-what-the-client-predicts)).

- **A spawn tells dot-moderation** (`_watch_spawns`, off `HungryWorld.player_spawned`, re-wired on a game change), so a respawn switches noclip and freeze off. The bits live on the monster, which outlives its pieces.
- **A game change clears the return history for everybody** (`_module_game_changed`): every stored position belongs to the arena that was freed.
- **Blind and beacon persist on a respawn** (`HungryModTools.PERSIST_ON_RESPAWN`); `blind <player> <seconds>` is dot-moderation's `TIMED_TOGGLES`. The client draws them: `HungryHud.blind_overlay` is a near-black rect over the whole viewport, **under** the HUD's widgets (the clock and feed still show the round is going) but **over the minimap**, which would otherwise be every monster's position on one square. It is this player's blind dead or alive. `HungryBeacon` (drawn by `HungryRenderer`) rings the whole monster with a ripple a second and **points from the screen's edge when the monster is off screen** — a top-down arena has no walls to see through, only an edge. Each ripple plays `HungryPresentation.BEACON_SOUND`, positional, culled past 3200 units.
- Refused, with a reason `modtools` prints: gravity (top-down), god and buddha (being eaten is the game), health and slap (a monster has mass, not health).

## Stats, boards and achievements

**Neither addon gets a new source of truth.** `HungryModule` declares a `DotStatsSchema` and records against it; `DotAchievementStatsLink` is a signal connection over that, and dot-leaderboard takes the readings worth ordering by. A second count would be a second number that can disagree. `dedicated` checks that **every stat an achievement watches is one the game declares** (one that watches an unreported stat never unlocks, silently). Boards are **scoped by mode** (one board over Classic and Frenzy is a board of who played Frenzy); one is a `PENALTY` board so the lower-is-better half of `beats()` is exercised.

## The vote and dot-map

**The modes are the maps.** dot-map's catalogue is built **from** the game descriptors (`HungryMaps`), adding what they lack: `min_players` (`gauntlet` is off the ballot below three). **The swap stays dot-server's**: `change_game` already announces, waits and swaps with a content sync this family spent nine bugs on, so `DotMapSyncHost` is not used and `DotVoteGameSource` applies through the game manager.

Settings set **explicitly** because dot-vote found bugs in leaving them: `extend_needs_majority`, `nomination_seconding` (without it every nomination count is 1 and `MOST_NOMINATED` does nothing), and `begin_on_apply` (both director and host announcing one play halves every cooldown).

The joins that make it work, each of which was once missing:

- **The director is advanced once a tick, by the module only** (it was also self-advancing, so every vote clock ran double).
- **`HungryMaps.install_commands`** puts `DotVoteCommands` on the module, voters keyed as the bare player id; a chat `!rtv` goes to the console here.
- **The leading score is the biggest monster's mass** (`director.note_score`, polled once a tick), so a vote `score_limit` is a mass; dot-match's `round_ended` reaches the director, so `apply: end_of_round` means a round. `round_based` is on, so `time_up: finish_round` finishes the round in progress.
- **`extend` from the wire is an admin's**, not any player's.
- **`map time` reads the vote's own clock**, which follows an extend; a separate `DotMapTimeLimit` beside it did not.

**Cues.** The rules name `HungryEvents.CUE_VOTE_*` — on the wire file because both ends load it, so rules, presentation catalogue and `HungrySoundSink.CUES` read one copy. `HungryMaps.cue_due` carries each cue and countdown second to the module, sent as `HungryEvents.Kind.VOTE`. `HungrySound` bakes them as pure tones (a ballot is about the server, not a monster). The countdown is one label under the round clock, not in the five-line feed, where a line a second would push out the chat line announcing the vote.

**The ballot on the shell.** The vote wrapper owns a `DotVoteBallotFeed` and the module points its `ballot_fn` at `server.send_notice`, one copy per playing session with that session's voter id, under the topic `map_ballot`. dot-server-deploy's shell draws it as a `DotBallotPanel` beside the server's own `game_ballot`, and a click goes back as the same command a player could type. Standalone, nothing draws it and chat still carries the ballot.

## The browser and the query provider

`HungryBrowser` is a dot-browser list: DQP, DQP over a WebSocket, A2S, favourites, history and a mode filter. `HungryQueryProvider` is the server's half, reporting what a person filtering a list filters on: the mode (the map here), occupancy, round state, the leader's mass, and **whether hunters and hazards are on**, the two cvars that make it a different game. With a site configured (`--browser-backbone-url=<origin>` or `DOT_BROWSER_BACKBONE_URL`), the list also starts with the site's listing of this game's servers (`DotBrowserSourceBackbone`, app `hungario`, website-city's `/api/content/server/list`); without one it is history and typed addresses only.

## The backbone

`HungryModule` builds the stats report (with the bot count dot-server cannot know, and the mode as the map) and wires it into `DotBackboneClient` when an operator has configured a token. The suites cover the report's shape and that an unconfigured server stays silent; nothing here talks to a real backbone. See the family's [backbone.md](../../../docs/backbone.md).
