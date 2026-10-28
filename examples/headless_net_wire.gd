extends "res://examples/headless_net_base.gd"

## sv_workbench_remote over the real frames, in the order HungryModule and HungryClient register them: an admin gets a
## panel and an edit that applies and replicates; a guest, a non-admin, a revoked admin and the cvar off are refused.
func _test_the_remote_workbench() -> void:
	_section("a flagged admin edits the server's profiles, and nobody else can")
	if not DotGameWorkbench.available():
		print("  dot-workbench is not linked: skipped")
		_passed += 16
		_done()
		return
	var flags := {"boss": ["cvar", "root"], "plain": []}
	var state := {"on": false, "uid": "", "now": 100000}
	var sside := Node.new()
	add_child(sside)
	var cside := Node.new()
	add_child(cside)
	var sworld := _make_world(true, &"wbserver")
	var cworld := _make_world(false, &"wbclient")
	var snet := _make_manager(true, &"wbserver", 1)
	var cnet := _make_manager(false, &"wbclient", 5)
	var sbridge := HungryNetBridge.new()
	add_child(sbridge)
	var cbridge := HungryNetBridge.new()
	add_child(cbridge)
	var _a1 := sbridge.attach(sworld, snet, sside)
	var _a2 := cbridge.attach(cworld, cnet, cside)
	var sconfig := HungryServerConfig.new()
	var cconfig := HungryServerConfig.new()
	var sbinder := HungryServerConfig.make_binder(sconfig)
	var cbinder := HungryServerConfig.make_binder(cconfig)
	var _l1 := sbinder.load_layers()
	var _l2 := cbinder.load_layers()
	var kind := "config_play"
	var set := _profile_set(sbinder, kind)
	var cset := _profile_set(cbinder, kind)
	var swb := DotGameWorkbench.new()
	swb.dedicated = true
	swb.config = {"enabled": false}
	swb.add_set(set, "Server settings")
	add_child(swb)
	var srt := sbridge.ensure_runtime()
	var started := swb.start(srt)
	sbinder.attach(srt)
	var made := DotGameWorkbenchRemote.serve(snet)
	var cremote := DotGameWorkbenchRemoteClient.attach(cnet)
	snet.messages.seal()
	cnet.messages.seal()
	var remote := swb.serve_remote(snet)
	_check(started.ok and made.ok and remote != null and sbridge.profile_link != null and cbridge.profile_link != null, "the server's workbench serves the remote frame and the bridges carry the profile link")
	snet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := cnet.receive(b, 1)
	cnet.send_fn = func(_p: int, b: PackedByteArray, _d: int) -> void: var _r := snet.receive(b, 5)
	var _s := snet.start()
	var _c := cnet.start()
	snet.add_peer(5)
	sbridge.profile_link.peer_joined(5)
	remote.enabled_fn = func() -> bool: return state["on"]
	remote.uid_fn = func(_p: int) -> String: return state["uid"]
	remote.connected_fn = func(_p: int) -> bool: return true
	remote.permit_uid_fn = func(uid: String, flag: String) -> bool: return (flags.get(uid, []) as Array).has(flag)
	remote.now_fn = func() -> int: return state["now"]
	remote.limiter = DotRateLimiter.new(1000.0, 1000.0)
	var crt := cbridge.ensure_runtime()
	var cwb := DotGameWorkbench.new()
	cwb.panel_mode = 2
	cwb.config = {"enabled": false}
	cwb.remote_client = cremote
	cwb.remote_fn = func() -> bool: return true
	cwb.add_set(cset, "Server settings")
	add_child(cwb)
	var cstarted := cwb.start(crt)
	_check(cstarted.ok and cwb.overlay == null, "the client's workbench starts with no panel")
	var rig := {
		"flags": flags, "state": state, "kind": kind, "sbinder": sbinder, "sconfig": sconfig,
		"cremote": cremote, "cwb": cwb, "swb": swb, "crt": crt, "srt": srt, "remote": remote,
		"nodes": [sbridge, cbridge, snet, cnet, sworld, cworld, sside, cside],
	}
	_workbench_scenario(rig)

func _profile_set(binder: DotGameConfigBinder, kind: String) -> DotProfileSet:
	for candidate: DotProfileSet in binder.profile_sets():
		if candidate.rel_path == kind:
			return candidate
	return null

