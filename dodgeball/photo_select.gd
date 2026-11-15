extends Control
## Photo mode (Y on the main menu): each player clicks their round camera
## button to take a photo with the computer's camera, and that photo becomes
## their character circle. Click again to retake. PLAY starts a normal
## two-player match (Blue vs Orange, Hardwood Hall, Normal) once both players
## have a photo.

const ARENA := "res://dodgeball/arena.tscn"
const MAIN_MENU := "res://dodgeball/main_menu.tscn"

## Kits used for the colours, names, rings and trails (Blue and Orange).
const KITS: Array[int] = [0, 1]
const BUTTON_SIZE := 220.0
const PANEL_Y := 110.0
const PANEL_H := 470.0

var webcam := Webcam.new()
## Upright round photo per player (for this screen), null until taken.
var previews: Array = [null, null]
## Round photo per player turned to the sprites' "facing right" direction.
var game_textures: Array = [null, null]
var status_labels: Array[Label] = []
var camera_buttons: Array[Button] = []
var play_button: Button
## Which player's photo is being taken (-1 = none).
var _taking: int = -1
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := _label("TAKE YOUR PHOTOS", 48, Color.WHITE, true)
	title.position = Vector2(0, 30)
	title.size = Vector2(1280, 64)
	for i in 2:
		var cx := _panel_centre_x(i)
		var header := _label("PLAYER %d" % (i + 1), 30, _colour(i), true)
		header.position = Vector2(cx - 270, PANEL_Y + 20)
		header.size = Vector2(540, 40)
		var b := Button.new()
		b.name = "CameraButton%d" % (i + 1)
		b.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		b.size = b.custom_minimum_size
		b.position = Vector2(cx - BUTTON_SIZE * 0.5, PANEL_Y + 90)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, _round_style(i, state))
		var face := ButtonFace.new()
		face.screen = self
		face.player = i
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(face)
		b.pressed.connect(take_photo.bind(i))
		add_child(b)
		camera_buttons.append(b)
		var status := _label("", 22, Color(0.75, 0.78, 0.83), false)
		status.position = Vector2(cx - 270, PANEL_Y + 330)
		status.size = Vector2(540, 40)
		status_labels.append(status)
	play_button = _orange_button("PLAY", Vector2(540, 610), Vector2(200, 70), 34)
	play_button.name = "PlayButton"
	play_button.pressed.connect(start_match)
	var back := _orange_button("BACK", Vector2(30, 630), Vector2(180, 60), 26)
	back.name = "BackButton"
	back.pressed.connect(go_back)
	if not Webcam.supported():
		for i in 2:
			camera_buttons[i].disabled = true
	_refresh()


func _process(_delta: float) -> void:
	if _taking >= 0 and not webcam.is_busy():
		var i := _taking
		_taking = -1
		var img := webcam.take_image()
		if img != null:
			previews[i] = Webcam.make_circle(img, _colour(i), false)
			game_textures[i] = Webcam.make_circle(img, _colour(i), true)
			SoundFx.play("select")
		else:
			status_labels[i].text = "No camera found"
			_refresh(i)
			return
		_refresh()


## Click a camera button: take (or retake) that player's photo. One photo at a
## time, since only one program can use the camera at once.
func take_photo(i: int) -> void:
	if _leaving or _taking >= 0:
		return
	SoundFx.play("click")
	if not webcam.start("player%d.jpg" % (i + 1)):
		status_labels[i].text = "No camera found"
		return
	_taking = i
	_refresh()


func start_match() -> void:
	if _leaving or previews.has(null) or _taking >= 0:
		return
	SoundFx.play("click")
	_leaving = true
	var arena: Node = (load(ARENA) as PackedScene).instantiate()
	arena.difficulty = Difficulty.NORMAL
	arena.apply_player_kits(KITS)
	arena.apply_player_photos(game_textures)
	arena.apply_court(0)
	var tree := get_tree()
	tree.root.add_child(arena)
	tree.current_scene = arena
	queue_free()


func go_back() -> void:
	if _leaving:
		return
	SoundFx.play("back")
	_leaving = true
	get_tree().change_scene_to_file(MAIN_MENU)


