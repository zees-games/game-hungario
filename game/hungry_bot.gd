extends RefCounted

const HungryContent := preload("hungry_content.gd")
const HungryField := preload("hungry_field.gd")
const HungryGrid := preload("hungry_grid.gd")
const HungryMonster := preload("hungry_monster.gd")
const HungryNetCommand := preload("net/hungry_net_command.gd")
const HungryPiece := preload("hungry_piece.gd")
const HungryWorld := preload("hungry_world.gd")

## A monster that plays itself.
##
## [b]It is a test fixture and a server that is never empty, not an opponent.[/b] It
## chases the best thing it can reach, runs from anything that can eat it, splits when
## that would win a chase, and throws what it is carrying at whoever is in front of it.
## That is enough to exercise every path in [HungryWorld] — eating, bursting, merging,
## dying, respawning — which is the job.
##
## [b]Everything here is deterministic.[/b] No [method @GlobalScope.randf], no clock: a
## bot's command is a pure function of the world, its own id and the tick, so a replay of
## a recorded round produces the same one. The little bit of variety that stops eight bots
## from moving as one body comes from hashing the id, which is the same trick
## [GS2DScatter] uses to place a field.
##
## [b]How well it plays is gs-bot's `bot_difficulty`[/b] ([GSBotSettings] on the world: the
## module binds the cvars, the offline client the console variables). Three of the settings
## mean something on a plate: `bot_sight` scales how far it looks ([constant SIGHT] at medium),
## `bot_reaction` how soon it runs from something that can eat it (the margin past six radii,
## [constant FLEE_MARGIN] at medium, scaled by medium's reaction over this one's), and
## `bot_aim_error` / `bot_aim_floor` how far off a throw leaves (degrees, either side, drawn
## from the id and the tick so it stays deterministic).

## How far a bot looks, in world units. Roughly a screen, so it does not react to things
## a player could not see it react to.
const SIGHT := 900.0

## How far past six of its radii a threat makes a medium bot run, in world units.
const FLEE_MARGIN := 180.0

## The preset every scale is relative to, so medium plays as this file always did.
static var _medium: GSBotProfile = GSBotProfile.new()

## How much bigger something has to be before it is worth running from. Slightly under
## the eat ratio, so a bot starts moving before it is actually in danger.
const FEAR_RATIO := 1.15

## Split when the prey is within this many of the bot's own radii and the split would
## still leave each half big enough to eat them.
const SPLIT_REACH := 3.2

## Throw at anything inside this, roughly ahead.
const THROW_REACH := 700.0


## The command this bot wants this tick.
static func command_for(
	world: HungryWorld,
	monster: HungryMonster,
	tick: int
) -> GS2DCommand:
	var command := GS2DCommand.new()

	if world == null or monster == null or not monster.alive:
		return command

	var head := monster.rider_piece()

	if head == null:
		return command

	var origin := head.position()
	var skill := GSBotSettings.of(world).profile
	var sight := SIGHT * skill.sight / _medium.sight
	var rules := world.tunables.mass_rules

	var look := look_for(world, monster, head, origin, sight)

	var threat := look.threat
	var threat_distance := look.threat_distance

	var prey := look.prey
	var prey_distance := look.prey_distance

	## The nearest piece belonging to anybody else, whatever its size.
	##
	## Separate from prey and from threat because a throwable is useful against both, and
	## a pepper is [i]most[/i] useful against something too big to eat: bursting it is how
	## a small monster turns an unwinnable fight into several winnable ones.
	var enemy := look.enemy
	var enemy_distance := look.enemy_distance

	var snack := look.snack
	var snack_score := look.snack_score

	var target := origin
	var deciding := true
	var flee_range := head.radius() * 6.0 + FLEE_MARGIN * clampf(_medium.reaction / maxf(skill.reaction, 0.05), 0.25, 3.0)

	# A snack inside the threat's flee range makes the bot step out, turn back for it and
	# step in again: 14 s of dithering against the wall in the soak.
	if threat_distance < INF and snack.distance_to(threat) < flee_range:
		snack_score = -INF

	if threat_distance < flee_range:
		# Away from the threat, and biased along the wall rather than into it, because a
		# bot that flees straight into a corner dies there every time.
		var away := (origin - threat).normalized()
		var bounds := world.arena.bounds
		var inward := (bounds.get_center() - origin).normalized()
		target = origin + (away * 2.0 + inward).normalized() * 400.0
		deciding = false

	if deciding and prey != null:
		target = prey.position()

		var reach := head.radius() * SPLIT_REACH
		var half := head.mass() * 0.5

		# Splitting halves you, so it is only correct if the half can still eat them.
		# Without that check a bot splits itself into a snack.
		if prey_distance < reach and rules.can_split(head.mass(), monster.piece_count()) \
				and half >= prey.mass() * rules.eat_ratio:
			command.set_button(GS2DCommand.BUTTON_SPLIT, true)

		deciding = false

	if deciding and snack_score > -INF:
		target = snack
		deciding = false

	if deciding:
		# Nothing in sight. Walk a deterministic circuit rather than standing still, so a
		# bot on an empty map still moves and still finds a field that has refilled.
		var phase := float(tick) * 0.006 + _jitter(monster.id) * TAU
		target = world.arena.bounds.get_center() \
			+ Vector2.from_angle(phase) * world.arena.bounds.size.x * 0.3

	# Throwing overrides the steering aim for this one tick, because a throw leaves along
	# the pointer and the most valuable target is usually the thing being run away from.
	# One tick of turning toward it is the cost, and the cooldown bounds how often.
	if enemy != null and enemy_distance < THROW_REACH and not monster.carried.is_empty():
		target = enemy.position()
		# The world throws on the press edge; a held button never fires again after the
		# cooldown, so two bots on top of each other would aim at one another forever.
		command.set_button(GS2DCommand.BUTTON_ACTION, tick % 2 == 0)

	target = _off_the_wall(target, world.arena.bounds, head.radius())

	var offset := target - origin
	if enemy != null and enemy_distance < THROW_REACH and not monster.carried.is_empty():
		offset = offset.rotated(deg_to_rad(_throw_error(monster.id, tick, skill)))
	command.aim = offset.normalized() if offset.length_squared() > 0.000001 else Vector2.ZERO
	command.reach = minf(offset.length(), HungryNetCommand.MAX_REACH)

	return command


