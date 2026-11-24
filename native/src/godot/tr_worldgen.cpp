#include "tr_worldgen.h"
#include "core/jsmath.h"

#include "core/board.h"
#include "core/nav.h"
#include "core/states.h"
#include "core/statedata.h"
#include "core/worldgen.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstring>

namespace godot {

namespace {

// float -> IEEE half, round to nearest even (what the GPU upload of a float texture does)
uint16_t to_half(float f) {
	uint32_t x;
	std::memcpy(&x, &f, 4);
	uint32_t sign = (x >> 16) & 0x8000u;
	int32_t e = int32_t((x >> 23) & 0xFF) - 127 + 15;
	uint32_t m = x & 0x7FFFFFu;
	if (((x >> 23) & 0xFF) == 0xFF) return uint16_t(sign | 0x7C00u | (m ? 0x200u : 0));   // inf / nan
	if (e >= 31) return uint16_t(sign | 0x7C00u);                                           // overflow -> inf
	if (e <= 0) {                                                                            // subnormal half
		if (e < -10) return uint16_t(sign);
		m |= 0x800000u;
		int shift = 14 - e;
		uint32_t hm = m >> shift, rem = m & ((1u << shift) - 1), half = 1u << (shift - 1);
		if (rem > half || (rem == half && (hm & 1))) hm++;
		return uint16_t(sign | hm);
	}
	uint32_t hm = m >> 13, rem = m & 0x1FFFu;
	uint32_t h = sign | (uint32_t(e) << 10) | hm;
	if (rem > 0x1000u || (rem == 0x1000u && (hm & 1))) h++;
	return uint16_t(h);
}

// mip chain of a float image (box average with clamped edges, like initGL), stored as halfs
PackedByteArray half_mips(const std::vector<float> &src, int w, int h, int ch) {
	std::vector<uint16_t> out;
	std::vector<float> data = src;
	for (;;) {
		for (float v : data) out.push_back(to_half(v));
		if (w <= 1 && h <= 1) break;
		int nw = std::max(1, w >> 1), nh = std::max(1, h >> 1);
		std::vector<float> nd(size_t(nw) * nh * ch);
		for (int y = 0; y < nh; y++)
			for (int x = 0; x < nw; x++) {
				int x0 = std::min(w - 1, x * 2), x1 = std::min(w - 1, x * 2 + 1), y0 = std::min(h - 1, y * 2), y1 = std::min(h - 1, y * 2 + 1);
				for (int c = 0; c < ch; c++)
					nd[(size_t(y) * nw + x) * ch + c] = float((double(data[(size_t(y0) * w + x0) * ch + c]) + data[(size_t(y0) * w + x1) * ch + c] +
																   data[(size_t(y1) * w + x0) * ch + c] + data[(size_t(y1) * w + x1) * ch + c]) * .25);
			}
		data.swap(nd);
		w = nw;
		h = nh;
	}
	PackedByteArray b;
	b.resize(int64_t(out.size() * 2));
	std::memcpy(b.ptrw(), out.data(), out.size() * 2);
	return b;
}

} // namespace

void TRWorldGen::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate", "seed", "states", "mw", "mh"), &TRWorldGen::generate, DEFVAL(26), DEFVAL(1800), DEFVAL(1200));
	ClassDB::bind_method(D_METHOD("set_fine_roads", "on"), &TRWorldGen::set_fine_roads);
	ClassDB::bind_method(D_METHOD("set_earth", "w", "h", "labels", "seeds", "names", "pop", "dev"), &TRWorldGen::set_earth);
	ClassDB::bind_method(D_METHOD("generate_board", "state_pops"), &TRWorldGen::generate_board, DEFVAL(PackedFloat64Array()));
	ClassDB::bind_method(D_METHOD("generate_states"), &TRWorldGen::generate_states);
	ClassDB::bind_method(D_METHOD("route", "mode", "a", "b"), &TRWorldGen::route);
	ClassDB::bind_method(D_METHOD("node_path", "a", "b", "rail", "ignore_wx"), &TRWorldGen::node_path, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("air_path", "x0", "z0", "x1", "z1"), &TRWorldGen::air_path);
	ClassDB::bind_method(D_METHOD("set_blocks", "blocks"), &TRWorldGen::set_blocks);
	ClassDB::bind_method(D_METHOD("state_at", "x", "z"), &TRWorldGen::state_at);
	ClassDB::bind_method(D_METHOD("sky_hit", "x0", "z0", "x1", "z1"), &TRWorldGen::sky_hit);
	ClassDB::bind_method(D_METHOD("sr_grid", "mode", "x0", "z0", "x1", "z1", "zones"), &TRWorldGen::sr_grid);
	ClassDB::bind_method(D_METHOD("node_path_avoid", "a", "b", "jam_nodes", "zones"), &TRWorldGen::node_path_avoid);
	ClassDB::bind_method(D_METHOD("continents"), &TRWorldGen::continents);
	ClassDB::bind_method(D_METHOD("lines"), &TRWorldGen::lines);
	ClassDB::bind_method(D_METHOD("crossings", "p", "eco"), &TRWorldGen::crossings);
	ClassDB::bind_method(D_METHOD("crossings64", "p", "eco"), &TRWorldGen::crossings64);
	ClassDB::bind_method(D_METHOD("states_rng_state"), &TRWorldGen::states_rng_state);
	ClassDB::bind_method(D_METHOD("build_textures"), &TRWorldGen::build_textures);
}

