class_name DodgePlayer
extends CharacterBody2D
## Top-down player. Reads its own input actions ("p1_*" or "p2_*"), moves with
## move_and_slide() so walls and the other player block it, and emits
## throw_requested / catch_requested. The ball decides whether a throw or a
## catch actually succeeds; a catch press keeps trying for catch_grace_time
## before it counts as a miss.

signal throw_requested(player: DodgePlayer)
signal catch_requested(player: DodgePlayer)

@export var player_id: int = 1
@export var display_name: String = "Player 1"
## Short colour name used in the score line and controls text (e.g. "Blue").
@export var color_name: String = "Blue"
@export var body_color: Color = Color(0.25, 0.55, 1.0)
## Top-down character sprite (drawn instead of the plain circle when set).
## It is drawn facing right, so it is rotated to `facing`, and scaled so its
## longest side matches the collision circle's diameter.
@export var character_texture: Texture2D

## Top movement speed in pixels per second.
@export var player_speed: float = 340.0
## How quickly the player reaches top speed / stops (pixels per second^2).
@export var player_acceleration: float = 3200.0
@export var player_deceleration: float = 3800.0
## Radius used for BOTH the drawn circle and the collision circle.
@export var player_radius: float = 24.0
## Direction the held ball sits in before the player has moved.
@export var initial_facing: Vector2 = Vector2.RIGHT

@export_group("Catching")
## The ball's centre must be within this distance of the player's centre
## when the catch key is pressed.
@export var catch_radius: float = 75.0
## A catch press keeps trying this many seconds, so pressing slightly early
## still catches the ball if it reaches the circle in time. Only then is it a
## miss (and the cooldown starts). 0 = the press is checked once.
@export var catch_grace_time: float = 0.075
## Seconds catching is disabled after a missed catch attempt.
@export var catch_cooldown: float = 1.0
@export var catch_circle_color: Color = Color(1.0, 1.0, 1.0, 0.16)
@export var catch_circle_cooldown_color: Color = Color(0.45, 0.45, 0.45, 0.32)

@export_group("Hold zone")
## Colour of the growing circle shown around the player while they hold the
## ball (its size is set by the arena through hold_zone_radius).
@export var hold_zone_color: Color = Color(1.0, 0.2, 0.2, 0.2)

@export_group("Dash")
## Speed during a dash (pixels per second).
@export var dash_speed: float = 1100.0
## How long a dash lasts (seconds). Distance is about dash_speed * dash_duration.
@export var dash_duration: float = 0.15
## Seconds before the player can dash again (counted from the start of a dash).
@export var dash_cooldown: float = 5.0
## Colour of the ring around the player: a full circle when the dash is ready,
## a partial arc that refills clockwise while it recharges.
@export var dash_cooldown_color: Color = Color(1.0, 1.0, 1.0, 0.55)
## Length of the longest motion line drawn behind a dashing player (pixels).
@export var dash_line_length: float = 70.0
## Seconds the motion lines take to fade out after the dash ends.
@export var dash_line_fade_time: float = 0.18
@export var dash_line_color: Color = Color(1.0, 1.0, 1.0, 0.85)

## Last non-zero movement direction (unit vector). The held ball sits this way.
var facing: Vector2 = Vector2.RIGHT
## Set by the ball. A player holding the ball has no catch circle.
var has_ball: bool = false
var catch_cooldown_remaining: float = 0.0
## Seconds left on the current catch attempt (see catch_grace_time).
var _catch_attempt_left: float = 0.0
var dash_cooldown_remaining: float = 0.0
var start_position: Vector2
## Movement allowed (off during the countdown; only the thrower may move
## during the death sequence).
var can_move: bool = true
## Throwing and catching allowed (off during the countdown and death sequence).
var can_act: bool = true
## Radius of the red hold zone; 0 hides it. Set by the arena every frame.
var hold_zone_radius: float = 0.0:
	set(value):
		if not is_equal_approx(value, hold_zone_radius):
			hold_zone_radius = value
			if _hold_zone_node != null:
				_hold_zone_node.queue_redraw()