## What a bot sees around its head: the best snack, and the nearest threat, prey and enemy piece.
class Look:
	var threat := Vector2.ZERO
	var threat_distance := INF
	var prey: HungryPiece = null
	var prey_distance := INF
	var enemy: HungryPiece = null
	var enemy_distance := INF
	var snack := Vector2.ZERO
	var snack_score := -INF

	func same_as(other: Look) -> bool:
		return threat == other.threat and threat_distance == other.threat_distance \
				and prey == other.prey and prey_distance == other.prey_distance \
				and enemy == other.enemy and enemy_distance == other.enemy_distance \
				and snack == other.snack and snack_score == other.snack_score

	func describe() -> String:
		return "threat %s@%s prey %s@%s enemy %s@%s snack %s@%s" % [
			threat, threat_distance, _id(prey), prey_distance, _id(enemy), enemy_distance, snack, snack_score
		]

	static func _id(piece: HungryPiece) -> String:
		return "-" if piece == null else str(piece.id)


## [method look_for] asks gs-sim's `GSSimGrid2D` (kept beside the world's grid by
## [HungryGrid]) for the neighbour loop when the library has it, to the script's bit
## (`headless_native_forage`); off, or with no library (the web), the script looks.
static var native_forage := true
## With [member native_forage], the native ask also judges the pieces it sees (`forage_judged`:
## owner and mass read from [member HungryWorld._pieces] in the same call) instead of handing
## each back to [method _judge]. Off, or with an older library, the script judges.
static var native_judge := true
## With the native ask, re-runs the script beside every [method look_for] and counts any
## difference (an error each, the script's answer wins). The parity suite's live half;
## costly, not for play.
static var forage_verify := false
## Asks checked and asks that differed under [member forage_verify].
static var forage_checked := 0
static var forage_differ := 0


## What [param monster]'s [param head] sees within [param sight] of [param origin].
static func look_for(
	world: HungryWorld,
	monster: HungryMonster,
	head: HungryPiece,
	origin: Vector2,
	sight: float
) -> Look:
	var grid := world.arena.grid
	var native: Variant = null

	if native_forage and grid is HungryGrid:
		native = (grid as HungryGrid).native()

	if native == null:
		return look_script(world, monster, head, origin, sight)

	var look := Look.new()
	var rules := world.tunables.mass_rules
	var pickups_ok := monster.carried.size() < HungryContent.MAX_CARRIED
	var seen: PackedFloat64Array

	if native_judge and (grid as HungryGrid).judges:
		seen = native.forage_judged(
			origin, sight, head.id, pickups_ok, world._pieces, monster.id, head.mass(),
			FEAR_RATIO, rules.eat_ratio
		)
		look.snack_score = seen[0]
		look.snack = Vector2(seen[1], seen[2])
		look.threat_distance = seen[3]
		look.threat = Vector2(seen[4], seen[5])
		look.prey = world.piece_for(int(seen[6])) if seen[6] >= 0.0 else null
		look.prey_distance = seen[7]
		look.enemy = world.piece_for(int(seen[8])) if seen[8] >= 0.0 else null
		look.enemy_distance = seen[9]
	else:
		seen = native.forage(origin, sight, head.id, pickups_ok)
		look.snack_score = seen[0]
		look.snack = Vector2(seen[1], seen[2])

		var at := 4
		for _piece in range(int(seen[3])):
			_judge(
				look, world.piece_for(int(seen[at])), Vector2(seen[at + 1], seen[at + 2]),
				seen[at + 3], head, monster, rules.eat_ratio
			)
			at += 4

	if forage_verify:
		forage_checked += 1
		var want := look_script(world, monster, head, origin, sight)

		if not look.same_as(want):
			forage_differ += 1
			push_error("HungryBot.look_for: native %s, script %s (head %d at %s, sight %s)" % [
				look.describe(), want.describe(), head.id, origin, sight
			])
			return want

	return look