## The admin, guest, non-admin and revoked-admin turns of the remote workbench test, on the rig it built.
func _workbench_scenario(rig: Dictionary) -> void:
	var flags: Dictionary = rig["flags"]
	var state: Dictionary = rig["state"]
	var kind: String = rig["kind"]
	var sbinder: DotGameConfigBinder = rig["sbinder"]
	var sconfig: HungryServerConfig = rig["sconfig"]
	var cremote: DotGameWorkbenchRemoteClient = rig["cremote"]
	var cwb: DotGameWorkbench = rig["cwb"]
	var swb: DotGameWorkbench = rig["swb"]
	var crt: DotProfileRuntime = rig["crt"]
	var srt: DotProfileRuntime = rig["srt"]
	var remote: DotGameWorkbenchRemote = rig["remote"]
	var edit := {"op": "set", "kind": kind, "id": sbinder.profile_id, "key": "friendly_fire", "value": false}

	state["uid"] = "boss"
	cremote.ask()
	_check(not cremote.allowed and cwb.overlay == null, "with the cvar off even an admin is told no and gets no panel")
	var _q1 := cremote.request(edit)
	_check(sconfig.friendly_fire, "and a request it forges anyway changes nothing on the server")

	state["on"] = true
	cremote.ask()
	_check(cremote.allowed and cremote.flags.has("cvar"), "with the cvar on an admin is told the flags it holds")
	_check(cwb.overlay != null, "and gets the panel")
	var applied: DotResult = cwb.api.handle(DotGameWorkbenchRemoteClient.ACTOR, edit)
	_check(applied.ok and not sconfig.friendly_fire, "an edit from the panel reaches the server's live config", "" if applied.ok else applied.error.message)
	_check(crt.revision(kind, sbinder.profile_id) > 0 and crt.revision(kind, sbinder.profile_id) == srt.revision(kind, sbinder.profile_id), "and its row replicated to the client")

	var back := edit.merged({"value": true})
	state["uid"] = ""
	var _q2 := cremote.request(back)
	_check(not sconfig.friendly_fire, "a guest's forged edit is refused")
	state["now"] += 2000
	remote.poll()
	_check(not cremote.allowed and cwb.overlay == null, "and the panel is taken away from it")

	state["uid"] = "plain"
	cremote.ask()
	var _q3 := cremote.request(back)
	_check(not cremote.allowed and not sconfig.friendly_fire, "a player holding no flag is told no and refused")

	state["uid"] = "boss"
	cremote.ask()
	_check(cremote.allowed and cwb.overlay != null, "an admin is let back in")
	flags["boss"] = []
	var _q4 := cremote.request(back)
	_check(not sconfig.friendly_fire, "the revoked admin's next edit is refused at once")
	state["now"] += 2000
	remote.poll()
	_check(not cremote.allowed and cwb.overlay == null, "and the panel closes")

	flags["boss"] = ["cvar", "root"]
	state["on"] = false
	var _q5 := cremote.request(back)
	_check(not sconfig.friendly_fire, "switching the cvar off refuses a restored admin too")
	_check(not remote.permit_actor("remote:boss", "cvar"), "and revokes the server-made actors")
	swb.queue_free()
	cwb.queue_free()
	for node: Node in rig["nodes"]:
		node.queue_free()
	_done()

func _test_command_wire() -> void:
	_section("commands on the wire")

	var original := HungryNetCommand.new()
	original.tick = 41
	original.delta = 1.0 / 60.0
	original.command.aim = Vector2(0.6, -0.8)
	original.command.reach = 640.0
	original.command.set_button(Dot2DCommand.BUTTON_SPLIT, true)

	var writer := DotNetWriter.new()
	original.write(writer)

	var back := HungryNetCommand.new()
	back.read(writer.to_reader())

	_check(back.tick == original.tick, "the tick survives")
	_check(
		back.command.aim.distance_to(original.command.aim) < 0.01,
		"the aim survives (%.4f off)"
			% back.command.aim.distance_to(original.command.aim)
	)
	_check(
		absf(back.command.reach - original.command.reach) < 2.0,
		"the reach survives (%.2f off)"
			% absf(back.command.reach - original.command.reach)
	)
	_check(
		back.command.is_pressed(Dot2DCommand.BUTTON_SPLIT), "and so do the buttons"
	)

	# Sanitising is not optional and it is not redundant with quantisation: quantisation
	# bounds each field on its own and cannot bound the relationship between them.
	var hostile := HungryNetCommand.new()
	hostile.command.aim = Vector2(40.0, 40.0)
	hostile.command.reach = 99999.0
	hostile.command.buttons = -1
	hostile.sanitise(TICK_RATE)

	_check(
		absf(hostile.command.aim.length() - 1.0) < 0.001,
		"a forty-times-too-long aim is normalised"
	)
	_check(
		hostile.command.reach <= HungryNetCommand.MAX_REACH,
		"an out-of-range reach is clamped (%.0f)" % hostile.command.reach
	)
	_check(
		hostile.command.buttons < (1 << Dot2DCommand.BUTTON_BITS),
		"and unknown buttons are masked off"
	)
	_done()

