class_name Keys
extends RefCounted
## Key bindings (08k-keys.js, Settings → «Керування»). Keys are matched by their physical position
## (physical_keycode), so they work the same on the Ukrainian and the English layout. The player's changes
## are kept in the setting "keys" ({id: keycode}, 0 = no key).

const DEF := [
	["Час", [["pause", "Пауза / продовжити", KEY_SPACE], ["speed1", "Швидкість ×1", KEY_F5], ["speed2", "Швидкість ×2", KEY_F6],
		["speed3", "Швидкість ×3", KEY_F7], ["slower", "Повільніше", KEY_MINUS], ["faster", "Швидше", KEY_EQUAL]]],
	["Шари мапи", [["lay_co", "Мережа компанії", KEY_1], ["lay_grid", "Логістичні шляхи", KEY_2], ["lay_risk", "Ризики перевезень", KEY_3],
		["lay_pol", "Політична", KEY_4], ["lay_dem", "Світовий попит", KEY_5]]],
	["Вікна", [["w_coHome", "Компанія", KEY_C], ["w_coJobs", "Біржа вантажів", KEY_O], ["w_coTrips", "Рейси в дорозі", KEY_R],
		["w_coFleet", "Автопарк", KEY_V], ["w_coNet", "Мережа хабів", KEY_H], ["w_coStaff", "Персонал і менеджмент", KEY_P],
		["w_coFin", "Фінанси", KEY_F], ["w_news", "Стрічка новин", KEY_N]]],
	["Мапа", [["shot", "Скріншот", KEY_F2]]],
]
## keys that cannot be given to an action: the camera, the menu and the panels use them
const FIXED := [["Рух камери", "W A S D / стрілки"], ["Поворот камери", "Q / E"], ["Наближення", "колесо миші"],
	["Закрити вікно, меню", "Esc"], ["Панель продуктивності", "F3"], ["Запис продуктивності", "F4"], ["Перевірки", "F9"], ["Скасувати крок маршруту", "Ctrl+Z"]]
const BUSY := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ESCAPE, KEY_F3, KEY_F4, KEY_F9]


static func default_key(id: String) -> int:
	for g in DEF:
		for a in g[1]:
			if a[0] == id:
				return a[2]
	return 0


static func key(id: String) -> int:
	var o: Dictionary = Settings.get_value("keys")
	return int(o.get(id, default_key(id)))


static func set_key(id: String, k: int) -> void:
	var o: Dictionary = (Settings.get_value("keys") as Dictionary).duplicate()
	if k != 0:   # a key belongs to one action: the one that had it loses it
		for g in DEF:
			for a in g[1]:
				if a[0] != id and key(a[0]) == k:
					o[a[0]] = 0
	o[id] = k
	Settings.set_value("keys", o)


static func reset() -> void:
	Settings.set_value("keys", {})


static func name_of(k: int) -> String:
	if k == 0:
		return "—"
	var s := OS.get_keycode_string(k)
	return {"Space": "Пробіл", "Minus": "-", "Equal": "=", "BracketLeft": "[", "BracketRight": "]", "Semicolon": ";",
		"Apostrophe": "'", "Comma": ",", "Period": ".", "Slash": "/", "Backslash": "\\", "QuoteLeft": "`"}.get(s, s)


## the action of a key press, "" when none (keys with Ctrl, Alt or Cmd are never actions)
static func action_for(e: InputEventKey) -> String:
	if e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		return ""
	var k := int(e.physical_keycode) if e.physical_keycode != KEY_NONE else int(e.keycode)
	for g in DEF:
		for a in g[1]:
			if key(a[0]) == k:
				return a[0]
	return ""
