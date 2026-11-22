// Port of genWorld() from legacy/src/04-map.js (logistics board: big:true, tri:true, square lattice).
// Every RNG call happens in the same order as in the JS original and arrays that are Float32Array / Int8Array
// there are float / int8_t here, so the result is the same world bit for bit.
#include "worldgen.h"

#include <array>
#include <unordered_map>
#include "jsmath.h"
#include "rng.h"

#include <algorithm>
#include <cmath>
#include <functional>
#include <utility>

namespace tr {

namespace {

struct Blob { double x, y, r, w; bool pen; };
struct Isl { double x, y, r, w; };
struct Seg5 { double a, b, c, d, r; };
struct Seg4 { double a, b, c, d; };
struct Arm { std::vector<Seg5> segs; double bx, ex, by, ey; };
struct Range { std::vector<Seg4> segs; double w, h, bx, ex, by, ey; };
struct Sea { double x, y, rx, ry, ca, sa, d; };

template <class S>
double seg_d(double x, double y, const S &s) {
	double vx = s.c - s.a, vy = s.d - s.b, wx = x - s.a, wy = y - s.b;
	double t = clampd((wx * vx + wy * vy) / (vx * vx + vy * vy), 0, 1);
	double dx = wx - vx * t, dy = wy - vy * t;
	return dx * dx + dy * dy;
}

// insertion-ordered small counter (JS Map semantics for iteration order)
struct OrderedCount {
	std::vector<std::pair<int, int>> v;
	int &operator[](int k) {
		for (auto &e : v)
			if (e.first == k) return e.second;
		v.push_back({k, 0});
		return v.back().second;
	}
};

void sq_build(World &w, const std::vector<int8_t> &src) {
	const int MW = w.p.mw, MH = w.p.mh, S = w.p.tri_s;
	w.sqw = (MW + S - 1) / S;
	w.sqh = (MH + S - 1) / S;
	const int SQW = w.sqw, SQH = w.sqh;
	w.sqd.assign(size_t(SQW) * SQH, 0);
	w.sql.assign(size_t(SQW) * SQH * 2, 0);
	auto at = [&](double x, double y) {
		int xi = clampi(int(std::floor(x)), 0, MW - 1), yi = clampi(int(std::floor(y)), 0, MH - 1);
		return int(src[size_t(yi) * MW + xi]);
	};
	std::vector<int16_t> C(size_t(SQW) * SQH);
	// 1. majority label of the square (first label to reach the top count wins, like the JS Map scan)
	for (int j = 0; j < SQH; j++)
		for (int i = 0; i < SQW; i++) {
			OrderedCount m;
			int b = -1, bv = -1;
			for (int v = 0; v < 4; v++)
				for (int u = 0; u < 4; u++) {
					int o = at((i + (u + .5) / 4) * S, (j + (v + .5) / 4) * S);
					int c = ++m[o];
					if (c > bv) { bv = c; b = o; }
				}
			C[size_t(j) * SQW + i] = int16_t(b);
		}
	auto L = [&](int i, int j) { return i < 0 || j < 0 || i >= SQW || j >= SQH ? -1 : int(C[size_t(j) * SQW + i]); };
	// 2. one-cell spikes and pits take the label of 3+ agreeing neighbours
	for (int it = 0; it < 3; it++) {
		std::vector<int16_t> Sv = C;
		auto Ls = [&](int i, int j) { return i < 0 || j < 0 || i >= SQW || j >= SQH ? -1 : int(Sv[size_t(j) * SQW + i]); };
		int ch = 0;
		for (int j = 0; j < SQH; j++)
			for (int i = 0; i < SQW; i++) {
				int c = Sv[size_t(j) * SQW + i];
				int nb[4] = {Ls(i, j - 1), Ls(i + 1, j), Ls(i, j + 1), Ls(i - 1, j)};
				OrderedCount cnt;
				for (int q : nb)
					if (q != c) cnt[q]++;
				for (auto &e : cnt.v)
					if (e.second >= 3) { C[size_t(j) * SQW + i] = int16_t(e.first); ch++; break; }
			}
		if (!ch) break;
	}
	// 3. staircase corners get a diagonal
	for (int j = 0; j < SQH; j++)
		for (int i = 0; i < SQW; i++) {
			size_t k = size_t(j) * SQW + i;
			int c = C[k], n = L(i, j - 1), e = L(i + 1, j), so = L(i, j + 1), wv = L(i - 1, j), ne = L(i + 1, j - 1), se = L(i + 1, j + 1), sw = L(i - 1, j + 1), nw = L(i - 1, j - 1);
			int d = 0, h0 = c, h1 = c;
			if (n == e && n < c && so == c && wv == c && ne == n) { d = 1; h0 = n; }
			else if (e == so && e < c && n == c && wv == c && se == e) { d = 0; h1 = e; }
			else if (so == wv && so < c && n == c && e == c && sw == so) { d = 1; h1 = so; }
			else if (wv == n && wv < c && e == c && so == c && nw == wv) { d = 0; h0 = wv; }
			w.sqd[k] = uint8_t(d);
			w.sql[k * 2] = int16_t(h0);
			w.sql[k * 2 + 1] = int16_t(h1);
		}
}

} // namespace

World generate_world(uint32_t seed, const WorldParams &p) {
	World w;
	w.p = p;
	w.seed = seed;
	const int MW = p.mw, MH = p.mh;
	Mulberry rng(seed);
	Perlin noise(rng);
	auto fbm = [&](double x, double y, int o) {
		double s = 0, a = 1, f = 1, n = 0;
		for (int i = 0; i < o; i++) { s += a * noise(x * f, y * f); n += a; a *= .5; f *= 2.03; }
		return s / n;
	};
	const double iS = 2.15;
	std::vector<Blob> blobs;
	std::vector<Isl> isl;
	std::vector<std::pair<double, double>> centers;
	const int nC = 7 + int(std::floor(rng() * 4));
	const int nMaj = 2 + (rng() < .5 ? 1 : 0);
	for (int t = 0; int(centers.size()) < nMaj && t < 2000; t++) {
		double x = (.42 + rng() * .96) * iS;
		double y = (.32 + rng() * .36) * iS;
		bool ok = true;
		for (auto &c : centers)
			if (!(js_hypot(c.first - x, c.second - y) > 1.05 - t * .0004)) { ok = false; break; }
		if (ok) centers.push_back({x, y});
	}
	for (int t = 0; int(centers.size()) < nC && t < 1600; t++) {
		double x = (.24 + rng() * 1.12) * iS;
		double y = (.2 + rng() * .6) * iS;
		bool ok = true;
		for (size_t i = 0; i < centers.size(); i++)
			if (!(js_hypot(centers[i].first - x, centers[i].second - y) > (int(i) < nMaj ? .72 : .46) - t * .0003)) { ok = false; break; }
		if (ok) centers.push_back({x, y});
	}
	for (size_t ci = 0; ci < centers.size(); ci++) {
		const bool maj = int(ci) < nMaj;
		double size = maj ? .21 + rng() * .09 : .08 + rng() * .09;
		double a = rng() * PI * 2, x = centers[ci].first, y = centers[ci].second;
		int k = maj ? 7 + int(std::floor(rng() * 5)) : 3 + int(std::floor(rng() * 5));
		double stp = maj ? .78 : 1;
		for (int j = 0; j < k; j++) {
			double r = size * (.6 + rng() * .65);
			blobs.push_back({x, y, r, .95 + rng() * .35, false});
			if (rng() < .4) {
				double sg = rng() < .5 ? 1 : -1;
				double pa = a + sg * (.9 + rng() * 1.1);
				double bx = x + std::cos(pa) * r * 1.25, by = y + std::sin(pa) * r * 1.25;
				blobs.push_back({bx, by, r * (.3 + rng() * .35), .95, true});
			}
			a += (rng() - .5) * (maj ? 1.9 : 1.3);
			x += std::cos(a) * r * stp;
			y += std::sin(a) * r * stp;
		}
	}
	const int nA = 6 + int(std::floor(rng() * 4));
	for (int t = 0, n = 0; n < nA && t < 800; t++) {
		double x = (.14 + rng() * 1.32) * iS;
		double y = (.14 + rng() * .72) * iS;
		bool hit = false;
		for (auto &b : blobs)
			if (js_hypot(b.x - x, b.y - y) < b.r + .12) { hit = true; break; }
		if (hit) continue;
		n++;
		double ang = rng() * PI, el = 1.2 + rng() * 2, ca = std::cos(ang), sa = std::sin(ang);
		auto put = [&](double g1, double g2, double r, double wv) { isl.push_back({x + ca * g1 - sa * g2, y + sa * g1 + ca * g2, r, wv}); };
		put(0, 0, .03 + rng() * .035, 1.35);
		int mid = 2 + int(std::floor(rng() * 4));
		for (int j = 0; j < mid; j++) {
			double d = .05 + rng() * .08, aa = rng() * 6.283;
			double g1 = std::cos(aa) * d * 1.3, g2 = std::sin(aa) * d / el;
			put(g1, g2, .012 + rng() * .012, 1.35);
		}
		double sp = .06 + rng() * .08;
		int cnt = 16 + int(std::floor(rng() * 26));
		for (int j = 0; j < cnt; j++) {
			double r1 = rng(), r2 = rng();
			double g1 = (r1 + r2 - 1) * sp * 1.6;
			double r3 = rng(), r4 = rng();
			double g2 = (r3 + r4 - 1) * sp / el;
			put(g1, g2, .004 + rng() * .009, 1.45);
		}
	}
	const int nI = 28 + int(std::floor(rng() * 16));
	for (int t = 0, n = 0; n < nI && t < 900; t++) {
		double x = (.08 + rng() * 1.44) * iS;
		double y = (.08 + rng() * .84) * iS;
		bool hit = false;
		for (auto &b : blobs)
			if (js_hypot(b.x - x, b.y - y) < b.r + .07) { hit = true; break; }
		if (hit) continue;
		n++;
		isl.push_back({x, y, .008 + rng() * .026, 1.3});
	}
	// curved arms
	std::vector<Arm> arms;
	std::vector<Blob> mainB;
	for (auto &b : blobs)
		if (!b.pen) mainB.push_back(b);
	const int nArm = 10 + int(std::floor(rng() * 8));
	for (int k = 0; k < nArm && !mainB.empty(); k++) {
		const Blob &b = mainB[size_t(std::floor(rng() * mainB.size()))];
		double a = rng() * 6.283;
		double px = b.x + std::cos(a) * b.r * .7, py = b.y + std::sin(a) * b.r * .7;
		Arm A;
		int n = 7 + int(std::floor(rng() * 6));
		double L = .14 + rng() * .26, r0 = .018 + rng() * .022, bend = (rng() - .5) * .9;
		for (int q = 0; q < n; q++) {
			a += bend + (rng() - .5) * .5;
			double qx = px + std::cos(a) * L / n, qy = py + std::sin(a) * L / n;
			A.segs.push_back({px, py, qx, qy, r0 * (1 - double(q) / n * .6)});
			px = qx;
			py = qy;
		}
		double mnx = INFINITY, mxx = -INFINITY, mny = INFINITY, mxy = -INFINITY;
		for (auto &s : A.segs) {
			mnx = std::min(mnx, std::min(s.a, s.c)); mxx = std::max(mxx, std::max(s.a, s.c));
			mny = std::min(mny, std::min(s.b, s.d)); mxy = std::max(mxy, std::max(s.b, s.d));
		}
		A.bx = mnx - .05; A.ex = mxx + .05; A.by = mny - .05; A.ey = mxy + .05;
		arms.push_back(std::move(A));
	}
	// mountain ranges
	std::vector<Range> ranges;
	for (auto &b : blobs) {
		if (b.pen) continue;
		int k = rng() < .38 ? 1 : 0;
		for (int r = 0; r < k; r++) {
			double a = rng() * PI * 2;
			double px = b.x + (rng() - .5) * b.r;
			double py = b.y + (rng() - .5) * b.r * .8;
			Range R;
			double L = b.r * (1.3 + rng() * 1.5);
			const int n = 10;
			for (int q = 0; q < n; q++) {
				a += (rng() - .5) * .65;
				double qx = px + std::cos(a) * L / n, qy = py + std::sin(a) * L / n;
				R.segs.push_back({px, py, qx, qy});
				px = qx;
				py = qy;
			}
			R.w = .026 + rng() * .026;
			R.h = .75 + rng() * .45;
			double mnx = INFINITY, mxx = -INFINITY, mny = INFINITY, mxy = -INFINITY;
			for (auto &s : R.segs) {
				mnx = std::min(mnx, std::min(s.a, s.c)); mxx = std::max(mxx, std::max(s.a, s.c));
				mny = std::min(mny, std::min(s.b, s.d)); mxy = std::max(mxy, std::max(s.b, s.d));
			}
			R.bx = mnx - .2; R.ex = mxx + .2; R.by = mny - .2; R.ey = mxy + .2;
			ranges.push_back(std::move(R));
		}
	}
	// inner seas & gulfs
	std::vector<Sea> seas;
	const int nsea = 4 + int(std::floor(rng() * 4));
	for (int i = 0; i < nsea; i++) {
		const Blob &b = blobs[size_t(std::floor(rng() * blobs.size()))];
		double rx = .04 + rng() * .1;
		Sea S;
		S.x = b.x + (rng() - .5) * b.r * 1.4;
		S.y = b.y + (rng() - .5) * b.r * 1.2;
		S.rx = rx;
		S.ry = rx * (.25 + rng() * .6);
		S.ca = std::cos(rng() * PI);
		S.sa = 0;
		S.d = .9 + rng() * .5;
		S.sa = std::sqrt(1 - S.ca * S.ca) * (rng() < .5 ? 1 : -1);
		seas.push_back(S);
	}
	// low-res height
	const int LW = MW / 2, LH = MH / 2;
	w.low.assign(size_t(LW) * LH, 0);
	w.low_m.assign(size_t(LW) * LH, 0);
	for (int y = 0; y < LH; y++)
		for (int x = 0; x < LW; x++) {
			double nx = double(x) / LW, ny = double(y) / LH, u = nx * 1.6 * iS, v = ny * iS;
			double wx0 = u + .24 * fbm(u * 2 + 5.2, v * 2 + 1.3, 4), wy0 = v + .24 * fbm(u * 2 + 8.1, v * 2 + 2.7, 4);
			double wx = wx0 + .07 * fbm(wx0 * 7 + 3, wy0 * 7 + 9, 3), wy = wy0 + .07 * fbm(wx0 * 7 + 13, wy0 * 7 + 1, 3);
			double c = 0;
			for (auto &b : blobs) {
				double dx = wx - b.x, dy = wy - b.y;
				c += b.w * std::exp(-(dx * dx + dy * dy) / (b.r * b.r));
			}
			for (auto &A : arms) {
				if (wx < A.bx || wx > A.ex || wy < A.by || wy > A.ey) continue;
				for (auto &sg : A.segs) {
					double d2 = seg_d(wx, wy, sg);
					if (d2 < sg.r * sg.r * 9) c = std::max(c, 1.15 * std::exp(-d2 / (sg.r * sg.r)));
				}
			}
			double ix = u + (wx - u) * .55, iy = v + (wy - v) * .55;
			for (auto &b : isl) {
				double dx = ix - b.x, dy = iy - b.y;
				double q = (dx * dx + dy * dy) / (b.r * b.r);
				if (q < 14) {
					q *= 1 + 1.1 * fbm(ix / b.r * .6 + b.x * 40, iy / b.r * .6 + b.y * 40, 3);
					c += b.w * std::exp(-q);
				}
			}
			double cs = sstep(.05, .9, c);
			double h = cs * .74 + fbm(wx * 3.5, wy * 3.5, 6) * .5 + fbm(wx * 8 + 21, wy * 8 + 5, 5) * .16 + (1 - std::fabs(fbm(wx * 9 + 40, wy * 9, 4) * 2)) * .06 - .07;
			double m = 0;
			for (auto &R : ranges) {
				if (wx < R.bx || wx > R.ex || wy < R.by || wy > R.ey) continue;
				double d2 = 1e9;
				for (auto &sg : R.segs) d2 = std::min(d2, seg_d(wx, wy, sg));
				double w2 = R.w * R.w;
				if (d2 > w2 * 14) continue;
				double along = .45 + .55 * sstep(-.25, .35, fbm(wx * 7 + R.w * 80, wy * 7 - R.w * 50, 3));
				double peak = std::exp(-d2 / w2), foot = std::exp(-d2 / (w2 * 7)) * .3;
				double rough = 1 - std::fabs(fbm(wx * 18 + R.w * 99, wy * 18, 4) * 2);
				m = std::max(m, (peak * (.35 + .65 * rough) * along + foot * (.6 + .4 * along)) * R.h);
			}
			h += m * .3;
			for (auto &S : seas) {
				double dx = wx - S.x, dy = wy - S.y, pp = dx * S.ca + dy * S.sa, qq = -dx * S.sa + dy * S.ca;
				h -= S.d * std::exp(-(pp * pp / (S.rx * S.rx) + qq * qq / (S.ry * S.ry)) * (1 + .8 * fbm(wx * 11 + S.rx * 90, wy * 11, 3)));
			}
			w.low_m[size_t(y) * LW + x] = float(m);
			double ed = std::min(std::min(nx, 1 - nx) * 1.6, std::min(ny, 1 - ny));
			h -= (1 - sstep(0, .1, ed)) * 1.4;
			w.low[size_t(y) * LW + x] = float(h);
		}
	// upsample + detail
	const size_t NPX = size_t(MW) * MH;
	w.H.assign(NPX, 0);
	w.Mf.assign(NPX, 0);
	for (int y = 0; y < MH; y++) {
		double fy = std::min(y / 2.0, LH - 1.001);
		int y0 = int(std::floor(fy));
		double ty = fy - y0;
		for (int x = 0; x < MW; x++) {
			double fx = std::min(x / 2.0, LW - 1.001);
			int x0 = int(std::floor(fx));
			double tx = fx - x0;
			size_t i = size_t(y0) * LW + x0;
			const auto &lo = w.low;
			const auto &lm = w.low_m;
			double h = (double(lo[i]) * (1 - tx) + double(lo[i + 1]) * tx) * (1 - ty) + (double(lo[i + LW]) * (1 - tx) + double(lo[i + LW + 1]) * tx) * ty;
			w.H[size_t(y) * MW + x] = float(h + noise(x * .02, y * .02) * .05 + noise(x * .05 + 50, y * .05) * .03 + noise(x * .12 + 7, y * .12 + 3) * .016);
			double mm = (double(lm[i]) * (1 - tx) + double(lm[i + 1]) * tx) * (1 - ty) + (double(lm[i + LW]) * (1 - tx) + double(lm[i + LW + 1]) * tx) * ty;
			w.Mf[size_t(y) * MW + x] = float(mm * (1 + noise(x * .05 + 7, y * .05 + 3) * .35 * mm));
		}
	}
	// threshold to a fixed land fraction
	{
		std::vector<double> sample(30000);
		for (int i = 0; i < 30000; i++) sample[i] = w.H[size_t(std::floor(rng() * double(NPX)))];
		std::sort(sample.begin(), sample.end());
		double T = .5;
		int above = 0;
		for (double v : sample)
			if (v > T) above++;
		double fr = double(above) / sample.size();
		if (fr > .3) T = sample[size_t(std::floor(sample.size() * .7))];
		else if (fr < .13) T = sample[size_t(std::floor(sample.size() * .87))];
		w.T = T;
		w.top = sample.back() - T;
		w.bot = T - sample.front();
	}
	w.land.assign(NPX, 0);
	w.land_count = 0;
	for (size_t i = 0; i < NPX; i++)
		if (double(w.H[i]) > w.T) { w.land[i] = 1; w.land_count++; }
	// land components and seeds
	struct Comp { int id; int area; std::vector<int> pix; int n = 0; };
	std::vector<Comp> comps;
	{
		std::vector<int> comp(NPX, -1);
		std::vector<int> st;
		for (size_t i0 = 0; i0 < NPX; i0++) {
			if (!w.land[i0] || comp[i0] >= 0) continue;
			Comp C;
			C.id = int(comps.size());
			C.area = 0;
			st.clear();
			st.push_back(int(i0));
			comp[i0] = C.id;
			while (!st.empty()) {
				int j = st.back();
				st.pop_back();
				C.area++;
				if ((C.area & 3) == 0) C.pix.push_back(j);
				int x = j % MW;
				int nbs[4] = {x > 0 ? j - 1 : -1, x < MW - 1 ? j + 1 : -1, j - MW, j + MW};
				for (int n : nbs)
					if (n >= 0 && n < int(NPX) && w.land[n] && comp[n] < 0) { comp[n] = C.id; st.push_back(n); }
			}
			comps.push_back(std::move(C));
		}
	}
	std::vector<Comp *> elig;
	for (auto &c : comps)
		if (c.area >= std::max(3000.0, w.land_count * .025)) elig.push_back(&c);
	std::stable_sort(elig.begin(), elig.end(), [](Comp *a, Comp *b) { return b->area - a->area < 0; });
	if (elig.empty()) {
		std::vector<Comp *> all;
		for (auto &c : comps) all.push_back(&c);
		std::stable_sort(all.begin(), all.end(), [](Comp *a, Comp *b) { return b->area - a->area < 0; });
		if (!all.empty()) elig.push_back(all[0]);
	}
	const int N = p.n;
	if (int(elig.size()) > N) elig.resize(N);
	{
		double S = 0;
		for (auto *c : elig) S += c->area;
		int tot = 0;
		for (auto *c : elig) { c->n = std::max(1, int(js_round(N * double(c->area) / S))); tot += c->n; }
		while (tot > N) {
			Comp *best = nullptr;
			for (auto *c : elig)
				if (c->n > 1 && (!best || double(c->area) / c->n < double(best->area) / best->n)) best = c;
			if (!best) break;
			best->n--;
			tot--;
		}
		while (tot < N) {
			Comp *best = nullptr;
			for (auto *c : elig)
				if (!best || double(c->area) / c->n > double(best->area) / best->n) best = c;
			best->n++;
			tot++;
		}
	}
	auto &seeds = w.seeds;
	for (auto *c : elig) {
		double minD = std::sqrt(double(c->area) / c->n) * .55;
		int got = 0;
		double ring = std::min(25.0, std::sqrt(double(c->area)) / 5);
		for (int att = 0; got < c->n && att < 6000; att++) {
			if (att % 600 == 599) minD *= .85;
			int i = c->pix[size_t(std::floor(rng() * c->pix.size()))], x = i % MW, y = i / MW;
			if (x < 10 || y < 10 || x > MW - 10 || y > MH - 10 || double(w.Mf[i]) > .45) continue;
			bool close = false;
			for (auto &s : seeds)
				if (double((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y)) < minD * minD) { close = true; break; }
			if (close) continue;
			int lc = 0;
			for (int k = 0; k < 16; k++) {
				double a = double(k) / 16 * 6.283;
				int xx = int(js_round(x + std::cos(a) * ring)), yy = int(js_round(y + std::sin(a) * ring));
				if (xx >= 0 && yy >= 0 && xx < MW && yy < MH && w.land[size_t(yy) * MW + xx]) lc++;
			}
			if (lc < 13) continue;
			SeedPt sp;
			sp.x = x;
			sp.y = y;
			seeds.push_back(sp);
			got++;
		}
	}
	// growth character of every state
	static const int DX[8] = {1, -1, 0, 0, 1, 1, -1, -1}, DY[8] = {0, 0, 1, -1, 1, -1, 1, -1};
	for (auto &sd : seeds) {
		int lc = 0;
		for (int k = 0; k < 32; k++) {
			double a = double(k) / 32 * 6.283;
			int xx = int(js_round(sd.x + std::cos(a) * 70)), yy = int(js_round(sd.y + std::sin(a) * 70));
			if (xx >= 0 && yy >= 0 && xx < MW && yy < MH && w.land[size_t(yy) * MW + xx]) lc++;
		}
		bool interior = lc >= 30;
		double r = rng();
		if (interior) r *= .75;
		sd.m = r < .2 ? .8 : r < .45 ? 1.25 : r < .75 ? 1.9 : r < .92 ? 2.8 : 4.2;
		double r1 = rng(), r2 = rng();
		sd.off = std::floor(r1 * r2 * (interior ? 60 : 180));
		double ang = rng() * PI, st = 1 + std::pow(rng(), 1.6) * 2.6, px = -std::sin(ang), py = std::cos(ang);
		for (int j = 0; j < 8; j++) {
			double dx = DX[j], dy = DY[j], len = js_hypot(dx, dy);
			sd.dm[j] = sd.m * len * (1 + (st - 1) * std::fabs((dx * px + dy * py) / len)) * 3;
		}
	}
	// Dial's algorithm region growing
	std::vector<int8_t> own(NPX, -1);
	{
		std::vector<int> dist(NPX, 1000000000);
		std::vector<std::vector<int>> buckets;
		auto push = [&](int d, int i) {
			if (int(buckets.size()) <= d) buckets.resize(size_t(d) + 1);
			buckets[d].push_back(i);
		};
		std::vector<uint8_t> locked(NPX, 0);
		for (size_t k = 0; k < seeds.size(); k++) {
			const auto &sd = seeds[k];
			for (int dy = -7; dy <= 7; dy++)
				for (int dx = -7; dx <= 7; dx++) {
					if (dx * dx + dy * dy > 49) continue;
					int x = sd.x + dx, y = sd.y + dy;
					if (x < 0 || y < 0 || x >= MW || y >= MH) continue;
					size_t i = size_t(y) * MW + x;
					if (!w.land[i] || locked[i]) continue;
					locked[i] = 1;
					own[i] = int8_t(k);
					dist[i] = int(sd.off);
					push(int(sd.off), int(i));
				}
		}
		std::vector<uint8_t> baseC(NPX, 0);
		for (size_t i = 0; i < NPX; i++) {
			if (!w.land[i]) continue;
			int x = int(i % MW), y = int(i / MW);
			double e = w.Mf[i];
			double v = std::max(0.0, e - .12) * 26 + (noise(x * .012 + 90, y * .012 + 40) + .5) * 5 + (noise(x * .03 + 31, y * .03 + 5) + .5) * 7 + (noise(x * .07 + 13, y * .07 + 77) + .5) * 4;
			baseC[i] = uint8_t(int(1 + std::floor(v)));
		}
		for (size_t d = 0; d < buckets.size(); d++) {
			std::vector<int> b = std::move(buckets[d]);
			for (size_t q = 0; q < b.size(); q++) {
				int i = b[q];
				if (dist[i] != int(d)) continue;
				int o = own[i];
				const double *dm = seeds[o].dm;
				int x = i % MW, y = i / MW;
				for (int j = 0; j < 8; j++) {
					int nx = x + DX[j], ny = y + DY[j];
					if (nx < 0 || ny < 0 || nx >= MW || ny >= MH) continue;
					size_t n = size_t(ny) * MW + nx;
					if (!w.land[n] || (locked[n] && own[n] != o)) continue;
					int nd = int(d) + std::max(1, int(js_round(baseC[n] * dm[j])));
					if (nd < dist[n]) { dist[n] = nd; own[n] = int8_t(o); push(nd, int(n)); }
				}
			}
		}
	}
	// island groups without a state become their own states (or join the nearest one)
	{
		std::vector<int> cid(NPX, -1);
		struct IC { std::vector<int> px; double x, y; int a; };
		std::vector<IC> cs;
		std::vector<int> st;
		for (size_t i0 = 0; i0 < NPX; i0++) {
			if (!w.land[i0] || own[i0] >= 0 || cid[i0] >= 0) continue;
			IC c;
			st.clear();
			st.push_back(int(i0));
			cid[i0] = int(cs.size());
			double sx = 0, sy = 0;
			while (!st.empty()) {
				int j = st.back();
				st.pop_back();
				c.px.push_back(j);
				int x = j % MW, y = j / MW;
				sx += x;
				sy += y;
				int nbs[4] = {x > 0 ? j - 1 : -1, x < MW - 1 ? j + 1 : -1, j - MW, j + MW};
				for (int q : nbs)
					if (q >= 0 && q < int(NPX) && w.land[q] && own[q] < 0 && cid[q] < 0) { cid[q] = int(cs.size()); st.push_back(q); }
			}
			c.a = int(c.px.size());
			c.x = sx / c.a;
			c.y = sy / c.a;
			cs.push_back(std::move(c));
		}
		std::vector<int> par(cs.size());
		for (size_t i = 0; i < cs.size(); i++) par[i] = int(i);
		std::function<int(int)> fd = [&](int i) { return par[i] == i ? i : (par[i] = fd(par[i])); };
		for (size_t a = 0; a < cs.size(); a++)
			for (size_t b = a + 1; b < cs.size(); b++)
				if (js_hypot(cs[a].x - cs[b].x, cs[a].y - cs[b].y) < 150) { int ra = fd(int(a)); par[ra] = fd(int(b)); }
		// groups in order of first appearance
		std::vector<int> roots;
		std::vector<std::vector<int>> members;
		for (size_t i = 0; i < cs.size(); i++) {
			int r = fd(int(i));
			size_t g = 0;
			for (; g < roots.size(); g++)
				if (roots[g] == r) break;
			if (g == roots.size()) { roots.push_back(r); members.push_back({}); }
			members[g].push_back(int(i));
		}
		struct Grp { std::vector<int> L; double a, x, y; };
		std::vector<Grp> G2;
		for (auto &L : members) {
			Grp g;
			g.L = L;
			double a = 0, sx = 0, sy = 0;
			for (int ci : L) a += cs[ci].a;
			for (int ci : L) sx += cs[ci].x * cs[ci].a;
			for (int ci : L) sy += cs[ci].y * cs[ci].a;
			g.a = a;
			g.x = sx / a;
			g.y = sy / a;
			G2.push_back(std::move(g));
		}
		std::stable_sort(G2.begin(), G2.end(), [](const Grp &a, const Grp &b) { return b.a - a.a < 0; });
		for (auto &g : G2) {
			int id = -1;
			if (g.a >= 700 && seeds.size() < 46) {
				std::vector<int> L = g.L;
				std::stable_sort(L.begin(), L.end(), [&](int a, int b) { return cs[b].a - cs[a].a < 0; });
				const IC &big = cs[L[0]];
				int best = big.px[0];
				double bd = 1e18;
				for (int j : big.px) {
					double ddx = j % MW - big.x, ddy = (j / MW) - big.y;
					double d = ddx * ddx + ddy * ddy;
					if (d < bd) { bd = d; best = j; }
				}
				SeedPt sp;
				sp.x = best % MW;
				sp.y = best / MW;
				seeds.push_back(sp);
				id = int(seeds.size()) - 1;
			} else {
				double bd = 1e18;
				for (size_t k = 0; k < seeds.size(); k++) {
					double ddx = seeds[k].x - g.x, ddy = seeds[k].y - g.y;
					double d = ddx * ddx + ddy * ddy;
					if (d < bd) { bd = d; id = int(k); }
				}
			}
			for (int ci : g.L)
				for (int j : cs[ci].px) own[j] = int8_t(id);
		}
	}
	for (size_t i = 0; i < NPX; i++)
		if (w.land[i] && own[i] < 0) own[i] = int8_t(NEU);
	w.own_grow = own;
	// onto the board lattice
	sq_build(w, own);
	{
		const int S = p.tri_s;
		for (int y = 0; y < MH; y++)
			for (int x = 0; x < MW; x++) {
				double fx_ = (x + .5) / S, fy_ = (y + .5) / S;
				int i = int(std::floor(fx_)), j = int(std::floor(fy_));
				double fx = fx_ - i, fy = fy_ - j;
				int d = (i >= 0 && j >= 0 && i < w.sqw && j < w.sqh) ? w.sqd[size_t(j) * w.sqw + i] : 0;
				int h = d ? (fx > fy ? 0 : 1) : (fx + fy < 1 ? 0 : 1);
				own[size_t(y) * MW + x] = int8_t(w.sql[(size_t(j) * w.sqw + i) * 2 + h]);
			}
	}
	w.own = own;
	// countries: area, label point, neighbours
	{
		const size_t n = seeds.size();
		std::vector<double> area(n, 0), cx(n, 0), cy(n, 0);
		std::vector<OrderedCount> adj(n);
		for (int y = 0; y < MH; y++)
			for (int x = 0; x < MW; x++) {
				size_t i = size_t(y) * MW + x;
				int o = own[i];
				if (o < 0 || o >= NEU) continue;
				area[o]++;
				cx[o] += x;
				cy[o] += y;
				int nbs[4] = {x > 0 ? own[i - 1] : -1, x < MW - 1 ? own[i + 1] : -1, y > 0 ? own[i - MW] : -1, y < MH - 1 ? own[i + MW] : -1};
				for (int q : nbs)
					if (q >= 0 && q != o && q != NEU) adj[o][q]++;
			}
		for (size_t k = 0; k < n; k++) {
			Country C;
			C.idx = int(k);
			C.area = area[k];
			if (area[k] == 0) {   // a seed that lost all its land: NaN label point in the original
				C.no_label = true;
				C.cap_x = seeds[k].x;
				C.cap_y = seeds[k].y;
				w.countries.push_back(std::move(C));
				continue;
			}
			double x = cx[k] / area[k], y = cy[k] / area[k];
			int ix = int(js_round(x)), iy = int(js_round(y));
			if (own[size_t(iy) * MW + ix] != int(k)) {
				double bd = 1e18;
				for (int yy = 0; yy < MH; yy += 3)
					for (int xx = 0; xx < MW; xx += 3)
						if (own[size_t(yy) * MW + xx] == int(k)) {
							double d = (xx - x) * (xx - x) + (yy - y) * (yy - y);
							if (d < bd) { bd = d; ix = xx; iy = yy; }
						}
			}
			if (js_hypot(ix - seeds[k].x, iy - seeds[k].y) < 40) {
				int ny = iy + (iy < seeds[k].y ? -34 : 34);
				if (ny > 0 && ny < MH && own[size_t(ny) * MW + ix] == int(k)) iy = ny;
			}
			for (auto &e : adj[k].v)
				if (e.second > 6) C.neighbors.push_back(e.first);
			C.lx = ix;
			C.ly = iy;
			C.cap_x = seeds[k].x;
			C.cap_y = seeds[k].y;
			C.land_share = area[k] / w.land_count;
			w.countries.push_back(std::move(C));
		}
	}
	return w;
}

namespace {

// exact Euclidean distance transform (Felzenszwalb), EDT in 04-map.js; F is a Float32Array there
void edt(std::vector<float> &F, int W, int Hh) {
	int N = std::max(W, Hh);
	std::vector<double> f(N), d(N), z(N + 1);
	std::vector<int> v(N);
	auto run = [&](int len) {
		int k = 0;
		v[0] = 0;
		z[0] = -INFINITY;
		z[1] = INFINITY;
		for (int q = 1; q < len; q++) {
			double sx = ((f[q] + double(q) * q) - (f[v[k]] + double(v[k]) * v[k])) / (2.0 * q - 2.0 * v[k]);
			while (sx <= z[k]) {
				k--;
				sx = ((f[q] + double(q) * q) - (f[v[k]] + double(v[k]) * v[k])) / (2.0 * q - 2.0 * v[k]);
			}
			k++;
			v[k] = q;
			z[k] = sx;
			z[k + 1] = INFINITY;
		}
		k = 0;
		for (int q = 0; q < len; q++) {
			while (z[k + 1] < q) k++;
			d[q] = double(q - v[k]) * (q - v[k]) + f[v[k]];
		}
	};
	for (int x = 0; x < W; x++) {
		for (int y = 0; y < Hh; y++) f[y] = F[size_t(y) * W + x];
		run(Hh);
		for (int y = 0; y < Hh; y++) F[size_t(y) * W + x] = float(d[y]);
	}
	for (int y = 0; y < Hh; y++) {
		for (int x = 0; x < W; x++) f[x] = F[size_t(y) * W + x];
		run(W);
		for (int x = 0; x < W; x++) F[size_t(y) * W + x] = float(d[x]);
	}
}

// box blur from genWorld (r, passes), Float32Array in and out
void blur(std::vector<float> &A, int r, int passes, int W, int Hh) {
	std::vector<float> tmp(A.size());
	const double div = 2 * r + 1;
	for (int p = 0; p < passes; p++) {
		for (int y = 0; y < Hh; y++) {
			double acc = 0;
			size_t row = size_t(y) * W;
			for (int x = -r; x <= r; x++) acc += A[row + clampi(x, 0, W - 1)];
			for (int x = 0; x < W; x++) {
				tmp[row + x] = float(acc / div);
				acc += double(A[row + std::min(W - 1, x + r + 1)]) - double(A[row + std::max(0, x - r)]);
			}
		}
		for (int x = 0; x < W; x++) {
			double acc = 0;
			for (int y = -r; y <= r; y++) acc += tmp[size_t(clampi(y, 0, Hh - 1)) * W + x];
			for (int y = 0; y < Hh; y++) {
				A[size_t(y) * W + x] = float(acc / div);
				acc += double(tmp[size_t(std::min(Hh - 1, y + r + 1)) * W + x]) - double(tmp[size_t(std::max(0, y - r)) * W + x]);
			}
		}
	}
}

inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }

} // namespace

