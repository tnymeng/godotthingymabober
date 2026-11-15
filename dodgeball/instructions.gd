extends Control
## How to play: controls and rules. Back returns to the main menu. The
## controls list shows the keys of the current control preset (6 / 7).

const MAIN_MENU := "res://dodgeball/main_menu.tscn"

## Full key names per preset for the controls list.
const KEY_NAMES := {
	6: {1: ["W A S D", "E", "Left Shift"], 2: ["Arrow keys", ". (period)", "Right Shift"]},
	7: {1: ["W A S D", "C", "Left Shift"], 2: ["I J K L", ". (period)", "B"]},
}

@onready var back_button: Button = %BackButton
@onready var controls_text: Label = $Center/Column/Columns/Controls/Text


func _ready() -> void:
	controls_text.text = _controls_text()
	back_button.pressed.connect(go_back)
	back_button.grab_focus()


func _controls_text() -> String:
	var lines: PackedStringArray = []
	for player in [1, 2]:
		var k: Array = KEY_NAMES[ControlScheme.current][player]
		lines.append("Player %d" % player)
		lines.append("   Move: %s" % k[0])
		lines.append("   Throw / catch: %s" % k[1])
		lines.append("   Dash: %s" % k[2])
		lines.append("")
	lines.append("Pause: Esc")
	lines.append("Switch controls in a match: 6 / 7")
	lines.append("")
	lines.append("Single player: you are Player 1")
	lines.append("against a computer player.")
	return "\n".join(lines)


func go_back() -> void:
	SoundFx.play("back")
	get_tree().change_scene_to_file(MAIN_MENU)
