class_name CharacterSelect
extends Node2D
## Character select: each player picks a kit colour on a rotating wheel, then
## readies up; the court is picked in the shared box underneath. When both are
## ready the arena starts with their kits on that court.
##
## Player 1: A / D rotate, E ready (press again to change).
## Player 2: Left / Right rotate, Period ready.
## Court: W / S or Up / Down (either player, while not ready).
## The two players can't have the same colour: rotating skips the colour the
## other player currently has.

const ARENA_SCENE := preload("res://dodgeball/arena.tscn")
const DIFFICULTY_SELECT := "res://dodgeball/difficulty_select.tscn"

## Set by the main menu before opening this screen. In single player the
## Player 2 panel is the bot: it is always ready and ignores the P2 keys.
static var single_player: bool = false
## Set by the difficulty screen; passed on to the arena.
static var difficulty: int = Difficulty.NORMAL

## Seconds between both players being ready and the match starting.
@export var start_delay: float = 1.0

# Layout (1280 x 720 viewport).
const PANEL_W := 540.0
const PANEL_H := 450.0
const PANEL_Y := 110.0
const PANEL_X := [60.0, 680.0]
const HEADER_Y := 146.0
const COLOUR_LABEL_Y := 186.0
const COLOUR_WHEEL_Y := 282.0
const KIT_NAME_Y := 372.0
const HINT_Y := 536.0
const COURT_BOX := Rect2(440, 578, 400, 92)
const COLOUR_WHEEL_RX := 175.0
const FRONT_SPRITE_SCALE := 4.6
const BACK_SPRITE_SCALE := 2.0

var players: Array[Dictionary] = []
var _start_timer: float = -1.0
## Index into CourtFloor.COURTS.
var court: int = 0
var _court_tiles: Array[Texture2D] = []


func _ready() -> void:
	players = [
		_new_player(1, "p1_", 0, _select_hint(1)),
		_new_player(2, "p2_", 1, _select_hint(2)),
	]
	if single_player:
		players[1]["bot"] = true
		players[1]["ready"] = true
		players[1]["hint"] = "Computer player"
	# Characters are drawn from high-resolution renders of the pack's vector
	# art and scaled down, so smooth (mipmapped) filtering looks best.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for c in CourtFloor.court_count():
		_court_tiles.append(CourtFloor.court_tile(c))
	# Back (mouse only, so the players' keys can't press it by accident).
	%BackButton.pressed.connect(go_back)
	queue_redraw()


## Back to the difficulty screen (same mode).
func go_back() -> void:
	SoundFx.play("back")
	set_process(false)
	get_tree().change_scene_to_file(DIFFICULTY_SELECT)


func _new_player(id: int, prefix: String, kit: int, hint: String) -> Dictionary:
	return {
		"id": id, "prefix": prefix, "hint": hint, "kit": kit, "ready": false,
		"kit_shown": float(kit), # smoothly animated wheel position
	}


func _process(delta: float) -> void:
	for i in players.size():
		_handle_input(i)
		_animate(players[i], delta)

	var all_ready := players.all(func(p): return p["ready"])
	if all_ready:
		if _start_timer < 0.0:
			_start_timer = start_delay
		_start_timer -= delta
		if _start_timer <= 0.0:
			_start_game()
			return
	else:
		_start_timer = -1.0
	queue_redraw()


func _handle_input(i: int) -> void:
	var p := players[i]
	if p.get("bot", false):
		return # the bot keeps its colour and is always ready
	var pre: String = p["prefix"]
	if Input.is_action_just_pressed(pre + "throw"):
		p["ready"] = not p["ready"]
		SoundFx.play("select")
	if p["ready"]:
		return
	if Input.is_action_just_pressed(pre + "up"):
		court = wrapi(court - 1, 0, CourtFloor.court_count())
		SoundFx.play("switch")
	if Input.is_action_just_pressed(pre + "down"):
		court = wrapi(court + 1, 0, CourtFloor.court_count())
		SoundFx.play("switch")
	var dir := 0
	if Input.is_action_just_pressed(pre + "left"):
		dir -= 1
	if Input.is_action_just_pressed(pre + "right"):
		dir += 1
	if dir != 0:
		rotate_choice(i, dir)