var _action_prefix: String = "p1_"
## When set (single player), this player is driven by a DodgeBot instead of
## the keyboard: it supplies the move vector and throw / catch / dash presses.
var bot = null
var _hold_zone_node: Node2D = null
var _sprite: Sprite2D = null
var _dash_time_left: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
## Seconds since the last dash started (drives the motion lines); -1 = none.
var _dash_fx_time: float = -1.0

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_action_prefix = "p%d_" % player_id
	start_position = global_position
	facing = _initial_facing()

	# Give each instance its own shape so changing one player's radius never
	# affects the other, and sync it to the drawn radius.
	var circle := CircleShape2D.new()
	circle.radius = player_radius
	_collision.shape = circle

	# The hold zone is drawn by a child one layer down (z_index -1), so it sits
	# under both players and the ball instead of covering the other player.
	_hold_zone_node = Node2D.new()
	_hold_zone_node.name = "HoldZone"
	_hold_zone_node.z_index = -1
	_hold_zone_node.draw.connect(_draw_hold_zone)
	add_child(_hold_zone_node)

	if character_texture != null:
		_sprite = Sprite2D.new()
		_sprite.name = "Character"
		_sprite.texture = character_texture
		var longest := maxf(character_texture.get_width(), character_texture.get_height())
		_sprite.scale = Vector2.ONE * (2.0 * player_radius / longest)
		_sprite.rotation = facing.angle()
		add_child(_sprite)
	queue_redraw()


func _physics_process(delta: float) -> void:
	catch_cooldown_remaining = maxf(catch_cooldown_remaining - delta, 0.0)
	dash_cooldown_remaining = maxf(dash_cooldown_remaining - delta, 0.0)
	if _dash_fx_time >= 0.0:
		_dash_fx_time += delta
		if _dash_fx_time > dash_duration + dash_line_fade_time:
			_dash_fx_time = -1.0

	# Keyboard or bot; length <= 1, so diagonals are not faster.
	var input := _move_input()
	if not can_move:
		input = Vector2.ZERO
		_dash_time_left = 0.0 # a round ending mid-dash stops it

	var dash_pressed := _pressed("dash")
	if can_move and dash_pressed and dash_cooldown_remaining <= 0.0:
		_start_dash(input)

	if _dash_time_left > 0.0:
		# Dash: fixed high speed in a straight line. move_and_slide() still
		# stops it at walls and at the other player.
		_dash_time_left -= delta
		velocity = _dash_direction * dash_speed
		move_and_slide()
		if _dash_time_left <= 0.0:
			# Come out of the dash at normal top speed instead of sliding on.
			velocity = velocity.limit_length(player_speed)
	else:
		var target_velocity := input * player_speed
		var rate := player_acceleration if input != Vector2.ZERO else player_deceleration
		velocity = velocity.move_toward(target_velocity, rate * delta)
		move_and_slide()

	if input != Vector2.ZERO and _dash_time_left <= 0.0:
		facing = input.normalized()

	if can_act:
		if _pressed("throw") and has_ball:
			throw_requested.emit(self)

		if _pressed("catch") and can_attempt_catch():
			catch_requested.emit(self) # the ball sets has_ball right away on a catch
			if not has_ball:
				if catch_grace_time > 0.0:
					_catch_attempt_left = catch_grace_time
				else:
					start_catch_cooldown()
		elif _catch_attempt_left > 0.0:
			# Still inside the grace window: keep trying.
			_catch_attempt_left -= delta
			if has_ball:
				_catch_attempt_left = 0.0
			else:
				catch_requested.emit(self)
				if has_ball:
					_catch_attempt_left = 0.0
				elif _catch_attempt_left <= 0.0:
					_catch_attempt_left = 0.0
					start_catch_cooldown() # missed
	else:
		_catch_attempt_left = 0.0

	queue_redraw()


## Movement input (length <= 1): keyboard, or the bot in single player.
## get_vector() clamps to length 1, so diagonals are not faster.
func _move_input() -> Vector2:
	if bot != null:
		return (bot.move as Vector2).limit_length(1.0)
	return Input.get_vector(
		_action_prefix + "left",
		_action_prefix + "right",
		_action_prefix + "up",
		_action_prefix + "down"
	)


## "Just pressed" for throw / catch / dash: keyboard, or the bot.
func _pressed(action: String) -> bool:
	if bot != null:
		return bot.consume(action)
	return Input.is_action_just_pressed(_action_prefix + action)


## Dash the way the player is steering, or the way they face if standing still.
func _start_dash(input: Vector2) -> void:
	_dash_direction = input.normalized() if input != Vector2.ZERO else facing
	facing = _dash_direction
	_dash_time_left = dash_duration
	dash_cooldown_remaining = dash_cooldown
	_dash_fx_time = 0.0
	SoundFx.play("dash")


func is_dashing() -> bool:
	return _dash_time_left > 0.0


# Sprite rotation is set here rather than in _physics_process because the
# ball may lock `facing` onto the other player after this player has moved.
func _process(_delta: float) -> void:
	if _sprite != null:
		_sprite.rotation = facing.angle()


