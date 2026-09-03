extends Node2D

## Delivery target. `accepted_color` is the gameplay rule input and is never
## touched by presentation: every reaction below drives the BinVisual wrapper,
## so this node's own transform - the endpoint the outbound paths deliver to -
## stays exactly where the level places it.

const CORRECT_SQUASH := Vector2(1.07, 0.94)
const CORRECT_COMPRESS_DURATION := 0.07
const CORRECT_RETURN_DURATION := 0.16
const CORRECT_HIGHLIGHT := 1.16

const WRONG_SHUDDER_OFFSETS := [9.0, -7.0, 3.5, 0.0]
const WRONG_STEP_DURATION := 0.045
const WRONG_TINT := Color(1.0, 0.58, 0.56, 1.0)
const WRONG_TINT_IN_DURATION := 0.05
const WRONG_TINT_OUT_DURATION := 0.13

@export var accepted_color: BlockTypes.BlockColor = BlockTypes.BlockColor.RED

var _base_position: Vector2
var _base_scale: Vector2
var _base_modulate: Color
var _transform_tween: Tween
var _tint_tween: Tween
@onready var bin_visual: Node2D = $BinVisual


func _ready() -> void:
	_base_position = bin_visual.position
	_base_scale = bin_visual.scale
	_base_modulate = bin_visual.modulate


func react_correct() -> void:
	_reset_visual()
	_transform_tween = create_tween()
	_transform_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transform_tween.tween_property(bin_visual, "scale", _base_scale * CORRECT_SQUASH, CORRECT_COMPRESS_DURATION)
	_transform_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transform_tween.tween_property(bin_visual, "scale", _base_scale, CORRECT_RETURN_DURATION)

	_tint_tween = create_tween()
	_tint_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tint_tween.tween_property(bin_visual, "modulate", _scaled_modulate(CORRECT_HIGHLIGHT, CORRECT_HIGHLIGHT, CORRECT_HIGHLIGHT), CORRECT_COMPRESS_DURATION)
	_tint_tween.tween_property(bin_visual, "modulate", _base_modulate, CORRECT_RETURN_DURATION)


func react_wrong() -> void:
	_reset_visual()
	# Localised horizontal shudder. Every step is an absolute offset from the
	# captured base, and the last one is the base itself, so repeated wrong
	# deliveries cannot accumulate drift.
	_transform_tween = create_tween()
	_transform_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for offset: float in WRONG_SHUDDER_OFFSETS:
		_transform_tween.tween_property(bin_visual, "position:x", _base_position.x + offset, WRONG_STEP_DURATION)

	_tint_tween = create_tween()
	_tint_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tint_tween.tween_property(bin_visual, "modulate", _scaled_modulate(WRONG_TINT.r, WRONG_TINT.g, WRONG_TINT.b), WRONG_TINT_IN_DURATION)
	_tint_tween.tween_property(bin_visual, "modulate", _base_modulate, WRONG_TINT_OUT_DURATION)


# Reactions can overlap when two blocks land close together, so an incoming one
# always cancels the previous tweens and snaps back to the captured base first.
func _reset_visual() -> void:
	if _transform_tween != null:
		_transform_tween.kill()
	if _tint_tween != null:
		_tint_tween.kill()
	bin_visual.position = _base_position
	bin_visual.scale = _base_scale
	bin_visual.modulate = _base_modulate


func _scaled_modulate(red: float, green: float, blue: float) -> Color:
	return Color(
		_base_modulate.r * red,
		_base_modulate.g * green,
		_base_modulate.b * blue,
		_base_modulate.a
	)
