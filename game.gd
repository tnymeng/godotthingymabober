extends Node2D

const GROUND := Color("3d4c63")
const GROUND_TOP := Color("6ea37a")
const STONE := Color("6e7c93")
const STONE_TOP := Color("a9bad4")
const GOLD := Color("e2b34d")
const GOLD_TOP := Color("ffe08a")

var _player_one: Player
var _player_two: Player
var _camera: Camera2D
var _banner: Label
var _on_goal: Dictionary = {}
var _won := false
var _restart_was := false

func _ready() -> void:
	_build_sky()
	_build_level()
	_build_goal()
	_spawn_players()
	_build_camera()
	_build_hud()

func _build_sky() -> void:
	_quad(Rect2(-400, -500, 4200, 1800), Color("1b2433"), -20)
	_quad(Rect2(-200, 300, 3800, 240), Color("243044"), -19)

func _physics_process(delta: float) -> void:
	_follow_players(delta)
	_refresh_banner()
	var restart := Input.is_physical_key_pressed(KEY_R)
	if _won and restart and not _restart_was:
		get_tree().reload_current_scene()
	_restart_was = restart

func _build_level() -> void:
	_platform(Vector2(500, 660), Vector2(1000, 64), GROUND, GROUND_TOP)
	_platform(Vector2(420, 540), Vector2(150, 20), STONE, STONE_TOP)
	_platform(Vector2(680, 470), Vector2(140, 20), STONE, STONE_TOP)
	_platform(Vector2(920, 540), Vector2(150, 20), STONE, STONE_TOP)
	_platform(Vector2(1140, 530), Vector2(180, 20), STONE, STONE_TOP)
	_platform(Vector2(1630, 660), Vector2(700, 64), GROUND, GROUND_TOP)
	_platform(Vector2(1480, 500), Vector2(160, 20), STONE, STONE_TOP)
	_platform(Vector2(1685, 400), Vector2(170, 20), STONE, STONE_TOP)
	_platform(Vector2(1900, 510), Vector2(140, 20), STONE, STONE_TOP)
	_platform(Vector2(2240, 548), Vector2(220, 20), STONE, STONE_TOP, true)
	_platform(Vector2(2900, 660), Vector2(800, 64), GROUND, GROUND_TOP)
	_platform(Vector2(2620, 540), Vector2(150, 20), STONE, STONE_TOP)
	_platform(Vector2(2760, 470), Vector2(150, 20), STONE, STONE_TOP)
	_platform(Vector2(3040, 360), Vector2(210, 22), GOLD, GOLD_TOP)

func _quad(rect: Rect2, color: Color, z: int) -> void:
	var poly := Polygon2D.new()
	poly.z_index = z
	poly.color = color
	poly.polygon = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])
	add_child(poly)

func _platform(center: Vector2, size: Vector2, fill: Color, top: Color, moving := false) -> Node2D:
	var body: Node2D = MovingPlatform.new() if moving else StaticBody2D.new()
	body.position = center
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	body.add_child(_slab(size, fill))
	var cap_h := minf(8.0, size.y * 0.4)
	var cap := _slab(Vector2(size.x, cap_h), top)
	cap.position = Vector2(0, -size.y * 0.5 + cap_h * 0.5)
	body.add_child(cap)
	add_child(body)
	return body

func _slab(size: Vector2, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var half := size * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	poly.color = color
	return poly

func _spawn_players() -> void:
	_player_one = _make_player(Vector2(150, 626), KEY_A, KEY_D, KEY_W, Color("3d8bff"), "P1")
	_player_two = _make_player(Vector2(220, 626), KEY_LEFT, KEY_RIGHT, KEY_UP, Color("ff6b3d"), "P2")

func _make_player(at: Vector2, left: Key, right: Key, jump: Key, color: Color, label: String) -> Player:
	var player := Player.new()
	player.position = at
	player.left_key = left
	player.right_key = right
	player.jump_key = jump
	player.body_color = color
	player.player_name = label
	player.spawn_point = at
	add_child(player)
	return player

func _build_goal() -> void:
	var area := Area2D.new()
	area.position = Vector2(3040, 300)
	area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(170, 120)
	shape.shape = rect
	area.add_child(shape)
	var flag := Polygon2D.new()
	flag.polygon = PackedVector2Array([
		Vector2(78, 28), Vector2(84, 28), Vector2(84, -70), Vector2(78, -70),
	])
	flag.color = Color("f4f7fb")
	area.add_child(flag)
	var cloth := Polygon2D.new()
	cloth.polygon = PackedVector2Array([
		Vector2(84, -70), Vector2(132, -52), Vector2(84, -34),
	])
	cloth.color = Color("e85d4c")
	area.add_child(cloth)
	area.body_entered.connect(_on_goal_entered)
	area.body_exited.connect(_on_goal_exited)
	add_child(area)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.position = Vector2(480, 420)
	_camera.zoom = Vector2(1.15, 1.15)
	add_child(_camera)
	_camera.make_current()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := _label("P1 blue: WASD          P2 orange: arrow keys", 22)
	title.position = Vector2(28, 18)
	layer.add_child(title)
	_banner = _label("Get both players onto the gold platform", 28)
	_banner.position = Vector2(28, 56)
	layer.add_child(_banner)

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	return label

func _follow_players(delta: float) -> void:
	if _player_one == null or _player_two == null:
		return
	var midpoint := (_player_one.global_position + _player_two.global_position) * 0.5
	midpoint.y -= 30.0
	var span := absf(_player_one.global_position.x - _player_two.global_position.x)
	var span_y := absf(_player_one.global_position.y - _player_two.global_position.y)
	var fit := maxf(span / 900.0, span_y / 420.0)
	var target_zoom := clampf(1.2 - fit, 0.55, 1.2)
	var blend := 1.0 - exp(-5.0 * delta)
	_camera.global_position = _camera.global_position.lerp(midpoint, blend)
	_camera.zoom = _camera.zoom.lerp(Vector2.ONE * target_zoom, blend)

func _on_goal_entered(body: Node2D) -> void:
	if not body.is_in_group("players"):
		return
	_on_goal[body] = true
	_refresh_banner()

func _on_goal_exited(body: Node2D) -> void:
	_on_goal.erase(body)
	_refresh_banner()

func _refresh_banner() -> void:
	if _won:
		return
	var blue_ready := _on_goal.has(_player_one) and _player_one.is_on_floor()
	var orange_ready := _on_goal.has(_player_two) and _player_two.is_on_floor()
	if blue_ready and orange_ready:
		_won = true
		_banner.text = "Both made it!   Press R to play again"
		_banner.add_theme_color_override("font_color", Color("ffe08a"))
		return
	if blue_ready:
		_banner.text = "Blue is on the flag. Orange, catch up."
	elif orange_ready:
		_banner.text = "Orange is on the flag. Blue, catch up."
	else:
		_banner.text = "Get both players onto the gold platform"