void TRWorldGen::set_earth(int64_t w, int64_t h, const PackedByteArray &labels, const PackedInt32Array &seeds,
		const PackedStringArray &names, const PackedFloat64Array &pop, const PackedFloat64Array &dev) {
	earth_w_ = int(w);
	earth_h_ = int(h);
	earth_.assign(labels.ptr(), labels.ptr() + labels.size());
	if (int64_t(earth_.size()) != w * h) {
		earth_.clear();
		earth_w_ = earth_h_ = 0;
	}
	earth_seeds_.assign(seeds.ptr(), seeds.ptr() + seeds.size());
	earth_names_.clear();
	for (int64_t i = 0; i < names.size(); i++) earth_names_.push_back(std::string(names[i].utf8().get_data()));
	earth_pop_.assign(pop.ptr(), pop.ptr() + pop.size());
	earth_dev_.assign(dev.ptr(), dev.ptr() + dev.size());
}

Dictionary TRWorldGen::generate(int64_t seed, int64_t states, int64_t mw, int64_t mh) {
	tr::WorldParams p;
	p.n = int(states);
	p.mw = int(mw);
	p.mh = int(mh);
	if (!earth_.empty()) {
		p.earth = earth_;
		p.ew = earth_w_;
		p.eh = earth_h_;
		p.eseeds = earth_seeds_;
		p.enames = earth_names_;
		p.epop = earth_pop_;
		p.edev = earth_dev_;
	}
	state_pops_.clear();
	nav_.reset();
	board_.reset();
	world_ = std::make_shared<tr::World>(tr::generate_world(uint32_t(seed & 0xFFFFFFFF), p));
	seed_ = seed;
	const tr::World &w = *world_;

	Dictionary d;
	d["mw"] = p.mw;
	d["mh"] = p.mh;
	d["tri_s"] = p.tri_s;
	d["sqw"] = w.sqw;
	d["sqh"] = w.sqh;
	d["T"] = w.T;
	d["top"] = w.top;
	d["bot"] = w.bot;
	d["land_count"] = w.land_count;

	PackedByteArray own;
	own.resize(int64_t(w.own.size()));
	std::memcpy(own.ptrw(), w.own.data(), w.own.size());
	d["own"] = own;

	PackedByteArray sqd;
	sqd.resize(int64_t(w.sqd.size()));
	std::memcpy(sqd.ptrw(), w.sqd.data(), w.sqd.size());
	d["sqd"] = sqd;

	PackedInt32Array sql;
	sql.resize(int64_t(w.sql.size()));
	for (size_t i = 0; i < w.sql.size(); i++) sql.set(int64_t(i), w.sql[i]);
	d["sql"] = sql;

	PackedFloat32Array height, mtn;
	height.resize(int64_t(w.H.size()));
	std::memcpy(height.ptrw(), w.H.data(), w.H.size() * sizeof(float));
	mtn.resize(int64_t(w.Mf.size()));
	std::memcpy(mtn.ptrw(), w.Mf.data(), w.Mf.size() * sizeof(float));
	d["height"] = height;
	d["mountains"] = mtn;

	Array countries;
	for (const auto &c : w.countries) {
		Dictionary cd;
		cd["idx"] = c.idx;
		cd["area"] = c.area;
		cd["lx"] = c.lx;
		cd["ly"] = c.ly;
		cd["cap_x"] = c.cap_x;
		cd["cap_y"] = c.cap_y;
		cd["has_label"] = !c.no_label;
		cd["land_share"] = c.land_share;
		PackedInt32Array nb;
		for (int n : c.neighbors) nb.push_back(n);
		cd["neighbors"] = nb;
		countries.push_back(cd);
	}
	d["countries"] = countries;
	return d;
}

