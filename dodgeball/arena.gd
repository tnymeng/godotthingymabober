extends Node2D
## Main arena: wires players to the ball, keeps score, resets rounds and
## keeps the HUD text up to date.

## Show the ball speed / bounce counter (debug).
@export var show_debug_speed: bool = true
## Seconds of "3, 2, 1" before each round, with players frozen.
@export var round_start_countdown: float = 3.0

var scores: Dictionary = {}
var countdown_remaining: float = 0.0

@onready var player_one: DodgePlayer = $Player1
@onready var player_two: DodgePlayer = $Player2
@onready var ball: DodgeBall = $Ball
@onready var possession_label: Label = $HUD/PossessionLabel
@onready var speed_label: Label = $HUD/SpeedLabel
@onready var score_label: Label = $HUD/ScoreLabel
@onready var countdown_label: Label = $HUD/CountdownLabel


func _ready() -> void:
	var players: Array[DodgePlayer] = [player_one, player_two]
	for player in players:
		scores[player] = 0
		player.throw_requested.connect(ball.try_throw)
		player.catch_requested.connect(_on_catch_requested)
	ball.player_hit.connect(_on_player_hit)
	ball.setup(players, player_one) # Player 1 starts with the ball.
	_update_score_label()
	_begin_countdown()


# Runs before the players and ball each physics step (parent first), so the
# frame the countdown ends is the first frame anyone can act.
func _physics_process(delta: float) -> void:
	if countdown_remaining <= 0.0:
		return
	countdown_remaining -= delta
	if countdown_remaining <= 0.0:
		countdown_remaining = 0.0
		_set_round_active(true)
		countdown_label.visible = false
	else:
		countdown_label.text = str(ceili(countdown_remaining))


func _begin_countdown() -> void:
	countdown_remaining = round_start_countdown
	if countdown_remaining <= 0.0:
		_set_round_active(true)
		countdown_label.visible = false
		return
	_set_round_active(false)
	countdown_label.text = str(ceili(countdown_remaining))
	countdown_label.visible = true


func _set_round_active(active: bool) -> void:
	player_one.controls_enabled = active
	player_two.controls_enabled = active
	ball.round_active = active


func _process(_delta: float) -> void:
	_update_possession_label()
	speed_label.visible = show_debug_speed
	if show_debug_speed:
		speed_label.text = "Ball: %d px/s   Round speed: %d px/s   Bounces: %d" % [
			roundi(ball.get_speed()), roundi(ball.current_round_speed()), ball.bounce_count]


func _on_catch_requested(player: DodgePlayer) -> void:
	if not ball.try_catch(player):
		player.start_catch_cooldown()


func _on_player_hit(victim: DodgePlayer, thrower: DodgePlayer) -> void:
	if thrower != null:
		scores[thrower] += 1
	_update_score_label()
	_start_new_round(victim) # The player who was hit gets the ball.


func _start_new_round(first_holder: DodgePlayer) -> void:
	player_one.reset_for_round()
	player_two.reset_for_round()
	ball.reset_round(first_holder)
	_begin_countdown()


func _update_score_label() -> void:
	score_label.text = "Blue  %d  -  %d  Red" % [scores[player_one], scores[player_two]]


func _update_possession_label() -> void:
	match ball.state:
		DodgeBall.State.HELD:
			possession_label.text = "%s has the ball" % ball.holder.display_name
			possession_label.add_theme_color_override("font_color", ball.holder.body_color.lightened(0.3))
		DodgeBall.State.FLYING:
			var suffix := ", returning" if ball.has_bounced else ""
			possession_label.text = "Thrown by %s%s" % [ball.last_thrower.display_name, suffix]
			possession_label.add_theme_color_override("font_color", ball.last_thrower.body_color.lightened(0.3))
