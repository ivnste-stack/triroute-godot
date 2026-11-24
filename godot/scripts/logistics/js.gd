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


## +x.toFixed(2), the same way as fixed1
static func fixed2(x: float) -> float:
	var n := floorf(x * 100.0)
	if x * 100.0 - n >= 0.5:
		n += 1.0
	return n / 100.0


## Math.exp / Math.log / Math.log10 / Math.log2 / Math.pow, correctly rounded (native TRMath, core/crmath.h):
## the same on every platform, equal to Chromium's for exp and the logarithms. GDScript's exp/log/pow come
## from the C runtime and differ between Windows, Linux and the HTML version in the last bit.
static func exp(x: float) -> float:
	return TRMath.exp(x)


static func log(x: float) -> float:
	return TRMath.log(x)


static func log10(x: float) -> float:
	return TRMath.log10(x)


static func log2(x: float) -> float:
	return TRMath.log2(x)


static func pow(x: float, y: float) -> float:
	return TRMath.pow(x, y)