## Update the status texts and buttons; `keep` = a player whose status text
## should be left as it is.
func _refresh(keep: int = -1) -> void:
	for i in 2:
		if i != keep:
			if not Webcam.supported():
				status_labels[i].text = "Camera needs Windows"
			elif _taking == i:
				status_labels[i].text = "Smile! Taking photo..."
			elif _taking >= 0:
				status_labels[i].text = "Wait for Player %d" % (_taking + 1)
			elif previews[i] == null:
				status_labels[i].text = "Click to take a photo"
			else:
				status_labels[i].text = "Click to retake"
		camera_buttons[i].queue_redraw()
	play_button.disabled = previews.has(null) or _taking >= 0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.078, 0.09))
	for i in 2:
		var r := Rect2(_panel_centre_x(i) - 270, PANEL_Y, 540, PANEL_H)
		draw_rect(r, Color(0.12, 0.125, 0.15))
		draw_rect(r, _colour(i), false, 3.0)


func _panel_centre_x(i: int) -> float:
	return 330.0 if i == 0 else 950.0


func _colour(i: int) -> Color:
	return CharacterLooks.kit_colour(KITS[i])


func _label(text: String, font_size: int, colour: Color, display: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if display:
		l.theme_type_variation = &"DisplayLabel"
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8 if display else 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _round_style(i: int, state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(int(BUTTON_SIZE * 0.5))
	s.corner_detail = 32
	s.anti_aliasing = true
	s.set_border_width_all(6)
	s.border_color = _colour(i)
	match state:
		"hover":
			s.bg_color = Color(0.24, 0.25, 0.29)
			s.border_color = _colour(i).lightened(0.3)
		"pressed":
			s.bg_color = Color(0.14, 0.15, 0.17)
		"focus":
			s.draw_center = false
			s.border_color = Color(1, 1, 1, 0.9)
			s.expand_margin_left = 6
			s.expand_margin_right = 6
			s.expand_margin_top = 6
			s.expand_margin_bottom = 6
			s.set_border_width_all(3)
		"disabled":
			s.bg_color = Color(0.16, 0.16, 0.18)
			s.border_color = Color(0.35, 0.35, 0.38)
		_:
			s.bg_color = Color(0.19, 0.2, 0.23)
	return s


## Orange button like the other menus' buttons (grey when disabled).
func _orange_button(text: String, pos: Vector2, button_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = button_size
	b.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.6, 0.62))
	var looks := {
		"normal": [Color(0.85, 0.38, 0.08), Color(0.55, 0.23, 0.04)],
		"hover": [Color(0.95, 0.47, 0.14), Color(0.55, 0.23, 0.04)],
		"pressed": [Color(0.7, 0.3, 0.05), Color(0.45, 0.18, 0.03)],
		"disabled": [Color(0.3, 0.3, 0.33), Color(0.2, 0.2, 0.22)],
	}
	for state in looks:
		var s := StyleBoxFlat.new()
		s.bg_color = looks[state][0]
		s.border_color = looks[state][1]
		if state == "pressed":
			s.border_width_top = 4
		else:
			s.border_width_bottom = 6
		s.set_corner_radius_all(14)
		b.add_theme_stylebox_override(state, s)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = Color(1, 1, 1, 0.9)
	focus.set_corner_radius_all(16)
	focus.set_expand_margin_all(5)
	b.add_theme_stylebox_override("focus", focus)
	add_child(b)
	return b


## What's drawn inside a round camera button: the player's photo once taken,
## otherwise a camera icon.
class ButtonFace extends Control:
	var screen: Node
	var player: int = 0

	func _draw() -> void:
		var c := size * 0.5
		var photo: Texture2D = screen.previews[player]
		if photo != null:
			var d := size.x - 12.0
			draw_texture_rect(photo, Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), false)
			return
		var col := Color(0.92, 0.93, 0.95)
		if (get_parent() as Button).disabled:
			col = Color(0.45, 0.45, 0.48)
		var body := Rect2(c + Vector2(-50, -28), Vector2(100, 66))
		draw_rect(Rect2(c + Vector2(-18, -40), Vector2(36, 14)), col) # viewfinder bump
		draw_style_box(_rounded(col), body)
		draw_circle(c + Vector2(0, 5), 22.0, Color(0.19, 0.2, 0.23))
		draw_circle(c + Vector2(0, 5), 14.0, col)
		draw_circle(c + Vector2(32, -16), 4.0, Color(0.19, 0.2, 0.23)) # flash

	func _rounded(col: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(10)
		return s
