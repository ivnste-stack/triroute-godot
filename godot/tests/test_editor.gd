extends RefCounted
## The map editor's world (MapEditor.build_world, TRWorldGen.edit_apply / generate_board_given / edit_path):
## an edit of a generated world — a new state painted out into the sea, an island erased, settlements and a
## drawn road — makes a playable world, and the same edit on a fresh generator of the same seed makes the
## very same world again (that is how a saved game of an edited world is loaded).


## a new state: a disc of triangles in the open sea; an island erased; three settlements and a road
func _edit(gen: Object, w: Dictionary) -> Dictionary:
	var ed := MapEditor.new()
	ed.MW = w.mw
	ed.MH = w.mh
	ed.TS = w.tri_s
	ed.SQW = w.sqw
	ed.SQH = w.sqh
	ed.WX = w.mw / 80.0
	ed.WZ = w.mh / 80.0
	ed.NX = w.board.nx
	ed.NZ = w.board.nz
	ed.ST = w.board.st
	ed.gen = gen
	ed.sqd = PackedByteArray(w.sqd)
	ed.sql = PackedInt32Array(w.sql)
	for st in w.states:
		ed.S.append({"name": st.name, "color": st.color, "pop": st.pop})
	for t in w.board.towns:
		ed.towns.append({"x": t.x, "z": t.z, "type": t.type, "name": t.name, "pop": t.pop, "port_ov": -1, "air_ov": false, "cid": t.cid})
	# the open sea farthest from any land, on a coarse scan
	var best := Vector2.ZERO
	var bd := -1.0
	for j in range(4, ed.SQH - 4, 3):
		for i in range(4, ed.SQW - 4, 3):
			var c := Vector2(-ed.WX / 2 + (i + .5) * ed.SQ, -ed.WZ / 2 + (j + .5) * ed.SQ)
			var d := 1e9
			for t in w.board.towns:
				d = minf(d, c.distance_to(Vector2(t.x, t.z)))
			if ed.own_at(c.x, c.y) < 0 and d > bd:
				bd = d
				best = c
	var id := ed.new_state()
	ed.brush = 5
	for a in 12:
		ed.paint_w(best + Vector2(cos(a * TAU / 12), sin(a * TAU / 12)) * .35, id)
	ed.paint_w(best, id)
	# the smallest island goes
	var seen := {}
	var small: PackedInt32Array = PackedInt32Array()
	for t in ed.sql.size():
		if ed.sql[t] >= 0 and ed.sql[t] != id and not seen.has(t):
			var L := ed.island(t)
			for q in L:
				seen[q] = true
			if small.is_empty() or L.size() < small.size():
				small = L
	for q in small:
		ed.sql[q] = -1
	var d: Dictionary = gen.edit_apply(ed.sqd, ed.sql, ed.S.size(), PackedInt32Array())
	ed.own = d.own
	ed.countries = d.countries
	ed._fix_towns()
	var t1: Variant = ed.add_town(best + Vector2(-.3, 0), "city")
	var t2: Variant = ed.add_town(best + Vector2(.35, .1), "town")
	ed.add_town(best + Vector2(0, -.3), "vil")
	ed.road_mode = "main"
	ed.roads = []
	for r in w.board.roads:
		ed.roads.append({"lv": r.lv, "p": PackedFloat32Array(r.p)})
	var ok := t1 != null and t2 != null and ed._road_add(ed.node_at(Vector2(t1.x, t1.z)), ed.node_at(Vector2(t2.x, t2.z)))
	var e := ed.make_edit()
	e["_ok"] = ok
	e["_alive"] = d.countries.filter(func(c): return c.area > 0).size()   # the erased island may have been a whole state
	e["_island"] = small.size()
	ed.free()
	return e


func _fp(w: Dictionary) -> String:
	var parts := [PackedByteArray(w.own).hex_encode().md5_text(), w.states.size()]
	for s in w.states:
		parts.append(s.name)
	for t in w.board.towns:
		parts.append("%s|%s|%.4f|%.4f|%d|%.6f|%s" % [t.name, t.type, t.x, t.z, t.cid, t.pop, t.port])
	for r in w.board.roads:
		parts.append(PackedFloat32Array(r.p).size())
	parts.append(PackedByteArray(w.board.bits).hex_encode().md5_text())
	parts.append(w.board.checkpoints.size())
	return str(parts).md5_text()


func test_edited_world_is_playable_and_made_again() -> String:
	if not ClassDB.class_exists("TRWorldGen"):
		return "no native module"
	var gen: Object = ClassDB.instantiate("TRWorldGen")
	var w: Dictionary = gen.generate(777)
	w["states"] = gen.generate_states()
	w["board"] = gen.generate_board()
	var e := _edit(gen, w)
	if not e._ok:
		return "the road between the new towns was not laid"
	e.erase("_ok")
	var isl: int = e._island
	e.erase("_island")
	var alive: int = e._alive
	e.erase("_alive")
	var n: int = e.states.size()
	if n != alive:
		return "states: %d, expected %d" % [n, alive]
	# the world of the edit on the same generator, then on a fresh one of the same seed
	var a := MapEditor.build_world(gen, w, e.duplicate(true))
	var g2: Object = ClassDB.instantiate("TRWorldGen")
	var w2: Dictionary = g2.generate(777)
	var b := MapEditor.build_world(g2, w2, a.edit.duplicate(true))
	if _fp(a) != _fp(b):
		return "the same edit made another world"
	# every state has land and a capital; the new state has its settlements and the drawn road is there
	var caps := {}
	for t in a.board.towns:
		if t.type == "cap":
			caps[t.cid] = true
	for c in a.countries:
		if c.area <= 0:
			return "state %d has no land" % c.idx
		if not caps.has(c.idx):
			return "state %d (%s) has no capital" % [c.idx, a.states[c.idx].name]
	var mine: Array = a.board.towns.filter(func(t): return t.cid == n - 1)
	if mine.size() < 3:
		return "the new state has %d settlements" % mine.size()
	if a.states[n - 1].name != e.states[n - 1].name:
		return "the new state's name was not kept"
	var mains: Array = a.board.roads.filter(func(r): return r.lv >= 3)
	if mains.is_empty():
		return "the drawn motorway is missing"
	# a route on the edited board between the new state's towns
	var i0: int = a.board.towns.find(mine[0])
	var i1: int = a.board.towns.find(mine[1])
	if gen.route("road", i0, i1).size() < 4:
		return "no road route inside the new state"
	print("       edited world: %d states, %d towns, an island of %d triangles erased, %d roads" % [n, a.board.towns.size(), isl, a.board.roads.size()])
	return ""
