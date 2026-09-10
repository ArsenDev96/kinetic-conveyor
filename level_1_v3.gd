extends Node2D

## Level 1 V3 round controller.
##
## One source -> input conveyor -> junction -> left (red) / right (blue) station.
## The machine is a single baked sprite; this script drives blocks, the
## junction's logical state, the indicator overlays, scoring, and the Phase 3
## motion feedback (belt treads, source beacon/recoil, junction punch, station
## reactions). Motion never touches gameplay: paths, speeds, capture and scoring
## are exactly as before.

const BlockScript := preload("res://v3_block.gd")

const ROUTE_LEFT := 0
const ROUTE_RIGHT := 1

const STATE_PLAYING := 0
const STATE_WON := 1
const STATE_LOST := 2

const COLOUR_RED := 0
const COLOUR_BLUE := 1

## Deterministic round: R R B R B B R B R B
const BLOCK_SEQUENCE: Array[int] = [
	COLOUR_RED, COLOUR_RED, COLOUR_BLUE, COLOUR_RED, COLOUR_BLUE,
	COLOUR_BLUE, COLOUR_RED, COLOUR_BLUE, COLOUR_RED, COLOUR_BLUE,
]
const TOTAL_BLOCKS := 10
const SPAWN_INTERVAL := 1.8
const BLOCK_SPEED := 100.0
const MISTAKE_LIMIT := 3
const TAP_DEBOUNCE_MS := 90

## Route indication: a soft illuminated lane lying ON the belt, tinted to the
## destination it feeds. A wide faint halo sits under a narrower band; both are
## feathered across their width in the scene, and their combined additive alpha
## peaks near 0.23, so the tread and its chevrons stay clearly readable. Neither
## layer may cover the Junction platform or reach into a bin.
const BEAM_CORE_LEFT := Color(1, 0.42, 0.34, 0.3)
const BEAM_GLOW_LEFT := Color(1, 0.38, 0.29, 0.2)
const BEAM_CORE_RIGHT := Color(0.44, 0.66, 1, 0.3)
const BEAM_GLOW_RIGHT := Color(0.38, 0.6, 1, 0.2)
## Trim, re-measured on the current machine art about the true chamber centre
## (359.68, 659.56): the dark Junction disc ends at r 59, the silver rim at r 72
## and the yellow chamber segments at r 83, while the tread first becomes visible
## at r 84 -- so the band starts on clear tread. The bin rim starts at y 893, so
## the band stops short of it and never enters the open interior.
const BEAM_START_RADIUS := 90.0
const BEAM_END_Y := 884.0
## Half the widest band layer (RouteBeamGlow, 27 px). Round end caps extend the
## drawn band this far past its first and last point, so the trim above is
## applied to the caps rather than to the centreline - the limits stay the ones
## measured on the art, and the band as drawn still honours them.
const BEAM_HALF_WIDTH := 13.5

