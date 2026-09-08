extends Node

## Level 1 V3 game feel: the one entry point for the short SFX and the mobile
## haptics that accompany a gameplay event.
##
## Gameplay never waits on this. `event()` only starts a sound and a vibration,
## and every call site runs after scoring and routing are already final, so the
## simulation stays authoritative and audio can never delay or alter it.
##
## Audio assets are optional. Each stream is looked up once at startup and a
## missing file simply leaves that event silent, so the game is fully playable
## before any SFX exist; `missing_sfx()` reports what is still absent.
##
## This is an autoload rather than a level-owned node for one concrete reason:
## RETRY changes scene immediately, so a level-owned player would be freed
## mid-sound and the click would be cut off.

const SFX_DIR := "res://assets/audio/sfx/"

## Event id -> file name. These seven ids are the whole vocabulary; nothing else
## may call into this singleton.
const SFX := {
	&"block_spawn": "block_spawn.wav",
	&"junction_switch": "junction_switch.wav",
	&"correct_delivery": "correct_delivery.wav",
	&"wrong_delivery": "wrong_delivery.wav",
	&"level_complete": "level_complete.wav",
	&"level_failed": "level_failed.wav",
	&"retry": "retry.wav",
}

## One trim for the whole bank. Per-event balance belongs in the assets
## themselves, so this stays a single number to pull the level down if needed.
const VOLUME_DB := 0.0

## Voices. Enough for the rare overlap (a delivery landing on a spawn) and
## allocated once at startup, so a burst of events never allocates.
const POOL_SIZE := 6

## Event id -> {ms, amp}. Deliberately sparse: only the moments where a physical
## response adds something. Nothing fires for spawn, conveyor motion, block
## movement or idle animation.
const HAPTIC := {
	&"junction_switch": {"ms": 10, "amp": 0.25},
	&"correct_delivery": {"ms": 15, "amp": 0.45},
	&"wrong_delivery": {"ms": 35, "amp": 0.80},
}

## Win is the only pattern: two short pulses rather than one long buzz. `at` is
## the delay in seconds from the event.
const HAPTIC_WIN := [
	{"ms": 18, "amp": 0.45, "at": 0.0},
	{"ms": 26, "amp": 0.70, "at": 0.09},
]

## Desktop is a deliberate no-op. `Input.vibrate_handheld` already ignores
## non-handheld platforms, but gating here keeps the switch in one place and
## lets a build or a test flip it.
var haptics_enabled := true

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _fired := {}
var _haptics_requested := {}


func _ready() -> void:
	for id in SFX:
		var path: String = SFX_DIR + String(SFX[id])
		if ResourceLoader.exists(path):
			_streams[id] = load(path)
	for _i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.volume_db = VOLUME_DB
		add_child(player)
		_players.append(player)
	haptics_enabled = OS.has_feature("mobile")
	var missing := missing_sfx()
	if not missing.is_empty():
		print("[GameFeel] no audio asset for: %s" % ", ".join(missing))


## The single call a gameplay event makes. Safe with no audio assets present.
func event(id: StringName) -> void:
	_fired[id] = int(_fired.get(id, 0)) + 1
	_play(id)
	_vibrate(id)


func _play(id: StringName) -> void:
	var stream = _streams.get(id)
	if stream == null:
		return
	var player := _take_player()
	player.stream = stream
	player.play()


## First idle voice, else the next in rotation so the newest event still lands
## rather than being dropped.
func _take_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	var taken := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return taken


func _vibrate(id: StringName) -> void:
	var pulses: Array = []
	if id == &"level_complete":
		pulses = HAPTIC_WIN
	elif HAPTIC.has(id):
		pulses = [HAPTIC[id]]
	if pulses.is_empty():
		return
	# Counted before the platform gate, so a desktop test can still prove the
	# event routed to exactly one haptic request.
	_haptics_requested[id] = int(_haptics_requested.get(id, 0)) + 1
	for pulse in pulses:
		var at: float = pulse.get("at", 0.0)
		if at <= 0.0:
			_pulse(pulse["ms"], pulse["amp"])
		else:
			get_tree().create_timer(at).timeout.connect(
				_pulse.bind(pulse["ms"], pulse["amp"]), CONNECT_ONE_SHOT)


func _pulse(ms: int, amp: float) -> void:
	if not haptics_enabled:
		return
	Input.vibrate_handheld(ms, amp)


# ---- test support

## Event ids with no audio file on disk yet.
func missing_sfx() -> PackedStringArray:
	var missing := PackedStringArray()
	for id in SFX:
		if not _streams.has(id):
			missing.append(String(id))
	return missing


## How many times each event fired since the last reset.
func fired() -> Dictionary:
	return _fired.duplicate()


## How many times each event asked for a haptic, regardless of platform.
func haptics_requested() -> Dictionary:
	return _haptics_requested.duplicate()


func reset_counters() -> void:
	_fired.clear()
	_haptics_requested.clear()
