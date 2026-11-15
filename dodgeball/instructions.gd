extends Control
## How to play: controls and rules. Back returns to the main menu.

const MAIN_MENU := "res://dodgeball/main_menu.tscn"

@onready var back_button: Button = %BackButton


func _ready() -> void:
	back_button.pressed.connect(go_back)
	back_button.grab_focus()


func go_back() -> void:
	SoundFx.play("back")
	get_tree().change_scene_to_file(MAIN_MENU)
