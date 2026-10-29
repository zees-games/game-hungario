extends RefCounted

const HungryRules := preload("hungry_rules.gd")
const HungryTuning := preload("hungry_tuning.gd")

## Every number the game is balanced on, in one file.


## Big enough that a full server is not one continuous fight, small enough that a lone
## player finds someone.
const WORLD_SIZE := Vector2(5200.0, 5200.0)

## Grid cell size for the spatial hash. Roughly the largest query radius that runs
## every tick — a mid-sized monster's eat radius, not a crumb's.
const CELL_SIZE := 240.0

const TICK_RATE := 60


## What a monster starts with. About twenty crumbs, which is fifteen seconds of
## uninterrupted eating: long enough to learn the controls, short enough that dying
## early costs nothing.
const START_MASS := 22.0

## Mass that ends a round.
const WIN_MASS := 2400.0

## Mass below which a monster cannot be burst by a thrown pepper.
const MIN_BURST_MASS := 60.0


## Food in the world at once, and how fast it comes back.
const FOOD_TARGET := 1100
const FOOD_REFILL_PER_TICK := 7

## The four sizes, and how often each one appears.
const FOOD_TIER_MASS: Array[float] = [1.0, 3.0, 9.0, 24.0]

## Cumulative weights over [constant FOOD_TIER_MASS]. 58% / 26% / 12% / 4%.
const FOOD_TIER_CUTOFF: Array[float] = [0.58, 0.84, 0.96, 1.0]

const FOOD_TIER_NAMES: Array[String] = ["crumb", "morsel", "chunk", "haunch"]

## Radius a piece of food is drawn and eaten at, per tier.
const FOOD_TIER_RADIUS: Array[float] = [5.0, 8.0, 12.0, 17.0]


## Rare, worth a lot, and each one does something for a while.
const FRUIT_TARGET := 10
const FRUIT_REFILL_PER_TICK := 1
const FRUIT_MASS := 90.0
const FRUIT_RADIUS := 22.0

## How long a fruit's effect lasts.
const FRUIT_EFFECT_SEC := 8.0

enum Fruit {
	## Faster for a while. The one that lets a big monster catch somebody.
	RUSH,
	## Eat at a smaller ratio for a while. The one that changes who you may eat.
	MAW,
	## Cannot be burst, and the next hit is absorbed. The one that survives an ambush.
	RIND,
}

const FRUIT_NAMES: Array[String] = ["rush", "maw", "rind"]
const FRUIT_COLOURS: Array[Color] = [
	Color(1.00, 0.72, 0.20),
	Color(0.85, 0.25, 0.55),
	Color(0.35, 0.85, 0.60),
]

## What [constant Fruit.RUSH] multiplies speed by.
const RUSH_SPEED_MULTIPLIER := 1.45

## What [constant Fruit.MAW] multiplies the eat ratio by. Below 1, so it is easier.
const MAW_RATIO_MULTIPLIER := 0.80


## Throwables lying in the world, and how fast they come back.
const ITEM_TARGET := 14
const ITEM_REFILL_PER_TICK := 1
const ITEM_RADIUS := 19.0

## Most charges of a throwable one monster may hold.
const MAX_CARRIED := 3

## Ticks between two throws. A held key is otherwise the whole stack in a fifth of a
## second, which is not a decision.
const THROW_COOLDOWN_TICKS := 24

## The three throwables, as ids into [method item_catalogue].
const ITEM_PEPPER := &"pepper"
const ITEM_FROST := &"frost"
const ITEM_LURE := &"lure"

const ITEM_IDS: Array[StringName] = [ITEM_PEPPER, ITEM_FROST, ITEM_LURE]

const ITEM_COLOURS: Array[Color] = [
	Color(0.95, 0.30, 0.25),
	Color(0.45, 0.80, 1.00),
	Color(0.80, 0.75, 0.30),
]

## How fast a thrown item travels, and how far it gets before it expires.
const THROW_SPEED := 900.0
const THROW_RANGE := 1150.0
const THROW_RADIUS := 13.0

## What a pepper does: splits every eligible piece into this many, radially.
const PEPPER_PIECES := 5

## How long a frosted monster is slowed, and by how much.
const FROST_SEC := 5.0
const FROST_SPEED_MULTIPLIER := 0.55

