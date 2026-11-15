extends Control
## Credits: the team, centred. Back returns to the main menu.

const MAIN_MENU := "res://dodgeball/main_menu.tscn"

@onready var back_button: Button = %BackButton

var _leaving := false


func _ready() -> void:
	back_button.pressed.connect(go_back)
	back_button.grab_focus()


func go_back() -> void:
	if _leaving:
		return
	_leaving = true
	SoundFx.play("back")
	get_tree().change_scene_to_file(MAIN_MENU)
