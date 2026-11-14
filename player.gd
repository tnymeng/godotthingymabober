class_name Player
extends CharacterBody2D

const SPEED := 280.0
const ACCEL := 2400.0
const FRICTION := 2800.0
const JUMP_VELOCITY := -660.0
const GRAVITY := 1500.0
const MAX_FALL := 900.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12

@export var left_key: Key = KEY_A
@export var right_key: Key = KEY_D
@export var jump_key: Key = KEY_W
@export var body_color: Color = Color("3d8bff")
@export var player_name: String = "P1"
@export var spawn_point := Vector2.ZERO
@export var fall_y := 1100.0

var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_was := false
var _facing := 1.0
var _visual: Node2D

func _ready() -> void:
	add_to_group("players")
	floor_snap_length = 16.0
	collision_layer = 2
	collision_mask = 1
	z_index = 5
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(28, 40)
	shape.shape = rect
	shape.position = Vector2(0, -20)
	add_child(shape)
	_build_visual()

func _build_visual() -> void:
	_visual = Node2D.new()
	add_child(_visual)
	var outline := Polygon2D.new()
	outline.color = Color(0, 0, 0, 0.45)
	outline.polygon = PackedVector2Array([
		Vector2(-16, -42), Vector2(16, -42), Vector2(16, 1), Vector2(-16, 1),
	])
	_visual.add_child(outline)
	var body := Polygon2D.new()
	body.color = body_color
	body.polygon = PackedVector2Array([
		Vector2(-14, -40), Vector2(14, -40), Vector2(14, 0), Vector2(-14, 0),
	])
	_visual.add_child(body)
	_add_eye(Vector2(3, -26))
	_add_eye(Vector2(10, -26))
	var tag := Label.new()
	tag.text = player_name
	tag.position = Vector2(-12, -64)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", Color.WHITE)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tag.add_theme_constant_override("outline_size", 6)
	add_child(tag)

func _add_eye(at: Vector2) -> void:
	var white := Polygon2D.new()
	white.color = Color.WHITE
	white.polygon = _diamond(at, 3.2)
	_visual.add_child(white)
	var pupil := Polygon2D.new()
	pupil.color = Color(0.08, 0.1, 0.16)
	pupil.polygon = _diamond(at + Vector2(1.1, 0), 1.5)
	_visual.add_child(pupil)

func _diamond(center: Vector2, radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
	])

func _physics_process(delta: float) -> void:
	var jump_down := Input.is_physical_key_pressed(jump_key)
	if jump_down and not _jump_was:
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_jump_was = jump_down

	if is_on_floor():
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if not is_on_floor():
		var gravity := GRAVITY
		if velocity.y < 0.0 and not jump_down:
			gravity *= 2.2
		velocity.y = minf(velocity.y + gravity * delta, MAX_FALL)

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0

	var direction := 0.0
	if Input.is_physical_key_pressed(left_key):
		direction -= 1.0
	if Input.is_physical_key_pressed(right_key):
		direction += 1.0

	var target := direction * SPEED
	var rate := ACCEL if direction != 0.0 else FRICTION
	velocity.x = move_toward(velocity.x, target, rate * delta)
	if direction != 0.0:
		_facing = direction
	_visual.scale = Vector2(_facing, 1.0)

	move_and_slide()

	if global_position.y > fall_y:
		global_position = spawn_point
		velocity = Vector2.ZERO
