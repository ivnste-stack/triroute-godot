#include "tr_worldgen.h"

#include "core/worldgen.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstring>

namespace godot {

void TRWorldGen::_bind_methods() {
	ClassDB::bind_method(D_METHOD("generate", "seed", "states", "mw", "mh"), &TRWorldGen::generate, DEFVAL(26), DEFVAL(1800), DEFVAL(1200));
}

Dictionary TRWorldGen::generate(int64_t seed, int64_t states, int64_t mw, int64_t mh) const {
	tr::WorldParams p;
	p.n = int(states);
	p.mw = int(mw);
	p.mh = int(mh);
	tr::World w = tr::generate_world(uint32_t(seed & 0xFFFFFFFF), p);

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

} // namespace godot
