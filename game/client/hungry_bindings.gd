extends RefCounted

## Every key this game reads, as one dot-menu [DotMenuBindings] table: the action, the setting
## that stores it, the words a player sees, the default, and the card it goes on.
##
## [b]A table, because four things read it:[/b] [HungryInput] and the client match events
## against the actions, the settings document stores one binding per row, the menu's Controls
## page draws a key per row, and the help screen (H) lists them with the key each is on now.
## Until 2026-10-12 the keys were dot-ui's rebinder over every `hungry_*` action and stored in
## its own file, so help (H) was not rebindable here; [HungrySettings] migrates that file.
##
## [b]The mouse buttons are rows of their own.[/b] A row puts ONE input on its action
## ([method DotInputBinding.apply] erases the rest), and split and throw used to be a key and a
## button on one action: tabled as one row, the first rebind of Space would have taken the
## left button away with it. So the button is a second action that [HungryInput] reads beside
## the key, and both are rebindable.
##
## H is help and M the map menu in every game of the family (dot-menu adds both rows), so
## nothing here may default to either; `headless_presentation` holds the table to it.

const SPLIT := &"hungry_split"
const SPLIT_CLICK := &"hungry_split_click"
const THROW := &"hungry_throw"
const THROW_CLICK := &"hungry_throw_click"
const BOOST := &"hungry_boost"
const EJECT := &"hungry_eject"
const SCOREBOARD := &"hungry_scoreboard"
## dot-ui's chat window's actions, as `HungryPresentation._build_chat` names them.
const CHAT := &"hungry_chat"
const CHAT_NEAR := &"hungry_chat_near"

## The settings the chat keys were stored under before there was a table. Kept, and kept
## ACCOUNT: changing a stored setting's name or scope resets somebody's key.
const CHAT_SETTING := &"chat_open_key"
const CHAT_NEAR_SETTING := &"chat_near_key"


static func make() -> DotMenuBindings:
	var keys := DotMenuBindings.new()
	keys.add(SPLIT, &"bind_split", "Split: throw half of you forward", "Space", "Playing")
	keys.add(SPLIT_CLICK, &"bind_split_click", "Split (mouse)", "Mouse 1", "Playing")
	keys.add(EJECT, &"bind_eject", "Eject a little mass (smaller and faster)", "W", "Playing")
	keys.add(THROW, &"bind_throw", "Throw what you are holding", "Q", "Playing")
	keys.add(THROW_CLICK, &"bind_throw_click", "Throw (mouse)", "Mouse 2", "Playing")
	keys.add(BOOST, &"bind_boost", "Boost (hold)", "Shift", "Playing")
	keys.add(CHAT, CHAT_SETTING, "Chat", "Y", "Communication", DotSettingsDef.Scope.ACCOUNT)
	keys.add(CHAT_NEAR, CHAT_NEAR_SETTING, "Chat with nearby players", "U", "Communication",
		DotSettingsDef.Scope.ACCOUNT)
	# Push to talk: dot-voice's own action, which `HungryVoice` gates on. Added here, in the
	# Communication group beside the chat keys, so `DotMenuSettings` finds the row and does not
	# add its own.
	keys.add_voice("Communication")
	keys.add(SCOREBOARD, &"bind_scoreboard", "Scoreboard (hold)", "Tab", "Interface")
	return keys
