extends Control
## Points screen, between the difficulty screen and the character select:
## first to 3, 5 or 7 points wins the match. The last choice (5 at first)
## starts focused; Up / Down move, Enter / Space / click choose.

const CHARACTER_SELECT := "res://dodgeball/character_select.tscn"
const DIFFICULTY_SELECT := "res://dodgeball/difficulty_select.tscn"
const CHOICES: Array[int] = [3, 5, 7]

@onready var buttons: Array[Button] = [%ThreeButton, %FiveButton, %SevenButton]

var _chosen := false


func _ready() -> void:
	for i in CHOICES.size():
		buttons[i].pressed.connect(choose.bind(CHOICES[i]))
	%BackButton.pressed.connect(go_back)
	var current := CHOICES.find(CharacterSelect.points_to_win)
	buttons[current if current >= 0 else 1].grab_focus()


func choose(points: int) -> void:
	if _chosen:
		return
	SoundFx.play("click")
	_chosen = true
	CharacterSelect.points_to_win = points
	get_tree().change_scene_to_file(CHARACTER_SELECT)


func go_back() -> void:
	if _chosen:
		return
	SoundFx.play("back")
	_chosen = true
	get_tree().change_scene_to_file(DIFFICULTY_SELECT)
