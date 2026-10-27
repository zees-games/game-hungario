extends DotGameCheckSuite

const HungryLayout := preload("../game/hungry_layout.gd")
const HungryWorkshop := preload("../game/hungry_workshop.gd")
const HungryWorld := preload("../game/hungry_world.gd")

## What a subscribed map pack does to this game's solo map list, against a fixture
## [DotContentIndex] and never the process's shared one: a solo map is listed as Name [Pack],
## online lists none, a map kind the game does not accept is left out, the game's own ids win,
## a bad document is refused, and a chosen pack map builds a world with its rocks in it.
##
## [codeblock]
## godot --headless --path . res://examples/headless_workshop.tscn
## [/codeblock]

const SECTIONS := 5
const DIR := "user://ws_fixture/"

var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-hungario — Workshop maps")
	_write_fixtures()
	_test_accepts()
	_test_solo()
	_test_online()
	_test_ids_and_refused()
	await _test_play()

	print("")
	_check(_completed == _entered and _entered == SECTIONS,
		"every section ran to its last line (%d of %d, %d expected)" % [_completed, _entered, SECTIONS])
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	get_tree().quit(1 if _failed > 0 or _completed != SECTIONS else 0)


func _write_fixtures() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_write("ruin.json", '{"id": "ruin", "name": "Ruin", "preset": "frenzy", "blocks": [[0.5, 0.0, 0.1], [-0.5, 0.2, 0.1], [0.0, -0.6, 0.08]]}')
	_write("bad.json", '{"id": "bad", "name": "Bad", "blocks": [[0.5, 0.0]]}')
	_write("run.json", '{"id": "run", "name": "Run", "blocks": []}')
	_write("classic.json", '{"id": "classic", "name": "Not Classic", "blocks": []}')


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(DIR + file, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _index(session: StringName) -> DotContentIndex:
	var index := DotContentIndex.new()
	index.set_session(session)
	var added := index.add_pack({
		"content_id": "fixture/ruins", "version": "1.0.0", "prefix": DIR,
		"session": session, "source": &"subscription",
		"provides": {"schema": 1, "title": "Fixture Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": "ruin", "name": "Ruin", "scene": "ruin.json", "map_kind": "arena"},
			{"kind": "map", "id": "bad", "name": "Bad", "scene": "bad.json", "map_kind": "arena"},
			{"kind": "map", "id": "run", "name": "Run", "scene": "run.json", "map_kind": "surf"},
			{"kind": "map", "id": "classic", "name": "Not Classic", "scene": "classic.json", "map_kind": "arena"},
		]},
	})
	_check(added.ok, "the fixture pack registers for %s" % session)
	return index


func _names(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in rows:
		out.append(str(row["name"]))
	return out


func _test_accepts() -> void:
	_entered += 1
	print("")
	print("what the game accepts")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://provides.json"))
	var accepts: Dictionary = (parsed as Dictionary).get("accepts", {})
	_check(accepts.get("kinds") == ["map"], "only maps (no weapons: the loadout reads no catalogue)", str(accepts))
	_check(PackedStringArray(accepts.get("map_kinds", [])) == HungryWorkshop.accepted(),
		"map kinds match HungryWorkshop.accepted()", str(accepts))
	_completed += 1


func _test_solo() -> void:
	_entered += 1
	print("")
	print("solo")
	var shop := HungryWorkshop.new()
	shop.follow(_index(DotContentIndex.SESSION_SOLO))
	var names := _names(shop.rows())
	_check(names.has("Ruin [Fixture Pack]"), "the accepted map is listed as Name [Pack]", str(names))
	_check(not names.has("Run [Fixture Pack]"), "a map kind the game does not accept is filtered out")
	_check(not names.has("Bad [Fixture Pack]"), "a bad document is listed nowhere")
	_completed += 1


func _test_online() -> void:
	_entered += 1
	print("")
	print("online")
	var index := _index(DotContentIndex.SESSION_SOLO)
	var shop := HungryWorkshop.new()
	shop.follow(index)
	_check(shop.rows().size() == 1, "listed while the index is solo")
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(shop.rows().is_empty(), "gone when the session turns online")
	_check(shop.preset_for(&"ruin") == null, "and not playable")
	_completed += 1


func _test_ids_and_refused() -> void:
	_entered += 1
	print("")
	print("ids and refusals")
	var shop := HungryWorkshop.new()
	shop.follow(_index(DotContentIndex.SESSION_SOLO))
	var names := _names(shop.rows())
	_check(not names.has("Not Classic [Fixture Pack]"), "the game's own id wins", str(names))
	_check(shop.refused.has("bad"), "the bad document is refused with a reason", str(shop.refused))
	_completed += 1


func _test_play() -> void:
	_entered += 1
	print("")
	print("play")
	var shop := HungryWorkshop.new()
	shop.follow(_index(DotContentIndex.SESSION_SOLO))
	var preset := shop.preset_for(&"ruin")
	_check(preset != null, "a preset is made for the chosen map")

	if preset != null:
		var world := HungryWorld.new()
		world.is_authority = true
		world.name = "World"
		world.preset = preset
		world.tick_rate = 30
		world.register_service = false
		add_child(world)
		var ready_result := world.setup()
		_check(ready_result.ok, "the world sets up on it")
		_check(world.layout.count() == 3, "the world has the document's rocks", str(world.layout.count()))
		var bounds := world.arena.bounds
		var half := minf(bounds.size.x, bounds.size.y) * 0.5
		_check(world.layout.blocked(bounds.get_center() + Vector2(half * 0.5, 0.0)),
			"a rock stands where the document put it")
		_check(preset.display_name == "Ruin [Fixture Pack]", "the preset carries the label", preset.display_name)
		world.queue_free()
		await get_tree().process_frame
	_check(HungryLayout.for_id(&"workshop:nothing", Rect2(-500, -500, 1000, 1000)).is_empty(), "an unknown pack map is an empty layout")
	_completed += 1
