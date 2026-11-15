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
##  - It leaves the thrower aimed at the opponent if there is a clear line to
##    them, otherwise in the direction the thrower is facing, and flies straight.
##  - After its first wall bounce it homes back toward the thrower, turning by
##    at most a limited angle per second (no snapping), at constant speed.
##    With cover walls it follows the grid route around them (nav).
##  - Every throw in a round is faster than the last by a fixed amount, except
##    that a throw the thrower catches again doesn't count: their next throw
##    keeps the same speed. Speed is constant during a flight and resets at the
##    start of a round.
##  - After it hits a player it switches to PASS_THROUGH: it flies through the
##    victim, starts curving back to the thrower once it is clear of them,
##    and is caught automatically when it gets back (emits returned_after_hit).

signal state_changed
signal bounced(bounce_count: int)
## Emitted once when a flying ball touches the thrower's opponent.
signal player_hit(victim: DodgePlayer, thrower: DodgePlayer)
## Emitted when the ball gets back to the thrower after hitting the victim.
signal returned_after_hit(thrower: DodgePlayer)

enum State { HELD, FLYING, PASS_THROUGH }

@export_group("Speed")
## Speed of the first throw of every round (pixels per second).
@export var ball_initial_speed: float = 650.0
## Each further throw in the same round is this much faster (pixels per
## second), unless the thrower caught their own previous throw.
@export var ball_speed_increment_per_throw: float = 50.0
## Upper limit for the ball speed (pixels per second).
@export var ball_max_speed: float = 1600.0

@export_group("Homing")
## How fast the ball can turn toward the thrower right after bouncing (degrees/s).
@export var homing_turn_rate_degrees: float = 160.0
## Turn rate grows by this fraction per second of returning, so the curve
## always tightens and the ball reliably gets back instead of orbiting.
@export var homing_strength_ramp: float = 1.5
## After hitting a player, the ball starts curving back to the thrower once it
## is this far past the victim (or at its next wall bounce, if sooner).
@export var pass_through_clearance: float = 70.0

@export_group("Shape")
## Radius used for BOTH the drawn circle and the collision circle.
@export var ball_radius: float = 10.0
## Gap between the holder's edge and the held ball.
@export var hold_gap: float = 3.0
## Safety cap on how many bounces one physics step may resolve (corners).
@export var max_bounces_per_step: int = 4
## The ball's colour. It stays this colour at all times.
@export var ball_color: Color = Color(1.0, 0.85, 0.15):
	set(value):
		ball_color = value
		queue_redraw()

@export_group("Trail")
## A small translucent trail in the thrower's colour follows the flying ball
## along its real path (bounce points included), smoothed into a curve.
@export var trail_length: float = 110.0
## Width right behind the ball; it tapers to a point at the tail.
@export var trail_width: float = 16.0
## Opacity right behind the ball; it fades to clear at the tail.
@export_range(0.0, 1.0) var trail_alpha: float = 0.5
## Seconds the trail takes to fade out once the ball stops flying.
@export var trail_fade_time: float = 0.15
## Extra points per path segment when smoothing (Catmull-Rom).
@export var trail_smoothing: int = 6

var state: State = State.HELD
var holder: DodgePlayer = null
var last_thrower: DodgePlayer = null
## True once the current throw has hit a wall (it is now returning).
var has_bounced: bool = false
var bounce_count: int = 0
## How many times the speed has gone up this round; sets the next throw's
## speed. Each throw adds a step, but it is taken back if the thrower gets
## their own ball back, so only throws the opponent catches make it faster.
var speed_steps: int = 0
## Seconds the current holder has had the ball (only counts while the round
## is active). Resets whenever the ball changes hands.
var hold_time: float = 0.0
## False during the countdown and the death sequence: no throwing, and the
## hold timer is paused.
var round_active: bool = true

var _players: Array[DodgePlayer] = []
var _homing_time: float = 0.0
## Speed of the current flight, fixed at the moment of the throw.
var _flight_speed: float = 0.0
var _hit_victim: DodgePlayer = null
## Cover layout, set by the arena. When set, the returning ball steers around
## cover walls along the grid instead of flying straight into them.
var nav: CoverGrid = null

var _trail: Line2D
var _trail_gradient: Gradient
## Recorded ball positions for the current flight (oldest first).
var _trail_points: PackedVector2Array = PackedVector2Array()
var _trail_color: Color = Color.WHITE
## 1 while flying; counts down to 0 after the ball is caught.
var _trail_fade: float = 0.0

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Run after the players each physics step so a held ball never lags a
	# frame and a catch pressed this frame is handled before the ball moves.
	process_physics_priority = 10
	var circle := CircleShape2D.new()
	circle.radius = ball_radius
	_collision.shape = circle
	_make_trail()
	queue_redraw()


