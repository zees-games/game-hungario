extends "./hungry_client_state.gd"
## The client's chat box wiring: what it sends, and what the server's chat state draws in it.
## [code]hungry_client.gd[/code] extends this.


## The chat box, or null before the presentation layer exists.
func _chat_window() -> GSChatWindow:
	return presentation.chat_window if presentation != null else null


## Joins the chat box to the three things it needs.
func _wire_chat_window() -> void:
	var window := _chat_window()

	if window == null:
		return

	window.submitted.connect(_on_chat_submitted)

	window.opened.connect(func(_channel: StringName) -> void:
		if voice != null:
			voice.release()
	)

	var client_link := GSRegistry.get_service(&"dot_client_link")

	if client_link != null and client_link.has_signal("chat_received"):
		client_link.connect("chat_received", _on_server_chat_state)


## dot-server's chat payload: what is carrying the conversation, and the server's own lines.
func _on_server_chat_state(payload: Dictionary) -> void:
	var kind := str(payload.get("kind", ""))

	if kind == "system" or kind == "admin":
		_draw_server_line(kind, str(payload.get("name", "")), str(payload.get("text", "")).strip_edges())
		return

	if kind != "state":
		return

	if presentation != null:
		presentation.set_chat_relayed(bool(payload.get("relay", false)))


func _draw_server_line(kind: String, speaker: String, text: String) -> void:
	var window := _chat_window()

	if window == null or text == "":
		return

	if kind == "system":
		window.add_text(text if speaker == "" else "%s %s" % [speaker, text], Color(0.98, 0.84, 0.40))
	else:
		window.add_said(speaker, text, Color(0.98, 0.72, 0.35))


func _on_chat_submitted(text: String, channel: StringName) -> void:
	_on_say(text, channel)


func _on_say(text: String, channel: StringName = HungryServices.CHANNEL_ALL) -> void:
	if bridge != null and not bridge.net.is_server:
		bridge.say(channel, text)
	elif hud != null:
		hud.say("(offline) %s" % text, Color(0.6, 0.62, 0.66))
