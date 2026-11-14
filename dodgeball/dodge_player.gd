class_name DodgePlayer
extends CharacterBody2D
## Top-down player. Reads its own input actions ("p1_*" or "p2_*"), moves with
## move_and_slide() so walls and the other player block it, and emits
## throw_requested / catch_requested. The ball decides whether a throw or a
## catch actually succeeds; the arena tells the player when a catch failed.

signal throw_requested(player: DodgePlayer)
signal catch_requested(player: DodgePlayer)

@export var player_id: int = 1
@export var display_name: String = "Player 1"
@export var body_color: Color = Color(0.25, 0.55, 1.0)

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
@export var catch_radius: float = 70.0
## Seconds catching is disabled after a missed catch attempt.
@export var catch_cooldown: float = 1.0
@export var catch_circle_color: Color = Color(1.0, 1.0, 1.0, 0.16)
@export var catch_circle_cooldown_color: Color = Color(0.45, 0.45, 0.45, 0.32)

## Last non-zero movement direction (unit vector). The held ball sits this way.
var facing: Vector2 = Vector2.RIGHT
## Set by the ball. A player holding the ball has no catch circle.
var has_ball: bool = false
var catch_cooldown_remaining: float = 0.0
var start_position: Vector2
## False during the round-start countdown: no moving, throwing or catching.
var controls_enabled: bool = true

var _action_prefix: String = "p1_"

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
	queue_redraw()


func _physics_process(delta: float) -> void:
	catch_cooldown_remaining = maxf(catch_cooldown_remaining - delta, 0.0)

	# get_vector() clamps the result to length 1, so diagonals are not faster.
	var input := Input.get_vector(
		_action_prefix + "left",
		_action_prefix + "right",
		_action_prefix + "up",
		_action_prefix + "down"
	)
	if not controls_enabled:
		input = Vector2.ZERO

	var target_velocity := input * player_speed
	var rate := player_acceleration if input != Vector2.ZERO else player_deceleration
	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()

	if input != Vector2.ZERO:
		facing = input.normalized()

	if controls_enabled:
		if Input.is_action_just_pressed(_action_prefix + "throw") and has_ball:
			throw_requested.emit(self)

		if Input.is_action_just_pressed(_action_prefix + "catch") and can_attempt_catch():
			catch_requested.emit(self)

	queue_redraw()


func can_attempt_catch() -> bool:
	return not has_ball and catch_cooldown_remaining <= 0.0


## Called by the arena when a catch attempt missed.
func start_catch_cooldown() -> void:
	catch_cooldown_remaining = catch_cooldown


## Back to the start of a round: start position, standing still, no cooldown.
func reset_for_round() -> void:
	global_position = start_position
	velocity = Vector2.ZERO
	facing = _initial_facing()
	catch_cooldown_remaining = 0.0
	queue_redraw()


func _initial_facing() -> Vector2:
	return initial_facing.normalized() if initial_facing != Vector2.ZERO else Vector2.RIGHT


func _draw() -> void:
	if not has_ball:
		var ring_color := catch_circle_color if catch_cooldown_remaining <= 0.0 else catch_circle_cooldown_color
		draw_circle(Vector2.ZERO, catch_radius, ring_color)
		draw_arc(Vector2.ZERO, catch_radius, 0.0, TAU, 64,
				Color(ring_color, minf(ring_color.a * 2.5, 1.0)), 1.5, true)

	draw_circle(Vector2.ZERO, player_radius, body_color)
	draw_arc(Vector2.ZERO, player_radius, 0.0, TAU, 48, body_color.darkened(0.45), 2.0, true)
	var font := ThemeDB.fallback_font
	var font_size := 18
	var label := str(player_id)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-text_size.x * 0.5, font_size * 0.35), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
