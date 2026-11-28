class_name SmoothScroll
extends ScrollContainer
## A scroll container that glides: the mouse wheel moves a target and the view eases to it (like a browser's
## smooth scrolling) and stops dead on it. Dragging the scroll bar or a jump made by the code cancels the glide.

const STEP := 90.0          # pixels per wheel notch
const TIME := .16           # seconds to reach the target

var _target := -1.0
var _from := 0.0
var _t := 0.0
var _mine := false          # the scroll value is being set by the glide
var hold := false           # the trailer studio scrolls it slowly: the window is not built again meanwhile


func _ready() -> void:
	scroll_vertical_custom_step = STEP
	var bar := get_v_scroll_bar()
	bar.value_changed.connect(func(_v): if not _mine: _target = -1.0)   # the bar was dragged or the code jumped


## a glide is running or the bar is held: the content should not be rebuilt under the reader
func busy() -> bool:
	return hold or _target >= 0 or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_v_scroll_bar().get_global_rect().has_point(get_global_mouse_position())


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		accept_event()   # the wheel over a panel never reaches the map
		var bar := get_v_scroll_bar()
		var top := maxf(0.0, bar.max_value - bar.page)
		if top <= 0:
			return
		var f: float = e.factor if e.factor > 0 else 1.0
		var base := _target if _target >= 0 else float(scroll_vertical)
		_target = clampf(base + (STEP if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -STEP) * f, 0, top)
		_from = scroll_vertical
		_t = 0.0


func _process(delta: float) -> void:
	if _target < 0:
		return
	_t = minf(1.0, _t + delta / TIME)
	var k := 1.0 - pow(1.0 - _t, 3.0)   # ease-out
	_mine = true
	scroll_vertical = int(round(lerpf(_from, _target, k)))
	_mine = false
	if _t >= 1.0:
		_target = -1.0
