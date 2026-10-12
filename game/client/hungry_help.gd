extends RefCounted

## H opens dot-menu's help screen here as in every game of the family: the goal, the modes
## and every key as it is bound now.
##
## [b]Only the help, not dot-menu's Escape menu.[/b] This game's menus are dot-ui's screen
## stack over a `DotConfig` (see `HungryMenus`), and moving them onto dot-menu changes where
## a player's settings are stored, which is its own piece of work. So the [DotMenu] built here
## never opens its own menu (`open_on_escape` off): it owns the help screen, H and the theme,
## and the pause menu's Help button opens the same screen.
##
## [b]The table is for reading, not storing.[/b] The keys are the `hungry_*` actions dot-ui's
## rebinder (the Controls screen) stores; [method DotMenuBindings.shown] reads each from the
## InputMap, so a key rebound there is shown where it is now. No row is declared into a
## settings document, and the help key itself is dot-menu's (H, put on the InputMap by
## [method DotMenu.setup]); the rebinder lists only `hungry_*`, so H is not rebindable here.

const CHANNEL := "hungry.help"


static func table() -> DotMenuBindings:
	var keys := DotMenuBindings.new()
	keys.add(&"hungry_split", &"bind_split", "Split: throw half of you forward", "Space", "Playing")
	keys.add(&"hungry_eject", &"bind_eject", "Eject a little mass (smaller and faster)", "W", "Playing")
	keys.add(&"hungry_throw", &"bind_throw", "Throw what you are holding", "Q", "Playing")
	keys.add(&"hungry_boost", &"bind_boost", "Boost (hold)", "Shift", "Playing")
	keys.add(&"hungry_chat", &"chat_open_key", "Chat", "Y", "Communication")
	keys.add(&"hungry_chat_near", &"chat_near_key", "Chat with nearby players", "U", "Communication")
	keys.add(&"dot_voice_talk", &"bind_voice_talk", "Push to talk (on a server)", "V", "Communication")
	keys.add_help("Interface")
	return keys


## The help-only menu under [param host]. Null when dot-menu could not build it (logged).
static func build(host: Node) -> DotMenu:
	var menu := DotMenu.new()
	menu.name = "HelpMenu"
	menu.bindings = table()
	var config := DotMenuConfig.new()
	config.brand_name = "Hungario"
	config.fps_counter = false
	config.net_stat = false
	# Top left: the top right is the leaderboard's.
	config.help_hint = &"top_left"
	menu.config = config
	menu.open_on_escape = false
	menu.manage_pointer = false
	host.add_child(menu)
	var built := menu.setup()
	if not built.ok:
		DotLog.result(CHANNEL, "the help screen", built)
		menu.queue_free()
		return null
	fill(menu.help)
	return menu


static func fill(help: DotMenuHelp) -> void:
	# Escape is on the Screen card with what it opens here; dot-menu's own line for it says
	# "Menu and settings", which is its menu, not this game's.
	help.extra_keys = {}
	help.about = "Steer a monster with the mouse and grow by eating: food, and anybody smaller than you. Split to throw half of you at somebody, but your pieces cannot merge for a while, so each is easier to eat. When you are eaten you watch whoever ate you until you respawn."
	help.add_section("Mouse", [["Point", "Steer: the further the cursor, the faster; on yourself to pull your pieces together"], ["Left", "Split"], ["Right", "Throw"]], &"keys")
	help.add_section("Screen", [["Tab", "Scoreboard (hold)"], ["Esc", "Menu: loadout, settings, controls, help, leave"]], &"keys")
	help.add_text("Fruit and throwables", "Fruit gives you eight seconds of something: rush (faster), maw (eat players closer to your size) or rind (absorbs one burst). A pepper bursts whoever it hits into five pieces, a frostberry slows them, and a lure drops a ring of food where it lands.")
	help.add_text("Modes", "Classic, the square arena. Frenzy, small and fast. Gauntlet, a long narrow corridor. Warrens, rocks and refuges. Reef, a wall with four channels. Shallows, posts whose gaps narrow toward the middle. The players vote for the next mode.")
