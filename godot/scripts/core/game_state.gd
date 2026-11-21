extends Node
## Top-level game state (legacy: G in 06-sim.js and the time loop in 09-main.js).
## The company data (legacy CO in 08e-company.js) moves here module by module.

const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

var world_seed: int = 0
var day: float = 0.0            # days since the start (fractional within a day)
var date := {"d": 1, "m": 0, "y": 2026}   # m is 0-based, like the legacy code
var speed: int = 0              # 0 = pause, 1..3 = play speeds
var difficulty: int = 1


func reset(seed_value: int) -> void:
	world_seed = seed_value
	day = 0.0
	date = {"d": 1, "m": 0, "y": 2026}
	speed = 0


func set_speed(s: int) -> void:
	speed = clampi(s, 0, 3)
	EventBus.speed_changed.emit(speed)


## Advances the calendar by whole days and emits day / month signals.
func advance_days(n: int) -> void:
	for i in n:
		day = floor(day) + 1.0
		date.d += 1
		if date.d > MONTH_DAYS[date.m]:
			date.d = 1
			date.m += 1
			if date.m > 11:
				date.m = 0
				date.y += 1
			EventBus.month_passed.emit(date.m, date.y)
		EventBus.day_passed.emit(int(day))


func to_dict() -> Dictionary:
	return {"seed": world_seed, "day": day, "date": date.duplicate(), "speed": speed, "diff": difficulty}


func from_dict(d: Dictionary) -> void:
	world_seed = int(d.get("seed", 0))
	day = float(d.get("day", 0.0))
	date = d.get("date", {"d": 1, "m": 0, "y": 2026})
	speed = 0
	difficulty = int(d.get("diff", 1))
