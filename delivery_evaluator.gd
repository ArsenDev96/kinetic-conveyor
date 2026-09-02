extends Node2D

enum RoundState { PLAYING, WON, LOST }

@export var total_blocks := 10
@export var maximum_mistakes := 3

var correct_count := 0
var mistake_count := 0
var completed_count := 0
var round_state := RoundState.PLAYING
var _feedback_version := 0

@onready var feedback_label: Label = $Labels/DeliveryFeedback
@onready var correct_label: Label = $Labels/CorrectCount
@onready var mistake_label: Label = $Labels/MistakeCount
@onready var blocks_label: Label = $Labels/BlocksProgress
@onready var result_panel: Panel = $RoundUI/ResultPanel
@onready var result_title: Label = $RoundUI/ResultPanel/ResultTitle
@onready var result_summary: Label = $RoundUI/ResultPanel/ResultSummary
@onready var retry_button: Button = $RoundUI/ResultPanel/RetryButton
@onready var block_spawner: Node = $BlockSpawner
@onready var junction: Area2D = $Junction


func _ready() -> void:
	retry_button.pressed.connect(_retry_level)


func evaluate_delivery(block_color: BlockTypes.BlockColor, accepted_color: BlockTypes.BlockColor) -> void:
	if round_state != RoundState.PLAYING:
		return

	var is_correct := block_color == accepted_color
	if is_correct:
		correct_count += 1
	else:
		mistake_count += 1
	completed_count += 1

	correct_label.text = "Correct: %d" % correct_count
	mistake_label.text = "Mistakes: %d" % mistake_count
	blocks_label.text = "Blocks: %d / %d" % [completed_count, total_blocks]
	_show_feedback(is_correct)

	if mistake_count >= maximum_mistakes:
		_finish_round(RoundState.LOST)
	elif completed_count == total_blocks:
		_finish_round(RoundState.WON)


func _finish_round(new_state: RoundState) -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = new_state
	block_spawner.stop_spawning()
	junction.set_interaction_enabled(false)
	get_tree().call_group("active_blocks", "queue_free")

	if round_state == RoundState.WON:
		result_title.text = "LEVEL COMPLETE"
		result_summary.text = "Correct: %d / %d\nMistakes: %d" % [correct_count, total_blocks, mistake_count]
	else:
		result_title.text = "LEVEL FAILED"
		result_summary.text = "Correct: %d\nMistakes: %d" % [correct_count, mistake_count]
	result_panel.visible = true


func _retry_level() -> void:
	get_tree().reload_current_scene()


func _show_feedback(is_correct: bool) -> void:
	_feedback_version += 1
	var version := _feedback_version
	feedback_label.text = "CORRECT" if is_correct else "WRONG"
	feedback_label.modulate = Color(0.35, 0.9, 0.4) if is_correct else Color(1.0, 0.35, 0.3)
	feedback_label.visible = true

	await get_tree().create_timer(0.85).timeout
	if version == _feedback_version:
		feedback_label.visible = false
