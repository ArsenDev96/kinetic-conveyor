extends PathFollow2D

const BLOCK_RED_TEXTURE := preload("res://assets/gameplay/blocks/block_red.png")
const BLOCK_BLUE_TEXTURE := preload("res://assets/gameplay/blocks/block_blue.png")

@export var speed: float = 100.0
@export var cleanup_delay: float = 0.65

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


func _complete_delivery(outbound_path: Path2D) -> void:
	if _evaluated:
		return
	_evaluated = true
	var destination_bin := _red_bin if outbound_path == _red_outbound else _blue_bin
	_delivery_evaluator.evaluate_delivery(block_color, destination_bin.accepted_color)
	await get_tree().create_timer(cleanup_delay).timeout
	queue_free()
