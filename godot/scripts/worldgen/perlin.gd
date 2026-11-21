class_name Perlin
extends RefCounted
## Gradient noise, exact port of makePerlin() in legacy 04-map.js (used by the world and road generators).
## Gradients are stored as float32 like the original Float32Array, so the values match to the last bits.

var _p := PackedInt32Array()
var _gx := PackedFloat32Array()
var _gy := PackedFloat32Array()


func _init(rng: Mulberry) -> void:
	var perm := PackedInt32Array()
	perm.resize(256)
	for i in 256:
		perm[i] = i
	for i in range(255, 0, -1):
		var j := int(floor(rng.next() * (i + 1)))
		var t := perm[i]
		perm[i] = perm[j]
		perm[j] = t
	_p.resize(512)
	for i in 512:
		_p[i] = perm[i & 255]
	_gx.resize(16)
	_gy.resize(16)
	for i in 16:
		var a := float(i) / 16.0 * PI * 2.0
		_gx[i] = cos(a)
		_gy[i] = sin(a)


func noise(x: float, y: float) -> float:
	var xi := int(floor(x))
	var yi := int(floor(y))
	var xf := x - xi
	var yf := y - yi
	var X := xi & 255
	var Y := yi & 255
	var u := xf * xf * xf * (xf * (xf * 6.0 - 15.0) + 10.0)
	var v := yf * yf * yf * (yf * (yf * 6.0 - 15.0) + 10.0)
	var a := _p[_p[X] + Y] & 15
	var b := _p[_p[X + 1] + Y] & 15
	var c := _p[_p[X] + Y + 1] & 15
	var d := _p[_p[X + 1] + Y + 1] & 15
	var n00 := _gx[a] * xf + _gy[a] * yf
	var n10 := _gx[b] * (xf - 1.0) + _gy[b] * yf
	var n01 := _gx[c] * xf + _gy[c] * (yf - 1.0)
	var n11 := _gx[d] * (xf - 1.0) + _gy[d] * (yf - 1.0)
	var x1 := n00 + (n10 - n00) * u
	var x2 := n01 + (n11 - n01) * u
	return x1 + (x2 - x1) * v
