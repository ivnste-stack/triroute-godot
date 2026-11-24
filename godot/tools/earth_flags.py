"""The flags of the Earth map's states, simplified: stripes, crosses, triangles, discs, stars and crescents, close
to the real ones but not exact. Every flag is a list of drawing operations on a 120×80 canvas, painted in
order (scripts/ui/flags.gd draws them):
  ["r", colour, x, y, w, h]          a rectangle
  ["p", colour, [x0, y0, x1, y1, …]] a polygon
  ["c", colour, x, y, r]             a disc
The first operation usually covers the whole flag; without one the background is transparent (Nepal).
"""
import math

R = "#ce1126"; DR = "#b22234"; CR = "#c8102e"
B = "#1f4fa0"; NB = "#012169"; LB = "#3d9be0"; SKY = "#75aadb"
W = "#f4f4f0"; Y = "#fcd116"; GO = "#f1bf00"
G = "#009b48"; DG = "#006a4e"
K = "#1b1b1b"; O = "#f77f00"; M = "#9e3039"


def h(cols, wts=None):
	wts = wts or [1] * len(cols)
	s = float(sum(wts))
	out, y = [], 0.0
	for c, w in zip(cols, wts):
		hh = 80 * w / s
		out.append(["r", c, 0, round(y, 2), 120, round(hh + .6, 2)])
		y += hh
	return out


def v(cols, wts=None):
	wts = wts or [1] * len(cols)
	s = float(sum(wts))
	out, x = [], 0.0
	for c, w in zip(cols, wts):
		ww = 120 * w / s
		out.append(["r", c, round(x, 2), 0, round(ww + .6, 2), 80])
		x += ww
	return out


def bg(c):
	return [["r", c, 0, 0, 120, 80]]


def rect(c, x, y, w, hh):
	return [["r", c, x, y, w, hh]]


def poly(c, pts):
	return [["p", c, [round(p, 2) for p in pts]]]


def disc(c, x, y, r):
	return [["c", c, x, y, r]]


def tri(c, depth=52):   # a triangle at the hoist
	return poly(c, [0, 0, depth, 40, 0, 80])


def star(c, x, y, r, rot=0.0):
	pts = []
	for i in range(10):
		rr = r if i % 2 == 0 else r * .4
		a = i * math.pi / 5 - math.pi / 2 + rot
		pts += [x + math.cos(a) * rr, y + math.sin(a) * rr]
	return poly(c, pts)


def crescent(c, back, x, y, r, dx=.38, dy=0.0):   # opens to the right (dx > 0)
	return disc(c, x, y, r) + disc(back, x + r * dx, y + r * dy, r * .82)


def nordic(c, inner=None, w=16, iw=8):
	cx = 44
	out = rect(c, cx - w / 2, 0, w, 80) + rect(c, 0, 40 - w / 2, 120, w)
	if inner:
		out += rect(inner, cx - iw / 2, 0, iw, 80) + rect(inner, 0, 40 - iw / 2, 120, iw)
	return out


def cross(c, w=14, cx=60, cy=40):
	return rect(c, cx - w / 2, 0, w, 80) + rect(c, 0, cy - w / 2, 120, w)


def band_up(c, w):   # a diagonal band from the bottom left to the top right
	k = w * .6
	return poly(c, [0, 80 - k, 120 - k * 1.5, 0, 120, 0, 120, k, k * 1.5, 80, 0, 80])


def band_down(c, w):   # from the top left to the bottom right
	k = w * .6
	return poly(c, [0, 0, k * 1.5, 0, 120, 80 - k, 120, 80, 120 - k * 1.5, 80, 0, k])


def stripes(c1, c2, n):
	return h([c1 if i % 2 == 0 else c2 for i in range(n)])


def half_disc(c, x, y, r, top=True):
	pts = []
	for i in range(17):
		a = math.pi * i / 16
		pts += [x + math.cos(a) * r, y - math.sin(a) * r if top else y + math.sin(a) * r]
	return poly(c, pts)


