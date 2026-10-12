@tool
extends DotHud

const HungryBeacon := preload("hungry_beacon.gd")
const HungryContent := preload("../hungry_content.gd")
const HungryEvents := preload("../net/hungry_events.gd")
const HungryField := preload("../hungry_field.gd")
const HungryMonster := preload("../hungry_monster.gd")
const HungryNetBridge := preload("../net/hungry_net_bridge.gd")
const HungryTouch := preload("hungry_touch.gd")
const HungryWorld := preload("../hungry_world.gd")

## Mass, the leaderboard, the clock, what you are carrying, the feed and a minimap.
##
## Every widget is a dot-ui class bound to a game value. dot-ui does not know what a
## monster is; it knows how to draw a bar from a [Callable], a table from rows of
## dictionaries and a feed from coloured fragments, which is all any of this needs.
##
## The one exception is the minimap, and it is the same exception game-blob found: a
## minimap is world-specific, and a [Control] per monster would be a hundred nodes created
## and freed every time somebody split.


var world: HungryWorld = null
var bridge: HungryNetBridge = null

## Whose monster this is.
var player_id: int = 0

## `func() -> HungryMonster`. Who the camera is actually looking at, which is somebody
## else while this player is dead. Optional; without it the status line just says dead.
var watching_source: Callable = Callable()

var mass_bar: DotStatBar = null

## The mass bar's number, drawn by a [Label] over the bar instead of by the bar itself.
##
## [b]Because [DotStatBar] draws its text with no outline[/b], and white text with no
## outline over this game's pale sky is a smudge: "20 mass" was unreadable from the look
## pass on. A Label takes the HUD theme's outline (see [constant TEXT_OUTLINE]) like every
## other line here.
var mass_label: Label = null
var leaderboard: DotTableView = null
var feed: DotFeedView = null
## The round clock, dot-ui's: the time on its plate, or the match's state as the line under
## it while there is no time to count. See [method piece_theme] for its colours.
##
## [b]A [DotScoreStrip] with no scores[/b], because this is a free-for-all whose standings are
## the leaderboard. It was a centred `Label` writing "%d:%02d" with the floor, so a round with
## half a second left said 0:00; the strip rounds up. Decided 2026-10-11 (hud-pieces).
var strip: DotScoreStrip = null

## The countdown before a mode-vote ballot, directly under the round clock's plate.
##
## [b]Not the feed, although the feed is where this game's notices go.[/b] The feed holds
## five lines, and a countdown is one line a second: a five-second one would push out the
## chat line announcing the vote, and whatever anybody said, and leave a column of
## numbers. One label that changes in place says the same thing and costs nothing else.
var vote_label: Label = null
var carry_label: Label = null
var status_label: Label = null
var minimap: Minimap = null

## The on-screen split and throw buttons, on a device that wants them.
var touch: HungryTouch = null

## An administrator's `blind`, over the arena and under the rest of the HUD.
##
## [b]Under the widgets, on purpose.[/b] A blind takes the game away, not the player's
## bearings: the clock, the feed, their own mass and the chat box still say the round is
## going on and that they are in it, which is what makes it read as "an admin did this"
## rather than as a client that stopped drawing. [b]The minimap is the exception and goes
## under it[/b]: it is the arena in miniature, every monster's position on one square, and
## a blind that left it showing would be a blind a player could play straight through.
##
## Black rather than white. A white screen at full brightness is a thing a player can be
## hurt by in a dark room, and taking the picture away is the whole of the point.
var blind_overlay: ColorRect = null

## Seconds a blind takes to come down and to lift. Short, so it is unmistakably on, and
## not instant, so it reads as something done to the screen rather than a frame dropped.
const BLIND_FADE_SEC := 0.25

const BLIND_COLOUR := Color(0.01, 0.01, 0.015)