# ---------------------------------------------------------------- motion tuning
## Apparent belt speed, world px/s. Tied to BLOCK_SPEED so the tread travels at
## exactly the speed of the cube on it: any other value makes the cube visibly
## slip along the belt. Applied to all three treads.
const BELT_SPEED_WORLD := BLOCK_SPEED
## Source beacon idle breathing (only the beacon overlay changes).
const BEACON_IDLE_MIN := 0.85
const BEACON_IDLE_MAX := 1.15
const BEACON_IDLE_HALF := 0.7
## Spawn event.
const BEACON_FLASH := 1.9
const SPAWN_RECOIL_WORLD_PX := 1.7
const MOUTH_FLASH_ALPHA := 0.85
## Junction tap punch (~0.23 s total).
const JUNCTION_PUNCH_IN := 0.07
const JUNCTION_PUNCH_OUT := 0.16
## Tap ring: thin warm amber, breathing on alpha rather than scale so it never
## grows over the silver rim. Effective alpha = default_color.a (0.34) * modulate.a
## * self_modulate.a, so the idle breath sits in 0.27-0.34 and the tap peaks at
## ~0.58 - present, but never a loading spinner.
const RING_IDLE_LOW := 0.78
const RING_IDLE_HALF := 0.9
const RING_PUNCH := Color(1.1, 1.02, 0.95, 1.7)
## First-tap ripple: two rings expanding from the plate centre, r 22 -> 62 in
## a 50-unit circle, so they always stay inside the silver rim (r 72). Half a
## period apart; retired with the hint on the first tap.
const RIPPLE_PERIOD := 1.2
const RIPPLE_SCALE_MIN := 0.44
const RIPPLE_SCALE_MAX := 1.24
const RIPPLE_ALPHA := 1.0
## Selected arrow: gentle warm throb so the Junction itself carries the routing.
const ARROW_IDLE_PEAK := 1.35
const ARROW_IDLE_SCALE := 1.08
## Unlit lamp: the painted yellow pulled down to a dark amber, still clearly a lamp.
const LAMP_UNLIT := Color(0.42, 0.38, 0.34, 1.0)
const ARROW_IDLE_HALF := 0.85
## Selected-destination accent, deliberately far weaker than a delivery pulse.
const STATION_SELECT_RED := Color(1.6, 0.62, 0.55, 0.0)
const STATION_SELECT_BLUE := Color(0.55, 0.8, 1.7, 0.0)
const STATION_SELECT_HOLD := 0.16
const STATION_SELECT_PEAK := 0.3
## Junction plate steering. The plate is a belt whose frame rotates, so its slats
## face the exit the cargo will take and the surface travels that way. The two
## angles are the output arms' own directions, so plate and arm read as one belt.
## Purely presentational: junction_route decides the route, never this angle.
const PLATE_ANGLE_LEFT := 0.70699
const PLATE_ANGLE_RIGHT := -0.70699
const PLATE_SWING := 0.28
## Destination reactions.
const DELIVERY_HOLD := 0.2
## The block vanishes deep inside the bin, where a burst would be lost against
## the dark interior, so the particles sit this far above it - at the bin mouth,
## popping up over the rim where they read.
const DELIVERY_FX_LIFT_PX := 44.0
## The block that ends the round still has its chime or its clunk landing with
## the station reaction one DELIVERY_HOLD later, so the result sting waits for
## it instead of talking over it. The overlay itself is not delayed.
const RESULT_STING_DELAY := DELIVERY_HOLD + 0.08
const STATION_PULSE_SCALE := 1.025
const STATION_TINT_RED := Color(1.55, 1.25, 1.2, 1.0)
const STATION_TINT_BLUE := Color(1.2, 1.32, 1.6, 1.0)
const STATION_WARN := Color(1.75, 1.15, 1.05, 1.0)
const STATION_SHAKE_WORLD_PX := 3.5

@export var junction_centre: Vector2 = Vector2(359.68, 659.56)
@export var block_sprite_scale: float = 0.047298
@export var block_sprite_offset: Vector2 = Vector2(0.5, 9.5)
@export var block_red_texture: Texture2D
@export var block_blue_texture: Texture2D

var junction_route: int = ROUTE_LEFT
var round_state: int = STATE_PLAYING
var correct_count := 0
var mistake_count := 0
var completed_count := 0
var spawned_count := 0

var _capture_offset := 0.0
var _spawn_timer := 0.0
var _last_tap_ms := -10000
var _has_tapped := false

## Motion rig: authored/base values of every animated property, captured once
## in _ready(). Every effect restores its node to these values before it starts
## and tweens back to them, so repeated events can never accumulate drift.
var _base: Dictionary = {}
## One tween per effect key; starting an effect kills its predecessor.
var _fx: Dictionary = {}

