class_name AttractOverlay
extends CanvasLayer
## Shown in attract (demo) mode: a flashing "PRESS ANY BUTTON TO PLAY!" and a
## listener for any key, mouse button or gamepad button. Keeps running while
## the game is paused (e.g. on the victory screen) and sits above everything.

signal any_button_pressed

## Seconds per flash cycle, and how much of it the text is shown.
@export var flash_period: float = 1.0
@export_range(0.0, 1.0) var flash_on_fraction: float = 0.6

var label: Label
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	label = Label.new()
	label.name = "PressAnyButton"
	label.text = "PRESS ANY BUTTON TO PLAY!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"DisplayLabel"
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 12)
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -150.0
	label.offset_bottom = -80.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _process(_delta: float) -> void:
	# Real time, so it flashes steadily through slow motion and pauses.
	var t := fmod(Time.get_ticks_msec() / 1000.0, flash_period)
	label.visible = t < flash_period * flash_on_fraction


func _input(event: InputEvent) -> void:
	if _done:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		_done = true
		get_viewport().set_input_as_handled()
		any_button_pressed.emit()