## The lure is the one throwable that is not aimed at a person.
const LURE_FOOD_COUNT := 26
const LURE_RADIUS := 190.0

## Which tier planted food is. Morsels: enough to be worth walking to, not enough to
## make the lure better than finding a fight.
const LURE_FOOD_TIER := 1


## The three traits, as ids into [method item_catalogue].
const TRAIT_NIMBLE := &"nimble"
const TRAIT_STURDY := &"sturdy"
const TRAIT_GREEDY := &"greedy"

const TRAIT_IDS: Array[StringName] = [TRAIT_NIMBLE, TRAIT_STURDY, TRAIT_GREEDY]

## The unlock [constant TRAIT_GREEDY] needs.
const TRAIT_GREEDY_UNLOCK := &"hungry.trait.greedy"

## Slot ids in [method loadout_schema].
const SLOT_STARTER := &"starter"
const SLOT_TRAIT := &"trait"

## What each trait multiplies. Speed, starting mass, and what food is worth.
const TRAIT_SPEED: Array[float] = [1.08, 0.95, 1.0]
const TRAIT_MASS: Array[float] = [0.90, 1.15, 0.90]
const TRAIT_FOOD: Array[float] = [1.0, 1.0, 1.15]


static func trait_index(id: StringName) -> int:
	var index := TRAIT_IDS.find(id)
	return index if index >= 0 else 0


static func trait_speed(id: StringName) -> float:
	return TRAIT_SPEED[trait_index(id)]


static func trait_mass(id: StringName) -> float:
	return TRAIT_MASS[trait_index(id)]


static func trait_food(id: StringName) -> float:
	return TRAIT_FOOD[trait_index(id)]



## Ticks between two voluntary splits.
const SPLIT_COOLDOWN_TICKS := 21

## What one press of eject costs, and what it leaves behind.
const EJECT_MASS := 32.0

## Mass a monster must have before it may eject at all. Below this a press would be most
## of what it has.
const EJECT_MIN_MASS := 90.0

const EJECT_COOLDOWN_TICKS := 10

## Which food tier an ejected blob becomes. The biggest, so the 25% lost to ejecting is a
## cost rather than a punishment.
const EJECT_TIER := 3

## How far ahead of the piece it lands.
const EJECT_REACH := 42.0


## [member Dot2DState.flags] bits. Sixteen of them are replicated; these are the ones
## that mean something, and they are what a client draws from.
const FLAG_RIDER := 1 << 0          ## Carries the avatar. Exactly one piece per monster.
const FLAG_RUSH := 1 << 1
const FLAG_MAW := 1 << 2
const FLAG_RIND := 1 << 3
const FLAG_FROSTED := 1 << 4
const FLAG_MERGE_READY := 1 << 5
const FLAG_PROTECTED := 1 << 6      ## Spawn protection.
const FLAG_BURST := 1 << 7          ## Made by a burst rather than by a split.

## The bits that describe a monster rather than a piece.
const EFFECT_MASK := FLAG_RUSH | FLAG_MAW | FLAG_RIND | FLAG_FROSTED | FLAG_PROTECTED


## How a monster moves. Speed falls with mass; radius grows as its square root.
static func tunables() -> Dot2DTunables:
	var out := Dot2DTunables.blob()
	out.max_speed = 415.0
	# The distance over which the cursor goes from "stopped" to "full speed", roughly a body length; much larger and steering feels like a barge.
	out.full_speed_reach = 105.0
	out.dead_reach = 7.0
	out.bounce_off_walls = false
	out.mass_rules = mass_rules()
	return out


## The three relationships the whole game balances on. See [Dot2DMassRules].
static func mass_rules() -> Dot2DMassRules:
	var rules := Dot2DMassRules.cell_eating()

	rules.base_radius = 8.0
	# Area is radius squared, so twice the mass is root-two the width. This is what
	# makes two small monsters worth the same area as one big one, and it is the single
	# number that decides whether splitting is ever correct.
	rules.radius_exponent = 0.5

	rules.base_speed_scale = 1.0
	rules.speed_exponent = 0.44
	# Without a floor the leader on a long-running server is effectively stationary,
	# which is not a challenge — it is a player who has stopped playing.
	rules.min_speed_scale = 0.22

	# A quarter bigger. Below about 1.15 the outcome of a collision starts depending on
	# which monster is resolved first, which is a coin flip dressed as a rule.
	rules.eat_ratio = 1.25
	rules.eat_overlap = 0.85
	rules.absorb_fraction = 1.0

	# A fifth of a percent a second above 260 mass. A player who is still eating never
	# notices; a player who has parked in a corner does.
	rules.decay_per_second = 0.002
	rules.decay_floor = 260.0

	# Sixteen, not eight: a pepper bursts a monster into five and a burst piece can be
	# burst again, so a ceiling of eight would make the second pepper do nothing and
	# look like it had failed.
	rules.max_pieces = 16
	rules.min_split_mass = 40.0
	rules.split_impulse = 820.0
	rules.merge_delay_sec = 16.0

	return rules


