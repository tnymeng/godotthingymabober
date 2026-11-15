extends Node2D
## Main arena: wires players to the ball, keeps score, runs the hold zone,
## the death sequence and the round-start countdown, and keeps the HUD up to date.
##
## Round flow:  countdown (3 s, frozen) -> play -> one of:
##   - hit: death sequence (1 s slow motion + explosion, then back to normal
##     speed until the ball is back with the thrower; at least 3 s; only the
##     thrower can move) -> reset -> countdown
##   - hold zone entered: point, immediate reset -> countdown (no animation)
## First player to points_to_win wins: victory screen (Rematch / Main menu).
## Esc pauses (Resume / Restart / Main menu).

const MAIN_MENU := "res://dodgeball/main_menu.tscn"
const ARENA_SCENE_PATH := "res://dodgeball/arena.tscn"

## Show the ball speed / throw counter (debug).
@export var show_debug_speed: bool = false
## Seconds of "3, 2, 1" before each round, with players frozen.
@export var round_start_countdown: float = 3.0
## "<player> scored" stays up until play resumes, and at least this many
## real seconds.
@export var score_message_min_time: float = 1.5
## Points needed to win the match (0 = no limit).
@export var points_to_win: int = 5
## Single player: Player 2 is controlled by a DodgeBot.
@export var single_player: bool = false
## Attract mode (U on the main menu): both players are bots.
@export var attract_mode: bool = false
## Difficulty level (Difficulty.EASY / NORMAL / HARD), set from the menus.
## Two players: catch circle size. Single player: bot speed and reactions.
## -1 leaves the players' own settings (when the arena is run on its own).
@export var difficulty: int = -1
## On very light floors (e.g. Ice) the translucent white catch ring would
## vanish, so players use this contrasting ring colour instead.
@export var light_floor_catch_ring_color: Color = Color(0.1, 0.25, 0.55, 0.25)
## Floor brightness (0..1) above which the floor counts as light.
@export var light_floor_threshold: float = 0.85

@export_group("Cover")
## Random grid-aligned cover walls (no dead ends, mirrored for fairness).
@export var cover_enabled: bool = true
## 0 = a new random layout every round; any other number repeats the same
## sequence of layouts (seed + round number).
@export var cover_seed: int = 0

@export_group("Hold zone")
## While a player holds the ball, a red circle around them grows with the
## time they've held it. If the other player's centre is inside it, the round
## ends immediately (no death animation).
@export var hold_zone_enabled: bool = true
## Radius when the ball is first picked up (pixels).
@export var hold_zone_start_radius: float = 24.0
## Growth per second the ball is held (pixels per second of radius).
@export var hold_zone_growth_rate: float = 8.75
## The circle never grows beyond this radius (180 = 360 px across).
@export var hold_zone_max_radius: float = 180.0
## true: the player who ENTERS the circle scores (punishes holding too long).
## false: the HOLDER scores when the other player is inside their circle.
@export var hold_zone_point_to_intruder: bool = true

@export_group("Death sequence")
## Minimum length of the death sequence in REAL seconds (0 = skip it). It
## also waits for the ball to get back to the thrower, up to the maximum.
@export var death_sequence_duration: float = 3.0
## Hard limit in REAL seconds, in case the ball takes too long to return.
@export var death_sequence_max_duration: float = 8.0
## Engine.time_scale during the slow motion (0.2 = five times slower).
@export var slow_motion_scale: float = 0.2
## Real seconds to blend into slow motion right after the hit.
@export var slow_motion_ramp_in: float = 0.15
## Real seconds of slow motion from the hit (includes the ramp-in).
@export var slow_motion_hold: float = 1.0
## Real seconds to speed back up to normal after the slow motion.
@export var slow_motion_ramp_out: float = 0.5

var scores: Dictionary = {}
var countdown_remaining: float = 0.0
## True while the death sequence is playing.
var death_sequence_active: bool = false

var _death_start_usec: int = 0
var _hit_victim: DodgePlayer = null
var _explosion: DeathExplosion = null
var _ball_returned: bool = false
var _score_message_until_usec: int = 0
var _pause_started_usec: int = 0
## The match setup, kept so Restart / Rematch can rebuild the same match.
var _kits: Array[int] = [0, 1]
## Photo mode: each player's round photo (null = use the kit's sprite).
var _photos: Array = []
var _court: int = 0
var _bot: DodgeBot = null
var _bot_one: DodgeBot = null
## Rounds played since the match started (picks each round's cover layout).
var _round_number: int = 0

