class_name DodgeBot
extends Node
## Computer player for single player mode. It drives one DodgePlayer through
## the same controls a person has: a move vector plus throw / catch / dash
## presses (the player reads them via `move` and consume()).
##
## Behaviour:
##  - Holding the ball: throws once it has a clear line to the opponent, after a
##    short reaction delay. Behind cover it moves toward the opponent to find a
##    shot, and throws anyway (a bank shot) if it has held the ball too long.
##  - Opponent holding the ball: keeps its distance and strafes; if the
##    opponent's red hold circle has grown big and it is close, it steps in to
##    take the point.
##  - Ball coming at it: catches it (catch_chance), dodges sideways and dashes
##    if the ball is close (dodge_chance), or otherwise freezes (no reaction).

## Random delay (seconds) before throwing once it has a clear shot.
@export var reaction_time: Vector2 = Vector2(0.25, 0.6)
## Throw straight away (no delay) with a clear shot if the opponent is this close.
@export var quick_throw_distance: float = 220.0
## Chance it catches an incoming throw.
@export_range(0.0, 1.0) var catch_chance: float = 0.6
## Chance it dodges an incoming throw. Whatever catch_chance and dodge_chance
## leave over is the chance it freezes and doesn't react.
@export_range(0.0, 1.0) var dodge_chance: float = 0.4
## Less time to react = lower chance to catch. The time is how long the ball
## needs to reach its catch circle when the throw starts (distance / speed).
## At or above catch_comfort_time it gets its full catch_chance; at or below
## catch_min_time it can't catch at all; in between it scales smoothly. The
## catch chance it loses becomes freezing (no reaction), not extra dodging.
@export var catch_comfort_time: float = 1.0
@export var catch_min_time: float = 0.25
## Distance it likes to keep from an opponent who has the ball.
@export var preferred_distance: float = 380.0
## While the opponent holds the ball, dash away when they get closer than this
## fraction of preferred_distance (0 = never dash for distance).
@export_range(0.0, 1.0) var distance_dash_fraction: float = 0.0
## While the opponent holds the ball: steer toward open space instead of just
## straight away (so it doesn't get cornered) and never stand still. It will
## slip past the opponent, briefly getting closer, to get out of a corner.
@export var smart_evasion: bool = false
## How far ahead (px) each direction is checked for walls and open space.
@export var evade_look_ahead: float = 200.0
## With no clear shot, it throws anyway after holding the ball this long.
@export var blocked_throw_after: float = 3.0
## Steps into the opponent's hold circle once it is at least this big.
@export var zone_attack_radius: float = 90.0

## Read by the player every physics step.
var move: Vector2 = Vector2.ZERO

var me: DodgePlayer
var opponent: DodgePlayer
var ball: DodgeBall
var nav: CoverGrid

var _presses := {"throw": false, "catch": false, "dash": false}
var _throw_timer: float = -1.0
var _incoming_plan: String = ""
var _strafe_sign: float = 1.0
var _strafe_timer: float = 0.0
var _stuck_time: float = 0.0
var _wander_dir: Vector2 = Vector2.ZERO
var _wander_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _evade_dir: Vector2 = Vector2.ZERO

const PLAY_AREA := Rect2(60, 90, 1160, 600)


func setup(bot_player: DodgePlayer, other: DodgePlayer, the_ball: DodgeBall, cover: CoverGrid) -> void:
	me = bot_player
	opponent = other
	ball = the_ball
	nav = cover
	_rng.randomize()


func _ready() -> void:
	# Decide before the players move each physics step, so the player reads
	# this frame's choices.
	process_physics_priority = -1


## Called by the player: true once per press.
func consume(action: String) -> bool:
	var pressed: bool = _presses.get(action, false)
	_presses[action] = false
	return pressed