## [method look_for] in script: the fallback, and what the native ask is held to.
static func look_script(
	world: HungryWorld,
	monster: HungryMonster,
	head: HungryPiece,
	origin: Vector2,
	sight: float
) -> Look:
	var look := Look.new()
	var eat_ratio := world.tunables.mass_rules.eat_ratio
	var grid := world.arena.grid

	for grid_id in grid.query_rect(
		Rect2(origin - Vector2(sight, sight), Vector2(sight, sight) * 2.0), head.id
	):
		var at := grid.position_of(grid_id)
		var distance := origin.distance_to(at)

		if distance <= HungryGrid.NEAR:
			continue

		if grid_id < HungryField.PIECE_ID_LIMIT:
			_judge(look, world.piece_for(grid_id), at, distance, head, monster, eat_ratio)
			continue

		if HungryField.kind_of(grid_id) == HungryField.Kind.ITEM:
			# A full bot cannot take it; steering at it parks the bot on the drop for good.
			if monster.carried.size() >= HungryContent.MAX_CARRIED:
				continue

			# Item drops are worth a detour even though they are worth no mass: a bot
			# that never picked one up would never exercise throwing.
			var item_score := HungryGrid.PICKUP_WORTH / (distance + HungryGrid.DISTANCE_BIAS)

			if item_score > look.snack_score:
				look.snack_score = item_score
				look.snack = at

			continue

		# Mass over distance, so a haunch across the map loses to a crumb underfoot but
		# beats a crumb on the far side of one.
		var score := world.field.mass_of(grid_id) / (distance + HungryGrid.DISTANCE_BIAS)

		if score > look.snack_score:
			look.snack_score = score
			look.snack = at

	return look


## Another monster's piece seen at [param at], [param distance] away: the nearest enemy,
## the nearest that can eat the head ([constant FEAR_RATIO]) and the nearest it can eat.
static func _judge(
	look: Look,
	other: HungryPiece,
	at: Vector2,
	distance: float,
	head: HungryPiece,
	monster: HungryMonster,
	eat_ratio: float
) -> void:
	if other == null or other.owner_id == monster.id:
		return

	if distance < look.enemy_distance:
		look.enemy_distance = distance
		look.enemy = other

	if other.mass() >= head.mass() * FEAR_RATIO:
		if distance < look.threat_distance:
			look.threat_distance = distance
			look.threat = at
	elif head.mass() >= other.mass() * eat_ratio:
		if distance < look.prey_distance:
			look.prey_distance = distance
			look.prey = other


## Pulls a target away from the arena edge.
##
## [b]A bot that steers into a wall stops, and a stopped bot is a bot that is eaten.[/b]
## The motor clamps a move at the boundary, so a target beyond it produces an aim that is
## fully engaged and a monster that does not move at all — which reads as a bot that has
## given up rather than one that has run out of room. This is also the state the
## interpolation check spent a while stuck in.
##
## The margin scales with the monster, because what matters is where its *edge* ends up.
static func _off_the_wall(target: Vector2, bounds: Rect2, radius: float) -> Vector2:
	var margin := radius + 40.0

	return Vector2(
		clampf(target.x, bounds.position.x + margin, bounds.end.x - margin),
		clampf(target.y, bounds.position.y + margin, bounds.end.y - margin)
	)


## Degrees a throw leaves off its target: between `bot_aim_floor` and `bot_aim_error`, to
## either side, drawn from the id and the quarter second so it is the same on a replay.
static func _throw_error(id: int, tick: int, skill: GSBotProfile) -> float:
	var h := GS2DScatter._hash(id, 0x7A + tick / 16)
	var size := lerpf(skill.aim_floor, skill.aim_error, GS2DScatter._unit(h))
	return size if GS2DScatter._unit(GS2DScatter._hash(h, 1)) < 0.5 else -size


## A stable value in [0, 1) for a bot, so eight of them do not orbit in lockstep.
static func _jitter(id: int) -> float:
	return GS2DScatter._unit(GS2DScatter._hash(id, 0xB07))
