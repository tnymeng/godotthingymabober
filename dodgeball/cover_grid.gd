class_name CoverGrid
extends "res://dodgeball/arena_walls.gd"
## Random cover walls on a grid inside the arena.
##
## The floor is split into columns x rows cells. Cover walls may only sit on
## the lines between two neighbouring cells (one wall = one cell edge), so
## pieces always meet cleanly at grid corners and form straight runs, L's and
## T's. Every wall is mirrored through the arena centre (180 degree turn), so
## both spawn points face the same layout.
##
## No dead ends: think of the cells as rooms and the open edges as doorways.
## After every placement the layout must still be "2-edge-connected": every
## room is reachable, and no single doorway is the only way into any part of
## the arena. So there are no cul-de-sacs, closed rooms or one-entrance
## pockets; a placement that would create one is rejected. Every doorway is
## at least (cell size - wall_thickness) wide, which fits a player easily.
##
## The same cell graph is used by the ball to find its way back around cover
## (see steer_target()).

## Area covered by the grid. Matches the inside of the arena's outer walls.
@export var area: Rect2 = Rect2(60, 90, 1160, 600)
@export var columns: int = 10
@export var rows: int = 5
@export var wall_thickness: float = 16.0
## How many mirrored pairs of wall pieces to try to place (picked at random
## between min and max; fewer if the no-dead-end rule rejects too many).
@export var min_wall_pairs: int = 7
@export var max_wall_pairs: int = 10
## Chance that a new piece is attached to an existing piece (longer, joined-up
## walls) instead of placed anywhere.
@export_range(0.0, 1.0) var connect_bias: float = 0.7
## Walls are kept at least this far from spawn points (beyond player radius).
@export var spawn_clearance: float = 40.0

const VERTICAL := 0   # edge between cell (c, r) and (c + 1, r)
const HORIZONTAL := 1 # edge between cell (c, r) and (c, r + 1)

## Placed walls, keyed by Vector3i(kind, c, r).
var walls: Dictionary = {}

var _cell_size: Vector2


func _ready() -> void:
	_cell_size = Vector2(area.size.x / columns, area.size.y / rows)
	super._ready()


## Build a new random layout. spawn_points are kept clear (with player_radius
## plus spawn_clearance around them). seed_value 0 = random.
func generate(seed_value: int, spawn_points: Array[Vector2], player_radius: float) -> void:
	_cell_size = Vector2(area.size.x / columns, area.size.y / rows)
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	walls.clear()
	var candidates: Array[Vector3i] = []
	for e in _all_edges():
		if not _edge_blocks_spawn(e, spawn_points, player_radius + spawn_clearance):
			candidates.append(e)

	var target := rng.randi_range(min_wall_pairs, max_wall_pairs)
	var pairs := 0
	var attempts := 0
	while pairs < target and attempts < 500:
		attempts += 1
		var edge := _pick_candidate(rng, candidates)
		if edge == Vector3i(-1, -1, -1):
			break
		var pair: Array[Vector3i] = [edge]
		var mirrored := _mirror(edge)
		if mirrored != edge:
			if not candidates.has(mirrored) or walls.has(mirrored):
				continue
			pair.append(mirrored)
		for e in pair:
			walls[e] = true
		if _is_dead_end_free():
			pairs += 1
		else:
			for e in pair:
				walls.erase(e)

	_build_wall_shapes()


# --- Grid helpers -----------------------------------------------------------

func _all_edges() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for r in rows:
		for c in columns - 1:
			out.append(Vector3i(VERTICAL, c, r))
	for r in rows - 1:
		for c in columns:
			out.append(Vector3i(HORIZONTAL, c, r))
	return out


## Same edge after a 180 degree turn around the arena centre.
func _mirror(e: Vector3i) -> Vector3i:
	if e.x == VERTICAL:
		return Vector3i(VERTICAL, columns - 2 - e.y, rows - 1 - e.z)
	return Vector3i(HORIZONTAL, columns - 1 - e.y, rows - 2 - e.z)


## The two grid corners an edge runs between.
func _edge_nodes(e: Vector3i) -> Array[Vector2i]:
	if e.x == VERTICAL:
		return [Vector2i(e.y + 1, e.z), Vector2i(e.y + 1, e.z + 1)]
	return [Vector2i(e.y, e.z + 1), Vector2i(e.y + 1, e.z + 1)]


## Collision rectangle of a wall piece. Pieces are stretched by half the
## thickness at both ends so neighbours overlap into clean square joints.
func edge_rect(e: Vector3i) -> Rect2:
	var t := wall_thickness
	if e.x == VERTICAL:
		var x := area.position.x + _cell_size.x * (e.y + 1)
		var y0 := area.position.y + _cell_size.y * e.z
		return Rect2(x - t * 0.5, y0 - t * 0.5, t, _cell_size.y + t)
	var y := area.position.y + _cell_size.y * (e.z + 1)
	var x0 := area.position.x + _cell_size.x * e.y
	return Rect2(x0 - t * 0.5, y - t * 0.5, _cell_size.x + t, t)


func _edge_blocks_spawn(e: Vector3i, spawns: Array[Vector2], clearance: float) -> bool:
	var grown := edge_rect(e).grow(clearance)
	for p in spawns:
		if grown.has_point(p):
			return true
	return false


