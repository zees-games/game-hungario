class_name HungryCover
extends DotLoadingCover

## The loading cover: the game's title and a tip over the arena's own sky and gold, with the
## stock status line and bar below. Handed to the platform as `cover`.

const TITLE := "Hungario"
const TIP := "Eat the small, split to catch, and stay out of the way of anything bigger."

const GOLD := Color(1.0, 0.70, 0.12)


func _init() -> void:
	super()
	background = Color(0.16, 0.18, 0.40)
	text_color = Color(0.92, 0.94, 1.0)
	title_color = GOLD
	title = TITLE
	tip = TIP
