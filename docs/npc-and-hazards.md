# Hunters and hazards

## Hunters: dot-npc, dot-npc-ai and the director

NPC monsters that roam, eat what they can and run from what they cannot. Three addons, each for the half this game would otherwise get wrong:

- **dot-npc**: catalogue, budget, per-kind cap and **perception**. `DotNpcSenses` acquires at one threshold, drops at a weaker one, and keeps chasing for a grace from the last sighting — a hunter that asked "who is nearest" every tick flickers between targets.
- **dot-npc-ai**: a three-state machine (a tree would be three leaves under a selector), a wander that wanders, separation so a pack does not stack, and a **reaction time** so a hunter cannot commit on the tick it first sees you. Difficulty is per kind (`skill` in the catalogue: swarmling normal, stalker hard, lurker easy); `npc_skill`, `npc_reaction_scale` and `npc_reaction_min` move every kind at once. Without a character, `has_reacted()` answers true on the first tick and the reaction time is zero.
- **dot-npc-ai-director**: *when*. Pressure builds, sustains, fades and relaxes against an estimate of what the players experience, which here is **how close the nearest hunter that could actually eat them is**, reported as the "health" the director understands. A lurker a player is about to swallow is not pressure.

**A 2D world is dot-npc's XZ plane**: `(x, y)` is `Vector3(x, 0, y)` (`DotNpcSpawner.spawn_2d`, `two_dimensional`). Every sense, steering rule and director measure is a 3D distance, and on a plane with one component fixed that is the 2D one.

**Hunters are not dot-net entities.** A piece is predicted, reconciled and interest-managed because a player's own input needs it. A hunter is server-authoritative and unpredicted (a corrected NPC reads worse than a slightly late one), and there are few, so one reliable event a few times a second is cheaper and adds no second id space.

**Off by default** (`hungry_hunters_on`). A mode about eating and a mode about being hunted are different games, and an installed addon must not turn one into the other. The query provider reports the cvar so a server list can tell them apart.

### Navigation

`HungryHunters.nav_for(layout, bounds)` builds dot-npc navigation from the layout: a 64-unit grid on the XZ plane, a point wherever 40 units of clearance fits (one graph for all kinds), edges to eight neighbours whose line keeps it. `_keep_nav_current` hands it to the spawner on the first tick of every layout, so a game change needs no hook; an empty box gets null, which is a straight line. The chase calls `steer_with_spacing`, which asks the spawner's `path_toward`. **Snap radius and repath drift are set in world units**: dot-npc's defaults are metres (a 4-unit snap never finds a point; a 2.5-unit drift repaths every tick). A hunter repaths at most once a second or when its target has moved three grid steps; a whole-map search costs tens of milliseconds. `_keep_out_of_the_level` stays, for overshoot on a turn.

**The brain reads its link to `HungryHunters` on first use (`_link`)**, not in `_build`: dot-npc builds the brain inside the spawn and sets `meta` after it, so a link read in `_build` is null and the hunter wanders for its whole life. See [history.md](history.md#no-hunter-had-ever-chased-anybody).

### Where a hunter may appear

`HungryHunters.spawn_points_for(layout, bounds)` walks the director's rings out of the rocks at the biggest hunter's radius (`largest_radius`) and refuses two kinds of point (`spawnable`): inside a refuge (harbour, cove, pool, the deepest shallows band) and off the biggest floor that radius can move about in (`HungryLayout.main_region`, `in_region`). `_keep_nav_current` re-seeds them on every layout, so they follow a game change.

### A hunter's size, and the open question

A hunter's radius is `HungryHunters.radius_of`, `4 √(mass / π)`: 15 for a swarmling, 34 for a stalker, 68 for a lurker. That is a different curve from the players' (`8 √mass`). A lurker is 135 across and fits every gate on every map, so the shared 40-clearance graph is enough and there are no per-kind graphs.

**It also means every hunter fits through every refuge's door.** The den and the harbours promise a small player that nobody can follow them in; that is true of monsters and false of hunters, since a lurker of 900 mass eats anything under 720. Whether hunters should be on the players' curve, or refuges refused to them another way, is **an open design decision**, not taken.

## Hazards: dot-props in an arena

Rocks, spikes and lures through `DotPropSpawner.spawn_2d`. dot-props supplies the catalogue, budget, world cap, undo and cleanup; **what a hazard does is this game's**: `HungryHazards.resolve` runs inside the world tick after movement and before eating.

Everything is **frozen the moment it lands**, because rigid-body simulation is not reproducible across machines; a frozen body is a fixed obstacle both ends derive from the replicated position and the catalogue radius. The spawn interval is zero: dot-props' interval exists because a player can hold a spawn key, and nothing here is placed by a player. The budget and world cap still apply.
