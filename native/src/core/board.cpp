// Port of boardGen() / boardRoads() from legacy/src/08e-company.js. Comments name the JS pieces they follow.
// Notes for exactness: Float32Array buffers of the original (terr, A* costs, polylines) are float here;
// the binary heap, the stable sorts and the iteration orders (Map/Set insertion, integer object keys) are kept.
#include "board.h"
#include "jsmath.h"
#include "names.h"
#include "rng.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <unordered_set>
#include <utility>

namespace tr {

namespace {

const int D8[8][2] = {{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}};
const double SQRT2 = 1.4142135623730951;   // Math.SQRT2

// the JS binary heap used by every A* of the original (ties resolve the same way)
struct Heap {
	std::vector<double> hk;
	std::vector<int> hv;
	void push(double f, int s) {
		hk.push_back(f);
		hv.push_back(s);
		size_t k = hk.size() - 1;
		while (k > 0) {
			size_t p = (k - 1) >> 1;
			if (hk[p] <= hk[k]) break;
			std::swap(hk[p], hk[k]);
			std::swap(hv[p], hv[k]);
			k = p;
		}
	}
	int pop() {
		int s = hv[0];
		double lk = hk.back();
		int lv = hv.back();
		hk.pop_back();
		hv.pop_back();
		if (!hk.empty()) {
			hk[0] = lk;
			hv[0] = lv;
			size_t k = 0;
			for (;;) {
				size_t l = k * 2 + 1, r = l + 1, m = k;
				if (l < hk.size() && hk[l] < hk[m]) m = l;
				if (r < hk.size() && hk[r] < hk[m]) m = r;
				if (m == k) break;
				std::swap(hk[m], hk[k]);
				std::swap(hv[m], hv[k]);
				k = m;
			}
		}
		return s;
	}
	bool empty() const { return hk.empty(); }
};

struct Ctx {
	const World &w;
	Board &B;
	double WX, WZ;
	int MW, MH;
	Ctx(const World &w_, Board &b_) : w(w_), B(b_) {
		MW = w.p.mw;
		MH = w.p.mh;
		WX = MW / 80.0;
		WZ = MH / 80.0;
	}
	int bOwn(double x, double z) const {
		int px = int(std::floor((x + WX / 2) / WX * MW)), py = int(std::floor((z + WZ / 2) / WZ * MH));
		if (px < 0 || py < 0 || px >= MW || py >= MH) return -1;
		int o = w.own[size_t(py) * MW + px];
		return o >= 0 && o < NEU ? o : -1;
	}
	int bInland(double x, double z) const {
		int o = bOwn(x, z);
		if (o < 0) return -1;
		static const int dd[4][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
		for (auto &d : dd)
			if (bOwn(x + d[0] * B.st, z + d[1] * B.st) < 0) return -1;
		return o;
	}
	int bNode(int i, int j) const { return j * B.nx + i; }
	void bXY(int n, double &x, double &z) const {
		int i = n % B.nx, j = n / B.nx;
		x = -WX / 2 + i * B.st;
		z = -WZ / 2 + j * B.st;
	}
	int nodeAt(double x, double z) const {
		int i = clampi(int(js_round((x + WX / 2) / B.st)), 0, B.nx - 1), j = clampi(int(js_round((z + WZ / 2) / B.st)), 0, B.nz - 1);
		return bNode(i, j);
	}
	bool onBorder(double x, double z, int o) const {
		static const double dd[8][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {.7, .7}, {-.7, .7}, {.7, -.7}, {-.7, -.7}};
		for (double s : {1.2, 2.2})
			for (auto &d : dd) {
				int wv = bOwn(x + d[0] * B.st * s, z + d[1] * B.st * s);
				if (wv >= 0 && wv != o) return true;
			}
		return false;
	}
};

// ---------- towns (boardGen) ----------
void gen_towns(Ctx &C, uint32_t seed, const std::vector<double> &state_pop) {
	Board &B = C.B;
	const World &w = C.w;
	Mulberry rr(seed ^ 0x51abu);
	std::set<std::string> used;
	auto &T = B.towns;
	auto pk = [&](const std::vector<std::string> &a) -> const std::string & { return a[size_t(std::floor(rr() * a.size()))]; };
	auto nm = [&](bool vil) -> std::string {
		for (int k = 0; k < 400; k++) {
			std::string n;
			if (vil) {
				if (k < 30) { n = pk(CITY_A); n += pk(VIL_B); }
				else { n = pk(CITY_A); n += pk(CITY_M); n += pk(VIL_B); }
			} else {
				if (k < 40) { n = pk(CITY_A); n += pk(CITY_B); }
				else { n = pk(CITY_A); n += pk(CITY_M); n += pk(CITY_B); }
			}
			if (!used.count(n)) { used.insert(n); return n; }
		}
		static const std::vector<std::string> pre = {"Нове ", "Верхнє ", "Мале "};
		std::string n = pk(pre);
		n += pk(CITY_A);
		n += pk(CITY_M);
		n += pk(VIL_B);
		return n;
	};
	auto near = [&](int i, int j, double &x, double &z) { C.bXY(C.bNode(i, j), x, z); };
	auto ok = [&](double x, double z, const std::string &type, double min) {
		for (auto &o : T) {
			double lim = (o.type == "vil" || type == "vil") ? std::min(min, .45) : min;
			if (js_hypot(o.x - x, o.z - z) < lim) return false;
		}
		return true;
	};
	auto add = [&](double x, double z, int i, int j, const std::string &type, int cid) {
		double pop = type == "vil" ? .015 + rr() * .05 : type == "town" ? .12 + rr() * .4 : type == "cap" ? state_pop[cid] * (.08 + rr() * .06) : .5 + rr() * 2.2;
		Town t;
		t.name = nm(type == "vil");
		t.x = x;
		t.z = z;
		t.node = C.bNode(i, j);
		t.type = type;
		t.pop = pop;
		t.cid = cid;
		T.push_back(std::move(t));
	};
	// capitals: on the state's biggest piece of land, the lattice node closest to the seed, off the border
	for (size_t ci_ = 0; ci_ < w.countries.size(); ci_++) {
		const Country &c = w.countries[ci_];
		double cx = double(c.cap_x) / C.MW * C.WX - C.WX / 2, cz = double(c.cap_y) / C.MH * C.WZ - C.WZ / 2;
		int ci = int(js_round((cx + C.WX / 2) / B.st)), cj = int(js_round((cz + C.WZ / 2) / B.st));
		const int R = 26, W = 2 * R + 1;
		std::vector<int8_t> own(W * W, 0);
		std::vector<int> lab(W * W, -1), sz;
		for (int dj = -R; dj <= R; dj++)
			for (int di = -R; di <= R; di++) {
				int i = ci + di, j = cj + dj;
				if (i < 1 || j < 1 || i >= B.nx - 1 || j >= B.nz - 1) continue;
				double x, z;
				near(i, j, x, z);
				if (C.bInland(x, z) == int(ci_)) own[(dj + R) * W + di + R] = 1;
			}
		static const int d8b[8][2] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {1, -1}, {-1, 1}};
		for (int s = 0; s < W * W; s++) {
			if (!own[s] || lab[s] >= 0) continue;
			int L = int(sz.size()), n = 0;
			std::vector<int> st = {s};
			lab[s] = L;
			while (!st.empty()) {
				int q = st.back();
				st.pop_back();
				n++;
				int qx = q % W, qy = q / W;
				for (auto &d : d8b) {
					int nx = qx + d[0], ny = qy + d[1];
					if (nx < 0 || ny < 0 || nx >= W || ny >= W) continue;
					int t = ny * W + nx;
					if (own[t] && lab[t] < 0) { lab[t] = L; st.push_back(t); }
				}
			}
			sz.push_back(n);
		}
		int big = -1;
		for (int L = 0; L < int(sz.size()); L++)
			if (big < 0 || sz[L] > sz[big]) big = L;
		bool found = false;
		double bd = 1e9, bx = 0, bz = 0;
		int bi = 0, bj = 0;
		for (int dj = -R; dj <= R; dj++)
			for (int di = -R; di <= R; di++) {
				int s = (dj + R) * W + di + R;
				if (lab[s] != big || big < 0) continue;
				double x, z;
				near(ci + di, cj + dj, x, z);
				double d = di * di + dj * dj + (C.onBorder(x, z, int(ci_)) ? 400 : 0);
				if (d < bd) { bd = d; bx = x; bz = z; bi = ci + di; bj = cj + dj; found = true; }
			}
		if (found) add(bx, bz, bi, bj, "cap", int(ci_));
	}
	auto place = [&](int n, double min, const std::string &type) {
		for (int q = 0, t = 0; q < n && t < n * 600; t++) {
			int i = 2 + int(std::floor(rr() * (B.nx - 4))), j = 2 + int(std::floor(rr() * (B.nz - 4)));
			double x, z;
			near(i, j, x, z);
			int o = (type == "vil" || rr() < .5) ? C.bOwn(x, z) : C.bInland(x, z);
			if (o < 0 || C.onBorder(x, z, o) || !ok(x, z, type, min)) continue;
			add(x, z, i, j, type, o);
			q++;
		}
	};
	{
		double A = C.WX * C.WZ / 384;
		place(int(js_round(30 * A)), 1, "city");
		place(int(js_round(105 * A)), .55, "town");
	}
	std::map<int, int> area;
	for (int j = 1; j < B.nz - 1; j++)
		for (int i = 1; i < B.nx - 1; i++) {
			double x, z;
			near(i, j, x, z);
			int o = C.bOwn(x, z);
			if (o >= 0) area[o]++;
		}
	auto needN = [&](int cid) { auto it = area.find(cid); int a = it == area.end() ? 0 : it->second; return int(clampd(4 + js_round(a / 260.0), 4, 10)); };
	// every state gets its minimum of settlements
	{
		Mulberry r2(seed ^ 0x3a77u);
		for (size_t cid = 0; cid < w.countries.size(); cid++) {
			int n = 0;
			for (auto &t : T)
				if (t.cid == int(cid)) n++;
			int need = needN(int(cid));
			if (n >= need) continue;
			struct Cand { double x, z; int i, j; };
			std::vector<Cand> cand;
			for (int pass = 0; pass < 2 && n < need; pass++) {
				bool tiny = pass == 1;
				cand.clear();
				for (int j = 1; j < B.nz - 1; j++)
					for (int i = 1; i < B.nx - 1; i++) {
						double x, z;
						near(i, j, x, z);
						double q = B.st * .3;
						if (C.bOwn(x + 1e-4, z + 1e-4) < 0 && !tiny) continue;
						if (C.bOwn(x + 1e-4, z + 1e-4) == int(cid)) { cand.push_back({x, z, i, j}); cand.push_back({x, z, i, j}); }
						if (C.bOwn(x + q, z + q) == int(cid) || C.bOwn(x - q, z + q) == int(cid) || C.bOwn(x + q, z - q) == int(cid) || C.bOwn(x - q, z - q) == int(cid))
							cand.push_back({x, z, i, j});
					}
				const size_t L = cand.size();
				for (size_t k = 0; k < L * 6 && n < need && L; k++) {
					const Cand q = cand[size_t(std::floor(r2() * L))];
					int node = C.bNode(q.i, q.j);
					bool taken = false;
					for (auto &o : T)
						if (o.node == node) { taken = true; break; }
					if (taken) continue;
					if (k < L * 3 ? C.onBorder(q.x, q.z, int(cid)) : n >= 3) continue;
					if (!ok(q.x, q.z, "town", k < L * 2 ? .3 : k < L * 4 ? .14 : .05)) continue;
					add(q.x, q.z, q.i, q.j, "town", int(cid));
					T.back().extra = true;
					n++;
				}
			}
		}
	}
	// the five biggest cities
	std::vector<Town *> cities;
	for (auto &t : T)
		if (t.type == "city") cities.push_back(&t);
	std::stable_sort(cities.begin(), cities.end(), [](Town *a, Town *b) { return b->pop - a->pop < 0; });
	for (size_t i = 0; i < cities.size() && i < 5; i++) cities[i]->type = "big";
}

// ---------- bCrossings ----------
struct Cross { double ws, s, x, z; int a, b; };
template <typename F>
std::vector<Cross> b_crossings(const Ctx &C, const std::vector<F> &pts, double eco) {
	std::vector<Cross> out;
	const double step = C.B.st * .12;
	double s = 0;
	int prev = -1;
	double px = pts[0], pz = pts[1], ps = 0;
	for (size_t i = 2; i < pts.size(); i += 2) {
		double x0 = pts[i - 2], z0 = pts[i - 1], x1 = pts[i], z1 = pts[i + 1], L = js_hypot(x1 - x0, z1 - z0);
		if (!L) continue;
		int n = std::max(1, int(std::ceil(L / step)));
		for (int k = (i == 2 ? 0 : 1); k <= n; k++) {
			double t = double(k) / n, x = x0 + (x1 - x0) * t, z = z0 + (z1 - z0) * t;
			int o = C.bOwn(x, z);
			if (o >= 0) {
				if (prev >= 0 && o != prev) {
					double ax = px, az = pz, bx = x, bz = z, as = ps, bs = s + L * t;
					for (int q = 0; q < 14; q++) {
						double mx = (ax + bx) / 2, mz = (az + bz) / 2, ms = (as + bs) / 2;
						int m = C.bOwn(mx, mz);
						if (m == prev) { ax = mx; az = mz; as = ms; }
						else { bx = mx; bz = mz; bs = ms; }
					}
					double ws = (as + bs) / 2;
					if (out.empty() || ws - out.back().ws > .12) out.push_back({ws, ws * eco, (ax + bx) / 2, (az + bz) / 2, prev, o});
				}
				prev = o;
				px = x;
				pz = z;
				ps = s + L * t;
			}
		}
		s += L;
	}
	for (int i = 1; i < int(out.size()); i++)
		if (out[i].a == out[i - 1].b && out[i].b == out[i - 1].a && out[i].ws - out[i - 1].ws < .3) {
			out.erase(out.begin() + (i - 1), out.begin() + (i + 1));
			i = std::max(0, i - 2);
		}
	return out;
}

// ---------- roadWeb: Poisson-disk points + Gabriel graph per state + pruning of sharp angles ----------
struct WebPt { double x, z; int cid; int town; };
std::vector<std::pair<WebPt, WebPt>> road_web(const Ctx &C, uint32_t seed, double SP) {
	const Board &B = C.B;
	Mulberry rf(seed ^ 0x5151u);
	const double cl = SP * .15;
	std::vector<WebPt> pts;
	auto okAt = [&](double x, double z) {
		int o = C.bOwn(x, z);
		if (o < 0) return -1;
		const double off[8][2] = {{cl, 0}, {-cl, 0}, {0, cl}, {0, -cl}, {cl * .7, cl * .7}, {-cl * .7, -cl * .7}, {cl * .7, -cl * .7}, {-cl * .7, cl * .7}};
		for (auto &d : off)
			if (C.bOwn(x + d[0], z + d[1]) != o) return -1;
		return o;
	};
	const double cs = SP / SQRT2;
	const int GW = int(std::ceil(C.WX / cs)), GH = int(std::ceil(C.WZ / cs));
	std::vector<int> grid(size_t(GW) * GH, -1);
	auto gi = [&](double x, double z) { return int(std::floor((z + C.WZ / 2) / cs)) * GW + int(std::floor((x + C.WX / 2) / cs)); };
	auto freeAt = [&](double x, double z, double r) {
		int i = int(std::floor((x + C.WX / 2) / cs)), j = int(std::floor((z + C.WZ / 2) / cs));
		for (int v = j - 2; v <= j + 2; v++)
			for (int u = i - 2; u <= i + 2; u++) {
				if (u < 0 || v < 0 || u >= GW || v >= GH) continue;
				int k = grid[size_t(v) * GW + u];
				if (k >= 0 && js_hypot(pts[k].x - x, pts[k].z - z) < r) return false;
			}
		return true;
	};
	auto put = [&](const WebPt &p) {
		int k = gi(p.x, p.z);
		if (k < 0 || k >= int(grid.size())) return;
		pts.push_back(p);
		grid[k] = int(pts.size()) - 1;
	};
	for (size_t ti = 0; ti < B.towns.size(); ti++) {
		const Town &t = B.towns[ti];
		if (freeAt(t.x, t.z, SP * .3)) put({t.x, t.z, t.cid, int(ti)});
	}
	std::vector<int> act;
	for (double z = -C.WZ / 2 + SP / 2; z < C.WZ / 2; z += SP * 1.7)
		for (double x = -C.WX / 2 + SP / 2; x < C.WX / 2; x += SP * 1.7) {
			double px = x + (rf() - .5) * SP;
			double pz = z + (rf() - .5) * SP;
			int o = okAt(px, pz);
			if (o < 0 || !freeAt(px, pz, SP)) continue;
			put({px, pz, o, -1});
			act.push_back(int(pts.size()) - 1);
		}
	while (!act.empty()) {
		size_t ai = size_t(std::floor(rf() * act.size()));
		const double ax = pts[act[ai]].x, az = pts[act[ai]].z;
		bool found = false;
		for (int k = 0; k < 24; k++) {
			double ang = rf() * PI * 2;
			double r = SP * (1 + rf());
			double x = ax + std::cos(ang) * r, z = az + std::sin(ang) * r;
			if (x < -C.WX / 2 || z < -C.WZ / 2 || x >= C.WX / 2 || z >= C.WZ / 2) continue;
			int o = okAt(x, z);
			if (o < 0 || !freeAt(x, z, SP)) continue;
			put({x, z, o, -1});
			act.push_back(int(pts.size()) - 1);
			found = true;
			break;
		}
		if (!found) act.erase(act.begin() + ai);
	}
	// Gabriel graph per state (states in ascending id order, like integer keys of a JS object)
	std::map<int, std::vector<int>> by;
	for (size_t i = 0; i < pts.size(); i++) by[pts[i].cid].push_back(int(i));
	struct E { int a, b; double d; };
	std::vector<E> Es;
	for (auto &kv : by) {
		const auto &L = kv.second;
		for (size_t a = 0; a < L.size(); a++)
			for (size_t b = a + 1; b < L.size(); b++) {
				const WebPt &P = pts[L[a]], &Q = pts[L[b]];
				double d = js_hypot(P.x - Q.x, P.z - Q.z);
				if (d > SP * 4.2) continue;
				double mx = (P.x + Q.x) / 2, mz = (P.z + Q.z) / 2, r2 = (d / 2) * (d / 2) * .98;
				bool good = true;
				for (int c : L) {
					if (c == L[a] || c == L[b]) continue;
					const WebPt &R = pts[c];
					double ex = R.x - mx, ez = R.z - mz;
					if (ex * ex + ez * ez < r2) { good = false; break; }
				}
				if (good) Es.push_back({L[a], L[b], d});
			}
	}
	std::stable_sort(Es.begin(), Es.end(), [](const E &a, const E &b) { return a.d - b.d < 0; });
	std::vector<std::vector<int>> adj(pts.size());
	std::vector<std::pair<WebPt, WebPt>> keep;
	for (auto &e : Es) {
		bool bad = false;
		int uv[2][2] = {{e.a, e.b}, {e.b, e.a}};
		for (auto &p : uv) {
			const WebPt &U = pts[p[0]], &V = pts[p[1]];
			double an = std::atan2(V.z - U.z, V.x - U.x);
			for (int wi : adj[p[0]]) {
				const WebPt &W = pts[wi];
				double aw = std::atan2(W.z - U.z, W.x - U.x);
				double df = std::fabs(an - aw);
				if (df > PI) df = 2 * PI - df;
				if (df < .6) { bad = true; break; }
			}
			if (bad) break;
		}
		if (bad) continue;
		keep.push_back({pts[e.a], pts[e.b]});
		adj[e.a].push_back(e.b);
		adj[e.b].push_back(e.a);
	}
	return keep;
}

} // namespace

template <typename F>
std::vector<Crossing> board_crossings_t(const World &w, const Board &b, const std::vector<F> &pts, double eco) {
	Board &bb = const_cast<Board &>(b);
	Ctx C(w, bb);
	std::vector<Crossing> out;
	if (pts.size() < 4) return out;
	for (auto &c : b_crossings(C, pts, eco)) out.push_back({c.ws, c.s, c.x, c.z, c.a, c.b});
	return out;
}

std::vector<Crossing> board_crossings(const World &w, const Board &b, const std::vector<float> &pts, double eco) {
	return board_crossings_t(w, b, pts, eco);
}

std::vector<Crossing> board_crossings(const World &w, const Board &b, const std::vector<double> &pts, double eco) {
	return board_crossings_t(w, b, pts, eco);
}

namespace {
// the roads, railways, ports, airports and checkpoints of a board whose towns are placed (boardRoads,
// boardPorts, boardCheckpoints); net: the roads and railways drawn in the editor (nullptr: generated)
void finish_board(uint32_t seed, Ctx &C, bool fine, const BoardNet *net, bool given_towns) {
	Board &B = C.B;
	const World &w = C.w;
	auto &T = B.towns;

	// ---------- boardRoads ----------
	const int N = B.nx * B.nz;
	std::vector<uint8_t> usedE(size_t(N) * 8, 0), usedR(size_t(N) * 8, 0);
	B.bits.assign(N, 0);
	B.rbits.assign(N, 0);
	std::vector<float> terr(N);
	std::vector<int> own(N);
	{
		Mulberry pr(seed ^ 0x77u);
		Perlin pn(pr);
		for (int n = 0; n < N; n++) {
			double x, z;
			C.bXY(n, x, z);
			own[n] = C.bOwn(x, z);
			terr[n] = own[n] < 0 ? 1e9f : float(1 + .35 * std::max(-1.0, std::min(1.0, pn(x * .35, z * .35) * 1.6)));
		}
	}
	auto &comp = B.comp;
	comp.assign(N, -1);
	{
		int k = 0;
		for (int n = 0; n < N; n++) {
			if (own[n] < 0 || comp[n] >= 0) continue;
			std::vector<int> st = {n};
			comp[n] = k;
			while (!st.empty()) {
				int m = st.back();
				st.pop_back();
				int x = m % B.nx, y = m / B.nx;
				for (auto &d : D8) {
					int nx = x + d[0], ny = y + d[1];
					if (nx < 0 || ny < 0 || nx >= B.nx || ny >= B.nz) continue;
					int q = ny * B.nx + nx;
					if (own[q] >= 0 && comp[q] < 0) { comp[q] = k; st.push_back(q); }
				}
			}
			k++;
		}
		B.csz.assign(k, 0);
		for (int n = 0; n < N; n++)
			if (comp[n] >= 0) B.csz[comp[n]]++;
	}
	const int tinyMin = fine ? TINY_ISL * 4 : TINY_ISL;   // the same land area in nodes
	auto tinyN = [&](int n) { return comp[n] < 0 || B.csz[comp[n]] < tinyMin; };
	if (!net) {
	// a capital cut off from its towns moves to the biggest town of the state's main landmass
	for (size_t cid = 0; cid < (given_towns ? 0 : w.countries.size()); cid++) {   // the editor's capitals stay
		std::vector<Town *> ts;
		for (auto &t : T)
			if (t.cid == int(cid) && comp[t.node] >= 0) ts.push_back(&t);
		Town *cap = nullptr;
		for (auto *t : ts)
			if (t->type == "cap") { cap = t; break; }
		if (!cap) continue;
		std::vector<std::pair<int, double>> grp;   // insertion-ordered Map
		for (auto *t : ts) {
			int g = comp[t->node];
			auto it = std::find_if(grp.begin(), grp.end(), [&](auto &e) { return e.first == g; });
			if (it == grp.end()) grp.push_back({g, t->type == "vil" ? .3 : 1});
			else it->second += t->type == "vil" ? .3 : 1;
		}
		int bg = comp[cap->node];
		double bn = 0;
		for (auto &e : grp)
			if (e.first == bg) bn = e.second;
		for (auto &e : grp) {
			if (!(e.second > bn + .5)) continue;
			Town *first = nullptr;
			for (auto *t : ts)
				if (comp[t->node] == e.first) { first = t; break; }
			if (!tinyN(first->node)) { bg = e.first; bn = e.second; }
		}
		if (bg == comp[cap->node]) continue;
		std::vector<Town *> cand;
		for (auto *t : ts)
			if (comp[t->node] == bg && t->type != "vil") cand.push_back(t);
		std::stable_sort(cand.begin(), cand.end(), [](Town *a, Town *b) { return b->pop - a->pop < 0; });
		if (cand.empty()) continue;
		Town *nc = cand[0];
		cap->type = "city";
		nc->type = "cap";
		nc->pop = std::max(nc->pop, cap->pop);
	}
	// edges that lie on land
	std::vector<uint8_t> eok(size_t(N) * 8, 0);
	{
		const double st = B.st;
		auto OW = [&](double u, double v) { return C.bOwn(-C.WX / 2 + u * st, -C.WZ / 2 + v * st); };
		auto LD = [&](double u, double v) { return OW(u, v) >= 0; };
		auto OK2 = [&](double u1, double v1, double u2, double v2) {
			int a = OW(u1, v1), b = OW(u2, v2);
			return (a >= 0 || b >= 0) && !(a >= 0 && b >= 0 && a != b);
		};
		for (int n = 0; n < N; n++) {
			if (own[n] < 0) continue;
			int x = n % B.nx, y = n / B.nx;
			for (int d = 0; d < 8; d++) {
				int dx = D8[d][0], dy = D8[d][1], x2 = x + dx, y2 = y + dy;
				if (x2 < 0 || y2 < 0 || x2 >= B.nx || y2 >= B.nz) continue;
				double mx = x + dx / 2.0, my = y + dy / 2.0;
				bool ok;
				if (!dx || !dy) {
					double px = -dy, py = dx;
					ok = OK2(mx + px * .2, my + py * .2, mx - px * .2, my - py * .2);
				} else if (fine) {   // a diagonal of a quarter square: land on both sides of its middle, one state
					double px = -dy / SQRT2, py = dx / SQRT2;
					ok = OK2(mx + px * .25, my + py * .25, mx - px * .25, my - py * .25) && LD(mx, my);
				} else {
					int ci = std::min(x, x2), cj = std::min(y, y2);
					int sd = (!w.sqd.empty() && ci < w.sqw && cj < w.sqh) ? w.sqd[size_t(cj) * w.sqw + ci] : (dx * dy > 0 ? 1 : 0);
					bool along = (dx * dy > 0) == (sd == 1);
					if (along) {
						double px = -dy / SQRT2, py = dx / SQRT2;
						ok = OK2(mx + px * .25, my + py * .25, mx - px * .25, my - py * .25);
					} else {
						double c00, c01, c10, c11;
						if (sd) { c00 = 2.0 / 3; c01 = 1.0 / 3; c10 = 1.0 / 3; c11 = 2.0 / 3; }
						else { c00 = 1.0 / 3; c01 = 1.0 / 3; c10 = 2.0 / 3; c11 = 2.0 / 3; }
						ok = LD(ci + c00, cj + c01) && LD(ci + c10, cj + c11);
					}
				}
				eok[size_t(n) * 8 + d] = ok ? 1 : 0;
			}
		}
	}
	// A* over (node, arrival direction): turn penalties, road reuse, terrain; railways keep their own corridor
	bool railMode = false;
	std::vector<uint8_t> *RSu = &usedE, *RSb = &B.bits;
	std::vector<float> g;
	std::vector<int> prevS;
	auto route = [&](int a, int b, double lv, int lockC) {
		if (tinyN(a) || tinyN(b)) return;
		const int S = N * 9;
		g.assign(S, 1e9f);
		prevS.assign(S, -1);
		Heap h;
		const int bi = b % B.nx, bj = b / B.nx;
		auto hh = [&](int n) {
			int dx = std::abs(n % B.nx - bi), dz = std::abs(n / B.nx - bj);
			return (std::max(dx, dz) + .4142 * std::min(dx, dz)) * .45;
		};
		const int s0 = a * 9 + 8;
		g[s0] = 0;
		h.push(hh(a), s0);
		int end = -1;
		auto &U = *RSu;
		auto &Bb = *RSb;
		while (!h.empty()) {
			int s = h.pop(), n = s / 9, dir = s % 9;
			if (n == b) { end = s; break; }
			double gs = g[s];
			int x = n % B.nx, y = n / B.nx;
			for (int d = 0; d < 8; d++) {
				if (dir < 8) {
					int df0 = std::min(std::abs(d - dir), 8 - std::abs(d - dir));
					if (df0 > 2) continue;
				}
				int nx = x + D8[d][0], ny = y + D8[d][1];
				if (nx < 0 || ny < 0 || nx >= B.nx || ny >= B.nz) continue;
				int m = ny * B.nx + nx;
				int df = dir < 8 ? std::min(std::abs(d - dir), 8 - std::abs(d - dir)) : 0;
				if (terr[m] >= 1e9f || !eok[size_t(n) * 8 + d] || (lockC >= 0 && own[m] != lockC)) continue;
				double base = (d & 1) ? 1.4142 : 1;
				double mul;
				if (U[size_t(n) * 8 + d]) mul = railMode ? .2 : (fine ? .62 : .32);   // the test net: roads merge less, more ways
				else mul = double(terr[m]) * (railMode ? 1.15 * (usedE[size_t(n) * 8 + d] ? 6 : (B.bits[m] && m != b) ? 1.8 : 1) : 1);
				double c = base * mul + (df == 1 ? (railMode ? 1.1 : .35) : df == 2 ? (railMode ? 9 : 1.6) : 0) + (own[m] != own[n] ? .6 : 0);
				int ns = m * 9 + d;
				double ng = gs + c;
				if (ng < double(g[ns])) {
					g[ns] = float(ng);
					prevS[ns] = s;
					h.push(ng + hh(m), ns);
				}
			}
		}
		if (end < 0) return;
		std::vector<int> nodes;
		for (int s = end; s >= 0; s = prevS[s]) nodes.push_back(s / 9);
		std::reverse(nodes.begin(), nodes.end());
		for (size_t k = 1; k < nodes.size(); k++) {
			int a_ = nodes[k - 1], b_ = nodes[k];
			int dx = b_ % B.nx - a_ % B.nx, dz = b_ / B.nx - a_ / B.nx;
			int d = -1;
			for (int q = 0; q < 8; q++)
				if (D8[q][0] == dx && D8[q][1] == dz) { d = q; break; }
			U[size_t(a_) * 8 + d] = 1;
			U[size_t(b_) * 8 + ((d + 4) % 8)] = 1;
			Bb[a_] |= uint8_t(1 << d);
			Bb[b_] |= uint8_t(1 << ((d + 4) % 8));
		}
		std::vector<float> pts;
		for (int n : nodes) {
			double x, z;
			C.bXY(n, x, z);
			pts.push_back(float(x));
			pts.push_back(float(z));
		}
		if (pts.size() >= 4) {
			if (railMode) B.rail.push_back(std::move(pts));
			else B.hw.push_back({lv, std::move(pts)});
		}
	};
	Mulberry rr2(seed ^ 0x99u);
	auto same = [&](const Town &a, const Town &b) { return comp[a.node] == comp[b.node]; };
	auto dist = [&](const Town &a, const Town &b) { return same(a, b) ? js_hypot(a.x - b.x, a.z - b.z) : 1e9; };
	auto key = [](int a, int b) { return int64_t(std::min(a, b)) * 1000000 + std::max(a, b); };
	std::vector<int> cities;
	for (size_t i = 0; i < T.size(); i++)
		if (T[i].type != "town" && T[i].type != "vil") cities.push_back(int(i));
	// 1. motorways: spanning tree over the cities + each city to its nearest neighbours
	std::set<int64_t> seen;
	struct Link { int a, b; double lv; };
	std::vector<Link> links;
	auto addL = [&](int a, int b, double lv) {
		int64_t k = key(T[a].node, T[b].node);
		if (seen.count(k)) return;
		seen.insert(k);
		links.push_back({a, b, lv});
	};
	if (!cities.empty()) {
		std::vector<int> inT = {cities[0]}, rest(cities.begin() + 1, cities.end());
		while (!rest.empty()) {
			double bd = 1e9;
			size_t bi = 0;
			int bo = -1;
			for (size_t i = 0; i < rest.size(); i++)
				for (int o : inT) {
					double d = dist(T[rest[i]], T[o]);
					if (d < bd) { bd = d; bi = i; bo = o; }
				}
			int c = rest[bi];
			rest.erase(rest.begin() + bi);
			if (bd < 1e8) addL(bo, c, 3);
			inT.push_back(c);
		}
	}
	for (int c : cities) {
		std::vector<int> others;
		for (int o : cities)
			if (o != c) others.push_back(o);
		std::stable_sort(others.begin(), others.end(), [&](int a, int b) { return dist(T[a], T[c]) - dist(T[b], T[c]) < 0; });
		for (size_t q = 0; q < others.size() && q < (fine ? 6u : 4u); q++)
			if (dist(T[others[q]], T[c]) < (fine ? (q < 3 ? 8 : 5.5) : (q < 2 ? 7 : 4.5))) addL(c, others[q], 3);
	}
	for (auto &l : links) route(T[l.a].node, T[l.b].node, l.lv, -1);
	// 2. towns: 2–4 links each; 3. villages
	std::set<int64_t> lk;
	auto link = [&](int a, int b, double lv) {
		int64_t k = key(T[a].node, T[b].node);
		if (lk.count(k) || seen.count(k)) return;
		lk.insert(k);
		route(T[a].node, T[b].node, lv, -1);
	};
	std::vector<int> net = cities;
	{
		std::vector<int> towns;
		for (size_t i = 0; i < T.size(); i++)
			if (T[i].type == "town") towns.push_back(int(i));
		auto minC = [&](int t) { double m = INFINITY; for (int c : cities) m = std::min(m, dist(T[t], T[c])); return m; };
		std::stable_sort(towns.begin(), towns.end(), [&](int a, int b) { return minC(a) - minC(b) < 0; });
		for (int t : towns) {
			std::vector<int> nr = net;
			std::stable_sort(nr.begin(), nr.end(), [&](int a, int b) { return dist(T[a], T[t]) - dist(T[b], T[t]) < 0; });
			for (size_t q = 0; q < nr.size() && q < (fine ? 6u : 4u); q++) {
				double d = dist(T[nr[q]], T[t]);
				if (fine ? d < 1e8 && (q < 2 || d < 3.4) : d < 1e8 && (q == 0 || (d < (q == 1 ? 3 : 2.4) && (q < 3 || rr2() < .5)))) link(t, nr[q], 2);
			}
			net.push_back(t);
		}
		for (size_t vi = 0; vi < T.size(); vi++) {
			if (T[vi].type != "vil") continue;
			int v = int(vi);
			std::vector<int> nr = net;
			std::stable_sort(nr.begin(), nr.end(), [&](int a, int b) { return dist(T[a], T[v]) - dist(T[b], T[v]) < 0; });
			for (size_t q = 0; q < nr.size() && q < (fine ? 4u : 3u); q++) {
				double d = dist(T[nr[q]], T[v]);
				if (fine ? d < 1e8 && (q < 2 || d < 2.4) : d < 1e8 && (q == 0 || (d < (q == 1 ? 3 : 1.9) && (q < 2 || rr2() < .5)))) link(v, nr[q], 1.5);
			}
			net.push_back(v);
		}
	}
	// 4. the countryside web (never across a border)
	{
		auto web = road_web(C, seed, fine ? .26 : .4);
		std::set<int64_t> fk;
		for (auto &e : web) {
			const WebPt &p = e.first, &q = e.second;
			int a = p.town >= 0 ? T[p.town].node : C.nodeAt(p.x, p.z), b = q.town >= 0 ? T[q.town].node : C.nodeAt(q.x, q.z);
			if (a == b) continue;
			int64_t k = key(a, b);
			if (fk.count(k) || lk.count(k) || seen.count(k)) continue;
			fk.insert(k);
			route(a, b, 1, p.cid);
		}
	}
	// railways
	railMode = true;
	RSu = &usedR;
	RSb = &B.rbits;
	std::set<int64_t> rseen;
	auto rl = [&](int a, int b) {
		int64_t k = key(T[a].node, T[b].node);
		if (rseen.count(k) || dist(T[a], T[b]) >= 1e8) return;
		rseen.insert(k);
		route(T[a].node, T[b].node, 0, -1);
	};
	std::vector<int> caps, bigs, cits;
	for (size_t i = 0; i < T.size(); i++)
		if (T[i].type == "cap" && w.countries[T[i].cid].area > 2500) caps.push_back(int(i));
	if (caps.empty())
		for (size_t i = 0; i < T.size(); i++)
			if (T[i].type == "cap") caps.push_back(int(i));
	for (size_t i = 0; i < T.size(); i++) {
		if (T[i].type == "big") bigs.push_back(int(i));
		if (T[i].type == "city") cits.push_back(int(i));
	}
	if (!caps.empty()) {
		std::vector<int> inT = {caps[0]}, rest(caps.begin() + 1, caps.end());
		while (!rest.empty()) {
			double bd = 1e9;
			size_t bi = 0;
			int bo = -1;
			for (size_t i = 0; i < rest.size(); i++)
				for (int o : inT) {
					double d = dist(T[rest[i]], T[o]);
					if (d < bd) { bd = d; bi = i; bo = o; }
				}
			int c = rest[bi];
			rest.erase(rest.begin() + bi);
			if (bd < 1e8 && bd < 9) rl(bo, c);
			inT.push_back(c);
		}
	}
	for (int c : caps) {
		std::vector<int> others;
		for (int o : caps)
			if (o != c) others.push_back(o);
		std::stable_sort(others.begin(), others.end(), [&](int a, int b) { return dist(T[a], T[c]) - dist(T[b], T[c]) < 0; });
		for (size_t q = 0; q < others.size() && q < 2; q++)
			if (dist(T[others[q]], T[c]) < 6) rl(c, others[q]);
	}
	for (int bg : bigs) {
		int cap = -1;
		for (int c : caps)
			if (T[c].cid == T[bg].cid) { cap = c; break; }
		if (cap < 0 && !caps.empty()) {
			std::vector<int> s = caps;
			std::stable_sort(s.begin(), s.end(), [&](int x, int y) { return dist(T[x], T[bg]) - dist(T[y], T[bg]) < 0; });
			cap = s[0];
		}
		if (cap >= 0) rl(bg, cap);
		std::vector<int> o;
		for (int x : bigs)
			if (x != bg && x != cap) o.push_back(x);
		for (int x : caps)
			if (x != bg && x != cap) o.push_back(x);
		std::stable_sort(o.begin(), o.end(), [&](int x, int y) { return dist(T[x], T[bg]) - dist(T[y], T[bg]) < 0; });
		if (!o.empty() && dist(T[o[0]], T[bg]) < 5) rl(bg, o[0]);
	}
	for (int c : cits) {
		std::vector<int> o = caps;
		o.insert(o.end(), bigs.begin(), bigs.end());
		std::stable_sort(o.begin(), o.end(), [&](int x, int y) { return dist(T[x], T[c]) - dist(T[y], T[c]) < 0; });
		if (!o.empty() && dist(T[o[0]], T[c]) < 6) rl(c, o[0]);
	}
	} else {
		// the drawn net: the lattice bits along every polyline (each step joins two neighbouring nodes)
		auto fill = [&](const std::vector<float> &p, std::vector<uint8_t> &bits) {
			auto ij = [&](size_t k, int &i, int &j) {
				i = clampi(int(js_round((double(p[k]) + C.WX / 2) / B.st)), 0, B.nx - 1);
				j = clampi(int(js_round((double(p[k + 1]) + C.WZ / 2) / B.st)), 0, B.nz - 1);
			};
			for (size_t k = 2; k + 1 < p.size(); k += 2) {
				int i0, j0, i1, j1;
				ij(k - 2, i0, j0);
				ij(k, i1, j1);
				for (int g = 0; (i0 != i1 || j0 != j1) && g < 5000; g++) {
					const int sx = (i1 > i0) - (i1 < i0), sz = (j1 > j0) - (j1 < j0);
					int d = -1;
					for (int q = 0; q < 8; q++)
						if (D8[q][0] == sx && D8[q][1] == sz) { d = q; break; }
					bits[size_t(j0) * B.nx + i0] |= uint8_t(1 << d);
					i0 += sx;
					j0 += sz;
					bits[size_t(j0) * B.nx + i0] |= uint8_t(1 << ((d + 4) % 8));
				}
			}
		};
		for (const auto &h : net->hw)
			if (h.p.size() >= 4) {
				B.hw.push_back(h);
				fill(h.p, B.bits);
			}
		for (const auto &r : net->rail)
			if (r.size() >= 4) {
				B.rail.push_back(r);
				fill(r, B.rbits);
			}
	}
	// ports and airports on tiny islands
	for (auto &t : T)
		if (tinyN(t.node) && t.port_ov != 0) t.port_ov = 1;
	{
		auto bWaterCell = [&](int ci, int cj) {
			if (ci < 0 || cj < 0 || ci >= B.nx - 1 || cj >= B.nz - 1) return false;
			double x0 = -C.WX / 2 + ci * B.st, z0 = -C.WZ / 2 + cj * B.st;
			static const double uv[5][2] = {{.25, .25}, {.75, .25}, {.25, .75}, {.75, .75}, {.5, .5}};
			for (auto &p : uv)
				if (C.bOwn(x0 + p[0] * B.st, z0 + p[1] * B.st) >= 0) return false;
			return true;
		};
		for (auto &t : T) {
			t.port = false;
			if (t.port_ov == 0) continue;
			if (t.type == "vil" && t.port_ov != 1) continue;
			double x = t.x, z = t.z, q = B.st * .3;
			int wv = 0;
			const double off[4][2] = {{q, q}, {-q, q}, {q, -q}, {-q, -q}};
			for (auto &d : off)
				if (C.bOwn(x + d[0], z + d[1]) < 0) wv++;
			if (!wv) continue;
			int i = int(js_round((t.x + C.WX / 2) / B.st)), j = int(js_round((t.z + C.WZ / 2) / B.st));
			bool got = false;
			int wi = 0, wj = 0;
			for (int r = 0; r <= 2 && !got; r++)
				for (int dj = -1 - r; dj <= r && !got; dj++)
					for (int di = -1 - r; di <= r; di++)
						if (bWaterCell(i + di, j + dj)) { wi = i + di; wj = j + dj; got = true; break; }
			if (!got) continue;
			if (t.type == "town" && t.port_ov != 1 && ((uint64_t(t.node) * 2654435761ull) & 0xFFFFFFFFull) % 10 >= 6) continue;
			t.port = true;
			t.wc_i = wi;
			t.wc_j = wj;
		}
	}
	for (auto &t : T)
		if (tinyN(t.node) && !t.port) t.air_ov = true;
	// border checkpoints
	{
		std::vector<std::pair<double, double>> seenP;
		auto scan = [&](const std::vector<float> &p, bool rail) {
			for (auto &c : b_crossings(C, p, 1)) {
				bool near = false;
				for (auto &q : seenP)
					if (js_hypot(q.first - c.x, q.second - c.z) < B.st * .3) { near = true; break; }
				if (near) continue;
				seenP.push_back({c.x, c.z});
				B.cps.push_back({c.x, c.z, c.a, c.b, rail});
			}
		};
		for (auto &h : B.hw) scan(h.p, false);
		for (auto &r : B.rail) scan(r, true);
	}
}
} // namespace

Board generate_board(uint32_t seed, const World &w, const std::vector<double> &state_pop, bool fine) {
	Board B;
	B.fine = fine;
	if (fine) B.st = .0625;
	Ctx C(w, B);
	B.wx = C.WX;
	B.wz = C.WZ;
	B.nx = int(js_round(C.WX / B.st)) + 1;
	B.nz = int(js_round(C.WZ / B.st)) + 1;
	gen_towns(C, seed, state_pop);
	finish_board(seed, C, fine, nullptr, false);
	return B;
}

Board generate_board_given(uint32_t seed, const World &w, const std::vector<double> &state_pop, bool fine, const std::vector<Town> &towns,
		const BoardNet *net) {
	Board B;
	B.fine = fine;
	if (fine) B.st = .0625;
	Ctx C(w, B);
	B.wx = C.WX;
	B.wz = C.WZ;
	B.nx = int(js_round(C.WX / B.st)) + 1;
	B.nz = int(js_round(C.WZ / B.st)) + 1;
	// the editor's towns: each on its lattice node, in the state that holds most of the land around it
	Mulberry rr(seed ^ 0x51abu);
	for (Town t : towns) {
		const int i = clampi(int(js_round((t.x + C.WX / 2) / B.st)), 0, B.nx - 1), j = clampi(int(js_round((t.z + C.WZ / 2) / B.st)), 0, B.nz - 1);
		double x, z;
		C.bXY(C.bNode(i, j), x, z);
		const double q = B.st * .3;
		int cnt[NEU + 1] = {};
		int best = -1;
		for (auto d : {std::pair<double, double>{q, q}, {-q, q}, {q, -q}, {-q, -q}}) {
			const int o = C.bOwn(x + d.first, z + d.second);
			if (o >= 0 && ++cnt[o] > (best >= 0 ? cnt[best] : 0)) best = o;
		}
		if (best < 0) continue;   // in the sea
		t.x = x;
		t.z = z;
		t.node = C.bNode(i, j);
		t.cid = best;
		if (!(t.pop > 0)) {
			const double sp = size_t(best) < state_pop.size() ? state_pop[size_t(best)] : 10;
			t.pop = t.type == "vil" ? .015 + rr() * .05 : t.type == "town" ? .12 + rr() * .4 : t.type == "cap" ? sp * (.08 + rr() * .06) : .5 + rr() * 2.2;
		}
		t.port = false;
		t.wc_i = t.wc_j = -1;
		B.towns.push_back(std::move(t));
	}
	finish_board(seed, C, fine, net, true);
	return B;
}

std::vector<int> edit_path(const World &w, bool fine, int a, int b) {
	Board B;
	B.fine = fine;
	if (fine) B.st = .0625;
	Ctx C(w, B);
	B.nx = int(js_round(C.WX / B.st)) + 1;
	B.nz = int(js_round(C.WZ / B.st)) + 1;
	const int NX = B.nx, NZ = B.nz, N = NX * NZ;
	if (a < 0 || b < 0 || a >= N || b >= N) return {};
	auto land = [&](double x, double z) { return C.bOwn(x, z) >= 0; };
	// a step lies on land when, at a quarter, the middle and three quarters of it, land is on one side at least
	auto ok = [&](int n, int m) {
		double x1, z1, x2, z2;
		C.bXY(n, x1, z1);
		C.bXY(m, x2, z2);
		for (double t : {.25, .5, .75}) {
			const double x = x1 + (x2 - x1) * t, z = z1 + (z2 - z1) * t, px = -(z2 - z1) * .2, pz = (x2 - x1) * .2;
			if (!land(x + px, z + pz) && !land(x - px, z - pz)) return false;
		}
		return true;
	};
	std::vector<float> g(size_t(N), 1e9f);
	std::vector<int> prev(size_t(N), -1);
	std::vector<uint8_t> done(size_t(N), 0);
	Heap h;
	const int bx = b % NX, bz = b / NX;
	g[size_t(a)] = 0;
	h.push(0, a);
	while (!h.empty()) {
		const int n = h.pop();
		if (done[size_t(n)]) continue;
		done[size_t(n)] = 1;
		if (n == b) break;
		const int x = n % NX, z = n / NX;
		for (auto &d : D8) {
			const int nx = x + d[0], nz = z + d[1];
			if (nx < 0 || nz < 0 || nx >= NX || nz >= NZ) continue;
			const int m = nz * NX + nx;
			if (done[size_t(m)] || !ok(n, m)) continue;
			const float ng = g[size_t(n)] + float(d[0] && d[1] ? 1.4142 : 1);
			if (ng < g[size_t(m)]) {
				g[size_t(m)] = ng;
				prev[size_t(m)] = n;
				h.push(ng + js_hypot(nx - bx, nz - bz), m);
			}
		}
	}
	if (g[size_t(b)] >= 1e9f) return {};
	std::vector<int> nodes;
	for (int n = b; n >= 0; n = prev[size_t(n)]) {
		nodes.push_back(n);
		if (n == a) break;
	}
	std::reverse(nodes.begin(), nodes.end());
	return nodes;
}

} // namespace tr
