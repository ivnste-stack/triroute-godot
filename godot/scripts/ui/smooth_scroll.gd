class_name SmoothScroll
extends ScrollContainer
## A scroll container that glides: the mouse wheel moves a target and the view eases to it every frame (like
## a browser's smooth scrolling), instead of jumping a step at a time.

const STEP := 90.0          # pixels per wheel notch
const EASE := 18.0          # how fast the view catches up (1/s)

var _target := -1.0


func _ready() -> void:
	scroll_vertical_custom_step = STEP


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var bar := get_v_scroll_bar()
		if bar.max_value - bar.page <= 0:
			return
		if _target < 0:
			_target = scroll_vertical
		var f: float = e.factor if e.factor > 0 else 1.0
		_target = clampf(_target + (STEP if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -STEP) * f, 0, bar.max_value - bar.page)
		accept_event()


func _process(delta: float) -> void:
	if _target < 0:
		return
	var cur := float(scroll_vertical)
	var nxt := lerpf(cur, _target, 1.0 - exp(-EASE * delta))
	if absf(_target - nxt) < 1.0:
		nxt = _target
		_target = -1.0
	scroll_vertical = int(round(nxt))