func _physics_process(delta: float) -> void:
	for k in _presses:
		_presses[k] = false
	move = Vector2.ZERO
	if me == null or ball == null:
		return
	if not me.can_act:
		_throw_timer = -1.0
		_incoming_plan = ""
		return

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = _rng.randf_range(0.8, 1.8)
		_strafe_sign = -_strafe_sign if _rng.randf() < 0.6 else _strafe_sign

	match ball.state:
		DodgeBall.State.HELD:
			_incoming_plan = ""
			if ball.holder == me:
				_with_ball(delta)
			else:
				_throw_timer = -1.0
				_opponent_has_ball()
		DodgeBall.State.FLYING:
			_throw_timer = -1.0
			if ball.last_thrower == opponent:
				_incoming()
			else:
				_incoming_plan = ""
				_keep_distance()
		_:
			_incoming_plan = ""

	_unstick(delta)


func _with_ball(delta: float) -> void:
	var clear_shot := ball._visible_opponent_in_sight(me) != null
	if clear_shot:
		var close := me.global_position.distance_to(opponent.global_position) < quick_throw_distance
		if _throw_timer < 0.0:
			_throw_timer = 0.0 if close else _rng.randf_range(reaction_time.x, reaction_time.y)
		_throw_timer -= delta
		if _throw_timer <= 0.0:
			_presses["throw"] = true
			_throw_timer = -1.0
		else:
			move = _strafe_dir() * 0.5
	else:
		_throw_timer = -1.0
		move = _steer_to(opponent.global_position)
		if ball.hold_time > blocked_throw_after:
			_presses["throw"] = true # bank shot the way it is facing


func _opponent_has_ball() -> void:
	var d := me.global_position.distance_to(opponent.global_position)
	var zone := opponent.hold_zone_radius
	if zone >= zone_attack_radius and d < zone + 140.0:
		move = _steer_to(opponent.global_position) # take the hold-zone point
	else:
		_keep_distance(true)


## Back off to preferred_distance (strafing once there). With threatened =
## true (the opponent has the ball) it may also dash away when crowded.
func _keep_distance(threatened: bool = false) -> void:
	var away := opponent.global_position.direction_to(me.global_position)
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var d := me.global_position.distance_to(opponent.global_position)
	var target: Vector2
	if d < preferred_distance:
		target = me.global_position + away * 160.0 + away.orthogonal() * _strafe_sign * 80.0
	else:
		target = me.global_position + away.orthogonal() * _strafe_sign * 160.0
	target = target.clamp(PLAY_AREA.position + Vector2(40, 40), PLAY_AREA.end - Vector2(40, 40))
	move = _steer_to(target)
	if threatened and smart_evasion:
		move = _evasive_direction()
	var crowded := d < preferred_distance * distance_dash_fraction
	if threatened and distance_dash_fraction > 0.0 and crowded and me.dash_cooldown_remaining <= 0.0 \
			and move != Vector2.ZERO:
		_presses["dash"] = true


## Smart evasion: try 16 directions and pick the best place to be a moment
## from now. Each direction is scored on
##  - how far it can actually go that way before a wall (outer or cover),
##  - how open the spot it reaches is (far from the arena edges both ways, so
##    corners score low),
##  - how far that spot is from the opponent (counted only up to a little past
##    preferred_distance, so escaping a corner can beat backing further in,
##    even if it means passing closer for a moment), with a penalty for ending
##    up really close,
##  - a small bonus for keeping its current direction (no jitter).
## It always returns a direction, so the bot keeps moving.
func _evasive_direction() -> Vector2:
	var best_dir := Vector2.ZERO
	var best_score := -INF
	for i in 16:
		var dir := Vector2.from_angle(TAU * i / 16.0)
		var reach := _free_reach(dir, evade_look_ahead)
		var spot := me.global_position + dir * reach
		var dist_after := spot.distance_to(opponent.global_position)
		var score := minf(dist_after, preferred_distance * 1.2) * 1.6
		score += _openness(spot) * 1.0
		score += reach * 0.5
		score += _evade_dir.dot(dir) * 60.0
		if dist_after < 200.0:
			score -= (200.0 - dist_after) * 3.0
		if score > best_score:
			best_score = score
			best_dir = dir
	_evade_dir = best_dir
	return best_dir