@onready var player_one: DodgePlayer = $Player1
@onready var player_two: DodgePlayer = $Player2
@onready var ball: DodgeBall = $Ball
@onready var cover: CoverGrid = $Cover
@onready var possession_label: Label = $HUD/PossessionLabel
@onready var speed_label: Label = $HUD/SpeedLabel
@onready var score_label: Label = $HUD/ScoreLabel
@onready var countdown_label: Label = $HUD/CountdownLabel
@onready var countdown_overlay: ColorRect = $HUD/CountdownOverlay
@onready var score_message_label: Label = $HUD/ScoreMessageLabel
@onready var controls_label: Label = $HUD/ControlsLabel
@onready var overlay: CanvasLayer = $MatchOverlay


func _ready() -> void:
	var players: Array[DodgePlayer] = [player_one, player_two]
	for player in players:
		scores[player] = 0
		player.throw_requested.connect(ball.try_throw)
		player.catch_requested.connect(_on_catch_requested)
	if single_player or attract_mode:
		_bot = DodgeBot.new()
		_bot.name = "Bot"
		add_child(_bot)
		player_two.bot = _bot
		player_two.display_name = "Bot (%s)" % player_two.color_name
		controls_label.text = ("%s: WASD move, E throw, Q catch, L-Shift dash\n"
				+ "%s: Computer") % [player_one.color_name, player_two.color_name]
	if attract_mode:
		_bot_one = DodgeBot.new()
		_bot_one.name = "BotOne"
		add_child(_bot_one)
		player_one.bot = _bot_one
		player_one.display_name = "Bot (%s)" % player_one.color_name
		controls_label.text = "%s and %s: Computer" % [
				player_one.color_name, player_two.color_name]
		# Flashing "press any button to play"; any button goes to the menu.
		var prompt := AttractOverlay.new()
		prompt.name = "AttractOverlay"
		add_child(prompt)
		prompt.any_button_pressed.connect(go_to_main_menu)
		overlay.pause_enabled = false
		# The demo runs forever: no points limit and no score counter.
		points_to_win = 0
		score_label.visible = false
	if not (single_player or attract_mode):
		controls_label.text = ("%s: WASD move, E throw, Q catch, L-Shift dash\n"
				+ "%s: Arrows move, . throw, , catch, R-Shift dash") % [
				player_one.color_name, player_two.color_name]
	ball.player_hit.connect(_on_player_hit)
	ball.returned_after_hit.connect(_on_ball_returned_after_hit)
	overlay.paused_changed.connect(_on_paused_changed)
	overlay.restart_requested.connect(restart_match)
	overlay.main_menu_requested.connect(go_to_main_menu)
	_pick_catch_ring_colour()
	_apply_theme_walls()
	if cover_enabled:
		_generate_cover()
		ball.nav = cover
	ball.setup(players, player_one) # Player 1 starts with the ball.
	if _bot != null:
		_bot.setup(player_two, player_one, ball, cover if cover_enabled else null)
	if _bot_one != null:
		_bot_one.setup(player_one, player_two, ball, cover if cover_enabled else null)
	_apply_difficulty()
	_apply_court_movement()
	_update_score_label()
	_begin_countdown()


## How the chosen court changes movement for both players (the bot too):
## slower on Grass, sliding on Ice. See CourtFloor.COURTS.
func _apply_court_movement() -> void:
	var c: Dictionary = CourtFloor.COURTS[wrapi(_court, 0, CourtFloor.court_count())]
	for player in [player_one, player_two]:
		player.player_speed *= c["speed"]
		player.player_acceleration *= c["accel"]
		player.player_deceleration *= c["brake"]


## Called by the character select screen BEFORE the arena enters the tree:
## kits[i] is the CharacterLooks kit index for player i + 1.
func apply_player_kits(kits: Array[int]) -> void:
	_kits = kits.duplicate()
	for i in mini(kits.size(), 2):
		var player := get_node("Player%d" % (i + 1)) as DodgePlayer
		var kit := kits[i]
		player.character_texture = CharacterLooks.texture(kit)
		player.body_color = CharacterLooks.kit_colour(kit)
		player.color_name = CharacterLooks.kit_name(kit)
		player.display_name = "Player %d (%s)" % [i + 1, player.color_name]