Dictionary TRWorldGen::generate_board(const PackedFloat64Array &state_pops) {
	Dictionary d;
	if (!world_) return d;
	std::vector<double> pops(size_t(state_pops.size()));
	for (int64_t i = 0; i < state_pops.size(); i++) pops[size_t(i)] = state_pops[i];
	if (pops.empty()) {
		if (state_pops_.empty()) generate_states();
		pops = state_pops_;
	}
	pops.resize(world_->countries.size(), 1.0);
	nav_.reset();
	board_ = std::make_shared<tr::Board>(tr::generate_board(uint32_t(seed_ & 0xFFFFFFFF), *world_, pops, fine_roads_));
	nav_ = std::make_shared<tr::Nav>(*world_, *board_);
	const tr::Board &B = *board_;
	d["nx"] = B.nx;
	d["nz"] = B.nz;
	d["st"] = B.st;
	d["wx"] = B.wx;
	d["wz"] = B.wz;
	Array towns;
	for (const auto &t : B.towns) {
		Dictionary td;
		td["x"] = t.x;
		td["z"] = t.z;
		td["node"] = t.node;
		td["type"] = String::utf8(t.type.c_str());
		td["pop"] = t.pop;
		td["cid"] = t.cid;
		td["name"] = String::utf8(t.name.c_str());
		td["port"] = t.port;
		td["wc_i"] = t.wc_i;
		td["wc_j"] = t.wc_j;
		td["air_ov"] = t.air_ov;
		td["port_ov"] = t.port_ov == 1;
		td["extra"] = t.extra;
		towns.push_back(td);
	}
	d["towns"] = towns;
	PackedByteArray bits, rbits;
	bits.resize(int64_t(B.bits.size()));
	std::memcpy(bits.ptrw(), B.bits.data(), B.bits.size());
	rbits.resize(int64_t(B.rbits.size()));
	std::memcpy(rbits.ptrw(), B.rbits.data(), B.rbits.size());
	d["bits"] = bits;
	d["rbits"] = rbits;
	PackedInt32Array comp, csz;
	for (int c : B.comp) comp.push_back(c);
	for (int c : B.csz) csz.push_back(c);
	d["comp"] = comp;
	d["comp_size"] = csz;
	auto f32 = [](const std::vector<float> &v) {
		PackedFloat32Array a;
		a.resize(int64_t(v.size()));
		std::memcpy(a.ptrw(), v.data(), v.size() * sizeof(float));
		return a;
	};
	Array roads, rails, cps;
	for (const auto &h : B.hw) {
		Dictionary r;
		r["lv"] = h.lv;
		r["p"] = f32(h.p);
		roads.push_back(r);
	}
	for (const auto &r : B.rail) rails.push_back(f32(r));
	for (const auto &c : B.cps) {
		Dictionary cd;
		cd["x"] = c.x;
		cd["z"] = c.z;
		cd["a"] = c.a;
		cd["b"] = c.b;
		cd["rail"] = c.rail;
		cps.push_back(cd);
	}
	d["roads"] = roads;
	d["railways"] = rails;
	d["checkpoints"] = cps;
	return d;
}

