extends "headless_presentation_exit.gd"
## Helper sections of headless_presentation.gd: the shared state, the presentation maker and the longer sections' halves.

const HungryConfig := preload("../game/hungry_config.gd")
const HungryParty := preload("../game/hungry_party.gd")
const HungryPresentation := preload("../game/client/hungry_presentation.gd")
const HungryServices := preload("../game/hungry_services.gd")
const HungrySound := preload("../game/client/hungry_sound.gd")
const HungrySoundSink := preload("../game/client/hungry_sound_sink.gd")
const HungryEvents := preload("../game/net/hungry_events.gd")
const HungryHud := preload("../game/client/hungry_hud.gd")
const HungryPreset := preload("../game/hungry_preset.gd")
const HungryRenderer := preload("../game/client/hungry_renderer.gd")
const HungryWorld := preload("../game/hungry_world.gd")
const HungryClient := preload("../game/client/hungry_client.gd")
const HungryInput := preload("../game/client/hungry_input.gd")
const HungryMonster := preload("../game/hungry_monster.gd")
const HungryBindings := preload("../game/client/hungry_bindings.gd")
const HungryMenus := preload("../game/client/hungry_menus.gd")
const HungrySettings := preload("../game/client/hungry_settings.gd")
const HungryFalls := preload("../game/client/hungry_falls.gd")
const HungryVoice := preload("../game/client/hungry_voice.gd")
const HungryPiece := preload("../game/hungry_piece.gd")

var _entered := 0
var _completed := 0


func _make() -> HungryPresentation:
	var p := HungryPresentation.new()
	p.name = "P%d" % _entered
	p.config = HungryConfig.new()
	p.sound = HungrySound.make()
	# A memory store, in place of the file one this game ships with, and no old files to
	# migrate.
	p.menu_settings = HungrySettings.new()
	p.menu_settings.store = DotSettingsStoreMemory.new()
	p.menu_settings.legacy_config_path = ""
	p.menu_settings.legacy_bindings_path = ""
	add_child(p.sound)
	add_child(p)
	p.setup()
	return p


func _section(title: String) -> void:
	_entered += 1
	print("")
	print("-- %s" % title)


func _done() -> void:
	_completed += 1


func _board_shrinks(hud: HungryHud, world: HungryWorld) -> void:
	hud.make_room()
	var room := hud.board_room()
	var shown := hud.leaderboard.rows()
	_check(
		room >= 1 and room < HungryHud.BOARD_ROWS and not hud.leaderboard.show_header
			and hud.leaderboard.offset_bottom <= 110.0 - HungryHud.BOARD_GAP,
		"a ballot over the corner shrinks the board above it, headerless",
		"room %d, header %s, bottom %.0f" % [room, hud.leaderboard.show_header, hud.leaderboard.offset_bottom]
	)
	_check(
		shown.size() == room and bool(shown.back().get("highlight", false)) and int(shown.back()[&"rank"]) == 7
			and int(shown.front()[&"rank"]) == 1,
		"the leader first and this player's own row last, with their real rank",
		str(shown.map(func(r: Dictionary) -> String: return "%s:%s" % [r[&"rank"], r[&"name"]]))
	)

	# The clock is dot-ui's DotScoreStrip, top centre, clear of the ballot's column.
	hud._refresh_clock()
	hud.strip.refresh_cover()
	var remaining := world.match_node.seconds_remaining() if world.match_node != null else -1.0
	_check(
		(hud.strip.clock == DotScoreStrip.clock_text(remaining)) if remaining >= 0.0 else hud.strip.under_text() != "",
		"the round clock is DotScoreStrip's, rounded up",
		"%s for %.2f s, under '%s'" % [hud.strip.clock, remaining, hud.strip.under_text()]
	)
	_check(not hud.strip.covered, "and a ballot down the right leaves it alone")


func _board_theme(hud: HungryHud) -> void:
	# Christian's first play test: a darker HUD by default, restyled live by the menu's theme.
	var settings := HungrySettings.new()
	settings.legacy_config_path = ""
	settings.legacy_bindings_path = ""
	add_child(settings)
	var _built: Variant = settings.setup(DotSettingsStoreMemory.new())
	settings.menu.follow_hud(hud, HungryHud.accent_theme())
	var plate := hud.strip.colour(&"plate")
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7 and hud.strip.colour(&"highlight") == Color(1.0, 0.85, 0.40),
		"the HUD is dark by default, in the menu's theme, with this game's gold as its accent", str(plate))
	var _t: Variant = settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: DotMenuPalette = settings.menu.palette()
	_check(contrast.id == &"contrast" and hud.strip.colour(&"plate") == contrast.hud_plate
		and hud.vote_label.get_theme_color(&"font_outline_color") == contrast.hud_ink
		and hud.vote_label.get_theme_constant(&"outline_size") == HungryHud.TEXT_OUTLINE,
		"a theme picked in the menu reaches the clock and every Label's outline at once")
	_t = settings.settings.set_value(&"ui_theme", &"midnight")
	settings.menu.unfollow_hud(hud)
	settings.queue_free()
	_check(
		hud.vote_label.offset_top >= HungryHud.STRIP_TOP + DotScoreStrip.H,
		"the vote countdown sits under the clock's plate, not on it",
		"%.0f against %.0f" % [hud.vote_label.offset_top, HungryHud.STRIP_TOP + DotScoreStrip.H]
	)


