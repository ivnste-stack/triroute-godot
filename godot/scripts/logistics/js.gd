class_name JS
extends RefCounted
## JavaScript-compatible helpers for the ported game logic: the same operations must give the same numbers
## as the HTML version (Math.hypot, Math.round, the game's clamp, Number.toFixed(1)).

## Math.hypot(a, b) as V8 computes it: scaled by the largest value, Kahan-summed squares.
static func hypot(a: float, b: float) -> float:
	a = absf(a)
	b = absf(b)
	var mx := maxf(a, b)
	if mx == 0.0:
		return 0.0
	var s := 0.0
	var comp := 0.0
	for v in [a, b]:
		var n: float = v / mx
		var summand := n * n - comp
		var prelim := s + summand
		comp = (prelim - s) - summand
		s = prelim
	return sqrt(s) * mx


## Math.round: ties toward +infinity.
static func round_js(x: float) -> float:
	var r := floorf(x)
	return r + 1.0 if x - r >= 0.5 else r


## clamp from 03-core.js: v<a?a:v>b?b:v
static func clamp_js(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)


## +x.toFixed(1): the nearest multiple of 0.1 (ties up), as the double JS parses it back to.
static func fixed1(x: float) -> float:
	var n := floorf(x * 10.0)
	if x * 10.0 - n >= 0.5:
		n += 1.0
	return n / 10.0


static func sstep(a: float, b: float, x: float) -> float:
	var t := clamp_js((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
