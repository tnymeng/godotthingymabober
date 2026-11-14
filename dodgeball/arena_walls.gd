@tool
extends StaticBody2D
## Draws every RectangleShape2D child exactly where its collision shape is,
## so the visible walls always match the physical walls. Edit the wall shapes
## in the scene and the drawing follows.

@export var wall_color: Color = Color(0.78, 0.8, 0.84):
	set(value):
		wall_color = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	for child in get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null:
			continue
		var rect_shape := shape_node.shape as RectangleShape2D
		if rect_shape == null:
			continue
		var size := rect_shape.size
		draw_rect(Rect2(shape_node.position - size * 0.5, size), wall_color)