def union_canton(w=60, hh=40):   # the Union Jack in the top left quarter
	sx, sy = w / 120.0, hh / 80.0
	def sc(ops):
		out = []
		for o in ops:
			if o[0] == "r":
				out.append(["r", o[1], round(o[2] * sx, 2), round(o[3] * sy, 2), round(o[4] * sx, 2), round(o[5] * sy, 2)])
			elif o[0] == "p":
				out.append(["p", o[1], [round(p * (sx if i % 2 == 0 else sy), 2) for i, p in enumerate(o[2])]])
		return out
	return sc(UK)


UK = bg(NB) + band_up(W, 16) + band_down(W, 16) + band_up(CR, 6) + band_down(CR, 6) + cross(W, 22) + cross(CR, 12)


def us():
	out = stripes(DR, W, 13) + rect("#3c3b6e", 0, 0, 52, 43)
	for j in range(4):
		for i in range(5):
			out += star(W, 6 + i * 10 + (5 if j % 2 else 0), 6 + j * 10, 3)
	return out


F = {
	"RUS": h([W, "#0039a6", "#d52b1e"]),
	"CAN": v([R, W, R], [1, 2, 1]) + star(R, 60, 40, 17),
	"USA": us(),
	"GRL": h([W, R]) + half_disc(R, 45, 40, 18, True) + half_disc(W, 45, 40, 18, False),
	"CHN": bg("#de2910") + star("#ffde00", 20, 20, 12) + star("#ffde00", 40, 8, 4) + star("#ffde00", 48, 16, 4) + star("#ffde00", 48, 28, 4) + star("#ffde00", 40, 36, 4),
	"AUS": bg(NB) + union_canton() + star(W, 30, 62, 9) + star(W, 92, 18, 5) + star(W, 104, 38, 5) + star(W, 84, 46, 5) + star(W, 94, 66, 5),
	"BRA": bg("#009c3b") + poly("#ffdf00", [60, 8, 112, 40, 60, 72, 8, 40]) + disc("#002776", 60, 40, 17),
	"KAZ": bg("#00afca") + rect("#fec50c", 6, 0, 6, 80) + disc("#fec50c", 62, 36, 13),
	"ARG": h(["#74acdf", W, "#74acdf"]) + disc("#f6b40e", 60, 40, 7),
	"IND": h(["#ff9933", W, "#138808"]) + disc("#000080", 60, 40, 9) + disc(W, 60, 40, 7) + disc("#000080", 60, 40, 2),
	"MNG": v(["#c4272f", "#015197", "#c4272f"]) + rect("#f9cf02", 16, 22, 8, 36) + disc("#f9cf02", 20, 16, 4),
	"DZA": v(["#006233", W]) + crescent("#d21034", W, 60, 40, 20, .3) + star("#d21034", 70, 40, 8, -math.pi / 2),
	"MEX": v(["#006847", W, "#ce1126"]) + disc("#8c6239", 60, 40, 9),
	"COD": bg("#007fff") + band_up("#f7d618", 28) + band_up("#ce1021", 16) + star("#f7d618", 20, 18, 11),
	"SAU": bg("#006c35") + rect(W, 30, 24, 60, 8) + rect(W, 30, 50, 60, 4) + rect(W, 86, 46, 4, 10),
	"IRN": h(["#239f40", W, "#da0000"]) + disc("#da0000", 60, 40, 7),
	"NOR": bg("#ba0c2f") + nordic(W, "#00205b", 18, 9),
	"IDN": h(["#ce1126", W]),
	"LBY": h(["#e70013", K, "#239e46"], [1, 2, 1]) + crescent(W, K, 56, 40, 12, .35) + star(W, 68, 40, 5, -math.pi / 2),
	"SDN": h(["#d21034", W, K]) + tri("#007229", 46),
	"SWE": bg("#006aa7") + nordic("#fecc02"),
	"ZAF": rect("#e03c31", 0, 0, 120, 40) + rect("#001489", 0, 40, 120, 40) + poly(W, [0, 0, 22, 0, 54, 28, 120, 28, 120, 52, 54, 52, 22, 80, 0, 80])
		+ poly("#007749", [0, 6, 12, 6, 50, 34, 120, 34, 120, 46, 50, 46, 12, 74, 0, 74]) + tri("#ffb81c", 40) + poly(K, [0, 18, 31, 40, 0, 62]),
	"TCD": v(["#002664", "#fecb00", "#c60c30"]),
	"PER": v(["#d91023", W, "#d91023"]),
	"CHL": h([W, "#d52b1e"]) + rect("#0039a6", 0, 0, 40, 40) + star(W, 20, 20, 9),
	"MLI": v(["#14b53a", "#fcd116", "#ce1126"]),
	"AGO": h(["#cc092f", K]) + star("#ffcb00", 60, 40, 10),
	"FIN": bg(W) + nordic("#003580"),
	"NER": h(["#e05206", W, "#0db02b"]) + disc("#e05206", 60, 40, 8),
	"EGY": h(["#ce1126", W, K]) + disc("#c09300", 60, 40, 7),
	"TUR": bg("#e30a17") + crescent(W, "#e30a17", 44, 40, 19, .3) + star(W, 68, 40, 8, -math.pi / 2),
	"BOL": h(["#d52b1e", "#f9e300", "#007934"]),
	"COL": h(["#fcd116", "#003893", "#ce1126"], [2, 1, 1]),
	"MRT": bg("#006233") + rect("#d01c1f", 0, 0, 120, 10) + rect("#d01c1f", 0, 70, 120, 10) + disc("#ffc400", 60, 40, 17) + disc("#006233", 60, 33, 16) + star("#ffc400", 60, 30, 6),
	"PAK": v([W, "#01411c"], [1, 3]) + crescent(W, "#01411c", 80, 42, 18, .3, -.3) + star(W, 88, 30, 7),
	"ETH": h(["#078930", "#fcdd09", "#da121a"]) + disc("#0f47af", 60, 40, 15) + star("#fcdd09", 60, 40, 10),
	"UKR": h(["#0057b7", "#ffd700"]),
	"FRA": v(["#0055a4", W, "#ef4135"]),
	"VEN": h(["#ffcc00", "#00247d", "#cf142b"]) + star(W, 42, 38, 3) + star(W, 50, 32, 3) + star(W, 60, 30, 3) + star(W, 70, 32, 3) + star(W, 78, 38, 3),
	"NAM": bg("#003580") + poly("#009543", [120, 0, 120, 80, 0, 80]) + band_up(W, 26) + band_up("#d21034", 18) + star("#ffce00", 20, 18, 10),
	"NGA": v(["#008751", W, "#008751"]),
	"TZA": bg("#1eb53a") + poly("#00a3dd", [120, 0, 120, 80, 0, 80]) + band_up("#fcd116", 28) + band_up(K, 18),
	"AFG": v([K, "#be0000", "#007a36"]) + disc(W, 60, 40, 10) + disc("#be0000", 60, 40, 7),
	"MOZ": h(["#007168", W, K, W, "#fce100"], [6, 1, 6, 1, 6]) + tri("#d21034", 46) + star("#fce100", 15, 40, 9),
	"ZMB": bg("#198a00") + rect("#de2010", 78, 32, 14, 48) + rect(K, 92, 32, 14, 48) + rect("#ef7d00", 106, 32, 14, 48) + star("#ef7d00", 99, 16, 8),
	"ESP": h(["#aa151b", "#f1bf00", "#aa151b"], [1, 2, 1]) + rect("#aa151b", 30, 30, 12, 20),
	"MMR": h(["#fecb00", "#34b233", "#ea2839"]) + star(W, 60, 42, 24),
	"TKM": bg("#00843d") + rect("#d22630", 18, 0, 20, 80) + crescent(W, "#00843d", 56, 22, 10, .35) + star(W, 66, 16, 3) + star(W, 72, 24, 3) + star(W, 66, 30, 3),
	"MAR": bg("#c1272d") + star("#006233", 60, 40, 17),
	"DEU": h([K, "#dd0000", "#ffce00"]),
	"UZB": h(["#0099b5", "#ce1126", W, "#ce1126", "#1eb53a"], [10, 1, 8, 1, 10]) + crescent(W, "#0099b5", 16, 14, 8, .35),
	"MDG": rect(W, 0, 0, 40, 80) + rect("#fc3d32", 40, 0, 80, 40) + rect("#007e3a", 40, 40, 80, 40),
	"POL": h([W, "#dc143c"]),
	"BWA": h(["#75aadb", W, K, W, "#75aadb"], [9, 1, 4, 1, 9]),
	"SOM": bg("#4189dd") + star(W, 60, 40, 20),
	"SDS": h([K, W, "#da121a", W, "#078930"], [6, 1, 6, 1, 6]) + tri("#0f47af", 46) + star("#fcdd09", 15, 40, 9),
	"CAF": h(["#003082", W, "#289728", "#ffce00"]) + rect("#d21034", 52, 0, 16, 80) + star("#ffce00", 18, 10, 7),
	"GBR": UK,
	"JPN": bg(W) + disc("#bc002d", 60, 40, 22),
	"KEN": h([K, W, "#bb0000", W, "#006600"], [6, 1, 6, 1, 6]) + poly(W, [60, 12, 74, 40, 60, 68, 46, 40]) + poly("#bb0000", [60, 16, 71, 40, 60, 64, 49, 40]),
	"IRQ": h(["#ce1126", W, K]) + rect("#007a3d", 42, 36, 36, 8),
	"THA": h(["#a51931", W, "#2d2a4a", W, "#a51931"], [1, 1, 2, 1, 1]),
	"ITA": v(["#009246", W, "#ce2b37"]),
	"PNG": bg(K) + poly("#ce1126", [0, 0, 120, 0, 120, 80]) + star("#fcd116", 86, 24, 12) + star(W, 22, 46, 4) + star(W, 32, 58, 4) + star(W, 16, 64, 4) + star(W, 28, 72, 3),
	"YEM": h(["#ce1126", W, K]),
	"CMR": v(["#007a5e", "#ce1126", "#fcd116"]) + star("#fcd116", 60, 40, 10),
	"BLR": h(["#c8313e", "#4aa657"], [2, 1]) + rect(W, 0, 0, 16, 80) + rect("#c8313e", 4, 6, 8, 8) + rect("#c8313e", 4, 24, 8, 8) + rect("#c8313e", 4, 42, 8, 8) + rect("#c8313e", 4, 60, 8, 8),
	"PRY": h(["#d52b1e", W, "#0038a8"]) + disc("#0038a8", 60, 40, 8) + disc(W, 60, 40, 6) + star("#fcd116", 60, 40, 4),
	"NZL": bg(NB) + union_canton() + star(W, 90, 22, 8) + star("#c8102e", 90, 22, 5.5) + star(W, 80, 40, 8) + star("#c8102e", 80, 40, 5.5)
		+ star(W, 102, 36, 7) + star("#c8102e", 102, 36, 4.5) + star(W, 90, 62, 8) + star("#c8102e", 90, 62, 5.5),
	"ZWE": h(["#319208", "#ffd200", "#d40000", K, "#d40000", "#ffd200", "#319208"]) + poly(K, [0, 0, 56, 40, 0, 80]) + tri(W, 52) + star("#d40000", 18, 40, 9),
	"ISL": bg("#02529c") + nordic(W, "#dc1e35", 18, 9),
	"ROU": v(["#002b7f", "#fcd116", "#ce1126"]),
	"PHL": h(["#0038a8", "#ce1126"]) + tri(W, 62) + disc("#fcd116", 20, 40, 7) + star("#fcd116", 6, 8, 3) + star("#fcd116", 6, 72, 3) + star("#fcd116", 50, 40, 3),
	"MYS": stripes("#cc0001", W, 14) + rect("#010066", 0, 0, 60, 46) + crescent("#ffcc00", "#010066", 22, 23, 14, .35) + star("#ffcc00", 40, 23, 9),
	"OMN": rect(W, 40, 0, 80, 27) + rect("#db161b", 40, 27, 80, 26) + rect("#008000", 40, 53, 80, 27) + rect("#db161b", 0, 0, 40, 80) + disc(W, 18, 16, 7),
	"VNM": bg("#da251d") + star("#ffff00", 60, 42, 24),
	"COG": bg("#009543") + poly("#dc241f", [120, 0, 120, 80, 0, 80]) + band_up("#fbde4a", 28),
	"KGZ": bg("#e8112d") + disc("#ffef00", 60, 40, 20) + disc("#e8112d", 60, 40, 12) + disc("#ffef00", 60, 40, 9),
	"CIV": v(["#f77f00", W, "#009e60"]),
	"BFA": h(["#ef2b2d", "#009e49"]) + star("#fcd116", 60, 40, 12),
	"GAB": h(["#009e60", "#fcd116", "#3a75c4"]),
	"LAO": h(["#ce1126", "#002868", "#ce1126"], [1, 2, 1]) + disc(W, 60, 40, 13),
	"ECU": h(["#ffd100", "#0072ce", "#ef3340"], [2, 1, 1]) + disc("#8c6b3d", 60, 40, 9) + disc("#4b9cd3", 60, 40, 5),
	"SYR": h(["#ce1126", W, K]) + star("#007a3d", 44, 40, 7) + star("#007a3d", 76, 40, 7),
	"UGA": h([K, "#fcdc04", "#d90000", K, "#fcdc04", "#d90000"]) + disc(W, 60, 40, 13) + disc("#9ca69c", 60, 40, 5),
	"GIN": v(["#ce1126", "#fcd116", "#009460"]),
	"URY": stripes(W, "#0038a8", 9) + rect(W, 0, 0, 48, 44) + disc("#fcd116", 24, 22, 11),
	"GHA": h(["#ce1126", "#fcd116", "#006b3f"]) + star(K, 60, 40, 11),
	"GRC": stripes("#0d5eaf", W, 9) + rect("#0d5eaf", 0, 0, 44, 44) + rect(W, 17.5, 0, 9, 44) + rect(W, 0, 17.5, 44, 9),
	"TJK": h(["#cc0000", W, "#006600"], [2, 3, 2]) + poly("#f8c300", [50, 42, 54, 32, 60, 38, 66, 32, 70, 42]) + star("#f8c300", 60, 28, 3),
	"TUN": bg("#e70013") + disc(W, 60, 40, 20) + crescent("#e70013", W, 58, 40, 15, .3) + star("#e70013", 66, 40, 7, -math.pi / 2),
	"GUY": bg("#009e49") + poly(W, [0, 0, 120, 40, 0, 80]) + poly("#fcd116", [0, 4, 112, 40, 0, 76]) + poly(K, [0, 0, 62, 40, 0, 80]) + poly("#ce1126", [0, 4, 55, 40, 0, 76]),
	"SEN": v(["#00853f", "#fdef42", "#e31b23"]) + star("#00853f", 60, 40, 11),
	"PRK": h(["#024fa2", W, "#ed1c27", W, "#024fa2"], [4, 1, 13, 1, 4]) + disc(W, 40, 40, 13) + star("#ed1c27", 40, 40, 12),
	"KHM": h(["#032ea1", "#e00025", "#032ea1"], [1, 2, 1]) + poly(W, [36, 54, 40, 36, 48, 36, 52, 26, 56, 36, 60, 22, 64, 36, 68, 26, 72, 36, 80, 36, 84, 54]),
	"NPL": poly("#003893", [0, 0, 100, 42, 44, 42, 104, 80, 0, 80]) + poly("#dc143c", [4, 7, 86, 38, 32, 38, 90, 76, 4, 76]) + disc(W, 26, 30, 7) + disc("#dc143c", 26, 26, 7) + star(W, 26, 60, 9),
	"BGR": h([W, "#00966e", "#d62612"]),
	"BGD": bg("#006a4e") + disc("#f42a41", 54, 40, 20),
	"IRL": v(["#169b62", W, "#ff883e"]),
	"LTU": h(["#fdb913", "#006a44", "#c1272d"]),
	"CZE": h([W, "#d7141a"]) + tri("#11457e", 60),
	"LVA": h(["#9e3039", W, "#9e3039"], [2, 1, 2]),
	"HUN": h(["#ce2939", W, "#477050"]),
	"SUR": h(["#377e3f", W, "#b40a2d", W, "#377e3f"], [2, 1, 4, 1, 2]) + star("#ecc81d", 60, 40, 11),
	"AUT": h(["#ed2939", W, "#ed2939"]),
	"KOR": bg(W) + half_disc("#cd2e3a", 60, 40, 19, True) + half_disc("#0047a0", 60, 40, 19, False) + disc("#cd2e3a", 50.5, 40, 9.5) + disc("#0047a0", 69.5, 40, 9.5)
		+ poly(K, [14, 20, 28, 8, 32, 12, 18, 24]) + poly(K, [88, 8, 102, 20, 98, 24, 84, 12]) + poly(K, [14, 60, 18, 56, 32, 68, 28, 72]) + poly(K, [98, 56, 102, 60, 88, 72, 84, 68]),
	"PRT": v(["#006600", "#ff0000"], [2, 3]) + disc("#ffcc00", 48, 40, 15) + disc("#ff0000", 48, 40, 10) + disc(W, 48, 40, 7),
	"CUB": stripes("#002a8f", W, 5) + tri("#cf142b", 56) + star(W, 18, 40, 9),
	"SRB": h(["#c6363c", "#0c4076", W]) + poly("#c6363c", [30, 24, 50, 24, 50, 46, 40, 54, 30, 46]) + disc(W, 40, 36, 4),
	"EST": h(["#0072ce", K, W]),
	"ERI": rect("#12ad2b", 0, 0, 120, 40) + rect("#4189dd", 0, 40, 120, 40) + poly("#ea0437", [0, 0, 120, 40, 0, 80]) + disc("#ffc726", 28, 40, 11) + disc("#ea0437", 28, 40, 8),
	"MWI": h([K, "#ce1126", "#339e35"]) + half_disc("#ce1126", 60, 27, 14, True),
	"AZE": h(["#00b5e2", "#ef3340", "#509e2f"]) + crescent(W, "#ef3340", 56, 40, 11, .35) + star(W, 70, 40, 5),
	"NIC": h(["#0067c6", W, "#0067c6"]) + poly("#4ba85e", [52, 46, 68, 46, 60, 33]) + poly("#c8a400", [54, 46, 66, 46, 60, 38]),
	"DNK": bg("#c8102e") + nordic(W),
	"SAH": h([K, W, "#007a3d"]) + tri("#c4111b", 46) + crescent("#c4111b", W, 60, 40, 9, .35) + star("#c4111b", 69, 40, 4, -math.pi / 2),
	"HND": h(["#0073cf", W, "#0073cf"]) + star("#0073cf", 60, 40, 4) + star("#0073cf", 46, 34, 3) + star("#0073cf", 74, 34, 3) + star("#0073cf", 46, 46, 3) + star("#0073cf", 74, 46, 3),
	"GTM": v(["#4997d0", W, "#4997d0"]) + disc("#6c9a46", 60, 40, 9) + disc(W, 60, 40, 6),
	"GEO": bg(W) + cross("#ff0000", 14) + sum((rect("#ff0000", cx - 2, cy - 8, 4, 16) + rect("#ff0000", cx - 8, cy - 2, 16, 4)
		for cx, cy in [(26, 17), (94, 17), (26, 63), (94, 63)]), []),
}