## Photo mode: use each player's photo (a round texture drawn facing right,
## see Webcam.make_circle) as their character instead of the kit's sprite.
## Call after apply_player_kits, before the arena enters the tree.
func apply_player_photos(photos: Array) -> void:
	_photos = photos.duplicate()
	for i in mini(photos.size(), 2):
		if photos[i] != null:
			(get_node("Player%d" % (i + 1)) as DodgePlayer).character_texture = photos[i]


## Bot speed and reactions for one bot-controlled player.
func _apply_bot_difficulty(the_bot: DodgeBot, player: DodgePlayer, d: int) -> void:
	player.player_speed *= Difficulty.BOT_SPEED[d]
	the_bot.catch_chance = Difficulty.BOT_CATCH[d]
	the_bot.dodge_chance = Difficulty.BOT_DODGE[d]
	var k := Difficulty.BOT_REACTION[d]
	the_bot.reaction_time *= k
	the_bot.catch_comfort_time *= k
	the_bot.catch_min_time *= k
	the_bot.preferred_distance = Difficulty.BOT_KEEP_DISTANCE[d]
	the_bot.distance_dash_fraction = Difficulty.BOT_DISTANCE_DASH[d]
	the_bot.smart_evasion = Difficulty.BOT_SMART_EVASION[d]


func _apply_difficulty() -> void:
	if difficulty < 0:
		return
	var d := Difficulty.clamp_level(difficulty)
	if _bot != null:
		_apply_bot_difficulty(_bot, player_two, d)
		if _bot_one != null:
			_apply_bot_difficulty(_bot_one, player_one, d)
	else:
		for player in [player_one, player_two]:
			player.catch_radius = Difficulty.CATCH_RADIUS[d]
			player.queue_redraw()


## Keep the catch ring visible against the floor: white normally, a dark
## blue on light floors.
func _pick_catch_ring_colour() -> void:
	var floor_node := get_node("Floor") as CourtFloor
	if floor_node.floor_colour().get_luminance() > light_floor_threshold:
		for player in [player_one, player_two]:
			player.catch_circle_color = light_floor_catch_ring_color
			player.queue_redraw()


## Called by the character select screen BEFORE the arena enters the tree:
## index into CourtFloor.COURTS.
func apply_court(court: int) -> void:
	_court = court
	(get_node("Floor") as CourtFloor).use_court(court)


## The map theme's border tile on the arena's outer walls (drawn a little
## thicker on the outside). Cover walls keep the default look.
func _apply_theme_walls() -> void:
	var c: Dictionary = CourtFloor.COURTS[wrapi(_court, 0, CourtFloor.court_count())]
	(get_node("Walls") as Node).use_theme_tile(load(c["border"]) as Texture2D, Rect2(), CourtFloor.BORDER_EXTRA)


## Start the same match again from 0 - 0 (same kits and court).
func restart_match() -> void:
	var tree := get_tree()
	tree.paused = false
	Engine.time_scale = 1.0
	var arena := (load(ARENA_SCENE_PATH) as PackedScene).instantiate()
	arena.apply_player_kits(_kits)
	arena.apply_player_photos(_photos)
	arena.apply_court(_court)
	arena.single_player = single_player
	arena.attract_mode = attract_mode
	arena.difficulty = difficulty
	tree.root.add_child(arena)
	tree.current_scene = arena
	queue_free()


func go_to_main_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MAIN_MENU)


## Real-time timers (death sequence, score message) skip the paused time.
func _on_paused_changed(paused: bool) -> void:
	if paused:
		_pause_started_usec = Time.get_ticks_usec()
	else:
		var paused_for := Time.get_ticks_usec() - _pause_started_usec
		_death_start_usec += paused_for
		_score_message_until_usec += paused_for


## If someone has reached points_to_win, show the victory screen.
func _check_victory() -> bool:
	if points_to_win <= 0:
		return false
	for player in [player_one, player_two]:
		if scores[player] >= points_to_win:
			_set_round_active(false)
			Engine.time_scale = 1.0
			score_message_label.visible = false
			overlay.show_victory("%s wins!" % player.display_name,
					player.body_color.lightened(0.3), score_label.text)
			SoundFx.play("win")
			return true
	return false


