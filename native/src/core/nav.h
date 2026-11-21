// Route search on the board: ports of boardPath(), boardSea() (08e-company.js) and incAirPath() /
// the BLK blocking rules of incBlk() (08f-incidents.js). Same heap, same float32 costs, same results.
#pragma once
#include "board.h"
#include "worldgen.h"

#include <cstdint>
#include <set>
#include <vector>

namespace tr {

struct Blocks {
	std::vector<uint8_t> wx;        // per lattice node: 1 road shut by weather, 2 rail shut by weather (empty = none)
	std::set<int> closed_states;    // a closed country: nothing crosses its border
	std::set<int64_t> closed_pairs; // a*1000+b and b*1000+a: border between a and b closed
	std::vector<std::pair<double, double>> closed_cps;   // closed checkpoints (x, z)
	std::set<int> sky;              // states at war: planes fly around
	bool ignore_wx = false;         // the planner's ordinary route ignores the weather (BLK_NOWX)
	bool any() const { return !wx.empty() || !closed_states.empty() || !closed_pairs.empty() || !closed_cps.empty(); }
};

class Nav {
public:
	Nav(const World &w, const Board &b);
	int own_at(double x, double z) const;   // bOwn
	// shortest path on the road (rail=false) or rail graph between two lattice nodes; empty if none
	std::vector<float> path(int a, int b, bool rail, const Blocks *blk) const;
	// sea route between two port towns (index into board towns); empty if none
	std::vector<float> sea(int ta, int tb) const;
	// flight path; straight unless it crosses a closed sky
	std::vector<float> air(double x0, double z0, double x1, double z1, const Blocks *blk) const;
	bool sky_hit(double x0, double z0, double x1, double z1, const std::set<int> &sky) const;

private:
	const World &w_;
	const Board &b_;
	std::vector<int> nown_;         // state per lattice node
	std::vector<uint8_t> water_;    // water cell per lattice square (boardSea)
	bool blocked(int n, int m, bool rail, const Blocks &blk) const;
};

} // namespace tr
