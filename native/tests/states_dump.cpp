// Writes the generated states as JSON for native/tests/states_compare.py.   states_dump <seed> <out.json>
#include "core/states.h"
#include "core/worldgen.h"
#include <cstdio>
#include <string>
int main(int argc, char **argv) {
	uint32_t seed = argc > 1 ? uint32_t(std::stoul(argv[1])) : 777;
	tr::World w = tr::generate_world(seed, tr::WorldParams());
	auto S = tr::generate_states(seed, w);
	FILE *o = std::fopen(argc > 2 ? argv[2] : "states.json", "w");
	std::fprintf(o, "[");
	for (size_t i = 0; i < S.size(); i++) {
		auto &c = S[i];
		std::fprintf(o, "%s{\"pop\":%.17g,\"name\":\"%s\",\"full\":\"%s\",\"color\":\"%s\",\"dev\":%.17g,\"gdp\":%.17g,\"stability\":%.17g,\"infl\":%.17g,\"unemp\":%.17g,\"tech\":%.17g,\"corr\":%.17g,\"mil\":%.17g,\"leader\":\"%s\",\"age\":%d,\"ideol\":\"%s\",\"trait\":\"%s\",\"electionIn\":%d,\"treasury\":%.17g,\"debt\":%.17g,\"laws\":[",
				i ? "," : "", c.pop, c.name.c_str(), c.full.c_str(), c.color.c_str(), c.dev, c.gdp, c.stability, c.infl, c.unemp, c.tech, c.corr, c.mil, c.leader.c_str(), c.leader_age,
				c.ideol.c_str(), c.trait.c_str(), c.election_in, c.treasury, c.debt);
		for (size_t k = 0; k < c.laws.size(); k++) std::fprintf(o, "%s\"%s\"", k ? "," : "", c.laws[k].c_str());
		std::fprintf(o, "],\"deposit\":[");
		for (size_t k = 0; k < c.deposit.size(); k++) std::fprintf(o, "%s%.17g", k ? "," : "", c.deposit[k]);
		std::fprintf(o, "]}");
	}
	std::fprintf(o, "]");
	std::fclose(o);
}
