extends Node

const LEVEL_SEQUENCE := [
	BlockTypes.BlockColor.RED,
	BlockTypes.BlockColor.RED,
	BlockTypes.BlockColor.BLUE,
	BlockTypes.BlockColor.RED,
	BlockTypes.BlockColor.BLUE,
	BlockTypes.BlockColor.BLUE,
	BlockTypes.BlockColor.RED,
	BlockTypes.BlockColor.BLUE,
	BlockTypes.BlockColor.RED,
	BlockTypes.BlockColor.BLUE,
]

@export var block_scene: PackedScene
@export var spawn_interval: float = 1.8

var _next_block_index := 0
var _time_until_spawn := 0.0
var _spawning_enabled := true
@onready var _red_inbound: Path2D = $"../MovementPaths/RedInboundPath"
@onready var _blue_inbound: Path2D = $"../MovementPaths/BlueInboundPath"
@onready var _red_outbound: Path2D = $"../MovementPaths/RedOutboundPath"
@onready var _blue_outbound: Path2D = $"../MovementPaths/BlueOutboundPath"
@onready var _junction: Node = $"../Junction"
@onready var _red_bin: Node = $"../Bins/RedBin"
@onready var _blue_bin: Node = $"../Bins/BlueBin"
@onready var _delivery_evaluator: Node = get_parent()


func _ready() -> void:
	_spawn_next_block()
	_time_until_spawn = spawn_interval


func _process(delta: float) -> void:
	if not _spawning_enabled:
		return
	if _next_block_index >= LEVEL_SEQUENCE.size():
		return
	_time_until_spawn -= delta
	if _time_until_spawn <= 0.0:
		_spawn_next_block()
		_time_until_spawn += spawn_interval


func _spawn_next_block() -> void:
	if not _spawning_enabled:
		return
	if _next_block_index >= LEVEL_SEQUENCE.size():
		return
	var block_color: BlockTypes.BlockColor = LEVEL_SEQUENCE[_next_block_index]
	_next_block_index += 1
	var inbound_path := _red_inbound if block_color == BlockTypes.BlockColor.RED else _blue_inbound
	var block := block_scene.instantiate()
	block.configure(block_color, _junction, _red_outbound, _blue_outbound, _red_bin, _blue_bin, _delivery_evaluator)
	inbound_path.add_child(block)


func stop_spawning() -> void:
	_spawning_enabled = false