Dictionary TRWorldGen::build_textures() {
	Dictionary d;
	if (!world_) return d;
	tr::World &w = *world_;
	if (w.tf.empty()) tr::build_render_data(w);
	const int MW = w.p.mw, MH = w.p.mh;
	d["width"] = MW;
	d["height"] = MH;
	d["terrain"] = half_mips(w.tf, MW, MH, 4);
	d["border"] = half_mips(w.hb, MW * 2, MH * 2, 1);
	PackedByteArray st;
	st.resize(int64_t(w.hid.size()));
	std::memcpy(st.ptrw(), w.hid.data(), w.hid.size());
	d["states"] = st;
	// the arrays are uploaded now; free the CPU copies
	std::vector<float>().swap(w.tf);
	std::vector<float>().swap(w.hb);
	return d;
}

Array TRWorldGen::generate_states() {
	Array out;
	if (!world_) return out;
	auto S = tr::generate_states(uint32_t(seed_ & 0xFFFFFFFF), *world_, &states_rng_);
	state_pops_.clear();
	auto str = [](const std::string &s) { return String::utf8(s.c_str()); };
	for (const auto &c : S) {
		state_pops_.push_back(c.pop);
		Dictionary d;
		d["id"] = c.id;
		d["name"] = str(c.name);
		d["full"] = str(c.full);
		d["gov"] = str(c.gov);
		d["title"] = str(c.title);
		d["ideol"] = str(c.ideol);
		d["trait"] = str(c.trait);
		d["leader"] = str(c.leader);
		d["leader_age"] = c.leader_age;
		d["pop"] = c.pop;
		d["dev"] = c.dev;
		d["gdp"] = c.gdp;
		d["treasury"] = c.treasury;
		d["debt"] = c.debt;
		d["stability"] = c.stability;
		d["infl"] = c.infl;
		d["unemp"] = c.unemp;
		d["tech"] = c.tech;
		d["corr"] = c.corr;
		d["mil"] = c.mil;
		d["election_in"] = c.election_in;
		d["color"] = str(c.color);
		PackedStringArray laws;
		for (auto &l : c.laws) laws.push_back(str(l));
		d["laws"] = laws;
		PackedFloat64Array dep;
		for (double v : c.deposit) dep.push_back(v);
		d["deposit"] = dep;
		Dictionary f;
		PackedStringArray fc;
		for (int k : c.flag.cols) fc.push_back(str(tr::FLAGCOL[k]));
		f["cols"] = fc;
		f["type"] = c.flag.type;
		f["emblem"] = c.flag.emblem;
		d["flag"] = f;
		out.push_back(d);
	}
	return out;
}

namespace {
PackedFloat32Array to_packed(const std::vector<float> &v) {
	PackedFloat32Array a;
	a.resize(int64_t(v.size()));
	if (!v.empty()) std::memcpy(a.ptrw(), v.data(), v.size() * sizeof(float));
	return a;
}
} // namespace

PackedFloat32Array TRWorldGen::route(const String &mode, int64_t a, int64_t b) const {
	if (!nav_ || a < 0 || b < 0 || a >= int64_t(board_->towns.size()) || b >= int64_t(board_->towns.size())) return PackedFloat32Array();
	const auto &A = board_->towns[size_t(a)], &B = board_->towns[size_t(b)];
	if (mode == "road") return to_packed(nav_->path(A.node, B.node, false, blocks_.get()));
	if (mode == "rail") return to_packed(nav_->path(A.node, B.node, true, blocks_.get()));
	if (mode == "sea") return to_packed(nav_->sea(int(a), int(b)));
	if (mode == "air") return to_packed(nav_->air(A.x, A.z, B.x, B.z, blocks_.get()));
	return PackedFloat32Array();
}

PackedFloat32Array TRWorldGen::node_path(int64_t a, int64_t b, bool rail, bool ignore_wx) const {
	if (!nav_) return PackedFloat32Array();
	if (ignore_wx && blocks_ && !blocks_->ignore_wx && !blocks_->wx.empty()) {
		tr::Blocks nb = *blocks_;
		nb.ignore_wx = true;
		return to_packed(nav_->path(int(a), int(b), rail, &nb));
	}
	return to_packed(nav_->path(int(a), int(b), rail, blocks_.get()));
}

