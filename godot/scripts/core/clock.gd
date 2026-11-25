class_name Clock
extends RefCounted
## The clock of the map's animations (blinking markers, pulses, moving dashes). Normally the real time; while
## the game is recorded by Movie Maker (--write-movie) the time of the frames, so a recording made on a slow
## machine moves as smoothly as the game does on a fast one.

static var _movie := -1


static func movie() -> bool:
	if _movie < 0:
		_movie = 1 if Engine.get_write_movie_path() != "" else 0
	return _movie == 1


## seconds
static func now() -> float:
	if movie():
		return Engine.get_process_frames() / float(maxi(1, Engine.max_fps if Engine.max_fps > 0 else 60))
	return Time.get_ticks_msec() / 1000.0


static func ms() -> int:
	return int(now() * 1000.0)
