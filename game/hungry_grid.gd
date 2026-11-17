extends Dot2DGrid

const HungryField := preload("hungry_field.gd")

## The world's [Dot2DGrid], with dot-sim's `DotSimGrid2D` kept beside it for the bots.
##
## [b]Only built where the library has the `grid2d` module[/b] ([method HungryWorld._build_arena]);
## everywhere else the world keeps a plain [Dot2DGrid] and nothing here runs. The native copy
## itself is made the first time a bot asks ([method native]), from the cells as they stand,
## so a client or a world without bots never pays for it. From then on every [method place],
## [method remove] and [method clear] goes to both, each id with what eating it is worth
## ([member worth_of]), and [method HungryBot.look_for] asks the native copy for its whole
## neighbour loop in one call.
##
## The native lists are the script's lists, in the script's order (`adopt` copies them; a
## place or a removal does the same swap-and-pop), so the answer is the script's to the bit:
## `headless_native_forage` holds the two together, and [member HungryBot.forage_verify]
## re-runs the script beside every live ask.

## What a bot scores an item drop at: worth no mass, but a detour (see [method HungryBot.look_script]).
const PICKUP_WORTH := 220.0
## The bias under a snack's distance, so a crumb underfoot does not score infinitely.
const DISTANCE_BIAS := 40.0
## Anything this close to the head is the head itself (or on it) and is not looked at.
const NEAR := 0.001

## id -> what eating it is worth in mass, read when an id at or above
## [constant HungryField.PIECE_ID_LIMIT] is placed. The world's [method HungryField.mass_of].
var worth_of: Callable = Callable()

## The native copy, null until a bot asks for it (or when it could not be made).
var _native: Variant = null
## Whether the native copy also judges the pieces it sees (`forage_judged`, dot-sim after 0.2.7);
## an older library forages and the script judges.
var judges := false


func _init(p_cell_size: float = 128.0) -> void:
	super(p_cell_size)


## The native copy, made from the cells as they stand on the first ask. Null without the
## library's `grid2d` module or when the copy failed (an error each time it is tried).
func native() -> Variant:
	if _native == null and DotSim.has(&"grid2d"):
		_native = _adopted()
	return _native


## Drops the native copy; the next [method native] makes a fresh one.
func drop_native() -> void:
	_native = null
	judges = false


func place(id: int, position: Vector2, radius: float = 0.0) -> void:
	super(id, position, radius)
	if _native != null:
		_native.place(id, position, _worth(id))


func remove(id: int) -> void:
	super(id)
	if _native != null:
		_native.remove(id)


func clear() -> void:
	super()
	if _native != null:
		_native.clear()


func _worth(id: int) -> float:
	if id < HungryField.PIECE_ID_LIMIT or not worth_of.is_valid():
		return 0.0
	return float(worth_of.call(id))


func _adopted() -> Variant:
	var copy: Variant = ClassDB.instantiate(&"DotSimGrid2D")
	copy.set_cell_size(cell_size)
	copy.set_forage_rules(
		HungryField.PIECE_ID_LIMIT, HungryField.ITEM_ID_BASE, HungryField.PLANTED_ID_BASE,
		PICKUP_WORTH, DISTANCE_BIAS, NEAR
	)

	var keys := PackedInt64Array()
	var counts := PackedInt64Array()
	var ids := PackedInt64Array()
	var positions := PackedVector2Array()
	var worths := PackedFloat64Array()

	for key in _cells:
		var bucket: Array = _cells[key]
		keys.append(int(key))
		counts.append(bucket.size())
		for entry in bucket:
			var id := int(entry)
			ids.append(id)
			positions.append(position_of(id))
			worths.append(_worth(id))

	if not copy.adopt(keys, counts, ids, positions, worths) or copy.size() != size():
		push_error("HungryGrid: the native copy did not take the grid (%d ids, %d copied)" % [size(), copy.size()])
		return null

	judges = copy.has_method(&"forage_judged")
	return copy