func _board_clear_of_chat(hud: HungryHud, ballot: Control) -> void:
	# The chat box's full log at 1280 x 720 (DotChatWindow's own sizes, lifted by this game's
	# margin) against the ballot and the clock: the three things up at a vote's end.
	var chat := DotChatWindow.new()
	var log_top := HungryPresentation.CHAT_MARGIN_BOTTOM + chat.entry_height \
		+ float(chat.max_lines) * (chat.line_height + chat.line_gap)
	var chat_rect := Rect2(chat.margin_left, 720.0 - log_top, chat.width, log_top - HungryPresentation.CHAT_MARGIN_BOTTOM)
	chat.free()
	var clock_rect := Rect2(hud.strip.position + hud.strip.footprint().position, hud.strip.footprint().size)
	var ballot_rect := Rect2(ballot.position, ballot.size)
	_check(
		not chat_rect.intersects(ballot_rect) and not chat_rect.intersects(clock_rect) and not ballot_rect.intersects(clock_rect),
		"the chat box, the ballot and the clock do not meet",
		"chat %s, ballot %s, clock %s" % [chat_rect, ballot_rect, clock_rect]
	)

	# A pack naming the strip does not parse on a shell whose dot-ui predates it, so the
	# requires.json dot-ci derives must ask for dot-ui 4, and nothing may lower it.
	var asks := DotAddonApi.derive()
	_check(
		int(asks.get("dot_ui", 0)) >= 4 and not FileAccess.file_exists("res://" + DotAddonApi.FLOOR_FILE),
		"the pack asks a shell for dot-ui level 4, the glance pieces",
		str(asks.get("dot_ui"))
	)


func _board_states(hud: HungryHud, ballot: Control) -> void:
	ballot.position = Vector2(904.0, 400.0)
	hud.make_room()
	_check(hud.board_room() == -1, "a panel clear of the corner leaves the board alone (%d)" % hud.board_room())

	ballot.position = Vector2(904.0, 110.0)
	hud.make_room()
	ballot.visible = false
	hud.make_room()
	_check(
		hud.board_room() == -1 and hud.leaderboard.show_header and hud.leaderboard.max_rows == HungryHud.BOARD_ROWS
			and hud.leaderboard.offset_bottom == HungryHud.BOARD_BOTTOM and hud.leaderboard.rows().size() == 7,
		"a hidden panel gives the corner back: header, ten rows, every monster"
	)

	ballot.visible = true
	ballot.position = Vector2(904.0, 20.0)
	hud.make_room()
	_check(
		hud.board_room() == 0 and not hud.leaderboard.visible,
		"no room for one row hides the board rather than drawing it under the panel"
	)


func _blind(world: HungryWorld, me: HungryMonster, them: HungryMonster) -> void:
	var hud := HungryHud.new()
	hud.name = "AdminHud"
	add_child(hud)
	hud.build(world, null, 1)

	_check(
		hud.blind_overlay != null and hud.blind_overlay.get_index() == 1
			and hud.minimap.get_index() == 0,
		"the blind sits over the minimap and under every other widget",
		"blind %d, minimap %d" % [hud.blind_overlay.get_index(), hud.minimap.get_index()]
	)

	them.blinded = true
	hud.present_blind(1.0)
	_check(
		not hud.blind_overlay.visible,
		"somebody else's blind does not touch this screen"
	)

	me.blinded = true
	hud.present_blind(HungryHud.BLIND_FADE_SEC * 0.5)
	var halfway := hud.blind_overlay.modulate.a
	hud.present_blind(1.0)
	_check(
		halfway > 0.3 and halfway < 0.7 and is_equal_approx(hud.blind_overlay.modulate.a, 1.0),
		"this player's own comes down over a quarter of a second, not in a frame (%.2f, then %.2f)"
			% [halfway, hud.blind_overlay.modulate.a]
	)

	# The whole viewport, not the HUD's rect: `DotHud` insets itself by the safe area, and
	# game-arena's first rendered blind left a frame of the world showing round the edge.
	var covered := hud.blind_overlay.get_global_rect()
	var screen := get_viewport().get_visible_rect()
	_check(
		covered.encloses(screen),
		"and it covers the whole viewport (%s over %s)" % [covered, screen]
	)

	# Dead is still blind: otherwise feeding yourself to the nearest monster lifts it.
	me.alive = false
	hud.present_blind(1.0)
	_check(hud.blind_overlay.visible, "and being eaten does not lift it")
	me.alive = true

	me.blinded = false
	hud.present_blind(1.0)
	_check(not hud.blind_overlay.visible, "and it lifts when the flag does")
	hud.queue_free()


