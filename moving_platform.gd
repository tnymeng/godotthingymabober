class_name MovingPlatform
extends AnimatableBody2D

var distance := 180.0
var speed := 0.85
var axis := Vector2.RIGHT
var _origin := Vector2.ZERO
var _time := 0.0

func _ready() -> void:
	_origin = global_position
	sync_to_physics = true

func _physics_process(delta: float) -> void:
	_time += delta
	global_position = _origin + axis * sin(_time * speed) * distance
