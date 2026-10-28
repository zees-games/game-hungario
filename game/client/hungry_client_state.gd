extends Node2D

const HungryAmbience := preload("../hungry_ambience.gd")
const HungryBindings := preload("hungry_bindings.gd")
const HungryBot := preload("../hungry_bot.gd")
const HungryCamera := preload("hungry_camera.gd")
const HungryConfig := preload("../hungry_config.gd")
const HungryContent := preload("../hungry_content.gd")
const HungryContentSource := preload("hungry_content_source.gd")
const HungryEvents := preload("../net/hungry_events.gd")
const HungryLayout := preload("../hungry_layout.gd")
const HungryModes := preload("../hungry_modes.gd")
const HungryTuning := preload("../hungry_tuning.gd")
const HungryHazards := preload("../hungry_hazards.gd")
const HungryHud := preload("hungry_hud.gd")
const HungryHunters := preload("../hungry_hunters.gd")
const HungryInput := preload("hungry_input.gd")
const HungryMenus := preload("hungry_menus.gd")
const HungryMonster := preload("../hungry_monster.gd")
const HungryNetBridge := preload("../net/hungry_net_bridge.gd")
const HungryPresentation := preload("hungry_presentation.gd")
const HungryMapConfig := preload("../hungry_map_config.gd")
const HungryPreset := preload("../hungry_preset.gd")
const HungryProjectile := preload("../hungry_projectile.gd")
const HungryRenderer := preload("hungry_renderer.gd")
const HungryServices := preload("../hungry_services.gd")
const HungrySettings := preload("hungry_settings.gd")
const HungrySound := preload("hungry_sound.gd")
const HungryVoice := preload("hungry_voice.gd")
const HungryWorkshop := preload("../hungry_workshop.gd")
const HungryWorld := preload("../hungry_world.gd")

const BOARD_INTERVAL_SEC := 0.5

## Bots to keep alive in offline mode, so there is something to play against.
@export_range(0, 32, 1) var offline_bots: int = 6

## Play alone against bots even if a link is available. Set by `--offline`.
@export var force_offline: bool = false

## The mode an offline client plays, by preset id. What the map menu (M) changes solo: a mode
## is a whole game here (a server switches between them with `changegame`), so solo it is a
## fresh client on the new preset ([method change_mode_offline]).
@export var offline_preset: StringName = &"classic"

var world: HungryWorld = null
var net: DotNetManager = null
var bridge: HungryNetBridge = null
## Asks a server whether this player may edit it (sv_workbench_remote); null offline.
var workbench_remote: DotGameWorkbenchRemoteClient = null
## The tuning panel's host: F9 solo, the admin's remote panel on a server that allows it.
var workbench: DotGameWorkbench = null
var renderer: HungryRenderer = null
var camera: HungryCamera = null
var sampler: HungryInput = null
var hud: HungryHud = null

## The client half of chat: the channels, the history, the unread counts and the gap
## detection. It decides nothing — every rule is the server's.
var chat: DotChatClient = null

## The client half of voice. Every call on it is guarded, because "there is no microphone"
## is a legitimate machine rather than an error.
var voice: HungryVoice = null

## What the arena has in it that nobody steers. Mirrors, and never spawn.
var hunters: HungryHunters = null
var hazards: HungryHazards = null
var sound: HungrySound = null

## Settings, audio, effects and the console. `sound` above is still what makes the noise;
## this is what decides whether it should, how many at once and how loud.
var presentation: HungryPresentation = null
var screens: DotScreenStack = null
var ui_config: DotUiConfig = null

## This game's own settings as the game reads them: the presentation layer's config, which
## it keeps in step with the player's document. See [HungrySettings].
var settings: HungryConfig = null

## The connection, when there is one.
var link: Node = null

## dot-menu's Escape menu ([HungrySettings]): Loadout, Game, the stock pages, Controls,
## Help & commands on H, and Leave.
var menu: DotMenu = null
## The menu's Loadout page.
var loadout_page: HungryMenus.LoadoutPage = null
var _offline: bool = false
var _tick: int = 0
var _board_accum: float = 0.0

## What the local monster weighed and carried last frame, for the sound. See
## [method _watch_mass].
var _last_mass: float = 0.0
var _last_carried: int = 0
var _last_pieces: int = 0

## When this player last asked to split and to eject, by button, in
## `Time.get_ticks_msec()`. See [method _asked_recently].
var _asked_at: Dictionary = {}

## How long after asking a split or an eject may take to show up in the monster.
##
## Long enough for a round trip, a snapshot interval and the interpolation delay on a real
## connection; short enough that a burst arriving well after the key was let go is not
## heard as a split the player made.
const ASKED_WINDOW_MSEC := 750

## Who ate us, so a dead player has somebody to watch. See [method _watched].
var _watching: int = 0
var _bots: Array[int] = []

## The platform layer (dot-game's [DotGameClient]): the loading cover, closed until the local
## monster exists so nobody sees an empty field or steers before the server has placed them;
## the settings, the Escape menu, the console, Tab and M; the pointer rules and the browser's
## filesystem flush. See [method _ready].
var platform: DotGameClient = null