PackedFloat32Array TRWorldGen::air_path(double x0, double z0, double x1, double z1) const {
	if (!nav_) return PackedFloat32Array();
	return to_packed(nav_->air(x0, z0, x1, z1, blocks_.get()));
}

void TRWorldGen::set_blocks(const Dictionary &d) {
	auto b = std::make_shared<tr::Blocks>();
	if (d.has("wx")) {
		PackedByteArray wx = d["wx"];
		b->wx.assign(wx.ptr(), wx.ptr() + wx.size());
	}
	if (d.has("closed_states")) {
		PackedInt32Array a = d["closed_states"];
		for (int64_t i = 0; i < a.size(); i++) b->closed_states.insert(a[i]);
	}
	if (d.has("closed_pairs")) {
		PackedInt32Array a = d["closed_pairs"];
		for (int64_t i = 0; i + 1 < a.size(); i += 2) {
			b->closed_pairs.insert(int64_t(a[i]) * 1000 + a[i + 1]);
			b->closed_pairs.insert(int64_t(a[i + 1]) * 1000 + a[i]);
		}
	}
	if (d.has("closed_cps")) {
		PackedFloat32Array a = d["closed_cps"];
		for (int64_t i = 0; i + 1 < a.size(); i += 2) b->closed_cps.push_back({a[i], a[i + 1]});
	}
	if (d.has("sky")) {
		PackedInt32Array a = d["sky"];
		for (int64_t i = 0; i < a.size(); i++) b->sky.insert(a[i]);
	}
	// weather zones that shut roads/rails (incBlk): x, z, r, flags (1 road, 2 rail) per zone;
	// a lattice node is shut when it lies within 0.8 r of the zone centre
	if (d.has("wx_zones") && board_) {
		PackedFloat64Array a = d["wx_zones"];
		const tr::Board &B = *board_;
		if (a.size() >= 4 && b->wx.empty()) b->wx.assign(size_t(B.nx) * B.nz, 0);
		for (int64_t q = 0; q + 3 < a.size(); q += 4) {
			const double x = a[q], z = a[q + 1], r = a[q + 2];
			const uint8_t fl = uint8_t(int(a[q + 3]));
			const int i0 = std::max(0, int(std::floor((x - r + B.wx / 2) / B.st))), i1 = std::min(B.nx - 1, int(std::ceil((x + r + B.wx / 2) / B.st)));
			const int k0 = std::max(0, int(std::floor((z - r + B.wz / 2) / B.st))), k1 = std::min(B.nz - 1, int(std::ceil((z + r + B.wz / 2) / B.st)));
			for (int k = k0; k <= k1; k++)
				for (int i = i0; i <= i1; i++) {
					const double nx = -B.wx / 2 + i * B.st, nz = -B.wz / 2 + k * B.st;
					if (tr::js_hypot(nx - x, nz - z) < r * .8) b->wx[size_t(k) * B.nx + i] |= fl;
				}
		}
	}
	b->ignore_wx = d.get("ignore_wx", false);
	blocks_ = b;
}

PackedFloat64Array TRWorldGen::sr_grid(const String &mode, double x0, double z0, double x1, double z1, const PackedFloat64Array &zones) const {
	PackedFloat64Array out;
	if (!nav_) return out;
	std::vector<std::array<double, 3>> zs;
	for (int64_t i = 0; i + 2 < zones.size(); i += 3) zs.push_back({zones[i], zones[i + 1], zones[i + 2]});
	static const std::set<int> none;
	auto p = nav_->grid(mode == "sea", x0, z0, x1, z1, zs, blocks_ ? blocks_->sky : none);
	out.resize(int64_t(p.size()));
	for (size_t i = 0; i < p.size(); i++) out[int64_t(i)] = p[i];
	return out;
}