## [b]The leaderboard makes room for a ballot.[/b] The client shell draws every ballot — the
## server's game vote and this game's mode vote — as a panel in a column down the right-hand
## side from 110 px down, over whatever the game drew, and this board's rows 3 to 10 sat under
## it unread for the whole vote. The shell cannot reach into the game, so the game looks: every
## visible Control in dot-ui's [code]dot_hud_cover[/code] group is something on top of this HUD
## ([method covered_rect]). While one overlaps the board's corner, the board keeps the corner
## and shrinks to the rows that fit above it, without its header, the leader first and this
## player's own row last when they are not in the top few — the strip a shooter's HUD shows
## while a menu has the right of the screen. [b]Not moved left[/b]: beside a 360 px column it
## ran into the round clock at the top centre. [b]Not faded[/b]: who is winning is what a
## player is deciding a vote with. The group is read by [method DotHudPiece.covered_rect].

## The leaderboard's corner, in this HUD's own coordinates from the top-right.
## Pixels of dark outline behind every line of HUD text: the labels (through
## [method hud_theme]) and the feed.
##
## [b]An outline rather than a dark colour[/b], because the arena is a pale sky but the
## blind, the death screen and a cloud-free corner under a big monster are not, and an
## outlined light glyph reads over all of them. White with no outline, which is what the
## HUD drew before, vanishes into the sky (see docs/client.md, Rendering).
const TEXT_OUTLINE := 5
const TEXT_OUTLINE_COLOUR := Color(0.05, 0.07, 0.14, 0.9)

## Seconds left at which the clock turns the theme's `low` red.
const LOW_CLOCK_SEC := 10.0

## Where the strip starts, and where the vote countdown starts under its plate.
const STRIP_TOP := 10.0
const VOTE_TOP := STRIP_TOP + DotScoreStrip.H + 6.0

const BOARD_LEFT := -280.0
const BOARD_RIGHT := -16.0
const BOARD_TOP := 16.0
const BOARD_BOTTOM := 280.0
const BOARD_ROWS := 10

## Space kept between the shrunk board and what covers the rest of its corner.
const BOARD_GAP := 8.0

## Rows the board has room for while something covers its corner, or -1 while nothing does.
## 0 hides it: a frame too short for even one row.
var _board_room: int = -1

## When [member vote_label] stops showing its last second, in [method Time.get_ticks_msec].
var _vote_until_msec: int = 0

## How long a countdown second stays up without the next one. Over a second, so a tick
## arriving a little late over the wire does not blink the line off between numbers.
const VOTE_LINGER_MSEC := 1500

## How long the countdown's last second stays up. See [method vote_countdown].
const VOTE_LAST_MSEC := 1000


