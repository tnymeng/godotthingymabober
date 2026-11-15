@tool
extends StaticBody2D
## Draws every RectangleShape2D child exactly where its collision shape is,
## so the visible walls always match the physical walls. Edit the wall shapes
## in the scene and the drawing follows.
##
## Default look: the Kenney Sports Pack grey padded barrier, repeated along
## each wall and scaled to its thickness. A map theme can set theme_texture
## instead (crates, bricks, sandbags, barriers...): one tile, drawn for
## horizontal walls and turned 90 degrees for vertical ones. For the arena
## border, outward_extra draws the art thicker on the OUTSIDE only, so it looks
## sturdier without changing where players and the ball stop.

@export var wall_color: Color = Color(0.78, 0.8, 0.84):
	set(value):
		wall_color = value
		queue_redraw()

@export_group("Wall art")
## Tile used for walls wider than tall, and the part of it with the wall art.
@export var horizontal_texture: Texture2D = preload("res://assets/kenney_sports/PNG/Elements/element (17).png"):
	set(value):
		horizontal_texture = value
		queue_redraw()
@export var horizontal_region: Rect2 = Rect2(0, 19, 64, 26)
## Tile used for walls taller than wide, and the part of it with the wall art.
@export var vertical_texture: Texture2D = preload("res://assets/kenney_sports/PNG/Elements/element (16).png"):
	set(value):
		vertical_texture = value
		queue_redraw()
@export var vertical_region: Rect2 = Rect2(19, 0, 26, 64)

@export_group("Theme art")
## When set, replaces the wall art above: drawn along horizontal walls and
## rotated 90 degrees for vertical ones.
@export var theme_texture: Texture2D = null:
	set(value):
		theme_texture = value
		queue_redraw()
## Part of theme_texture to use (zero size = the whole image).
@export var theme_region: Rect2 = Rect2()
## Extra thickness (px) drawn on the side facing away from outward_center.
@export var outward_extra: float = 0.0
@export var outward_center: Vector2 = Vector2(640, 390)


func _ready() -> void:
	queue_redraw()


## Switch to a theme tile (call before or after entering the tree).
func use_theme_tile(texture: Texture2D, region: Rect2 = Rect2(), extra: float = 0.0) -> void:
	theme_region = region
	outward_extra = extra
	theme_texture = texture


func _draw() -> void:
	for child in get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null:
			continue
		var rect_shape := shape_node.shape as RectangleShape2D
		if rect_shape == null:
			continue
		var size := rect_shape.size
		var rect := Rect2(shape_node.position - size * 0.5, size)
		if theme_texture != null:
			_draw_theme_wall(rect)
		else:
			_draw_wall(rect)


func _draw_wall(rect: Rect2) -> void:
	var horizontal := rect.size.x >= rect.size.y
	var texture := horizontal_texture if horizontal else vertical_texture
	if texture == null:
		draw_rect(rect, wall_color)
		return
	var region := horizontal_region if horizontal else vertical_region

	# Repeat the tile along the wall. The tile is scaled so its thickness
	# matches the wall's; the last piece is cropped to fit.
	if horizontal:
		var tile_scale := rect.size.y / region.size.y
		var step := region.size.x * tile_scale
		var x := rect.position.x
		while x < rect.end.x - 0.01:
			var w := minf(step, rect.end.x - x)
			var src := Rect2(region.position, Vector2(w / tile_scale, region.size.y))
			draw_texture_rect_region(texture, Rect2(x, rect.position.y, w, rect.size.y), src)
			x += w
	else:
		var tile_scale := rect.size.x / region.size.x
		var step := region.size.y * tile_scale
		var y := rect.position.y
		while y < rect.end.y - 0.01:
			var h := minf(step, rect.end.y - y)
			var src := Rect2(region.position, Vector2(region.size.x, h / tile_scale))
			draw_texture_rect_region(texture, Rect2(rect.position.x, y, rect.size.x, h), src)
			y += h


func _draw_theme_wall(rect: Rect2) -> void:
	var horizontal := rect.size.x >= rect.size.y
	# Border pieces: grow on the side away from the arena centre.
	if outward_extra > 0.0:
		if horizontal:
			if rect.get_center().y < outward_center.y:
				rect = Rect2(rect.position - Vector2(0, outward_extra), rect.size + Vector2(0, outward_extra))
			else:
				rect = Rect2(rect.position, rect.size + Vector2(0, outward_extra))
		else:
			if rect.get_center().x < outward_center.x:
				rect = Rect2(rect.position - Vector2(outward_extra, 0), rect.size + Vector2(outward_extra, 0))
			else:
				rect = Rect2(rect.position, rect.size + Vector2(outward_extra, 0))
	var region := theme_region
	if region.size == Vector2.ZERO:
		region = Rect2(Vector2.ZERO, theme_texture.get_size())
	if horizontal:
		draw_set_transform(rect.position, 0.0, Vector2.ONE)
		_draw_strip(rect.size.x, rect.size.y, region)
	else:
		# Rotated 90 degrees: the strip's length runs down the wall.
		draw_set_transform(rect.position + Vector2(rect.size.x, 0), PI * 0.5, Vector2.ONE)
		_draw_strip(rect.size.y, rect.size.x, region)
	draw_set_transform(Vector2.ZERO)


## Repeat the theme tile along a strip `length` long and `thickness` thick
## (in the current transform); the last tile is cropped to fit.
func _draw_strip(length: float, thickness: float, region: Rect2) -> void:
	var tile_scale := thickness / region.size.y
	var step := region.size.x * tile_scale
	var x := 0.0
	while x < length - 0.01:
		var w := minf(step, length - x)
		var src := Rect2(region.position, Vector2(w / tile_scale, region.size.y))
		draw_texture_rect_region(theme_texture, Rect2(x, 0, w, thickness), src)
		x += w
