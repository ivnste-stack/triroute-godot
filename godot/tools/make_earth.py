#!/usr/bin/env python3
"""The Earth map (the "Земля" world): Natural Earth country polygons (public domain, naturalearthdata.com,
ne_10m_admin_0_countries_ukr.geojson) drawn in the Miller projection onto the 4×3 board (2400×1800 texture
pixels), the same data the HTML version's EARTH_DATA held (04b-earth.js), with more states:

  near   a label per pixel of a half-resolution grid (1200×900): state id + 1 on land, (id + 1) | 128 on the
         sea within 5 cells of a coast (the generator's noise moves coasts a little there), 0 further out: always sea; run-length coded
         (value, count ≤ 255 pairs) and base64
  seeds  a point inside every state (the label point of Natural Earth, or the point farthest from its border)
  names  Ukrainian names; pop: population in millions; dev: 0.15…1 from the GDP per head

At most 119 states (the generator keeps owners in an int8, 120+ is neutral land): the largest ones; a
smaller country gives its land to the neighbour nearest to each pixel, tiny islands far from any kept state
become sea.

the source: https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries_ukr.geojson
(the borders as Ukraine recognises them: Crimea is Ukrainian)
  cities a state's real cities (ne_10m_populated_places, NAME_UK): [name, x, y (texture pixels), population
         in millions, capital 0/1], the largest 120; the game gives every generated town the nearest one of a
         like size (MapView.earth_names)
  flags  simplified real flags (tools/earth_flags.py)

the places: https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places.geojson
usage: python3 tools/make_earth.py countries.geojson places.geojson assets/maps/earth.json [preview.png]
"""
import base64
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

W, H = 2400, 1800            # the 4×3 board's texture
GW, GH = W // 2, H // 2      # the stored grid
MAX_STATES = 119
MIN_AREA = 260               # texture pixels (a lattice square is 10×10): smaller countries are merged
LON0 = -169.0                # the map's west edge: Chukotka stays whole, the Aleutians' tail is cut
LAT_N, LAT_S = 84.0, -56.0
MX = 24                      # side margins (pixels)
SKIP = {"ATA", "ATF", "HMD", "SGS", "IOA", "ATC", "CSI", "CLP", "BVT"}
MERGE = {"SSD": "SDS", "SOL": "SOM", "CYN": "CYP", "KAS": "IND", "KOS": "SRB", "SAH": "SAH", "PSX": "ISR", "BJN": "COL", "SER": "COL",
         "USG": "CUB", "ESB": "CYP", "WSB": "CYP", "SCR": "CHN", "CNM": "CYP", "KAB": "KAZ", "ALD": "FIN"}
SHORT = {"CHN": "Китай", "COD": "ДР Конго", "COG": "Республіка Конго", "CAF": "ЦАР", "USA": "США", "GBR": "Велика Британія", "ARE": "ОАЕ",
         "DOM": "Домініканська Республіка", "BIH": "Боснія і Герцеговина", "PRK": "Північна Корея", "KOR": "Південна Корея",
         "ZAF": "ПАР", "SSD": "Південний Судан", "PNG": "Папуа Нова Гвінея", "GNQ": "Екваторіальна Гвінея", "CIV": "Кот-д'Івуар",
         "TLS": "Східний Тимор", "MKD": "Північна Македонія", "CZE": "Чехія", "RUS": "Росія", "IRN": "Іран", "SYR": "Сирія",
         "LAO": "Лаос", "VNM": "В'єтнам", "TZA": "Танзанія", "BOL": "Болівія", "VEN": "Венесуела", "MDA": "Молдова", "ESH": "Західна Сахара",
         "TWN": "Тайвань", "BRN": "Бруней", "SWZ": "Есватіні", "FLK": "Фолкленди", "NCL": "Нова Каледонія", "PRI": "Пуерто-Рико"}

K = (W - 2 * MX) / (2 * math.pi)   # pixels per radian


def miller(lat):
	f = math.radians(max(min(lat, 89.0), -89.0))
	return 1.25 * math.log(math.tan(math.pi / 4 + .4 * f))


OY = (H - (miller(LAT_N) - miller(LAT_S)) * K) / 2


def proj(lon, lat):
	if lon < LON0:
		lon += 360
	return MX + math.radians(lon - LON0) * K, OY + (miller(LAT_N) - miller(lat)) * K


def rings(geom):
	polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
	for poly in polys:
		yield poly[0]   # the outer ring: holes are filled by the countries inside them, drawn later


