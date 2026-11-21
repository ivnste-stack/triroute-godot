// Godot binding of the world generator: TRWorldGen.generate(seed, states) -> Dictionary.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

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
	Dictionary generate(int64_t seed, int64_t states = 26, int64_t mw = 1800, int64_t mh = 1200) const;
};

} // namespace godot
