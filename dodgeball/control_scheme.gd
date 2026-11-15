class_name ControlScheme
extends RefCounted
## Keyboard control presets for the two players. Press 6 or 7 during a match
## to switch (see Arena); the keys are rebound in the InputMap straight away
## and stay that way until switched again. The game always starts on preset 7,
## which matches the bindings saved in project.godot.
##
##   Preset 6: Player 1 W A S D, E throw/catch, Left Shift dash
##             Player 2 arrow keys, Period throw/catch, Right Shift dash
##   Preset 7: Player 1 W A S D, C throw/catch, Left Shift dash
##             Player 2 I J K L, Period throw/catch, B dash

const DEFAULT := 7

## action -> [physical key, key location]
const PRESETS := {
	6: {
		"p1_up": [KEY_W, KEY_LOCATION_UNSPECIFIED], "p1_left": [KEY_A, KEY_LOCATION_UNSPECIFIED],
		"p1_down": [KEY_S, KEY_LOCATION_UNSPECIFIED], "p1_right": [KEY_D, KEY_LOCATION_UNSPECIFIED],
		"p1_throw": [KEY_E, KEY_LOCATION_UNSPECIFIED], "p1_dash": [KEY_SHIFT, KEY_LOCATION_LEFT],
		"p2_up": [KEY_UP, KEY_LOCATION_UNSPECIFIED], "p2_left": [KEY_LEFT, KEY_LOCATION_UNSPECIFIED],
		"p2_down": [KEY_DOWN, KEY_LOCATION_UNSPECIFIED], "p2_right": [KEY_RIGHT, KEY_LOCATION_UNSPECIFIED],
		"p2_throw": [KEY_PERIOD, KEY_LOCATION_UNSPECIFIED], "p2_dash": [KEY_SHIFT, KEY_LOCATION_RIGHT],
	},
	7: {
		"p1_up": [KEY_W, KEY_LOCATION_UNSPECIFIED], "p1_left": [KEY_A, KEY_LOCATION_UNSPECIFIED],
		"p1_down": [KEY_S, KEY_LOCATION_UNSPECIFIED], "p1_right": [KEY_D, KEY_LOCATION_UNSPECIFIED],
		"p1_throw": [KEY_C, KEY_LOCATION_UNSPECIFIED], "p1_dash": [KEY_SHIFT, KEY_LOCATION_LEFT],
		"p2_up": [KEY_I, KEY_LOCATION_UNSPECIFIED], "p2_left": [KEY_J, KEY_LOCATION_UNSPECIFIED],
		"p2_down": [KEY_K, KEY_LOCATION_UNSPECIFIED], "p2_right": [KEY_L, KEY_LOCATION_UNSPECIFIED],
		"p2_throw": [KEY_PERIOD, KEY_LOCATION_UNSPECIFIED], "p2_dash": [KEY_B, KEY_LOCATION_UNSPECIFIED],
	},
}

## Short names shown in hints (move keys, throw/catch key, dash key, and the
## up/down and left/right pairs used on the character select screen).
const LABELS := {
	6: {
		1: {"move": "WASD", "throw": "E", "dash": "L-Shift", "up_down": "W / S", "left_right": "A / D"},
		2: {"move": "Arrows", "throw": ".", "dash": "R-Shift", "up_down": "↑ / ↓", "left_right": "← / →"},
	},
	7: {
		1: {"move": "WASD", "throw": "C", "dash": "L-Shift", "up_down": "W / S", "left_right": "A / D"},
		2: {"move": "IJKL", "throw": ".", "dash": "B", "up_down": "I / K", "left_right": "J / L"},
	},
}

static var current: int = DEFAULT


## Rebind every player action to the given preset (6 or 7).
static func apply(preset: int) -> void:
	if not PRESETS.has(preset):
		return
	current = preset
	var keys: Dictionary = PRESETS[preset]
	for action in keys:
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action][0]
		ev.location = keys[action][1]
		InputMap.action_add_event(action, ev)


## Hint text for one player (1 or 2) in the current preset, e.g. "throw" -> "C".
static func label(player: int, what: String) -> String:
	return LABELS[current][player][what]


## "WASD move, C throw/catch, L-Shift dash" for one player.
static func controls_line(player: int) -> String:
	return "%s move, %s throw/catch, %s dash" % [
			label(player, "move"), label(player, "throw"), label(player, "dash")]
