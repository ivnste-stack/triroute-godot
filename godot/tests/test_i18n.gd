extends RefCounted
## The English of the interface (I18n): exact strings, format strings with their values, joined parts,
## units, dates and transliterated names; the Ukrainian locale leaves every text as it is.

const CASES := [
	["Фінанси", "Finance"],
	["Доставок 20", "Deliveries 20"],
	["Інші кандидати · $346", "Other candidates · $346"],
	["$1.6 тис./міс", "$1.6k/month"],
	["3 січня 2026", "3 January 2026"],
	["1. Внутрішні перевезення", "1. Domestic haulage"],
	["ПрАТ «Мурінвест» → ТОВ «Бетонмонтаж»", "PJSC «Murinvest» → LLC «Betonmontazh»"],
	["Потрібно 3 × вантажна машина, вільних 1", "Needs 3 × light truck, free 1"],
	["ПРАЦІВНИКИ", "WORKERS"],
	["Річар", "Richar"],
]


func test_english_interface() -> String:
	I18n.setup("en")
	var bad := []
	for c in CASES:
		var got := TranslationServer.translate(c[0])
		if got != c[1]:
			bad.append("%s → %s (expected %s)" % [c[0], got, c[1]])
	I18n.setup("uk")
	if TranslationServer.translate("Фінанси") != "Фінанси":
		bad.append("the Ukrainian locale translated a text")
	return "; ".join(bad)
