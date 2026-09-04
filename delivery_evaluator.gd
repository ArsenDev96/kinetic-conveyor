extends Node2D

enum RoundState { PLAYING, WON, LOST }
## What a call to `evaluate_delivery` actually scored. IGNORED means the round
## was already over, so the delivery changed nothing and must not be reacted to.
enum DeliveryOutcome { IGNORED, CORRECT, WRONG }

const FEEDBACK_CORRECT_TEXTURE := preload("res://assets/ui/feedback/feedback_correct.png")
const FEEDBACK_WRONG_TEXTURE := preload("res://assets/ui/feedback/feedback_wrong.png")

# Long enough for the final block's ~0.28 s landing animation to read before the
# overlay covers the board.
const RESULT_PANEL_DELAY := 0.35

@export var total_blocks := 10
@export var maximum_mistakes := 3

var correct_count := 0
var mistake_count := 0
var completed_count := 0
var round_state := RoundState.PLAYING
var _feedback_version := 0

@onready var feedback_presentation: Node2D = $HUD/CountersAndFeedback/FeedbackPresentation
@onready var feedback_background: Sprite2D = $HUD/CountersAndFeedback/FeedbackPresentation/FeedbackBackground
@onready var feedback_label: Label = $HUD/CountersAndFeedback/FeedbackPresentation/DeliveryFeedback
@onready var correct_label: Label = $HUD/CountersAndFeedback/CorrectCount
@onready var mistake_label: Label = $HUD/CountersAndFeedback/MistakeCount
@onready var blocks_label: Label = $HUD/CountersAndFeedback/BlocksProgress
@onready var result_panel: Control = $HUD/ResultOverlay
@onready var result_title: Label = $HUD/ResultOverlay/ResultPanel/ResultTitle
@onready var result_summary: Label = $HUD/ResultOverlay/ResultPanel/ResultSummary
@onready var retry_button: Button = $HUD/ResultOverlay/ResultPanel/RetryButton
@onready var block_spawner: Node = $BlockSpawner
@onready var junction: Area2D = $Junction


func _ready() -> void:
	retry_button.pressed.connect(_retry_level)


func evaluate_delivery(block_color: BlockTypes.BlockColor, accepted_color: BlockTypes.BlockColor) -> DeliveryOutcome:
	if round_state != RoundState.PLAYING:
		return DeliveryOutcome.IGNORED

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

	return DeliveryOutcome.CORRECT if is_correct else DeliveryOutcome.WRONG


func _finish_round(new_state: RoundState) -> void:
	if round_state != RoundState.PLAYING:
		return
	round_state = new_state
	block_spawner.stop_spawning()
	junction.set_interaction_enabled(false)
	# Drops every block still travelling. A block already playing its landing
	# animation ignores this and frees itself when the animation ends, so the
	# delivery that just closed the round stays visible.
	get_tree().call_group("active_blocks", "cancel_in_flight")

	if round_state == RoundState.WON:
		result_title.text = "LEVEL COMPLETE"
		result_summary.text = "Correct: %d / %d\nMistakes: %d" % [correct_count, total_blocks, mistake_count]
	else:
		result_title.text = "LEVEL FAILED"
		result_summary.text = "Correct: %d\nMistakes: %d" % [correct_count, mistake_count]
	_reveal_result_panel()


# The overlay is held back briefly so the delivery that ended the round can
# finish its landing animation in full view before the panel covers the board.
func _reveal_result_panel() -> void:
	await get_tree().create_timer(RESULT_PANEL_DELAY).timeout
	result_panel.visible = true


func _retry_level() -> void:
	get_tree().reload_current_scene()


func _show_feedback(is_correct: bool) -> void:
	_feedback_version += 1
	var version := _feedback_version
	feedback_label.text = "CORRECT" if is_correct else "WRONG"
	feedback_background.texture = FEEDBACK_CORRECT_TEXTURE if is_correct else FEEDBACK_WRONG_TEXTURE
	feedback_presentation.scale = Vector2(0.9, 0.9)
	feedback_presentation.modulate = Color.WHITE
	feedback_presentation.visible = true
	var pop_tween := create_tween()
	pop_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(feedback_presentation, "scale", Vector2.ONE, 0.16)

	await get_tree().create_timer(0.85).timeout
	if version == _feedback_version:
		feedback_presentation.visible = false