func _beacon(world: HungryWorld, them: HungryMonster) -> void:
	var p := _make()
	var sink := p.audio.sink as HungrySoundSink
	var ping := p.audio.catalogue.find(HungryPresentation.BEACON_SOUND)
	_check(
		ping != null and ping.kind == DotAudioDef.Kind.POSITIONAL_2D and ping.priority < 100
			and HungrySoundSink.CUES.has(String(HungryPresentation.BEACON_SOUND)),
		"the ping is catalogued, positional, under the three that change everything, and mapped to a voice"
	)

	var renderer := HungryRenderer.new()
	renderer.name = "AdminRenderer"
	add_child(renderer)
	renderer.bind(world, null, 1)
	var pulses: Array[int] = []
	renderer.beacon_pulsed.connect(func(id: int, at: Vector2) -> void:
		pulses.append(id)
		var _handle := p.on_beacon(at)
	)

	_check(renderer.present_beacons(0.016) == 0 and renderer.beacon_count() == 0,
		"nothing is beaconed, nothing is drawn")

	them.beacon = true
	sink.forget()
	p.present(0.0, them.centre())
	var first := renderer.present_beacons(0.016)
	var rest := 0
	for _frame in range(58):
		rest += renderer.present_beacons(1.0 / 60.0)
	_check(
		first == 1 and rest == 0 and renderer.beacon_count() == 1,
		"a beacon pings the moment it comes on, then not again inside a second (%d, %d)" % [first, rest]
	)
	for _frame in range(4):
		rest += renderer.present_beacons(1.0 / 60.0)
	_check(rest == 1, "and once when the second is up: once a second, not once a frame (%d)" % rest)
	_check(
		pulses == [2, 2] and sink.count_of(HungryPresentation.BEACON_SOUND) == 2,
		"every ripple is heard through the bank, for the beaconed player (%s, %d)"
			% [str(pulses), sink.count_of(HungryPresentation.BEACON_SOUND)]
	)

	# Positional: dot-audio culls a ping past its distance, which is what makes the edge
	# pointer — not the sound — the way a beacon two screens away is found.
	p.present(0.0, them.centre() + Vector2(ping.max_distance * 2.0, 0.0) if ping != null else Vector2.ZERO)
	_check(
		p.on_beacon(them.centre()) == 0,
		"and a beacon far outside earshot is culled rather than heard across the arena"
	)

	them.alive = false
	var _gone := renderer.present_beacons(0.016)
	_check(renderer.beacon_count() == 0, "a beacon goes when its monster is eaten")
	them.alive = true
	var _back := renderer.present_beacons(0.016)
	them.beacon = false
	var _off := renderer.present_beacons(0.016)
	_check(renderer.beacon_count() == 0, "and when the flag does")

	renderer.queue_free()
	p.queue_free()


func _party_refused(stub: Variant, url: String, ada: HungryParty, bob: HungryParty) -> void:
	# A refusal arrives as a failure the caller can read, not as null and not as success.
	bob.leave()
	var carol := HungryParty.new()
	carol.name = "PartyCarol"
	carol.signalling_url = url
	add_child(carol)
	var _set := carol.setup()
	stub.refuse = 403
	var refused: DotResult = await carol.host("Carol")
	_check(refused != null and not refused.ok and not carol.active(),
		"and a rendezvous that refuses leaves the party closed with a reason",
		"null" if refused == null else ("ok" if refused.ok else refused.error.message))

	ada.leave()
	for node: Node in [ada, bob, carol, stub]:
		node.queue_free()
	_done()


func _chat_box_input(p: HungryPresentation, window: DotChatWindow) -> void:
	# Split, throw, boost and eject are all keys here: "gg boost" splits you twice.
	_check(not p.swallows_input(), "a closed box does not swallow input")
	window.open()
	_check(p.swallows_input(), "an open one does, so a typed key is not a split")
	window.close()
	_check(not p.swallows_input(), "and gives it back when it closes")


func _chat_box_join(p: HungryPresentation, window: DotChatWindow) -> void:
	# A join notice is a name and NO text (dot-chat's `_presence`). Drawn by its text it was
	# an empty row in the box: with dot-server's own join line turned off, nobody was ever
	# seen to join. The client is never added to the tree (its `_ready` builds the netcode).
	var chat := DotChatClient.new()
	chat.channels = HungryServices.chat_channels()
	var hud := HungryHud.new()
	var client := HungryClient.new()
	client.hud = hud
	client.chat = chat
	client.presentation = p
	client._on_chat_message(
		DotChatMessage.make(
			DotChatMessage.Kind.JOIN, HungryServices.CHANNEL_ALL, "k2", "Guest 435", ""
		),
		HungryServices.CHANNEL_ALL
	)
	var rows := window.history()
	var drawn := ""
	for part in (rows[rows.size() - 1] if not rows.is_empty() else []):
		drawn += str((part as Dictionary).get("text", ""))
	_check(
		drawn.contains("Guest 435") and drawn.contains("joined"),
		"a join notice is drawn as a sentence, not as an empty line",
		"'%s'" % drawn
	)
	client.free()
	chat.free()
	hud.free()