## The round: a clock and a mass target. See [HungryRules].
static func rules(tick_rate: int = TICK_RATE) -> HungryRules:
	var out := HungryRules.new()
	out.id = &"hungry"
	out.display_name = "Free for all"
	out.mass_to_win = WIN_MASS
	out.team_based = false
	# Mass is the score, and dot-match's own score-limit check counts kills. The
	# subclass is what makes the win condition mean the right thing.
	out.score_limit = 0
	out.time_limit_sec = 900.0
	out.min_players = 1
	out.warmup_sec = 0.0
	out.countdown_sec = 0.0
	var tuning := HungryTuning.settings()
	out.respawn_delay_sec = tuning.respawn_delay_sec
	out.spawn_protection_sec = tuning.spawn_protection_sec
	out.intermission_sec = tuning.intermission_sec
	out.match_end_sec = tuning.match_end_sec
	out.suicide_points = 0
	out.kill_points = 0
	out.pause_when_empty = false
	return out


## What a monster may throw, as data a server can check without loading anything.
static func item_catalogue() -> DotItemCatalogue:
	var pepper := DotItem.make(ITEM_PEPPER, DotItem.KIND_CONSUMABLE, true)
	pepper.display_name = "Pepper"
	pepper.tags = [&"throwable", &"burst"] as Array[StringName]
	pepper.content_id = "hungry/items/pepper"

	var frost := DotItem.make(ITEM_FROST, DotItem.KIND_CONSUMABLE, true)
	frost.display_name = "Frostberry"
	frost.tags = [&"throwable", &"slow"] as Array[StringName]
	frost.content_id = "hungry/items/frost"

	var lure := DotItem.make(ITEM_LURE, DotItem.KIND_CONSUMABLE, true)
	lure.display_name = "Lure"
	lure.tags = [&"throwable", &"field"] as Array[StringName]
	lure.content_id = "hungry/items/lure"

	var nimble := DotItem.make(TRAIT_NIMBLE, DotItem.KIND_PERK, true)
	nimble.display_name = "Nimble"
	nimble.tags = [&"trait"] as Array[StringName]

	var sturdy := DotItem.make(TRAIT_STURDY, DotItem.KIND_PERK, true)
	sturdy.display_name = "Sturdy"
	sturdy.tags = [&"trait"] as Array[StringName]

	# Not free, and the only thing here that is not. An unwired server permits only what
	# is marked free, so this is what an unlock looks like from the inside.
	var greedy := DotItem.make(TRAIT_GREEDY, DotItem.KIND_PERK, false)
	greedy.display_name = "Greedy"
	greedy.entitlement_id = TRAIT_GREEDY_UNLOCK
	greedy.tags = [&"trait"] as Array[StringName]

	var catalogue := DotItemCatalogue.of(
		[pepper, frost, lure, nimble, sturdy, greedy] as Array[DotItem]
	)
	catalogue.id = &"hungry_items"
	catalogue.reindex()
	return catalogue


## What a player brings in, as a document of ids a server can check without loading
## anything.
static func loadout_schema() -> DotLoadoutSchema:
	var starter := DotLoadoutSlot.make(SLOT_STARTER, true, ITEM_PEPPER)
	starter.display_name = "Starting throwable"
	starter.kinds = [DotItem.KIND_CONSUMABLE] as Array[StringName]
	# The tag rather than the kind alone: a consumable that is not a throwable would fit a
	# slot checked only by kind, and the slot is "what you spawn holding".
	starter.require_tags = [&"throwable"] as Array[StringName]

	var trait_slot := DotLoadoutSlot.make(SLOT_TRAIT, true, TRAIT_NIMBLE)
	trait_slot.display_name = "Trait"
	trait_slot.kinds = [DotItem.KIND_PERK] as Array[StringName]
	trait_slot.require_tags = [&"trait"] as Array[StringName]

	var schema := DotLoadoutSchema.of(
		&"hungry_loadout",
		[starter, trait_slot] as Array[DotLoadoutSlot],
		item_catalogue()
	)
	schema.display_name = "Monster"
	schema.reindex()
	return schema


