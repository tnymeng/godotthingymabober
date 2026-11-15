extends Node2D
## Main arena: wires players to the ball, keeps score, runs the hold zone,
## the death sequence and the round-start countdown, and keeps the HUD up to date.
##
## Round flow:  countdown (3 s, frozen) -> play -> one of:
##   - hit: death sequence (1 s slow motion + explosion, then back to normal
##     speed until the ball is back with the thrower; at least 3 s; only the
##     thrower can move) -> reset -> countdown
##   - hold zone entered: point, immediate reset -> countdown (no animation)

## Show the ball speed / throw counter (debug).
@export var show_debug_speed: bool = true
## Seconds of "3, 2, 1" before each round, with players frozen.
@export var round_start_countdown: float = 3.0
## "<player> scored" stays up until play resumes, and at least this many
## real seconds.
@export var score_message_min_time: float = 1.5

@export_group("Cover")
## Random grid-aligned cover walls (no dead ends, mirrored for fairness).
@export var cover_enabled: bool = true
## 0 = a new random layout every launch; any other number repeats a layout.
@export var cover_seed: int = 0

@export_group("Hold zone")
## While a player holds the ball, a red circle around them grows with the
## time they've held it. If the other player's centre is inside it, the round
## ends immediately (no death animation).
@export var hold_zone_enabled: bool = true
## Radius when the ball is first picked up (pixels).
@export var hold_zone_start_radius: float = 24.0
## Growth per second the ball is held (pixels per second of radius).
@export var hold_zone_growth_rate: float = 8.75
## The circle never grows beyond this radius (180 = 360 px across).
@export var hold_zone_max_radius: float = 180.0
## true: the player who ENTERS the circle scores (punishes holding too long).
## false: the HOLDER scores when the other player is inside their circle.
@export var hold_zone_point_to_intruder: bool = true

@export_group("Death sequence")
## Minimum length of the death sequence in REAL seconds (0 = skip it). It
## also waits for the ball to get back to the thrower, up to the maximum.
@export var death_sequence_duration: float = 3.0
## Hard limit in REAL seconds, in case the ball takes too long to return.
@export var death_sequence_max_duration: float = 8.0
## Engine.time_scale during the slow motion (0.2 = five times slower).
@export var slow_motion_scale: float = 0.2
## Real seconds to blend into slow motion right after the hit.
@export var slow_motion_ramp_in: float = 0.15
## Real seconds of slow motion from the hit (includes the ramp-in).
@export var slow_motion_hold: float = 1.0
## Real seconds to speed back up to normal after the slow motion.
@export var slow_motion_ramp_out: float = 0.5

var scores: Dictionary = {}
var countdown_remaining: float = 0.0
## True while the death sequence is playing.
var death_sequence_active: bool = false

var _death_start_usec: int = 0
var _hit_victim: DodgePlayer = null
var _explosion: DeathExplosion = null
var _ball_returned: bool = false
var _score_message_until_usec: int = 0

@onready var player_one: DodgePlayer = $Player1
@onready var player_two: DodgePlayer = $Player2
@onready var ball: DodgeBall = $Ball
@onready var cover: CoverGrid = $Cover
@onready var possession_label: Label = $HUD/PossessionLabel
@onready var speed_label: Label = $HUD/SpeedLabel
@onready var score_label: Label = $HUD/ScoreLabel
@onready var countdown_label: Label = $HUD/CountdownLabel
@onready var countdown_overlay: ColorRect = $HUD/CountdownOverlay
@onready var score_message_label: Label = $HUD/ScoreMessageLabel


func _ready() -> void:
	var players: Array[DodgePlayer] = [player_one, player_two]
	for player in players:
		scores[player] = 0
		player.throw_requested.connect(ball.try_throw)
		player.catch_requested.connect(_on_catch_requested)
	ball.player_hit.connect(_on_player_hit)
	ball.returned_after_hit.connect(_on_ball_returned_after_hit)
	if cover_enabled:
		var spawns: Array[Vector2] = [player_one.global_position, player_two.global_position]
		cover.generate(cover_seed, spawns, maxf(player_one.player_radius, player_two.player_radius))
		ball.nav = cover
	ball.setup(players, player_one) # Player 1 starts with the ball.
	_update_score_label()
	_begin_countdown()


