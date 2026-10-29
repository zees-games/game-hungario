extends Node

const HungryModule := preload("hungry_module.gd")
const HungryEvents := preload("net/hungry_events.gd")

## What plays next, and who decides.

const CHANNEL := "hungry.maps"

## Where a server owner configures this game's vote. Empty skips the file.
const CONFIG_PATH := "user://cfg/hungry_vote.json"

## The key in the running game's descriptor metadata an operator's overrides are read
## from — [code]metadata: map_vote:[/code] in a delivered game's [code]game.yml[/code].
const METADATA_KEY := "map_vote"


## The vote picked something and the server should change to it.
signal change_due(game_id: StringName)

## Something a player should be told: the ballot, the tally, a warning.
signal announced(line: String)

## Something for every client to hear or count: a [code]cue_*[/code] id, or a second of
## the countdown before a ballot. One of the two is empty or zero. The module puts it on
## the wire as [constant HungryEvents.Kind].VOTE.
signal cue_due(cue: StringName, seconds_left: int, runoff: bool)


var catalogue: DotMapCatalogue = null
var rotation: DotMapRotation = null
var director: DotVoteDirector = null

## dot-server's game manager, which is what a vote actually applies through.
var games: Object = null

## How many people are playing. Set by [HungryModule]; a vote's every threshold needs it.
var player_count_fn: Callable = Callable()

## Whether a voter is an admin.
var is_admin_fn: Callable = Callable()

## `func() -> DotMatch`. The match being played now, for its round ends. A callable because
## a mode change builds a new world, and a new world a new match.
var match_fn: Callable = Callable()

## `func() -> int`. The leading score: the biggest monster's mass, which is what a round
## here is won on. Reported to the director for `trigger: score_limit`.
var score_fn: Callable = Callable()

var commands: DotVoteCommands = null

## The server's maps.yml, or null when there is none. See [method load_rotation].
var rotation_file: DotMapRotationFile = null

## Where [member rotation_file] was read from, or "" when there was no file.
var rotation_source: String = ""

## The file that says which modes rotate: dot-map's [DotMapRotationFile] format, looked for in
## the `--config` directory first. A test sets it empty. Empty, or no file, rotates every mode
## the catalogue holds, which is what this game always did.
const ROTATION_FILE := "cfg/maps.yml"
var rotation_stem: String = ROTATION_FILE

## [code]func(state: Dictionary)[/code]: the ballot as a client draws it, sent whenever it
## changes. The host points it at the client shell (a dot-server notice), which draws a
## menu a player picks from with a number key or a click. Unset sends nothing.
var ballot_fn: Callable = Callable()

## [code]func(voter: StringName) -> Dictionary[/code]: a voter's name and avatar URL.
var people_fn: Callable = Callable()

## What [member ballot_fn] is fed from. Polled once per [method advance].
var feed: DotVoteBallotFeed = null

## What dot-vote's commands are called here. `vote` rather than `votefor`, so the command
## is the token this game's own wire already sends.
const COMMAND_NAMES := {"vote": "vote"}

var _match: DotMatch = null

## The file [method setup] layers over the defaults. A test sets it empty.
var config_path: String = CONFIG_PATH


## dot-server's games, kept to the ones [member keep_fn] says are this game's modes.
class ModeSource extends DotVoteGameSource:
	## [code]func(id: StringName) -> bool[/code]: whether a game id is one of the modes.
	var keep_fn: Callable = Callable()

	func choices() -> Array[DotVoteChoice]:
		var out: Array[DotVoteChoice] = []

		for choice in super.choices():
			if not keep_fn.is_valid() or bool(keep_fn.call(choice.id)):
				out.append(choice)

		return out



## The modes, as maps.
static func map_catalogue() -> DotMapCatalogue:
	var out := DotMapCatalogue.new()

	# Built from the game descriptors rather than beside them: scene path, name and id are declared once in [method HungryModule.game_descriptors].
	# What is new is `min_players`, which a `DotGameDescriptor` does not record and a ballot needs.
	for descriptor in HungryModule.game_descriptors():
		var added := out.add(_map(descriptor, int(MINIMUMS.get(descriptor.game_id, 1))))

		if not added.ok:
			# Loud, because a catalogue that silently holds nothing is a shape this family keeps finding: `DotMapCatalogue.add` validates and refuses.
			DotLog.error(CHANNEL, "a mode was refused by the map catalogue", {
				"game": descriptor.game_id, "why": added.error.message,
			})

	return out


## How many people a mode needs before it is worth offering.
const MINIMUMS := {
	"hungry_gauntlet": 3,
}


