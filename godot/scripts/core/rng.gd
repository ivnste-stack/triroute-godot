class_name Mulberry
extends RefCounted
## Deterministic RNG, bit-exact port of the legacy mulberry32 (03-core.js):
##   function mulberry(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);
##     t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
## The same seed must give the same world as the HTML version, so every step keeps 32-bit wrap-around.

const M := 0xFFFFFFFF

var _a: int


func _init(seed_value: int = 0) -> void:
	_a = seed_value & M


## Math.imul for unsigned 32-bit operands, without overflowing 64-bit ints.
static func imul(x: int, y: int) -> int:
	var lo := (x & 0xFFFF) * y
	var hi := (((x >> 16) & 0xFFFF) * y) & 0xFFFF
	return (lo + (hi << 16)) & M


## Next value in [0, 1).
func next() -> float:
	_a = (_a + 0x6D2B79F5) & M
	var t := imul(_a ^ (_a >> 15), 1 | _a)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & M) ^ t
	return float((t ^ (t >> 14)) & M) / 4294967296.0


func range_f(a: float, b: float) -> float:
	return a + next() * (b - a)


func range_i(a: int, b: int) -> int:   # inclusive, like legacy rint(a,b)
	return int(floor(range_f(a, b + 1)))


func chance(p: float) -> bool:
	return next() < p


func pick(arr: Array) -> Variant:
	return arr[int(floor(next() * arr.size()))]
