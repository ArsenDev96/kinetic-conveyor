extends Area2D

enum Route { LEFT, RIGHT }

@export var initial_route: Route = Route.LEFT

var current_route: Route:
	set(value):
		current_route = value
		if is_node_ready():
			_update_direction_marker()
var _last_toggle_time := -1000
var interaction_enabled := true
var _rotation_tween: Tween
@onready var direction_marker: Node2D = $JunctionVisual/DirectionMarker


func _ready() -> void:
	current_route = initial_route
	_update_direction_marker()


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _is_press(event):
		_try_toggle()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_press(event):
		return

	var pointer_position: Vector2 = event.position
	if Rect2(270, 460, 180, 160).has_point(pointer_position):
		_try_toggle()


func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false


func _try_toggle() -> void:
	if not interaction_enabled:
		return
	var now := Time.get_ticks_msec()
	if now - _last_toggle_time < 200:
		return
	_last_toggle_time = now
	toggle_route()
	get_viewport().set_input_as_handled()


func toggle_route() -> void:
	current_route = Route.RIGHT if current_route == Route.LEFT else Route.LEFT
	_update_direction_marker()


func is_routing_left() -> bool:
	return current_route == Route.LEFT


func set_interaction_enabled(enabled: bool) -> void:
	interaction_enabled = enabled
	input_pickable = enabled


func _update_direction_marker() -> void:
	var target_rotation := PI / 4.0 if current_route == Route.LEFT else -PI / 4.0
	if not is_node_ready():
		direction_marker.rotation = target_rotation
		return
	if _rotation_tween != null:
		_rotation_tween.kill()
	_rotation_tween = create_tween()
	_rotation_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rotation_tween.tween_property(direction_marker, "rotation", target_rotation, 0.15)
