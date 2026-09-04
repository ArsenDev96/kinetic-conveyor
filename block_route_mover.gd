extends PathFollow2D

const BLOCK_RED_TEXTURE := preload("res://assets/themes/factory/blocks/block_red.png")
const BLOCK_BLUE_TEXTURE := preload("res://assets/themes/factory/blocks/block_blue.png")

# Landing presentation. Only BlockVisual is animated: the PathFollow2D keeps the
# progress the gameplay path gave it, so the delivery point never moves.
const IMPACT_SCALE := Vector2(1.12, 0.88)
const IMPACT_DURATION := 0.06
const SINK_SCALE := Vector2(0.4, 0.4)
const SINK_OFFSET_Y := 24.0
const SINK_DURATION := 0.22

@export var speed: float = 100.0

var block_color: BlockTypes.BlockColor = BlockTypes.BlockColor.RED
var _junction: Node
var _red_outbound: Path2D
var _blue_outbound: Path2D
var _red_bin: Node
var _blue_bin: Node
var _delivery_evaluator: Node
var _is_outbound := false
var _finished := false
var _evaluated := false
var _landing := false
@onready var _block_visual: Node2D = $BlockVisual


func configure(color_type: BlockTypes.BlockColor, junction: Node, red_outbound: Path2D, blue_outbound: Path2D, red_bin: Node, blue_bin: Node, delivery_evaluator: Node) -> void:
	block_color = color_type
	_junction = junction
	_red_outbound = red_outbound
	_blue_outbound = blue_outbound
	_red_bin = red_bin
	_blue_bin = blue_bin
	_delivery_evaluator = delivery_evaluator
	$BlockVisual/BlockSprite.texture = BLOCK_RED_TEXTURE if block_color == BlockTypes.BlockColor.RED else BLOCK_BLUE_TEXTURE


func _process(delta: float) -> void:
	if _finished:
		return
	var path := get_parent() as Path2D
	if path == null or path.curve == null:
		return
	var path_length := path.curve.get_baked_length()
	progress = minf(progress + speed * delta, path_length)
	if progress < path_length:
		return
	if _is_outbound:
		_finished = true
		_complete_delivery(path)
		return
	var selected_outbound := _red_outbound if _junction.is_routing_left() else _blue_outbound
	reparent(selected_outbound, false)
	progress = 0.0
	_is_outbound = true


# Called on every block still in the "active_blocks" group when the round ends.
# A block that already reached its bin keeps its landing animation and frees
# itself when the animation finishes; everything still travelling is dropped.
func cancel_in_flight() -> void:
	if _landing:
		return
	_finished = true
	queue_free()


func _complete_delivery(outbound_path: Path2D) -> void:
	if _evaluated:
		return
	_evaluated = true
	_landing = true
	var destination_bin := _red_bin if outbound_path == _red_outbound else _blue_bin
	# Gameplay first: the evaluator owns the correct/wrong rule and reports what
	# it scored, so the bin reaction only ever mirrors a decision already made.
	var outcome: int = _delivery_evaluator.evaluate_delivery(block_color, destination_bin.accepted_color)
	if outcome == _delivery_evaluator.DeliveryOutcome.CORRECT:
		destination_bin.react_correct()
	elif outcome == _delivery_evaluator.DeliveryOutcome.WRONG:
		destination_bin.react_wrong()
	await _play_landing_animation()
	queue_free()


func _play_landing_animation() -> void:
	var landing_tween := create_tween()
	landing_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	landing_tween.tween_property(_block_visual, "scale", IMPACT_SCALE, IMPACT_DURATION)
	landing_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	landing_tween.tween_property(_block_visual, "scale", SINK_SCALE, SINK_DURATION)
	landing_tween.parallel().tween_property(_block_visual, "position:y", _block_visual.position.y + SINK_OFFSET_Y, SINK_DURATION)
	landing_tween.parallel().tween_property(_block_visual, "modulate:a", 0.0, SINK_DURATION)
	await landing_tween.finished
