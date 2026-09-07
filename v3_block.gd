extends PathFollow2D

## A production block travelling the Level 1 V3 machine.
##
## Invariant: the block is always a direct child of the Path2D it is currently
## travelling. It starts on InputPath and is reparented once - at the junction
## centre - onto the captured output path. Route capture is one-shot: once
## route_locked is true the stored captured_direction can never change, so a
## later junction toggle cannot re-route a block that has already passed.

signal captured(block)
signal delivered(block)

const COLOUR_RED := 0
const COLOUR_BLUE := 1

## Delivery presentation. The PathFollow2D keeps the progress the path gave it,
## so the delivery point never moves; only the sprite animates.
const DELIVERY_HOLD := 0.2
const SQUASH_SCALE := Vector2(1.12, 0.88)
const SQUASH_DURATION := 0.06
const REJECT_STRETCH := Vector2(0.94, 1.06)
const REJECT_BOUNCE_PX := 6.0
const REJECT_UP_DURATION := 0.07
const REJECT_DOWN_DURATION := 0.09
const VANISH_SCALE := 0.12
const VANISH_DURATION := 0.3

var colour: int = COLOUR_RED
var speed: float = 100.0
var route_locked: bool = false
var captured_direction: int = -1

var _capture_offset: float = 0.0
var _on_input: bool = true
var _finished: bool = false
var _sprite: Sprite2D


func setup(colour_in: int, texture: Texture2D, sprite_scale: float, sprite_offset: Vector2,
		capture_offset: float, move_speed: float) -> void:
	colour = colour_in
	_capture_offset = capture_offset
	speed = move_speed
	rotates = false
	loop = false
	progress = 0.0
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = Vector2(sprite_scale, sprite_scale)
	_sprite.offset = sprite_offset
	add_child(_sprite)
	_lock_sprite_upright()


func _physics_process(delta: float) -> void:
	if _finished:
		return
	progress += speed * delta
	_lock_sprite_upright()
	if _on_input:
		if progress >= _capture_offset:
			# Overshoot carries onto the output path so there is no stall or jump.
			var excess: float = progress - _capture_offset
			_on_input = false
			captured.emit(self)
			if is_inside_tree():
				progress = excess
				_lock_sprite_upright()
	elif progress_ratio >= 1.0:
		_finished = true
		delivered.emit(self)


## Cargo blocks must stay axis-aligned on every route. PathFollow2D still
## writes the curve tangent into `rotation` even though `rotates` is false,
## so the sprite cancels the parent rotation instead of trusting that flag.
## Cancelling it here also keeps `offset` in screen-aligned texture space,
## which is what the shared block offset is measured in.
func _lock_sprite_upright() -> void:
	_sprite.rotation = -rotation


## Hold at the pad centre, react to the verdict, then shrink and fade out.
## Correct: a subtle squash. Wrong: a tiny upward rejection bounce.
## The cube keeps its z-order the whole time, so nothing ever covers it.
func play_delivery_finish(correct: bool) -> void:
	var base_scale: Vector2 = _sprite.scale
	var tw: Tween = create_tween()
	tw.tween_interval(DELIVERY_HOLD)
	if correct:
		tw.tween_property(_sprite, "scale", base_scale * SQUASH_SCALE, SQUASH_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_method(_set_screen_lift, 0.0, -REJECT_BOUNCE_PX, REJECT_UP_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_sprite, "scale", base_scale * REJECT_STRETCH, REJECT_UP_DURATION)
		tw.tween_method(_set_screen_lift, -REJECT_BOUNCE_PX, 0.0, REJECT_DOWN_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(_sprite, "scale", base_scale, REJECT_DOWN_DURATION)
	tw.tween_property(_sprite, "scale", base_scale * VANISH_SCALE, VANISH_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_sprite, "modulate:a", 0.0, VANISH_DURATION)
	tw.tween_callback(queue_free)


## Screen-space vertical lift of the sprite, expressed in the parent's rotated
## frame so "up" stays up on every route.
func _set_screen_lift(y: float) -> void:
	_sprite.position = Vector2(0.0, y).rotated(-rotation)