## The store key for a player.
static func loadout_key(player_id: int) -> String:
	return "hungry-%08d" % player_id


## Which tier a food slot is, from its variant. Deterministic; never sent.
static func food_tier(variant: float) -> int:
	for tier in range(FOOD_TIER_CUTOFF.size()):
		if variant < FOOD_TIER_CUTOFF[tier]:
			return tier

	return FOOD_TIER_CUTOFF.size() - 1


static func food_mass(variant: float) -> float:
	return FOOD_TIER_MASS[food_tier(variant)]


static func food_radius(variant: float) -> float:
	return FOOD_TIER_RADIUS[food_tier(variant)]


## Which fruit a fruit slot is, from its variant.
static func fruit_kind(variant: float) -> Fruit:
	return (int(variant * float(FRUIT_NAMES.size())) % FRUIT_NAMES.size()) as Fruit


## Which throwable an item slot holds, from its variant.
static func item_id(variant: float) -> StringName:
	return ITEM_IDS[int(variant * float(ITEM_IDS.size())) % ITEM_IDS.size()]


static func item_index(id: StringName) -> int:
	return ITEM_IDS.find(id)


static func item_colour(id: StringName) -> Color:
	var index := item_index(id)
	return ITEM_COLOURS[index] if index >= 0 else Color.WHITE


## A colour for a player, from their id. Deterministic, so every client agrees.
static func colour_for(id: int) -> Color:
	return Color.from_hsv(fposmod(float(id) * 0.618033988749895, 1.0), 0.66, 0.96)


## The avatar schema a monster's rider is dressed from.
static func avatar_schema() -> DotAvatarSchema:
	var schema := DotAvatarSchema.new()
	schema.id = &"hungry_rider"
	schema.version = 1

	var body := DotAvatarSlot.make(&"body", true, &"rider_pip")
	body.display_name = "Body"
	body.layer = 20

	var hat := DotAvatarSlot.make(&"hat")
	hat.display_name = "Hat"
	hat.layer = 60

	var trail := DotAvatarSlot.make(&"trail")
	trail.display_name = "Trail"
	trail.layer = 10

	schema.slots = [body, hat, trail]

	var parts: Array[DotAvatarPart] = []

	for entry in [
		[&"rider_pip", &"body", true, 2, "hungry/avatar/rider_pip"],
		[&"rider_blob", &"body", true, 2, "hungry/avatar/rider_blob"],
		[&"rider_spike", &"body", false, 2, "hungry/avatar/rider_spike"],
		[&"hat_cap", &"hat", true, 1, "hungry/avatar/hat_cap"],
		[&"hat_crown", &"hat", false, 1, "hungry/avatar/hat_crown"],
		[&"trail_dust", &"trail", true, 1, "hungry/avatar/trail_dust"],
		[&"trail_ember", &"trail", false, 1, "hungry/avatar/trail_ember"],
	]:
		var row: Array = entry
		var part := DotAvatarPart.make(row[0], row[1], bool(row[2]))
		part.colour_channels = int(row[3])
		part.content_id = String(row[4])
		# Everything in the body slot falls back to the free rider, so undownloaded content draws a plain rider; the free rider itself has no fallback, since the schema refuses a resolution loop.
		part.fallback_id = (
			&"rider_pip" if row[1] == &"body" and row[0] != &"rider_pip" else &""
		)
		parts.append(part)

	schema.parts = parts
	schema.invalidate()
	return schema


## A deterministic avatar for a player who has none. The look of a guest.
static func default_avatar(id: int) -> DotAvatar:
	var avatar := DotAvatar.make(&"hungry_rider")
	avatar.set_part(&"body", &"rider_pip" if (id % 2) == 0 else &"rider_blob")
	avatar.set_colour(&"body", 0, colour_for(id))
	avatar.set_colour(&"body", 1, Color.WHITE)
	return avatar
