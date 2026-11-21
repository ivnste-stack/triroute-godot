// Godot binding of the world generator: TRWorldGen.generate(seed, states) -> Dictionary.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <memory>

namespace tr { struct World; struct Board; class Nav; struct Blocks; }

namespace godot {

class TRWorldGen : public RefCounted {
	GDCLASS(TRWorldGen, RefCounted)

protected:
	static void _bind_methods();

public:
	// Generates the logistics board world exactly like the HTML version (genWorld in 04-map.js).
	// Thread-safe (no shared state): call it from WorkerThreadPool to keep the game responsive.
	// Returns: mw, mh, tri_s, sqw, sqh, T, top, bot, land_count,
	//   own (PackedByteArray, signed: -1 sea, 0..n-1 state, >=120 neutral), sqd (PackedByteArray),
	//   sql (PackedInt32Array, 2 per square), height (PackedFloat32Array), mountains (PackedFloat32Array),
	//   countries (Array of {idx, area, lx, ly, cap_x, cap_y, neighbors, land_share, has_label}).
	Dictionary generate(int64_t seed, int64_t states = 26, int64_t mw = 1800, int64_t mh = 1200);

	// Towns, roads, railways, ports, airports and border checkpoints on the world made by the last generate()
	// (boardGen + boardRoads of the HTML version). state_pops: population of every state (millions).
	// Returns: nx, nz, st, wx, wz, towns (Array of {x, z, node, type, pop, cid, name, port, wc_i, wc_j, air_ov,
	//   port_ov, extra}), bits / rbits (PackedByteArray: 8 direction bits per lattice node, roads / railways),
	//   comp (PackedInt32Array: land component per node), comp_size (PackedInt32Array),
	//   roads (Array of {lv, p: PackedFloat32Array x,z pairs}), railways (Array of PackedFloat32Array),
	//   checkpoints (Array of {x, z, a, b, rail}).
	Dictionary generate_board(const PackedFloat64Array &state_pops = PackedFloat64Array());

	// The states' starting characteristics for the last generated world, exactly like the HTML version
	// (makeCountry + colours): Array of {id, name, full, gov, title, ideol, trait, leader, leader_age, pop, dev, gdp,
	//   treasury, debt, stability, infl, unemp, tech, corr, mil, election_in, color, laws, deposit, flag {cols, type, emblem}}.
	// generate_board() without arguments uses these populations.
	Array generate_states();

	// ---- route search on the board made by the last generate_board() (boardPath / boardSea / incAirPath) ----
	// route(mode, a, b): path between towns a and b ("road" | "rail" | "sea" | "air") as x,z pairs; empty if none.
	PackedFloat32Array route(const String &mode, int64_t a, int64_t b) const;
	// path on the road or rail graph between two lattice nodes (empty if none)
	PackedFloat32Array node_path(int64_t a, int64_t b, bool rail) const;
	// flight path between two points, around a closed sky
	PackedFloat32Array air_path(double x0, double z0, double x1, double z1) const;
	// route blocking (incBlk): {wx: PackedByteArray per node (1 road, 2 rail), closed_states: PackedInt32Array,
	//   closed_pairs: PackedInt32Array of a,b pairs, closed_cps: PackedFloat32Array of x,z, sky: PackedInt32Array, ignore_wx: bool}
	void set_blocks(const Dictionary &blocks);
	// state at a world point (bOwn), -1 water / neutral
	// does a straight flight cross a closed sky (skyHit)
	bool sky_hit(double x0, double z0, double x1, double z1) const;
	int64_t state_at(double x, double z) const;
	// continent of every state (coCont): states whose land touches share a continent id (a state index)
	PackedInt32Array continents() const;
	// border crossings along a path (bCrossings): Array of {ws, s, x, z, a, b}; s = ws * eco
	Array crossings(const PackedFloat32Array &p, double eco) const;
	// position of the game RNG after the states were made (mulberry(seed^0x5bd1e995) state), for the game logic
	int64_t states_rng_state() const { return int64_t(states_rng_); }

	// Map shader textures for the last generated world, ready for Image.create_from_data():
	//   terrain: RGBAH with mipmaps (MW x MH) — coast/height, lattice diagonal, lighting, noise
	//   border:  RH with mipmaps (2MW x 2MH) — distance to a state border
	//   states:  R8 (2MW x 2MH) — state id + 1 (121 neutral), grown into the sea
	// Mipmaps are 2x2 box averages like the HTML version builds them.
	Dictionary build_textures();

private:
	std::shared_ptr<tr::World> world_;
	std::vector<double> state_pops_;
	uint32_t states_rng_ = 0;
	std::shared_ptr<tr::Board> board_;
	std::shared_ptr<tr::Nav> nav_;
	std::shared_ptr<tr::Blocks> blocks_;
	int64_t seed_ = 0;
};

} // namespace godot
