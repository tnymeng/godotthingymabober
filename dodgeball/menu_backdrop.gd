extends Node2D
## Title screen animation: two players pass the ball back and forth behind the
## Start button. Drawn before (behind) the menu's buttons and text.

@export var left_kit: int = 0   # Blue
@export var right_kit: int = 1  # Orange
@export var left_x: float = 300.0
@export var right_x: float = 980.0
@export var player_y: float = 460.0
## Sprite size relative to the 21 x 31 px in-game sprite.
@export var player_scale: float = 3.2
## Seconds the ball is in the air for one pass, and held before each throw.
@export var pass_time: float = 0.9
@export var hold_time: float = 0.35
@export var ball_radius: float = 13.0
@export var ball_color: Color = Color(1.0, 0.85, 0.15)

var _textures: Array[Texture2D] = []
var _time: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_textures = [CharacterLooks.hd_texture(left_kit), CharacterLooks.hd_texture(right_kit)]
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var left := Vector2(left_x, player_y)
	var right := Vector2(right_x, player_y)
	# Sprites face right: the left player faces right, the right player left.
	_draw_player(_textures[0], left, 0.0)
	_draw_player(_textures[1], right, PI)
	draw_circle(_ball_position(left, right), ball_radius, ball_color)
	draw_arc(_ball_position(left, right), ball_radius, 0.0, TAU, 32, ball_color.darkened(0.5), 2.0, true)


func _draw_player(tex: Texture2D, pos: Vector2, rotation_angle: float) -> void:
	# Same on-screen size as the 21 x 31 sprite at player_scale.
	var k := player_scale * 31.0 / tex.get_size().y
	draw_set_transform(pos, rotation_angle, Vector2(k, k))
	draw_texture(tex, -tex.get_size() * 0.5)
	draw_set_transform(Vector2.ZERO)


## Hold at the left hand, fly right, hold at the right hand, fly back.
func _ball_position(left: Vector2, right: Vector2) -> Vector2:
	var reach := 21.0 * player_scale * 0.5 + ball_radius + 2.0
	var left_hand := left + Vector2(reach, 0)
	var right_hand := right - Vector2(reach, 0)
	var cycle := 2.0 * (hold_time + pass_time)
	var t := fmod(_time, cycle)
	if t < hold_time:
		return left_hand
	t -= hold_time
	if t < pass_time:
		return left_hand.lerp(right_hand, t / pass_time)
	t -= pass_time
	if t < hold_time:
		return right_hand
	t -= hold_time
	return right_hand.lerp(left_hand, t / pass_time)
