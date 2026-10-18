extends RefCounted

const HungryLayout := preload("hungry_layout.gd")
const HungryPreset := preload("hungry_preset.gd")

const CHANNEL := "hungry.workshop"

## Subscribed map packs in SOLO play (dot-cloud's Workshop; docs/workshop.md there).
##
## [b]A pack's `map` entry names a JSON document in `scene`[/b], because this game's levels are
## not scenes: a level is a [HungryLayout] (discs in the arena) on a [HungryPreset]. The document:
## [codeblock]
## {"id": "ruin", "name": "Ruin", "preset": "classic",
##  "blocks": [[0.3, 0.2, 0.1], [-0.4, 0.0, 0.08]]}
## [/codeblock]
## `id` must equal the entry's id (the menu and the catalogue must agree on one name). `blocks`
## are `[x, y, radius]` as fractions of the arena's smaller half-extent from its centre, so the
## map fits whatever size the world has. `preset` is one of the game's own modes, which supplies
## the size, food and rules; the document adds only the rocks.
##
## [b]Online lists none[/b]: the index answers for its session, and only a solo client builds this.
## The rocks reach [member HungryLayout.documents], which the layout id `workshop:<id>` resolves
## against, so a pack map goes through the world's ordinary path.

## The map kinds this game takes: provides.json's `accepts.map_kinds`, which a test compares.
static func accepted() -> PackedStringArray:
	return PackedStringArray(["arena"])

## The game's own mode ids. A pack cannot take one.
const OWN_IDS: Array[StringName] = [&"classic", &"frenzy", &"gauntlet", &"warrens", &"reef", &"shallows"]

## Entry id -> why it was refused.
var refused: Dictionary = {}

var catalogue: DotMapCatalogue = null
var _blocks: Dictionary = {}


## Follows [param index] (the process's shared one by default).
func follow(index: DotContentIndex = null) -> void:
	catalogue = DotMapCatalogue.new()

	for id in OWN_IDS:
		var own := DotMapDef.new()
		own.id = id
		own.display_name = String(id).capitalize()
		own.kind = DotMapDef.KIND_ARENA
		own.scene_path = "res://game/hungry_workshop.gd"
		var _added := catalogue.add(own)

	catalogue.follow_content(index if index != null else DotContentIndex.shared(), accepted())


## The pack maps now visible, as menu rows `{id, name, detail, current}`. Reads documents lazily.
func rows(current_variant: String = "") -> Array:
	catalogue.refresh_content()
	var out: Array = []

	for map in catalogue.maps:
		if map.pack_title == "" or OWN_IDS.has(map.id):
			continue

		var blocks: Variant = _document_blocks(map)

		if blocks == null:
			continue

		HungryLayout.documents[String(map.id)] = blocks
		out.append({"id": String(map.id), "name": map.label(), "detail": "A subscribed map.",
			"current": current_variant == String(map.id)})

	return out


## Whether [param id] is a pack map this follower can play.
func has(id: StringName) -> bool:
	for row: Dictionary in rows():
		if row["id"] == String(id):
			return true

	return false


## The preset for pack map [param id], or null.
func preset_for(id: StringName) -> HungryPreset:
	if not has(id):
		return null

	var map := catalogue.get_map(id)
	var base := str(_docs[map.entry_key].get("preset", "classic")) if _docs.has(map.entry_key) else "classic"
	var preset := HungryPreset.for_id(StringName(base))
	preset.layout = HungryLayout.WORKSHOP
	preset.layout_variant = String(id)
	preset.display_name = map.label()
	return preset


var _docs: Dictionary = {}


func _document_blocks(map: DotMapDef) -> Variant:
	if _blocks.has(map.entry_key):
		return _blocks[map.entry_key]

	var text := FileAccess.get_file_as_string(map.scene_path) if map.scene_path != "" else ""
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	var why := ""
	var rocks := PackedVector3Array()

	if not (parsed is Dictionary):
		why = "The map document is empty or not JSON: %s" % map.scene_path
	elif str((parsed as Dictionary).get("id", "")) != String(map.id):
		why = "The entry's id is %s but its document's id is %s." % [map.id, (parsed as Dictionary).get("id", "")]
	elif not ((parsed as Dictionary).get("blocks", null) is Array):
		why = "The map document has no blocks list."
	else:
		for row: Variant in (parsed as Dictionary)["blocks"]:
			if not (row is Array) or (row as Array).size() != 3:
				why = "A block must be [x, y, radius]."
				break
			var r := float((row as Array)[2])
			if r <= 0.0 or r > 0.5 or absf(float((row as Array)[0])) > 1.5 or absf(float((row as Array)[1])) > 1.5:
				why = "A block lies outside the arena or has no size."
				break
			rocks.append(Vector3(float((row as Array)[0]), float((row as Array)[1]), r))

	if why != "":
		refused[String(map.id)] = why
		DotLog.warn(CHANNEL, "a subscribed map was refused", {"id": String(map.id), "why": why})
		_blocks[map.entry_key] = null
		return null

	_docs[map.entry_key] = parsed
	_blocks[map.entry_key] = rocks
	return rocks
