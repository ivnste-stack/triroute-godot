// Godot binding of the world generator: TRWorldGen.generate(seed, states) -> Dictionary.
#pragma once
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include <memory>
#include <string>
#include <vector>

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

	// The Earth for the next generate() (assets/maps/earth.json, tools/make_earth.py): a label grid w×h
	// (state id + 1 on land, | 128 on the sea near a coast, 0 far out), a seed per state (x, y grid cells),
	// the names, real populations (millions) and development. An empty grid goes back to invented worlds.
	void set_earth(int64_t w, int64_t h, const PackedByteArray &labels, const PackedInt32Array &seeds,
			const PackedStringArray &names, const PackedFloat64Array &pop, const PackedFloat64Array &dev);

	// Towns, roads, railways, ports, airports and border checkpoints on the world made by the last generate()
	// (boardGen + boardRoads of the HTML version). state_pops: population of every state (millions).
	// Returns: nx, nz, st, wx, wz, towns (Array of {x, z, node, type, pop, cid, name, port, wc_i, wc_j, air_ov,
	//   port_ov, extra}), bits / rbits (PackedByteArray: 8 direction bits per lattice node, roads / railways),
	//   comp (PackedInt32Array: land component per node), comp_size (PackedInt32Array),
	//   roads (Array of {lv, p: PackedFloat32Array x,z pairs}), railways (Array of PackedFloat32Array),
	//   checkpoints (Array of {x, z, a, b, rail}).
	Dictionary generate_board(const PackedFloat64Array &state_pops = PackedFloat64Array());
	Dictionary board_dict_() const;
	// ---- the map editor ----
	// the world from its edited lattice: sqd (diagonal per square), sql (owner per half: -1 sea, 0..n-1 state,
	// 120 neutral), n states, caps (x, y texture pixels per state, -1: at the label point). Returns own, land_count
	// and countries as generate() does; build_textures() and lines() follow it. The board is dropped.
	Dictionary edit_apply(const PackedByteArray &sqd, const PackedInt32Array &sql, int64_t n, const PackedInt32Array &caps);
	// the board of the editor: towns (Array of {x, z, type, name, pop?, port_ov?, air_ov?}), the drawn roads
	// (Array of {lv, p}) and railways (Array of PackedFloat32Array) — or generated ones when auto_net
	Dictionary generate_board_given(const PackedFloat64Array &state_pops, const Array &towns, const Array &roads, const Array &rails, bool auto_net);
	// a generator holding a copy of this world (the editor builds the textures on it in a worker thread while
	// this one goes on with the edits)
	Ref<TRWorldGen> clone() const;
	// lattice nodes of a road over land from node a to node b (empty: the sea is in the way)
	PackedInt32Array edit_path(int64_t a, int64_t b) const;
	// the test road net for the next generate_board(): nodes twice as dense, denser roads, more ways
	void set_fine_roads(bool on) { fine_roads_ = on; }
	// which build of the module is loaded (the performance record names it: an old library left in place shows)
	String build_id() const { return "2026-11-25 editor2"; }

	// The states' starting characteristics for the last generated world, exactly like the HTML version
	// (makeCountry + colours): Array of {id, name, full, gov, title, ideol, trait, leader, leader_age, pop, dev, gdp,
	//   treasury, debt, stability, infl, unemp, tech, corr, mil, election_in, color, laws, deposit, flag {cols, type, emblem}}.
	// generate_board() without arguments uses these populations.
	Array generate_states();

	// ---- route search on the board made by the last generate_board() (boardPath / boardSea / incAirPath) ----
	// route(mode, a, b): path between towns a and b ("road" | "rail" | "sea" | "air") as x,z pairs; empty if none.
	PackedFloat32Array route(const String &mode, int64_t a, int64_t b) const;
	// path on the road or rail graph between two lattice nodes (empty if none)
	// ignore_wx: the planner's ordinary route does not steer around the weather (BLK_NOWX)
	PackedFloat32Array node_path(int64_t a, int64_t b, bool rail, bool ignore_wx = false) const;
	// flight path between two points, around a closed sky
	PackedFloat32Array air_path(double x0, double z0, double x1, double z1) const;
	// route blocking (incBlk): {wx: PackedByteArray per node (1 road, 2 rail), closed_states: PackedInt32Array,
	//   closed_pairs: PackedInt32Array of a,b pairs, closed_cps: PackedFloat32Array of x,z, sky: PackedInt32Array, ignore_wx: bool}
	void set_blocks(const Dictionary &blocks);
	// state at a world point (bOwn), -1 water / neutral
	// the course change (08r-multi.js): srGrid for "sea"/"air" and srRoad with avoid; zones are x, z, r triples
	PackedFloat64Array sr_grid(const String &mode, double x0, double z0, double x1, double z1, const PackedFloat64Array &zones) const;
// road rules: the road path with the edges (pairs of nodes, both ways) costing mult times more: a detour
	// around them when there is a sensible one, through them when there is not
	PackedFloat32Array node_path_costly(int64_t a, int64_t b, const PackedInt32Array &edges, double mult) const;
		PackedFloat32Array node_path_avoid(int64_t a, int64_t b, const PackedInt32Array &jam_nodes, const PackedFloat64Array &zones) const;
	// does a straight flight cross a closed sky (skyHit)
	bool sky_hit(double x0, double z0, double x1, double z1) const;
	int64_t state_at(double x, double z) const;
	// continent of every state (coCont): states whose land touches share a continent id (a state index)
	PackedInt32Array continents() const;
	// coastlines (a == 0) and state borders as polylines: Array of {a, b, p: PackedFloat32Array}
	Array lines() const;
	// border crossings along a path (bCrossings): Array of {ws, s, x, z, a, b}; s = ws * eco
	Array crossings(const PackedFloat32Array &p, double eco) const;
	// the same along a path of doubles (a course drawn by the player)
	Array crossings64(const PackedFloat64Array &p, double eco) const;
	// position of the game RNG after the states were made (mulberry(seed^0x5bd1e995) state), for the game logic
	int64_t states_rng_state() const { return int64_t(states_rng_); }

	// Map shader textures for the last generated world, ready for Image.create_from_data():
	//   terrain: RGBAH with mipmaps (MW x MH) — coast/height, lattice diagonal, lighting, noise
	//   border:  RH with mipmaps (2MW x 2MH) — distance to a state border
	//   states:  R8 (2MW x 2MH) — state id + 1 (121 neutral), grown into the sea
	// Mipmaps are 2x2 box averages like the HTML version builds them.
	// lite (the map editor): only what the shader reads, the terrain without mipmaps (terrain_mips false)
	Dictionary build_textures(bool lite = false);

private:
	std::shared_ptr<tr::World> world_;
	std::vector<double> state_pops_;
	uint32_t states_rng_ = 0;
	std::shared_ptr<tr::Board> board_;
	std::shared_ptr<tr::Nav> nav_;
	std::shared_ptr<tr::Blocks> blocks_;
	int64_t seed_ = 0;
	bool fine_roads_ = false;
	int earth_w_ = 0, earth_h_ = 0;
	std::vector<uint8_t> earth_;
	std::vector<int> earth_seeds_;
	std::vector<std::string> earth_names_;
	std::vector<double> earth_pop_, earth_dev_;
};

} // namespace godot