func can_attempt_catch() -> bool:
	return not has_ball and catch_cooldown_remaining <= 0.0 and _catch_attempt_left <= 0.0


## Called when a catch attempt missed.
func start_catch_cooldown() -> void:
	catch_cooldown_remaining = catch_cooldown
	SoundFx.play("miss")


## Back to the start of a round: start position, standing still, no cooldown.
func reset_for_round() -> void:
	global_position = start_position
	velocity = Vector2.ZERO
	facing = _initial_facing()
	catch_cooldown_remaining = 0.0
	_catch_attempt_left = 0.0
	dash_cooldown_remaining = 0.0
	_dash_time_left = 0.0
	_dash_fx_time = -1.0
	hold_zone_radius = 0.0
	visible = true # hidden while the death explosion plays
	_collision.set_deferred("disabled", false)
	queue_redraw()


## Victim of a hit: vanish (the explosion takes its place) and stop blocking
## the thrower, who can still walk around during the death sequence.
func hide_for_death() -> void:
	visible = false
	velocity = Vector2.ZERO
	_dash_time_left = 0.0
	_dash_fx_time = -1.0
	_collision.set_deferred("disabled", true)


func _draw_hold_zone() -> void:
	if hold_zone_radius <= 0.0:
		return
	_hold_zone_node.draw_circle(Vector2.ZERO, hold_zone_radius, hold_zone_color)
	_hold_zone_node.draw_arc(Vector2.ZERO, hold_zone_radius, 0.0, TAU, 96,
			Color(hold_zone_color, minf(hold_zone_color.a * 3.0, 1.0)), 2.0, true)


func _initial_facing() -> Vector2:
	return initial_facing.normalized() if initial_facing != Vector2.ZERO else Vector2.RIGHT


## White speed lines trailing behind the player, opposite the dash direction.
## They shoot out at the start of the dash and shrink and fade once it ends.
func _draw_dash_lines() -> void:
	if _dash_fx_time < 0.0 or _dash_direction == Vector2.ZERO:
		return
	var back := -_dash_direction
	var side := _dash_direction.orthogonal()
	var grow := clampf(_dash_fx_time / 0.05, 0.0, 1.0) # quick extend at the start
	var fade := 1.0
	if _dash_fx_time > dash_duration and dash_line_fade_time > 0.0:
		fade = clampf(1.0 - (_dash_fx_time - dash_duration) / dash_line_fade_time, 0.0, 1.0)
	# Five lines across the body: longest in the middle, shorter towards the edges.
	var offsets := [-0.7, -0.35, 0.0, 0.35, 0.7]
	var lengths := [0.55, 0.85, 1.0, 0.85, 0.55]
	for i in offsets.size():
		var start: Vector2 = back * (player_radius * 0.6) + side * (player_radius * offsets[i])
		var length: float = dash_line_length * lengths[i] * grow * (0.4 + 0.6 * fade)
		var end: Vector2 = start + back * length
		var c := dash_line_color
		c.a *= fade
		draw_line(start, end, c, 2.0, true)


func _draw() -> void:
	if not has_ball:
		var ring_color := catch_circle_color if catch_cooldown_remaining <= 0.0 else catch_circle_cooldown_color
		draw_circle(Vector2.ZERO, catch_radius, ring_color)
		draw_arc(Vector2.ZERO, catch_radius, 0.0, TAU, 64,
				Color(ring_color, minf(ring_color.a * 2.5, 1.0)), 1.5, true)

	_draw_dash_lines()

	if _sprite == null:
		draw_circle(Vector2.ZERO, player_radius, body_color)
		draw_arc(Vector2.ZERO, player_radius, 0.0, TAU, 48, body_color.darkened(0.45), 2.0, true)

	# Dash ring: full circle = dash ready; otherwise it refills clockwise from the top.
	var charged := 1.0
	if dash_cooldown > 0.0:
		charged = 1.0 - dash_cooldown_remaining / dash_cooldown
	if charged >= 1.0:
		draw_arc(Vector2.ZERO, player_radius + 5.0, 0.0, TAU, 48, dash_cooldown_color, 2.5, true)
	elif charged > 0.0:
		draw_arc(Vector2.ZERO, player_radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * charged, 48,
				dash_cooldown_color, 2.5, true)
	if _sprite == null:
		var font := ThemeDB.fallback_font
		var font_size := 18
		var label := str(player_id)
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, Vector2(-text_size.x * 0.5, font_size * 0.35), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
