extends CanvasLayer
## Fades every new screen in from black (menus, matches, restarts). Runs as
## the "ScreenFade" autoload and watches for the current scene changing, so
## scene changes themselves aren't delayed. Real time, works while paused,
## and never blocks the mouse.

## Seconds to fade in from black.
@export var fade_time: float = 0.3

var _rect: ColorRect
var _scene: Node = null
var _start_usec: int = 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Black"
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(_delta: float) -> void:
	var current := get_tree().current_scene
	if current != _scene:
		_scene = current
		_start_usec = Time.get_ticks_usec()
	var t := (Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	var a := 1.0 - clampf(t / fade_time, 0.0, 1.0) if fade_time > 0.0 else 0.0
	_rect.color.a = a * a # ease out
	_rect.visible = a > 0.0