func _make_trail() -> void:
	_trail = Line2D.new()
	_trail.name = "Trail"
	_trail.top_level = true # points are in world coordinates
	_trail.z_as_relative = false
	_trail.z_index = 9 # just under the ball (z 10), over players and walls
	_trail.width = trail_width
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.0))
	taper.add_point(Vector2(1.0, 1.0))
	_trail.width_curve = taper
	_trail_gradient = Gradient.new()
	_trail_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	_trail_gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, trail_alpha)])
	_trail.gradient = _trail_gradient
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.antialiased = true
	add_child(_trail)


## Called once by the arena. Gives the ball its players and the first holder.
func setup(players: Array[DodgePlayer], first_holder: DodgePlayer) -> void:
	_players = players
	reset_round(first_holder)


## Start of a round: speed back to its initial value, ball to new_holder.
func reset_round(new_holder: DodgePlayer) -> void:
	speed_steps = 0
	bounce_count = 0
	_give_to(new_holder)


## Speed the next throw will have.
func next_throw_speed() -> float:
	return minf(ball_initial_speed + ball_speed_increment_per_throw * speed_steps, ball_max_speed)


func get_speed() -> float:
	return velocity.length()


## Connected to every player's throw_requested signal.
func try_throw(thrower: DodgePlayer) -> void:
	if not round_active or state != State.HELD or holder != thrower:
		return # Only the current holder may throw, and not during the countdown.

	# Clear line to the other player: aim at them. A wall in the way: throw
	# the way the thrower is facing (their movement direction).
	var direction := thrower.facing
	var target := _visible_opponent_in_sight(thrower)
	if target != null:
		direction = (target.global_position - thrower.global_position).normalized()

	# Launch from the thrower's centre. The thrower's circle can never overlap a
	# wall and ball_radius < player_radius, so the ball always starts in free
	# space (the held offset position might be poking into a wall).
	global_position = thrower.global_position
	_flight_speed = next_throw_speed()
	speed_steps += 1
	velocity = direction * _flight_speed
	last_thrower = thrower
	holder = null
	thrower.has_ball = false
	has_bounced = false
	bounce_count = 0
	_homing_time = 0.0
	state = State.FLYING
	# New trail from the launch point, in the thrower's colour.
	_trail_points = PackedVector2Array([global_position])
	_trail_color = thrower.body_color
	_trail_fade = 1.0
	SoundFx.play("throw")
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
	if player == last_thrower:
		_undo_speed_step() # caught their own throw: speed stays the same
	_give_to(player)
	SoundFx.play("catch")
	return true


func _physics_process(delta: float) -> void:
	if round_active and state == State.HELD:
		hold_time += delta
	match state:
		State.HELD:
			_lock_holder_facing()
			_follow_holder()
		State.FLYING, State.PASS_THROUGH:
			_fly(delta)
	_update_trail(delta)


## Record the flight path and redraw the trail; fade it out after a catch.
func _update_trail(delta: float) -> void:
	if _trail == null:
		return
	var flying := state == State.FLYING or state == State.PASS_THROUGH
	if flying:
		if _trail_points.is_empty() or _trail_points[-1].distance_to(global_position) > 0.5:
			_trail_points.append(global_position)
		# Keep only what can still be part of the trail.
		while _trail_points.size() > 64:
			_trail_points.remove_at(0)
		_trail_fade = 1.0
	elif _trail_fade > 0.0:
		_trail_fade = maxf(_trail_fade - delta / maxf(trail_fade_time, 0.001), 0.0)
		if _trail_fade <= 0.0:
			_trail_points.clear()
	_trail.points = _trail_curve()
	var head := Color(_trail_color, trail_alpha * _trail_fade)
	_trail_gradient.colors = PackedColorArray([Color(_trail_color, 0.0), head])


