class_name I18n
extends Translation
## The game's English. The interface is written in Ukrainian; with the English locale every text the
## interface shows passes through here (Godot's auto-translation of Labels, Buttons, tooltips… — the game's
## logic keeps comparing its own Ukrainian strings, nothing in it changes):
##   1. the exact string (assets/i18n/en.json, made by tools/i18n.py from the scripts' literals), also in
##      capitals (the code upper-cases some headings);
##   2. a format string with its values (“Доставок %d” → “Deliveries %d”), the text values translated too;
##   3. a known head or tail joined to something else (“Куплено: ” + a vehicle, a name + “ · штаб”);
##   4. parts joined by « · », new lines, bbcode tags — each part on its own;
##   5. what is left in Cyrillic — the names of towns, states, people, firms — transliterated;
##   6. the units after numbers: тис. → k, млн → M, дн. → d, год → h, км → km, т → t.
## Results are cached: a text costs one lookup after the first time.

const LANGS := [["uk", "Українська"], ["en", "English"]]
const SEPS := ["\n", " · ", " → "]
const EXTRA := {" Логістик": " Logistics", " Експрес": " Express", " Карго": " Cargo", " Доставка": " Delivery", " Транс": " Trans"}

static var _inst: I18n = null

var _map := {}          # Ukrainian → English
var _upper := {}        # the same in capitals
var _lower := {}        # and in small letters (cargo names in the middle of a sentence)
var _pat := {}          # the first two letters of a format string's literal head → [[regex, english, specs]]
var _pat_any := []      # format strings that begin with a value
var _heads := []        # keys ending in a space or a colon: [uk, en], longest first
var _tails := []        # keys beginning with a space: [uk, en], longest first
var _cache := {}
var _cy := RegEx.create_from_string("[А-Яа-яІіЇїЄєҐґ]")
var _spec := RegEx.create_from_string("%(?:%|[-+ 0#]*\\d*(?:\\.\\d+)?[sdfiexXc])")
var _units := []
var _edges := RegEx.create_from_string("^([^А-Яа-яІіЇїЄєҐґ«]*)(.*?)([^А-Яа-яІіЇїЄєҐґ»]*)$")


## the locale from the settings, the English table registered once
static func setup(lang: String) -> void:
	if _inst == null:
		_inst = I18n.new()
		_inst.locale = "en"
		_inst._load()
		TranslationServer.add_translation(_inst)
	TranslationServer.set_locale("en" if lang == "en" else "uk")


static func lang() -> String:
	return "en" if TranslationServer.get_locale().begins_with("en") else "uk"


## a text drawn by hand (labels on the map): translated like the interface's own
static func t(s: String) -> String:
	if _inst == null or lang() != "en" or s == "":
		return s
	return _inst._tr(s)


func _load() -> void:
	var f := FileAccess.get_file_as_string("res://assets/i18n/en.json")
	var d: Variant = JSON.parse_string(f) if f != "" else null
	if not (d is Dictionary):
		return
	_map = d
	for k in EXTRA:   # name pieces worth translating (the company names' endings)
		_map[k] = EXTRA[k]
	for k in _map:
		var uk: String = k
		var en: String = _map[k]
		_upper[uk.to_upper()] = en.to_upper()
		if not _lower.has(uk.to_lower()):
			_lower[uk.to_lower()] = en.to_lower()
		var specs := _spec.search_all(uk)
		if specs.size() and specs.any(func(m): return m.get_string() != "%%"):
			_add_pattern(uk, en)
		elif uk.length() > 2 and (uk.ends_with(" ") or uk.ends_with(": ")) and not uk.begins_with(" "):
			_heads.append([uk, en])
		elif uk.length() > 2 and uk.begins_with(" ") and not uk.ends_with(" "):
			_tails.append([uk, en])
	# the most specific format first: «Досвід команди %s» before «Досвід %s%s»
	var lit_len := func(e: Array) -> int: return _spec.sub(String(e[2]), "", true).length()
	for k in _pat:
		_pat[k].sort_custom(func(a, b): return lit_len.call(a) > lit_len.call(b))
	_pat_any.sort_custom(func(a, b): return lit_len.call(a) > lit_len.call(b))
	_heads.sort_custom(func(a, b): return a[0].length() > b[0].length())
	_tails.sort_custom(func(a, b): return a[0].length() > b[0].length())
	var nl := "(?![А-Яа-яІіЇїЄєҐґ])"   # not followed by a letter (\\b knows only Latin letters)
	for u in [["(\\d) тис\\.", "$1k"], ["(\\d) млн" + nl, "$1M"], ["(\\d) млрд" + nl, "$1B"], ["(\\d) дн\\.", "$1 d"], ["(\\d) год" + nl, "$1 h"],
			["(\\d) хв" + nl, "$1 min"], ["(\\d) км" + nl, "$1 km"], ["(\\d) т" + nl, "$1 t"], ["(\\d) міс\\.", "$1 mo"], ["/міс", "/month"], ["(\\d) шт" + nl, "$1 pcs"]]:
		_units.append([RegEx.create_from_string(u[0]), u[1]])


