extends Area2D

enum Route { LEFT, RIGHT }

const ROUTE_ROTATION_LEFT := PI / 4.0
const ROUTE_ROTATION_RIGHT := -PI / 4.0
const INPUT_DEBOUNCE_MSEC := 85
const PRESS_SCALE := 0.92
const PRESS_DOWN_DURATION := 0.05
const PRESS_RELEASE_DURATION := 0.11
const ROTATION_DURATION := 0.18
const PULSE_BRIGHTNESS := 1.35
const PULSE_IN_DURATION := 0.1
const PULSE_OUT_DURATION := 0.15

@export var initial_route: Route = Route.LEFT

var current_route: Route:
	set(value):
		current_route = value
		_apply_route_visuals()
var interaction_enabled := true
var _last_toggle_time := -1000
var _base_arrow_modulate := Color.WHITE
var _pulse_arrow_modulate := Color.WHITE
var _rotation_tween: Tween
var _press_tween: Tween
var _pulse_tween: Tween
@onready var junction_visual: Node2D = $JunctionVisual
@onready var direction_marker: Node2D = $JunctionVisual/DirectionMarker
@onready var direction_arrow: Sprite2D = $JunctionVisual/DirectionMarker/DirectionArrow


func _ready() -> void:
	_base_arrow_modulate = direction_arrow.modulate
	_pulse_arrow_modulate = Color(
		_base_arrow_modulate.r * PULSE_BRIGHTNESS,
		_base_arrow_modulate.g * PULSE_BRIGHTNESS,
		_base_arrow_modulate.b * PULSE_BRIGHTNESS,
		_base_arrow_modulate.a
	)
	current_route = initial_route


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _is_press(event):
		_try_toggle()


# A touchscreen tap can also raise a synthesized mouse button event when
# emulate_mouse_from_touch is on. Emulation is left enabled globally so that
# regular UI controls keep working, so the synthesized copy is filtered here
# instead: one physical tap must produce exactly one toggle.
func _is_press(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return false
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	return false


func _try_toggle() -> void:
	if not interaction_enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_toggle_time < INPUT_DEBOUNCE_MSEC:
		return
	_last_toggle_time = now
	_play_press_animation()
	toggle_route()
	get_viewport().set_input_as_handled()


func toggle_route() -> void:
	current_route = Route.RIGHT if current_route == Route.LEFT else Route.LEFT


func is_routing_left() -> bool:
	return current_route == Route.LEFT


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	input_pickable = enabled


func _apply_route_visuals() -> void:
	var target_rotation := ROUTE_ROTATION_LEFT if current_route == Route.LEFT else ROUTE_ROTATION_RIGHT
	if not is_node_ready():
		direction_marker.rotation = target_rotation
		return
	if _rotation_tween != null:
		_rotation_tween.kill()
	_rotation_tween = create_tween()
	_rotation_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rotation_tween.tween_property(direction_marker, "rotation", target_rotation, ROTATION_DURATION)
	_play_arrow_pulse()


func _play_press_animation() -> void:
	if _press_tween != null:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_press_tween.tween_property(junction_visual, "scale", Vector2.ONE * PRESS_SCALE, PRESS_DOWN_DURATION)
	_press_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_press_tween.tween_property(junction_visual, "scale", Vector2.ONE, PRESS_RELEASE_DURATION)


func _play_arrow_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
	direction_arrow.modulate = _base_arrow_modulate
	_pulse_tween = create_tween()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(direction_arrow, "modulate", _pulse_arrow_modulate, PULSE_IN_DURATION)
	_pulse_tween.tween_property(direction_arrow, "modulate", _base_arrow_modulate, PULSE_OUT_DURATION)