void build_render_data(World &w) {
	const int MW = w.p.mw, MH = w.p.mh, S = w.p.tri_s;
	const size_t NPX = size_t(MW) * MH;
	const float INF = float(1e10);
	Mulberry rng(w.seed);
	Perlin noise(rng);
	const auto &own = w.own;
	// 2x state map on the board lattice (triLab)
	const int HW = MW * 2, HH = MH * 2;
	w.hid.assign(size_t(HW) * HH, 0);
	for (int Y = 0; Y < HH; Y++)
		for (int X = 0; X < HW; X++) {
			double x = (X + .5) / 2, y = (Y + .5) / 2;
			int i = int(std::floor(x / S)), j = int(std::floor(y / S));
			double fx = x / S - i, fy = y / S - j;
			int d = (i >= 0 && j >= 0 && i < w.sqw && j < w.sqh) ? w.sqd[size_t(j) * w.sqw + i] : 0;
			int h = d ? (fx > fy ? 0 : 1) : (fx + fy < 1 ? 0 : 1);
			double c0 = d ? (h ? 1.0 / 3 : 2.0 / 3) : (h ? 2.0 / 3 : 1.0 / 3), c1 = d ? (h ? 2.0 / 3 : 1.0 / 3) : (h ? 2.0 / 3 : 1.0 / 3);
			int cx = int(std::floor((i + c0) * S)), cy = int(std::floor((j + c1) * S));
			int o = (cx < 0 || cy < 0 || cx >= MW || cy >= MH) ? -1 : own[size_t(cy) * MW + cx];
			w.hid[size_t(Y) * HW + X] = uint8_t(o < 0 ? 0 : o + 1);
		}
	// border distance on the 2x grid
	auto &hid = w.hid;
	w.hb.assign(size_t(HW) * HH, 0);
	auto &hb = w.hb;
	for (int Y = 0; Y < HH; Y++)
		for (int X = 0; X < HW; X++) {
			size_t i = size_t(Y) * HW + X;
			int o = hid[i];
			hb[i] = INF;
			if (!o) continue;
			if ((X > 0 && hid[i - 1] && hid[i - 1] != o) || (X < HW - 1 && hid[i + 1] && hid[i + 1] != o) || (Y > 0 && hid[i - HW] && hid[i - HW] != o) ||
					(Y < HH - 1 && hid[i + HW] && hid[i + HW] != o))
				hb[i] = 0;
		}
	edt(hb, HW, HH);
	for (auto &v : hb) v = float(std::min(std::sqrt(double(v)) + .5, 24.0));
	blur(hb, 1, 1, HW, HH);
	// the state map grows into the sea so lookups near the coast never hit 0
	for (int it = 0; it < 8; it++) {
		std::vector<uint8_t> src = hid;
		for (int Y = 1; Y < HH - 1; Y++)
			for (int X = 1; X < HW - 1; X++) {
				size_t i = size_t(Y) * HW + X;
				if (src[i]) continue;
				uint8_t q = src[i - 1] ? src[i - 1] : src[i + 1] ? src[i + 1] : src[i - HW] ? src[i - HW] : src[i + HW];
				if (q) hid[i] = q;
			}
	}
	// smoothed height for the lighting, signed distance to the coast, relief height
	const double T = w.T, top = w.top, bot = w.bot;
	std::vector<float> Hs(NPX), sdl(NPX), sdw(NPX), cs(NPX), EV(NPX);
	for (size_t i = 0; i < NPX; i++) {
		double d = (double(w.H[i]) - T) / top;
		Hs[i] = float(std::max(0.0, d) * .25 + double(w.Mf[i]) * .9 * sstep(0, .05, d));
	}
	blur(Hs, 1, 2, MW, MH);
	for (size_t i = 0; i < NPX; i++) {
		bool L = own[i] >= 0;
		sdl[i] = L ? INF : 0;
		sdw[i] = L ? 0 : INF;
	}
	edt(sdl, MW, MH);
	edt(sdw, MW, MH);
	for (size_t i = 0; i < NPX; i++) cs[i] = float(own[i] >= 0 ? std::sqrt(double(sdl[i])) - .5 : -(std::sqrt(double(sdw[i])) - .5));
	for (size_t i = 0; i < NPX; i++) {
		double d = (double(w.H[i]) - T) / top;
		EV[i] = float(std::max(.002, std::max(0.0, d) * .12 + double(w.Mf[i]) * .85 * sstep(0, .05, d)));
	}
	blur(EV, 2, 3, MW, MH);
	w.tf.assign(NPX * 4, 0);
	const double Lx = -.55, Ly = -.65, Lz = .52;
	for (int y = 0; y < MH; y++)
		for (int x = 0; x < MW; x++) {
			size_t i = size_t(y) * MW + x;
			double h = w.H[i];
			double gx = (double(Hs[size_t(y) * MW + std::min(MW - 1, x + 1)]) - double(Hs[size_t(y) * MW + std::max(0, x - 1)])) * 32;
			double gy = (double(Hs[size_t(std::min(MH - 1, y + 1)) * MW + x]) - double(Hs[size_t(std::max(0, y - 1)) * MW + x])) * 32;
			double nl = js_hypot3(gx, gy, 1);
			double lit = (-gx * Lx - gy * Ly + Lz) / nl / Lz;
			double lit2 = (gx * .4 - gy * .3 + .85) / nl / .85;
			double ev = EV[i], wv = std::min((h - T) / bot, -.001), c_ = cs[i];
			w.tf[i * 4] = float(c_ > 0 ? lerpd(c_ * .004, std::max(ev, std::min(c_ * .004, .02)), sstep(2, 8, c_)) : lerpd(c_ * .004, std::min(wv, c_ * .004), sstep(10, 40, -c_)));
			w.tf[i * 4 + 1] = float(w.sqd[size_t(y / S) * w.sqw + size_t(x / S)]);
			w.tf[i * 4 + 2] = float(clampd(.5 + (lit * .75 + lit2 * .25 - 1) * .85, 0, 1));
			w.tf[i * 4 + 3] = float(noise(x * .006 + 20, y * .006 + 11) * .5 + noise(x * .018, y * .018 + 60) * .25 + .5);
		}
}