func _exit_tree() -> void:
	Engine.time_scale = 1.0 # never leave the engine stuck in slow motion


# Runs before the players and ball each physics step (parent first), so the
# frame the countdown ends is the first frame anyone can act.
func _physics_process(delta: float) -> void:
	if countdown_remaining > 0.0:
		countdown_remaining -= delta
		if countdown_remaining <= 0.0:
			countdown_remaining = 0.0
			_set_round_active(true)
			_show_countdown(false)
		else:
			countdown_label.text = str(ceili(countdown_remaining))
	_update_hold_zone()


func _process(_delta: float) -> void:
	var round_running := ball.round_active and not death_sequence_active
	if score_message_label.visible and round_running \
			and Time.get_ticks_usec() >= _score_message_until_usec:
		score_message_label.visible = false
	if death_sequence_active:
		_update_death_sequence()
	_update_possession_label()
	speed_label.visible = show_debug_speed
	if show_debug_speed:
		speed_label.text = "Ball: %d px/s   Next throw: %d px/s   Speed step: %d" % [
			roundi(ball.get_speed()), roundi(ball.next_throw_speed()), ball.speed_steps]


func _begin_countdown() -> void:
	countdown_remaining = round_start_countdown
	if countdown_remaining <= 0.0:
		_set_round_active(true)
		_show_countdown(false)
		return
	_set_round_active(false)
	countdown_label.text = str(ceili(countdown_remaining))
	_show_countdown(true)


func _show_countdown(show: bool) -> void:
	countdown_label.visible = show
	countdown_overlay.visible = show


func _set_round_active(active: bool) -> void:
	for player in [player_one, player_two]:
		player.can_move = active
		player.can_act = active
	ball.round_active = active


func _other_player(player: DodgePlayer) -> DodgePlayer:
	return player_two if player == player_one else player_one


# --- Hold zone ---------------------------------------------------------------

func _update_hold_zone() -> void:
	var active := hold_zone_enabled and ball.round_active and not death_sequence_active \
			and ball.state == DodgeBall.State.HELD and ball.holder != null
	if not active:
		player_one.hold_zone_radius = 0.0
		player_two.hold_zone_radius = 0.0
		return

	var holder := ball.holder
	var other := _other_player(holder)
	var radius := minf(hold_zone_start_radius + hold_zone_growth_rate * ball.hold_time,
			hold_zone_max_radius)
	holder.hold_zone_radius = radius
	other.hold_zone_radius = 0.0

	if other.global_position.distance_to(holder.global_position) < radius:
		_on_hold_zone_entered(holder, other)


## Point and an immediate new round (no death animation). The player who
## gave up the point starts the next round with the ball, like after a hit.
func _on_hold_zone_entered(holder: DodgePlayer, intruder: DodgePlayer) -> void:
	var scorer := intruder if hold_zone_point_to_intruder else holder
	var loser := _other_player(scorer)
	scores[scorer] += 1
	_announce_score(scorer)
	_update_score_label()
	_start_new_round(loser)


# --- Catches and hits ----------------------------------------------------------

func _on_catch_requested(player: DodgePlayer) -> void:
	if not ball.try_catch(player):
		player.start_catch_cooldown()


func _on_player_hit(victim: DodgePlayer, thrower: DodgePlayer) -> void:
	if death_sequence_active:
		return # can't happen (the ball ignores players now), but never double-score
	if thrower != null:
		scores[thrower] += 1
		_announce_score(thrower)
	_update_score_label()
	_start_death_sequence(victim, thrower)


func _on_ball_returned_after_hit(_thrower: DodgePlayer) -> void:
	_ball_returned = true


# --- Death sequence ------------------------------------------------------------

