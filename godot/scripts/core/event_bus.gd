extends Node
## Global signals. Modules talk through these instead of calling each other directly,
## so each module can be ported and tested on its own.

signal day_passed(day: int)
signal month_passed(month: int, year: int)
signal speed_changed(speed: int)
signal world_generated(seed: int)
signal game_saved(slot: String)
signal game_loaded(slot: String)
signal settings_changed(key: String, value: Variant)
signal toast(tone: String, title: String, text: String)
