extends Node

## A private arena among friends, with the host able to leave.
##
## [b]hungario's peer-to-peer decision is the opposite of game-fatal-contact's on one axis and the
## same on the other, and both halves follow from what kind of game it is.[/b]
##
## **Migration is on, where the arena turns it off.** A deathmatch is rounds: the host
## holds the match clock, the score and every hitbox, and handing that over mid-round
## produces a round nobody can agree about, so an arena party whose host leaves has ended.
## hungario is a *continuous* arena — people join, grow, burst and come back, and there is
## no round boundary to be in the middle of — so a host leaving should cost a moment and
## not the session.
##
## **Reporting is refused, exactly as the arena refuses it.** This game files to gs-stats
## and unlocks gs-achievements, and a peer-to-peer host is a player's own machine that can
## lie about how much they ate. A host who can cheat and a persistent number are one
## exploit rather than two features.

const CHANNEL := "hungry.party"

signal open(code: String)
signal closed(res: GSResult)

var session: GSP2PSession = null

@export var signalling_url: String = ""

var _http: GSHttp = null


func setup() -> GSResult:
	session = GSP2PSession.new()
	session.name = "P2P"
	session.config = _config()
	add_child(session)

	var res := session.setup()
	if not res.ok:
		return res.wrap("hungario's party session")

	session.signaller = _make_signaller()
	session.ended.connect(func(r: GSResult) -> void: closed.emit(r))
	return GSResult.success(null)


func _config() -> GSP2PConfig:
	var c := GSP2PConfig.new()
	# Sixteen. The arena is big and this game is cheap on the wire -- a monster is a
	# position, a mass and a bitmask -- so the limit here is the host's uplink rather than
	# the simulation, and sixteen is what a domestic one carries at this rate.
	c.max_peers = 16
	c.trust = GSP2PConfig.Trust.SANDBOXED
	# On, and this is the axis where this game disagrees with the arena. There is no round
	# to be in the middle of.
	c.migrate_host = true
	c.signalling_url = signalling_url
	return c


func _make_signaller() -> GSP2PSignaller:
	if signalling_url.is_empty():
		return GSP2PSignallerLoopback.new(session.local_id)
	_http = GSHttp.new()
	_http.name = "PartyHttp"
	add_child(_http)
	return GSP2PSignallerHttp.new(signalling_url, session.local_id, _http)


func host(display_name: String) -> GSResult:
	if not GSP2PSession.available():
		return GSResult.fail(
			GSError.CODE_UNSUPPORTED,
			"this build cannot host a private arena",
			GSP2PSession.unavailable_reason()
		)
	# Awaited: gs-peer-to-peer's session awaits its signaller since 37d47c1, because an
	# HTTP rendezvous answers a frame later at best. A caller of this awaits it too.
	var res: GSResult = await session.host(display_name)
	if res.ok:
		open.emit(str(res.value))
		GSLog.info(
			CHANNEL,
			"a private arena is open; nothing from it is filed anywhere",
			{"code": str(res.value)}
		)
	return res


func join(code: String, display_name: String) -> GSResult:
	return await session.join(code, display_name)


func leave() -> void:
	session.leave()


func active() -> bool:
	return session != null and session.state() != &"idle"


## Whether statistics and achievements may leave this session. Asked in one place.
func reporting_allowed() -> bool:
	if not active():
		return true
	return session.config.trust != GSP2PConfig.Trust.SANDBOXED


func describe_lines() -> PackedStringArray:
	if session == null:
		return PackedStringArray(["no party"])
	var out := session.describe_lines()
	out.append(
		"  reporting %s" % ("allowed" if reporting_allowed() else "refused: this arena is sandboxed")
	)
	return out