## a format string as a pattern: its literal parts escaped, every value a group
func _add_pattern(uk: String, en: String) -> void:
	var rx := "^"
	var pos := 0
	var head := ""
	var first := true
	for m in _spec.search_all(uk):
		var lit := uk.substr(pos, m.get_start() - pos)
		if first:
			head = lit
		rx += _esc(lit)
		var s := m.get_string()
		if s == "%%":
			rx += "%"
		elif s.ends_with("d") or s.ends_with("i"):
			rx += "(-?[\\d\\s,.]+?)"
		elif s.ends_with("f") or s.ends_with("e"):
			rx += "(-?[\\d.,]+?)"
		else:
			rx += "(.*?)"
		first = false
		pos = m.get_end()
	rx += _esc(uk.substr(pos)) + "$"
	var r := RegEx.create_from_string(rx)
	if not r.is_valid():
		return
	var e := [r, en, uk]
	if head.length() >= 2:
		var key := head.substr(0, 2)
		if not _pat.has(key):
			_pat[key] = []
		_pat[key].append(e)
	else:
		_pat_any.append(e)


static func _esc(s: String) -> String:
	var o := ""
	for ch in s:
		o += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return o


func _get_message(src: StringName, _context: StringName) -> StringName:
	return StringName(_tr(String(src)))


func _tr(s: String) -> String:
	if s == "" or _cy.search(s) == null:
		return s
	if _cache.has(s):
		return _cache[s]
	if _cache.size() > 40000:
		_cache.clear()
	_cache[s] = s   # a guard while the parts are being translated
	var u := _units_en(s)   # the units after numbers first: «$12 тис.» → «$12k»
	var out := u if _cy.search(u) == null else _units_en(_find(u, 0))
	_cache[s] = out
	return out