## Everybody's position on one small rectangle.
##
## Drawn rather than composed: a dot per monster is a `_draw` call, and the alternative is
## a node per monster created and freed as they split, burst and die.
##
## [b]Food is deliberately not on it.[/b] Eleven hundred crumbs on a 180-pixel square is a
## grey smear that tells nobody anything, and it is eleven hundred draw calls a frame.
class Minimap extends Control:
	var world: HungryWorld = null
	var player_id: int = 0

	var background := Color(0.038, 0.045, 0.082, 0.78)
	var border := Color(0.30, 0.44, 0.72, 0.60)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(180.0, 180.0)

	func _process(_delta: float) -> void:
		if not Engine.is_editor_hint():
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), background)
		draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.0)

		if world == null or world.arena == null:
			return

		var bounds := world.arena.bounds

		# Fruit, and only fruit. There are ten of them in a world of eleven hundred pieces
		# of food, they are worth going out of your way for, and ten dots is ten dots.
		# Drawing the food as well is a grey smear that tells nobody anything and eleven
		# hundred draw calls a frame.
		for grid_id in world.field.alive_ids():
			if HungryField.kind_of(grid_id) != HungryField.Kind.FRUIT:
				continue

			var at := world.field.position_of(grid_id)
			var local := Vector2(
				(at.x - bounds.position.x) / bounds.size.x,
				(at.y - bounds.position.y) / bounds.size.y
			) * size

			draw_circle(
				local, 2.0,
				HungryContent.FRUIT_COLOURS[int(world.field.fruit_kind_of(grid_id))]
			)

		for monster in world.monsters():
			if not monster.alive:
				continue

			var at := monster.centre()
			var local := Vector2(
				(at.x - bounds.position.x) / bounds.size.x,
				(at.y - bounds.position.y) / bounds.size.y
			) * size

			var dot := maxf(2.0, sqrt(monster.mass()) * 0.11)
			var colour := monster.colour

			if monster.id == player_id:
				colour = Color.WHITE
				dot = maxf(dot, 3.5)

			draw_circle(local, dot, colour)

			# An administrator's beacon, on the minimap as well as in the arena: the map is
			# where a player looks to find somebody, which is the beacon's whole job. A
			# ring that grows once a second, in the beacon's own colour.
			if monster.beacon:
				var t := fmod(Time.get_ticks_msec() / 1000.0, HungryBeacon.PERIOD_SEC) \
					/ HungryBeacon.PERIOD_SEC
				draw_arc(local, dot + 3.0 + 6.0 * t, 0.0, TAU, 20,
					Color(HungryBeacon.COLOUR, 1.0 - 0.7 * t), 2.0)

			# A split monster is drawn as a ring around its centroid, so a player can see
			# at a glance that the thing chasing them is in pieces.
			if monster.piece_count() > 1:
				draw_arc(
					local,
					clampf(monster.spread_radius() / bounds.size.x * size.x, 3.0, 40.0),
					0.0, TAU, 20, Color(colour.r, colour.g, colour.b, 0.5), 1.0
				)