static func _map(descriptor: DotGameDescriptor, min_players: int) -> DotMapDef:
	var out := DotMapDef.new()
	out.id = StringName(descriptor.game_id)
	out.display_name = descriptor.display_name
	# [b]A semantic version or a default, because `validate()` refuses anything else.[/b]
	out.version = descriptor.version if DotSemVer.parse(descriptor.version).valid \
		else "1.0.0"
	out.kind = DotMapDef.KIND_ARENA
	out.min_players = min_players
	out.max_players = descriptor.max_players
	# The same scene dot-server loads, read from the same declaration.
	out.scene_path = descriptor.scene
	out.meta = {"vote": {"display": descriptor.display_name}}
	return out


## The vote's policy. Fifty-five settings and these are the ones this game changes.
static func vote_rules() -> DotVoteRules:
	var rules := DotVoteRules.new()
	rules.enabled = true
	rules.trigger = DotVoteRules.Trigger.TIME_LIMIT
	# A mode is half an hour rather than the forty-five minutes a map elsewhere gets. A
	# round here is a few minutes; a limit that outlasted a dozen of them would be a limit
	# nobody ever saw fire.
	rules.duration_sec = 1800.0
	rules.vote_lead_sec = 150.0
	rules.vote_cooldown_sec = 60.0
	rules.vote_duration_sec = 25.0
	# Four modes with `include_current` off, so three others and an extend is exactly a
	# full ballot. A ballot of six would be a ballot of four and two blanks.
	rules.max_options = 4
	rules.include_extend = true
	rules.include_current = false
	rules.method = DotVoteRules.Method.PLURALITY
	rules.tie_break = DotVoteRules.TieBreak.BALLOT_ORDER
	# Off, so the ordinary tie-break runs: with it on "extend" is erased from a tie, but every pseudo-option sorts last so `BALLOT_ORDER` hands the tie to the new thing anyway.
	# Set explicitly so changing it is a visible change.
	rules.extend_needs_majority = false
	rules.rtv_enabled = true
	rules.rtv_fraction = 0.6
	rules.rtv_min_players = 1
	# [b]Measured against elapsed time, which is the other bug dot-vote found.[/b]
	rules.rtv_delay_sec = 120.0
	rules.nominations_enabled = true
	rules.nominations_per_player = 1
	# On, which makes `MOST_NOMINATED` mean anything: dot-vote now allows a second nomination, so counts differ and a ballot can show which mode people want.
	rules.nomination_seconding = true
	rules.cooldown = 1
	rules.cooldown_mode = DotVoteRules.Cooldown.PLAYS
	rules.apply = DotVoteRules.Apply.END_OF_ROUND
	rules.apply_delay_sec = 5.0

	# Five seconds' warning, counted down on every client, before a ballot opens over a
	# chase. Shorter than a shooter's ten: a round here is a few minutes and the ballot
	# changes nothing until it ends, so the warning is for finishing a bite, not a fight.
	rules.vote_warning_sec = 5.0
	rules.runoff_warning_sec = 3.0

	# The ids the client's catalogue plays, from the wire's one copy of them. dot-vote
	# ships every cue empty and names no audio class.
	rules.cue_vote_start = HungryEvents.CUE_VOTE_START
	rules.cue_vote_end = HungryEvents.CUE_VOTE_END
	rules.cue_warning = HungryEvents.CUE_VOTE_WARNING
	rules.cue_runoff_warning = HungryEvents.CUE_VOTE_WARNING
	rules.cue_countdown = HungryEvents.CUE_VOTE_COUNT
	return rules



