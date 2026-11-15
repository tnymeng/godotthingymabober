class_name CourtFloor
extends Node2D
## Court floor under the arena: the plain tile of one of the Kenney Sports
## Pack's floor sheets repeated across the play area, with a centre line and
## centre circle in that sheet's court-line colour. Drawn below everything else.

const SHEET_DIR := "res://assets/kenney_sports/Tilesheet/"

## Themed maps that can be picked on the select screen.
##  - "sheet" / "lines": floor sheet and its court-line colour (white
##    everywhere except Frozen Kingdom, which uses the ice sheet's blue lines).
##  - "speed": top speed multiplier (Meadow Mayhem is slower).
##  - "accel" / "brake": how quickly players speed up / stop. Low = sliding.
##  - "border": tile for the arena border
##    (Kenney Sokoban and Racing packs, CC0).
const COURTS: Array[Dictionary] = [
	{"name": "Hardwood Hall", "sheet": "groundBeige_white", "lines": Color(1, 1, 1, 0.9),
		"speed": 1.0, "accel": 1.0, "brake": 1.0,
		"border": "res://assets/kenney_sokoban/PNG/Default size/Blocks/block_04.png"},
	{"name": "Meadow Mayhem", "sheet": "groundGrass", "lines": Color(1, 1, 1, 0.9),
		"speed": 0.8, "accel": 1.0, "brake": 1.0,
		"border": "res://assets/kenney_sokoban/PNG/Default size/Blocks/block_03.png"},
	{"name": "Sunbaked Canyon", "sheet": "groundGravel", "lines": Color(1, 1, 1, 0.9),
		"speed": 1.0, "accel": 1.0, "brake": 1.0,
		"border": "res://assets/kenney_sokoban/PNG/Default size/Blocks/block_06.png"},
	{"name": "Frozen Kingdom", "sheet": "groundIce_blue", "lines": Color(0.255, 0.624, 0.867, 0.9),
		"speed": 1.0, "accel": 0.3, "brake": 0.15,
		"border": "res://assets/kenney_racing/PNG/Objects/barrier_white.png"},
]

## Border art is drawn this much thicker on the outside of the arena.
const BORDER_EXTRA := 12.0

## Play area plus the outer walls, so the outer walls sit on the court.
@export var area: Rect2 = Rect2(40, 70, 1200, 640)
@export var floor_texture: Texture2D = preload("res://assets/kenney_sports/Tilesheet/groundBeige_white.png")
## The plain (line-free) tile in the sheet.
@export var tile_region: Rect2i = Rect2i(0, 0, 64, 64)
## Multiplies the floor colour (e.g. darken it to make white effects stand out).
@export var tint: Color = Color(1, 1, 1, 1)
@export var draw_markings: bool = true
@export var marking_color: Color = Color(1, 1, 1, 0.9)
@export var marking_width: float = 3.0
@export var centre_circle_radius: float = 90.0

var _tile: Texture2D


static func court_count() -> int:
	return COURTS.size()


static func court_name(court: int) -> String:
	return COURTS[wrapi(court, 0, COURTS.size())]["name"]


## The plain floor tile of a court as a texture (for previews).
static func court_tile(court: int) -> Texture2D:
	var sheet := load(SHEET_DIR + COURTS[wrapi(court, 0, COURTS.size())]["sheet"] + ".png") as Texture2D
	return ImageTexture.create_from_image(sheet.get_image().get_region(Rect2i(0, 0, 64, 64)))


## Switch to one of COURTS. Call before the node is ready (or call
## queue_redraw() after).
func use_court(court: int) -> void:
	var c: Dictionary = COURTS[wrapi(court, 0, COURTS.size())]
	floor_texture = load(SHEET_DIR + c["sheet"] + ".png") as Texture2D
	marking_color = c["lines"]
	if is_inside_tree():
		_build_tile()
		queue_redraw()


func _ready() -> void:
	z_index = -10 # under the hold zone (-1), walls, players and ball
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_build_tile()
	queue_redraw()


## The plain floor colour of the current court.
func floor_colour() -> Color:
	if _tile != null:
		return _tile.get_image().get_pixel(0, 0)
	return Color(0.85, 0.8, 0.64)


func _build_tile() -> void:
	_tile = null
	if floor_texture != null:
		var image := floor_texture.get_image()
		if image != null:
			_tile = ImageTexture.create_from_image(image.get_region(tile_region))


func _draw() -> void:
	if _tile != null:
		draw_texture_rect(_tile, area, true, tint)
	else:
		draw_rect(area, Color(0.85, 0.8, 0.64) * tint)
	if draw_markings:
		var centre := area.get_center()
		draw_line(Vector2(centre.x, area.position.y), Vector2(centre.x, area.end.y),
				marking_color, marking_width)
		draw_arc(centre, centre_circle_radius, 0.0, TAU, 96, marking_color, marking_width, true)