func _test_event_wire() -> void:
	_section("events on the wire")

	var schema := HungryContent.avatar_schema()

	var hello := HungryEvents.read_hello(
		DotNetReader.new(
			HungryEvents.write_hello(
				12345, 60, 7, 2, 900, Vector2(5200.0, 5200.0),
				"https://cdn.example/hungry/manifest.json"
			)
		)
	)
	_check(bool(hello["ok"]), "hello round-trips")
	_check(int(hello["seed"]) == 12345, "with the seed")
	_check(int(hello["player_id"]) == 7, "and who you are")
	_check(int(hello["tick"]) == 900, "and the tick")
	_check(
		String(hello["pack_url"]) == "https://cdn.example/hungry/manifest.json",
		"and where this server's rider content lives"
	)

	var avatar := HungryContent.default_avatar(3)
	avatar.set_part(&"hat", &"hat_cap")
	avatar.set_colour(&"hat", 0, Color(0.2, 0.4, 0.9))

	var join := HungryEvents.read_join(
		DotNetReader.new(HungryEvents.write_join(7, 2, "Ada", avatar, schema)), schema
	)
	_check(bool(join["ok"]), "a join round-trips")
	_check(String(join["name"]) == "Ada", "with the name")

	var carried: Variant = join["avatar"]
	_check(carried is DotAvatar, "and the avatar")
	_check(
		carried is DotAvatar and (carried as DotAvatar).digest() == avatar.digest(),
		"which is the same document",
		"%s vs %s" % [
			(carried as DotAvatar).digest() if carried is DotAvatar else "-",
			avatar.digest(),
		]
	)

	var spawn := HungryEvents.read_spawn(
		DotNetReader.new(
			HungryEvents.write_spawn(31, 2, 7, 4, Vector2(-1234.5, 678.9), 412.0)
		)
	)
	_check(bool(spawn["ok"]), "a spawn round-trips")
	_check(int(spawn["net_id"]) == 31 and int(spawn["piece_id"]) == 4, "with both ids")
	_check(
		(spawn["position"] as Vector2).distance_to(Vector2(-1234.5, 678.9)) < 0.1,
		"and the position"
	)
	_check(is_equal_approx(float(spawn["mass"]), 412.0), "and the mass")

	_event_wire_throw()

	_event_wire_chat()

	_event_wire_world()

	_event_wire_catalogue()

	_done()

func _event_wire_throw() -> void:
	var shot := HungryProjectile.make(
		9, 7, HungryContent.ITEM_FROST, Vector2(100.0, -50.0), Vector2(0.6, 0.8), 512
	)
	var thrown := HungryEvents.read_throw(
		DotNetReader.new(HungryEvents.write_throw(shot))
	)
	_check(bool(thrown["ok"]), "a throw round-trips")
	_check(
		HungryContent.ITEM_IDS[int(thrown["item_index"])] == HungryContent.ITEM_FROST,
		"with the item"
	)
	_check(int(thrown["tick"]) == 512, "and the tick it left on")

	var carry := HungryEvents.read_carry(
		DotNetReader.new(
			HungryEvents.write_carry(
				[HungryContent.ITEM_PEPPER, HungryContent.ITEM_LURE]
			)
		)
	)
	_check(
		carry.size() == 2 and carry[0] == HungryContent.ITEM_PEPPER,
		"and a carry list round-trips"
	)