@onready var _input_path: Path2D = $MovementPaths/InputPath
@onready var _left_path: Path2D = $MovementPaths/LeftOutputPath
@onready var _right_path: Path2D = $MovementPaths/RightOutputPath
## Delivery bursts, parked just above the two delivery points in _place_delivery_fx().
@onready var _burst_red: CPUParticles2D = $DeliveryFx/CorrectBurstRed
@onready var _burst_blue: CPUParticles2D = $DeliveryFx/CorrectBurstBlue
@onready var _junction_area: Area2D = $JunctionInput
@onready var _junction_shape: CollisionShape2D = $JunctionInput/JunctionShape
@onready var _left_glow: Sprite2D = $MachineVisual/ArrowLeft
@onready var _right_glow: Sprite2D = $MachineVisual/ArrowRight
@onready var _route_beam: Line2D = $RouteIndicators/RouteBeam
@onready var _route_glow: Line2D = $RouteIndicators/RouteBeamGlow
@onready var _tap_ring: Line2D = $RouteIndicators/JunctionTapRing
@onready var _tap_hint: Label = $RouteIndicators/TapHint
@onready var _tap_ripple: Node2D = $RouteIndicators/TapRipple
@onready var _hint_leader: Node2D = $RouteIndicators/TapHintLeader
@onready var _machine: Sprite2D = $MachineVisual
@onready var _tread_input: Sprite2D = $MachineVisual/TreadInput
@onready var _tread_left: Sprite2D = $MachineVisual/TreadLeft
@onready var _tread_right: Sprite2D = $MachineVisual/TreadRight
@onready var _disc: Sprite2D = $MachineVisual/JunctionDisc
@onready var _source_body: Sprite2D = $MachineVisual/SourceBody
@onready var _beacon: Sprite2D = $MachineVisual/SourceBody/SourceBeacon
@onready var _mouth_flash: Sprite2D = $MachineVisual/MouthFlash
@onready var _station_red: Sprite2D = $MachineVisual/StationRed
@onready var _station_blue: Sprite2D = $MachineVisual/StationBlue
@onready var _station_red_select: Sprite2D = $MachineVisual/StationRedSelect
@onready var _station_blue_select: Sprite2D = $MachineVisual/StationBlueSelect
@onready var _correct_label: Label = $HUD/Counters/CorrectLabel
@onready var _blocks_label: Label = $HUD/Counters/BlocksLabel
@onready var _mistakes_label: Label = $HUD/Counters/MistakesLabel
@onready var _result_overlay: Control = $HUD/ResultOverlay
@onready var _result_title: Label = $HUD/ResultOverlay/ResultPanel/ResultTitle
@onready var _result_summary: Label = $HUD/ResultOverlay/ResultPanel/ResultSummary
@onready var _retry_button: Button = $HUD/ResultOverlay/ResultPanel/RetryButton


func _ready() -> void:
	# Capture point is derived from the curve itself, not a hardcoded progress.
	_capture_offset = _input_path.curve.get_closest_offset(junction_centre - _input_path.position)
	_junction_area.input_event.connect(_on_junction_input_event)
	_retry_button.pressed.connect(_on_retry_pressed)
	_result_overlay.visible = false
	_setup_motion_rig()
	_place_delivery_fx()
	_apply_route_indicator(false)
	_start_attention_loops()
	_start_beacon_idle()
	_update_hud()


func _process(delta: float) -> void:
	if round_state != STATE_PLAYING:
		return
	if spawned_count >= TOTAL_BLOCKS:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_block()
		_spawn_timer = SPAWN_INTERVAL


# ---------------------------------------------------------------- blocks

func _spawn_block() -> void:
	var colour: int = BLOCK_SEQUENCE[spawned_count]
	var block := BlockScript.new()
	_input_path.add_child(block)
	block.setup(
		colour,
		block_red_texture if colour == COLOUR_RED else block_blue_texture,
		block_sprite_scale,
		block_sprite_offset,
		_capture_offset,
		BLOCK_SPEED
	)
	block.captured.connect(_on_block_captured)
	block.delivered.connect(_on_block_delivered)
	spawned_count += 1
	_update_hud()
	_play_spawn_feedback()
	GameFeel.event(&"block_spawn")


## Reached JUNCTION_CENTER. Read the junction state exactly once, store it,
## and hand the block to the matching output path. Idempotent by route_locked.
func _on_block_captured(block) -> void:
	if block.route_locked:
		return
	block.captured_direction = junction_route
	block.route_locked = true
	var target: Path2D = _left_path if block.captured_direction == ROUTE_LEFT else _right_path
	var current: Node = block.get_parent()
	if current == target:
		return
	current.remove_child(block)
	target.add_child(block)


func _on_block_delivered(block) -> void:
	# Left station is RED, right station is BLUE.
	var expected_route: int = ROUTE_LEFT if block.colour == COLOUR_RED else ROUTE_RIGHT
	var correct: bool = block.captured_direction == expected_route
	# Read before _check_round_end() below can move the round to a terminal
	# state. The delivery that ends the round still earns its own feedback; a
	# block already in flight at that moment must not add another delivery cue.
	var round_was_live: bool = round_state == STATE_PLAYING
	if round_was_live:
		if correct:
			correct_count += 1
		else:
			mistake_count += 1
		completed_count += 1
		_update_hud()
	# Presentation only: the scoring above is already final.
	var station: Sprite2D = _station_red if block.captured_direction == ROUTE_LEFT else _station_blue
	block.play_delivery_finish(correct)
	_play_station_reaction(station, correct, round_was_live)
	_check_round_end()