func _pick_candidate(rng: RandomNumberGenerator, candidates: Array[Vector3i]) -> Vector3i:
	var free: Array[Vector3i] = []
	for e in candidates:
		if not walls.has(e):
			free.append(e)
	if free.is_empty():
		return Vector3i(-1, -1, -1)
	if not walls.is_empty() and rng.randf() < connect_bias:
		# Prefer pieces that share a grid corner with an existing piece.
		var used_nodes := {}
		for w in walls:
			for n in _edge_nodes(w):
				used_nodes[n] = true
		var touching: Array[Vector3i] = []
		for e in free:
			for n in _edge_nodes(e):
				if used_nodes.has(n):
					touching.append(e)
					break
		if not touching.is_empty():
			return touching[rng.randi() % touching.size()]
	return free[rng.randi() % free.size()]


# --- Dead-end check (cells = rooms, open edges = doorways) ------------------

func cell_id(cell: Vector2i) -> int:
	return cell.y * columns + cell.x


func is_open(a: Vector2i, b: Vector2i) -> bool:
	if a.y == b.y:
		return not walls.has(Vector3i(VERTICAL, mini(a.x, b.x), a.y))
	return not walls.has(Vector3i(HORIZONTAL, a.x, mini(a.y, b.y)))


func open_neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: Vector2i = cell + d
		if n.x < 0 or n.y < 0 or n.x >= columns or n.y >= rows:
			continue
		if is_open(cell, n):
			out.append(n)
	return out


## True when every cell is reachable and no doorway is a bridge (the only
## link to some part of the arena). That also means every cell has at least
## two ways out, so nothing is a dead end.
func _is_dead_end_free() -> bool:
	var count := columns * rows
	var disc: Array[int] = []
	var low: Array[int] = []
	disc.resize(count)
	low.resize(count)
	disc.fill(-1)
	var timer := [0]
	var has_bridge := [false]
	_bridge_dfs(Vector2i.ZERO, Vector2i(-1, -1), disc, low, timer, has_bridge)
	if has_bridge[0]:
		return false
	for i in count:
		if disc[i] == -1:
			return false # some cell can't be reached
	return true


func _bridge_dfs(cell: Vector2i, parent: Vector2i, disc: Array[int], low: Array[int],
		timer: Array, has_bridge: Array) -> void:
	var id := cell_id(cell)
	disc[id] = timer[0]
	low[id] = timer[0]
	timer[0] += 1
	for n in open_neighbours(cell):
		if n == parent:
			continue
		var nid := cell_id(n)
		if disc[nid] == -1:
			_bridge_dfs(n, cell, disc, low, timer, has_bridge)
			low[id] = mini(low[id], low[nid])
			if low[nid] > disc[id]:
				has_bridge[0] = true
		else:
			low[id] = mini(low[id], disc[nid])


# --- Shapes -----------------------------------------------------------------

func _build_wall_shapes() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			remove_child(child)
			child.queue_free()
	for e in walls:
		var rect := edge_rect(e)
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var node := CollisionShape2D.new()
		node.shape = shape
		node.position = rect.get_center()
		add_child(node)
	queue_redraw()


# --- Navigation for the returning ball --------------------------------------

func cell_of(p: Vector2) -> Vector2i:
	var local := (p - area.position) / _cell_size
	return Vector2i(clampi(floori(local.x), 0, columns - 1), clampi(floori(local.y), 0, rows - 1))


func cell_center(cell: Vector2i) -> Vector2:
	return area.position + (Vector2(cell) + Vector2(0.5, 0.5)) * _cell_size


## Shortest route of cells from a to b through open edges (BFS), including both.
func find_cell_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var came_from := {a: a}
	var queue: Array[Vector2i] = [a]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == b:
			break
		for n in open_neighbours(cur):
			if not came_from.has(n):
				came_from[n] = cur
				queue.append(n)
	var path: Array[Vector2i] = []
	if not came_from.has(b):
		return path
	var step := b
	while step != a:
		path.push_front(step)
		step = came_from[step]
	path.push_front(a)
	return path


## Where something of the given radius at `from` should head to reach `to`.
## Straight at `to` if nothing is in the way; otherwise at the furthest cell
## centre along the grid route that it can see (so it rounds corners).
func steer_target(from: Vector2, to: Vector2, radius: float, exclude: Array[RID]) -> Vector2:
	if walls.is_empty() or _clear_line(from, to, radius, exclude):
		return to
	var path := find_cell_path(cell_of(from), cell_of(to))
	if path.size() < 2:
		return to
	for i in range(path.size() - 1, 0, -1):
		var p := cell_center(path[i])
		if _clear_line(from, p, radius, exclude):
			return p
	return cell_center(path[1])


func _clear_line(from: Vector2, to: Vector2, radius: float, exclude: Array[RID]) -> bool:
	var motion := to - from
	if motion.length_squared() < 0.01:
		return true
	var circle := CircleShape2D.new()
	circle.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.transform = Transform2D(0.0, from)
	params.motion = motion
	params.collision_mask = 1
	params.exclude = exclude
	var result := get_world_2d().direct_space_state.cast_motion(params)
	return result.size() > 0 and result[0] >= 1.0
