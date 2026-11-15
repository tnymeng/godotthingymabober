class_name SoundFx
extends Node
## Sound effects: SoundFx.play("bounce") from anywhere. Runs as the "Sfx"
## autoload; the static play() finds it, so scripts don't depend on the
## autoload name at compile time.
##
## Placeholder sounds from Kenney's CC0 packs (Interface Sounds, 50 RPG Sound
## Effects, Digital SFX) in assets/sounds/. To swap a sound, change its path(s)
## in SOUNDS; when a cue lists several files, one is picked at random. A small
## random pitch change keeps repeated sounds from sounding identical. Keeps
## playing while the game is paused (menus, victory screen).

const DIR := "res://assets/sounds/"

## cue name -> [file paths, volume in dB, pitch variation (+/-)]
const SOUNDS := {
	"throw": [["kenney_rpg/OGG/knifeSlice.ogg", "kenney_rpg/OGG/knifeSlice2.ogg"], -4.0, 0.08],
	"bounce": [["kenney_interface/Audio/drop_002.ogg", "kenney_interface/Audio/drop_003.ogg"], -2.0, 0.12],
	"catch": [["kenney_rpg/OGG/dropLeather.ogg"], 0.0, 0.06],
	"miss": [["kenney_interface/Audio/error_004.ogg"], -6.0, 0.0],
	"dash": [["kenney_rpg/OGG/cloth1.ogg", "kenney_rpg/OGG/cloth2.ogg"], -2.0, 0.1],
	"hit": [["kenney_rpg/OGG/chop.ogg"], 2.0, 0.05],
	"score": [["kenney_interface/Audio/confirmation_002.ogg"], -2.0, 0.0],
	"tick": [["kenney_interface/Audio/tick_002.ogg"], -2.0, 0.0],
	"go": [["kenney_digital/highUp.mp3"], -8.0, 0.0],
	"win": [["kenney_digital/powerUp1.mp3"], -6.0, 0.0],
	"click": [["kenney_interface/Audio/click_002.ogg"], -4.0, 0.0],
	"back": [["kenney_interface/Audio/back_002.ogg"], -4.0, 0.0],
	"select": [["kenney_interface/Audio/select_002.ogg"], -4.0, 0.0],
	"switch": [["kenney_interface/Audio/switch_002.ogg"], -6.0, 0.05],
}

## How many sounds can play at once.
const VOICES := 12

## Mute everything (e.g. for tests).
var muted: bool = false
## Last cue played (handy for checking sounds fire).
var last_cue: String = ""
## How many times each cue has been played.
var counts: Dictionary = {}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for cue in SOUNDS:
		var list: Array[AudioStream] = []
		for path in SOUNDS[cue][0]:
			var s := load(DIR + path) as AudioStream
			if s != null:
				list.append(s)
			else:
				push_warning("Sfx: missing sound %s" % path)
		_streams[cue] = list
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Play a cue on the running Sfx autoload (does nothing if it isn't there).
static func play(cue: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var node := tree.root.get_node_or_null("Sfx") as SoundFx
	if node != null:
		node.play_cue(cue)


func play_cue(cue: String) -> void:
	last_cue = cue
	counts[cue] = counts.get(cue, 0) + 1
	if muted or not _streams.has(cue) or _streams[cue].is_empty():
		return
	var info: Array = SOUNDS[cue]
	var list: Array = _streams[cue]
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[_rng.randi() % list.size()]
	p.volume_db = info[1]
	p.pitch_scale = 1.0 + _rng.randf_range(-info[2], info[2])
	p.play()
