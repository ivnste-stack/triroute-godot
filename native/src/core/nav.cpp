#include "nav.h"
#include "jsmath.h"

#include <algorithm>
#include <cmath>

namespace tr {

namespace {
const int D8[8][2] = {{1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1}};

struct Heap {   // the JS binary heap
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
	double top() const { return hk[0]; }
};
} // namespace

Nav::Nav(const World &w, const Board &b) : w_(w), b_(b) {
	const int N = b.nx * b.nz;
	nown_.resize(N);
	for (int n = 0; n < N; n++) {
		double x = -b.wx / 2 + (n % b.nx) * b.st, z = -b.wz / 2 + (n / b.nx) * b.st;
		nown_[n] = own_at(x, z);
	}
	const int W = b.nx - 1, H = b.nz - 1;
	water_.assign(size_t(W) * H, 0);
	for (int j = 0; j < H; j++)
		for (int i = 0; i < W; i++) {
			double x0 = -b.wx / 2 + i * b.st, z0 = -b.wz / 2 + j * b.st;
			static const double uv[5][2] = {{.25, .25}, {.75, .25}, {.25, .75}, {.75, .75}, {.5, .5}};
			bool wat = true;
			for (auto &p : uv)
				if (own_at(x0 + p[0] * b.st, z0 + p[1] * b.st) >= 0) { wat = false; break; }
			water_[size_t(j) * W + i] = wat ? 1 : 0;
		}
	// the bodies of water (squares joined by a side): ports on different ones have no sea route
	wcomp_.assign(size_t(W) * H, -1);
	int nc = 0;
	std::vector<int> q;
	for (int c0 = 0; c0 < W * H; c0++) {
		if (!water_[size_t(c0)] || wcomp_[size_t(c0)] >= 0) continue;
		wcomp_[size_t(c0)] = nc;
		q.assign(1, c0);
		while (!q.empty()) {
			const int c = q.back();
			q.pop_back();
			const int x = c % W, y = c / W;
			const int nb[4][2] = {{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}};
			for (auto &e : nb) {
				if (e[0] < 0 || e[1] < 0 || e[0] >= W || e[1] >= H) continue;
				const size_t m = size_t(e[1]) * W + e[0];
				if (water_[m] && wcomp_[m] < 0) {
					wcomp_[m] = nc;
					q.push_back(int(m));
				}
			}
		}
		nc++;
	}
}

int Nav::own_at(double x, double z) const {
	const int MW = w_.p.mw, MH = w_.p.mh;
	int px = int(std::floor((x + b_.wx / 2) / b_.wx * MW)), py = int(std::floor((z + b_.wz / 2) / b_.wz * MH));
	if (px < 0 || py < 0 || px >= MW || py >= MH) return -1;
	int o = w_.own[size_t(py) * MW + px];
	return o >= 0 && o < NEU ? o : -1;
}

bool Nav::blocked(int n, int m, bool rail, const Blocks &blk) const {
	if (!blk.ignore_wx && !blk.wx.empty() && (blk.wx[m] & (rail ? 2 : 1))) return true;
	int a = nown_[n], b = nown_[m];
	if (a == b || a < 0 || b < 0) return false;
	if (blk.closed_states.count(a) || blk.closed_states.count(b) || blk.closed_pairs.count(int64_t(a) * 1000 + b)) return true;
	if (!blk.closed_cps.empty()) {
		double x1 = -b_.wx / 2 + (n % b_.nx) * b_.st, z1 = -b_.wz / 2 + (n / b_.nx) * b_.st;
		double x2 = -b_.wx / 2 + (m % b_.nx) * b_.st, z2 = -b_.wz / 2 + (m / b_.nx) * b_.st;
		double mx = (x1 + x2) / 2, mz = (z1 + z2) / 2;
		for (auto &c : blk.closed_cps)
			if (js_hypot(mx - c.first, mz - c.second) < b_.st * 1.6) return true;
	}
	return false;
}

std::vector<float> Nav::path(int a, int b, bool rail, const Blocks *blk) const {
	return path(a, b, rail, blk, nullptr);
}

std::vector<float> Nav::path(int a, int b, bool rail, const Blocks *blk, const std::function<bool(int)> &bad) const {
	const int N = b_.nx * b_.nz;
	const auto &bits = rail ? b_.rbits : b_.bits;
	const bool useBlk = blk && blk->any();
	std::vector<float> g(N, 1e9f);
	std::vector<int> prev(N, -1);
	Heap h;
	std::vector<double> lastk(N, -1.0);   // stale heap entries are skipped (see Nav::sea)
	const double eps = b_.fine ? 1e-6 : 0.0;
	g[a] = 0;
	h.push(0, a);
	lastk[a] = 0;
	while (!h.empty()) {
		double kk = h.top();
		int n = h.pop();
		if (n == b) break;
		if (kk != lastk[n]) continue;
		int x = n % b_.nx, y = n / b_.nx;
		for (int d = 0; d < 8; d++) {
			if (!(bits[n] & (1 << d))) continue;
			int m = (y + D8[d][1]) * b_.nx + x + D8[d][0];
			if (useBlk && blocked(n, m, rail, *blk)) continue;
			if (bad && m != b && bad(m)) continue;
			double ng = double(g[n]) + ((d & 1) ? 1.4142 : 1) * b_.st;
			if (ng < double(g[m]) - eps) {
				g[m] = float(ng);
				prev[m] = n;
				h.push(ng, m);
				lastk[m] = ng;
			}
		}
	}
	if (g[b] >= 1e9f) return {};
	std::vector<int> nodes;
	for (int n = b; n >= 0; n = prev[n]) {
		nodes.push_back(n);
		if (n == a) break;
	}
	std::reverse(nodes.begin(), nodes.end());
	std::vector<float> pts;
	for (size_t k = 0; k < nodes.size(); k++) {
		if (k > 0 && k < nodes.size() - 1 && nodes[k] - nodes[k - 1] == nodes[k + 1] - nodes[k]) continue;
		pts.push_back(float(-b_.wx / 2 + (nodes[k] % b_.nx) * b_.st));
		pts.push_back(float(-b_.wz / 2 + (nodes[k] / b_.nx) * b_.st));
	}
	if (pts.size() < 4) {
		std::vector<float> p2 = pts;
		pts.insert(pts.end(), p2.begin(), p2.end());
	}
	return pts;
}

std::vector<float> Nav::path_w(int a, int b, bool rail, const Blocks *blk, const std::function<double(int, int)> &w) const {
	const int N = b_.nx * b_.nz;
	const auto &bits = rail ? b_.rbits : b_.bits;
	const bool useBlk = blk && blk->any();
	std::vector<float> g(N, 1e9f);
	std::vector<int> prev(N, -1);
	Heap h;
	std::vector<double> lastk(N, -1.0);   // stale heap entries are skipped (see Nav::sea)
	const double eps = b_.fine ? 1e-6 : 0.0;
	g[a] = 0;
	h.push(0, a);
	lastk[a] = 0;
	while (!h.empty()) {
		double kk = h.top();
		int n = h.pop();
		if (n == b) break;
		if (kk != lastk[n]) continue;
		int x = n % b_.nx, y = n / b_.nx;
		for (int d = 0; d < 8; d++) {
			if (!(bits[n] & (1 << d))) continue;
			int m = (y + D8[d][1]) * b_.nx + x + D8[d][0];
			if (useBlk && blocked(n, m, rail, *blk)) continue;
			double ng = double(g[n]) + ((d & 1) ? 1.4142 : 1) * b_.st * w(n, m);
			if (ng < double(g[m]) - eps) {
				g[m] = float(ng);
				prev[m] = n;
				h.push(ng, m);
				lastk[m] = ng;
			}
		}
	}
	if (g[b] >= 1e9f) return {};
	std::vector<int> nodes;
	for (int n = b; n >= 0; n = prev[n]) {
		nodes.push_back(n);
		if (n == a) break;
	}
	std::reverse(nodes.begin(), nodes.end());
	std::vector<float> pts;
	for (size_t k = 0; k < nodes.size(); k++) {
		if (k > 0 && k < nodes.size() - 1 && nodes[k] - nodes[k - 1] == nodes[k + 1] - nodes[k]) continue;
		pts.push_back(float(-b_.wx / 2 + (nodes[k] % b_.nx) * b_.st));
		pts.push_back(float(-b_.wz / 2 + (nodes[k] / b_.nx) * b_.st));
	}
	if (pts.size() < 4) {
		std::vector<float> p2 = pts;
		pts.insert(pts.end(), p2.begin(), p2.end());
	}
	return pts;
}

// Sea routes along the lines of the map's triangle mesh: from corner to corner of the lattice squares, along
// their sides and along the diagonal each square is drawn with (World::sqd: 1 the (0,0)-(1,1) diagonal, 0 the
// other one), so a route on the water follows the triangles instead of stepping through the squares' centres.
// A route keeps to open water (a side with land next to it costs more) and goes straight where it can: a small
// cost for every turn joins equal ways into long runs instead of a zigzag of short ones.
std::vector<float> Nav::sea(int ta, int tb) const {
	const Town &A = b_.towns[ta], &B = b_.towns[tb];
	if (A.wc_i < 0 || B.wc_i < 0) return {};
	const int W = b_.nx - 1, H = b_.nz - 1;          // lattice squares (water_)
	const int NX = b_.nx, NZ = b_.nz, N = NX * NZ;   // corners
	if (wcomp_[size_t(A.wc_j) * W + A.wc_i] != wcomp_[size_t(B.wc_j) * W + B.wc_i]) return {};   // different seas
	const double ST = b_.st;
	// map squares per lattice square: 1, or 2 on the fine test lattice (a map line every other lattice line)
	const int R = std::max(1, int(js_round(.125 / ST)));
	auto wat = [&](int i, int j) { return i >= 0 && j >= 0 && i < W && j < H && water_[size_t(j) * W + i] != 0; };
	auto diag = [&](int i, int j) {   // the diagonal of lattice square (i, j): 1 main, 0 the other, -1 none
		const int si = i / R, sj = j / R, a = i % R, b = j % R;
		const int d = (si < w_.sqw && sj < w_.sqh) ? w_.sqd[size_t(sj) * w_.sqw + si] : 0;
		if (d == 1) return a == b ? 1 : -1;
		return a + b == R - 1 ? 0 : -1;
	};
	static const int DX[8] = {1, 1, 0, -1, -1, -1, 0, 1}, DZ[8] = {0, 1, 1, 1, 0, -1, -1, -1};
	// the cost of the step from corner (x, z) in direction d, or < 0 when it is not a line of the mesh on water
	// relaxed: a second try when the mesh lines alone do not connect the ports (a strait one fine square wide):
	// steps off the lines are allowed then, at a price
	bool relaxed = false;
	auto step = [&](int x, int z, int d) -> double {
		const int dx = DX[d], dz = DZ[d], x2 = x + dx, z2 = z + dz;
		if (x2 < 0 || z2 < 0 || x2 >= NX || z2 >= NZ) return -1;
		if (dx && dz) {
			const int ci = std::min(x, x2), cj = std::min(z, z2);
			if (!wat(ci, cj)) return -1;
			const int want = (dx == dz) ? 1 : 0;
			return diag(ci, cj) == want ? 1.4142 : (relaxed ? 1.4142 * 3 : -1);
		}
		const double off = relaxed ? 3.0 : -1.0;
		if (dz == 0) {   // along a horizontal line: the squares above and below it
			const int ci = std::min(x, x2);
			const bool u = wat(ci, z - 1), v = wat(ci, z);
			const double c = (u && v) ? 1.0 : ((u || v) ? 2.5 : -1);
			return (c < 0 || z % R == 0) ? c : (off < 0 ? -1 : c * off);
		}
		const int cj = std::min(z, z2);
		const bool u = wat(x - 1, cj), v = wat(x, cj);
		const double c = (u && v) ? 1.0 : ((u || v) ? 2.5 : -1);
		return (c < 0 || x % R == 0) ? c : (off < 0 ? -1 : c * off);
	};
	const double TURN = .06;
	const int S = 9;   // a state: a corner and the direction it was reached in (8: the start)
	std::vector<double> g;
	std::vector<int> prev;
	std::vector<uint8_t> done;
	const double bx = B.wc_i + .5, bz = B.wc_j + .5;
	auto hfun = [&](int x, int z) {   // octile distance to the target square (a lower bound: turns cost extra)
		const double ax = std::fabs(x - bx), az = std::fabs(z - bz);
		return std::max(ax, az) + (1.4142 - 1) * std::min(ax, az);
	};
	std::vector<uint8_t> goal(size_t(N), 0);
	for (int c = 0; c < 4; c++) goal[size_t(B.wc_j + c / 2) * NX + B.wc_i + c % 2] = 1;
	int end = -1;
	for (int pass = 0; pass < 2 && end < 0; pass++) {
	relaxed = pass == 1;
	g.assign(size_t(N) * S, 1e18);
	prev.assign(size_t(N) * S, -1);
	done.assign(size_t(N) * S, 0);
	Heap h;
	for (int c = 0; c < 4; c++) {   // the start: the corners of the port's water square
		const int x = A.wc_i + c % 2, z = A.wc_j + c / 2;
		const double g0 = js_hypot(-b_.wx / 2 + x * ST - A.x, -b_.wz / 2 + z * ST - A.z) / ST;
		const size_t s = (size_t(z) * NX + x) * S + 8;
		if (g0 < g[s]) {
			g[s] = g0;
			h.push(g0 + hfun(x, z), int(s));
		}
	}
	while (!h.empty()) {
		const int s = h.pop();
		if (done[size_t(s)]) continue;
		done[size_t(s)] = 1;
		const int n = s / S, dir = s % S, x = n % NX, z = n / NX;
		if (goal[size_t(n)]) {
			end = s;
			break;
		}
		for (int d = 0; d < 8; d++) {
			const double c = step(x, z, d);
			if (c < 0) continue;
			const int m = (z + DZ[d]) * NX + x + DX[d];
			const size_t t = size_t(m) * S + d;
			if (done[t]) continue;
			const double ng = g[size_t(s)] + c + ((dir != 8 && dir != d) ? TURN : 0.0);
			if (ng < g[t]) {
				g[t] = ng;
				prev[t] = s;
				h.push(ng + hfun(m % NX, m / NX), int(t));
			}
		}
	}
	}
	if (end < 0) return {};
	std::vector<int> nodes;
	for (int s = end; s >= 0; s = prev[size_t(s)]) nodes.push_back(s / S);
	std::reverse(nodes.begin(), nodes.end());
	std::vector<float> pts = {float(A.x), float(A.z)};
	for (size_t k = 0; k < nodes.size(); k++) {
		const int c = nodes[k];
		if (k > 0 && k < nodes.size() - 1 && c - nodes[k - 1] == nodes[k + 1] - c) continue;
		pts.push_back(float(-b_.wx / 2 + (c % NX) * ST));
		pts.push_back(float(-b_.wz / 2 + (c / NX) * ST));
	}
	pts.push_back(float(B.x));
	pts.push_back(float(B.z));
	return pts;
}

bool Nav::sky_hit(double x0, double z0, double x1, double z1, const std::set<int> &sky) const {
	if (sky.empty()) return false;
	double L = js_hypot(x1 - x0, z1 - z0);
	int n = std::max(2, int(std::ceil(L / (b_.st * .5))));
	for (int k = 1; k < n; k++) {
		int o = own_at(x0 + (x1 - x0) * k / n, z0 + (z1 - z0) * k / n);
		if (o >= 0 && sky.count(o)) return true;
	}
	return false;
}

std::vector<float> Nav::air(double x0, double z0, double x1, double z1, const Blocks *blk) const {
	static const std::set<int> none;
	const std::set<int> &sky = blk ? blk->sky : none;
	if (sky.empty() || !sky_hit(x0, z0, x1, z1, sky)) return {float(x0), float(z0), float(x1), float(z1)};
	const double ST = b_.st;
	const int W = b_.nx, H = b_.nz, N = W * H;
	auto id = [&](double x, double z) {
		int i = clampi(int(js_round((x + b_.wx / 2) / ST)), 0, W - 1), k = clampi(int(js_round((z + b_.wz / 2) / ST)), 0, H - 1);
		return k * W + i;
	};
	auto xy = [&](int c, double &x, double &z) {
		x = -b_.wx / 2 + (c % W) * ST;
		z = -b_.wz / 2 + (c / W) * ST;
	};
	// a node under a closed sky (it or a neighbour in a closed state): worked out once per node, not at every look
	std::vector<int8_t> badc(size_t(N), -1);
	auto bad = [&](int c) {
		if (badc[size_t(c)] >= 0) return badc[size_t(c)] != 0;
		int x = c % W, z = c / W;
		bool r = false;
		for (int dz = -1; dz <= 1 && !r; dz++)
			for (int dx = -1; dx <= 1; dx++) {
				int i = x + dx, k = z + dz;
				if (i < 0 || k < 0 || i >= W || k >= H) continue;
				int o = own_at(-b_.wx / 2 + i * ST + 1e-4, -b_.wz / 2 + k * ST + 1e-4);
				if (o >= 0 && sky.count(o)) {
					r = true;
					break;
				}
			}
		badc[size_t(c)] = r ? 1 : 0;
		return r;
	};
	const int s0 = id(x0, z0), e0 = id(x1, z1);
	double ex, ez;
	xy(e0, ex, ez);
	// A* with every node expanded once (the heuristic is consistent: a step costs at least its length) and the
	// costs in doubles; before, stale heap entries were expanded again and again — under a closed sky over a fine
	// lattice one path took seconds
	std::vector<double> g(size_t(N), 1e18);
	std::vector<int> prev(size_t(N), -1);
	std::vector<uint8_t> done(size_t(N), 0);
	Heap h;
	g[s0] = 0;
	h.push(0, s0);
	while (!h.empty()) {
		int n = h.pop();
		if (done[size_t(n)]) continue;
		done[size_t(n)] = 1;
		if (n == e0) break;
		int x = n % W, z = n / W;
		for (int dz = -1; dz <= 1; dz++)
			for (int dx = -1; dx <= 1; dx++) {
				if (!dx && !dz) continue;
				int nx = x + dx, nz = z + dz;
				if (nx < 0 || nz < 0 || nx >= W || nz >= H) continue;
				int m = nz * W + nx;
				if (done[size_t(m)]) continue;
				double ng = g[n] + ((dx && dz) ? 1.4142 : 1) * ((m != e0 && bad(m)) ? 25 : 1);
				if (ng < g[m]) {
					g[m] = ng;
					prev[m] = n;
					double mx, mz;
					xy(m, mx, mz);
					h.push(ng + js_hypot(mx - ex, mz - ez) / ST, m);
				}
			}
	}
	if (!(g[e0] < 1e17)) return {};
	std::vector<int> cells;
	for (int n = e0; n >= 0; n = prev[n]) {
		cells.push_back(n);
		if (n == s0) break;
	}
	std::reverse(cells.begin(), cells.end());
	std::vector<std::pair<double, double>> raw = {{x0, z0}};
	for (size_t k = 1; k + 1 < cells.size(); k++) {
		double x, z;
		xy(cells[k], x, z);
		raw.push_back({x, z});
	}
	raw.push_back({x1, z1});
	std::vector<float> out = {float(raw[0].first), float(raw[0].second)};
	size_t i = 0;
	while (i < raw.size() - 1) {
		size_t k = raw.size() - 1;
		while (k > i + 1 && sky_hit(raw[i].first, raw[i].second, raw[k].first, raw[k].second, sky)) k--;
		out.push_back(float(raw[k].first));
		out.push_back(float(raw[k].second));
		i = k;
	}
	return out;
}

std::vector<double> Nav::grid(bool sea, double x0, double z0, double x1, double z1, const std::vector<std::array<double, 3>> &zones,
		const std::set<int> &sky) const {
	const int W = b_.nx - 1, H = b_.nz - 1, N = W * H;
	const double ST = b_.st;
	auto cell = [&](double x, double z) {
		int i = int(std::floor((x + b_.wx / 2) / ST)), j = int(std::floor((z + b_.wz / 2) / ST));
		return (i < 0 || j < 0 || i >= W || j >= H) ? -1 : j * W + i;
	};
	auto cxy = [&](int c, double &x, double &z) {
		x = -b_.wx / 2 + (c % W + .5) * ST;
		z = -b_.wz / 2 + (c / W + .5) * ST;
	};
	std::vector<uint8_t> blk;
	if (!sea && !sky.empty()) {
		blk.assign(N, 0);
		for (int c = 0; c < N; c++) {
			double x, z;
			cxy(c, x, z);
			int o = own_at(x, z);
			if (o >= 0 && sky.count(o)) blk[c] = 1;
		}
	}
	auto pass = [&](int c) { return sea ? water_[c] != 0 : (blk.empty() || !blk[c]); };
	auto near_w = [&](int c, int rad) {
		if (c >= 0 && pass(c)) return c;
		if (c < 0) return -1;
		int x0_ = c % W, y0_ = c / W, best = -1, bd = 1000000000;
		for (int dy = -rad; dy <= rad; dy++)
			for (int dx = -rad; dx <= rad; dx++) {
				int x = x0_ + dx, y = y0_ + dy;
				if (x < 0 || y < 0 || x >= W || y >= H) continue;
				int m = y * W + x;
				if (pass(m) && dx * dx + dy * dy < bd) {
					bd = dx * dx + dy * dy;
					best = m;
				}
			}
		return best;
	};
	const int s0 = near_w(cell(x0, z0), 3), e0 = near_w(cell(x1, z1), 3);
	if (s0 < 0 || e0 < 0) return {};
	std::vector<float> pen;
	if (!zones.empty()) {
		pen.assign(N, 0.f);
		for (auto &zn : zones) {
			const int r = int(std::ceil(zn[2] / ST)) + 1, c = cell(zn[0], zn[1]);
			if (c < 0) continue;
			const int cx = c % W, cy = c / W;
			for (int dy = -r; dy <= r; dy++)
				for (int dx = -r; dx <= r; dx++) {
					int x = cx + dx, y = cy + dy;
					if (x < 0 || y < 0 || x >= W || y >= H) continue;
					double px, pz;
					cxy(y * W + x, px, pz);
					if (js_hypot(px - zn[0], pz - zn[1]) < zn[2]) pen[size_t(y * W + x)] = 30;
				}
		}
	}
	// every cell expanded once (see air), the costs in doubles
	std::vector<double> g(size_t(N), 1e18);
	std::vector<int> prev(size_t(N), -1);
	std::vector<uint8_t> done(size_t(N), 0);
	const int ex = e0 % W, ey = e0 / W;
	Heap h;
	g[s0] = 0;
	h.push(0, s0);
	while (!h.empty()) {
		int n = h.pop();
		if (done[size_t(n)]) continue;
		done[size_t(n)] = 1;
		if (n == e0) break;
		int x = n % W, y = n / W;
		for (int dy = -1; dy <= 1; dy++)
			for (int dx = -1; dx <= 1; dx++) {
				if (!dx && !dy) continue;
				int nx = x + dx, ny = y + dy;
				if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
				int c = ny * W + nx;
				if (!pass(c)) continue;
				if (dx && dy && (!pass(y * W + nx) || !pass(ny * W + x))) continue;
				if (done[size_t(c)]) continue;
				double ng = g[n] + ((dx && dy) ? 1.4142 : 1) + (pen.empty() ? 0.0 : double(pen[c]));
				if (ng < g[c]) {
					g[c] = ng;
					prev[c] = n;
					h.push(ng + js_hypot(nx - ex, ny - ey), c);
				}
			}
	}
	if (!(g[e0] < 1e17)) return {};
	std::vector<int> cells;
	for (int n = e0; n >= 0; n = prev[n]) {
		cells.push_back(n);
		if (n == s0) break;
	}
	std::reverse(cells.begin(), cells.end());
	std::vector<double> pts = {x0, z0};
	for (size_t k = 0; k < cells.size(); k++) {
		const int c = cells[k];
		if (k > 0 && k < cells.size() - 1 && c - cells[k - 1] == cells[k + 1] - c) continue;
		double x, z;
		cxy(c, x, z);
		pts.push_back(x);
		pts.push_back(z);
	}
	pts.push_back(x1);
	pts.push_back(z1);
	return pts;
}

} // namespace tr