PackedFloat32Array TRWorldGen::node_path_avoid(int64_t a, int64_t b, const PackedInt32Array &jam_nodes, const PackedFloat64Array &zones) const {
	if (!nav_ || !board_) return PackedFloat32Array();
	std::set<int> jn;
	for (int64_t i = 0; i < jam_nodes.size(); i++) jn.insert(jam_nodes[i]);
	std::vector<std::array<double, 3>> zs;
	for (int64_t i = 0; i + 2 < zones.size(); i += 3) zs.push_back({zones[i], zones[i + 1], zones[i + 2]});
	const tr::Board &B = *board_;
	auto bad = [&](int n) {
		if (jn.count(n)) return true;
		const double x = -B.wx / 2 + (n % B.nx) * B.st, z = -B.wz / 2 + (n / B.nx) * B.st;
		for (auto &q : zs)
			if (tr::js_hypot(x - q[0], z - q[1]) < q[2]) return true;
		return false;
	};
	return to_packed(nav_->path(int(a), int(b), false, blocks_.get(), bad));
}

bool TRWorldGen::sky_hit(double x0, double z0, double x1, double z1) const {
	if (!nav_ || !blocks_ || blocks_->sky.empty()) return false;
	return nav_->sky_hit(x0, z0, x1, z1, blocks_->sky);
}

int64_t TRWorldGen::state_at(double x, double z) const {
	return nav_ ? nav_->own_at(x, z) : -1;
}

Array TRWorldGen::lines() const {
	Array out;
	if (!world_) return out;
	for (const auto &l : tr::extract_lines(*world_)) {
		Dictionary d;
		d["a"] = l.a;
		d["b"] = l.b;
		d["p"] = to_packed(l.p);
		out.push_back(d);
	}
	return out;
}

PackedInt32Array TRWorldGen::continents() const {
	PackedInt32Array out;
	if (!world_) return out;
	const tr::World &w = *world_;
	const int n = int(w.countries.size()), MW = w.p.mw, MH = w.p.mh;
	std::vector<int> par(n);
	for (int i = 0; i < n; i++) par[i] = i;
	auto f = [&](int a) {
		while (par[a] != a) a = par[a] = par[par[a]];
		return a;
	};
	auto ok = [&](int o) { return o >= 0 && o < n; };
	for (int y = 0; y < MH; y++)
		for (int x = 0; x < MW; x++) {
			int o = w.own[size_t(y) * MW + x];
			if (!ok(o)) continue;
			int r = x + 1 < MW ? w.own[size_t(y) * MW + x + 1] : -1, d = y + 1 < MH ? w.own[size_t(y + 1) * MW + x] : -1;
			if (ok(r) && r != o) {
				int a = f(o), b = f(r);
				if (a != b) par[a] = b;
			}
			if (ok(d) && d != o) {
				int a = f(o), b = f(d);
				if (a != b) par[a] = b;
			}
		}
	for (int i = 0; i < n; i++) out.push_back(f(i));
	return out;
}

Array TRWorldGen::crossings(const PackedFloat32Array &p, double eco) const {
	Array out;
	if (!board_) return out;
	std::vector<float> v(size_t(p.size()));
	for (int64_t i = 0; i < p.size(); i++) v[size_t(i)] = p[i];
	for (const auto &c : tr::board_crossings(*world_, *board_, v, eco)) {
		Dictionary d;
		d["ws"] = c.ws;
		d["s"] = c.s;
		d["x"] = c.x;
		d["z"] = c.z;
		d["a"] = c.a;
		d["b"] = c.b;
		out.push_back(d);
	}
	return out;
}

Array TRWorldGen::crossings64(const PackedFloat64Array &p, double eco) const {
	Array out;
	if (!board_) return out;
	std::vector<double> v(size_t(p.size()));
	for (int64_t i = 0; i < p.size(); i++) v[size_t(i)] = p[i];
	for (const auto &c : tr::board_crossings(*world_, *board_, v, eco)) {
		Dictionary d;
		d["ws"] = c.ws;
		d["s"] = c.s;
		d["x"] = c.x;
		d["z"] = c.z;
		d["a"] = c.a;
		d["b"] = c.b;
		out.push_back(d);
	}
	return out;
}

} // namespace godot