func setup(p_games: Object) -> DotResult:
	games = p_games

	catalogue = map_catalogue()
	rotation = DotMapRotation.of(catalogue)
	rotation.mode = DotMapRotation.Mode.SEQUENTIAL
	# One play of cooldown over four maps: enough that the same mode never plays twice in
	# a row, and not so much that a two-mode server runs out of things to pick.
	rotation.cooldown = 1
	load_rotation()

	var rules := vote_rules()
	var problem := rules.validate()

	if not problem.ok:
		return problem.wrap("The vote rules are not usable")

	# The owner's layers over the defaults that just validated, BEFORE the mode timer
	# below is built from them — so what an owner sets reaches `timeleft` too. Refused
	# whole, loudly and not fatally, when the result does not validate.
	var layered := rules.layer_over_defaults(
		config_path, DotVoteGameSource.running_game_metadata(METADATA_KEY)
	)

	if not layered.ok:
		DotLog.error(CHANNEL, "the vote configuration is not usable; using the defaults", {
			"path": config_path,
			"why": layered.error.message,
			"detail": layered.error.detail,
		})

	director = DotVoteDirector.new()
	director.name = "Vote"
	director.rules = rules
	# The source is dot-server's games, not dot-map's catalogue: `DotVoteGameSource.apply` calls `change_game`, which is what changes the game.
	# Narrowed to this game's modes, since a server running several games would otherwise ballot the others.
	var modes := ModeSource.new()
	modes.manager = games
	var known := catalogue
	# In rotation as well as known: a mode maps.yml leaves out is never on a ballot, never
	# nominated and never what `next` answers, though `changegame` can still load it.
	modes.keep_fn = func(id: StringName) -> bool:
		return known != null and known.has(id) and in_rotation(id)
	director.source = modes
	director.auto_apply = true
	# Off: the director and the host's `game_loaded` (which also fires for an operator's `changegame`) would both announce a change,
	# double-counting the play history and halving the "played in the last N" cooldown.
	director.begin_on_apply = false
	# Off: the module advances it once per world tick; with it on every clock in the vote counted twice.
	director.self_advance = false
	director.register_service = false
	director.player_count_fn = _player_count
	director.is_admin_fn = _is_admin
	director.announce_fn = func(line: String) -> void: announced.emit(line)
	# Every round's end is reported (see _on_round_ended), so a time limit can wait for the
	# round in progress under `time_up: finish_round`.
	director.round_based = true
	# Set by name and only where it exists: a delivered pack runs on the shell's dot-vote, and one older than API 3 has no `round_in_progress_fn`, whose name would fail the pack's parse.
	if "round_in_progress_fn" in director:
		director.set(&"round_in_progress_fn", round_in_progress)
	add_child(director)

	feed = DotVoteBallotFeed.of(director, func(state: Dictionary) -> void:
		if ballot_fn.is_valid():
			ballot_fn.call(state)
	)
	feed.title = "Vote for the next mode"
	feed.people_fn = func(voter: StringName) -> Dictionary:
		return people_fn.call(voter) if people_fn.is_valid() else {}

	director.change_due.connect(func(id: StringName, _choice: DotVoteChoice) -> void:
		change_due.emit(id)
	)

	# Two signals, two messages: dot-vote emits a countdown second and that second's cue
	# separately, and merging them here would be this file deciding which is which.
	director.cue.connect(func(id: StringName) -> void: cue_due.emit(id, 0, false))
	director.countdown_tick.connect(func(seconds_left: int, runoff: bool) -> void:
		cue_due.emit(&"", seconds_left, runoff)
	)

	# No second clock: the vote's own clock hears extends, kept-mode ballots and stops, and dot-vote's `timeleft` already reads it.

	return DotResult.success(null)


## Somebody is playing something. Both the rotation and the vote are told.
func note_playing(game_id: StringName) -> void:
	if rotation != null:
		rotation.note_played(game_id)

	if director != null:
		director.begin(game_id)

	_bind_match()


func advance(delta: float) -> void:
	if director != null:
		director.advance(delta)
		_report_score()

	if feed != null:
		feed.poll()


## The leading score, once a tick and only when it moved.
func _report_score() -> void:
	if not score_fn.is_valid():
		return

	var top := int(score_fn.call())

	# Against the clock's own memory rather than a copy here: the clock zeroes it on every
	# restart — a new map, an extend, a ballot that kept the map — and a cached copy would
	# then hold back a score that had not moved but that the clock had forgotten.
	if top == director.clock.top_score:
		return

	director.note_score(top)


## Follows the match a round ends in. Rebound on every mode change, because a new mode is
## a new world with a new match, and a connection to the freed one would never fire.
func _bind_match() -> void:
	var node: DotMatch = match_fn.call() if match_fn.is_valid() else null

	if node == _match:
		return

	if (
		_match != null and is_instance_valid(_match)
		and _match.round_ended.is_connected(_on_round_ended)
	):
		_match.round_ended.disconnect(_on_round_ended)

	_match = node

	if _match != null:
		_match.round_ended.connect(_on_round_ended)


## Whether a round is being played now, for `time_up: finish_round`: warmup and the gap between rounds have nothing to play out, so a limit there changes the mode at once.
## Asked of [member match_fn] every time because a mode change replaces the match; no match is "cannot tell".
func round_in_progress() -> bool:
	var node: DotMatch = match_fn.call() if match_fn.is_valid() else null
	return node == null or not is_instance_valid(node) or node.is_live()


