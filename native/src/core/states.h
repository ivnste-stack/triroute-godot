// States' starting characteristics: port of makeCountry() and the colour assignment in startBoard()
// (legacy/src/06-sim.js, 08e-company.js). Every RNG call of the original is repeated in order, so names,
// populations, development, stability and colours match the HTML version for the same seed.
#pragma once
#include "worldgen.h"

#include <cstdint>
#include <string>
#include <vector>

namespace tr {

struct Flag {
	int cols[4] = {0, 0, 0, 0};   // indices into FLAGCOL after the shuffle (a, b, d, e)
	int type = 0;                 // 0..8 layout
	int emblem = -1;              // -1 none, 0 star, 1 crescent, 2 diamond
};

struct State {
	int id = 0;
	std::string name, full;
	std::string ideol, gov, title, trait;
	double pop = 0, dev = 0, gdp = 0;
	double treasury = 0, debt = 0;
	double stability = 0, infl = 0, unemp = 0, tech = 0, corr = 0, mil = 0;
	std::string leader;
	int leader_age = 0;
	int election_in = 0;
	std::vector<double> budget, quality, mood, deposit;
	std::vector<std::string> laws;
	std::string color;            // #rrggbb
	Flag flag;
};

// R = mulberry(seed ^ 0x5bd1e995), then makeCountry for every state and the colours.
// rng_state receives the RNG position afterwards (the game continues from it in the HTML version).
std::vector<State> generate_states(uint32_t seed, const World &w, uint32_t *rng_state = nullptr);

} // namespace tr
