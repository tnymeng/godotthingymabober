class_name DodgeBall
extends CharacterBody2D
## The single ball. Kinematic body driven by move_and_collide():
##  - move_and_collide() sweeps the circle shape along the frame's motion, so it
##    stops exactly at the contact point instead of tunnelling or sinking in.
##  - We reflect the velocity ourselves with the wall normal, so every bounce is
##    exact and predictable (no physics-engine restitution/friction surprises).
##  - The ball only collides with walls (mask = layer 1). Hits and the
##    thrower's auto-catch are a swept circle-vs-circle test in this script.
##
## Flight rules:
##  - It leaves the thrower aimed at the opponent and flies straight.
##  - After its first wall bounce it homes back toward the thrower, turning by
##    at most a limited angle per second (no snapping), at constant speed.
##  - Speed is the round's current speed, which grows the longer the round lasts.

signal state_changed
signal bounced(bounce_count: int)
## Emitted once when a flying ball touches the thrower's opponent.
signal player_hit(victim: DodgePlayer, thrower: DodgePlayer)

enum State { HELD, FLYING }

@export_group("Speed")
## Ball speed at the start of every round (pixels per second).
@export var ball_initial_speed: float = 650.0
## Speed gained per second of round time (pixels per second, per second).
@export var ball_speed_acceleration: float = 20.0
## Upper limit for the ball speed (pixels per second).
@export var ball_max_speed: float = 1600.0

@export_group("Homing")
## How fast the ball can turn toward the thrower right after bouncing (degrees/s).
@export var homing_turn_rate_degrees: float = 160.0
## Turn rate grows by this fraction per second of returning, so the curve
## always tightens and the ball reliably gets back instead of orbiting.
@export var homing_strength_ramp: float = 1.5

@export_group("Shape")
## Radius used for BOTH the drawn circle and the collision circle.
@export var ball_radius: float = 10.0
## Gap between the holder's edge and the held ball.
@export var hold_gap: float = 3.0
## Safety cap on how many bounces one physics step may resolve (corners).
@export var max_bounces_per_step: int = 4
## Colour while held (in flight it takes the thrower's colour).
@export var neutral_color: Color = Color(1.0, 0.85, 0.15)

var state: State = State.HELD
var holder: DodgePlayer = null
var last_thrower: DodgePlayer = null
## True once the current throw has hit a wall (it is now returning).
var has_bounced: bool = false
var bounce_count: int = 0
## Seconds since the round started; drives the speed increase.
var round_time: float = 0.0
## False during the round-start countdown, so the speed ramp doesn't start early.
var round_active: bool = true

var _players: Array[DodgePlayer] = []
var _homing_time: float = 0.0
var _color: Color

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Run after the players each physics step so a held ball never lags a
	# frame and a catch pressed this frame is handled before the ball moves.
	process_physics_priority = 10
	_color = neutral_color
	var circle := CircleShape2D.new()
	circle.radius = ball_radius
	_collision.shape = circle
	queue_redraw()


## Called once by the arena. Gives the ball its players and the first holder.
func setup(players: Array[DodgePlayer], first_holder: DodgePlayer) -> void:
	_players = players
	reset_round(first_holder)


## Start of a round: speed back to its initial value, ball to new_holder.
func reset_round(new_holder: DodgePlayer) -> void:
	round_time = 0.0
	bounce_count = 0
	_give_to(new_holder)


func current_round_speed() -> float:
	return minf(ball_initial_speed + ball_speed_acceleration * round_time, ball_max_speed)


func get_speed() -> float:
	return velocity.length()


## Connected to every player's throw_requested signal.
func try_throw(thrower: DodgePlayer) -> void:
	if not round_active or state != State.HELD or holder != thrower:
		return # Only the current holder may throw, and not during the countdown.

	var target := _opponent_of(thrower)
	var direction := thrower.facing
	if target != null:
		var to_target := target.global_position - thrower.global_position
		if to_target.length_squared() > 0.001:
			direction = to_target.normalized()

	# Launch from the thrower's centre. The thrower's circle can never overlap a
	# wall and ball_radius < player_radius, so the ball always starts in free
	# space (the held offset position might be poking into a wall).
	global_position = thrower.global_position
	velocity = direction * current_round_speed()
	last_thrower = thrower
	holder = null
	thrower.has_ball = false
	has_bounced = false
	bounce_count = 0
	_homing_time = 0.0
	_color = thrower.body_color
	state = State.FLYING
	queue_redraw()
	state_changed.emit()