## Freeze the victim, spawn the explosion and go to slow motion. The thrower
## can still walk around; their movement follows Engine.time_scale, so they
## slow down and speed back up together with the ball and the explosion.
## The ball flies through the victim (PASS_THROUGH) and homes back to the
## thrower; the sequence ends once it is back and the minimum time passed.
func _start_death_sequence(victim: DodgePlayer, thrower: DodgePlayer) -> void:
	_hit_victim = victim
	_set_round_active(false) # no throwing/catching, hold timer paused
	if death_sequence_duration <= 0.0:
		_finish_death_sequence()
		return
	if thrower != null:
		thrower.can_move = true
	death_sequence_active = true
	_ball_returned = ball.state == DodgeBall.State.HELD
	_death_start_usec = Time.get_ticks_usec()

	_explosion = DeathExplosion.new()
	_explosion.setup(victim.body_color, victim.player_radius)
	_explosion.position = victim.position
	add_child(_explosion)
	victim.hide_for_death()


func _update_death_sequence() -> void:
	# Measured in real time, so slow motion doesn't stretch it.
	var elapsed := (Time.get_ticks_usec() - _death_start_usec) / 1_000_000.0
	var done := elapsed >= death_sequence_duration and _ball_returned
	if done or elapsed >= death_sequence_max_duration:
		_finish_death_sequence()
		return
	Engine.time_scale = _slow_motion_curve(elapsed)


## 1 -> slow_motion_scale over the ramp-in, hold until slow_motion_hold,
## ramp back to 1 over slow_motion_ramp_out, then normal speed.
func _slow_motion_curve(elapsed: float) -> float:
	if slow_motion_ramp_in > 0.0 and elapsed < slow_motion_ramp_in:
		return lerpf(1.0, slow_motion_scale, elapsed / slow_motion_ramp_in)
	if elapsed < slow_motion_hold:
		return slow_motion_scale
	if slow_motion_ramp_out > 0.0 and elapsed < slow_motion_hold + slow_motion_ramp_out:
		return lerpf(slow_motion_scale, 1.0, (elapsed - slow_motion_hold) / slow_motion_ramp_out)
	return 1.0


func _finish_death_sequence() -> void:
	death_sequence_active = false
	Engine.time_scale = 1.0
	if is_instance_valid(_explosion):
		_explosion.queue_free()
	_explosion = null
	var victim := _hit_victim
	_hit_victim = null
	_start_new_round(victim) # The player who was hit gets the ball.


func _start_new_round(first_holder: DodgePlayer) -> void:
	player_one.reset_for_round()
	player_two.reset_for_round()
	ball.reset_round(first_holder)
	_begin_countdown()


# --- HUD -----------------------------------------------------------------------

func _announce_score(scorer: DodgePlayer) -> void:
	score_message_label.text = "%s scored" % scorer.display_name
	score_message_label.add_theme_color_override("font_color", scorer.body_color.lightened(0.35))
	score_message_label.visible = true
	_score_message_until_usec = Time.get_ticks_usec() + int(score_message_min_time * 1_000_000.0)


func _update_score_label() -> void:
	score_label.text = "Blue  %d  -  %d  Red" % [scores[player_one], scores[player_two]]


func _update_possession_label() -> void:
	if death_sequence_active and _hit_victim != null:
		possession_label.text = "%s was hit!" % _hit_victim.display_name
		possession_label.add_theme_color_override("font_color", _hit_victim.body_color.lightened(0.3))
		return
	match ball.state:
		DodgeBall.State.HELD:
			possession_label.text = "%s has the ball" % ball.holder.display_name
			possession_label.add_theme_color_override("font_color", ball.holder.body_color.lightened(0.3))
		DodgeBall.State.FLYING:
			var suffix := ", returning" if ball.has_bounced else ""
			possession_label.text = "Thrown by %s%s" % [ball.last_thrower.display_name, suffix]
			possession_label.add_theme_color_override("font_color", ball.last_thrower.body_color.lightened(0.3))