## A round ended. This game's rules apply a vote's winner at the end of a round, and until
## this was connected nothing told the director one had — so the winner waited for the
## clock, and a round-limit or round-end trigger could never fire at all.
func _on_round_ended(_round: int, _winner: int, _outcome: DotMatchRules.Outcome) -> void:
	if director != null:
		director.note_round_end()


## dot-vote's commands, on [param host] — the module, so they go when it does.
func install_commands(host: Object) -> DotResult:
	if director == null:
		return DotResult.fail(DotError.CODE_STATE, "There is no vote to command.")

	commands = DotVoteCommands.new()
	commands.director = director
	commands.names = COMMAND_NAMES.duplicate()
	# maps.yml's `commands:` block, so an operator renames rtv and friends without this game
	# naming any of them. Read on every bind, so a reloaded file reaches it.
	commands.spec_fn = func() -> Dictionary:
		return rotation_file.commands() if rotation_file != null else {}
	commands.voter_fn = func(ctx: Object) -> StringName:
		var session: Variant = ctx.get("session")

		if session is Object and (session as Object).get("userid") != null:
			return StringName(str((session as Object).get("userid")))

		return &"console"

	var bound := commands.bind(host)

	if feed != null:
		feed.command = commands.command_name("vote")

	return bound


## Reads maps.yml and applies it; called at setup and again by `hungry_maps_reload`.
func load_rotation() -> DotResult:
	var dir := DotMapRotationFile.config_dir_arg()
	var found := DotMapRotationFile.find(rotation_stem, dir)

	if found == "" and rotation_stem != "" and (dir != "" or rotation_stem != ROTATION_FILE):
		# The default name being absent is an install with no maps.yml; a name or a directory
		# somebody chose that finds nothing is a typo they would otherwise never hear about.
		DotLog.warn(CHANNEL, "the map rotation file was not found; every mode rotates", {
			"file": rotation_stem, "config_dir": dir,
		})

	var paths := PackedStringArray()

	if found != "":
		paths.append(found)

	var read := DotMapRotationFile.load_files(paths, "game-hungario")

	if not read.ok:
		DotLog.error(CHANNEL, "the map rotation file could not be read; every mode rotates", {
			"why": read.error.message,
		})
		rotation_file = null
		rotation_source = ""
		apply_rotation()
		return read

	rotation_file = read.value
	rotation_source = ", ".join(rotation_file.sources)

	if rotation_file.has_rotations():
		DotLog.info(CHANNEL, "the map rotation file", {
			"paths": rotation_source, "active": rotation_file.active_name(),
		})

	apply_rotation()
	return read


## Marks every mode in or out of rotation from the file. No file, or an empty rotation, keeps
## every mode in (this game has no kind it keeps out), and a rotation never empties the server.
func apply_rotation() -> void:
	if catalogue == null or rotation == null:
		return

	if rotation_file != null and rotation_file.has_rotations():
		rotation_file.fallback_in = func(_map: DotMapDef) -> bool: return true
		rotation_file.apply(rotation)
		return

	rotation.order = []

	for map: DotMapDef in catalogue.maps:
		map.in_rotation = true


## `sv_map_rotation <name>`: the live switch to another named rotation in the file.
func switch_rotation(rotation_name: String) -> DotResult:
	if rotation_file == null:
		return DotResult.fail(DotError.CODE_STATE, "There is no maps.yml to switch rotations in.")

	return rotation_file.switch(rotation, rotation_name)


## Whether a mode is in the rotation. One the catalogue does not hold is not.
func in_rotation(game_id: StringName) -> bool:
	var map := catalogue.get_map(game_id) if catalogue != null else null
	return map != null and map.in_rotation and map.enabled


## What would play next with nobody voting.
func next_in_rotation() -> StringName:
	if director != null:
		var voted := director.next_in_rotation()

		if voted != &"":
			return voted

	var chosen := rotation.choose(_player_count()) if rotation != null else null
	return chosen.id if chosen != null else &""


## Whether a mode may be offered at the current head count.
func available(game_id: StringName) -> bool:
	var map := catalogue.get_map(game_id) if catalogue != null else null
	return map == null or map.available_for(_player_count())


func _player_count() -> int:
	return int(player_count_fn.call()) if player_count_fn.is_valid() else 0


func _is_admin(voter: StringName) -> bool:
	return bool(is_admin_fn.call(voter)) if is_admin_fn.is_valid() else false


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	# The vote's clock: the one that ends a mode, and the one an extend moves.
	if director != null:
		out.append("map time     %s" % director.clock.formatted_remaining())
		out.append_array(director.describe_lines())

	return out
