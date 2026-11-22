class_name GameSession
extends Node
## A running company game: the simulation (Sim) and its clock, like simStep / dayTick of the HTML version
## (09-main.js): at speed 1 / 2 / 3 a day takes 150 / 30 / 5 seconds; the part of the day that has passed goes
## to the trips every frame (coFrame), a new day runs the day's logic (coDay). Paused at speed 0.

signal day_passed(day: int)

const DUR := [0.0, 150000.0, 30000.0, 5000.0]   # ms per day (DUR_C)

var sim: Sim
var speed := 0
var acc := 0.0          # ms into the current day
var anim_t := 0.0       # animation time (ANIM_T): runs while the game runs
var paused_fr := 0.0    # the part of the day shown while paused (G.pfr)
var hold := false       # a dialog is open: time stands still (modalOpen)


## a new company on the world made by gen (states, board and the world dictionary of the same seed);
## hq: a place id, or -1 for the first suggested capital
func start(gen: Object, seed_value: int, states: Array, board: Dictionary, world: Dictionary, hq: int = -1) -> void:
	begin(gen, seed_value, states, board, world)
	choose_hq(hq if hq >= 0 else choices[0].id)


var choices: Array = []


## a new company before the headquarters is chosen (coInit with the first suggested capital, as the original)
func begin(gen: Object, seed_value: int, states: Array, board: Dictionary, world: Dictionary, diff: int = 1) -> void:
	sim = Sim.new()
	sim.setup(gen, seed_value, states, board, world)
	sim.diff = diff
	choices = sim.start_choices()
	sim.co_init(choices[0].id)


## the headquarters (coSetHQ); decisions wait for the interface unless auto_choice is set
func choose_hq(pid: int, auto_decisions: bool = true) -> void:
	sim.co_set_hq(pid)
	sim.auto_choice = 0 if auto_decisions else -1
	acc = 0.0
	sim.co_frame(0.0)


## a fleet of tier 4 at the headquarters with an automatic dispatcher (the "abroad" scenario of the tests):
## trips run on their own while the interface cannot send them yet
func demo_fleet() -> void:
	var CO := sim.CO
	CO.cash = 2e6
	CO.tier = 4
	CO.staff.merge({"driver": 12, "rail": 6}, true)
	for vt in ["truck", "truck", "truck", "rtrain", "reefer", "ltruck", "van", "van", "van", "train", "train"]:
		CO.veh.append({"id": CO.uid, "t": vt, "loc": CO.hq, "st": "idle", "cond": 100.0, "km": 0.0})
		CO.uid += 1
	CO.mgr.cto = CO.cand.cto[0].duplicate()
	CO.cand.erase("cto")
	CO.auto = true
	for i in 3:
		sim.co_board_day()
	sim.co_auto()


## while set, time may not run (the route planner is open): why
var lock_speed := ""
signal speed_refused(why: String)


func set_speed(i: int) -> void:
	if i and lock_speed != "":
		speed_refused.emit(lock_speed)
		return
	if i == speed:
		return
	if i == 0:
		paused_fr = minf(acc / DUR[speed], .999) if speed > 0 else paused_fr
	else:
		acc = (paused_fr if speed == 0 else acc / DUR[speed]) * DUR[i]
	speed = i


## the part of the day that has passed
func fraction() -> float:
	return clampf(acc / DUR[speed], 0, .999) if speed > 0 else paused_fr


## runs days at once (tests, fast-forward); the trips are stepped 8 times a day
func run_days(n: int) -> void:
	for d in n:
		for f in 8:
			sim.co_frame(f / 8.0)
		sim.co_day()
		day_passed.emit(int(sim.day))
	sim.co_frame(0.0)


func _process(delta: float) -> void:
	if sim == null:
		return
	var dt := minf(delta * 1000.0, 250.0)
	if speed > 0 and not sim.over and not hold:
		anim_t += dt / 1000.0
		acc += dt
		var n := 0
		while acc >= DUR[speed] and n < 4:
			acc -= DUR[speed]
			n += 1
			sim.co_day()
			day_passed.emit(int(sim.day))
	sim.co_frame(fraction())