func _exit_tree() -> void:
	Engine.time_scale = 1.0 # never leave the engine stuck in slow motion


# Runs before the players and ball each physics step (parent first), so the
# frame the countdown ends is the first frame anyone can act.
func _physics_process(delta: float) -> void:
	if countdown_remaining > 0.0:
		countdown_remaining -= delta
		if countdown_remaining <= 0.0:
			countdown_remaining = 0.0
			_set_round_active(true)
			_show_countdown(false)
			SoundFx.play("go")
		else:
			var shown := str(ceili(countdown_remaining))
			if shown != countdown_label.text:
				SoundFx.play("tick") # each new number: 3, 2, 1
			countdown_label.text = shown
	_update_hold_zone()


func _process(_delta: float) -> void:
	var round_running := ball.round_active and not death_sequence_active
	if score_message_label.visible and round_running \
			and Time.get_ticks_usec() >= _score_message_until_usec:
		score_message_label.visible = false
	if death_sequence_active:
		_update_death_sequence()
	_update_possession_label()
	speed_label.visible = show_debug_speed
	if show_debug_speed:
		speed_label.text = "Ball: %d px/s   Next throw: %d px/s   Speed step: %d" % [
			roundi(ball.get_speed()), roundi(ball.next_throw_speed()), ball.speed_steps]


func _begin_countdown() -> void:
	countdown_remaining = round_start_countdown
	if countdown_remaining <= 0.0:
		_set_round_active(true)
		_show_countdown(false)
		return
	_set_round_active(false)
	countdown_label.text = str(ceili(countdown_remaining))
	_show_countdown(true)
	SoundFx.play("tick")


func _show_countdown(show: bool) -> void:
	countdown_label.visible = show
	countdown_overlay.visible = show


func _set_round_active(active: bool) -> void:
	for player in [player_one, player_two]:
		player.can_move = active
		player.can_act = active
	ball.round_active = active


func _other_player(player: DodgePlayer) -> DodgePlayer:
	return player_two if player == player_one else player_one


# --- Hold zone ---------------------------------------------------------------

func _update_hold_zone() -> void:
	var active := hold_zone_enabled and ball.round_active and not death_sequence_active \
			and ball.state == DodgeBall.State.HELD and ball.holder != null
	if not active:
		player_one.hold_zone_radius = 0.0
		player_two.hold_zone_radius = 0.0
		return

	var holder := ball.holder
	var other := _other_player(holder)
	var radius := minf(hold_zone_start_radius + hold_zone_growth_rate * ball.hold_time,
			hold_zone_max_radius)
	holder.hold_zone_radius = radius
	other.hold_zone_radius = 0.0

	if other.global_position.distance_to(holder.global_position) < radius:
		_on_hold_zone_entered(holder, other)


## Point and an immediate new round (no death animation). The player who
## gave up the point starts the next round with the ball, like after a hit.
func _on_hold_zone_entered(holder: DodgePlayer, intruder: DodgePlayer) -> void:
	var scorer := intruder if hold_zone_point_to_intruder else holder
	var loser := _other_player(scorer)
	scores[scorer] += 1
	_announce_score(scorer)
	_update_score_label()
	if _check_victory():
		return
	_start_new_round(loser)


# --- Catches and hits ----------------------------------------------------------

func _on_catch_requested(player: DodgePlayer) -> void:
	ball.try_catch(player) # a miss is handled by the player (grace window, cooldown)


func _on_player_hit(victim: DodgePlayer, thrower: DodgePlayer) -> void:
	if death_sequence_active:
		return # can't happen (the ball ignores players now), but never double-score
	SoundFx.play("hit")
	if thrower != null:
		scores[thrower] += 1
		_announce_score(thrower)
	_update_score_label()
	_start_death_sequence(victim, thrower)


func _on_ball_returned_after_hit(_thrower: DodgePlayer) -> void:
	_ball_returned = true


# --- Death sequence ------------------------------------------------------------