std::vector<BorderLine> extract_lines(const World &w) {
	const int S = w.p.tri_s, SQW = w.sqw, SQH = w.sqh, MW = w.p.mw, MH = w.p.mh, JW = SQH + 3;
	const double WXh = MW / 160.0, WZh = MH / 160.0;   // half the world size (WX = MW / 80)
	auto vid = [&](int i, int j) { return (i + 1) * JW + (j + 1); };
	auto lab = [&](int i, int j, int h) {
		if (i < 0 || j < 0 || i >= SQW || j >= SQH) return 0;
		const int d = w.sqd[size_t(j) * SQW + i];
		double cx, cy;
		if (d) { cx = h ? 1.0 / 3 : 2.0 / 3; cy = h ? 2.0 / 3 : 1.0 / 3; }
		else { cx = h ? 2.0 / 3 : 1.0 / 3; cy = h ? 2.0 / 3 : 1.0 / 3; }
		const int X = std::min(MW - 1, int(std::floor((i + cx) * S))), Y = std::min(MH - 1, int(std::floor((j + cy) * S)));
		const int o = w.own[size_t(Y) * MW + X];
		return o < 0 ? 0 : o + 1;
	};
	// which half touches each side: "/" (d=0): h0 top+left, h1 bottom+right; "\" (d=1): h0 top+right, h1 bottom+left
	auto side = [&](int i, int j, char sd) {
		if (i < 0 || j < 0 || i >= SQW || j >= SQH) return 0;
		const int d = w.sqd[size_t(j) * SQW + i];
		const int h = sd == 't' ? 0 : sd == 'b' ? 1 : sd == 'l' ? (d ? 1 : 0) : (d ? 0 : 1);
		return lab(i, j, h);
	};
	// groups keyed a*256+b in insertion order (a JS Map)
	std::vector<int> keys;
	std::unordered_map<int, std::vector<int>> groups;
	auto add = [&](int a, int b, int v1, int v2) {
		if (a == b) return;
		if (a > b) std::swap(a, b);
		const int k = a * 256 + b;
		auto it = groups.find(k);
		if (it == groups.end()) {
			keys.push_back(k);
			it = groups.emplace(k, std::vector<int>()).first;
		}
		it->second.push_back(v1);
		it->second.push_back(v2);
	};
	for (int j = -1; j < SQH; j++)
		for (int i = -1; i < SQW; i++) {
			if (i >= 0 && j >= 0) {
				const int d = w.sqd[size_t(j) * SQW + i];
				add(lab(i, j, 0), lab(i, j, 1), d ? vid(i, j) : vid(i + 1, j), d ? vid(i + 1, j + 1) : vid(i, j + 1));
			}
			if (j >= 0) add(side(i, j, 'r'), side(i + 1, j, 'l'), vid(i + 1, j), vid(i + 1, j + 1));
			if (i >= 0) add(side(i, j, 'b'), side(i, j + 1, 't'), vid(i, j + 1), vid(i + 1, j + 1));
		}
	std::vector<BorderLine> res;
	for (int key : keys) {
		const std::vector<int> &e = groups[key];
		const int a = key >> 8, b = key & 255, ne = int(e.size() / 2);
		std::vector<int> vorder;
		std::unordered_map<int, std::vector<int>> adj;
		for (int q = 0; q < ne; q++)
			for (int v : {e[q * 2], e[q * 2 + 1]}) {
				auto it = adj.find(v);
				if (it == adj.end()) {
					vorder.push_back(v);
					it = adj.emplace(v, std::vector<int>()).first;
				}
				it->second.push_back(q);
			}
		std::vector<uint8_t> used(ne, 0);
		std::vector<std::vector<int>> chains;
		auto walk = [&](int start, int ei) {
			std::vector<int> pts = {start};
			int v = start;
			while (ei >= 0 && !used[ei]) {
				used[ei] = 1;
				const int nv = e[ei * 2] == v ? e[ei * 2 + 1] : e[ei * 2];
				pts.push_back(nv);
				v = nv;
				const auto &l = adj[v];
				if (l.size() != 2) break;
				ei = l[0] == ei ? l[1] : l[0];
			}
			return pts;
		};
		for (int v : vorder) {
			const auto l = adj[v];
			if (l.size() != 2)
				for (int ei : l)
					if (!used[ei]) chains.push_back(walk(v, ei));
		}
		for (int q = 0; q < ne; q++)
			if (!used[q]) chains.push_back(walk(e[q * 2], q));
		for (const auto &ch : chains) {
			std::vector<std::array<double, 2>> P;
			for (int v : ch) P.push_back({double((v / JW - 1) * S), double((v % JW - 1) * S)});
			std::vector<std::array<double, 2>> out = {P[0]};
			for (size_t k = 1; k + 1 < P.size(); k++) {
				const auto &A = out.back(), &B = P[k], &C = P[k + 1];
				if (std::fabs((B[0] - A[0]) * (C[1] - A[1]) - (B[1] - A[1]) * (C[0] - A[0])) > 1e-3) out.push_back(B);
			}
			out.push_back(P.back());
			BorderLine bl{a, b, {}};
			for (auto &q : out) {
				const double x = clampd(q[0], 0, MW), y = clampd(q[1], 0, MH);
				bl.p.push_back(float(x / MW * (2 * WXh) - WXh));
				bl.p.push_back(float(y / MH * (2 * WZh) - WZh));
			}
			res.push_back(std::move(bl));
		}
	}
	return res;
}

} // namespace tr