## The recorded path smoothed with Catmull-Rom splines, cut to trail_length
## measured back from the ball. Oldest point first.
func _trail_curve() -> PackedVector2Array:
	var raw := _trail_points
	var n := raw.size()
	if n < 2 or _trail_fade <= 0.0:
		return PackedVector2Array()
	var smooth := PackedVector2Array([raw[0]])
	var steps := maxi(trail_smoothing, 1)
	for i in n - 1:
		var p0 := raw[maxi(i - 1, 0)]
		var p1 := raw[i]
		var p2 := raw[i + 1]
		var p3 := raw[mini(i + 2, n - 1)]
		for s in range(1, steps + 1):
			var t := float(s) / steps
			smooth.append(_catmull_rom(p0, p1, p2, p3, t))
	# Walk back from the ball until trail_length is used up.
	var out := PackedVector2Array([smooth[-1]])
	var left := trail_length
	for i in range(smooth.size() - 1, 0, -1):
		var a := smooth[i]
		var b := smooth[i - 1]
		var seg := a.distance_to(b)
		if seg >= left:
			out.append(a.lerp(b, left / maxf(seg, 0.0001)))
			break
		out.append(b)
		left -= seg
	out.reverse()
	return out


func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3)


## While the holder can see the other player, they face them (so the ball
## sits on that side). Behind a wall, facing follows their movement again.
func _lock_holder_facing() -> void:
	if holder == null:
		return
	var target := _visible_opponent_in_sight(holder)
	if target != null:
		holder.facing = (target.global_position - holder.global_position).normalized()


## The other player if a ball-sized path from `player` to them is free of
## walls (outer walls and cover), otherwise null.
func _visible_opponent_in_sight(player: DodgePlayer) -> DodgePlayer:
	var other := _opponent_of(player)
	if other == null or not other.visible:
		return null
	if other.global_position.distance_squared_to(player.global_position) < 0.001:
		return null
	return other if has_line_of_sight(player.global_position, other.global_position) else null


## True if the ball could fly straight from `from` to `to` without touching a wall.
func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var motion := to - from
	if motion.length_squared() < 0.01:
		return true
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _collision.shape
	params.transform = Transform2D(0.0, from)
	params.motion = motion
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]
	var result := get_world_2d().direct_space_state.cast_motion(params)
	return result.size() > 0 and result[0] >= 1.0


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
	if not has_bounced and state == State.PASS_THROUGH and _hit_victim != null:
		var clear := _hit_victim.player_radius + ball_radius + pass_through_clearance
		if global_position.distance_to(_hit_victim.global_position) > clear:
			has_bounced = true # start homing now, no wall needed
			_homing_time = 0.0

	if has_bounced and last_thrower != null:
		_homing_time += delta
		var target := last_thrower.global_position
		if nav != null:
			target = nav.steer_target(global_position, target, ball_radius, [get_rid()])
		var to_thrower := target - global_position
		if to_thrower.length_squared() > 0.01:
			var turn_rate := deg_to_rad(homing_turn_rate_degrees) * (1.0 + homing_strength_ramp * _homing_time)
			var max_turn := turn_rate * delta
			var angle := direction.angle_to(to_thrower)
			direction = direction.rotated(clampf(angle, -max_turn, max_turn))

	velocity = direction * _flight_speed

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
			_trail_points.append(global_position) # exact bounce point for the trail
			SoundFx.play("bounce")
			bounced.emit(bounce_count)
		motion = remainder
		if motion.length_squared() < 0.0001:
			break

	_resolve_contacts(path)


## Walk the path in order; the first player body the ball touches decides
## what happens: the opponent is hit, the thrower (after a bounce) catches it.
## In PASS_THROUGH only the thrower counts: the ball flies through the victim.
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
					var after_hit := state == State.PASS_THROUGH
					_undo_speed_step() # own ball back: speed stays the same
					_give_to(player) # Returned to thrower: automatic catch.
					SoundFx.play("catch")
					if after_hit:
						returned_after_hit.emit(player)
					return
				continue # Just thrown: ignore the thrower's own body.
			if state == State.PASS_THROUGH:
				continue # Already scored: fly straight through the victim.
			# Opponent hit. Leave FLYING before emitting so this can only
			# score once. The ball keeps going (through the victim), then
			# bounces and homes back to the thrower as usual.
			state = State.PASS_THROUGH
			_hit_victim = player
			state_changed.emit()
			player_hit.emit(player, last_thrower)
			return


## The thrower got their own ball back: take back the step the throw added.
func _undo_speed_step() -> void:
	speed_steps = maxi(speed_steps - 1, 0)


func _give_to(player: DodgePlayer) -> void:
	holder = player
	hold_time = 0.0
	_hit_victim = null
	last_thrower = null
	has_bounced = false
	velocity = Vector2.ZERO
	state = State.HELD
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
	draw_circle(Vector2.ZERO, ball_radius, ball_color)
	draw_arc(Vector2.ZERO, ball_radius, 0.0, TAU, 32, ball_color.darkened(0.5), 1.5, true)
