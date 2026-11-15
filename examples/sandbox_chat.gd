extends DotGameCheckSuite
## The sandbox's chat checks and the section bookkeeping every sandbox part shares.
## [code]sandbox.gd[/code] extends this; it holds the rest of the suite.

const HungryClient := preload("../game/client/hungry_client.gd")
const HungryServices := preload("../game/hungry_services.gd")
var _client: HungryClient = null
var _link: DotClientLink = null
## Chat lines the client received.
var _heard: Array[DotChatMessage] = []
## Anything that came back through dot-server's own chat signal.
var _legacy_heard: Array[Dictionary] = []
## The one thing dot-server's chat signal legitimately carries here.
var _chat_state: Array[Dictionary] = []
## Sections entered, and sections that ran to their last line.
var _entered := 0
var _completed := 0


## Opens a section. Pair with [method _done] on every path out of it.
func _section(title: String) -> void:
	_entered += 1
	print("")
	print(title)


func _done() -> void:
	_completed += 1


## Waits for a condition, or gives up. Returns whether it happened.
func _until(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)

	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true

		await get_tree().physics_frame

	return false


func _test_chat() -> void:
	_section("chat")

	# Attached here: the chat client exists once `_client` is in the tree.
	if not _client.chat.message_received.is_connected(_note_heard):
		_client.chat.message_received.connect(_note_heard)

	var before := _heard.size()
	_client.bridge.say(HungryServices.CHANNEL_ALL, "hello from the sandbox")

	var heard := await _until(func() -> bool: return _heard.size() > before, 6.0)

	if not _check(heard, "a line the client sends comes back to it"):
		_done()
		return

	var last := _heard[_heard.size() - 1]
	_check(
		last.text.contains("hello from the sandbox"),
		"with the text intact",
		last.text
	)
	_check(
		last.channel == HungryServices.CHANNEL_ALL,
		"on the channel it was sent to (%s)" % String(last.channel)
	)

	# The HUD is what a player actually sees, and it takes the same message the log does.
	var lines := _client.hud.feed.line_count()
	_client.hud.chat({"name": last.sender_name, "text": last.text})
	_check(
		_client.hud.feed.line_count() > lines,
		"and the HUD shows it"
	)

	# [DotChatFilter] sanitises first: a zero-width space slips a name past a filter, and no client should get one.
	var zero_width := String.chr(0x200B)
	var dirty := await _say_and_wait("bad%sline" % zero_width)
	_check(
		dirty != "" and not dirty.contains(zero_width),
		"and a zero-width space never reaches a client",
		dirty
	)

	# The proximity channel is the one a lobby's argument does not cover: an arena is bigger than a screen, and a line on it must reach its sender, who is within their own radius.
	var near_before := _heard.size()
	_client.bridge.say(HungryServices.CHANNEL_NEAR, "anybody close?")

	var nearby := await _until(func() -> bool: return _heard.size() > near_before, 6.0)
	_check(nearby, "a line on the proximity channel reaches somebody standing there")

	await _chat_legacy_path()
	_done()


## The one payload that legitimately comes down dot-server's chat signal, and the legacy path beside the router.
func _chat_legacy_path() -> void:
	_check(
		_chat_state.size() >= 1,
		"the server told the client what is carrying chat, on joining (%d)" % _chat_state.size()
	)
	_check(
		_chat_state.is_empty() or not bool(_chat_state[0].get("relay", true)),
		"and this one is carrying it nowhere else, which is the honest answer with no relay"
	)

	_check(
		_legacy_heard.is_empty(),
		"and dot-server's own chat delivered nothing beside it (%d)"
			% _legacy_heard.size(),
		"two paths for one message is two sets of rules, and the one that skipped the "
		+ "filter would be the one that leaked admin chat"
	)

	# A browser shell's chat box goes through dot-server and cannot name a channel; the module forwards it.
	var forwarded_before := _heard.size()
	_link.send_chat("said the old way", false)

	var forwarded := await _until(
		func() -> bool: return _heard.size() > forwarded_before, 6.0
	)
	_check(
		forwarded,
		"a line sent through dot-server's own chat is forwarded onto this game's wire"
	)


func _note_heard(message: DotChatMessage, _channel: StringName) -> void:
	_heard.append(message)


func _say_and_wait(text: String) -> String:
	var before := _heard.size()
	_client.bridge.say(HungryServices.CHANNEL_ALL, text)

	var heard := await _until(func() -> bool: return _heard.size() > before, 6.0)

	if not heard:
		return ""

	return _heard[_heard.size() - 1].text