def main(src, places, out):
	feats = json.load(open(src, encoding="utf-8"))["features"]
	groups = {}   # code → {props, rings}
	for f in feats:
		p = f["properties"]
		code = p["ADM0_A3"]
		if code in SKIP or p.get("CONTINENT") == "Antarctica":
			continue
		code = MERGE.get(code, code)
		g = groups.setdefault(code, {"p": None, "rings": [], "pop": 0.0, "gdp": 0.0})
		if g["p"] is None or p["ADM0_A3"] == code:
			g["p"] = p
		g["pop"] += float(p.get("POP_EST") or 0)
		g["gdp"] += float(p.get("GDP_MD") or 0)
		for r in rings(f["geometry"]):
			pts = [proj(x, y) for x, y in r]
			# a ring that crosses the cut longitude (Chukotka, Fiji) is split by the projection: keep the side
			# with most of its points
			xs = [q[0] for q in pts]
			if max(xs) - min(xs) > W / 2:
				left = sum(1 for x in xs if x < W / 2)
				pts = [(x if (x < W / 2) == (left * 2 >= len(xs)) else (x - (W - 2 * MX) if x >= W / 2 else x + (W - 2 * MX)), y) for x, y in pts]
			g["rings"].append(pts)

	def ring_area(pts):
		a = 0.0
		for i in range(len(pts)):
			x1, y1 = pts[i - 1]
			x2, y2 = pts[i]
			a += x1 * y2 - x2 * y1
		return abs(a) / 2

	codes = sorted(groups, key=lambda c: -sum(ring_area(r) for r in groups[c]["rings"]))
	img = Image.new("I", (W, H), 0)
	dr = ImageDraw.Draw(img)
	for i, c in enumerate(codes):   # the largest first: enclaves (Lesotho, San Marino…) are drawn over them
		for r in groups[c]["rings"]:
			if len(r) >= 3:
				dr.polygon(r, fill=i + 1)
	lab = np.array(img, dtype=np.int32)
	# tiny islands
	land = lab > 0
	cc, n = ndimage.label(land)
	sizes = ndimage.sum(land, cc, range(1, n + 1))
	small = np.zeros(n + 1, bool)
	small[1:] = sizes < 40
	lab[small[cc]] = 0
	area = np.bincount(lab.ravel(), minlength=len(codes) + 1)
	order = [i for i in sorted(range(len(codes)), key=lambda i: -area[i + 1]) if area[i + 1] >= MIN_AREA][:MAX_STATES]
	keep = np.zeros(len(codes) + 1, np.int32)   # old label → new id + 1 (0: merged / sea)
	for k, i in enumerate(order):
		keep[i + 1] = k + 1
	new = keep[lab]
	# the land of the countries left out: to the nearest kept state, or the sea when far from all
	gone = (lab > 0) & (new == 0)
	dist, (iy, ix) = ndimage.distance_transform_edt(new == 0, return_indices=True)
	take = gone & (dist <= 30)
	new[take] = new[iy[take], ix[take]]
	print("states: %d of %d (smallest kept %d px); merged pixels %d, dropped %d" % (len(order), len(codes),
		area[order[-1] + 1], int(take.sum()), int((gone & ~take).sum())))
	# the half-resolution grid: the label at each cell's centre
	g = new[1::2, 1::2].astype(np.int32)
	dist, (iy, ix) = ndimage.distance_transform_edt(g == 0, return_indices=True)
	near = np.where(g > 0, g, np.where(dist <= 5, g[iy, ix] | 128, 0)).astype(np.uint8)
	# run-length code
	flat = near.ravel()
	buf = bytearray()
	i = 0
	while i < len(flat):
		v = flat[i]
		j = i
		while j < len(flat) and flat[j] == v and j - i < 255:
			j += 1
		buf += bytes([v, j - i])
		i = j
	names, seeds, pops, devs, isos = [], [], [], [], []
	for k, i in enumerate(order):
		c = codes[i]
		p = groups[c]["p"]
		m = g == k + 1
		# the largest piece, and in it the point farthest from the border (or Natural Earth's label point)
		cc, n = ndimage.label(m)
		if n == 0:
			m2 = new == k + 1
			ys, xs = np.nonzero(m2)
			sx, sy = int(xs.mean()) // 2, int(ys.mean()) // 2
		else:
			big = 1 + int(np.argmax(ndimage.sum(m, cc, range(1, n + 1))))
			piece = cc == big
			dt = ndimage.distance_transform_edt(piece)
			lx, ly = proj(float(p.get("LABEL_X") or 0), float(p.get("LABEL_Y") or 0))
			lx, ly = int(lx / 2), int(ly / 2)
			if 0 <= lx < GW and 0 <= ly < GH and piece[ly, lx] and dt[ly, lx] >= min(4, dt.max() * .5):
				sx, sy = lx, ly
			else:
				sy, sx = np.unravel_index(int(np.argmax(dt)), dt.shape)
		seeds.append([int(sx), int(sy)])
		names.append(SHORT.get(c) or p.get("NAME_UK") or p["NAME"])
		pop = groups[c]["pop"] / 1e6
		pops.append(round(max(pop, .05), 3))
		pc = groups[c]["gdp"] / max(groups[c]["pop"], 1) * 1e6   # US$ per head
		devs.append(round(min(1.0, max(.15, math.sqrt(max(0.0, (pc / 1000 - 3) / 59)))), 3))
		isos.append(c)
	# the cities of every kept state
	idx = {c: k for k, c in enumerate(isos)}
	cities = [[] for _ in isos]
	for f in json.load(open(places, encoding="utf-8"))["features"]:
		p = f["properties"]
		c = MERGE.get(p["ADM0_A3"], p["ADM0_A3"])
		if c not in idx:   # a country left out (merged into a neighbour): its cities are not used
			continue
		x, y = proj(float(p["LONGITUDE"]), float(p["LATITUDE"]))
		if not (0 <= x < W and 0 <= y < H):
			continue
		# Crimea is Ukraine (the borders of the Ukrainian point of view): its cities too, although the places
		# file lists them under Russia
		lon, lat = float(p["LONGITUDE"]), float(p["LATITUDE"])
		if c == "RUS" and 32.0 < lon < 36.7 and 44.2 < lat < 46.3 and "UKR" in idx:
			c = "UKR"
		nm = (p.get("NAME_UK") or p["NAME"]).strip()
		cities[idx[c]].append([nm, int(round(x)), int(round(y)), round(max(float(p["POP_MAX"] or 0), 1000) / 1e6, 3), 1 if p.get("ADM0CAP") else 0])
	for k in range(len(cities)):
		seen = set()
		L = []
		for e in sorted(cities[k], key=lambda e: (-e[4], -e[3])):
			if e[0] not in seen:
				seen.add(e[0])
				L.append(e)
		cities[k] = sorted(L, key=lambda e: (-e[4], -e[3]))[:120]
	# every state's seed (its capital town) at its real capital, when that stands on the state's own land
	moved = 0
	for k in range(len(isos)):
		caps = [e for e in cities[k] if e[4]]
		if not caps:
			continue
		cx, cy = caps[0][1] // 2, caps[0][2] // 2
		own = g == k + 1
		if not own.any():
			continue
		if not own[min(GH - 1, cy), min(GW - 1, cx)]:
			ys, xs = np.nonzero(own)
			j = int(np.argmin((xs - cx) ** 2 + (ys - cy) ** 2))
			if (xs[j] - cx) ** 2 + (ys[j] - cy) ** 2 > 100:
				continue
			cx, cy = int(xs[j]), int(ys[j])
		seeds[k] = [int(cx), int(cy)]
		moved += 1
	print("capitals as seeds: %d" % moved)
	import os
	sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
	from earth_flags import F as FLAGS
	flags = [FLAGS.get(c) for c in isos]
	print("cities: %d, states without any: %s; flags missing: %s" % (sum(len(c) for c in cities), [names[k] for k in range(len(isos)) if not cities[k]],
		[isos[k] for k in range(len(isos)) if not flags[k]]))
	data = {"w": GW, "h": GH, "mw": W, "mh": H, "names": names, "iso": isos, "seeds": seeds, "pop": pops, "dev": devs,
		"cities": cities, "flags": flags,
		"near": base64.b64encode(bytes(buf)).decode("ascii"),
		"source": "Natural Earth 1:10m admin 0 countries, Ukrainian point of view, and populated places (public domain), Miller projection"}
	with open(out, "w", encoding="utf-8") as fo:
		json.dump(data, fo, ensure_ascii=False, separators=(",", ":"))
	print("%s: %d bytes, %d states" % (out, len(json.dumps(data, ensure_ascii=False)), len(names)))
	if len(sys.argv) > 4:   # a preview of the grid
		pal = np.random.RandomState(3).randint(60, 255, (256, 3)).astype(np.uint8)
		pal[0] = (10, 30, 50)
		rgb = pal[np.where(near >= 128, 0, near)]
		rgb[(near >= 128)] = (20, 50, 80)
		Image.fromarray(rgb).save(sys.argv[4])


if __name__ == "__main__":
	main(sys.argv[1], sys.argv[2], sys.argv[3])
