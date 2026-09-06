extends Node2D

## Level 1 V3 round controller.
##
## One source -> input conveyor -> junction -> left (red) / right (blue) station.
## The machine is a single baked sprite; this script only drives blocks, the
## junction's logical state, the indicator overlays and scoring.

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

## Route beam is tinted to the destination station it feeds.
const BEAM_LEFT := Color(1, 0.34, 0.28, 0.34)
const BEAM_RIGHT := Color(0.32, 0.56, 1, 0.34)

@export var junction_centre: Vector2 = Vector2(360, 731.609)
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

@onready var _input_path: Path2D = $MovementPaths/InputPath
@onready var _left_path: Path2D = $MovementPaths/LeftOutputPath
@onready var _right_path: Path2D = $MovementPaths/RightOutputPath
@onready var _junction_area: Area2D = $JunctionInput
@onready var _junction_shape: CollisionShape2D = $JunctionInput/JunctionShape
@onready var _left_glow: Polygon2D = $RouteIndicators/LeftArrowGlow
@onready var _left_dim: Polygon2D = $RouteIndicators/LeftArrowDim
@onready var _right_glow: Polygon2D = $RouteIndicators/RightArrowGlow
@onready var _right_dim: Polygon2D = $RouteIndicators/RightArrowDim
@onready var _route_beam: Line2D = $RouteIndicators/RouteBeam
@onready var _tap_ring: Line2D = $RouteIndicators/JunctionTapRing
@onready var _tap_hint: Label = $RouteIndicators/TapHint
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
	_apply_route_indicator(false)
	_start_attention_loops()
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
	if round_state == STATE_PLAYING:
		if block.captured_direction == expected_route:
			correct_count += 1
		else:
			mistake_count += 1
		completed_count += 1
		_update_hud()
	block.play_delivery_finish()
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
	if not _has_tapped:
		_has_tapped = true
		_dismiss_hint()


func _apply_route_indicator(pulse: bool) -> void:
	var left_active := junction_route == ROUTE_LEFT
	_left_glow.self_modulate.a = 1.0 if left_active else 0.0
	_left_dim.self_modulate.a = 0.0 if left_active else 1.0
	_right_glow.self_modulate.a = 0.0 if left_active else 1.0
	_right_dim.self_modulate.a = 1.0 if left_active else 0.0
	# The beam traces the actual active curve, so it can never disagree with it.
	# It starts at the chamber edge rather than the centre, leaving the disc
	# clear for the cube that sits there.
	var active_path: Path2D = _left_path if left_active else _right_path
	var inner_radius: float = _tap_ring.points[0].length()
	var beam_points := PackedVector2Array()
	for p in active_path.curve.get_baked_points():
		if p.distance_to(junction_centre) >= inner_radius:
			beam_points.append(p)
	_route_beam.points = beam_points
	_route_beam.default_color = BEAM_LEFT if left_active else BEAM_RIGHT
	if pulse:
		_pulse(_left_glow if left_active else _right_glow)
		_pulse_beam()


## Idle attention: the tap ring breathes so the junction reads as interactive,
## and the Level 1 hint pulses until the player taps for the first time.
func _start_attention_loops() -> void:
	var ring_tw: Tween = create_tween().set_loops()
	ring_tw.tween_property(_tap_ring, "scale", Vector2(1.10, 1.10), 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ring_tw.parallel().tween_property(_tap_ring, "modulate", Color(1.7, 1.7, 1.7, 1.0), 0.75)
	ring_tw.tween_property(_tap_ring, "scale", Vector2.ONE, 0.75) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ring_tw.parallel().tween_property(_tap_ring, "modulate", Color(1, 1, 1, 1), 0.75)

	var hint_tw: Tween = create_tween().set_loops()
	hint_tw.tween_property(_tap_hint, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
	hint_tw.tween_property(_tap_hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


func _dismiss_hint() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(_tap_hint, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): _tap_hint.visible = false)


func _pulse_beam() -> void:
	_route_beam.modulate = Color(1, 1, 1, 1)
	var tw: Tween = create_tween()
	tw.tween_property(_route_beam, "modulate", Color(2.2, 2.2, 2.2, 1.0), 0.09)
	tw.tween_property(_route_beam, "modulate", Color(1, 1, 1, 1), 0.28)


func _pulse(node: Polygon2D) -> void:
	node.modulate = Color(1, 1, 1, 1)
	node.scale = Vector2.ONE
	var tw: Tween = create_tween()
	tw.tween_property(node, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.08)
	tw.parallel().tween_property(node, "scale", Vector2(1.18, 1.18), 0.08)
	tw.tween_property(node, "modulate", Color(1, 1, 1, 1), 0.2)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.2)


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
	_result_title.text = "LEVEL COMPLETE" if round_state == STATE_WON else "OUT OF ORDER"
	_result_summary.text = "Correct: %d / %d\nMistakes: %d" % [correct_count, TOTAL_BLOCKS, mistake_count]
	_result_overlay.visible = true


func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file("res://level_1_v3.tscn")


func _update_hud() -> void:
	_correct_label.text = "Correct: %d" % correct_count
	_blocks_label.text = "Blocks: %d / %d" % [completed_count, TOTAL_BLOCKS]
	_mistakes_label.text = "Mistakes: %d" % mistake_count