## A player pressed their catch key. Returns true if they caught the ball.
## The thrower can't catch their own throw until it has bounced (that also
## prevents a catch right after throwing).
func try_catch(player: DodgePlayer) -> bool:
	if state != State.FLYING:
		return false
	if player == last_thrower and not has_bounced:
		return false
	if player.global_position.distance_to(global_position) > player.catch_radius:
		return false
	_give_to(player)
	return true


func _physics_process(delta: float) -> void:
	if round_active:
		round_time += delta
	match state:
		State.HELD:
			_follow_holder()
		State.FLYING:
			_fly(delta)


func _follow_holder() -> void:
	if holder == null:
		return
	var offset := holder.facing * (holder.player_radius + ball_radius + hold_gap)
	global_position = holder.global_position + offset
	velocity = Vector2.ZERO


func _fly(delta: float) -> void:
	var direction := velocity.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	# Homing: rotate the heading toward the thrower by at most max_turn this
	# step. Clamping the angle (instead of lerping velocity) keeps speed
	# constant and the curve smooth, and lands exactly on target when close.
	if has_bounced and last_thrower != null:
		_homing_time += delta
		var to_thrower := last_thrower.global_position - global_position
		if to_thrower.length_squared() > 0.01:
			var turn_rate := deg_to_rad(homing_turn_rate_degrees) * (1.0 + homing_strength_ramp * _homing_time)
			var max_turn := turn_rate * delta
			var angle := direction.angle_to(to_thrower)
			direction = direction.rotated(clampf(angle, -max_turn, max_turn))

	velocity = direction * current_round_speed()

	# Record the path (including bounce points) so contact tests are swept and
	# a fast ball can't skip over a player between two frames.
	var path: PackedVector2Array = [global_position]
	var motion := velocity * delta

	for i in max_bounces_per_step:
		var collision := move_and_collide(motion)
		path.append(global_position)
		if collision == null:
			break

		var normal := collision.get_normal()
		var remainder := collision.get_remainder()
		# Only reflect if we are actually moving into the surface.
		if velocity.dot(normal) < 0.0:
			velocity = velocity.bounce(normal)
			remainder = remainder.bounce(normal)
			bounce_count += 1
			if not has_bounced:
				has_bounced = true
				_homing_time = 0.0
				state_changed.emit()
			bounced.emit(bounce_count)
		motion = remainder
		if motion.length_squared() < 0.0001:
			break

	_resolve_contacts(path)


## Walk the path in order; the first player body the ball touches decides
## what happens: the opponent is hit, the thrower (after a bounce) catches it.
func _resolve_contacts(path: PackedVector2Array) -> void:
	for s in range(path.size() - 1):
		var a := path[s]
		var b := path[s + 1]
		for player in _players:
			var closest := Geometry2D.get_closest_point_to_segment(player.global_position, a, b)
			var reach := player.player_radius + ball_radius
			if closest.distance_squared_to(player.global_position) > reach * reach:
				continue
			if player == last_thrower:
				if has_bounced:
					_give_to(player) # Returned to thrower: automatic catch.
					return
				continue # Just thrown: ignore the thrower's own body.
			# Opponent hit. Leave FLYING before emitting so this can only
			# score once, even if the signal handler does nothing.
			var thrower := last_thrower
			_give_to(player)
			player_hit.emit(player, thrower)
			return


func _give_to(player: DodgePlayer) -> void:
	holder = player
	last_thrower = null
	has_bounced = false
	velocity = Vector2.ZERO
	state = State.HELD
	_color = neutral_color
	for p in _players:
		p.has_ball = (p == player)
	_follow_holder()
	queue_redraw()
	state_changed.emit()


func _opponent_of(player: DodgePlayer) -> DodgePlayer:
	for other in _players:
		if other != player:
			return other
	return null


func _draw() -> void:
	draw_circle(Vector2.ZERO, ball_radius, _color)
	draw_arc(Vector2.ZERO, ball_radius, 0.0, TAU, 32, _color.darkened(0.5), 1.5, true)
