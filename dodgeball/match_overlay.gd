extends CanvasLayer
## Pause menu (Esc: Resume / Restart / Main menu) and the end-of-match victory
## screen (Rematch / Main menu). Both pause the scene tree; this layer keeps
## running while paused. The arena decides what Restart / Rematch / Main menu do.

signal paused_changed(paused: bool)
signal restart_requested
signal main_menu_requested

## Esc opens the pause menu. Off in attract mode (any key goes to the menu).
var pause_enabled: bool = true

@onready var pause_panel: Control = %PausePanel
@onready var victory_panel: Control = %VictoryPanel
@onready var victory_title: Label = %VictoryTitle
@onready var victory_score: Label = %VictoryScore


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.visible = false
	victory_panel.visible = false
	for b in [%ResumeButton, %RestartButton, %PauseMenuButton, %RematchButton, %VictoryMenuButton]:
		b.pressed.connect(func(): SoundFx.play("click"))
	%ResumeButton.pressed.connect(set_paused.bind(false))
	%RestartButton.pressed.connect(restart_requested.emit)
	%PauseMenuButton.pressed.connect(main_menu_requested.emit)
	%RematchButton.pressed.connect(restart_requested.emit)
	%VictoryMenuButton.pressed.connect(main_menu_requested.emit)


func _process(_delta: float) -> void:
	if pause_enabled and Input.is_action_just_pressed("pause") and not victory_panel.visible:
		set_paused(not pause_panel.visible)


func is_open() -> bool:
	return pause_panel.visible or victory_panel.visible


func set_paused(paused: bool) -> void:
	if paused == pause_panel.visible:
		return
	get_tree().paused = paused
	pause_panel.visible = paused
	if paused:
		%ResumeButton.grab_focus()
	paused_changed.emit(paused)


func show_victory(title: String, colour: Color, score_line: String) -> void:
	pause_panel.visible = false
	victory_title.text = title
	victory_title.add_theme_color_override("font_color", colour)
	victory_score.text = score_line
	victory_panel.visible = true
	get_tree().paused = true
	%RematchButton.grab_focus()
