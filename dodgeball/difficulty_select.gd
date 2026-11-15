extends Control
## Difficulty screen, between the main menu and the character select. Shows
## what each level means for the mode that was picked (two players or single
## player). Normal starts focused; Up / Down move, Enter / Space / click choose.

const CHARACTER_SELECT := "res://dodgeball/character_select.tscn"
const MAIN_MENU := "res://dodgeball/main_menu.tscn"

@onready var mode_label: Label = %ModeLabel
@onready var buttons: Array[Button] = [%EasyButton, %NormalButton, %HardButton]
@onready var descriptions: Array[Label] = [%EasyText, %NormalText, %HardText]

var _chosen := false


func _ready() -> void:
	var single := CharacterSelect.single_player
	mode_label.text = "Single player vs bot" if single else "Two players"
	var texts := Difficulty.SINGLE_PLAYER_TEXT if single else Difficulty.TWO_PLAYER_TEXT
	for level in buttons.size():
		descriptions[level].text = texts[level]
		buttons[level].pressed.connect(choose.bind(level))
	%BackButton.pressed.connect(go_back)
	buttons[Difficulty.NORMAL].grab_focus()


func choose(level: int) -> void:
	if _chosen:
		return
	SoundFx.play("click")
	_chosen = true
	CharacterSelect.difficulty = Difficulty.clamp_level(level)
	get_tree().change_scene_to_file(CHARACTER_SELECT)


func go_back() -> void:
	if _chosen:
		return
	SoundFx.play("back")
	_chosen = true
	get_tree().change_scene_to_file(MAIN_MENU)
