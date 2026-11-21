// Generates world + board for a seed and writes the board as JSON (compared with legacy/tests/boardref.js
// output by native/tests/board_compare.py).
//   board_dump <seed> <pops.txt: one state population per line> <out.json>
#include "core/board.h"
#include "core/nav.h"
#include "core/worldgen.h"

#include <chrono>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

static std::string esc(const std::string &s) { return "\"" + s + "\""; }

int main(int argc, char **argv) {
	uint32_t seed = argc > 1 ? uint32_t(std::stoul(argv[1])) : 777;
	std::vector<double> pops;
	{
		std::ifstream f(argc > 2 ? argv[2] : "pops.txt");
		double v;
		while (f >> v) pops.push_back(v);
	}
	auto t0 = std::chrono::steady_clock::now();
	tr::World w = tr::generate_world(seed, tr::WorldParams());
	auto t1 = std::chrono::steady_clock::now();
	tr::Board B = tr::generate_board(seed, w, pops);
	auto t2 = std::chrono::steady_clock::now();
	std::fprintf(stderr, "world %.0f ms, board %.0f ms: %zu towns, %zu roads, %zu railways, %zu checkpoints\n",
			std::chrono::duration<double, std::milli>(t1 - t0).count(), std::chrono::duration<double, std::milli>(t2 - t1).count(),
			B.towns.size(), B.hw.size(), B.rail.size(), B.cps.size());
	FILE *o = std::fopen(argc > 3 ? argv[3] : "board_cpp.json", "w");
	std::fprintf(o, "{\"nx\":%d,\"nz\":%d,\"towns\":[", B.nx, B.nz);
	for (size_t i = 0; i < B.towns.size(); i++) {
		auto &t = B.towns[i];
		std::fprintf(o, "%s{\"x\":%.17g,\"z\":%.17g,\"node\":%d,\"type\":%s,\"pop\":%.17g,\"cid\":%d,\"name\":%s,\"port\":%s,\"wc\":%s,\"airOv\":%s,\"portOv\":%s,\"extra\":%s}",
				i ? "," : "", t.x, t.z, t.node, esc(t.type).c_str(), t.pop, t.cid, esc(t.name).c_str(), t.port ? "true" : "false",
				t.wc_i >= 0 ? ("[" + std::to_string(t.wc_i) + "," + std::to_string(t.wc_j) + "]").c_str() : "null", t.air_ov ? "true" : "false",
				t.port_ov == 1 ? "true" : "null", t.extra ? "true" : "false");
	}
	std::fprintf(o, "],\"hw\":[");
	for (size_t i = 0; i < B.hw.size(); i++) {
		std::fprintf(o, "%s{\"lv\":%.17g,\"p\":[", i ? "," : "", B.hw[i].lv);
		for (size_t k = 0; k < B.hw[i].p.size(); k++) std::fprintf(o, "%s%.9g", k ? "," : "", double(B.hw[i].p[k]));
		std::fprintf(o, "]}");
	}
	std::fprintf(o, "],\"rail\":[");
	for (size_t i = 0; i < B.rail.size(); i++) {
		std::fprintf(o, "%s[", i ? "," : "");
		for (size_t k = 0; k < B.rail[i].size(); k++) std::fprintf(o, "%s%.9g", k ? "," : "", double(B.rail[i][k]));
		std::fprintf(o, "]");
	}
	std::fprintf(o, "],\"cps\":[");
	for (size_t i = 0; i < B.cps.size(); i++)
		std::fprintf(o, "%s{\"x\":%.17g,\"z\":%.17g,\"a\":%d,\"b\":%d,\"rail\":%s}", i ? "," : "", B.cps[i].x, B.cps[i].z, B.cps[i].a, B.cps[i].b, B.cps[i].rail ? "true" : "false");
	std::fprintf(o, "],\"routes\":[");
	{
		tr::Nav nav(w, B);
		auto pr = [&](const std::vector<float> &v) {
			if (v.empty()) { std::fprintf(o, "null"); return; }
			std::fprintf(o, "[");
			for (size_t k = 0; k < v.size(); k++) std::fprintf(o, "%s%.9g", k ? "," : "", double(v[k]));
			std::fprintf(o, "]");
		};
		int n = int(B.towns.size());
		bool first = true;
		for (int i = 0; i < n; i += 3) {
			int j = (i * 13 + 5) % n;
			if (i == j) continue;
			std::fprintf(o, "%s{\"a\":%d,\"b\":%d,\"road\":", first ? "" : ",", i, j);
			first = false;
			pr(nav.path(B.towns[i].node, B.towns[j].node, false, nullptr));
			std::fprintf(o, ",\"rail\":");
			if (B.rbits[B.towns[i].node] && B.rbits[B.towns[j].node]) pr(nav.path(B.towns[i].node, B.towns[j].node, true, nullptr));
			else std::fprintf(o, "null");
			std::fprintf(o, ",\"sea\":");
			if (B.towns[i].wc_i >= 0 && B.towns[j].wc_i >= 0) pr(nav.sea(i, j));
			else std::fprintf(o, "null");
			std::fprintf(o, "}");
		}
	}
	std::fprintf(o, "]}");
	std::fclose(o);
	std::ofstream(std::string(argc > 3 ? argv[3] : "board_cpp.json") + ".bits", std::ios::binary).write((const char *)B.bits.data(), B.bits.size());
	std::ofstream(std::string(argc > 3 ? argv[3] : "board_cpp.json") + ".rbits", std::ios::binary).write((const char *)B.rbits.data(), B.rbits.size());
	std::ofstream(std::string(argc > 3 ? argv[3] : "board_cpp.json") + ".comp", std::ios::binary).write((const char *)B.comp.data(), B.comp.size() * sizeof(int));
	return 0;
}