## Freeze the victim, spawn the explosion and go to slow motion. The thrower
## can still walk around; their movement follows Engine.time_scale, so they
## slow down and speed back up together with the ball and the explosion.
## The ball flies through the victim (PASS_THROUGH) and homes back to the
## thrower; the sequence ends once it is back and the minimum time passed.
func _start_death_sequence(victim: DodgePlayer, thrower: DodgePlayer) -> void:
	_hit_victim = victim
	_set_round_active(false) # no throwing/catching, hold timer paused
	if death_sequence_duration <= 0.0:
		_finish_death_sequence()
		return
	if thrower != null:
		thrower.can_move = true
	death_sequence_active = true
	_ball_returned = ball.state == DodgeBall.State.HELD
	_death_start_usec = Time.get_ticks_usec()

	_explosion = DeathExplosion.new()
	_explosion.setup(victim.body_color, victim.player_radius)
	_explosion.position = victim.position
	add_child(_explosion)
	victim.hide_for_death()


func _update_death_sequence() -> void:
	# Measured in real time, so slow motion doesn't stretch it.
	var elapsed := (Time.get_ticks_usec() - _death_start_usec) / 1_000_000.0
	var done := elapsed >= death_sequence_duration and _ball_returned
	if done or elapsed >= death_sequence_max_duration:
		_finish_death_sequence()
		return
	Engine.time_scale = _slow_motion_curve(elapsed)


## 1 -> slow_motion_scale over the ramp-in, hold until slow_motion_hold,
## ramp back to 1 over slow_motion_ramp_out, then normal speed.
func _slow_motion_curve(elapsed: float) -> float:
	if slow_motion_ramp_in > 0.0 and elapsed < slow_motion_ramp_in:
		return lerpf(1.0, slow_motion_scale, elapsed / slow_motion_ramp_in)
	if elapsed < slow_motion_hold:
		return slow_motion_scale
	if slow_motion_ramp_out > 0.0 and elapsed < slow_motion_hold + slow_motion_ramp_out:
		return lerpf(slow_motion_scale, 1.0, (elapsed - slow_motion_hold) / slow_motion_ramp_out)
	return 1.0


func _finish_death_sequence() -> void:
	death_sequence_active = false
	Engine.time_scale = 1.0
	if is_instance_valid(_explosion):
		_explosion.queue_free()
	_explosion = null
	var victim := _hit_victim
	_hit_victim = null
	if _check_victory():
		return
	_start_new_round(victim) # The player who was hit gets the ball.


func _start_new_round(first_holder: DodgePlayer) -> void:
	player_one.reset_for_round()
	player_two.reset_for_round()
	ball.reset_round(first_holder)
	if cover_enabled:
		_round_number += 1
		_generate_cover() # new wall layout every round; the floor stays the same
	_begin_countdown()


## Random cover around the players' start positions. With cover_seed set,
## each round gets its own repeatable layout (seed + round number).
func _generate_cover() -> void:
	var spawns: Array[Vector2] = [player_one.start_position, player_two.start_position]
	var seed_value := 0 if cover_seed == 0 else cover_seed + _round_number
	cover.generate(seed_value, spawns, maxf(player_one.player_radius, player_two.player_radius))


# --- HUD -----------------------------------------------------------------------

func _announce_score(scorer: DodgePlayer) -> void:
	SoundFx.play("score")
	score_message_label.text = "%s scored" % scorer.display_name
	score_message_label.add_theme_color_override("font_color", scorer.body_color.lightened(0.35))
	score_message_label.visible = true
	_score_message_until_usec = Time.get_ticks_usec() + int(score_message_min_time * 1_000_000.0)


func _update_score_label() -> void:
	score_label.text = "%s  %d  -  %d  %s" % [player_one.color_name, scores[player_one],
			scores[player_two], player_two.color_name]


func _update_possession_label() -> void:
	if death_sequence_active and _hit_victim != null:
		possession_label.text = "%s was hit!" % _hit_victim.display_name
		possession_label.add_theme_color_override("font_color", _hit_victim.body_color.lightened(0.3))
		return
	match ball.state:
		DodgeBall.State.HELD:
			possession_label.text = "%s has the ball" % ball.holder.display_name
			possession_label.add_theme_color_override("font_color", ball.holder.body_color.lightened(0.3))
		DodgeBall.State.FLYING:
			var suffix := ", returning" if ball.has_bounced else ""
			possession_label.text = "Thrown by %s%s" % [ball.last_thrower.display_name, suffix]
			possession_label.add_theme_color_override("font_color", ball.last_thrower.body_color.lightened(0.3))