## How far (px, up to look) the bot can move in dir before touching a wall.
func _free_reach(dir: Vector2, look: float) -> float:
	var shape := CircleShape2D.new()
	shape.radius = me.player_radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, me.global_position)
	params.motion = dir * look
	params.collision_mask = 1
	params.exclude = [me.get_rid()]
	var result := me.get_world_2d().direct_space_state.cast_motion(params)
	if result.size() == 0:
		return look
	return look * result[0]


## Open space around a point: distance to the nearest side wall plus distance
## to the nearest top/bottom wall (each capped). Low in corners and along edges.
func _openness(p: Vector2) -> float:
	var horizontal := minf(p.x - PLAY_AREA.position.x, PLAY_AREA.end.x - p.x)
	var vertical := minf(p.y - PLAY_AREA.position.y, PLAY_AREA.end.y - p.y)
	return minf(horizontal, 300.0) + minf(vertical, 250.0)


func _incoming() -> void:
	if _incoming_plan == "":
		var catch_now := catch_chance * reaction_factor()
		var roll := _rng.randf()
		if roll < catch_now:
			_incoming_plan = "catch"
		elif roll < catch_now + dodge_chance:
			_incoming_plan = "dodge"
		else:
			_incoming_plan = "freeze"
	var to_me := me.global_position - ball.global_position
	var dist := to_me.length()
	var coming := ball.velocity.dot(to_me) > 0.0
	if _incoming_plan == "catch":
		if dist <= me.catch_radius - 6.0 and me.can_attempt_catch():
			_presses["catch"] = true
		elif not coming:
			_keep_distance()
		return
	if _incoming_plan == "freeze":
		if not coming:
			_keep_distance()
		return # stands still while the ball comes at it
	# Dodge: sidestep off the ball's line, dash if it is close.
	if coming:
		var side := ball.velocity.orthogonal().normalized()
		if side.dot(to_me) < 0.0:
			side = -side
		move = side
		if dist < 220.0 and me.dash_cooldown_remaining <= 0.0:
			_presses["dash"] = true
	else:
		_keep_distance()


## 0..1: how much of catch_chance applies, from the time the ball needs to
## reach the catch circle (closer or faster throws give less time).
func reaction_factor() -> float:
	var speed := ball.velocity.length()
	if speed < 1.0:
		return 1.0
	var gap := maxf(me.global_position.distance_to(ball.global_position) - me.catch_radius, 0.0)
	var time := gap / speed
	if catch_comfort_time <= catch_min_time:
		return 1.0 if time > catch_min_time else 0.0
	return clampf(inverse_lerp(catch_min_time, catch_comfort_time, time), 0.0, 1.0)


func _strafe_dir() -> Vector2:
	var to_opp := me.global_position.direction_to(opponent.global_position)
	return to_opp.orthogonal() * _strafe_sign


## Direction toward target, going round cover along the grid when needed.
func _steer_to(target: Vector2) -> Vector2:
	var waypoint := target
	if nav != null and not nav.walls.is_empty():
		waypoint = nav.steer_target(me.global_position, target, me.player_radius, [me.get_rid()])
	var dir := me.global_position.direction_to(waypoint)
	return dir if me.global_position.distance_to(waypoint) > 6.0 else Vector2.ZERO


## If it wants to move but is not getting anywhere, wander a random way briefly.
func _unstick(delta: float) -> void:
	if _wander_time > 0.0:
		_wander_time -= delta
		move = _wander_dir
		return
	if move.length() > 0.5 and me.velocity.length() < 40.0 and not me.is_dashing():
		_stuck_time += delta
		if _stuck_time > 0.35:
			_stuck_time = 0.0
			_wander_dir = Vector2.from_angle(_rng.randf() * TAU)
			_wander_time = 0.5
	else:
		_stuck_time = 0.0
