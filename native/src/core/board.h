// Board generator: towns, roads, railways, ports, airports and border checkpoints.
// Port of boardGen() and boardRoads() (with roadWeb, boardPorts, boardCheckpoints, bCrossings) from
// legacy/src/08e-company.js — default road generator (the test "roadGab" generator is not ported).
// Same seed and the same world give the same board as the HTML version.
#pragma once
#include "worldgen.h"

#include <cstdint>
#include <string>
#include <vector>

namespace tr {

struct Town {
	double x = 0, z = 0;          // world coordinates
	int node = 0;                 // board lattice node
	std::string type;             // cap | big | city | town | vil
	double pop = 0;               // millions
	int cid = 0;                  // state
	std::string name;
	bool port = false;
	int wc_i = -1, wc_j = -1;     // water cell next to the port
	bool air_ov = false;          // forced airport (tiny island without a port)
	int port_ov = -1;             // -1 unset, 1 forced port (tiny island)
	bool extra = false;           // added to give a small state its minimum of settlements
};

struct Polyline {
	double lv = 0;                // road level: 3 motorway, 2 road between towns, 1.5 village road, 1 local road
	std::vector<float> p;         // x,z pairs (Float32Array in the original)
};

struct Checkpoint {
	double x, z;
	int a, b;                     // from state, to state
	bool rail;
	double dx = 0, dz = 0;        // where it is drawn: on the border line itself (x, z: on the pixel raster)
};

struct Board {
	int nx = 0, nz = 0;           // lattice nodes (step 0.125 world units)
	double st = .125;
	bool fine = false;            // the test road net: nodes every 0.0625 (each lattice square in 4, both diagonals)
	double wx = 0, wz = 0;        // world size
	std::vector<Town> towns;
	std::vector<uint8_t> bits, rbits;   // 8 direction bits per node: road / rail graph
	std::vector<int> comp;              // land component per node (-1 water)
	std::vector<int> csz;               // size of every component
	std::vector<Polyline> hw;           // roads
	std::vector<std::vector<float>> rail;
	std::vector<Checkpoint> cps;
};

static const int TINY_ISL = 40;

// border crossings along a polyline (bCrossings): {ws, s = ws*eco, x, z, a = from state, b = to state}
struct Crossing { double ws, s, x, z; int a, b; };
std::vector<Crossing> board_crossings(const World &w, const Board &b, const std::vector<float> &pts, double eco);
std::vector<Crossing> board_crossings(const World &w, const Board &b, const std::vector<double> &pts, double eco);

// the roads and railways drawn in the map editor
struct BoardNet {
	std::vector<Polyline> hw;
	std::vector<std::vector<float>> rail;
};

// state_pop: population of every state (G.C[i].pop in the HTML version, millions).
// fine: the test road net (a node grid twice as dense, denser roads, more alternative ways between towns).
Board generate_board(uint32_t seed, const World &w, const std::vector<double> &state_pop, bool fine = false);

// The map editor's board: the given towns (snapped to their lattice nodes, the state taken from the land
// around them, a town in the sea dropped; pop <= 0 is drawn by type), the drawn net or (net == nullptr)
// roads and railways generated as usual; then ports, airports and checkpoints.
Board generate_board_given(uint32_t seed, const World &w, const std::vector<double> &state_pop, bool fine, const std::vector<Town> &towns,
		const BoardNet *net);

// The map editor's road: lattice nodes from a to b over land (the board lattice of the world, fine or not);
// empty when the sea is in the way.
std::vector<int> edit_path(const World &w, bool fine, int a, int b);

} // namespace tr
