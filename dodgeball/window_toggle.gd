extends Node
## F11 switches between fullscreen and a 1280x720 window, from any screen
## (menus, matches, the pause menu, the demo). Runs as the "WindowToggle"
## autoload. The game starts fullscreen (project setting window/size/mode).

const WINDOW_SIZE := Vector2i(1280, 720)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		get_viewport().set_input_as_handled()
		toggle()


func toggle() -> void:
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(WINDOW_SIZE)
		var screen := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(screen)
		DisplayServer.window_set_position(area.position + (area.size - WINDOW_SIZE) / 2)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
