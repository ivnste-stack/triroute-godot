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
	const int N = b_.nx * b_.nz;
	const auto &bits = rail ? b_.rbits : b_.bits;
	const bool useBlk = blk && blk->any();
	std::vector<float> g(N, 1e9f);
	std::vector<int> prev(N, -1);
	Heap h;
	g[a] = 0;
	h.push(0, a);
	while (!h.empty()) {
		int n = h.pop();
		if (n == b) break;
		int x = n % b_.nx, y = n / b_.nx;
		for (int d = 0; d < 8; d++) {
			if (!(bits[n] & (1 << d))) continue;
			int m = (y + D8[d][1]) * b_.nx + x + D8[d][0];
			if (useBlk && blocked(n, m, rail, *blk)) continue;
			double ng = double(g[n]) + ((d & 1) ? 1.4142 : 1) * b_.st;
			if (ng < double(g[m])) {
				g[m] = float(ng);
				prev[m] = n;
				h.push(ng, m);
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

std::vector<float> Nav::sea(int ta, int tb) const {
	const Town &A = b_.towns[ta], &B = b_.towns[tb];
	if (A.wc_i < 0 || B.wc_i < 0) return {};
	const int W = b_.nx - 1, H = b_.nz - 1, N = W * H;
	std::vector<float> g(N, 1e9f);
	std::vector<int> prev(N, -1);
	const int s0 = A.wc_j * W + A.wc_i, e0 = B.wc_j * W + B.wc_i, ex = B.wc_i, ey = B.wc_j;
	Heap h;
	g[s0] = 0;
	h.push(0, s0);
	while (!h.empty()) {
		int n = h.pop();
		if (n == e0) break;
		int x = n % W, y = n / W;
		for (int dy = -1; dy <= 1; dy++)
			for (int dx = -1; dx <= 1; dx++) {
				if (!dx && !dy) continue;
				int nx = x + dx, ny = y + dy;
				if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
				int m = ny * W + nx;
				if (!water_[m]) continue;
				if (dx && dy && (!water_[size_t(y) * W + nx] || !water_[size_t(ny) * W + x])) continue;
				double ng = double(g[n]) + ((dx && dy) ? 1.4142 : 1);
				if (ng < double(g[m])) {
					g[m] = float(ng);
					prev[m] = n;
					h.push(ng + js_hypot(nx - ex, ny - ey), m);
				}
			}
	}
	if (!(g[e0] < 1e9f)) return {};
	std::vector<int> cells;
	for (int n = e0; n >= 0; n = prev[n]) {
		cells.push_back(n);
		if (n == s0) break;
	}
	std::reverse(cells.begin(), cells.end());
	std::vector<float> pts = {float(A.x), float(A.z)};
	for (size_t k = 0; k < cells.size(); k++) {
		int c = cells[k];
		if (k > 0 && k < cells.size() - 1 && c - cells[k - 1] == cells[k + 1] - c) continue;
		pts.push_back(float(-b_.wx / 2 + (c % W + .5) * b_.st));
		pts.push_back(float(-b_.wz / 2 + (c / W + .5) * b_.st));
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
	auto bad = [&](int c) {
		int x = c % W, z = c / W;
		for (int dz = -1; dz <= 1; dz++)
			for (int dx = -1; dx <= 1; dx++) {
				int i = x + dx, k = z + dz;
				if (i < 0 || k < 0 || i >= W || k >= H) continue;
				int o = own_at(-b_.wx / 2 + i * ST + 1e-4, -b_.wz / 2 + k * ST + 1e-4);
				if (o >= 0 && sky.count(o)) return true;
			}
		return false;
	};
	const int s0 = id(x0, z0), e0 = id(x1, z1);
	double ex, ez;
	xy(e0, ex, ez);
	std::vector<float> g(N, 1e9f);
	std::vector<int> prev(N, -1);
	Heap h;
	g[s0] = 0;
	h.push(0, s0);
	while (!h.empty()) {
		int n = h.pop();
		if (n == e0) break;
		int x = n % W, z = n / W;
		for (int dz = -1; dz <= 1; dz++)
			for (int dx = -1; dx <= 1; dx++) {
				if (!dx && !dz) continue;
				int nx = x + dx, nz = z + dz;
				if (nx < 0 || nz < 0 || nx >= W || nz >= H) continue;
				int m = nz * W + nx;
				double ng = double(g[n]) + ((dx && dz) ? 1.4142 : 1) * ((m != e0 && bad(m)) ? 25 : 1);
				if (ng < double(g[m])) {
					g[m] = float(ng);
					prev[m] = n;
					double mx, mz;
					xy(m, mx, mz);
					h.push(ng + js_hypot(mx - ex, mz - ez) / ST, m);
				}
			}
	}
	if (!(g[e0] < 1e9f)) return {};
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

} // namespace tr
