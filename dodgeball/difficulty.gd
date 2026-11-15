class_name Difficulty
extends RefCounted
## Difficulty levels and what they change.
##  - Two players: the size of both players' catch circles.
##  - Single player: how fast the bot moves and how it reacts to a throw at it
##    (catch / dodge / freeze = no reaction).

const EASY := 0
const NORMAL := 1
const HARD := 2

const NAMES: Array[String] = ["Easy", "Normal", "Hard"]

## Two players: catch circle radius (pixels).
const CATCH_RADIUS: Array[float] = [75.0, 65.0, 55.0]

## Single player: bot movement speed as a fraction of a player's normal speed.
const BOT_SPEED: Array[float] = [0.7, 0.85, 1.0]
## Single player: chance the bot catches / dodges a throw at it. Whatever is
## left over is the chance it freezes and doesn't react.
const BOT_CATCH: Array[float] = [0.25, 0.40, 0.55]
const BOT_DODGE: Array[float] = [0.30, 0.35, 0.40]
## Single player: multiplier on all the bot's reaction times (delay before
## throwing, and the time it needs to catch). Normal = 2/3, Hard = half.
const BOT_REACTION: Array[float] = [1.0, 2.0 / 3.0, 0.5]
## Single player: distance (px) the bot tries to keep from you while you hold
## the ball (more distance = more time to react to your throw)...
const BOT_KEEP_DISTANCE: Array[float] = [380.0, 460.0, 540.0]
## ...and it dashes away when you get closer than this fraction of that
## distance (0 = never dashes for distance).
const BOT_DISTANCE_DASH: Array[float] = [0.0, 0.6, 0.85]
## Single player: Hard bot steers toward open space so it doesn't get
## cornered, and never stands still while you hold the ball.
const BOT_SMART_EVASION: Array[bool] = [false, false, true]

## One-line descriptions for the difficulty screen.
const TWO_PLAYER_TEXT: Array[String] = [
	"Big catch circles",
	"Medium catch circles",
	"Small catch circles",
]
const SINGLE_PLAYER_TEXT: Array[String] = [
	"Slow bot that often misses",
	"Quicker bot that catches and dodges more",
	"Full-speed bot that rarely misses",
]


static func clamp_level(level: int) -> int:
	return clampi(level, EASY, HARD)
