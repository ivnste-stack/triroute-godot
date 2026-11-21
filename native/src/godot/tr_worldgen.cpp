#include "tr_worldgen.h"

#include "core/board.h"
#include "core/worldgen.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstring>

namespace godot {

void TRWorldGen::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate", "seed", "states", "mw", "mh"), &TRWorldGen::generate, DEFVAL(26), DEFVAL(1800), DEFVAL(1200));
	ClassDB::bind_method(D_METHOD("generate_board", "state_pops"), &TRWorldGen::generate_board);
}

Dictionary TRWorldGen::generate(int64_t seed, int64_t states, int64_t mw, int64_t mh) {
	tr::WorldParams p;
	p.n = int(states);
	p.mw = int(mw);
	p.mh = int(mh);
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
	pops.resize(world_->countries.size(), 1.0);
	tr::Board B = tr::generate_board(uint32_t(seed_ & 0xFFFFFFFF), *world_, pops);
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

} // namespace godot