func build(p_world: HungryWorld, p_bridge: HungryNetBridge, p_player_id: int) -> void:
	world = p_world
	bridge = p_bridge
	player_id = p_player_id
	theme = hud_theme()

	# First, so every widget added below draws over it. See [member blind_overlay].
	blind_overlay = ColorRect.new()
	blind_overlay.name = "Blind"
	blind_overlay.color = BLIND_COLOUR
	# Not anchored to this HUD's rect: `DotHud` insets itself by the safe area, and a
	# blind the size of the HUD leaves a frame of the arena showing round the edge — which
	# game-arena's first rendered blind did. Sized to the whole viewport in
	# [method present_blind] instead.
	blind_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blind_overlay.modulate.a = 0.0
	blind_overlay.visible = false
	add_child(blind_overlay)

	mass_bar = DotStatBar.new()
	mass_bar.name = "Mass"
	mass_bar.format = "%d"
	mass_bar.suffix = " mass"
	mass_bar.show_bar = true
	# The number is [member mass_label]'s job; see there for why.
	mass_bar.show_text = false
	mass_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mass_bar.offset_left = 20.0
	mass_bar.offset_top = -74.0
	mass_bar.offset_right = 300.0
	mass_bar.offset_bottom = -40.0
	mass_bar.ease_sec = 0.25
	add_child(mass_bar)
	mass_bar.bind(func() -> Variant:
		var monster := _me()
		return monster.mass() if monster != null else 0.0
	)
	mass_bar.max_source = func() -> Variant:
		return world.preset.win_mass if world != null and world.preset != null \
			else HungryContent.WIN_MASS

	mass_label = Label.new()
	mass_label.name = "MassText"
	mass_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mass_label.offset_left = 20.0
	mass_label.offset_top = -80.0
	mass_label.offset_right = 300.0
	mass_label.offset_bottom = -50.0
	mass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mass_label)

	carry_label = Label.new()
	carry_label.name = "Carrying"
	carry_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	carry_label.offset_left = 20.0
	carry_label.offset_top = -36.0
	carry_label.offset_right = 400.0
	carry_label.offset_bottom = -12.0
	carry_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(carry_label)

	leaderboard = DotTableView.new()
	leaderboard.name = "Leaderboard"
	leaderboard.max_rows = BOARD_ROWS
	leaderboard.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leaderboard.offset_left = BOARD_LEFT
	leaderboard.offset_top = BOARD_TOP
	leaderboard.offset_right = BOARD_RIGHT
	leaderboard.offset_bottom = BOARD_BOTTOM
	add_child(leaderboard)
	leaderboard.set_columns([
		{"key": &"rank", "title": "#", "width": 0.4, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"name", "title": "Monster", "width": 3.0},
		{"key": &"mass", "title": "Mass", "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])

	feed = DotFeedView.new()
	feed.name = "Feed"
	feed.alignment = HORIZONTAL_ALIGNMENT_LEFT
	feed.newest_last = true
	feed.outline_size = TEXT_OUTLINE
	feed.outline_colour = TEXT_OUTLINE_COLOUR
	feed.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Under dot-menu's "H Help" plate, which is in this corner (HungrySettings); at 16 the
	# plate sat on the feed's first line.
	feed.offset_left = 16.0
	feed.offset_top = 64.0
	feed.offset_right = 520.0
	feed.offset_bottom = 288.0
	add_child(feed)

	minimap = Minimap.new()
	minimap.name = "Minimap"
	minimap.world = world
	minimap.player_id = player_id
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -200.0
	minimap.offset_top = -200.0
	minimap.offset_right = -20.0
	minimap.offset_bottom = -20.0
	add_child(minimap)
	# Under the blind, which is the first child. See [member blind_overlay].
	move_child(minimap, 0)

	# Top centre, full width: the strip centres its plate on its own middle. The theme is
	# the piece's own, so the Labels' outline theme on this HUD stays theirs.
	strip = DotScoreStrip.new()
	strip.name = "Clock"
	strip.theme = piece_theme()
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = STRIP_TOP
	strip.offset_bottom = STRIP_TOP + DotScoreStrip.H + 28.0
	add_child(strip)

	vote_label = Label.new()
	vote_label.name = "VoteCountdown"
	vote_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Offsets, because `set_anchors_preset` does not set them, and a centred label with
	# none is a zero-width column the text overflows out of to the right. Wide enough for
	# "Runoff in 3…" at any font this HUD uses, and under the clock rather than over it.
	vote_label.offset_left = -200.0
	vote_label.offset_right = 200.0
	vote_label.offset_top = VOTE_TOP
	vote_label.offset_bottom = VOTE_TOP + 24.0
	vote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vote_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	add_child(vote_label)

	if HungryTouch.wanted():
		touch = HungryTouch.make()
		add_child(touch)
		touch.apply_safe_area()

	status_label = Label.new()
	status_label.name = "Status"
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_label.offset_top = -22.0
	status_label.offset_bottom = -4.0
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_label)


## Shows or hides the minimap. A player's setting.
func set_minimap_visible(shown: bool) -> void:
	if minimap != null:
		minimap.visible = shown


func follow(p_player_id: int) -> void:
	player_id = p_player_id

	if minimap != null:
		minimap.player_id = p_player_id


func _me() -> HungryMonster:
	return world.monster_for(player_id) if world != null else null


func _watched() -> HungryMonster:
	if not watching_source.is_valid():
		return null

	var value: Variant = watching_source.call()
	return value as HungryMonster if value is HungryMonster else null


# --- The feed --------------------------------------------------------------

func say(text: String, colour: Color = Color(0.88, 0.90, 0.94)) -> void:
	if feed != null:
		feed.add_text(text, colour)


## A chat line as dot-server delivered it.
##
## The payload is dot-server's and its shape is the server's business; everything read out
## of it is defaulted, because a server that sends a field this does not expect should
## produce a slightly plain line rather than an error.
func chat(payload: Dictionary) -> void:
	var who := String(payload.get("name", ""))
	var text := String(payload.get("text", ""))

	if text == "":
		return

	if who == "":
		say(text, Color(0.62, 0.78, 1.0))
		return

	feed.add_line([
		{"text": "%s: " % who, "colour": Color(0.72, 0.84, 1.0)},
		{"text": text, "colour": Color(0.92, 0.93, 0.95)},
	])


## Something happened to somebody. Driven from [signal HungryNetBridge.cue].
func note(kind: int, data: Dictionary) -> void:
	match kind:
		HungryEvents.Kind.DIED:
			feed.add_line([
				{"text": _name_of(int(data.get("second", 0))), "colour": Color(1.0, 0.85, 0.4)},
				{"text": " devoured ", "colour": Color(0.7, 0.72, 0.76)},
				{"text": _name_of(int(data.get("first", 0))), "colour": Color(0.95, 0.55, 0.5)},
			])

		HungryEvents.Kind.BURST:
			feed.add_line([
				{"text": _name_of(int(data.get("second", 0))), "colour": Color(1.0, 0.85, 0.4)},
				{"text": " burst ", "colour": Color(0.7, 0.72, 0.76)},
				{"text": _name_of(int(data.get("first", 0))), "colour": Color(0.95, 0.55, 0.5)},
				{"text": " into %d" % int(data.get("extra", 0)), "colour": Color(0.7, 0.72, 0.76)},
			])


func _name_of(id: int) -> String:
	var monster := world.monster_for(id) if world != null else null

	if monster != null:
		return monster.display_name

	return "somebody" if id == 0 else "Player %d" % id


## One second of the countdown before a mode-vote ballot. Driven from
## [signal HungryNetBridge.vote_cue_received].
func vote_countdown(seconds_left: int, runoff: bool) -> void:
	if vote_label == null:
		return

	vote_label.text = "%s in %d…" % ["Runoff" if runoff else "Mode vote", seconds_left]
	# The last second lingers exactly a second: nothing follows it but the ballot, and the
	# half second more read "Mode vote in 1…" under a ballot already open (a game_vote_all frame).
	_vote_until_msec = Time.get_ticks_msec() + (VOTE_LAST_MSEC if seconds_left <= 1 else VOTE_LINGER_MSEC)


# --- Refreshing ------------------------------------------------------------

## Rebuilds the leaderboard rows.
##
## Called on a timer rather than every frame: it rebuilds a table of [Label]s, and doing
## that sixty times a second to show ten numbers that change slowly is most of a frame's
## layout budget for no benefit.
func refresh_leaderboard() -> void:
	if leaderboard == null or world == null:
		return

	var rows: Array[Dictionary] = []
	var rank := 1

	# The authority's ranking when there is one: a client only knows about the monsters
	# interest management has told it about, so ranking locally would put whoever happens
	# to be nearby at the top of the board.
	var authoritative: Array = bridge.board if bridge != null else []

	if not authoritative.is_empty():
		for row in authoritative:
			var id := int((row as Dictionary).get("id", 0))
			rows.append({
				&"rank": rank,
				&"name": _name_of(id),
				&"mass": int((row as Dictionary).get("mass", 0)),
				"highlight": id == player_id,
				"colour": HungryContent.colour_for(id),
			})
			rank += 1
	else:
		for monster in world.leaderboard(10):
			rows.append({
				&"rank": rank,
				&"name": monster.display_name,
				&"mass": int(monster.mass()),
				"highlight": monster.id == player_id,
				"colour": monster.colour,
			})
			rank += 1

	if _board_room > 0:
		rows = _top_and_me(rows, _board_room)

	leaderboard.set_rows(rows)


## The first [param room] rows, with this player's own row last in place of the one it pushes
## out when they are not among them. Ranks are kept, so "7  you" says where they stand.
static func _top_and_me(rows: Array[Dictionary], room: int) -> Array[Dictionary]:
	if rows.size() <= room:
		return rows

	var out: Array[Dictionary] = rows.slice(0, room)
	var mine := -1

	for i in rows.size():
		if bool(rows[i].get("highlight", false)):
			mine = i
			break

	if mine >= room:
		out[room - 1] = rows[mine]

	return out


# --- Making room -----------------------------------------------------------

## Everything drawn over this HUD by somebody else — the shell's ballot panels — as one
## rect in this HUD's own coordinates, or an empty rect when nothing is. See [member _board_room].
##
## [b]Through the canvas transforms, both ways.[/b] The panel is on the shell's canvas layer
## and this HUD is inset by the safe area and scaled by the interface scale, so a rect read
## as-is is in the wrong space on any phone and at any scale but one.
##
## dot-ui's reading of the group ([method DotHudPiece.covered_rect]), which this HUD used to
## do by hand: the same transforms, and the same skip of this HUD's own children.
func covered_rect() -> Rect2:
	return DotHudPiece.covered_rect(self)


## Shrinks the board to the rows that fit above whatever covers its corner, and gives it the
## corner back when that goes. Every frame: one group lookup, and a rebuild only on a change.
func make_room() -> void:
	if leaderboard == null:
		return

	var home := Rect2(
		Vector2(size.x + BOARD_LEFT, BOARD_TOP),
		Vector2(BOARD_RIGHT - BOARD_LEFT, BOARD_BOTTOM - BOARD_TOP)
	)
	var cover := covered_rect()
	var room := -1

	if cover.has_area() and cover.intersects(home):
		var row := _board_row_height()
		var above := cover.position.y - BOARD_GAP - BOARD_TOP
		room = clampi(int(floor((above + row.y) / (row.x + row.y))), 0, BOARD_ROWS)

	if room == _board_room:
		return

	_board_room = room
	leaderboard.show_header = room < 0
	leaderboard.max_rows = BOARD_ROWS if room < 0 else room
	leaderboard.visible = room != 0
	leaderboard.offset_bottom = BOARD_BOTTOM if room < 0 else maxf(cover.position.y - BOARD_GAP, BOARD_TOP)
	refresh_leaderboard()


## Rows the board shows while shrunk, or -1 when it has its corner. For a check and a bug report.
func board_room() -> int:
	return _board_room


## A row's height and the gap between rows, measured from the board's own first row
## (dot-ui keeps its rows container named `Grid` for exactly this kind of reader), so a theme
## or an interface scale that changes the font changes how many rows fit.
func _board_row_height() -> Vector2:
	var grid := leaderboard.get_node_or_null(^"Grid") as Container

	if grid != null and grid.get_child_count() > 0:
		var first := grid.get_child(0) as Control

		if first != null:
			var height := first.get_combined_minimum_size().y

			if height > 0.0:
				return Vector2(height, float(grid.get_theme_constant(&"separation")))

	return Vector2(26.0, 4.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or world == null:
		return

	present_blind(delta)
	make_room()
	_refresh_clock()
	_refresh_vote()
	_refresh_carry()
	_refresh_mass()
	_refresh_status()


## Fades [member blind_overlay] toward whether this player is blinded.
##
## Read off the local monster rather than pushed by anybody, because the flag arrives in a
## snapshot on a networked client and is set directly offline, and a HUD that had to be
## told would need telling from two places. Public so a check can step it.
##
## [b]This player's, not the watched one's, and dead or alive.[/b] A blinded player who is
## eaten spectates somebody else, and a blind that lifted for that would be a blind any
## player could end by feeding themselves to the nearest monster.
func present_blind(delta: float) -> void:
	if blind_overlay == null:
		return

	var me := _me()
	var want := 1.0 if me != null and me.blinded else 0.0
	blind_overlay.modulate.a = move_toward(
		blind_overlay.modulate.a, want, maxf(delta, 0.0) / BLIND_FADE_SEC
	)
	blind_overlay.visible = blind_overlay.modulate.a > 0.0

	if blind_overlay.visible and is_inside_tree():
		# The whole viewport, in this HUD's own coordinates — whatever the safe area and
		# the interface scale did to where this HUD starts.
		var inverse := get_global_transform().affine_inverse()
		blind_overlay.position = inverse * Vector2.ZERO
		blind_overlay.size = inverse.basis_xform(get_viewport_rect().size)


func _refresh_clock() -> void:
	if strip == null:
		return

	var behaviour := bridge.match_behaviour() if bridge != null else null
	var remaining := -1.0
	var state := ""

	if behaviour != null:
		remaining = behaviour.seconds_remaining(
			world.current_tick(), world.tick_rate
		)
		state = behaviour.state_name()
	elif world.match_node != null:
		remaining = world.match_node.seconds_remaining()
		state = String(DotMatch.State.keys()[world.match_node.state])

	if remaining < 0.0:
		# No time to count (warmup, between rounds): no plate, the state's words under it.
		strip.show_clock("", false, state.capitalize())
	else:
		strip.show_clock(DotScoreStrip.clock_text(remaining), remaining <= LOW_CLOCK_SEC)


func _refresh_vote() -> void:
	if vote_label != null and vote_label.text != "" and Time.get_ticks_msec() > _vote_until_msec:
		vote_label.text = ""


func _refresh_mass() -> void:
	if mass_label == null:
		return

	var monster := _me()
	# Not lagged like the bar: the number is the current value (DotStatBar's rule).
	mass_label.text = "%d mass" % int(monster.mass() if monster != null else 0.0)


## The clock's colours in this game's palette: a deep navy plate, so the white time reads
## over the pale pastel sky, ringed in the same dark outline every Label here has
## ([constant TEXT_OUTLINE_COLOUR], from ab14971). Static so a render tool can use it.
static func piece_theme() -> Theme:
	var t := Theme.new()
	var type := DotHudPiece.THEME_TYPE
	t.set_color(&"plate", type, Color(0.07, 0.10, 0.22, 0.72))
	t.set_color(&"plate_edge", type, Color(1.0, 1.0, 1.0, 0.22))
	t.set_color(&"ink", type, TEXT_OUTLINE_COLOUR)
	t.set_color(&"text", type, Color(0.97, 0.98, 1.0))
	t.set_color(&"highlight", type, Color(1.0, 0.85, 0.40))
	t.set_color(&"low", type, Color(1.0, 0.36, 0.30))
	return t


## The theme every [Label] in this HUD inherits: an outline, so text is readable over
## the pale arena. The leaderboard's cells are Labels and inherit it too.
static func hud_theme() -> Theme:
	var out := Theme.new()
	out.set_constant(&"outline_size", &"Label", TEXT_OUTLINE)
	out.set_color(&"font_outline_color", &"Label", TEXT_OUTLINE_COLOUR)
	return out


func _refresh_carry() -> void:
	if carry_label == null:
		return

	var monster := _me()

	if monster == null or monster.carried.is_empty():
		carry_label.text = "carrying nothing"

		if touch != null:
			touch.show_carried(PackedStringArray())

		return

	var names := monster.carried_names()
	carry_label.text = "carrying  " + "  ".join(names)

	if touch != null:
		touch.show_carried(names)


func _refresh_status() -> void:
	if status_label == null:
		return

	var monster := _me()

	if monster == null:
		status_label.text = "joining…"
		return

	if not monster.alive:
		# Who they are watching, because a dead player staring at somebody else's monster
		# with no explanation reasonably concludes the game has broken.
		var watched := _watched()

		status_label.text = (
			"eaten — watching %s" % watched.display_name
			if watched != null and watched != monster
			else "eaten — respawning"
		)
		return

	if monster.piece_count() > 1:
		status_label.text = "%d pieces — let go of the mouse to gather" \
			% monster.piece_count()
		return

	status_label.text = ""


func describe() -> Dictionary:
	return {
		"player": player_id,
		"rows": leaderboard.row_count() if leaderboard != null else 0,
		"board_room": _board_room,
		"feed": feed.line_count() if feed != null else 0,
		"clock": strip.describe() if strip != null else null,
		"vote": vote_label.text if vote_label != null else "",
		"blind": blind_overlay.modulate.a if blind_overlay != null else 0.0,
		"touch": touch.describe() if touch != null else null,
	}
