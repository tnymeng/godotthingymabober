extends Control
## Title screen. Start (two players) and Single Player (vs a bot) both open
## the difficulty screen, then the character select. The buttons can be clicked, Start
## begins focused (Enter / Space; Up / Down move between buttons), and either
## player's throw key (E or Period) also starts a two-player game, so nobody
## needs the mouse.

const DIFFICULTY_SELECT := "res://dodgeball/difficulty_select.tscn"
const INSTRUCTIONS := "res://dodgeball/instructions.tscn"
const ARENA := "res://dodgeball/arena.tscn"
const PHOTO_SELECT := "res://dodgeball/photo_select.tscn"

@onready var start_button: Button = %StartButton
@onready var single_player_button: Button = %SinglePlayerButton
@onready var how_to_play_button: Button = %HowToPlayButton

var _starting := false


func _ready() -> void:
	start_button.pressed.connect(start_game)
	single_player_button.pressed.connect(start_single_player)
	how_to_play_button.pressed.connect(open_instructions)
	start_button.grab_focus()
	# Keep the title animation passing behind Start once the layout is done.
	await get_tree().process_frame
	if is_inside_tree():
		$Backdrop.player_y = start_button.get_global_rect().get_center().y


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("p1_throw") or Input.is_action_just_pressed("p2_throw"):
		start_game()
	elif Input.is_action_just_pressed("attract_mode"):
		start_attract_mode()
	elif Input.is_action_just_pressed("photo_mode"):
		open_photo_mode()


## U: attract mode, two bots playing each other (Blue vs Orange, Gym court,
## Normal difficulty). Esc opens the pause menu to get back to the menu.
func start_attract_mode() -> void:
	if _starting:
		return
	_starting = true
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	arena.attract_mode = true
	arena.difficulty = Difficulty.NORMAL
	arena.apply_player_kits([0, 1] as Array[int])
	arena.apply_court(0)
	var tree := get_tree()
	tree.root.add_child(arena)
	tree.current_scene = arena
	queue_free()


## Y: photo mode, players take photos with the camera to use as their characters.
func open_photo_mode() -> void:
	if _starting:
		return
	SoundFx.play("click")
	_starting = true
	get_tree().change_scene_to_file(PHOTO_SELECT)


func start_game() -> void:
	_open_select(false)


func start_single_player() -> void:
	_open_select(true)


func open_instructions() -> void:
	if _starting:
		return
	SoundFx.play("click")
	_starting = true
	get_tree().change_scene_to_file(INSTRUCTIONS)


func _open_select(single_player: bool) -> void:
	if _starting:
		return
	SoundFx.play("click")
	_starting = true
	CharacterSelect.single_player = single_player
	get_tree().change_scene_to_file(DIFFICULTY_SELECT)
