class_name CharacterLooks
extends RefCounted
## Player kits from the Kenney Sports Pack: the pack's single-colour,
## plain-shirt characters.
##
## texture() is the small in-game sprite (PNG). hd_texture() renders the same
## character from the pack's vector sheet (Vector/charactersEquipment.svg) at a
## high resolution, so it can be shown big with its original colours and
## details instead of as blocky, scaled-up pixels.

const PNG_DIR := "res://assets/kenney_sports/PNG/"

const KITS: Array[Dictionary] = [
	{"name": "Blue", "path": "Blue/characterBlue (1).png", "svg_y": 210.0},
	{"name": "Orange", "path": "Red/characterRed (1).png", "svg_y": 170.0},
	{"name": "Green", "path": "Green/characterGreen (1).png", "svg_y": 250.0},
	{"name": "White", "path": "White/characterWhite (1).png", "svg_y": 290.0},
	{"name": "Yellow", "path": "Special/characterSpecial (1).png", "svg_y": 350.0},
]

## A shirt pixel in every kit (used as the player's colour in the game).
const KIT_COLOUR_PIXEL := Vector2i(10, 2)

const VECTOR_SHEET := "res://assets/kenney_sports/Vector/charactersEquipment.svg"
## In the vector sheet, variant 1 of every kit is centred at x = 40 (1x units);
## each kit's row centre is its "svg_y". This box around it holds one character.
const SVG_CHARACTER_X := 40.0
const SVG_BOX := Vector2(30, 40)
## Render scale of hd_texture() (1 = the 21 x 31 px PNG size).
const HD_SCALE := 8.0

static var _cache: Dictionary = {}
static var _hd_cache: Dictionary = {}
static var _svg_text: String = ""


static func kit_count() -> int:
	return KITS.size()


static func kit_name(kit: int) -> String:
	return KITS[wrapi(kit, 0, KITS.size())]["name"]


static func kit_colour(kit: int) -> Color:
	var img := _load(KITS[wrapi(kit, 0, KITS.size())]["path"])
	var c := img.get_pixelv(KIT_COLOUR_PIXEL)
	c.a = 1.0
	return c


## The character texture for a kit (cached).
static func texture(kit: int) -> Texture2D:
	kit = wrapi(kit, 0, KITS.size())
	if _cache.has(kit):
		return _cache[kit]
	var tex := ImageTexture.create_from_image(_load(KITS[kit]["path"]))
	_cache[kit] = tex
	return tex


## The kit's character rendered from the vector sheet at HD_SCALE (cached),
## cropped to the character. Faces right, like the PNG sprite.
static func hd_texture(kit: int) -> Texture2D:
	kit = wrapi(kit, 0, KITS.size())
	if _hd_cache.has(kit):
		return _hd_cache[kit]
	if _svg_text.is_empty():
		_svg_text = FileAccess.get_file_as_string(VECTOR_SHEET)
	# Render only the box around this character by narrowing the viewBox.
	var centre := Vector2(SVG_CHARACTER_X, KITS[kit]["svg_y"])
	var box := Rect2(centre - SVG_BOX * 0.5, SVG_BOX)
	var svg := _svg_text.replace(
			'width="550px" height="400px" viewBox="0 0 550 400"',
			'width="%spx" height="%spx" viewBox="%s %s %s %s"' % [
				box.size.x, box.size.y, box.position.x, box.position.y, box.size.x, box.size.y])
	var img := Image.new()
	if img.load_svg_from_string(svg, HD_SCALE) != OK:
		return texture(kit) # fall back to the PNG sprite
	img = img.get_region(img.get_used_rect())
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_hd_cache[kit] = tex
	return tex


static func _load(rel_path: String) -> Image:
	var tex := load(PNG_DIR + rel_path) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img
