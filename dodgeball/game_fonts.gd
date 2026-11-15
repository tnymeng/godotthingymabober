class_name GameFonts
extends RefCounted
## The game's two fonts, for text drawn in code (labels and buttons get them
## from the project theme, dodgeball/ui_theme.tres).
##  - DISPLAY: Lilita One, chunky, for titles, buttons, score and big text.
##  - BODY: Fredoka SemiBold, rounded and easy to read, for everything else.
## Both from Google Fonts, SIL Open Font License (see assets/fonts/*-OFL.txt).

const DISPLAY: Font = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const BODY: Font = preload("res://assets/fonts/fredoka_semibold.tres")