# ---------------------------------------------------------------- junction

## Area2D picking path (fires when the viewport does physics object picking).
func _on_junction_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _press_position(event) != null:
		_try_toggle()


## Direct fallback so the tap works regardless of viewport picking configuration.
## The Area2D + its CollisionShape2D stay the single source of truth for the hit
## region; this only tests the press point against that same circle. Both paths
## share the debounce, so a doubled event cannot toggle twice.
func _unhandled_input(event: InputEvent) -> void:
	var pos = _press_position(event)
	if pos == null:
		return
	if _junction_area.global_position.distance_to(pos) > _junction_shape.shape.radius:
		return
	_try_toggle()


## Returns the press position for a mouse-down / touch-down, else null.
func _press_position(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			return event.position
	elif event is InputEventScreenTouch:
		if event.pressed:
			return event.position
	return null


func _try_toggle() -> void:
	if round_state != STATE_PLAYING:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < TAP_DEBOUNCE_MS:
		return
	_last_tap_ms = now
	toggle_route()


func toggle_route() -> void:
	junction_route = ROUTE_RIGHT if junction_route == ROUTE_LEFT else ROUTE_LEFT
	_apply_route_indicator(true)
	GameFeel.event(&"junction_switch")
	if not _has_tapped:
		_has_tapped = true
		_dismiss_hint()


func _apply_route_indicator(pulse: bool) -> void:
	var left_active := junction_route == ROUTE_LEFT
	_set_lamp(_left_glow, left_active)
	_set_lamp(_right_glow, not left_active)
	# The band traces the actual active curve, so it can never disagree with it.
	# It is trimmed at both ends: it begins past the Junction platform and its
	# surrounding hardware, and stops above the bin rim, so it only ever lies on
	# visible conveyor tread. The centreline is inset by BEAM_HALF_WIDTH at each
	# end so the round caps, not the points, land exactly on those limits.
	var active_path: Path2D = _left_path if left_active else _right_path
	var beam_points := PackedVector2Array()
	var start_radius := BEAM_START_RADIUS + BEAM_HALF_WIDTH
	var end_y := BEAM_END_Y - BEAM_HALF_WIDTH
	for p in active_path.curve.get_baked_points():
		if p.distance_to(junction_centre) >= start_radius and p.y <= end_y:
			beam_points.append(p)
	_route_beam.points = beam_points
	_route_glow.points = beam_points
	_route_beam.default_color = BEAM_CORE_LEFT if left_active else BEAM_CORE_RIGHT
	_route_glow.default_color = BEAM_GLOW_LEFT if left_active else BEAM_GLOW_RIGHT
	_apply_station_selection(left_active, pulse)
	_steer_plate(left_active, pulse)
	if pulse:
		_play_junction_tap_feedback(left_active)
	else:
		_start_arrow_idle(_left_glow if left_active else _right_glow)


## Swings the Junction plate so its slats face the selected exit. On a tap it
## eases across; on the initial state it snaps, so the round opens already aligned.
func _steer_plate(left_active: bool, pulse: bool) -> void:
	_fx_kill("plate_swing")
	var target: float = PLATE_ANGLE_LEFT if left_active else PLATE_ANGLE_RIGHT
	if not pulse:
		_disc.material.set_shader_parameter("plate_angle", target)
		return
	var tw := _fx_tween("plate_swing")
	tw.tween_method(
		func(v: float) -> void: _disc.material.set_shader_parameter("plate_angle", v),
		float(_disc.material.get_shader_parameter("plate_angle")), target, PLATE_SWING
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Idle attention: the tap ring breathes so the junction reads as interactive,
## and the Level 1 hint pulses until the player taps for the first time.
## The ring loop animates `modulate` alpha only - never scale, so it can never
## grow out over the silver rim - while the tap punch below uses
## `self_modulate`/`width`, so the two never fight over a property.
func _start_attention_loops() -> void:
	var ring_tw: Tween = create_tween().set_loops()
	ring_tw.tween_property(_tap_ring, "modulate:a", RING_IDLE_LOW, RING_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ring_tw.tween_property(_tap_ring, "modulate:a", 1.0, RING_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_fx["ring_idle"] = ring_tw

	var hint_tw: Tween = create_tween().set_loops()
	hint_tw.tween_property(_tap_hint, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
	hint_tw.parallel().tween_property(_hint_leader, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
	hint_tw.tween_property(_tap_hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	hint_tw.parallel().tween_property(_hint_leader, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	_fx["hint_idle"] = hint_tw
	_start_tap_ripple()


## Each ring grows from the plate centre and fades as it reaches the rim; the
## second ring starts half a period later so the pulse never pauses.
func _start_tap_ripple() -> void:
	var rings := _tap_ripple.get_children()
	for i in rings.size():
		var ring: Line2D = rings[i]
		var key := "ripple%d" % i
		var tw := _fx_tween(key)
		ring.modulate.a = 0.0
		tw.tween_interval(RIPPLE_PERIOD * 0.5 * i)
		tw.tween_callback(func(): _loop_ripple(ring, key))


func _loop_ripple(ring: Line2D, key: String) -> void:
	var tw := _fx_tween(key).set_loops()
	tw.tween_property(ring, "scale", Vector2.ONE * RIPPLE_SCALE_MAX, RIPPLE_PERIOD) \
		.from(Vector2.ONE * RIPPLE_SCALE_MIN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, RIPPLE_PERIOD) \
		.from(RIPPLE_ALPHA).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _dismiss_hint() -> void:
	_fx_kill("hint_idle")
	for i in _tap_ripple.get_child_count():
		_fx_kill("ripple%d" % i)
	var tw: Tween = create_tween()
	tw.tween_property(_tap_hint, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(_hint_leader, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(_tap_ripple, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		_tap_hint.visible = false
		_hint_leader.visible = false
		_tap_ripple.visible = false)


# ---------------------------------------------------------------- motion rig

func _setup_motion_rig() -> void:
	# Belt speed is derived from the authored machine scale so all three treads
	# share one physical speed regardless of how the sprite is scaled.
	var speed_tex: float = BELT_SPEED_WORLD / _machine.scale.x
	# The Junction plate is a belt too, so it shares the one physical speed.
	for tread in [_tread_input, _tread_left, _tread_right, _disc]:
		tread.material.set_shader_parameter("speed_tex", speed_tex)
	_rig(_left_glow, ["position", "scale", "modulate"])
	_rig(_right_glow, ["position", "scale", "modulate"])
	_rig(_tap_ring, ["position", "self_modulate", "modulate", "width"])
	for ring in _tap_ripple.get_children():
		_rig(ring, ["scale", "modulate"])
	_rig(_hint_leader, ["modulate"])
	_rig(_route_beam, ["position", "modulate"])
	_rig(_route_glow, ["position", "modulate"])
	_rig(_source_body, ["position", "scale", "rotation", "modulate"])
	_rig(_beacon, ["position", "scale", "modulate"])
	_rig(_mouth_flash, ["position", "scale", "modulate"])
	_rig(_station_red, ["position", "scale", "rotation", "modulate"])
	_rig(_station_blue, ["position", "scale", "rotation", "modulate"])
	_rig(_machine, ["position", "scale", "rotation", "modulate"])


func _rig(node: CanvasItem, props: Array) -> void:
	var snapshot := {}
	for p in props:
		snapshot[p] = node.get(p)
	_base[node] = snapshot


func _restore(node: CanvasItem) -> void:
	for p in _base[node]:
		node.set(p, _base[node][p])


func _fx_tween(key: String) -> Tween:
	_fx_kill(key)
	var tw: Tween = create_tween()
	_fx[key] = tw
	return tw


func _fx_kill(key: String) -> void:
	var old = _fx.get(key)
	if old != null and old.is_valid():
		old.kill()
	_fx.erase(key)


## World px -> MachineVisual local px (overlays live in its texture space).
func _machine_px(world_px: float) -> float:
	return world_px / _machine.scale.x


# ---- source

func _start_beacon_idle() -> void:
	_fx_kill("beacon_flash")
	_restore(_beacon)
	var tw := _fx_tween("beacon_idle")
	tw.set_loops()
	tw.tween_property(_beacon, "modulate", Color(BEACON_IDLE_MIN, BEACON_IDLE_MIN, BEACON_IDLE_MIN, 1.0), BEACON_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_beacon, "modulate", Color(BEACON_IDLE_MAX, BEACON_IDLE_MAX, BEACON_IDLE_MAX, 1.0), BEACON_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _play_spawn_feedback() -> void:
	# Beacon: one quick bright flash, then the idle breathing resumes from base.
	_fx_kill("beacon_idle")
	_restore(_beacon)
	var flash := _fx_tween("beacon_flash")
	flash.tween_property(_beacon, "modulate", Color(BEACON_FLASH, BEACON_FLASH, BEACON_FLASH, 1.0), 0.04)
	flash.tween_property(_beacon, "modulate", _base[_beacon]["modulate"], 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flash.tween_callback(_start_beacon_idle)

	# Housing: tiny upward recoil, eased back to the exact authored position.
	_restore(_source_body)
	var base_pos: Vector2 = _base[_source_body]["position"]
	var recoil := _fx_tween("source_recoil")
	recoil.tween_property(_source_body, "position", base_pos + Vector2(0.0, -_machine_px(SPAWN_RECOIL_WORLD_PX)), 0.05) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	recoil.tween_property(_source_body, "position", base_pos, 0.14) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Mouth: small additive flash where the belt leaves the housing.
	_restore(_mouth_flash)
	var mouth := _fx_tween("mouth_flash")
	mouth.tween_property(_mouth_flash, "modulate:a", MOUTH_FLASH_ALPHA, 0.04)
	mouth.tween_property(_mouth_flash, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---- junction

func _play_junction_tap_feedback(left_active: bool) -> void:
	# Both arrows are restored so a fast LEFT/RIGHT/LEFT flurry cannot leave the
	# previously active arrow mid-punch or mid-throb. Active/inactive alpha
	# lives in self_modulate and is untouched here.
	_fx_kill("arrow_idle")
	_restore(_left_glow)
	_restore(_right_glow)
	var arrow: Sprite2D = _left_glow if left_active else _right_glow
	var punch := _fx_tween("arrow_punch")
	punch.tween_property(arrow, "modulate", Color(1.75, 1.75, 1.75, 1.0), JUNCTION_PUNCH_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	punch.parallel().tween_property(arrow, "scale", _base[arrow]["scale"] * 1.18, JUNCTION_PUNCH_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	punch.tween_property(arrow, "modulate", _base[arrow]["modulate"], JUNCTION_PUNCH_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	punch.parallel().tween_property(arrow, "scale", _base[arrow]["scale"], JUNCTION_PUNCH_OUT) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The selected arrow resumes its idle throb once the punch has landed, so
	# the two never animate `modulate` at the same time.
	punch.tween_callback(func(): _start_arrow_idle(arrow))

	# Ring: brighten and thicken briefly. `modulate` belongs to the idle breath,
	# so the punch multiplies through self_modulate instead.
	var ring := _fx_tween("ring_pulse")
	_tap_ring.self_modulate = _base[_tap_ring]["self_modulate"]
	_tap_ring.width = _base[_tap_ring]["width"]
	ring.tween_property(_tap_ring, "self_modulate", RING_PUNCH, JUNCTION_PUNCH_IN)
	ring.parallel().tween_property(_tap_ring, "width", _base[_tap_ring]["width"] * 1.5, JUNCTION_PUNCH_IN)
	ring.tween_property(_tap_ring, "self_modulate", _base[_tap_ring]["self_modulate"], JUNCTION_PUNCH_OUT)
	ring.parallel().tween_property(_tap_ring, "width", _base[_tap_ring]["width"], JUNCTION_PUNCH_OUT)

	_restore(_route_beam)
	_restore(_route_glow)
	var beam := _fx_tween("beam_pulse")
	beam.tween_property(_route_beam, "modulate", Color(1.6, 1.6, 1.6, 1.0), JUNCTION_PUNCH_IN)
	beam.parallel().tween_property(_route_glow, "modulate", Color(1.6, 1.6, 1.6, 1.0), JUNCTION_PUNCH_IN)
	beam.tween_property(_route_beam, "modulate", _base[_route_beam]["modulate"], JUNCTION_PUNCH_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	beam.parallel().tween_property(_route_glow, "modulate", _base[_route_glow]["modulate"], JUNCTION_PUNCH_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The lamps are the painted arrows on the housing, drawn through their masks:
## lit is the artwork itself (with the idle throb and tap punch on `modulate`),
## unlit darkens it through self_modulate so the two never share a property.
func _set_lamp(lamp: Sprite2D, lit: bool) -> void:
	lamp.self_modulate = Color(1, 1, 1, 1) if lit else LAMP_UNLIT


## Gentle warm throb on whichever arrow is currently selected. Always starts
## from the cached base modulate, so repeated toggles cannot accumulate.
func _start_arrow_idle(arrow: Sprite2D) -> void:
	_fx_kill("arrow_idle")
	_restore(_left_glow)
	_restore(_right_glow)
	var tw := _fx_tween("arrow_idle")
	tw.set_loops()
	tw.tween_property(arrow, "modulate", Color(ARROW_IDLE_PEAK, ARROW_IDLE_PEAK, ARROW_IDLE_PEAK, 1.0), ARROW_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(arrow, "scale", _base[arrow]["scale"] * ARROW_IDLE_SCALE, ARROW_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(arrow, "modulate", Color(1, 1, 1, 1), ARROW_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(arrow, "scale", _base[arrow]["scale"], ARROW_IDLE_HALF) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Very restrained tint on the destination the junction currently feeds. These
## overlay nodes are driven purely by selection state (constant target alphas,
## so nothing can accumulate) and are separate from StationRed / StationBlue,
## which the delivery reactions animate.
func _apply_station_selection(left_active: bool, pulse: bool) -> void:
	_set_station_select(_station_red_select, STATION_SELECT_RED, left_active, pulse)
	_set_station_select(_station_blue_select, STATION_SELECT_BLUE, not left_active, pulse)


func _set_station_select(node: Sprite2D, tint: Color, on: bool, pulse: bool) -> void:
	var key := "select_%s" % node.name
	_fx_kill(key)
	if not pulse:
		node.modulate = Color(tint.r, tint.g, tint.b, STATION_SELECT_HOLD if on else 0.0)
		return
	var tw := _fx_tween(key)
	if on:
		tw.tween_property(node, "modulate:a", STATION_SELECT_PEAK, 0.10).set_trans(Tween.TRANS_SINE)
		tw.tween_property(node, "modulate:a", STATION_SELECT_HOLD, 0.28) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(node, "modulate:a", 0.0, 0.22) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---- destinations

## Runs after the same DELIVERY_HOLD the cube uses, so the station reacts the
## moment the cube starts its squash (correct) or rejection bounce (wrong).
func _play_station_reaction(station: Sprite2D, correct: bool, feedback: bool = true) -> void:
	var key := "station_%s" % station.name
	_restore(station)
	var base_mod: Color = _base[station]["modulate"]
	var base_scale: Vector2 = _base[station]["scale"]
	var base_pos: Vector2 = _base[station]["position"]
	var tw := _fx_tween(key)
	tw.tween_interval(DELIVERY_HOLD)
	# Sound, haptic and particles ride the station's own tween, so they land
	# on the same frame as the tint or the shake rather than at arrival. They
	# are skipped outright for a block that lands after the round already ended,
	# so a late arrival cannot read as a fourth mistake.
	if feedback:
		tw.tween_callback(_play_delivery_feedback.bind(station, correct))
	if correct:
		var tint: Color = STATION_TINT_RED if station == _station_red else STATION_TINT_BLUE
		tw.tween_property(station, "modulate", tint, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(station, "scale", base_scale * STATION_PULSE_SCALE, 0.08) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(station, "modulate", base_mod, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(station, "scale", base_scale, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		var dx := _machine_px(STATION_SHAKE_WORLD_PX)
		tw.tween_property(station, "modulate", STATION_WARN, 0.05)
		tw.tween_property(station, "position", base_pos + Vector2(dx, 0), 0.05)
		tw.parallel().tween_property(station, "modulate", base_mod, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(station, "position", base_pos + Vector2(-dx, 0), 0.05)
		tw.tween_property(station, "position", base_pos + Vector2(dx * 0.55, 0), 0.05)
		tw.tween_property(station, "position", base_pos + Vector2(-dx * 0.25, 0), 0.04)
		tw.tween_property(station, "position", base_pos, 0.04)


## Parks each burst on its own delivery point, read from the output curve, so the
## particles appear exactly where the block vanishes and this never duplicates
## the authored path geometry. Runs once; the emitters do not move again.
func _place_delivery_fx() -> void:
	var lift := Vector2(0.0, -DELIVERY_FX_LIFT_PX)
	_burst_red.global_position = _delivery_point(_left_path) + lift
	_burst_blue.global_position = _delivery_point(_right_path) + lift


func _delivery_point(path: Path2D) -> Vector2:
	return path.to_global(path.curve.sample_baked(path.curve.get_baked_length()))


## Fired from the station tween, so it is already in step with the destination
## reaction. Scoring happened at arrival and is untouched here.
func _play_delivery_feedback(station: Sprite2D, correct: bool) -> void:
	GameFeel.event(&"correct_delivery" if correct else &"wrong_delivery")
	if not correct:
		# No sparks on a rejection, deliberately. The reject bounce, the warn
		# flash, the station shake, the clunk and the stronger haptic already say
		# it; more importantly a second burst at the same bin mouth would rhyme
		# with the correct one, blurring the very distinction this feedback
		# exists to draw. The pop belongs to "accepted" alone.
		return
	var burst: CPUParticles2D = _burst_red if station == _station_red else _burst_blue
	burst.restart()


# ---- test support

## True while any one-shot effect tween is still running (idle loops excluded).
func is_motion_busy() -> bool:
	for key in _fx:
		if key.ends_with("_idle"):
			continue
		var tw = _fx[key]
		if tw != null and tw.is_valid() and tw.is_running():
			return true
	return false


## Stops the idle loops and restores their nodes so every rigged property can
## be compared against its authored value.
func stop_idle_loops_for_test() -> void:
	_fx_kill("beacon_idle")
	_fx_kill("ring_idle")
	_fx_kill("hint_idle")
	for i in _tap_ripple.get_child_count():
		_fx_kill("ripple%d" % i)
	_fx_kill("arrow_idle")
	_restore(_beacon)
	_restore(_tap_ring)
	for ring in _tap_ripple.get_children():
		_restore(ring)
	_restore(_hint_leader)
	_restore(_left_glow)
	_restore(_right_glow)


## Max deviation of every rigged property from its authored value.
func get_motion_drift_report() -> Dictionary:
	var report := {}
	for node in _base:
		var deltas := {}
		for p in _base[node]:
			var cur = node.get(p)
			var ref = _base[node][p]
			var d := 0.0
			match typeof(cur):
				TYPE_VECTOR2:
					d = (cur - ref).length()
				TYPE_COLOR:
					d = maxf(maxf(absf(cur.r - ref.r), absf(cur.g - ref.g)), maxf(absf(cur.b - ref.b), absf(cur.a - ref.a)))
				_:
					d = absf(float(cur) - float(ref))
			deltas[p] = d
		report[String(node.name)] = deltas
	return report


# ---------------------------------------------------------------- round

func _check_round_end() -> void:
	if round_state != STATE_PLAYING:
		return
	if mistake_count >= MISTAKE_LIMIT:
		round_state = STATE_LOST
		_show_result()
	elif completed_count >= TOTAL_BLOCKS:
		round_state = STATE_WON
		_show_result()


func _show_result() -> void:
	# Interaction is over, so retire its affordances too.
	_junction_area.input_pickable = false
	_tap_ring.visible = false
	_tap_hint.visible = false
	_hint_leader.visible = false
	_tap_ripple.visible = false
	_result_title.text = "LEVEL COMPLETE" if round_state == STATE_WON else "OUT OF ORDER"
	_result_summary.text = "Correct: %d / %d\nMistakes: %d" % [correct_count, TOTAL_BLOCKS, mistake_count]
	_result_overlay.visible = true
	# Routed through this level rather than straight at the autoload, so the
	# pending sting is owned by the round that earned it: RETRY inside the delay
	# frees this node, Godot drops the connection with it, and the finished
	# round's sting cannot play over the fresh one. Nothing to cancel by hand.
	var sting := &"level_complete" if round_state == STATE_WON else &"level_failed"
	get_tree().create_timer(RESULT_STING_DELAY).timeout.connect(
		_play_result_sting.bind(sting), CONNECT_ONE_SHOT)


## Sole target of the result-sting timer. Reached only while this level is still
## in the tree, which is exactly the lifecycle guarantee the scheduling relies on.
func _play_result_sting(sting: StringName) -> void:
	GameFeel.event(sting)


func _on_retry_pressed() -> void:
	GameFeel.event(&"retry")
	get_tree().change_scene_to_file("res://level_1_v3.tscn")


func _update_hud() -> void:
	_correct_label.text = "Correct: %d" % correct_count
	_blocks_label.text = "Blocks: %d / %d" % [completed_count, TOTAL_BLOCKS]
	_mistakes_label.text = "Mistakes: %d" % mistake_count