func _find(s: String, depth: int) -> String:
	if _map.has(s):
		return _map[s]
	if _upper.has(s):
		return _upper[s]
	if _lower.has(s):
		return _lower[s]
	if depth > 6:
		return _translit(s)
	# leading and trailing spaces kept around the text
	var st := s.strip_edges()
	if st != s and st != "":
		var a := s.find(st)
		return s.substr(0, a) + _find(st, depth + 1) + s.substr(a + st.length())
	# a format string with its values
	var cands: Array = _pat.get(s.substr(0, 2), []) + _pat_any
	for e in cands:
		var skip := false
		for sep in SEPS:   # «ПрАТ «%s»» must not swallow «ПрАТ «А» → ТОВ «Б»»: the parts go first
			if s.contains(sep) and not String(e[2]).contains(sep):
				skip = true
				break
		if skip:
			continue
		var m: RegExMatch = e[0].search(s)
		if m != null:
			return _fill(e[1], m, depth)
	# bbcode: the text between the tags
	if s.contains("[") and s.contains("]"):
		var rx := RegEx.create_from_string("\\[[^\\]]*\\]")
		var out := ""
		var pos := 0
		var any := false
		for m in rx.search_all(s):
			out += _part(s.substr(pos, m.get_start() - pos), depth)
			out += m.get_string()
			pos = m.get_end()
			any = true
		if any:
			return out + _part(s.substr(pos), depth)
	# a known head or tail with a known rest: «Дороги: » + a whole sentence that has a dash in it
	for h in _heads:
		if s.begins_with(h[0]) and _map.has(s.substr(h[0].length())):
			return h[1] + _map[s.substr(h[0].length())]
	for t_ in _tails:
		if s.ends_with(t_[0]) and _map.has(s.substr(0, s.length() - t_[0].length())):
			return _map[s.substr(0, s.length() - t_[0].length())] + t_[1]
	# parts joined by a separator
	for sep in ["\n", " · ", " — ", " → ", "; ", ", "]:
		if s.contains(sep):
			var ps := s.split(sep)
			var out := []
			for i in ps.size():
				var p: String = ps[i]
				# a part whose key holds the separator itself: «Інші кандидати · » + a price
				if i < ps.size() - 1 and _map.has(p + sep):
					out.append(String(_map[p + sep]).strip_edges(false, true).trim_suffix(sep.strip_edges()).strip_edges(false, true))
				else:
					out.append(_part(p, depth))
			return sep.join(out)
	# numbers, signs and punctuation around the words: «1. Внутрішні перевезення», «3 січня 2026», «★ Штаб»
	var m2 := _edges.search(s)
	if m2 != null and (m2.get_string(1) != "" or m2.get_string(3) != "") and m2.get_string(2) != "":
		return m2.get_string(1) + _part(m2.get_string(2), depth) + m2.get_string(3)
	# a known head or tail
	for h in _heads:
		if s.begins_with(h[0]):
			return h[1] + _part(s.substr(h[0].length()), depth)
	for t_ in _tails:
		if s.ends_with(t_[0]):
			return _part(s.substr(0, s.length() - t_[0].length()), depth) + t_[1]
	return _translit(s)


func _part(p: String, depth: int) -> String:
	if p == "" or _cy.search(p) == null:
		return p
	return _find(p, depth + 1)


## the English template with the captured values, a text value translated itself
func _fill(en: String, m: RegExMatch, depth: int) -> String:
	var out := ""
	var pos := 0
	var g := 1
	for sm in _spec.search_all(en):
		out += en.substr(pos, sm.get_start() - pos)
		var s := sm.get_string()
		if s == "%%":
			out += "%"
		else:
			var v := m.get_string(g) if g <= m.get_group_count() else ""
			out += _part(v, depth) if s.ends_with("s") else v
			g += 1
		pos = sm.get_end()
	return out + en.substr(pos)


func _units_en(s: String) -> String:
	if _cy.search(s) == null:
		return s
	for u in _units:
		s = u[0].sub(s, u[1], true)
	return s


# ---------- names: Ukrainian → Latin (the national transliteration of 2010) ----------
const TL := {"а": "a", "б": "b", "в": "v", "г": "h", "ґ": "g", "д": "d", "е": "e", "є": "ie", "ж": "zh", "з": "z", "и": "y", "і": "i",
	"ї": "i", "й": "i", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
	"х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ь": "", "ю": "iu", "я": "ia", "'": "", "’": ""}
const TL_FIRST := {"є": "ye", "ї": "yi", "й": "y", "ю": "yu", "я": "ya"}


static func _translit(s: String) -> String:
	var out := ""
	var start := true
	for ch in s:
		var lo := ch.to_lower()
		if TL.has(lo):
			var t_: String = TL_FIRST[lo] if start and TL_FIRST.has(lo) else TL[lo]
			if ch != lo and t_ != "":
				t_ = t_.substr(0, 1).to_upper() + t_.substr(1)
				if s == s.to_upper() and s.length() > 1:
					t_ = t_.to_upper()
			out += t_
			start = false
		else:
			out += ch
			start = not (ch.is_valid_identifier() or ch == "-")
	return out
