// Godot binding of the world generator: TRWorldGen.generate(seed, states) -> Dictionary.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

#include <memory>

namespace tr { struct World; }

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
	Dictionary generate_board(const PackedFloat64Array &state_pops);

	// Map shader textures for the last generated world, ready for Image.create_from_data():
	//   terrain: RGBAH with mipmaps (MW x MH) — coast/height, lattice diagonal, lighting, noise
	//   border:  RH with mipmaps (2MW x 2MH) — distance to a state border
	//   states:  R8 (2MW x 2MH) — state id + 1 (121 neutral), grown into the sea
	// Mipmaps are 2x2 box averages like the HTML version builds them.
	Dictionary build_textures();

private:
	std::shared_ptr<tr::World> world_;
	int64_t seed_ = 0;
};

} // namespace godot
