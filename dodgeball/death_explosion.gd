class_name DeathExplosion
extends Node2D
## Procedural "player pops" animation, drawn with _draw() (no assets).
## Runs on game time, so under Engine.time_scale slow motion it plays slowly.
## Frees itself when finished.

## Length of the animation in game seconds. With the arena's 1 s of 0.2 slow
## motion and 0.5 s speed-up, it finishes about 2.4 s after the hit.
@export var duration: float = 1.4
@export var shard_count: int = 24
@export var shard_speed_min: float = 160.0
@export var shard_speed_max: float = 460.0
@export var shockwave_radius: float = 150.0

var _color: Color = Color.WHITE
var _radius: float = 24.0
var _time: float = 0.0
var _shards: Array[Dictionary] = []


## Call before adding to the tree.
func setup(color: Color, radius: float) -> void:
	_color = color
	_radius = radius
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_shards.clear()
	for i in shard_count:
		var angle := TAU * (i + rng.randf_range(-0.4, 0.4)) / shard_count
		_shards.append({
			"dir": Vector2.from_angle(angle),
			"speed": rng.randf_range(shard_speed_min, shard_speed_max),
			"size": rng.randf_range(3.0, 8.0),
			"spin": rng.randf_range(-12.0, 12.0),
			"angle": rng.randf() * TAU,
			"color": _color.lightened(rng.randf_range(0.0, 0.5)),
		})


func _ready() -> void:
	z_index = 5 # under the ball (z 10), so the ball visibly flies through it
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _time >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_time / duration, 0.0, 1.0) # 0 -> 1 over the animation

	# 1. Body swells and flashes white, then pops (first ~12%).
	var pop := 0.12
	if k < pop:
		var p := k / pop
		draw_circle(Vector2.ZERO, _radius * (1.0 + 0.45 * p), _color.lerp(Color.WHITE, p))

	# 2. Soft glow that grows and fades.
	var glow_alpha := 0.45 * (1.0 - k)
	draw_circle(Vector2.ZERO, _radius * (1.0 + 2.2 * _ease_out(k)), Color(_color, glow_alpha * 0.5))

	# 3. Shockwave ring.
	var ring_k := clampf(k / 0.6, 0.0, 1.0)
	if ring_k < 1.0:
		var ring_r := _radius + (shockwave_radius - _radius) * _ease_out(ring_k)
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 64,
				Color(1.0, 1.0, 1.0, 1.0 - ring_k), 6.0 * (1.0 - ring_k) + 1.0, true)

	# 4. Shards fly out, slow down (drag), spin, shrink and fade.
	var t := _time
	var drag := 3.0
	for s in _shards:
		var travel: float = s.speed * (1.0 - exp(-drag * t)) / drag
		var pos: Vector2 = s.dir * (_radius * 0.6 + travel)
		var size: float = s.size * (1.0 - k * 0.85)
		var rot: float = s.angle + s.spin * t
		var c: Color = s.color
		c.a = 1.0 - k * k
		var points := PackedVector2Array([
			pos + Vector2.from_angle(rot) * size,
			pos + Vector2.from_angle(rot + 2.3) * size * 0.8,
			pos + Vector2.from_angle(rot - 2.3) * size * 0.8,
		])
		draw_colored_polygon(points, c)


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
