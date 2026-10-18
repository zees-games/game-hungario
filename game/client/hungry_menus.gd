extends RefCounted

const HungryContent := preload("../hungry_content.gd")
const HungryNetBridge := preload("../net/hungry_net_bridge.gd")
const HungryWorld := preload("../hungry_world.gd")

## What is on screen besides the HUD and dot-menu's Escape menu: the Tab scoreboard's
## dressing and the menu's Loadout page.
##
## [b]The Escape menu is dot-menu's[/b] ([HungrySettings]): Loadout, Game, the stock pages,
## the Controls page over [HungryBindings], Help & commands and Leave, as in every game of
## the family. Until 2026-10-12 this file built dot-ui's pause, settings, controls and
## loadout screens over a `DotConfig` and a bindings file of their own; the settings and keys
## moved into the menu's document, and [HungrySettings] migrated the files.

## Dresses dot-menu's Tab board (the one [DotGameClient] holds on Tab) for this game: the
## columns, the world's own rank order, and the rows from the world. [param bridge] names the
## local player; null draws no "you".
##
## The rows are the world's, every monster, bots included, ranked by mass, with the server's
## time and ping merged in for the ones that are people. The roster the link feeds carries
## those; solo the platform's snapshot is empty and `prepare` fills the rows.
static func dress_board(board: DotMenuScoreboard, world: HungryWorld, bridge: HungryNetBridge) -> void:
	board.title_text = "Hungario"
	board.columns = [
		{"key": &"rank", "title": "#", "width": 0.4, "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"name", "title": "Monster", "width": 3.0},
		{"key": &"mass", "title": "Mass", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"pieces", "title": "Pieces", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"seconds", "title": "Time", "kind": DotMenuScoreboard.KIND_DURATION},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_with = func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("rank", 0)) < int(b.get("rank", 0))
	board.prepare = func(snap: Dictionary) -> void: _rows_from_world(snap, world, bridge)


## What the solo board is given to prepare: no roster, so no ping and no time.
static func solo_snapshot() -> Dictionary:
	return {"server": {"name": "Hungario"}, "players": []}


static func _rows_from_world(snap: Dictionary, world: HungryWorld, bridge: HungryNetBridge) -> void:
	if world == null:
		return
	var roster := {}
	for r in (snap.get("players", []) as Array):
		if r is Dictionary:
			roster[int(r.get("id", 0))] = r
	var me := bridge.local_player_id if bridge != null else 0
	var rows: Array = []
	var rank := 1
	for monster in world.leaderboard(20):
		var known: Dictionary = roster.get(monster.id, {})
		rows.append({
			"id": monster.id, "rank": rank, "name": monster.display_name,
			"mass": int(monster.mass()), "pieces": monster.piece_count(),
			"seconds": int(known.get("seconds", -1)), "ping": int(known.get("ping", -1)),
			"you": monster.id == me, "bot": not roster.is_empty() and known.is_empty(),
		})
		rank += 1
	snap["players"] = rows
	if not snap.has("server"):
		snap["server"] = {"name": "Hungario"}


## What you bring in: a starting throwable and a trait, as the Escape menu's first page.
##
## [b]The page never decides what is legal.[/b] It offers what
## [method DotLoadoutSchema.choices_for] says this player may take — which is the schema
## and their entitlements, and nothing else — and the server validates the result anyway.
## A page that filtered on its own would drift from the server the first time an unlock
## changed, and a page the server trusted would be a client choosing its own stats.
##
## [b]Live rows, not settings.[/b] A loadout is the server's to accept, so it is not stored in
## the player's document; each choice is sent as it is made ([method on_chosen]) and takes
## effect at the next spawn.
class LoadoutPage extends RefCounted:
	var schema: DotLoadoutSchema = null
	var entitlements: DotLoadoutEntitlements = null
	var page: DotMenuPage = null

	# What the rows read and write. A dictionary the rows' callables capture, never this
	# object: a row holding a callable bound to its own page's owner is a cycle of
	# RefCounteds, and the whole menu page leaked at exit (`sandbox`, 8 resources).
	# `picked` is slot id -> item id; `chosen` is `func(loadout)`, `redraw` is `func()`.
	var _state: Dictionary = {"picked": {}, "chosen": Callable(), "redraw": Callable()}
	var _rows: Dictionary = {}

	func _init(p_schema: DotLoadoutSchema) -> void:
		schema = p_schema
		# Nothing owned until a server says otherwise. Offering everything and letting the
		# server refuse it is a page that offers things it cannot deliver.
		entitlements = DotLoadoutEntitlements.none()
		page = DotMenuPage.make(&"loadout", "Loadout",
			"What you bring in. The server checks it, and it takes effect the next time you spawn.")
		var section := page.section("What you bring in")
		var state := _state
		var s := schema
		for slot in schema.ordered_slots():
			var id: StringName = slot.id
			var row := DotMenuRow.live_select(slot.display_name, "", [],
				func() -> Variant: return (state["picked"] as Dictionary).get(id, &""),
				func(value: Variant) -> void: LoadoutPage._choose(state, s, id, StringName(str(value)))
			).named(StringName("loadout_%s" % id))
			_rows[id] = row
			section.add(row)
		section.add(DotMenuRow.note("").described_by(
			func() -> String: return LoadoutPage.describe(state["picked"])
		).named(&"loadout_summary"))
		refresh()

	## [param fn] is `func(loadout: DotLoadout)`, called with each choice as it is made.
	func on_chosen(fn: Callable) -> void:
		_state["chosen"] = fn

	## [param fn] redraws the page after a choice, so the summary under it follows.
	func on_redraw(fn: Callable) -> void:
		_state["redraw"] = fn

	## Rebuilds the choices from the schema and what this player owns, keeping each slot's
	## choice where it is still offered.
	func refresh() -> void:
		var picked: Dictionary = _state["picked"]
		for slot in schema.ordered_slots():
			var options: Array = []
			var still := false
			for item in schema.choices_for(slot.id, entitlements):
				options.append([item.id, item.display_name])
				still = still or item.id == picked.get(slot.id, &"")
			(_rows[slot.id] as DotMenuRow).options = options
			if not still:
				picked[slot.id] = options[0][0] if not options.is_empty() else &""

	## Takes what a server says this player owns, and re-offers accordingly.
	func allow(owned: DotLoadoutEntitlements) -> void:
		entitlements = owned if owned != null else DotLoadoutEntitlements.none()
		refresh()

	## Shows a loadout the player already has, so the page opens on what they are wearing.
	func show_loadout(loadout: DotLoadout) -> void:
		if loadout == null:
			return
		for slot in schema.ordered_slots():
			var wanted := loadout.item_in(slot.id)
			for option in (_rows[slot.id] as DotMenuRow).options:
				if option[0] == wanted:
					_state["picked"][slot.id] = wanted

	func picked(slot_id: StringName) -> StringName:
		return (_state["picked"] as Dictionary).get(slot_id, &"")

	## The loadout the page currently describes.
	func current() -> DotLoadout:
		return LoadoutPage.loadout_of(schema, _state["picked"])

	func summary() -> String:
		return LoadoutPage.describe(_state["picked"])

	static func loadout_of(p_schema: DotLoadoutSchema, picked_items: Dictionary) -> DotLoadout:
		var loadout := DotLoadout.empty(p_schema.id)
		for slot in p_schema.ordered_slots():
			var item: StringName = picked_items.get(slot.id, &"")
			if item != &"":
				loadout.set_item(slot.id, item)
		return loadout

	## Says what the choice actually does, in the units the player sees. A trait called
	## "Nimble" tells nobody anything; the numbers come from [HungryContent], so the page
	## cannot describe a trade the game does not make.
	static func describe(picked_items: Dictionary) -> String:
		var trait_id: StringName = picked_items.get(HungryContent.SLOT_TRAIT, &"")
		return "%+.0f%% speed   %+.0f%% starting mass   %+.0f%% from food. Spawn holding one %s." % [
			(HungryContent.trait_speed(trait_id) - 1.0) * 100.0,
			(HungryContent.trait_mass(trait_id) - 1.0) * 100.0,
			(HungryContent.trait_food(trait_id) - 1.0) * 100.0,
			String(picked_items.get(HungryContent.SLOT_STARTER, &"")),
		]

	static func _choose(state: Dictionary, p_schema: DotLoadoutSchema, slot_id: StringName, item: StringName) -> void:
		var picked_items: Dictionary = state["picked"]
		if picked_items.get(slot_id, &"") == item:
			return
		picked_items[slot_id] = item
		var chosen: Callable = state["chosen"]
		if chosen.is_valid():
			chosen.call(LoadoutPage.loadout_of(p_schema, picked_items))
		var redraw: Callable = state["redraw"]
		if redraw.is_valid():
			redraw.call_deferred()


## The Loadout page over [param bridge]'s schema (the server's), or this build's own.
static func loadout_page(bridge: HungryNetBridge) -> LoadoutPage:
	return LoadoutPage.new(
		bridge.loadout_schema if bridge != null and bridge.loadout_schema != null
		else HungryContent.loadout_schema()
	)
