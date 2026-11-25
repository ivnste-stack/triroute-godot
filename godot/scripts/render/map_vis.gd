class_name MapVis
extends RefCounted
## What the player has hidden on the map by a click in the legend (UI.hid and vis() of 08e-company.js):
## hubs, vehicles by transport, roads and railways, checkpoints, ports, airports, stations, towns, borders,
## the situation on the map. The layers ask vis(k) and redraw when `ver` changes.

static var hid := {}
static var ver := 0


static func vis(k: String) -> bool:
	if hid.has(k):
		return false
	if (k == "r1" or k == "r2" or k == "r3") and hid.has("roads"):
		return false
	return true


static func toggle(k: String) -> void:
	if hid.has(k):
		hid.erase(k)
	else:
		hid[k] = true
	ver += 1


static func clear() -> void:
	hid.clear()
	ver += 1


## LV_MAP: the legend line → what it hides (the first name the line starts with)
const LV_MAP := [["Хаби", "hub"], ["Кордони держав", "pol_b"], ["Фургони", "v_road"], ["Потяги", "v_rail"], ["Кораблі", "v_sea"],
	["Літаки", "v_air"], ["Доступно за ліцензією", "avail"], ["Поки недоступно", "unavail"], ["Зона піратства", "pir"],
	["Перекриті дороги", "jam"], ["Закриті кордони", "clb"], ["Негода", "wx"], ["Закриті порти", "clp"], ["Закрите небо", "sky"],
	["Зона бандитів", "band"], ["Платні швидкісні", "toll"], ["Заборона для важкого", "hban"], ["Напад", "mark"], ["Автомагістралі й", "roads"], ["Автомагістралі", "r3"], ["Дороги", "r2"],
	["Залізнична станція", "rails"], ["Залізниця", "rail"], ["Пропускний", "cp"], ["Морський порт", "port"], ["Аеропорт", "air"],
	["Назви морів", "seas"], ["Суходіл", "land"], ["Столиці", "s_city"], ["Малі міста", "s_town"]]


static func key_of(text: String) -> String:
	for m in LV_MAP:
		if text.begins_with(m[0]):
			return m[1]
	return ""