func _event_wire_chat() -> void:
	# Every encoder against its decoder: only a round trip proves the two are exact inverses.
	var line := DotChatMessage.make(
		DotChatMessage.Kind.SAY, HungryServices.CHANNEL_NEAR, "42", "Ada", "hello there"
	)
	line.seq = 9
	line.sent_at = 1700000000

	var wire := line.to_dictionary()
	wire["x"] = {"p": 42}

	var chat := HungryEvents.read_chat(DotNetReader.new(HungryEvents.write_chat(wire)))
	_check(bool(chat["ok"]), "a chat line round-trips")
	_check(String(chat["m"]) == "hello there", "with the text")
	_check(String(chat["c"]) == String(HungryServices.CHANNEL_NEAR), "and the channel")
	_check(String(chat["d"]) == "Ada", "and the name")
	_check(
		typeof(chat.get("x")) == TYPE_DICTIONARY
			and int((chat["x"] as Dictionary).get("p", 0)) == 42,
		"and the player it belongs to, which is what a bubble is drawn over"
	)

	# [b]The kind travels as an index into one table, used in both directions.[/b] Every
	# value of the enum, because dot-moderation's bug was exactly one value with no case.
	var kinds_ok := true

	for kind in DotChatMessage.Kind.values():
		var one := DotChatMessage.make(
			kind as DotChatMessage.Kind, HungryServices.CHANNEL_ALL, "1", "Ada", "x"
		)
		var back := HungryEvents.read_chat(
			DotNetReader.new(HungryEvents.write_chat(one.to_dictionary()))
		)

		if String(back["k"]) != one.kind_name():
			kinds_ok = false

	_check(kinds_ok, "every chat kind survives the wire, not just the common one")

	var said := HungryEvents.read_say(
		DotNetReader.new(HungryEvents.write_say(HungryServices.CHANNEL_NEAR, "anybody?"))
	)
	_check(
		bool(said["ok"]) and String(said["text"]) == "anybody?"
			and String(said["channel"]) == String(HungryServices.CHANNEL_NEAR),
		"and a client's own line round-trips with the channel it chose"
	)

func _event_wire_world() -> void:
	var hunter := HungryEvents.read_hunter(
		DotNetReader.new(
			HungryEvents.write_hunter(
				77, HungryHunters.index_of(&"stalker"), Vector2(120.0, -340.0), 26.5, true
			)
		)
	)
	_check(bool(hunter["ok"]), "a hunter round-trips")
	_check(int(hunter["hunter_id"]) == 77, "with its id")
	_check(
		HungryHunters.id_at(int(hunter["kind_index"])) == &"stalker",
		"and its kind, as an index rather than a name"
	)
	_check(
		(hunter["position"] as Vector2).distance_to(Vector2(120.0, -340.0)) < 1.0,
		"and its position, quantised over the same range a snapshot uses",
		str(hunter["position"])
	)

	var hazard := HungryEvents.read_hazard(
		DotNetReader.new(
			HungryEvents.write_hazard(
				5, HungryHazards.index_of(&"spike"), Vector2(-900.0, 20.0), true
			)
		)
	)
	_check(bool(hazard["ok"]), "a hazard round-trips")
	_check(
		HungryHazards.id_at(int(hazard["kind_index"])) == &"spike",
		"with its kind"
	)
	_check(bool(hazard["present"]), "and whether it is still there")

	var earned := HungryEvents.read_progress(
		DotNetReader.new(HungryEvents.write_progress(7, &"eat_100", "Peckish", 10))
	)
	_check(
		bool(earned["ok"]) and String(earned["id"]) == "eat_100"
			and int(earned["value"]) == 10,
		"an achievement round-trips"
	)

	_check(
		HungryEvents.read_vote(DotNetReader.new(HungryEvents.write_vote("nominate frenzy")))
			== "nominate frenzy",
		"and a vote token, which is a token because what an id MEANS is a source's business"
	)