## Turn player i's colour wheel one step (dir = -1 or 1), skipping the other
## player's colour.
func rotate_choice(i: int, dir: int) -> void:
	SoundFx.play("switch")
	var p := players[i]
	var taken: int = players[1 - i]["kit"]
	var kit := wrapi(p["kit"] + dir, 0, CharacterLooks.kit_count())
	if kit == taken:
		kit = wrapi(kit + dir, 0, CharacterLooks.kit_count())
	p["kit"] = kit


func _animate(p: Dictionary, delta: float) -> void:
	var k := 1.0 - exp(-12.0 * delta)
	p["kit_shown"] = _approach_wrapped(p["kit_shown"], p["kit"], CharacterLooks.kit_count(), k)


## Move `shown` toward `target` the short way round a wheel of n items.
func _approach_wrapped(shown: float, target: int, n: int, k: float) -> float:
	var diff := fposmod(float(target) - shown + n * 0.5, float(n)) - n * 0.5
	if absf(diff) < 0.001:
		return float(target)
	return fposmod(shown + diff * k, float(n))


func _start_game() -> void:
	var arena := ARENA_SCENE.instantiate()
	var kits: Array[int] = []
	for p in players:
		kits.append(p["kit"])
	arena.apply_player_kits(kits)
	arena.apply_court(court)
	arena.single_player = single_player
	arena.difficulty = difficulty
	var tree := get_tree()
	tree.root.add_child(arena)
	tree.current_scene = arena
	queue_free()


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	_text("CHOOSE YOUR PLAYER", Vector2(640, 62), 40, Color.WHITE, true)
	for i in players.size():
		_draw_panel(i)
	_draw_court_picker()
	if _start_timer >= 0.0:
		_text("GET READY!", Vector2(640, 690), 30, Color(1, 0.9, 0.4), true)


func _draw_panel(i: int) -> void:
	var p := players[i]
	var x0: float = PANEL_X[i]
	var rect := Rect2(x0, PANEL_Y, PANEL_W, PANEL_H)
	var cx := rect.get_center().x
	var kit_col := CharacterLooks.kit_colour(p["kit"])

	draw_rect(rect, Color(0.12, 0.13, 0.16))
	draw_rect(rect, kit_col, false, 3.0)
	var header := "BOT" if p.get("bot", false) else "PLAYER %d" % p["id"]
	_text(header, Vector2(cx, HEADER_Y), 26, kit_col, true)

	# Colour wheel
	var colour_active: bool = not p["ready"]
	_row_label("COLOUR", Vector2(x0 + 24, COLOUR_LABEL_Y), colour_active)
	_draw_colour_wheel(i, Vector2(cx, COLOUR_WHEEL_Y))
	_text(CharacterLooks.kit_name(p["kit"]), Vector2(cx, KIT_NAME_Y), 26, Color.WHITE, true)
	if colour_active:
		_arrows(Vector2(cx, COLOUR_WHEEL_Y), 205.0, kit_col)

	_text(p["hint"], Vector2(cx, HINT_Y), 15, Color(0.6, 0.63, 0.68), true)

	if p["ready"]:
		draw_rect(rect, Color(0, 0, 0, 0.45))
		_text("READY!", Vector2(cx, PANEL_Y + PANEL_H * 0.5), 64, kit_col, true)
		var key := ControlScheme.label(p["id"], "throw")
		var note := "computer player" if p.get("bot", false) else "press %s to change" % key
		_text(note, Vector2(cx, PANEL_Y + PANEL_H * 0.5 + 44), 18,
				Color(0.85, 0.85, 0.85), true)


