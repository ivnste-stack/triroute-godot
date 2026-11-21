// World generator: port of genWorld() (legacy/src/04-map.js) for the logistics board
// (options big:true, tri:true on the square lattice; no "dom" or "earth" variants).
// Same seed -> the same world as the HTML version, bit for bit (checked by native/tests/worldgen_test.cpp).
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace tr {

struct WorldParams {
	int mw = 1800, mh = 1200;   // texture size (WX*80, WZ*80)
	int tri_s = 10;             // lattice square in texture pixels
	int n = 26;                 // number of states to seed on continents
};

struct Country {
	int idx = 0;
	double area = 0;
	int lx = 0, ly = 0;          // label point (texture pixels)
	int cap_x = 0, cap_y = 0;    // seed point
	std::vector<int> neighbors;
	double land_share = 0;
	bool no_label = false;   // the state has no land left (label point is NaN in the HTML version)
};

struct SeedPt {
	int x, y;
	double m = 0, off = 0;
	double dm[8] = {};
};

struct World {
	WorldParams p;
	std::vector<float> low, low_m;   // half-resolution height / mountains
	std::vector<float> H, Mf;        // height and mountains
	double T = 0, top = 0, bot = 0;  // land threshold
	std::vector<uint8_t> land;
	int land_count = 0;
	std::vector<int8_t> own_grow;    // states after region growing
	std::vector<int8_t> own;         // final owner per texture pixel (-1 sea, 0..n-1 state, >=120 neutral)
	int sqw = 0, sqh = 0;
	std::vector<uint8_t> sqd;        // lattice: diagonal per square
	std::vector<int16_t> sql;        // lattice: owner of each half
	std::vector<SeedPt> seeds;
	std::vector<Country> countries;
	uint32_t seed = 0;
	// render data (build_render_data): what the HTML version uploads to the map shader
	std::vector<float> tf;           // MW*MH*4: coast/height, lattice diagonal, lighting, noise
	std::vector<float> hb;           // (2MW)*(2MH): distance to a state border (pixels of the 2x grid)
	std::vector<uint8_t> hid;        // (2MW)*(2MH): state id + 1 on the 2x grid (121 neutral, 0 sea), grown into the sea
};

static const int NEU = 120;

// Generates the world. The HTML version takes the same steps in the same order, so the RNG stays in step.
World generate_world(uint32_t seed, const WorldParams &p);

// Fills tf / hb / hid exactly like the end of genWorld() (tri lattice branch).
void build_render_data(World &w);

} // namespace tr