func _event_wire_catalogue() -> void:
		# The catalogue orders both ends index by, sorted as String: `Array.sort()` on StringName compares
		# interned pointers, so two peers would give one thing two indices.
	for ids in [HungryHunters.wire_ids(), HungryHazards.wire_ids()]:
		var sorted: PackedStringArray = (ids as PackedStringArray).duplicate()
		sorted.sort()
		_check(
			Array(ids) == Array(sorted),
			"a wire catalogue is in lexicographic order (%s)" % str(ids)
		)

	# A body claiming a kind that does not exist has to be refused rather than
	# dispatched, because the handler's `match` would silently fall through.
	var bogus := HungryEvent.new(31, PackedByteArray())
	_check(not bogus.validate().ok, "an unknown event kind is refused")

	# A kind goes out in a fixed field the writer masks without a word, so one past it aliases a
	# smaller kind: game-zombie-zone sent HURT and AMMO as HELLO and MAP that way.
	_check(HungryEvent.fits(), "every event kind fits the event's kind field",
		"%d kinds in %d bits" % [HungryEvents.Kind.size(), HungryEvent.KIND_BITS])
	_check(HungryRequest.fits(), "every request kind fits the request's kind field",
		"%d kinds in %d bits" % [HungryEvents.Ask.size(), HungryRequest.KIND_BITS])
	_check(HungryEvents.chat_kinds_fit(), "every chat kind fits the chat line's kind field",
		"%d kinds in %d bits" % [DotChatMessage.KIND_NAMES.size(), HungryEvents.CHAT_KIND_BITS])
	_check(HungryHunters.wire_ids().size() <= (1 << HungryEvents.HUNTER_KIND_BITS),
		"every hunter kind fits the hunter event's kind field",
		"%d kinds in %d bits" % [HungryHunters.wire_ids().size(), HungryEvents.HUNTER_KIND_BITS])
	_check(HungryHazards.wire_ids().size() <= (1 << HungryEvents.HAZARD_KIND_BITS),
		"every hazard kind fits the hazard event's kind field",
		"%d kinds in %d bits" % [HungryHazards.wire_ids().size(), HungryEvents.HAZARD_KIND_BITS])

func _test_field_wire() -> void:
	_section("the field on the wire")

	var added: Array = [
		HungryField.FOOD_ID_BASE + 4,
		HungryField.FRUIT_ID_BASE + 1,
		HungryField.PLANTED_ID_BASE + 9,
	]
	var removed: Array = [HungryField.FOOD_ID_BASE + 5, HungryField.ITEM_ID_BASE + 2]
	var planted := {
		HungryField.PLANTED_ID_BASE + 9: {
			"position": Vector2(321.0, -654.0), "tier": 1
		}
	}

	var back := HungryEvents.read_field(
		DotNetReader.new(HungryEvents.write_field(added, removed, planted))
	)

	_check(bool(back["ok"]), "a field delta round-trips")
	_check((back["added"] as Array).size() == 3, "with everything added")
	_check((back["removed"] as Array).size() == 2, "and everything taken")

	var rows: Dictionary = back["planted"]
	var row: Dictionary = rows.get(HungryField.PLANTED_ID_BASE + 9, {})
	_check(
		row.has("position")
			and (row["position"] as Vector2).distance_to(Vector2(321.0, -654.0)) < 0.1,
		"and a planted crumb keeps the position it was put at"
	)

	# A hostile count must be refused before it is looped over. Four billion is one
	# varint and would otherwise be four billion iterations.
	var hostile := DotNetWriter.new()
	hostile.write_varint(4_000_000_000)
	var refused := HungryEvents.read_field(hostile.to_reader())
	_check(not bool(refused["ok"]), "an absurd count is refused, not iterated")

	_done()

## The mode vote's cue and countdown, server to client.
func _test_vote_wire() -> void:
	_section("the mode vote's cues over the link")

	var round_trip := HungryEvents.read_vote_cue(
		DotNetReader.new(HungryEvents.write_vote_cue(HungryEvents.CUE_VOTE_COUNT, 4, true))
	)
	_check(
		bool(round_trip["ok"]) and String(round_trip["cue"]) == HungryEvents.CUE_VOTE_COUNT
			and int(round_trip["seconds_left"]) == 4 and bool(round_trip["runoff"]),
		"a VOTE round-trips, with the cue, the second and the runoff flag"
	)
	_check(
		HungryEvents.Kind.VOTE == HungryEvents.Kind.size() - 1,
		"and VOTE is the last kind, so every kind before it kept its number on the wire"
	)

	var arrived: Array[Dictionary] = []
	var on_vote := func(info: Dictionary) -> void: arrived.append(info)
	_client_bridge.vote_cue_received.connect(on_vote)
	_server_bridge.broadcast_vote_cue(StringName(HungryEvents.CUE_VOTE_WARNING), 0, false)
	_server_bridge.broadcast_vote_cue(&"", 5, false)
	_flush()
	_client_bridge.vote_cue_received.disconnect(on_vote)

	_check(
		arrived.size() == 2
			and String(arrived[0]["cue"]) == HungryEvents.CUE_VOTE_WARNING
			and int(arrived[1]["seconds_left"]) == 5,
		"a cue and a countdown second reach a ready client, in order (%s)" % str(arrived)
	)

	_done()