## Shared court box: floor swatch + name, with arrows (W / S or Up / Down).
func _draw_court_picker() -> void:
	var box := COURT_BOX
	draw_rect(box, Color(0.12, 0.13, 0.16))
	draw_rect(box, Color(0.6, 0.63, 0.68), false, 2.0)
	_text("COURT", Vector2(box.position.x + 16, box.position.y + 16), 15, Color(0.6, 0.63, 0.68), false)
	var centre := Vector2(box.get_center().x, box.position.y + 46)
	# Swatch + name centred together between the arrows.
	var court_name := CourtFloor.court_name(court)
	var name_w := _font_for(24).get_string_size(court_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var left := centre.x - (40.0 + 10.0 + name_w) * 0.5
	var swatch := Rect2(Vector2(left, centre.y - 20), Vector2(40, 40))
	draw_texture_rect(_court_tiles[court], swatch, false)
	draw_rect(swatch, Color(0, 0, 0, 0.6), false, 2.0)
	_text(court_name, Vector2(left + 50.0, centre.y), 24, Color.WHITE, false)
	var any_choosing := players.any(func(p): return not p["ready"])
	if any_choosing:
		for side in [-1.0, 1.0]:
			var base := centre + Vector2(side * 150.0, 0)
			var tip := base + Vector2(side * 20.0, 0)
			draw_colored_polygon(PackedVector2Array([
				tip, base + Vector2(0, -11), base + Vector2(0, 11)]), Color(0.85, 0.85, 0.85))
	var keys := "%s  or  %s" % [ControlScheme.label(1, "up_down"), ControlScheme.label(2, "up_down")]
	_text(keys, Vector2(box.get_center().x, box.end.y - 13), 13, Color(0.6, 0.63, 0.68), true)


## Characters on a turning ring: front = selected, back ones smaller/fainter.
func _draw_colour_wheel(i: int, centre: Vector2) -> void:
	var p := players[i]
	var n := CharacterLooks.kit_count()
	var taken: int = players[1 - i]["kit"]
	var items := []
	for k in n:
		var w := _wheel_point(k, p["kit_shown"], n, centre, COLOUR_WHEEL_RX)
		w["kit"] = k
		items.append(w)
	items.sort_custom(func(a, b): return a["depth"] < b["depth"])
	for it in items:
		var s := lerpf(BACK_SPRITE_SCALE, FRONT_SPRITE_SCALE, it["front"])
		var alpha := lerpf(0.35, 1.0, it["front"])
		if it["kit"] == taken:
			alpha *= 0.35 # the other player's colour: shown, but skipped
		# High-res vector render, scaled so it shows at the same size the 21 x 31
		# sprite would at scale s.
		var tex := CharacterLooks.hd_texture(it["kit"])
		var sprite_size := CharacterLooks.texture(it["kit"]).get_size()
		var k := s * sprite_size.y / tex.get_size().y
		# Sprites face right; turn them to face up so the shirt reads clearly.
		draw_set_transform(it["pos"], -PI * 0.5, Vector2(k, k))
		draw_texture(tex, -tex.get_size() * 0.5, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO)


## Position of item k on a horizontal ring whose front shows item `shown`.
func _wheel_point(k: int, shown: float, n: int, centre: Vector2, rx: float) -> Dictionary:
	var offset := fposmod(float(k) - shown + n * 0.5, float(n)) - n * 0.5
	var angle := offset * TAU / n
	var depth := cos(angle) # 1 = front, -1 = back
	var front := (depth + 1.0) * 0.5
	var pos := centre + Vector2(sin(angle) * rx, -(1.0 - front) * 26.0)
	return {"pos": pos, "depth": depth, "front": front}


func _row_label(label: String, pos: Vector2, active: bool) -> void:
	var col := Color.WHITE if active else Color(0.5, 0.52, 0.56)
	_text(label, pos, 18, col, false)


## Small triangles either side of the front item of the wheel.
func _arrows(centre: Vector2, gap: float, col: Color) -> void:
	for side in [-1.0, 1.0]:
		var tip := centre + Vector2(side * (gap + 26.0), 0)
		var base := centre + Vector2(side * gap, 0)
		draw_colored_polygon(PackedVector2Array([
			tip, base + Vector2(0, -14), base + Vector2(0, 14)]), col)


## Big text (24+) in the chunky display font, small text in the body font.
func _font_for(size: int) -> Font:
	return GameFonts.DISPLAY if size >= 24 else GameFonts.BODY


func _text(s: String, pos: Vector2, size: int, col: Color, centred: bool) -> void:
	var font := _font_for(size)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(pos.x - w * 0.5 if centred else pos.x, pos.y + size * 0.35)
	draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## "A / D  rotate     C  ready" for a player, in the current control preset.
func _select_hint(player: int) -> String:
	return "%s  rotate     %s  ready" % [ControlScheme.label(player, "left_right"),
			ControlScheme.label(player, "throw")]
